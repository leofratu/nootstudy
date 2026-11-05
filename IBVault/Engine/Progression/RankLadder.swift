import Foundation

/// A twenty-rank ladder that moves from subatomic scale to the observable universe.
/// Declaration order is ladder order. Raw values are what profiles and backups
/// store, so they stay fixed: a new rank takes the next unused number.
nonisolated enum Rank: Int, CaseIterable, Codable, Sendable, Comparable {
    case electron = 0
    case nucleus = 15
    case atom = 1
    case molecule = 2
    case protein = 16
    case crystal = 3
    case cell = 4
    case organism = 5
    case ecosystem = 6
    case moon = 17
    case planet = 7
    case star = 8
    case supernova = 9
    case blackHole = 18
    case nebula = 10
    case galaxy = 11
    case galaxyCluster = 12
    case supercluster = 19
    case cosmicWeb = 13
    case universe = 14

    private static let ladderIndexes = Dictionary(
        uniqueKeysWithValues: allCases.enumerated().map { ($0.element, $0.offset) }
    )

    /// Position on the ladder, independent of the stored raw value.
    var ladderIndex: Int { Self.ladderIndexes[self] ?? 0 }

    var displayName: String {
        switch self {
        case .electron: return "Electron"
        case .nucleus: return "Nucleus"
        case .atom: return "Atom"
        case .molecule: return "Molecule"
        case .protein: return "Protein"
        case .crystal: return "Crystal"
        case .cell: return "Cell"
        case .organism: return "Organism"
        case .ecosystem: return "Ecosystem"
        case .moon: return "Moon"
        case .planet: return "Planet"
        case .star: return "Star"
        case .supernova: return "Supernova"
        case .blackHole: return "Black Hole"
        case .nebula: return "Nebula"
        case .galaxy: return "Galaxy"
        case .galaxyCluster: return "Galaxy Cluster"
        case .supercluster: return "Supercluster"
        case .cosmicWeb: return "Cosmic Web"
        case .universe: return "Universe"
        }
    }

    /// SF Symbol used for the badge. Replaced by bespoke artwork in a later plan.
    var symbolName: String {
        switch self {
        case .electron: return "bolt.circle"
        case .nucleus: return "smallcircle.filled.circle"
        case .atom: return "atom"
        case .molecule: return "circle.hexagongrid"
        case .protein: return "point.3.connected.trianglepath.dotted"
        case .crystal: return "diamond"
        case .cell: return "circle.circle"
        case .organism: return "leaf"
        case .ecosystem: return "globe.europe.africa"
        case .moon: return "moon"
        case .planet: return "circle.dotted.circle"
        case .star: return "star"
        case .supernova: return "sparkles"
        case .blackHole: return "circle.fill"
        case .nebula: return "cloud"
        case .galaxy: return "hurricane"
        case .galaxyCluster: return "circle.grid.3x3.fill"
        case .supercluster: return "square.grid.3x3.fill"
        case .cosmicWeb: return "network"
        case .universe: return "globe.americas.fill"
        }
    }

    static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.ladderIndex < rhs.ladderIndex }
}

/// Tier within a rank. Three is the lowest, one the highest.
nonisolated enum RankTier: Int, CaseIterable, Codable, Sendable, Comparable {
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

/// One of the sixty positions on the ladder.
nonisolated struct RankStep: Codable, Sendable, Equatable, Comparable {
    let rank: Rank
    let tier: RankTier

    static let maxOrdinal = Rank.allCases.count * RankTier.allCases.count - 1
    static let stepSize = 1.0 / Double(maxOrdinal)

    /// Guards against binary representation error. `0.87 / 0.03` is
    /// 28.999999999999996, which would floor to the wrong step without this.
    private static let epsilon = 1e-9

    var ordinal: Int { rank.ladderIndex * RankTier.allCases.count + tier.rawValue }

    var displayName: String { "\(rank.displayName) \(tier.numeral)" }

    init(rank: Rank, tier: RankTier) {
        self.rank = rank
        self.tier = tier
    }

    init(ordinal: Int) {
        let clamped = min(max(ordinal, 0), Self.maxOrdinal)
        let tierCount = RankTier.allCases.count
        self.rank = Rank.allCases[clamped / tierCount]
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
