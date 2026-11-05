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
    private var isStarting = false

    init(container: ModelContainer) {
        self.container = container
    }

    /// Starts the listener without blocking the main actor. Binds on a
    /// background continuation and publishes the result when ready, so launch
    /// never freezes on port probing.
    func start() {
        guard !isStarting, case .stopped = state else { return }
        guard BridgeAuthService.isEnabled else {
            state = .stopped
            return
        }
        isStarting = true
        let server = LocalBridgeServer(container: container)
        self.server = server
        Task { [weak self] in
            let result: Result<Int, any Error>
            do { result = .success(try await server.start()) }
            catch { result = .failure(error) }
            // A stop during startup already reset state. Close what just bound
            // rather than reporting a server nothing holds any more.
            guard let self, self.server === server else {
                server.stop()
                return
            }
            self.isStarting = false
            switch result {
            case .success(let port): self.state = .running(port: port)
            case .failure(let error): self.state = .failed(error.localizedDescription)
            }
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isStarting = false
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
