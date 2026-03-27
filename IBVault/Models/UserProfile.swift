import Foundation
import SwiftData

enum ADHDMedicationType: String, Codable, CaseIterable, Sendable {
    case methylphenidateIR = "Methylphenidate IR (Ritalin)"
    case methylphenidateER = "Methylphenidate ER (Concerta/Ritalin LA)"
    case amphetamineIR = "Amphetamine IR (Adderall)"
    case amphetamineXR = "Amphetamine XR (Adderall XR)"
    case lisdexamfetamine = "Lisdexamfetamine (Vyvanse)"
    case atomoxetine = "Atomoxetine (Strattera)"
    case guanfacine = "Guanfacine (Intuniv)"
    case none = "None"
    
    var displayName: String {
        switch self {
        case .methylphenidateIR: return "Methylphenidate IR"
        case .methylphenidateER: return "Methylphenidate ER"
        case .amphetamineIR: return "Amphetamine IR"
        case .amphetamineXR: return "Amphetamine XR"
        case .lisdexamfetamine: return "Lisdexamfetamine"
        case .atomoxetine: return "Atomoxetine"
        case .guanfacine: return "Guanfacine"
        case .none: return "None"
        }
    }
    
    var brandNames: String {
        switch self {
        case .methylphenidateIR: return "Ritalin, Methylin"
        case .methylphenidateER: return "Concerta, Ritalin LA"
        case .amphetamineIR: return "Adderall, Vyvanse (IR)"
        case .amphetamineXR: return "Adderall XR, Mydayis"
        case .lisdexamfetamine: return "Vyvanse"
        case .atomoxetine: return "Strattera"
        case .guanfacine: return "Intuniv, Tenex"
        case .none: return ""
        }
    }
    
    var typicalDosesMg: [Int] {
        switch self {
        case .methylphenidateIR: return [5, 10, 15, 20]
        case .methylphenidateER: return [18, 27, 36, 54]
        case .amphetamineIR: return [5, 10, 15, 20, 30]
        case .amphetamineXR: return [10, 15, 20, 25, 30]
        case .lisdexamfetamine: return [20, 30, 40, 50, 60, 70]
        case .atomoxetine: return [10, 18, 25, 40, 60, 80, 100]
        case .guanfacine: return [1, 2, 3, 4]
        case .none: return []
        }
    }
    
    var typicalDailyDoses: ClosedRange<Int> {
        switch self {
        case .methylphenidateIR: return 1...3
        case .methylphenidateER: return 1...1
        case .amphetamineIR: return 1...2
        case .amphetamineXR: return 1...1
        case .lisdexamfetamine: return 1...1
        case .atomoxetine: return 1...2
        case .guanfacine: return 1...1
        case .none: return 0...0
        }
    }
    
    var isStimulant: Bool {
        switch self {
        case .methylphenidateIR, .methylphenidateER,
             .amphetamineIR, .amphetamineXR, .lisdexamfetamine:
            return true
        case .atomoxetine, .guanfacine, .none:
            return false
        }
    }
    
    var peakHoursAfterDose: Double {
        switch self {
        case .methylphenidateIR: return 2.0
        case .methylphenidateER: return 6.0
        case .amphetamineIR: return 3.0
        case .amphetamineXR: return 7.0
        case .lisdexamfetamine: return 3.5
        case .atomoxetine: return 2.0
        case .guanfacine: return 5.0
        case .none: return 0
        }
    }
    
    var durationHours: Double {
        switch self {
        case .methylphenidateIR: return 4.0
        case .methylphenidateER: return 12.0
        case .amphetamineIR: return 6.0
        case .amphetamineXR: return 12.0
        case .lisdexamfetamine: return 14.0
        case .atomoxetine: return 24.0
        case .guanfacine: return 24.0
        case .none: return 0
        }
    }
}

enum StudyIntensity: String, Codable, CaseIterable, Sendable {
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

enum IBYear: String, Codable, CaseIterable, Sendable {
    case dp1 = "DP1 (Year 1)"
    case dp2 = "DP2 (Year 2)"
    
    var shortLabel: String {
        switch self {
        case .dp1: return "DP1"
        case .dp2: return "DP2"
        }
    }
}

enum UserRank: String, Codable, CaseIterable, Sendable {
    case electron = "Electron"
    case atom = "Atom"
    case molecule = "Molecule"
    case catalyst = "Catalyst"
    case cell = "Cell"
    case nucleus = "Nucleus"
    case organism = "Organism"
    case ecosystem = "Ecosystem"
    case universe = "Universe"
    case supernova = "Supernova"
    
    var emoji: String {
        switch self {
        case .electron: return "⚡"
        case .atom: return "⚛️"
        case .molecule: return "🧬"
        case .catalyst: return "🔥"
        case .cell: return "🔬"
        case .nucleus: return "💫"
        case .organism: return "🌱"
        case .ecosystem: return "🌍"
        case .universe: return "🌌"
        case .supernova: return "✨"
        }
    }
    
    var xpRequired: Int {
        switch self {
        case .electron: return 0
        case .atom: return 100
        case .molecule: return 300
        case .catalyst: return 500
        case .cell: return 800
        case .nucleus: return 1200
        case .organism: return 1800
        case .ecosystem: return 2800
        case .universe: return 4500
        case .supernova: return 7000
        }
    }
    
    var title: String {
        switch self {
        case .electron: return "Just getting started"
        case .atom: return "Building foundations"
        case .molecule: return "Connecting concepts"
        case .catalyst: return "Accelerating learning"
        case .cell: return "Deep understanding"
        case .nucleus: return "Core mastery"
        case .organism: return "Growing expertise"
        case .ecosystem: return "System thinker"
        case .universe: return "Knowledge master"
        case .supernova: return "IB Legend"
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
    
    var studentName: String
    var studyIntensityRaw: String
    var ibYearRaw: String
    var targetIBScore: Int
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
        } else {
            currentStreak = 1
        }
        
        longestStreak = max(longestStreak, currentStreak)
        lastStudyDate = Date()
        
        if currentStreak > 0 && currentStreak % 7 == 0 {
            streakFreezes += 1
        }
    }
    
    func applyPreset() {
        dailyGoal = studyIntensity.dailyCardSuggestion
        
        let scoreRatio = Double(targetIBScore) / 45.0
        if scoreRatio >= 0.9 { rank = .molecule; totalXP = 300 }
        else if scoreRatio >= 0.75 { rank = .atom; totalXP = 150 }
        else { rank = .electron; totalXP = 50 }
        
        if ibYear == .dp2 {
            totalXP += 100
            let all = UserRank.allCases
            for r in all.reversed() {
                if totalXP >= r.xpRequired { rank = r; break }
            }
        }
    }
    
    func autoUpdateFromGrades(averageGrade: Double, totalReviews: Int) {
        let gradeScore = averageGrade / 7.0
        let consistencyScore = min(Double(totalReviews) / 200.0, 1.0)
        let combined = (gradeScore * 0.6 + consistencyScore * 0.4)
        
        if combined >= 0.9 { if rank.xpRequired < UserRank.universe.xpRequired { rank = .universe; totalXP = max(totalXP, 4500) } }
        else if combined >= 0.8 { if rank.xpRequired < UserRank.ecosystem.xpRequired { rank = .ecosystem; totalXP = max(totalXP, 2800) } }
        else if combined >= 0.7 { if rank.xpRequired < UserRank.organism.xpRequired { rank = .organism; totalXP = max(totalXP, 1800) } }
        else if combined >= 0.6 { if rank.xpRequired < UserRank.nucleus.xpRequired { rank = .nucleus; totalXP = max(totalXP, 1200) } }
        else if combined >= 0.5 { if rank.xpRequired < UserRank.cell.xpRequired { rank = .cell; totalXP = max(totalXP, 800) } }
        else if combined >= 0.4 { if rank.xpRequired < UserRank.catalyst.xpRequired { rank = .catalyst; totalXP = max(totalXP, 500) } }
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

struct ADHDMedicationSettings: Codable, Sendable {
    var medicationType: ADHDMedicationType
    var doseMg: Int
    var dailyDoses: Int
    var firstDoseHour: Int
    var firstDoseMinute: Int
    var doseIntervalMinutes: Int
    var isEnabled: Bool
    
    static let `default` = ADHDMedicationSettings(
        medicationType: .none,
        doseMg: 10,
        dailyDoses: 3,
        firstDoseHour: 9,
        firstDoseMinute: 0,
        doseIntervalMinutes: 270,
        isEnabled: false
    )
    
    func saveToDefaults() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(self) {
            UserDefaults.standard.set(data, forKey: "adhdMedicationSettings")
        }
    }
    
    static func loadFromDefaults() -> ADHDMedicationSettings {
        guard let data = UserDefaults.standard.data(forKey: "adhdMedicationSettings"),
              let settings = try? JSONDecoder().decode(ADHDMedicationSettings.self, from: data) else {
            return .default
        }
        return settings
    }
    
    static func clearFromDefaults() {
        UserDefaults.standard.removeObject(forKey: "adhdMedicationSettings")
    }
}

enum ADHDMedicationTracker {
    static func estimatePlasmaLevel(
        at date: Date,
        settings: ADHDMedicationSettings
    ) -> Double {
        guard settings.isEnabled && settings.medicationType != .none else { return 0 }
        
        let calendar = Calendar.current
        let currentMinutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let doseStart = settings.firstDoseHour * 60 + settings.firstDoseMinute
        
        var totalLevel = 0.0
        let doseInterval = settings.doseIntervalMinutes
        let doseCount = settings.dailyDoses
        
        for i in 0..<doseCount {
            let doseTime = doseStart + (i * doseInterval)
            let minutesSinceDose = currentMinutes - doseTime
            
            guard minutesSinceDose >= 0 else { continue }
            
            let hoursSinceDose = Double(minutesSinceDose) / 60.0
            
            let peakHours = settings.medicationType.peakHoursAfterDose
            let duration = settings.medicationType.durationHours
            
            guard hoursSinceDose <= duration else { continue }
            
            let peakLevel = Double(settings.doseMg) * 0.43
            let normalizedTime = hoursSinceDose / duration
            let peakNormalized = peakHours / duration
            
            var relativeLevel: Double
            if hoursSinceDose <= peakHours {
                let t = hoursSinceDose / peakHours
                relativeLevel = t * t * (3 - 2 * t)
            } else {
                let t = (hoursSinceDose - peakHours) / (duration - peakHours)
                relativeLevel = 1.0 - (t * t)
            }
            
            totalLevel += peakLevel * relativeLevel
        }
        
        return totalLevel
    }
    
    static func currentFocusStatus(
        at date: Date,
        settings: ADHDMedicationSettings
    ) -> (level: Double, status: String, colorName: String) {
        let level = estimatePlasmaLevel(at: date, settings: settings)
        
        let therapeuticMin = Double(settings.doseMg) * 0.25
        
        if level >= therapeuticMin * 1.5 {
            return (level, "Peak Focus", "green")
        } else if level >= therapeuticMin {
            return (level, "Effective Range", "blue")
        } else if level > 0 {
            return (level, "Wearing Off", "orange")
        }
        
        return (0, "Not Active", "gray")
    }
    
    static func focusWindows(
        settings: ADHDMedicationSettings
    ) -> [(start: Date, peak: Date, end: Date, label: String)] {
        guard settings.isEnabled && settings.medicationType != .none else { return [] }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var windows: [(start: Date, peak: Date, end: Date, label: String)] = []
        
        for i in 0..<settings.dailyDoses {
            let doseMinutes = settings.firstDoseHour * 60 + settings.firstDoseMinute + (i * settings.doseIntervalMinutes)
            let doseHour = doseMinutes / 60
            let doseMinute = doseMinutes % 60
            
            let peakMinutes = doseMinutes + Int(settings.medicationType.peakHoursAfterDose * 60)
            let endMinutes = doseMinutes + Int(settings.medicationType.durationHours * 60)
            
            let startComponents = DateComponents(hour: doseHour, minute: doseMinute)
            let peakComponents = DateComponents(hour: peakMinutes / 60, minute: peakMinutes % 60)
            let endComponents = DateComponents(hour: min(endMinutes / 60, 23), minute: endMinutes % 60)
            
            if let startDate = calendar.date(bySettingHour: doseHour, minute: doseMinute, second: 0, of: today),
               let peakDate = calendar.date(bySettingHour: peakMinutes / 60, minute: peakMinutes % 60, second: 0, of: today),
               let endDate = calendar.date(bySettingHour: min(endMinutes / 60, 23), minute: endMinutes % 60, second: 0, of: today) {
                windows.append((
                    start: startDate,
                    peak: peakDate,
                    end: endDate,
                    label: "Dose \(i + 1)"
                ))
            }
        }
        
        return windows
    }
}