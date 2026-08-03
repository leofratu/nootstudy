import Testing
import Foundation
@testable import IBVault

@Suite("JSONLineBuffer Line Extraction")
struct JSONLineBufferTests {

    @Test("Complete lines are extracted across chunk boundaries")
    func extractsCompleteLinesAcrossChunks() {
        let buffer = AIProviderService.JSONLineBuffer()

        let first = buffer.append(Data(#"{"a":1}"#.utf8))
        #expect(first.isEmpty) // no newline yet

        let second = buffer.append(Data("\n{\"b\":2}\n".utf8))
        #expect(second == [#"{"a":1}"#, #"{"b":2}"#])
    }

    @Test("A trailing partial line is retained until the next chunk or flush")
    func trailingPartialLineIsRetained() {
        let buffer = AIProviderService.JSONLineBuffer()

        let first = buffer.append(Data("{\"c\":3}\n{\"d\":".utf8))
        #expect(first == [#"{"c":3}"#])

        let second = buffer.append(Data("4}\n".utf8))
        #expect(second == [#"{"d":4}"#])

        #expect(buffer.flush().isEmpty)
    }

    @Test("Whitespace-only lines are skipped, not emitted")
    func skipsWhitespaceLines() {
        let buffer = AIProviderService.JSONLineBuffer()

        let lines = buffer.append(Data("{\"e\":5}\n   \n\n{\"f\":6}\n".utf8))
        #expect(lines == [#"{"e":5}"#, #"{"f":6}"#])
    }

    @Test("flush emits a buffered non-newline-terminated line once")
    func flushEmitsResidualLine() {
        let buffer = AIProviderService.JSONLineBuffer()

        let lines = buffer.append(Data("{\"g\":7}\n{\"h\":8}".utf8))
        #expect(lines == [#"{"g":7}"#])

        #expect(buffer.flush() == [#"{"h":8}"#])
        #expect(buffer.flush().isEmpty)
    }

    @Test("A large burst of lines is extracted without losing any")
    func extractsLargeBurstWithoutLoss() {
        let buffer = AIProviderService.JSONLineBuffer()
        let expected = (0..<500).map { "{\"n\":\($0)}" }
        let payload = expected.joined(separator: "\n") + "\n"

        let lines = buffer.append(Data(payload.utf8))
        #expect(lines.count == 500)
        #expect(lines == expected)
    }
}
