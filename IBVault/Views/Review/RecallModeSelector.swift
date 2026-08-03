import SwiftUI

// NOTE: Unused. `RecallMode` and `RecallModeSelector` are referenced only
// within this file — the review session hard-codes its flashcard/typing flow
// and never presents this selector. Kept (file removal is out of scope for a
// strict-pass edit) but should not be treated as live UI.

// MARK: - Recall Mode
enum RecallMode: String, CaseIterable {
    case flashcard = "Flashcard"
    case typing = "Type Answer"
    case multipleChoice = "Multiple Choice"

    var icon: String {
        switch self {
        case .flashcard: return "rectangle.on.rectangle"
        case .typing: return "keyboard"
        case .multipleChoice: return "list.bullet.rectangle"
        }
    }
}

// MARK: - Recall Mode Selector
struct RecallModeSelector: View {
    @Binding var selected: RecallMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RecallMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(IBAnimation.snappy) { selected = mode }
                    IBHaptics.soft()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .medium))
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected == mode ? IBColors.electricBlue : Color.clear)
                    )
                    .foregroundStyle(selected == mode ? .white : .secondary)
                }
                .buttonStyle(.plain)
                .animation(IBAnimation.snappy, value: selected)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
