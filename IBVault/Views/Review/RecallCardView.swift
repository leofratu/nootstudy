import SwiftUI

/// The same answer interaction is used by scheduled review and free practice.
struct RecallCardView: View {
    let card: StudyCard
    @Binding var revealed: Bool
    var onAnswer: (Bool) -> Void = { _ in }
    @State private var selectedChoice: String?
    @State private var choiceOrder: [String] = []
    @State private var showHint = false

    private var validChoices: [String]? {
        guard card.cardStyle == .multipleChoice else { return nil }
        return CardGeneratorService.validatedChoices(back: card.back, choices: card.choices)
    }

    private var prompt: String {
        CardRecallPresentation.prompt(front: card.front, style: card.cardStyle, revealed: revealed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label(card.cardStyle.label.uppercased(), systemImage: card.cardStyle.symbol)
                    .font(IBTypography.captionBold).tracking(1)
                    .foregroundStyle(IBColors.accent)
                Spacer()
                StudioPill(title: card.difficulty.rawValue)
            }
            Text(card.topicName).font(IBTypography.caption).foregroundStyle(IBColors.inkSecondary)
            FormattedMessageContent(text: prompt)
                .font(.custom("Georgia", size: 25))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let choices = validChoices {
                VStack(spacing: 10) {
                    ForEach(Array((choiceOrder.isEmpty ? choices : choiceOrder).enumerated()), id: \.offset) { index, choice in
                        choiceButton(choice, index: index)
                    }
                    if !revealed {
                        Button("Check answer") {
                            guard let selectedChoice else { return }
                            onAnswer(CardRecallPresentation.isCorrect(selectedChoice, answer: card.back))
                            revealed = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(selectedChoice == nil)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            } else if card.cardStyle == .multipleChoice {
                Label("This card has incomplete options. You can still reveal its answer.", systemImage: "exclamationmark.triangle")
                    .font(IBTypography.caption).foregroundStyle(IBColors.coral)
            }
            if revealed {
                Divider()
                if let selectedChoice {
                    Label(CardRecallPresentation.isCorrect(selectedChoice, answer: card.back) ? "Correct" : "Not quite — review the answer below",
                          systemImage: CardRecallPresentation.isCorrect(selectedChoice, answer: card.back) ? "checkmark.circle.fill" : "xmark.circle")
                        .font(IBTypography.headline)
                        .foregroundStyle(CardRecallPresentation.isCorrect(selectedChoice, answer: card.back) ? IBColors.success : IBColors.coral)
                }
                Text("ANSWER").font(IBTypography.captionBold).tracking(1).foregroundStyle(IBColors.accent)
                FormattedMessageContent(text: card.back).textSelection(.enabled)
                if let explanation = BiologyStudyService.explanation(for: card) {
                    Text(explanation).font(.callout).foregroundStyle(IBColors.inkSecondary).textSelection(.enabled)
                }
                if let url = card.sourceURL, let title = card.sourceTitle {
                    Link(destination: url) { Label(title, systemImage: "arrow.up.right") }
                        .font(IBTypography.caption)
                }
            } else if let hint = card.hint, !hint.isEmpty {
                if showHint {
                    Text(hint).font(IBTypography.body).foregroundStyle(IBColors.inkSecondary)
                } else {
                    Button("Show hint") { showHint = true }.buttonStyle(.borderless)
                }
            }
        }
        .foregroundStyle(IBColors.ink)
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
        .surfaceCard()
        .onAppear { resetChoices() }
        .onChange(of: card.id) { _, _ in resetChoices() }
        .onChange(of: revealed) { _, value in if !value { resetChoices() } }
    }

    private func resetChoices() {
        selectedChoice = nil
        showHint = false
        choiceOrder = (validChoices ?? []).shuffled()
    }

    private func choiceButton(_ choice: String, index: Int) -> some View {
        let correct = CardRecallPresentation.isCorrect(choice, answer: card.back)
        let selected = selectedChoice == choice
        let tint = revealed && correct ? IBColors.success : revealed && selected ? IBColors.coral : selected ? IBColors.accent : IBColors.inkSecondary
        return Button {
            selectedChoice = choice
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Text(String(UnicodeScalar(65 + index)!)).font(IBTypography.mono)
                    .frame(width: 22, height: 22)
                Text(choice).font(IBTypography.body).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                if revealed && (correct || selected) {
                    Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                } else {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                }
            }
            .foregroundStyle(tint)
            .padding(16)
            .background((revealed && correct) || selected ? IBColors.highlight : IBColors.canvas, in: RoundedRectangle(cornerRadius: IBRadius.md))
            .overlay(RoundedRectangle(cornerRadius: IBRadius.md).stroke(tint, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(revealed)
        .accessibilityLabel("Option \(index + 1): \(choice)")
        .accessibilityValue(revealed && correct ? "Correct answer" : selected ? "Selected" : "")
    }
}

nonisolated enum CardRecallPresentation {
    static func prompt(front: String, style: CardStyle, revealed: Bool) -> String {
        guard style == .cloze else { return front }
        return front.replacingOccurrences(of: #"\{\{c\d+::(.*?)(?:::[^}]+)?\}\}"#,
                                         with: revealed ? "$1" : "______",
                                         options: .regularExpression)
    }

    static func isCorrect(_ choice: String, answer: String) -> Bool {
        choice.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(answer.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}
