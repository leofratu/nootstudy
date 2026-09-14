import SwiftUI

struct CardStudioOptionsView: View {
    @Binding var options: CardGenerationOptions
    var showsCount = true
    var compact = false
    var showsStyle = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 24) {
            if showsStyle {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Format").font(IBTypography.headline)
                    Picker("Card format", selection: $options.style) {
                        ForEach(CardStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(options.style.summary)
                        .font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                }
            }
            if showsCount {
                HStack {
                    Text("Total cards").font(IBTypography.headline)
                    Spacer()
                    Stepper(value: $options.count, in: 1...50, step: 1) {
                        Text("\(options.count)").monospacedDigit().font(IBTypography.title3)
                            .frame(minWidth: 32)
                    }
                    .fixedSize()
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Difficulty").font(IBTypography.headline)
                Picker("Difficulty", selection: $options.difficulty) {
                    ForEach(CardDifficulty.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack {
                Text("Writing style").font(IBTypography.headline)
                Spacer()
                Picker("Writing style", selection: $options.tone) {
                    ForEach(CardTone.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(maxWidth: 160)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Skills to practise").font(IBTypography.headline)
                    Spacer()
                    if options.cognitiveSkills.isEmpty {
                        Text("Adaptive mix").font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(CardCognitiveSkill.allCases) { skill in
                        StudioSelectionButton(title: skill.rawValue, selected: options.cognitiveSkills.contains(skill)) {
                            if options.cognitiveSkills.contains(skill) {
                                options.cognitiveSkills.removeAll { $0 == skill }
                            } else { options.cognitiveSkills.append(skill) }
                        }
                    }
                }
            }
        }
        .foregroundStyle(IBColors.ink)
    }
}

struct StudioSelectionButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                Text(title).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(selected ? IBColors.accent : IBColors.inkSecondary)
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? IBColors.highlight : IBColors.surface, in: RoundedRectangle(cornerRadius: IBRadius.md))
            .overlay(RoundedRectangle(cornerRadius: IBRadius.md).stroke(selected ? IBColors.accent : IBColors.borderStrong, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }
}

extension CardStyle {
    var symbol: String {
        switch self {
        case .basic: "rectangle.on.rectangle"
        case .cloze: "textformat.abc.dottedunderline"
        case .multipleChoice: "list.bullet.circle"
        }
    }

    var shortDescription: String {
        switch self {
        case .basic: "Question & answer"
        case .cloze: "Fill in the blank"
        case .multipleChoice: "Pick the right answer"
        }
    }
}
