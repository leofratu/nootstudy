import Foundation
import SwiftData

enum StudyIntensity: String, Codable, CaseIterable {
    case belowAverage = "Below Average"
    case average = "Average"
    case aboveAverage = "Above Average"
    case intensive = "Intensive"

    var emoji: String {
        switch self {
        case .belowAverage: return "🐢"
        case .average: return "📖"
        case .aboveAverage: return "🚀"
        case .intensive: return "🔥"
        }
    }

    var dailyCardSuggestion: Int {
        switch self {
        case .belowAverage: return 10
        case .average: return 20
        case .aboveAverage: return 35
        case .intensive: return 50
        }
    }

    var xpMultiplier: Double {
        switch self {
        case .belowAverage: return 0.8
        case .average: return 1.0
        case .aboveAverage: return 1.2
        case .intensive: return 1.5
        }
    }
}

enum IBYear: String, Codable, CaseIterable {
    case dp1 = "DP1 (Year 1)"
    case dp2 = "DP2 (Year 2)"

    var shortLabel: String {
        switch self {
        case .dp1: return "DP1"
        case .dp2: return "DP2"
        }
    }
}

enum UserRank: String, Codable, CaseIterable {
    case electron = "Electron"
    case atom = "Atom"
    case molecule = "Molecule"
    case cell = "Cell"
    case organism = "Organism"
    case ecosystem = "Ecosystem"
    case universe = "Universe"

    var emoji: String {
        switch self {
        case .electron: return "⚡"
        case .atom: return "⚛️"
        case .molecule: return "🧬"
        case .cell: return "🔬"
        case .organism: return "🌱"
        case .ecosystem: return "🌍"
        case .universe: return "🌌"
        }
    }

    var xpRequired: Int {
        switch self {
        case .electron: return 0
        case .atom: return 100
        case .molecule: return 300
        case .cell: return 600
        case .organism: return 1200
        case .ecosystem: return 2500
        case .universe: return 5000
        }
    }

    var next: UserRank? {
        let all = UserRank.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }
}

@Model
final class UserProfile {
    var id: UUID
    var totalXP: Int
    var currentStreak: Int
    var longestStreak: Int
    var lastStudyDate: Date?
    var streakFreezes: Int
    var rankRaw: String
    var onboardingCompleted: Bool
    var dailyGoal: Int
    var notificationHour: Int
    var notificationMinute: Int
    var weeklyChallenge: String?
    var weeklyChallengeProgress: Int
    var weeklyChallengeTarget: Int

    // Presets
    var studentName: String
    var studyIntensityRaw: String
    var ibYearRaw: String
    var targetIBScore: Int  // out of 45
    var reportLastUploaded: Date?

    var studyIntensity: StudyIntensity {
        get { StudyIntensity(rawValue: studyIntensityRaw) ?? .average }
        set { studyIntensityRaw = newValue.rawValue }
    }

    var ibYear: IBYear {
        get { IBYear(rawValue: ibYearRaw) ?? .dp1 }
        set { ibYearRaw = newValue.rawValue }
    }

    var rank: UserRank {
        get { UserRank(rawValue: rankRaw) ?? .electron }
        set { rankRaw = newValue.rawValue }
    }

    var progressToNextRank: Double {
        guard let next = rank.next else { return 1.0 }
        let currentMin = rank.xpRequired
        let nextMin = next.xpRequired
        return Double(totalXP - currentMin) / Double(nextMin - currentMin)
    }

    func addXP(_ amount: Int) {
        totalXP += amount
        // Auto-rank-up
        let all = UserRank.allCases
        for r in all.reversed() {
            if totalXP >= r.xpRequired {
                rank = r
                break
            }
        }
    }

    func checkAndUpdateStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let last = lastStudyDate {
            let lastDay = calendar.startOfDay(for: last)
            let diff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

            if diff == 1 {
                currentStreak += 1
            } else if diff > 1 {
                if streakFreezes > 0 && diff == 2 {
                    streakFreezes -= 1
                    currentStreak += 1
                } else {
                    currentStreak = 1
                }
            }
            // diff == 0 means already studied today
        } else {
            currentStreak = 1
        }

        longestStreak = max(longestStreak, currentStreak)
        lastStudyDate = Date()

        // Award streak freeze every 7 days
        if currentStreak > 0 && currentStreak % 7 == 0 {
            streakFreezes += 1
        }
    }

    /// Apply preset: set rank and XP based on reported average grade & study intensity
    func applyPreset() {
        // Set daily goal from study intensity
        dailyGoal = studyIntensity.dailyCardSuggestion

        // Calculate starting rank from target score
        let scoreRatio = Double(targetIBScore) / 45.0
        if scoreRatio >= 0.9 { rank = .molecule; totalXP = 300 }
        else if scoreRatio >= 0.75 { rank = .atom; totalXP = 150 }
        else { rank = .electron; totalXP = 50 }

        // DP2 students get a head start
        if ibYear == .dp2 {
            totalXP += 100
            // Re-check rank
            let all = UserRank.allCases
            for r in all.reversed() {
                if totalXP >= r.xpRequired { rank = r; break }
            }
        }
    }

    /// Auto-update rank from grades (called by ARIA)
    func autoUpdateFromGrades(averageGrade: Double, totalReviews: Int) {
        // Rank based on grade + consistency combo
        let gradeScore = averageGrade / 7.0  // 0-1
        let consistencyScore = min(Double(totalReviews) / 200.0, 1.0)  // 0-1
        let combined = (gradeScore * 0.6 + consistencyScore * 0.4)

        if combined >= 0.85 { if rank.xpRequired < UserRank.ecosystem.xpRequired { rank = .ecosystem; totalXP = max(totalXP, 2500) } }
        else if combined >= 0.7 { if rank.xpRequired < UserRank.organism.xpRequired { rank = .organism; totalXP = max(totalXP, 1200) } }
        else if combined >= 0.55 { if rank.xpRequired < UserRank.cell.xpRequired { rank = .cell; totalXP = max(totalXP, 600) } }
        else if combined >= 0.4 { if rank.xpRequired < UserRank.molecule.xpRequired { rank = .molecule; totalXP = max(totalXP, 300) } }
    }

    init() {
        self.id = UUID()
        self.totalXP = 0
        self.currentStreak = 0
        self.longestStreak = 0
        self.streakFreezes = 0
        self.rankRaw = UserRank.electron.rawValue
        self.onboardingCompleted = false
        self.dailyGoal = 20
        self.notificationHour = 9
        self.notificationMinute = 0
        self.weeklyChallengeProgress = 0
        self.weeklyChallengeTarget = 20
        self.studentName = ""
        self.studyIntensityRaw = StudyIntensity.average.rawValue
        self.ibYearRaw = IBYear.dp1.rawValue
        self.targetIBScore = 30
    }
}
