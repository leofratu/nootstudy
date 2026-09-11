import Foundation
import SwiftData

enum BridgeState: Sendable, Equatable {
    case stopped
    case running(port: Int)
    case failed(String)
}

@MainActor
@Observable
final class IntegrationBridgeController {
    private(set) var state: BridgeState = .stopped
    let container: ModelContainer
    private var server: LocalBridgeServer?

    init(container: ModelContainer) {
        self.container = container
    }

    func start() {
        guard case .stopped = state else { return }
        guard BridgeAuthService.isEnabled else {
            state = .stopped
            return
        }
        let server = LocalBridgeServer(container: container)
        do {
            let port = try server.start()
            self.server = server
            state = .running(port: port)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        server?.stop()
        server = nil
        state = .stopped
    }

    func regenerateToken() {
        _ = BridgeAuthService.regenerateToken()
    }

    var currentPort: Int? {
        if case .running(let port) = state { return port }
        return nil
    }

    var token: String {
        BridgeAuthService.token()
    }

    var isEnabled: Bool {
        get { BridgeAuthService.isEnabled }
        set {
            BridgeAuthService.isEnabled = newValue
            if newValue {
                start()
            } else {
                stop()
            }
        }
    }

    func recentRequests() -> [LocalBridgeServer.RequestLog] {
        guard let server else { return [] }
        return server.recentRequests()
    }
}
