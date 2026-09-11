import Testing
import Foundation
@testable import IBVault

@Suite("ARIA Stream Coalescer Tests")
struct ARIAStreamCoalescerTests {

    @MainActor
    @Test("N chunks within one interval coalesce into a single callback")
    func coalescesWithinInterval() async throws {
        var emissions: [String] = []
        let coalescer = ARIAStreamCoalescer(interval: 0.03) { text in
            emissions.append(text)
        }
        // Enqueue 5 chunks rapidly within 5ms
        for i in 1...5 {
            coalescer.enqueue(String(repeating: "a", count: i * 10))
        }
        // Wait for one interval plus margin
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(emissions.count == 1)
        #expect(emissions.first == String(repeating: "a", count: 50))
        coalescer.cancel()
    }

    @MainActor
    @Test("Final flush emits the tail immediately")
    func finalFlushEmitsTail() async throws {
        var emissions: [String] = []
        let coalescer = ARIAStreamCoalescer(interval: 0.05) { text in
            emissions.append(text)
        }
        coalescer.enqueue("pending tail")
        // Flush should emit immediately without waiting for timer
        coalescer.flush("final tail")
        // Allow any pending timer to fire (should not duplicate)
        try await Task.sleep(nanoseconds: 70_000_000)
        #expect(emissions == ["final tail"])
    }

    @MainActor
    @Test("Cancellation stops emissions")
    func cancellationStopsEmissions() async throws {
        var emissions: [String] = []
        let coalescer = ARIAStreamCoalescer(interval: 0.02) { text in
            emissions.append(text)
        }
        coalescer.enqueue("will be cancelled")
        coalescer.cancel()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(emissions.isEmpty)
    }

    @MainActor
    @Test("Multiple intervals produce multiple emissions")
    func multipleIntervals() async throws {
        var emissions: [String] = []
        let coalescer = ARIAStreamCoalescer(interval: 0.02) { text in
            emissions.append(text)
        }
        coalescer.enqueue("first")
        try await Task.sleep(nanoseconds: 40_000_000)
        coalescer.enqueue("second")
        try await Task.sleep(nanoseconds: 40_000_000)
        #expect(emissions.count == 2)
        #expect(emissions[0] == "first")
        #expect(emissions[1] == "second")
        coalescer.cancel()
    }
}
