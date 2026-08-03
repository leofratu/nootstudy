import Foundation
import SwiftData

/// Whether a curriculum unit has been taught in class yet. Set during
/// onboarding calibration, editable afterwards from the subject drill-down.
/// Read by the mastery heatmap and the study planner.
@Model
final class UnitState {
    var id: UUID
    var subjectName: String
    var unitName: String
    var isTaught: Bool

    init(subjectName: String, unitName: String, isTaught: Bool = false) {
        self.id = UUID()
        self.subjectName = subjectName
        self.unitName = unitName
        self.isTaught = isTaught
    }
}
