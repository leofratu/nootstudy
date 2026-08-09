import SwiftUI

struct ProgressHubView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case recommendations = "Next steps"
        case predictions = "Predictions"

        var id: String { rawValue }
    }

    @State private var selectedSection: Section = .overview

    var body: some View {
        VStack(spacing: 0) {
            Picker("Progress view", selection: $selectedSection) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)

            Divider()

            Group {
                switch selectedSection {
                case .overview:
                    AnalyticsView()
                case .recommendations:
                    SmartRecommendationsView()
                case .predictions:
                    PredictiveGradeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(IBColors.canvas)
    }
}
