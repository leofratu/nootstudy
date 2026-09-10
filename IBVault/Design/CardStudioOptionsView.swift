import SwiftUI

struct CardStudioOptionsView: View {
    @Binding var options: CardGenerationOptions
    var showsCount: Bool = true
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            // Style
            VStack(alignment: .leading, spacing: 6) {
                Label("Card style", systemImage: "rectangle.on.rectangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IBColors.secondaryText)
                Picker("Style", selection: $options.style) {
                    ForEach(CardStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .help(options.style.summary)
                Text(options.style.summary)
                    .font(.caption2)
                    .foregroundStyle(IBColors.tertiaryText)
            }

            // Tone
            VStack(alignment: .leading, spacing: 6) {
                Label("Tone", systemImage: "text.bubble")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IBColors.secondaryText)
                Picker("Tone", selection: $options.tone) {
                    ForEach(CardTone.allCases) { tone in
                        Text(tone.label).tag(tone)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Difficulty
            VStack(alignment: .leading, spacing: 6) {
                Label("Difficulty", systemImage: "chart.bar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IBColors.secondaryText)
                Picker("Difficulty", selection: $options.difficulty) {
                    ForEach(CardDifficulty.allCases) { diff in
                        Text(diff.rawValue).tag(diff)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Cognitive skills multi-select chips
            VStack(alignment: .leading, spacing: 6) {
                Label("Cognitive skills", systemImage: "brain.head.profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IBColors.secondaryText)
                Text("Tap to select multiple. Leave empty for adaptive mix.")
                    .font(.caption2)
                    .foregroundStyle(IBColors.tertiaryText)
                FlowLayout(spacing: 6) {
                    ForEach(CardCognitiveSkill.allCases) { skill in
                        SkillChip(
                            skill: skill,
                            isSelected: options.cognitiveSkills.contains(skill),
                            action: {
                                if options.cognitiveSkills.contains(skill) {
                                    options.cognitiveSkills.removeAll { $0 == skill }
                                } else {
                                    options.cognitiveSkills.append(skill)
                                }
                                IBHaptics.light()
                            }
                        )
                    }
                }
            }

            if showsCount {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Card count", systemImage: "number")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(IBColors.secondaryText)
                    HStack(spacing: 10) {
                        Text("\(options.count)")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .frame(width: 30)
                        Slider(
                            value: Binding(
                                get: { Double(options.count) },
                                set: { options.count = min(max(Int($0.rounded()), 1), 50) }
                            ),
                            in: 1...50,
                            step: 1
                        )
                        Stepper("", value: Binding(
                            get: { options.count },
                            set: { options.count = min(max($0, 1), 50) }
                        ), in: 1...50)
                        .labelsHidden()
                        .fixedSize()
                    }
                    Text("1 to 50 cards per batch")
                        .font(.caption2)
                        .foregroundStyle(IBColors.tertiaryText)
                }
            }

            // Internal tools toggle — prominent
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $options.useInternalTools) {
                    HStack(spacing: 6) {
                        Image(systemName: "internaldrive")
                            .foregroundStyle(IBColors.electricBlue)
                        Text("Let ARIA use internal tools")
                            .font(.callout.weight(.semibold))
                    }
                }
                .toggleStyle(.switch)
                .tint(IBColors.electricBlue)

                Text("ARIA looks up your curriculum, checks duplicates, and schedules; the app enforces these steps.")
                    .font(.caption)
                    .foregroundStyle(IBColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(IBColors.electricBlue.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(IBColors.electricBlue.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(IBColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(IBColors.cardBorder, lineWidth: 1)
                )
        )
    }
}

private struct SkillChip: View {
    let skill: CardCognitiveSkill
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(skill.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : IBColors.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? IBColors.electricBlue : IBColors.canvas)
                        .overlay(
                            Capsule().stroke(isSelected ? IBColors.electricBlue : IBColors.cardBorder, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(skill.rawValue)
    }
}

// Simple flow layout for chips
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        let maxWidth = bounds.width
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            if x > maxWidth { x = bounds.minX; y += rowHeight + spacing }
        }
    }
}

#Preview {
    CardStudioOptionsView(options: .constant(.default))
        .frame(width: 400)
        .padding()
}
