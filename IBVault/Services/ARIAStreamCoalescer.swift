import Foundation

/// Time-based coalescer for streamed text. Emits pending text on a fixed timer
/// (~16-24ms) instead of per-token or character-stride callbacks, keeping
/// MainActor pressure to one timer Task. Mirrors ARIAService streaming contract:
/// - N chunks within one interval coalesce into a single callback emitting the
///   latest accumulated text.
/// - Final flush emits the tail exactly once.
/// - Cancellation stops further emissions.
@MainActor
final class ARIAStreamCoalescer {
    private let interval: TimeInterval
    private let onEmit: (String) -> Void
    private var pending: String?
    private var task: Task<Void, Never>?

    init(interval: TimeInterval = 0.02, onEmit: @escaping (String) -> Void) {
        self.interval = interval
        self.onEmit = onEmit
        start()
    }

    func enqueue(_ text: String) {
        pending = text
    }

    func flush(_ text: String) {
        task?.cancel()
        task = nil
        pending = nil
        onEmit(text)
    }

    func cancel() {
        task?.cancel()
        task = nil
        pending = nil
    }

    private func start() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.interval ?? 0.02
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                if let text = self.pending {
                    self.pending = nil
                    self.onEmit(text)
                }
            }
        }
    }
}
