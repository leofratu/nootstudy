import SwiftUI
import SwiftData
import Charts

struct LearningAnalyticsView: View {
    @Environment(\.modelContext) private var context
    @Query private var subjects: [Subject]
    @Query(sort: \StudySession.startDate, order: .reverse) private var sessions: [StudySession]
    @Query private var activities: [StudyActivity]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCard
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                
                timeSpentCard
                    .padding(.horizontal, 28)
                
                productivityCard
                    .padding(.horizontal, 28)
                
                retentionCard
                    .padding(.horizontal, 28)
                    
                subjectTimeCard
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            }
        }
        .background(.background)
        .navigationTitle("Learning Analytics")
    }
    
    // MARK: - Header
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(IBColors.electricBlue.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 18))
                        .foregroundStyle(IBColors.electricBlue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Learning Analytics")
                        .font(.headline)
                    Text("Track your study patterns and productivity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
        }
        .padding(16)
        .glassCard()
    }
    
    // MARK: - Time Spent
    private var timeSpentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.tint)
                Text("Time Spent")
                    .font(.headline)
                Spacer()
            }
            
            let weekMinutes = totalMinutesThisWeek
            let dayAvg = weekMinutes / 7
            
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("\(weekMinutes)")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(IBColors.electricBlue)
                    Text("minutes this week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Divider().frame(height: 40)
                
                VStack(spacing: 4) {
                    Text("\(dayAvg)")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(IBColors.success)
                    Text("avg per day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            
            Chart {
                ForEach(weeklyData) { day in
                    BarMark(
                        x: .value("Day", day.day),
                        y: .value("Minutes", day.minutes)
                    )
                    .foregroundStyle(IBColors.electricBlue.gradient)
                }
            }
            .frame(height: 120)
        }
        .padding(16)
        .glassCard()
    }
    
    // MARK: - Productivity
    private var productivityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                Text("Productivity")
                    .font(.headline)
                Spacer()
            }
            
            let peakHour = mostProductiveHour
            
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("\(sessions.count)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(IBColors.electricBlue)
                    Text("sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 4) {
                    Text("\(peakHour == 0 ? "12" : "\(peakHour)")\(peakHour >= 12 ? "PM" : "AM")")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(IBColors.success)
                    Text("peak hour")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 4) {
                    Text("\(Int(productivityScore * 100))%")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.orange)
                    Text("efficiency")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .glassCard()
    }
    
    // MARK: - Retention
    private var retentionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                Text("Retention Rate")
                    .font(.headline)
                Spacer()
                Text("Last 30 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            let retention = overallRetentionRate
            
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(IBColors.cardBorder.opacity(0.3), lineWidth: 8)
                        .frame(width: 80, height: 80)
                    Circle()
                        .trim(from: 0, to: retention)
                        .stroke(.purple, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(Int(retention * 100))%")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.purple)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    retentionLabel("Remembered", percentage: retention)
                    retentionLabel("Forgot", percentage: 1 - retention)
                }
            }
        }
        .padding(16)
        .glassCard()
    }
    
    private func retentionLabel(_ text: String, percentage: Double) -> some View {
        HStack {
            Circle()
                .fill(text == "Remembered" ? .purple : .gray)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(Int(percentage * 100))%")
                .font(.caption.bold())
        }
    }
    
    // MARK: - Subject Time
    private var subjectTimeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(.tint)
                Text("Time per Subject")
                    .font(.headline)
                Spacer()
            }
            
            ForEach(subjectTimeData.prefix(5)) { item in
                let color = Color(hex: item.colorHex)
                
                HStack(spacing: 10) {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                    
                    Text(item.subjectName)
                        .font(.callout)
                    
                    Spacer()
                    
                    Text("\(item.minutes) min")
                        .font(.caption.bold())
                        .foregroundStyle(color)
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.1))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: geo.size.width * item.percentage)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(16)
        .glassCard()
    }
    
    // MARK: - Computed Data
    private var totalMinutesThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return sessions
            .filter { $0.startDate > weekAgo }
            .reduce(0) { $0 + Int($1.duration / 60) }
    }
    
    private var weeklyData: [DayData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        return (0..<7).reversed().map { daysAgo in
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            let dayStart = calendar.startOfDay(for: day)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? day
            
            let minutes = sessions
                .filter { $0.startDate >= dayStart && $0.startDate < dayEnd }
                .reduce(0) { $0 + Int($1.duration / 60) }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            
            return DayData(day: formatter.string(from: day), minutes: minutes)
        }
    }
    
    private var mostProductiveHour: Int {
        let hourCounts = Dictionary(grouping: sessions) { session in
            Calendar.current.component(.hour, from: session.startDate)
        }
        
        return hourCounts.max(by: { $0.value.count < $1.value.count })?.key ?? 16
    }
    
    private var productivityScore: Double {
        guard !sessions.isEmpty else { return 0 }
        
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentSessions = sessions.filter { $0.startDate > weekAgo }
        
        guard !recentSessions.isEmpty else { return 0 }
        
        let avgDuration = recentSessions.reduce(0.0) { $0 + ($1.duration / 60) } / Double(recentSessions.count)
        let completionRate = Double(recentSessions.count) / Double(max(1, sessions.count))
        
        return min(1.0, (avgDuration / 60.0) * 0.5 + completionRate * 0.5)
    }
    
    private var overallRetentionRate: Double {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentSessions = sessions.filter { $0.startDate > thirtyDaysAgo }
        
        guard !recentSessions.isEmpty else { return 0.7 }
        
        let totalReviewed = recentSessions.reduce(0) { $0 + $1.cardsReviewed }
        let correctCount = recentSessions.reduce(0) { $0 + $1.correctCount }
        
        guard totalReviewed > 0 else { return 0.7 }
        
        return Double(correctCount) / Double(totalReviewed)
    }
    
    private var subjectTimeData: [SubjectTimeData] {
        let totalMinutes = Double(max(1, sessions.reduce(0) { $0 + Int($1.duration / 60) }))
        
        return subjects.compactMap { subject in
            let minutes = sessions
                .filter { $0.subjectName == subject.name }
                .reduce(0) { $0 + Int($1.duration / 60) }
            
            guard minutes > 0 else { return nil }
            
            return SubjectTimeData(
                subjectName: subject.name,
                colorHex: subject.accentColorHex,
                minutes: minutes,
                percentage: CGFloat(minutes) / CGFloat(totalMinutes)
            )
        }.sorted { $0.minutes > $1.minutes }
    }
}

struct DayData: Identifiable {
    let id = UUID()
    let day: String
    let minutes: Int
}

struct SubjectTimeData: Identifiable {
    let id = UUID()
    let subjectName: String
    let colorHex: String
    let minutes: Int
    let percentage: CGFloat
}

#Preview {
    NavigationStack {
        LearningAnalyticsView()
    }
}
