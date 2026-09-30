import AppKit
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import IBVault

/// Native view rendering with in-memory fixtures, never the user's database.
@Suite("Biology native visual checks", .serialized)
@MainActor
struct BiologyVisualTests {
    @Test func studyLayoutsRenderAcrossWindowSizesAndAppearances() async throws {
        let store = try ModelContainer(for: Subject.self, StudyCard.self, Grade.self,
                                       CurriculumNode.self, ReviewSession.self, UserProfile.self, StudySession.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let subject = Subject(name: "Biology", level: "SL", accentColorHex: "386044")
        store.mainContext.insert(subject)
        #expect(SyllabusSeeder.synchronizeCurriculum(context: store.mainContext))
        defer {
            for level in ["SL", "HL"] {
                UserDefaults.standard.removeObject(forKey: "biology.selection.\(subject.id.uuidString).\(level)")
            }
            UserDefaults.standard.removeObject(forKey: BiologyPracticeBookmarks.key(subjectID: subject.id))
        }
        #if BIOLOGY_BASELINE
        for width in [720, 1280] {
            let view = BiologyStudyView(subject: subject, initialCode: "B4.2").modelContainer(store)
            try await render(view, width: width, height: 900, dark: false, name: "before-learn-\(width)")
        }
        #else
        for width in [420, 768, 1280] {
            for dark in [false, true] {
                let view = BiologyStudyView(subject: subject, initialCode: "B4.2").modelContainer(store)
                try await render(view, width: width, height: 900, dark: dark,
                                 name: "after-learn-\(width)-\(dark ? "dark" : "light")")
            }
        }
        for mode in [BiologyStudyView.StudyMode.flashcards, .practice] {
            let view = BiologyStudyView(subject: subject, initialCode: "C4.2", initialMode: mode).modelContainer(store)
            try await render(view, width: 768, height: 900, dark: false, name: "after-\(mode.rawValue.lowercased())-768")
        }
        let photosynthesis = BiologyStudyView(subject: subject, initialCode: "C1.3").modelContainer(store)
        try await render(photosynthesis, width: 420, height: 900, dark: false, name: "after-photosynthesis-sl-420")
        subject.level = "HL"
        let respiration = BiologyStudyView(subject: subject, initialCode: "C1.2").modelContainer(store)
        try await render(respiration, width: 1280, height: 900, dark: false, name: "after-respiration-hl-1280")
        let hl = BiologyStudyView(subject: subject, initialCode: "D2.3").modelContainer(store)
        try await render(hl, width: 1280, height: 900, dark: false, name: "after-hl-water-potential")
        #endif
    }

    #if !BIOLOGY_BASELINE
    @Test func quizFeedbackRendersWithTextAndSymbols() async throws {
        let view = VStack(alignment: .leading, spacing: 18) {
            Text("Question feedback").font(.title2.weight(.semibold))
            Text("Correctness is conveyed through words and symbols as well as visual emphasis.")
            BiologyAnswerOption(number: 1, text: "An unselected answer", selected: false, revealed: false, correct: false) {}
            BiologyAnswerOption(number: 2, text: "The selected answer, before checking", selected: true, revealed: false, correct: false) {}
            BiologyAnswerOption(number: 3, text: "The correct answer, after checking", selected: false, revealed: true, correct: true) {}
            BiologyAnswerOption(number: 4, text: "An incorrect answer selected by the student", selected: true, revealed: true, correct: false) {}
        }.padding(24).foregroundStyle(IBColors.ink).background(IBColors.canvas)
        try await render(view, width: 600, height: 640, dark: false, name: "after-quiz-feedback-light")
        try await render(view, width: 600, height: 640, dark: true, name: "after-quiz-feedback-dark")
    }
    #endif

    private func render<V: View>(_ view: V, width: Int, height: Int, dark: Bool, name: String) async throws {
        let size = NSSize(width: width, height: height)
        let hosting = NSHostingView(rootView: view
            .frame(width: CGFloat(width), height: CGFloat(height))
            .background(IBColors.canvas)
            .environment(\.colorScheme, dark ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.setContentSize(size)
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(200))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(bitmap.pixelsWide >= width)
        #expect(bitmap.pixelsHigh >= height)
        #expect(data.count > 1_000)
        let directory = URL(fileURLWithPath: "/tmp/nootstudy-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
    }
}
