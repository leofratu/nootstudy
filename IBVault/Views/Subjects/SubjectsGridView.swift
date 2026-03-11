import SwiftUI
import SwiftData

struct SubjectsGridView: View {
    @Query private var subjects: [Subject]

    var body: some View {
        NavigationStack {
            ZStack {
                IBColors.navy.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: IBSpacing.lg) {
                        Text("Subjects")
                            .font(IBTypography.largeTitle)
                            .foregroundColor(IBColors.softWhite)
                            .padding(.horizontal, IBSpacing.md)
                            .padding(.top, IBSpacing.md)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: IBSpacing.md),
                            GridItem(.flexible(), spacing: IBSpacing.md)
                        ], spacing: IBSpacing.md) {
                            ForEach(subjects, id: \.id) { subject in
                                NavigationLink(destination: SubjectDetailView(subject: subject)) {
                                    SubjectCard(subject: subject)
                                }
                            }
                        }
                        .padding(.horizontal, IBSpacing.md)
                    }
                    .padding(.bottom, 100)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

struct SubjectCard: View {
    let subject: Subject
    @State private var appear = false

    private var color: Color { Color(hex: subject.accentColorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: IBSpacing.sm) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                Spacer()
                Text(subject.level)
                    .font(IBTypography.captionBold)
                    .foregroundColor(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(color.opacity(0.15)))
            }

            Text(subject.name)
                .font(IBTypography.headline)
                .foregroundColor(IBColors.softWhite)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 4)

            MasteryBar(progress: subject.masteryProgress, height: 4, color: color)

            HStack {
                Text("\(Int(subject.masteryProgress * 100))%")
                    .font(IBTypography.caption)
                    .foregroundColor(color)
                Spacer()
                if subject.dueCardsCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text("\(subject.dueCardsCount)")
                            .font(IBTypography.captionBold)
                    }
                    .foregroundColor(IBColors.warning)
                }
            }
        }
        .padding(IBSpacing.md)
        .frame(minHeight: 140)
        .glassCard(cornerRadius: 16)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 10)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                appear = true
            }
        }
    }
}
