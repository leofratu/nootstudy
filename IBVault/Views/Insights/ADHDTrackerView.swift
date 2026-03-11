import SwiftUI

struct ADHDTrackerView: View {
    @AppStorage("adhdDoseMg") private var doseMg = 10
    @AppStorage("adhdDose1Hour") private var dose1Hour = 9
    @AppStorage("adhdDose1Min") private var dose1Min = 0
    @AppStorage("adhdDoseInterval") private var doseIntervalMin = 270 // 4h30m in minutes

    @State private var selectedTime: Int? = nil
    @State private var animateGraph = false

    // PK data from user-provided clinical estimates
    private var pkData: [(time: String, hour: Double, level: Double)] {
        doseMg == 20 ? pk20mg : pk10mg
    }

    // 10 mg IR, 3x daily, 4h30m intervals
    private let pk10mg: [(time: String, hour: Double, level: Double)] = [
        ("9 AM",   0, 0.0),  ("10 AM",  1, 3.6),  ("11 AM",  2, 4.3),
        ("12 PM",  3, 4.0),  ("1 PM",   4, 3.4),   ("1:30 PM", 4.5, 3.1),
        ("2 PM",   5, 5.2),  ("3 PM",   6, 6.4),   ("4 PM",   7, 6.0),
        ("5 PM",   8, 5.1),  ("6 PM",   9, 4.2),   ("7 PM",  10, 7.0),
        ("8 PM",  11, 7.0),  ("9 PM",  12, 6.2),   ("10 PM", 13, 5.1),
        ("11 PM", 14, 4.1),  ("12 AM", 15, 3.3)
    ]

    // 20 mg IR, 3x daily, 4h30m intervals (dose-scaled)
    private let pk20mg: [(time: String, hour: Double, level: Double)] = [
        ("9 AM",   0, 0.0),  ("10 AM",  1, 7.2),   ("11 AM",  2, 8.6),
        ("12 PM",  3, 8.0),  ("1 PM",   4, 6.8),   ("1:30 PM", 4.5, 6.2),
        ("2 PM",   5, 10.3), ("3 PM",   6, 12.8),  ("4 PM",   7, 12.0),
        ("5 PM",   8, 10.2), ("6 PM",   9, 8.4),   ("7 PM",  10, 14.0),
        ("8 PM",  11, 14.0), ("9 PM",  12, 12.3),  ("10 PM", 13, 10.2),
        ("11 PM", 14, 8.3),  ("12 AM", 15, 6.7)
    ]

    private var maxLevel: Double { pkData.map(\.level).max() ?? 8 }
    private var therapeuticMin: Double { doseMg == 20 ? 5.0 : 2.5 }

    // Current status based on actual time
    private var currentStatus: (level: Double, status: String, color: Color) {
        let now = Date()
        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: now)
        let currentMin = cal.component(.minute, from: now)
        let hoursSince9 = Double(currentHour - 9) + Double(currentMin) / 60.0

        if hoursSince9 < 0 || hoursSince9 > 15 {
            return (0, "Not active", IBColors.mutedGray)
        }

        // Interpolate level
        var level = 0.0
        for i in 0..<pkData.count - 1 {
            if hoursSince9 >= pkData[i].hour && hoursSince9 <= pkData[i+1].hour {
                let t = (hoursSince9 - pkData[i].hour) / (pkData[i+1].hour - pkData[i].hour)
                level = pkData[i].level + t * (pkData[i+1].level - pkData[i].level)
                break
            }
        }

        if level >= therapeuticMin * 1.5 {
            return (level, "Peak Focus", IBColors.success)
        } else if level >= therapeuticMin {
            return (level, "Effective Range", IBColors.electricBlue)
        } else if level > 0 {
            return (level, "Wearing Off", IBColors.warning)
        }
        return (0, "Not active", IBColors.mutedGray)
    }

    var body: some View {
        ZStack {
            IBColors.navy.ignoresSafeArea()
            IBColors.meshGlow.ignoresSafeArea()

            ScrollView {
                VStack(spacing: IBSpacing.lg) {
                    currentStatusCard
                    dosePicker
                    concentrationGraph
                    doseScheduleCard
                    disclaimerCard
                }
                .padding(.horizontal, IBSpacing.md)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle("ADHD Med Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.easeOut(duration: 1).delay(0.2)) {
                animateGraph = true
            }
        }
    }

    // MARK: - Current Status
    private var currentStatusCard: some View {
        GlassCard {
            VStack(spacing: IBSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Status")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(IBColors.secondaryText)
                            .textCase(.uppercase).tracking(1.2)
                        Text(currentStatus.status)
                            .font(IBTypography.title)
                            .foregroundColor(currentStatus.color)
                    }
                    Spacer()
                    VStack(spacing: 4) {
                        Text(String(format: "%.1f", currentStatus.level))
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundColor(currentStatus.color)
                        Text("ng/mL")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(IBColors.mutedGray)
                    }
                }

                // Mini status bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(IBColors.cardBorder.opacity(0.3))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [currentStatus.color.opacity(0.5), currentStatus.color],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * min(currentStatus.level / maxLevel, 1.0))
                            .shadow(color: currentStatus.color.opacity(0.4), radius: 4)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - Dose Picker
    private var dosePicker: some View {
        GlassCard(cornerRadius: IBRadius.md, padding: 12) {
            HStack(spacing: IBSpacing.md) {
                Text("Dose:")
                    .font(IBTypography.captionBold).foregroundColor(IBColors.secondaryText)
                ForEach([10, 20], id: \.self) { mg in
                    Button {
                        withAnimation(IBAnimation.snappy) { doseMg = mg; animateGraph = false }
                        withAnimation(.easeOut(duration: 0.8).delay(0.1)) { animateGraph = true }
                        IBHaptics.soft()
                    } label: {
                        Text("\(mg) mg")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(doseMg == mg ? .white : IBColors.mutedGray)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(doseMg == mg ? IBColors.blueGradient : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom))
                                    .overlay(
                                        Capsule().stroke(doseMg == mg ? Color.clear : IBColors.cardBorder, lineWidth: 0.8)
                                    )
                            )
                            .shadow(color: doseMg == mg ? IBColors.electricBlue.opacity(0.3) : .clear, radius: 6)
                    }
                }
                Spacer()
                Text("3× daily")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(IBColors.mutedGray)
            }
        }
    }

    // MARK: - Concentration Graph
    private var concentrationGraph: some View {
        VStack(alignment: .leading, spacing: IBSpacing.sm) {
            HStack {
                Text("Plasma Methylphenidate")
                    .font(IBTypography.headline).foregroundColor(IBColors.softWhite)
                Spacer()
                if let idx = selectedTime {
                    Text("\(pkData[idx].time): \(String(format: "%.1f", pkData[idx].level)) ng/mL")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(IBColors.electricBlue)
                        .transition(.opacity)
                }
            }

            GlassCard(cornerRadius: IBRadius.lg, padding: IBSpacing.md) {
                VStack(spacing: 0) {
                    // Graph
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        let maxY = maxLevel * 1.15

                        ZStack {
                            // Therapeutic zone
                            let thMin = h - (therapeuticMin / maxY * h)
                            let thMax = h - (maxLevel * 0.85 / maxY * h)
                            Rectangle()
                                .fill(IBColors.electricBlue.opacity(0.05))
                                .frame(height: thMin - thMax)
                                .offset(y: thMax - h / 2 + (thMin - thMax) / 2)

                            // Therapeutic line
                            Path { path in
                                let y = h - (therapeuticMin / maxY * h)
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: w, y: y))
                            }
                            .stroke(IBColors.success.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                            // Dose markers
                            ForEach([0, 4.5, 9], id: \.self) { doseHour in
                                let x = doseHour / 15.0 * w
                                Path { path in
                                    path.move(to: CGPoint(x: x, y: 0))
                                    path.addLine(to: CGPoint(x: x, y: h))
                                }
                                .stroke(IBColors.warning.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                            }

                            // Gradient fill under curve
                            if animateGraph {
                                Path { path in
                                    path.move(to: CGPoint(x: 0, y: h))
                                    for dp in pkData {
                                        let x = dp.hour / 15.0 * w
                                        let y = h - (dp.level / maxY * h)
                                        if dp.hour == 0 { path.addLine(to: CGPoint(x: x, y: y)) }
                                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                                    }
                                    path.addLine(to: CGPoint(x: w, y: h))
                                    path.closeSubpath()
                                }
                                .fill(
                                    LinearGradient(
                                        colors: [IBColors.electricBlue.opacity(0.2), IBColors.electricBlue.opacity(0.02)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .transition(.opacity)
                            }

                            // Line
                            if animateGraph {
                                Path { path in
                                    for (i, dp) in pkData.enumerated() {
                                        let x = dp.hour / 15.0 * w
                                        let y = h - (dp.level / maxY * h)
                                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                                    }
                                }
                                .stroke(
                                    LinearGradient(
                                        colors: [IBColors.electricBlue, Color(hex: "7C5CFC")],
                                        startPoint: .leading, endPoint: .trailing
                                    ),
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                                )
                                .shadow(color: IBColors.electricBlue.opacity(0.4), radius: 4)
                                .transition(.opacity)
                            }

                            // Data points
                            if animateGraph {
                                ForEach(Array(pkData.enumerated()), id: \.offset) { index, dp in
                                    let x = dp.hour / 15.0 * w
                                    let y = h - (dp.level / maxY * h)
                                    Circle()
                                        .fill(selectedTime == index ? IBColors.electricBlue : Color(hex: "1A1F3A"))
                                        .frame(width: selectedTime == index ? 10 : 6, height: selectedTime == index ? 10 : 6)
                                        .overlay(
                                            Circle().stroke(IBColors.electricBlue, lineWidth: selectedTime == index ? 2 : 1.5)
                                        )
                                        .shadow(color: IBColors.electricBlue.opacity(selectedTime == index ? 0.5 : 0.2), radius: 4)
                                        .position(x: x, y: y)
                                        .onTapGesture {
                                            withAnimation(IBAnimation.snappy) {
                                                selectedTime = selectedTime == index ? nil : index
                                            }
                                            IBHaptics.soft()
                                        }
                                }
                            }

                            // Current time indicator
                            let now = Date()
                            let cal = Calendar.current
                            let hoursSince9 = Double(cal.component(.hour, from: now) - 9) + Double(cal.component(.minute, from: now)) / 60.0
                            if hoursSince9 >= 0 && hoursSince9 <= 15 {
                                let nx = hoursSince9 / 15.0 * w
                                VStack(spacing: 0) {
                                    Circle().fill(IBColors.danger).frame(width: 6, height: 6)
                                    Rectangle().fill(IBColors.danger.opacity(0.5)).frame(width: 1, height: h)
                                }
                                .position(x: nx, y: h / 2)
                            }
                        }
                    }
                    .frame(height: 200)

                    // X-axis labels
                    HStack {
                        Text("9 AM").font(.system(size: 9)).foregroundColor(IBColors.mutedGray)
                        Spacer()
                        Text("1:30 PM").font(.system(size: 9)).foregroundColor(IBColors.warning.opacity(0.7))
                        Spacer()
                        Text("6 PM").font(.system(size: 9)).foregroundColor(IBColors.warning.opacity(0.7))
                        Spacer()
                        Text("12 AM").font(.system(size: 9)).foregroundColor(IBColors.mutedGray)
                    }
                    .padding(.top, 6)
                }
            }

            // Legend
            HStack(spacing: IBSpacing.md) {
                legendItem(color: IBColors.electricBlue, text: "Plasma level")
                legendItem(color: IBColors.success, text: "Therapeutic min")
                legendItem(color: IBColors.warning, text: "Dose times")
                legendItem(color: IBColors.danger, text: "Now")
            }
            .font(.system(size: 10))
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).foregroundColor(IBColors.mutedGray)
        }
    }

    // MARK: - Dose Schedule
    private var doseScheduleCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: IBSpacing.md) {
                Text("Dose Schedule")
                    .font(IBTypography.headline).foregroundColor(IBColors.softWhite)

                ForEach(Array(["9:00 AM", "1:30 PM", "6:00 PM"].enumerated()), id: \.offset) { index, time in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(IBColors.warning.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Text("\(index + 1)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(IBColors.warning)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dose \(index + 1) — \(doseMg) mg IR")
                                .font(IBTypography.captionBold).foregroundColor(IBColors.softWhite)
                            Text(time)
                                .font(.system(size: 12)).foregroundColor(IBColors.secondaryText)
                        }
                        Spacer()
                        let peakTime = ["~11 AM", "~3 PM", "~8 PM"][index]
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Peak: \(peakTime)")
                                .font(.system(size: 11, weight: .medium)).foregroundColor(IBColors.electricBlue)
                            let peakLevel = doseMg == 20 ? ["8.6", "12.8", "14.0"][index] : ["4.3", "6.4", "7.0"][index]
                            Text("\(peakLevel) ng/mL")
                                .font(.system(size: 10)).foregroundColor(IBColors.mutedGray)
                        }
                    }
                    if index < 2 { PremiumDivider() }
                }
            }
        }
    }

    // MARK: - Disclaimer
    private var disclaimerCard: some View {
        GlassCard(cornerRadius: IBRadius.sm, padding: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(IBColors.electricBlueMuted)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Important Notes")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(IBColors.secondaryText)
                    Text("These are evidence-based PK estimates anchored to FDA-reviewed data, NOT direct measurements for your exact schedule. Actual concentrations vary significantly between individuals. 20 mg × 3 = 60 mg/day matches the labelled adult maximum. This tool is for awareness only — always follow your prescriber's guidance.")
                        .font(.system(size: 11))
                        .foregroundColor(IBColors.mutedGray)
                        .lineSpacing(3)
                }
            }
        }
    }
}
