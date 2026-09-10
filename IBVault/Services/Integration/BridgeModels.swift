import Foundation

/// Plain Sendable value types for the bridge. Router must be a pure function
/// `(BridgeRequest) -> BridgeResponse` so it is unit-testable without a socket.
nonisolated struct BridgeRequest: Sendable {
    let method: String
    let path: String
    let queryItems: [String: String]
    let headers: [String: String]
    let body: Data?

    /// Lowercased header lookup.
    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    var bearerToken: String? {
        header("authorization")
    }
}

nonisolated struct BridgeResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    init(statusCode: Int, headers: [String: String] = [:], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    init(json: Any, statusCode: Int, headers: [String: String] = [:]) {
        let dict = json as? [String: Any]
        let data = (try? JSONSerialization.data(withJSONObject: dict ?? [:], options: [])) ?? Data()
        var hdrs = headers
        hdrs["content-type"] = "application/json"
        hdrs["content-length"] = "\(data.count)"
        self.statusCode = statusCode
        self.headers = hdrs
        self.body = data
    }

    static func json(_ object: [String: Any], status: Int) -> BridgeResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data()
        return BridgeResponse(statusCode: status, headers: ["content-type": "application/json", "content-length": "\(data.count)"], body: data)
    }

    static func jsonData(_ data: Data, status: Int) -> BridgeResponse {
        BridgeResponse(statusCode: status, headers: ["content-type": "application/json", "content-length": "\(data.count)"], body: data)
    }

    static func error(code: String, message: String, status: Int) -> BridgeResponse {
        json(["error": ["code": code, "message": message]], status: status)
    }
}

// Helper to encode arbitrary Encodable without type erasure
private struct EncodableBox: Encodable {
    let value: Any
    init(_ value: Any) { self.value = value }
    func encode(to encoder: any Encoder) throws {
        // Not used; stub
    }
}
