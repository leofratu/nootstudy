import Foundation

/// A fifteen-rank ladder that moves from subatomic scale to the observable universe.
enum Rank: Int, CaseIterable, Codable, Sendable, Comparable {
    case electron = 0
    case atom
    case molecule
    case crystal
    case cell
    case organism
    case ecosystem
    case planet
    case star
    case supernova
    case nebula
    case galaxy
    case galaxyCluster
    case cosmicWeb
    case universe

    var displayName: String {
        switch self {
        case .electron: return "Electron"
        case .atom: return "Atom"
        case .molecule: return "Molecule"
        case .crystal: return "Crystal"
        case .cell: return "Cell"
        case .organism: return "Organism"
        case .ecosystem: return "Ecosystem"
        case .planet: return "Planet"
        case .star: return "Star"
        case .supernova: return "Supernova"
        case .nebula: return "Nebula"
        case .galaxy: return "Galaxy"
        case .galaxyCluster: return "Galaxy Cluster"
        case .cosmicWeb: return "Cosmic Web"
        case .universe: return "Universe"
        }
    }

    /// SF Symbol used for the badge. Replaced by bespoke artwork in a later plan.
    var symbolName: String {
        switch self {
        case .electron: return "bolt.circle"
        case .atom: return "atom"
        case .molecule: return "circle.hexagongrid"
        case .crystal: return "diamond"
        case .cell: return "circle.circle"
        case .organism: return "leaf"
        case .ecosystem: return "globe.europe.africa"
        case .planet: return "circle.dotted.circle"
        case .star: return "star"
        case .supernova: return "sparkles"
        case .nebula: return "cloud"
        case .galaxy: return "hurricane"
        case .galaxyCluster: return "circle.grid.3x3.fill"
        case .cosmicWeb: return "network"
        case .universe: return "globe.americas.fill"
        }
    }

    static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Tier within a rank. Three is the lowest, one the highest.
enum RankTier: Int, CaseIterable, Codable, Sendable, Comparable {
    case three = 0
    case two
    case one

    var numeral: String {
        switch self {
        case .three: return "III"
        case .two: return "II"
        case .one: return "I"
        }
    }

    static func < (lhs: RankTier, rhs: RankTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One of the forty-five positions on the ladder.
struct RankStep: Codable, Sendable, Equatable, Comparable {
    let rank: Rank
    let tier: RankTier

    static let maxOrdinal = Rank.allCases.count * RankTier.allCases.count - 1
    static let stepSize = 1.0 / Double(maxOrdinal)

    /// Guards against binary representation error. `0.87 / 0.03` is
    /// 28.999999999999996, which would floor to the wrong step without this.
    private static let epsilon = 1e-9

    var ordinal: Int { rank.rawValue * RankTier.allCases.count + tier.rawValue }

    var displayName: String { "\(rank.displayName) \(tier.numeral)" }

    init(rank: Rank, tier: RankTier) {
        self.rank = rank
        self.tier = tier
    }

    init(ordinal: Int) {
        let clamped = min(max(ordinal, 0), Self.maxOrdinal)
        let tierCount = RankTier.allCases.count
        self.rank = Rank(rawValue: clamped / tierCount) ?? .electron
        self.tier = RankTier(rawValue: clamped % tierCount) ?? .three
    }

    init(forMastery mastery: Double) {
        let clamped = min(max(mastery, 0), 1)
        let raw = Int((clamped / Self.stepSize) + Self.epsilon)
        self.init(ordinal: min(raw, Self.maxOrdinal))
    }

    /// Mastery at which this step is entered.
    var masteryThreshold: Double { Double(ordinal) * Self.stepSize }

    static func < (lhs: RankStep, rhs: RankStep) -> Bool { lhs.ordinal < rhs.ordinal }
}
