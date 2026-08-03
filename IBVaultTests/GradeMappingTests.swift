import Testing
import Foundation
@testable import IBVault

@Suite("Grade IB Score Mapping")
struct GradeMappingTests {

    @Test("ibScore maps normalized scores at the exact boundaries")
    func ibScoreBoundaries() {
        #expect(Grade.ibScore(fromNormalized: 0.19) == 1)
        #expect(Grade.ibScore(fromNormalized: 0.20) == 2)
        #expect(Grade.ibScore(fromNormalized: 0.34) == 2)
        #expect(Grade.ibScore(fromNormalized: 0.35) == 3)
        #expect(Grade.ibScore(fromNormalized: 0.49) == 3)
        #expect(Grade.ibScore(fromNormalized: 0.50) == 4)
        #expect(Grade.ibScore(fromNormalized: 0.61) == 4)
        #expect(Grade.ibScore(fromNormalized: 0.62) == 5)
        #expect(Grade.ibScore(fromNormalized: 0.74) == 5)
        #expect(Grade.ibScore(fromNormalized: 0.75) == 6)
        #expect(Grade.ibScore(fromNormalized: 0.87) == 6)
        #expect(Grade.ibScore(fromNormalized: 0.88) == 7)
        #expect(Grade.ibScore(fromNormalized: 0.89) == 7)
        #expect(Grade.ibScore(fromNormalized: 1.0) == 7)
    }

    @Test("ibScore clamps out-of-range input before mapping")
    func ibScoreClampsOutOfRange() {
        #expect(Grade.ibScore(fromNormalized: -0.5) == 1)
        #expect(Grade.ibScore(fromNormalized: 1.5) == 7)
    }

    @Test("Points-based grades resolve through the same normalized mapping")
    func pointsResolveThroughNormalizedMapping() {
        let fromPoints = Grade(component: "Paper 1", score: 1, achievedPoints: 17, maxPoints: 20)

        #expect(fromPoints.normalizedScore == 17.0 / 20.0)
        #expect(fromPoints.score == Grade.ibScore(fromNormalized: 17.0 / 20.0))
        #expect(fromPoints.resolvedIBScore == 6)
    }

    @Test("Score-based grades report their score directly")
    func scoreBasedGradesReportScore() {
        let grade = Grade(component: "Paper 1", score: 6)

        #expect(grade.normalizedScore == 6.0 / 7.0)
        #expect(grade.resolvedIBScore == 6)
    }
}
