// IBVaultTests/XPCalculatorTests.swift
import Testing
import Foundation
@testable import IBVault

@Suite("XP Calculator Tests")
struct XPCalculatorTests {

    @Test("Review XP sums per-card values and applies the intensity multiplier")
    func reviewXPAppliesMultiplier() {
        // good + easy == 10 + 15 == 25, at 1.2x == 30.
        let xp = XPCalculator.xp(forQualities: [.good, .easy], intensity: .aboveAverage)
        #expect(xp == 30)
    }

    @Test("Review XP at average intensity is the raw sum")
    func reviewXPAtAverage() {
        #expect(XPCalculator.xp(forQualities: [.good, .good], intensity: .average) == 20)
    }

    @Test("Review XP of an empty session is zero")
    func reviewXPOfEmptySession() {
        #expect(XPCalculator.xp(forQualities: [], intensity: .intensive) == 0)
    }

    @Test("Study XP awards five points per minute scaled by intensity, rounded down")
    func studyXPPerMinute() {
        #expect(XPCalculator.xp(forStudyMinutes: 50, intensity: .average) == 250)
        #expect(XPCalculator.xp(forStudyMinutes: 50, intensity: .intensive) == 375)
        #expect(XPCalculator.xp(forStudyMinutes: 10.9, intensity: .average) == 54)
    }

    @Test("Negative or zero study minutes never award XP")
    func studyXPNeverNegative() {
        #expect(XPCalculator.xp(forStudyMinutes: -30, intensity: .intensive) == 0)
        #expect(XPCalculator.xp(forStudyMinutes: 0, intensity: .average) == 0)
    }

    @Test("Imported nonfinite or overflowing durations do not trap")
    func malformedImportedDurations() {
        #expect(XPCalculator.xp(forStudyMinutes: .nan, intensity: .average) == 0)
        #expect(XPCalculator.xp(forStudyMinutes: .infinity, intensity: .average) == 0)
        #expect(XPCalculator.xp(forStudyMinutes: .greatestFiniteMagnitude, intensity: .intensive) == 0)
    }

    @Test("Completing a real session earns a bonus, a brief check-in does not")
    func completionBonus() {
        #expect(XPCalculator.completionBonus(forStudyMinutes: 9.9, intensity: .average) == 0)
        #expect(XPCalculator.completionBonus(forStudyMinutes: 10, intensity: .average) == 50)
        #expect(XPCalculator.completionBonus(forStudyMinutes: 60, intensity: .intensive) == 75)
        #expect(XPCalculator.completionBonus(forStudyMinutes: .nan, intensity: .average) == 0)
    }
}
