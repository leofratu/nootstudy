import SwiftUI
import SwiftData
import Charts

struct PredictiveGradeView: View {
    @Environment(\.modelContext) private var context
    @Query private var subjects: [Subject]
    @Query private var profiles: [UserProfile]
    @Query(sort: \Grade.date, order: .reverse) private var allGrades: [Grade]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                
                predictedScoreCard
                    .padding(.horizontal, 28)
                
                subjectPredictionsCard
                    .padding(.horizontal, 28)
                    
                gradeGapCard
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            }
        }
        .background(.background)
        .navigationTitle("Grade Prediction")
    }
    
    // MARK: - Header
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(IBColors.success.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 18))
                        .foregroundStyle(IBColors.success)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Predictive Grade Calculator")
                        .font(.headline)
                    Text("Based on your weighted assessments, mastery trends, and historical grades")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
        }
        .padding(16)
        .glassCard()
    }
    
    // MARK: - Overall Prediction
    private var predictedScoreCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Predicted IB Score")
                    .font(.headline)
                Spacer()
            }
            
            HStack(alignment: .center, spacing: 30) {
                VStack(spacing: 4) {
                    Text("\(predictedTotalScore)")
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(IBColors.electricBlue)
                    Text("Predicted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Divider().frame(height: 50)
                
                if let profile = profiles.first {
                    VStack(spacing: 4) {
                        Text("\(profile.targetIBScore)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(targetColor)
                        Text("Target")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider().frame(height: 50)
                
                VStack(spacing: 4) {
                    Text("\(scoreGap)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreGapColor)
                    Text(scoreGapLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if scoreGap > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(IBColors.success)
                    Text("\(Int(Double(abs(scoreGap)) * masteryImpactFactor)) points from mastery")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .glassCard()
    }
    
    private var targetColor: Color {
        guard let profile = profiles.first else { return .secondary }
        return predictedTotalScore >= profile.targetIBScore ? IBColors.success : .orange
    }
    
    private var scoreGapColor: Color {
        if scoreGap >= 0 {
            return IBColors.success
        } else {
            return .red
        }
    }
    
    private var scoreGapLabel: String {
        if scoreGap >= 0 {
            return "Above target"
        } else {
            return "To go"
        }
    }
    
    // MARK: - Subject Predictions
    private var subjectPredictionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(.tint)
                Text("Subject Predictions")
                    .font(.headline)
                Spacer()
            }
            
            ForEach(subjects) { subject in
                subjectPredictionRow(subject)
                
                if subject.id != subjects.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .glassCard()
    }
    
    private func subjectPredictionRow(_ subject: Subject) -> some View {
        let prediction = predictSubjectGrade(subject)
        let color = Color(hex: subject.accentColorHex)
        let weightedAverage = subject.weightedGradeAverage
        
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                
                Text(subject.name)
                    .font(.callout.weight(.medium))
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Predicted: \(prediction.predicted)")
                        .font(.caption.bold())
                        .foregroundStyle(color)
                    
                    if let weightedAverage {
                        Text("Course avg: \(weightedAverage, specifier: "%.1f")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let latest = prediction.latest {
                        Text("Latest: \(latest)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            HStack(spacing: 4) {
                MasteryBar(progress: subject.masteryProgress, height: 4, color: color)
                Text("\(Int(subject.masteryProgress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 35, alignment: .trailing)
            }
            
            if prediction.trend != .stable {
                HStack(spacing: 4) {
                    Image(systemName: prediction.trend == .improving ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)
                    Text(prediction.trend == .improving ? "Improving" : "Declining")
                        .font(.caption2)
                }
                .foregroundStyle(prediction.trend == .improving ? IBColors.success : .orange)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Grade Gap
    private var gradeGapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "target")
                    .foregroundStyle(.tint)
                Text("Gap Analysis")
                    .font(.headline)
                Spacer()
            }
            
            if let profile = profiles.first {
                let gap = profile.targetIBScore - predictedTotalScore
                
                if gap <= 0 {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(IBColors.success)
                            Text("On track to meet target!")
                                .font(.callout.weight(.medium))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 12) {
                        Text("You need \(gap) more points to reach your target")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        
                        let weakest = subjects.sorted { $0.masteryProgress < $1.masteryProgress }.prefix(2)
                        
                        if !weakest.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Focus on these subjects:")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                
                                ForEach(Array(weakest)) { subject in
                                    HStack {
                                        Circle()
                                            .fill(Color(hex: subject.accentColorHex))
                                            .frame(width: 8, height: 8)
                                        Text(subject.name)
                                            .font(.callout)
                                        Spacer()
                                        Text("\(Int(subject.masteryProgress * 100))%")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.03))
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .glassCard()
    }
    
    // MARK: - Helpers
    private var predictedTotalScore: Int {
        subjects.reduce(0) { $0 + predictSubjectGrade($1).predicted }
    }
    
    private var scoreGap: Int {
        guard let profile = profiles.first else { return 0 }
        return predictedTotalScore - profile.targetIBScore
    }
    
    private var masteryImpactFactor: Double {
        0.7
    }
    
    private func predictSubjectGrade(_ subject: Subject) -> SubjectPrediction {
        let mastery = subject.masteryProgress
        let grades = subject.grades.sorted { $0.date > $1.date }
        let weightedAverage = subject.weightedGradeAverage
        
        var predicted: Int
        var latest: Int?
        var trend: GradeTrend = .stable
        
        if let latestGrade = grades.first {
            latest = latestGrade.resolvedIBScore
            
            if grades.count >= 2, let second = grades.dropFirst().first {
                trend = latestGrade.resolvedIBScore > second.resolvedIBScore ? .improving : (latestGrade.resolvedIBScore < second.resolvedIBScore ? .declining : .stable)
            }

            let baseGrade = weightedAverage ?? Double(latestGrade.resolvedIBScore)
            let masteryBoost = mastery * 1.4
            predicted = min(7, max(1, Int((baseGrade + masteryBoost).rounded())))
        } else {
            predicted = max(1, Int(mastery * 7))
        }
        
        return SubjectPrediction(predicted: predicted, latest: latest, trend: trend)
    }
}

struct SubjectPrediction {
    let predicted: Int
    let latest: Int?
    let trend: GradeTrend
}

enum GradeTrend {
    case improving
    case stable
    case declining
}

#Preview {
    NavigationStack {
        PredictiveGradeView()
    }
}
