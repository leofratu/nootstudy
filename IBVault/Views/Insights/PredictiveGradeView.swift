import SwiftUI
import SwiftData
import Charts

struct PredictiveGradeView: View {
    @Query private var subjects: [Subject]
    @Query private var profiles: [UserProfile]
    @Query(sort: \Grade.date, order: .reverse) private var allGrades: [Grade]
    @Query private var academicAssessments: [AcademicAssessment]
    @Query private var academicMappings: [AcademicAssessmentMapping]
    @Query private var academicReports: [AcademicReportSnapshot]
    @Query(sort: \StudySession.endDate, order: .reverse) private var studySessions: [StudySession]

    /// Per-subject predictions and their sum, refreshed only when the queried
    /// subjects or grades change. `predictSubjectGrade` used to re-scan every
    /// subject's cards and sort grades ~6 times per render.
    @State private var cachedPredictions: [UUID: SubjectPrediction] = [:]
    @State private var cachedTotalScore = 0
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                StudioPageHeader(
                    eyebrow: "Forecast",
                    title: "Grade prediction",
                    subtitle: "Teacher predictions from the latest D1 report, using an assumed 2 TOK/EE core points.",
                    symbol: "chart.line.uptrend.xyaxis",
                    tint: IBColors.inkTertiary
                ) {
                    StudioPill(title: subjectPointsStillNeeded == 0 ? "ON TARGET" : "\(subjectPointsStillNeeded) PTS TO CLOSE", tint: subjectPointsStillNeeded == 0 ? IBColors.success : IBColors.inkTertiary)
                }

                predictedScoreCard
                subjectPredictionsCard
                gradeGapCard
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(IBColors.canvas)
        .navigationTitle("Grade Prediction")
        .onAppear(perform: refreshPredictions)
        .onChange(of: subjects) { _, _ in refreshPredictions() }
        .onChange(of: allGrades) { _, _ in refreshPredictions() }
    }
    
    // MARK: - Overall Prediction
    private var predictedScoreCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Diploma forecast")
                    .font(.headline)
                Spacer()
            }
            
            HStack(alignment: .center, spacing: 30) {
                VStack(spacing: 4) {
                    Text("\(predictedSubjectPoints)")
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(IBColors.accent)
                    Text("Subject points / 42")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Divider().frame(height: 50)

                VStack(spacing: 4) {
                    Text("\(DiplomaForecast.assumedCorePoints)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(IBColors.inkTertiary)
                    Text("TOK + EE assumed")
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
                    Text("\(predictedDiplomaScore)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(targetColor)
                    Text("Predicted / 45")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if subjectPointsStillNeeded > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(IBColors.inkTertiary)
                    Text("Assuming \(DiplomaForecast.assumedCorePoints) TOK/EE core points, you need \(subjectPointsStillNeeded) more points to reach \(targetScore).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(IBColors.success)
                    Text("This forecast assumes \(DiplomaForecast.assumedCorePoints) TOK/EE core points.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .glassCard()
    }
    
    private var targetColor: Color {
        subjectPointsStillNeeded == 0 ? IBColors.success : IBColors.warning
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
            
            ForEach(diplomaSubjects) { subject in
                subjectPredictionRow(subject)
                
                if subject.id != diplomaSubjects.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .glassCard()
    }
    
    private func subjectPredictionRow(_ subject: Subject) -> some View {
        let prediction = predictSubjectGrade(subject)
        let color = IBColors.inkTertiary
        let mastery = evidenceBackedMastery(for: subject)
        
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
                    
                    if let latest = prediction.latest {
                        Text("Latest report: \(latest)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            HStack(spacing: 4) {
                MasteryBar(progress: mastery, height: 4, color: color)
                Text("\(Int(mastery * 100))%")
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
                .foregroundStyle(prediction.trend == .improving ? IBColors.success : IBColors.warning)
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
                let gap = subjectPointsStillNeeded
                
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
                        Text("You need \(gap) more points to reach \(profile.targetIBScore), assuming \(DiplomaForecast.assumedCorePoints) TOK/EE core points.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        
                        let weakest = diplomaSubjects.sorted { evidenceBackedMastery(for: $0) < evidenceBackedMastery(for: $1) }.prefix(2)
                        
                        if !weakest.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Focus on these subjects:")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                
                                ForEach(Array(weakest)) { subject in
                                    HStack {
                                        Circle()
                                            .fill(IBColors.inkTertiary)
                                            .frame(width: 8, height: 8)
                                        Text(subject.name)
                                            .font(.callout)
                                        Spacer()
                                        Text("\(Int(evidenceBackedMastery(for: subject) * 100))%")
                                            .font(.caption)
                                            .foregroundStyle(IBColors.danger)
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
    private var diplomaSubjects: [Subject] {
        subjects.filter { DiplomaForecast.isScoredDiplomaSubject($0.name) }
    }

    private var predictedSubjectPoints: Int {
        guard cachedPredictions.count == diplomaSubjects.count, !diplomaSubjects.isEmpty else { return computeTotalScore() }
        return cachedTotalScore
    }

    private var targetScore: Int { profiles.first?.targetIBScore ?? 40 }

    private var predictedDiplomaScore: Int {
        min(45, predictedSubjectPoints + DiplomaForecast.assumedCorePoints)
    }

    private var subjectPointsStillNeeded: Int {
        max(0, targetScore - predictedDiplomaScore)
    }

    private func predictSubjectGrade(_ subject: Subject) -> SubjectPrediction {
        if let cached = cachedPredictions[subject.id] {
            return cached
        }
        return computePrediction(for: subject)
    }

    private func computeTotalScore() -> Int {
        diplomaSubjects.reduce(0) { $0 + computePrediction(for: $1).predicted }
    }

    private func refreshPredictions() {
        var predictions: [UUID: SubjectPrediction] = [:]
        var total = 0
        for subject in diplomaSubjects {
            let prediction = computePrediction(for: subject)
            predictions[subject.id] = prediction
            total += prediction.predicted
        }
        cachedPredictions = predictions
        cachedTotalScore = total
    }

    private func computePrediction(for subject: Subject) -> SubjectPrediction {
        let grades = subject.grades.sorted { $0.date > $1.date }
        let weightedAverage = subject.weightedGradeAverage
        
        var predicted: Int
        var latest: Int?
        var trend: GradeTrend = .stable
        
        if let teacherPrediction = grades.compactMap(\.predictedGrade).first,
           let latestGrade = grades.first {
            latest = latestGrade.resolvedIBScore
            predicted = teacherPrediction
        } else if let latestGrade = grades.first {
            latest = latestGrade.resolvedIBScore
            
            if grades.count >= 2, let second = grades.dropFirst().first {
                trend = latestGrade.resolvedIBScore > second.resolvedIBScore ? .improving : (latestGrade.resolvedIBScore < second.resolvedIBScore ? .declining : .stable)
            }

            let baseGrade = weightedAverage ?? Double(latestGrade.resolvedIBScore)
            let masteryBoost = evidenceBackedMastery(for: subject) * 1.4
            predicted = min(7, max(1, Int((baseGrade + masteryBoost).rounded())))
        } else {
            predicted = max(1, Int(evidenceBackedMastery(for: subject) * 7))
        }
        
        return SubjectPrediction(predicted: predicted, latest: latest, trend: trend)
    }

    private func evidenceBackedMastery(for subject: Subject) -> Double {
        ProgressEvidenceService.score(
            subjectName: subject.name,
            courseLevel: subject.level,
            cards: subject.cards,
            assessments: academicAssessments,
            mappings: academicMappings,
            reports: academicReports,
            workSessions: studySessions
        ).blendedMastery ?? 0
    }
}

nonisolated enum DiplomaForecast {
    static let assumedCorePoints = 2

    static func isScoredDiplomaSubject(_ subjectName: String) -> Bool {
        ["Russian A Literature", "English B", "Business Management", "Economics", "Biology", "Mathematics AA"].contains(subjectName)
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
