import AppKit
import Combine
import SwiftUI
import SwiftData

// NotebookLM export: subject picker + pack generation via NotebookPackService.

// MARK: - Integration Settings Section

struct IntegrationSettingsSection: View {
    @Environment(IntegrationBridgeController.self) private var bridge: IntegrationBridgeController?
    @Environment(\.modelContext) private var context
    @Query private var subjects: [Subject]

    @State private var showRegenerateConfirm = false
    @State private var showToken = false
    @State private var copyTokenFeedback = false
    @State private var copyMCPFeedback = false
    @State private var recentLogs: [LocalBridgeServer.RequestLog] = []
    @State private var selectedSubjectName: String = ""
    @State private var selectedTopicName: String = ""
    @State private var exportStatus: String = ""
    @State private var exportSuccessURL: URL?
    @State private var isExporting = false

    private var isBridgeEnabled: Binding<Bool> {
        Binding(
            get: { bridge?.isEnabled ?? BridgeAuthService.isEnabled },
            set: { bridge?.isEnabled = $0 }
        )
    }

    private var statusText: String {
        guard let bridge else { return "Stopped" }
        switch bridge.state {
        case .stopped: return "Stopped"
        case .running(let port): return "Running on 127.0.0.1:\(port)"
        case .failed(let msg): return "Failed (\(msg))"
        }
    }

    private var statusColor: Color {
        guard let bridge else { return IBColors.secondaryText }
        switch bridge.state {
        case .stopped: return IBColors.secondaryText
        case .running: return IBColors.success
        case .failed: return IBColors.danger
        }
    }

    private var currentPort: Int {
        bridge?.currentPort ?? UserDefaults.standard.integer(forKey: "BridgeActualPort").nonZeroOrDefault(42827)
    }

    private var bridgeURL: String {
        "http://127.0.0.1:\(currentPort)"
    }

    private var currentToken: String {
        bridge?.token ?? BridgeAuthService.token()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            workspaceBand(
                title: "Local integration bridge",
                subtitle: "Expose your library to Codex, ChatGPT, and Claude on this Mac only.",
                symbol: "link",
                tint: IBColors.electricBlue
            ) {
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Label("Local integration bridge", systemImage: "point.3.connected.trianglepath.dotted")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("", isOn: isBridgeEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(IBColors.electricBlue)
                    }
                    .padding(.vertical, 10)

                    Divider()

                    HStack(spacing: 10) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(IBColors.ink)
                            .lineLimit(1)
                        Spacer()
                        if case .running = bridge?.state {
                            StudioPill(title: "LIVE", tint: IBColors.success)
                        } else if case .failed = bridge?.state {
                            StudioPill(title: "ERROR", tint: IBColors.danger)
                        } else {
                            StudioPill(title: "OFF", tint: IBColors.secondaryText)
                        }
                    }
                    .padding(.vertical, 10)

                    Divider()

                    HStack(spacing: 14) {
                        Label("Port", systemImage: "number")
                            .frame(width: 120, alignment: .leading)
                        Text("\(currentPort)")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(IBColors.ink)
                        Spacer()
                        Text("127.0.0.1 only")
                            .font(.caption)
                            .foregroundStyle(IBColors.secondaryText)
                    }
                    .padding(.vertical, 10)

                    Divider()

                    HStack(spacing: 14) {
                        Label("Bearer token", systemImage: "key.fill")
                            .frame(width: 120, alignment: .leading)
                        if showToken {
                            Text(currentToken)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(IBColors.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        } else {
                            Text(String(repeating: "•", count: 24))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(IBColors.ink)
                        }
                        Spacer()
                        Button(showToken ? "Hide" : "Show") { showToken.toggle() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button {
                            copyToken()
                        } label: {
                            Label(copyTokenFeedback ? "Copied" : "Copy Token", systemImage: copyTokenFeedback ? "checkmark.circle.fill" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Copy Token")
                        Button("Regenerate", role: .destructive) {
                            showRegenerateConfirm = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Regenerate Token")
                    }
                    .padding(.vertical, 10)

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("MCP setup", systemImage: "terminal")
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Button {
                                copyMCPSetup()
                            } label: {
                                Label(copyMCPFeedback ? "Copied" : "Copy MCP Setup", systemImage: copyMCPFeedback ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(IBColors.electricBlue)
                            .accessibilityLabel("Copy MCP Setup")
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(mcpSetupSnippet)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(IBColors.secondaryText)
                                .textSelection(.enabled)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(IBColors.canvasDeep)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(IBColors.cardBorder, lineWidth: 1))
                                )
                        }
                    }
                    .padding(.vertical, 10)

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Data stays local. The bridge only listens on 127.0.0.1 and requires the bearer token. Integration is off by default.")
                            .font(.caption)
                            .foregroundStyle(IBColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        NavigationLink {
                            ExternalActivityView()
                        } label: {
                            Label("Manage external work", systemImage: "tray.and.arrow.down.fill")
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.vertical, 10)
                }
            }

            workspaceBand(
                title: "Recent activity",
                subtitle: "Last requests handled by the bridge (up to 100).",
                symbol: "waveform.path.ecg",
                tint: IBColors.teal
            ) {
                if recentLogs.isEmpty {
                    Text("No requests yet. When Codex or ChatGPT calls the bridge, method, path, and status appear here.")
                        .font(.callout)
                        .foregroundStyle(IBColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(recentLogs.enumerated()), id: \.offset) { idx, log in
                            HStack(spacing: 10) {
                                Text(log.method)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(IBColors.ink)
                                    .frame(width: 42, alignment: .leading)
                                    .lineLimit(1)
                                Text(log.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(IBColors.ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text("\(log.status)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(log.status < 400 ? IBColors.success : IBColors.danger)
                                    .frame(width: 28, alignment: .trailing)
                                Text(log.timestamp, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(IBColors.secondaryText)
                                    .frame(width: 80, alignment: .trailing)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 8)
                            if idx < recentLogs.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }

            workspaceBand(
                title: "NotebookLM pack",
                subtitle: "Export a markdown source + cards JSON to upload into NotebookLM.",
                symbol: "doc.richtext.fill",
                tint: IBColors.gold
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("NotebookLM has no public API, so this pack is meant to be uploaded as a notebook source, and Codex/ChatGPT can query the same data through the bridge.")
                        .font(.caption)
                        .foregroundStyle(IBColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Picker("Subject", selection: $selectedSubjectName) {
                            Text("Select subject").tag("")
                            ForEach(subjects.sorted { $0.name < $1.name }, id: \.name) { subject in
                                Text(subject.name).tag(subject.name)
                            }
                        }
                        .frame(maxWidth: 220)
                        .labelsHidden()

                        TextField("Topic (optional)", text: $selectedTopicName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)

                        Button {
                            exportPack()
                        } label: {
                            Label(isExporting ? "Exporting…" : "Export NotebookLM Pack", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .tint(IBColors.electricBlue)
                        .disabled(selectedSubjectName.isEmpty || isExporting)
                        .accessibilityLabel("Export NotebookLM Pack")

                        Spacer(minLength: 8)
                    }

                    if !exportStatus.isEmpty {
                        Text(exportStatus)
                            .font(.caption)
                            .foregroundStyle(exportSuccessURL == nil ? IBColors.danger : IBColors.success)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let url = exportSuccessURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Open Folder", systemImage: "folder.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }

            workspaceBand(
                title: "External work",
                subtitle: "Add work you did elsewhere back into your study history.",
                symbol: "tray.and.arrow.down.fill",
                tint: IBColors.coral
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Use the activity bridge or add work manually. Merged work becomes a real study session.")
                        .font(.callout)
                        .foregroundStyle(IBColors.secondaryText)
                    NavigationLink {
                        ExternalActivityView()
                    } label: {
                        Label("Open external work", systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(IBColors.coral)
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            if selectedSubjectName.isEmpty, let first = subjects.sorted(by: { $0.name < $1.name }).first {
                selectedSubjectName = first.name
            }
            refreshLogs()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            refreshLogs()
        }
        .onChange(of: bridge?.state) { _, _ in
            refreshLogs()
        }
        .alert("Regenerate token?", isPresented: $showRegenerateConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Regenerate", role: .destructive) {
                bridge?.regenerateToken()
                IBHaptics.warning()
            }
        } message: {
            Text("This invalidates the old token. Update your Codex/ChatGPT config after regenerating.")
        }
    }

    private var mcpSetupSnippet: String {
        let url = bridgeURL
        let token = currentToken
        return """
        Bridge URL: \(url)
        Token: \(token)

        Codex CLI:
        codex mcp add nootstudy --env NOOTSTUDY_BRIDGE_URL=\(url) --env NOOTSTUDY_BRIDGE_TOKEN=\(token) -- npx -y nootstudy-mcp

        ChatGPT / Claude (JSON):
        {
          "mcpServers": {
            "nootstudy": {
              "command": "npx",
              "args": ["-y", "nootstudy-mcp"],
              "env": {
                "NOOTSTUDY_BRIDGE_URL": "\(url)",
                "NOOTSTUDY_BRIDGE_TOKEN": "\(token)"
              }
            }
          }
        }
        """
    }

    private func copyToken() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(currentToken, forType: .string)
        copyTokenFeedback = true
        IBHaptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copyTokenFeedback = false }
    }

    private func copyMCPSetup() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(mcpSetupSnippet, forType: .string)
        copyMCPFeedback = true
        IBHaptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copyMCPFeedback = false }
    }

    private func refreshLogs() {
        recentLogs = bridge?.recentRequests() ?? []
    }

    private func exportPack() {
        guard !selectedSubjectName.isEmpty else { return }
        isExporting = true
        exportStatus = ""
        exportSuccessURL = nil

        let container = context.container
        let subjectName = selectedSubjectName
        let topic = selectedTopicName.trimmingCharacters(in: .whitespacesAndNewlines)
        let topicParam: String? = topic.isEmpty ? nil : topic

        guard let pack = NotebookPackService.export(subjectName: subjectName, topicName: topicParam, container: container) else {
            exportStatus = "Subject not found."
            isExporting = false
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Choose where to save notebooklm-source.md and cards.json"
        if panel.runModal() != .OK || panel.url == nil {
            // Fallback to Documents/NotebookLM Packs
            let fallback = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("NotebookLM Packs", isDirectory: true)
            if let fallback {
                do {
                    try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
                    try writePack(pack, to: fallback)
                    exportSuccessURL = fallback
                    exportStatus = "Saved to \(fallback.lastPathComponent) in Documents."
                    IBHaptics.success()
                } catch {
                    exportStatus = "Export failed: \(error.localizedDescription)"
                }
            } else {
                exportStatus = "No folder selected."
            }
            isExporting = false
            return
        }

        let directory = panel.url!
        do {
            try writePack(pack, to: directory)
            exportSuccessURL = directory
            exportStatus = "Saved notebooklm-source.md and cards.json to \(directory.lastPathComponent)."
            IBHaptics.success()
        } catch {
            exportStatus = "Export failed: \(error.localizedDescription)"
        }
        isExporting = false
    }

    private func writePack(_ pack: NotebookPackService.ExportPack, to directory: URL) throws {
        let markdownURL = directory.appendingPathComponent("notebooklm-source.md")
        try pack.markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(pack.cards)
        let jsonURL = directory.appendingPathComponent("cards.json")
        try data.write(to: jsonURL)
    }

    private func workspaceBand<Content: View>(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(IBColors.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(IBColors.secondaryText)
                }
            }
            content()
        }
        .padding(.vertical, 4)
    }
}

private extension Int {
    func nonZeroOrDefault(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}
