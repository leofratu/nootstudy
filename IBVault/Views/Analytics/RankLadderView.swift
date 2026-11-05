import SwiftUI

/// Every rank from Electron to Universe, including the ones still ahead, with
/// what it takes to reach each one.
struct RankLadderView: View {
    let achieved: RankStep
    /// Current overall mastery, 0...1. Rank can stay above it after decay.
    let liveMastery: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Overall mastery with the same teaching-hour weighting the progression
    /// engine ranks on, read from its cached per-subject results.
    static func liveMastery(subjects: [Subject], tracks: [SubjectTrack]) -> Double {
        let masteryBySubject = Dictionary(tracks.map { ($0.subjectName, $0.cachedMastery) }, uniquingKeysWith: { first, _ in first })
        let totalWeight = subjects.reduce(0.0) { $0 + SubjectLevel(rawLevel: $1.level).masteryWeight }
        guard totalWeight > 0 else { return 0 }
        return subjects.reduce(0.0) {
            $0 + (masteryBySubject[$1.name] ?? 0) * SubjectLevel(rawLevel: $1.level).masteryWeight
        } / totalWeight
    }

    private var nextStep: RankStep? {
        achieved.ordinal < RankStep.maxOrdinal ? RankStep(ordinal: achieved.ordinal + 1) : nil
    }

    private func percent(_ value: Double) -> Int { Int(ceil(value * 100)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            currentRank
            VStack(alignment: .leading, spacing: 0) {
                // Top of the ladder first, so you look up at what is ahead.
                ForEach(Array(Rank.allCases.reversed()), id: \.rawValue) { rank in
                    rankRow(rank)
                }
            }
            .frame(maxWidth: 620)
        }
    }

    private var currentRank: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: achieved.rank.symbolName)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(IBColors.accent)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text(achieved.displayName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(IBColors.ink)
                if let nextStep {
                    MasteryBar(progress: RankProgress(liveMastery: liveMastery, achieved: achieved).fractionToNextStep, height: 5)
                    Text("Next: \(nextStep.displayName) at \(percent(nextStep.masteryThreshold))% mastery. You are at \(Int(liveMastery * 100))%.")
                        .font(IBTypography.caption)
                        .foregroundStyle(IBColors.inkSecondary)
                } else {
                    Text("The top of the ladder.")
                        .font(IBTypography.caption)
                        .foregroundStyle(IBColors.inkSecondary)
                }
            }
        }
    }

    private func rankRow(_ rank: Rank) -> some View {
        let first = RankStep(rank: rank, tier: .three)
        let isCurrent = achieved.rank == rank
        let isUnlocked = first <= achieved
        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                // The spine joins the ranks into one climb.
                Rectangle()
                    .fill(isUnlocked && rank != achieved.rank ? IBColors.accent.opacity(0.5) : IBColors.border)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .opacity(rank == Rank.allCases.first ? 0 : 1)
                    .offset(y: 16)
                Image(systemName: isUnlocked ? rank.symbolName : "lock.fill")
                    .font(.system(size: isUnlocked ? 13 : 9))
                    .foregroundStyle(isUnlocked ? IBColors.accent : IBColors.inkTertiary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isCurrent ? IBColors.highlight : IBColors.surface))
            }
            .frame(width: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(rank.displayName)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isUnlocked ? IBColors.ink : IBColors.inkSecondary)
                Text(isCurrent ? "You are here" : isUnlocked ? "Reached" : "Unlocks at \(percent(first.masteryThreshold))% mastery")
                    .font(IBTypography.caption)
                    .foregroundStyle(IBColors.inkTertiary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                ForEach(RankTier.allCases, id: \.rawValue) { tier in
                    tierMark(RankStep(rank: rank, tier: tier))
                }
            }
        }
        .frame(height: 42)
        .accessibilityElement(children: .combine)
    }

    private func tierMark(_ step: RankStep) -> some View {
        let reached = step <= achieved
        return Text(step.tier.numeral)
            .font(.system(size: 10, weight: step == achieved ? .bold : .regular).monospacedDigit())
            .foregroundStyle(step == achieved ? IBColors.accent : reached ? IBColors.inkSecondary : IBColors.inkTertiary.opacity(0.7))
            .frame(width: 44, alignment: .trailing)
            .overlay(alignment: .leading) {
                Text("\(percent(step.masteryThreshold))%")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(IBColors.inkTertiary.opacity(reached ? 1 : 0.7))
            }
            .help("\(step.displayName) unlocks at \(percent(step.masteryThreshold))% mastery")
    }
}

/// What each mastery level means, and the studies the signals come from.
struct MasteryLevelsGuideView: View {
    /// How many of the learner's cards sit at each level.
    var counts: [ProficiencyLevel: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(MasteryLevelGuide.all()) { guide in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(guide.level.stageName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(IBColors.ink)
                            Text(guide.requirement)
                                .font(IBTypography.caption)
                                .foregroundStyle(IBColors.inkSecondary)
                            Text(guide.meaning)
                                .font(IBTypography.caption)
                                .foregroundStyle(IBColors.inkTertiary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        if !counts.isEmpty {
                            Text("\(counts[guide.level] ?? 0)")
                                .font(.system(size: 15, weight: .medium).monospacedDigit())
                                .foregroundStyle(IBColors.ink)
                        }
                    }
                    .padding(.vertical, 10)
                    if guide.level != .mastered {
                        Rectangle().fill(IBColors.border).frame(height: 1)
                    }
                }
            }
            Text(ProficiencyConfig.evidenceSummary)
                .font(IBTypography.caption)
                .foregroundStyle(IBColors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                Text("The research")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IBColors.ink)
                ForEach(MasteryLevelGuide.citations) { source in
                    VStack(alignment: .leading, spacing: 1) {
                        if let url = source.url {
                            Link(source.citation, destination: url)
                                .font(IBTypography.caption)
                        } else {
                            Text(source.citation).font(IBTypography.caption)
                        }
                        Text(source.finding)
                            .font(IBTypography.caption)
                            .foregroundStyle(IBColors.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
