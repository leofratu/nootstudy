import SwiftUI

/// Isolated input bar + configuration rail so streaming token writes do not invalidate the parent chat view.
/// Only this view and the streaming row observe `ARIAStreamStore`.
struct ARIAChatInputBar: View {
    var streamStore: ARIAStreamStore
    @Binding var inputText: String

    let selectedProvider: AIProviderKind
    let selectedModel: String
    let selectedReasoningEffort: AIReasoningEffort
    let selectedVerbosity: AIResponseVerbosity
    let selectedWebSearchMode: AIWebSearchMode
    let geminiCreativityName: String

    @Binding var reasoningEffortRaw: String
    @Binding var verbosityRaw: String
    @Binding var webSearchModeRaw: String
    @Binding var ariaTemperature: Double

    let onSend: (String) -> Void
    let onCancel: () -> Void
    let onSelectProvider: (AIProviderKind) -> Void
    let onSetModel: (String) -> Void

    var body: some View {
        VStack(spacing: 9) {
            configurationRail

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask ARIA…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .onSubmit { onSend(inputText) }
                    .disabled(streamStore.isLoading)

                Button {
                    if streamStore.isLoading {
                        onCancel()
                    } else {
                        onSend(inputText)
                    }
                } label: {
                    let canSend = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || streamStore.isLoading
                    Image(systemName: streamStore.isLoading ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Group {
                                if canSend {
                                    Circle().fill(IBGradient.accent)
                                } else {
                                    Circle().fill(IBColors.tertiaryText.opacity(0.45))
                                }
                            }
                            .shadow(color: canSend ? IBColors.electricBlue.opacity(0.3) : .clear, radius: 6, x: 0, y: 2)
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !streamStore.isLoading)
                .help(streamStore.isLoading ? "Stop response" : "Send message")
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(IBColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(IBColors.cardBorder, lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(IBColors.canvas)
    }

    private var configurationRail: some View {
        HStack(spacing: 8) {
            Menu {
                Section("Provider") {
                    ForEach(AIProviderKind.allCases) { provider in
                        Button {
                            onSelectProvider(provider)
                        } label: {
                            Label(
                                provider.displayName,
                                systemImage: provider == selectedProvider ? "checkmark" : provider.symbolName
                            )
                        }
                    }
                }

                Section("Model") {
                    ForEach(AIConfiguration.knownModels[selectedProvider] ?? []) { option in
                        Button {
                            onSetModel(option.id)
                        } label: {
                            Label(
                                "\(option.name) · \(option.role)",
                                systemImage: option.id == selectedModel ? "checkmark" : "cpu"
                            )
                        }
                    }

                    if !(AIConfiguration.knownModels[selectedProvider] ?? []).contains(where: { $0.id == selectedModel }) {
                        Text("Custom: \(selectedModel)")
                    }
                }

                if selectedProvider == .gemini {
                    Section("Response style") {
                        Button {
                            ariaTemperature = 0.2
                        } label: {
                            Label("Precise", systemImage: geminiCreativityName == "Precise" ? "checkmark" : "scope")
                        }
                        Button {
                            ariaTemperature = 0.7
                        } label: {
                            Label("Balanced", systemImage: geminiCreativityName == "Balanced" ? "checkmark" : "dial.medium")
                        }
                        Button {
                            ariaTemperature = 1.1
                        } label: {
                            Label("Exploratory", systemImage: geminiCreativityName == "Exploratory" ? "checkmark" : "wand.and.stars")
                        }
                    }
                } else {
                    Section("Reasoning") {
                        ForEach(AIConfiguration.supportedReasoningEfforts(for: selectedProvider)) { effort in
                            Button {
                                reasoningEffortRaw = effort.rawValue
                            } label: {
                                let isSelected = effort == selectedReasoningEffort
                                Label(
                                    effort.displayName,
                                    systemImage: isSelected ? "checkmark" : "brain.head.profile"
                                )
                            }
                        }
                    }

                    Section("Answer detail") {
                        ForEach(AIResponseVerbosity.allCases) { verbosity in
                            Button {
                                verbosityRaw = verbosity.rawValue
                            } label: {
                                Label(
                                    verbosity.displayName,
                                    systemImage: verbosity == selectedVerbosity ? "checkmark" : "text.alignleft"
                                )
                            }
                        }
                    }
                }

                if selectedProvider == .codexCLI {
                    Section("Web search") {
                        ForEach(AIWebSearchMode.allCases) { mode in
                            Button {
                                webSearchModeRaw = mode.rawValue
                            } label: {
                                Label(
                                    mode.displayName,
                                    systemImage: mode == selectedWebSearchMode ? "checkmark" : "globe"
                                )
                            }
                        }
                    }
                }
            } label: {
                Label(
                    "\(selectedProvider.shortName) · \(AIConfiguration.modelDisplayName(selectedModel, for: selectedProvider))",
                    systemImage: "slider.horizontal.3"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(IBColors.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Response settings")

            Spacer()

            if streamStore.isLoading {
                Text(streamStore.statusText)
                    .font(.caption)
                    .foregroundStyle(IBColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .disabled(streamStore.isLoading)
    }
}

// Kept for compatibility if parent still references the old name; the consolidated bar above is the source of truth.
struct ARIAChatConfigurationRail: View {
    var streamStore: ARIAStreamStore
    let selectedProvider: AIProviderKind
    let selectedModel: String
    let selectedReasoningEffort: AIReasoningEffort
    let selectedVerbosity: AIResponseVerbosity
    let selectedWebSearchMode: AIWebSearchMode
    let geminiCreativityName: String
    @Binding var reasoningEffortRaw: String
    @Binding var verbosityRaw: String
    @Binding var webSearchModeRaw: String
    @Binding var ariaTemperature: Double
    let onSelectProvider: (AIProviderKind) -> Void
    let onSetModel: (String) -> Void
    var body: some View { EmptyView() }
}
