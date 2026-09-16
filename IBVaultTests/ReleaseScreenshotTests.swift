import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import IBVault

/// Opt-in documentation previews with synthetic in-memory records.
/// An external screenshot tool captures each window. The app never captures
/// the screen or requests screen-recording permission.
@Suite("Release screenshots", .enabled(if: ProcessInfo.processInfo.environment["NOOTSTUDY_SCREENSHOT_DIR"] != nil))
@MainActor
struct ReleaseScreenshotTests {
    @Test func renderDocumentation() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["NOOTSTUDY_SCREENSHOT_DIR"]))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let schema = Schema([Subject.self, StudyCard.self, ReviewSession.self, Grade.self, UserProfile.self,
            Achievement.self, ARIAMemory.self, ARIAChatSession.self, ChatMessage.self, StudyActivity.self,
            StudySession.self, StudyPlan.self, SubjectTrack.self, UnitState.self, CurriculumNode.self,
            WeeklyChallenge.self, AcademicImport.self, AcademicAssessment.self, AcademicAssessmentMapping.self,
            AcademicReportSnapshot.self, ExternalActivity.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "34533B")
        let profile = UserProfile()
        profile.studentName = "Demo learner"
        context.insert(subject)
        context.insert(profile)
        let card = StudyCard(topicName: "Ecosystems", subtopic: "Food webs",
            front: "What do the arrows in a food web represent?",
            back: "The direction of energy transfer between organisms", subject: subject,
            cardStyle: .multipleChoice, choices: ["The direction of energy transfer between organisms",
                "The relative size of each population", "The age of organisms in each population", "The movement of water through an ecosystem"])
        let second = StudyCard(topicName: "Energy Flow in Ecosystems", subtopic: "Trophic levels",
            front: "Why does less energy reach each successive trophic level?",
            back: "Organisms use energy in respiration and lose heat; not all biomass is eaten or assimilated.", subject: subject)
        let third = StudyCard(topicName: "Population Biology", subtopic: "Carrying capacity",
            front: "Define the carrying capacity of an ecosystem.",
            back: "The largest population that the environment can support over time with its available resources.", subject: subject)
        for item in [card, second, third] { context.insert(item) }
        try context.save()
        try StudyTestStore.save(.init(subject: "Biology", level: "SL", topics: ["Ecosystems"], subtopics: ["Food webs"],
            question: "Explain how removing a predator can affect the populations in a food web. [4 marks]", maximumMarks: 4), context: context)

        try await render(ContentView(initialTab: .library).overlay(alignment: .bottomLeading) {
            HStack(spacing: 10) {
                Circle().fill(IBColors.inkSecondary.opacity(0.4)).frame(width: 28, height: 28)
                VStack(alignment: .leading) {
                    Text("Demo learner").font(.system(size: 12.5, weight: .semibold))
                    Text("Personal profile").font(.system(size: 10))
                }
            }.blur(radius: 7).frame(width: 208, height: 44, alignment: .leading)
                .padding(.horizontal, 12).background(IBColors.canvasDeep).padding(.bottom, 5)
        }, container: container, size: NSSize(width: 1280, height: 820), output: output.appendingPathComponent("library.png"))
        try await render(CardStudioView(initialSubject: subject,
            initialSelection: [.init(topic: "Ecosystems"), .init(topic: "Population Biology")]),
            container: container, size: NSSize(width: 1100, height: 1050), output: output.appendingPathComponent("card-studio.png"))
        try await render(CardPracticeView(cards: [card]), container: container,
            size: NSSize(width: 760, height: 860), output: output.appendingPathComponent("multiple-choice.png"))
    }

    private func render<V: View>(_ view: V, container: ModelContainer, size: NSSize, output: URL) async throws {
        if let only = ProcessInfo.processInfo.environment["NOOTSTUDY_PREVIEW_ONLY"],
           only != output.deletingPathExtension().lastPathComponent { return }
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let scale = min(1, (visible.height - 80) / size.height, (visible.width - 80) / size.width)
        let windowSize = NSSize(width: size.width * scale, height: size.height * scale)
        let root = view.modelContainer(container).environment(ReviewQueueManager())
            .environment(ProgressionEventCenter()).preferredColorScheme(.light)
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .frame(width: windowSize.width, height: windowSize.height)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: windowSize), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.title = "Noot Study — " + output.deletingPathExtension().lastPathComponent
        window.sharingType = .readOnly
        window.center()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }
        try await Task.sleep(for: .seconds(1))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let marker = output.appendingPathExtension("captured")
        if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
        let ready = output.deletingLastPathComponent().appendingPathComponent("current-preview.txt")
        try window.title.write(to: ready, atomically: true, encoding: .utf8)
        let deadline = ContinuousClock.now.advanced(by: .seconds(180))
        while !FileManager.default.fileExists(atPath: marker.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(FileManager.default.fileExists(atPath: marker.path), "Capture the demo window externally, then create \(marker.lastPathComponent).")
    }
}
