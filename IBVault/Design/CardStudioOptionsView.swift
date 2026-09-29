import SwiftUI

struct CardStudioOptionsView: View {
    @Binding var options: CardGenerationOptions
    var showsCount = true
    var compact = false
    var showsStyle = true
    var showsTone = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 24) {
            if showsStyle {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Format").font(IBTypography.headline)
                    Picker("Card format", selection: preference(\.style)) {
                        ForEach(CardStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(options.style.summary)
                        .font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
                }
            }
            if showsCount {
                CardCountControl(count: preference(\.count))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Difficulty").font(IBTypography.headline)
                Picker("Difficulty", selection: preference(\.difficulty)) {
                    ForEach(CardDifficulty.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if showsTone {
                HStack {
                    Text("Writing style").font(IBTypography.headline)
                    Spacer()
                    Picker("Writing style", selection: preference(\.tone)) {
                        ForEach(CardTone.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().frame(maxWidth: 160)
                }
                Text(options.tone.summary)
                    .font(IBTypography.caption)
                    .foregroundStyle(IBColors.inkSecondary)
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

    private func preference<Value>(_ path: WritableKeyPath<CardGenerationOptions, Value>) -> Binding<Value> {
        Binding(get: { options[keyPath: path] }, set: {
            options[keyPath: path] = $0
            options.savePreferences()
        })
    }
}

struct CardCountControl: View {
    @Binding var count: Int

    private var boundedCount: Binding<Int> {
        Binding(get: { count }, set: { count = min(max($0, 1), 50) })
    }

    var body: some View {
        HStack {
            Text("Cards per set").font(IBTypography.headline)
            Spacer()
            TextField("Count", value: boundedCount, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
                .accessibilityLabel("Cards per set")
            Stepper("Cards per set", value: boundedCount, in: 1...50)
                .labelsHidden().fixedSize()
        }
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
