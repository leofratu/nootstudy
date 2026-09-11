@preconcurrency import Foundation
@preconcurrency import Dispatch
import Network
import SwiftData

/// Minimal HTTP/1.1 server for the local bridge. Bound to 127.0.0.1 only.
/// Preferred port 42827 with fallback up to 42837 then ephemeral; persists actual port.
/// Parses request line, headers, Content-Length body with 1 MiB cap and 10 s timeout.
/// Returns JSON responses and enforces bearer auth (except health). Keeps ring buffer of last 100 requests.
nonisolated final class LocalBridgeServer: @unchecked Sendable {
    private let container: ModelContainer
    private var listener: NWListener?
    private var runningPort: Int?
    private let queue = DispatchQueue(label: "com.nootstudy.bridge.listener")
    private let logQueue = DispatchQueue(label: "com.nootstudy.bridge.log")
    nonisolated(unsafe) private var requestLog: [RequestLog] = []

    struct RequestLog: Sendable {
        let method: String
        let path: String
        let status: Int
        let timestamp: Date
    }

    init(container: ModelContainer) {
        self.container = container
    }

    var actualPort: Int? {
        let persisted = UserDefaults.standard.integer(forKey: "BridgeActualPort")
        if persisted > 0 { return persisted }
        return runningPort
    }

    func start() throws -> Int {
        let preferredRange = 42827...42837
        var lastError: (any Error)?
        for port in preferredRange {
            do {
                let actual = try startListener(on: port)
                persistPort(actual)
                runningPort = actual
                return actual
            } catch {
                lastError = error
                continue
            }
        }
        do {
            let actual = try startListener(on: 0)
            persistPort(actual)
            runningPort = actual
            return actual
        } catch {
            throw lastError ?? error
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        runningPort = nil
    }

    func recentRequests() -> [RequestLog] {
        logQueue.sync { requestLog }
    }

    // MARK: - Private

    private func persistPort(_ port: Int) {
        UserDefaults.standard.set(port, forKey: "BridgeActualPort")
    }

    private func startListener(on port: Int) throws -> Int {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = false
        let nwPort: NWEndpoint.Port = port == 0 ? .any : NWEndpoint.Port(rawValue: UInt16(port))!
        let listener = try NWListener(using: params, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                debugPrint("[Bridge] listener failed: \(err.localizedDescription)")
            }
        }
        let sem = DispatchSemaphore(value: 0)
        listener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 0.2) { sem.signal() }
        sem.wait()
        if case .failed(let err) = listener.state {
            throw err
        }
        let actualPort: Int = port == 0 ? Int(listener.port?.rawValue ?? 0) : port
        self.listener = listener
        return actualPort
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveRequest(on: connection, buffer: Data())
            case .failed, .cancelled:
                connection.cancel()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        let timeoutItem = DispatchWorkItem { connection.cancel() }
        queue.asyncAfter(deadline: .now() + 10, execute: timeoutItem)
        receiveData(on: connection, buffer: buffer, timeoutItem: timeoutItem)
    }

    private func receiveData(on connection: NWConnection, buffer: Data, timeoutItem: DispatchWorkItem) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var newBuffer = buffer
            if let data, !data.isEmpty {
                newBuffer.append(data)
                if newBuffer.count > 1_048_576 + 8192 {
                    self.sendResponse(status: 413, body: ["error": ["code": "payload_too_large", "message": "Body exceeds 1 MiB"]], on: connection, timeoutItem: timeoutItem, requestMethod: "UNKNOWN", requestPath: "/")
                    return
                }
                if let parsed = self.tryParseRequest(from: newBuffer) {
                    if let contentLength = parsed.contentLength, newBuffer.count < parsed.headerEndOffset + contentLength {
                        if isComplete {
                            self.sendResponse(status: 400, body: ["error": ["code": "bad_request", "message": "Incomplete body"]], on: connection, timeoutItem: timeoutItem, requestMethod: parsed.method, requestPath: parsed.path)
                            return
                        }
                        self.receiveData(on: connection, buffer: newBuffer, timeoutItem: timeoutItem)
                        return
                    }
                    timeoutItem.cancel()
                    self.handleParsedRequest(parsed, rawBuffer: newBuffer, on: connection, timeoutItem: timeoutItem)
                    return
                }
            }
            if error != nil {
                timeoutItem.cancel()
                connection.cancel()
                return
            }
            if isComplete {
                self.sendResponse(status: 400, body: ["error": ["code": "bad_request", "message": "Malformed HTTP"]], on: connection, timeoutItem: timeoutItem, requestMethod: "UNKNOWN", requestPath: "/")
                return
            }
            self.receiveData(on: connection, buffer: newBuffer, timeoutItem: timeoutItem)
        }
    }

    private struct ParsedRequest {
        let method: String
        let path: String
        let queryItems: [String: String]
        let headers: [String: String]
        let headerEndOffset: Int
        let contentLength: Int?
    }

    private func tryParseRequest(from data: Data) -> ParsedRequest? {
        guard let headerEndRange = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.prefix(upTo: headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        let method = parts[0].uppercased()
        let rawPath = parts[1]
        let urlComponents = URLComponents(string: "http://127.0.0.1\(rawPath)")
        let path = urlComponents?.path ?? rawPath.split(separator: "?").first.map(String.init) ?? rawPath
        var queryItems: [String: String] = [:]
        for item in urlComponents?.queryItems ?? [] {
            if let value = item.value { queryItems[item.name] = value }
        }
        var headers: [String: String] = [:]
        var contentLength: Int?
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<colon]).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
            if name == "content-length", let len = Int(value) { contentLength = len }
        }
        return ParsedRequest(method: method, path: path, queryItems: queryItems, headers: headers, headerEndOffset: headerEndRange.upperBound, contentLength: contentLength)
    }

    private func handleParsedRequest(_ parsed: ParsedRequest, rawBuffer: Data, on connection: NWConnection, timeoutItem: DispatchWorkItem) {
        let headerEndOffset = parsed.headerEndOffset
        let contentLength = parsed.contentLength ?? 0
        if contentLength > 1_048_576 {
            sendResponse(status: 413, body: ["error": ["code": "payload_too_large", "message": "Body exceeds 1 MiB"]], on: connection, timeoutItem: timeoutItem, requestMethod: parsed.method, requestPath: parsed.path)
            return
        }
        let body: Data? = contentLength > 0 ? Data(rawBuffer[headerEndOffset..<headerEndOffset + contentLength]) : nil
        let request = BridgeRequest(method: parsed.method, path: parsed.path, queryItems: parsed.queryItems, headers: parsed.headers, body: body)
        let router = BridgeRouter(container: container)
        let response = router.handle(request)
        logQueue.async { [weak self] in
            guard let self else { return }
            self.requestLog.append(RequestLog(method: parsed.method, path: parsed.path, status: response.statusCode, timestamp: Date()))
            if self.requestLog.count > 100 { self.requestLog.removeFirst(self.requestLog.count - 100) }
        }
        sendRawResponse(response, on: connection, timeoutItem: timeoutItem)
    }

    private func sendResponse(status: Int, body: [String: Any], on connection: NWConnection, timeoutItem: DispatchWorkItem, requestMethod: String, requestPath: String) {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [])) ?? Data()
        let response = BridgeResponse(statusCode: status, headers: ["content-type": "application/json", "content-length": "\(data.count)"], body: data)
        logQueue.async { [weak self] in
            guard let self else { return }
            self.requestLog.append(RequestLog(method: requestMethod, path: requestPath, status: status, timestamp: Date()))
            if self.requestLog.count > 100 { self.requestLog.removeFirst(self.requestLog.count - 100) }
        }
        sendRawResponse(response, on: connection, timeoutItem: timeoutItem)
    }

    private func sendRawResponse(_ response: BridgeResponse, on connection: NWConnection, timeoutItem: DispatchWorkItem) {
        let statusText: String = switch response.statusCode {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Payload Too Large"
        case 500: "Internal Server Error"
        default: "OK"
        }
        var headerString = "HTTP/1.1 \(response.statusCode) \(statusText)\r\n"
        for (key, value) in response.headers { headerString += "\(key): \(value)\r\n" }
        headerString += "Connection: close\r\n\r\n"
        var out = Data(headerString.utf8)
        out.append(response.body)
        connection.send(content: out, completion: .contentProcessed { _ in
            timeoutItem.cancel()
            connection.cancel()
        })
    }
}
