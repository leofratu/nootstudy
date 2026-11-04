import SwiftUI

/// Next steps and predictions have their own sidebar entries, so Progress no
/// longer repeats them behind a second set of tabs.
struct ProgressHubView: View {
    var body: some View {
        AnalyticsView()
            .background(IBColors.canvas)
    }
}
