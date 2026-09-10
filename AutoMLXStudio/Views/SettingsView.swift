import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Text("Settings")
                    .font(.largeTitle.bold())
            }

            Section("MLX-LM") {
                TextField("Repository path", text: $appState.mlxRepoPath)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text(appState.environmentReady ? "Environment ready" : "Virtual environment not found")
                        .foregroundStyle(appState.environmentReady ? .green : .red)
                    Spacer()
                    Button("Choose Folder…") {
                        chooseRepoFolder()
                    }
                }

                Text("Expected Python executable: \(appState.pythonPath)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Legacy / Fallback Model") { // Preserves V0.1 configuration while making its V0.2 role explicit.
                TextField("Legacy model identifier", text: $appState.modelIdentifier) // Keeps repository and local path compatibility for final routing recovery.
                    .textFieldStyle(.roundedBorder)

                Picker("Legacy model preset", selection: $appState.modelIdentifier) { // Preserves the existing convenience presets for fallback configuration.
                    Text("Llama 3.2 3B 4-bit")
                        .tag("mlx-community/Llama-3.2-3B-Instruct-4bit")
                    Text("Qwen3 4B 4-bit")
                        .tag("mlx-community/Qwen3-4B-4bit")
                    Text("Custom")
                        .tag(appState.modelIdentifier)
                }

                Text("This model remains the final fallback for every agent and is still used by Optimize and Benchmark. Normal V0.2 assignments are configured in Agents and Models.") // Explains backward compatibility and the new primary path.
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Quantized output base path", text: $appState.outputModelPath)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Model switching") { // Exposes the explicit deterministic V0.2 switching-cost policy.
                Picker("Policy", selection: $appState.modelSwitchPolicy) { // Uses a native persisted policy selector.
                    ForEach(ModelSwitchPolicy.allCases) { policy in // Lists every deterministic policy mode.
                        Text(policy.displayName) // Shows concise policy identity.
                            .tag(policy) // Stores the typed policy value.
                    } // Ends policy choices.
                } // Ends switching policy Picker.
                Text(appState.modelSwitchPolicy.detail) // Explains the exact active quality-versus-latency rule.
                    .font(.caption) // Keeps supporting policy copy subordinate.
                    .foregroundStyle(.secondary) // Uses native secondary hierarchy.
                Text("Only one medium or large text model is kept loaded at a time.") // States the unified-memory invariant explicitly.
                    .font(.caption) // Keeps operational guidance compact.
                    .foregroundStyle(.secondary) // Uses native secondary hierarchy.
            } // Ends model switching Settings section.

            Section("Agent execution") { // Separates inference-stage policy from physical model-switching policy.
                Picker("Default quality", selection: $appState.defaultAgentQuality) { // Stores the default used when a conversation has no explicit override.
                    ForEach(AgentExecutionQuality.allCases) { quality in // Lists the complete bounded policy vocabulary.
                        Text(quality.rawValue).tag(quality) // Shows and stores Fast, Balanced, or Thorough exactly.
                    } // Ends quality choices.
                } // Ends default quality picker.
                Text(agentQualityDescription) // Explains the actual stage policy rather than implying a different physical model.
                    .font(.caption) // Keeps supporting behavior subordinate.
                    .foregroundStyle(.secondary) // Uses native Settings hierarchy.
                Text("A conversation can override this value from the Chat header.") // Documents the narrow per-conversation override surface.
                    .font(.caption) // Keeps override guidance compact.
                    .foregroundStyle(.secondary) // Uses native supporting text.
            } // Ends agent-execution settings.

            Section("Project Memory") { // Groups retrieval bounds and audited optional-runtime availability.
                Picker("Context budget", selection: $appState.projectContextBudgetPreset) { // Stores one safe named preset rather than arbitrary unbounded prompt values.
                    Text("Efficient").tag(ProjectContextBudgetPreset.efficient) // Selects the compact three-chunk policy.
                    Text("Balanced").tag(ProjectContextBudgetPreset.balanced) // Selects the default six-chunk policy.
                    Text("Maximum Quality").tag(ProjectContextBudgetPreset.maximumQuality) // Selects the larger but still bounded ten-chunk policy.
                } // Ends context-budget picker.
                let limits = appState.projectContextBudgetPreset.limits // Resolves actual immutable limits for honest supporting copy.
                Text("Up to \(limits.maxChunks) chunks, \(limits.maxTotalCharacters.formatted()) characters total, \(limits.maxChunksPerDocument) chunks per document.") // Shows concrete current prompt bounds.
                    .font(.caption) // Keeps numerical policy subordinate.
                    .foregroundStyle(.secondary) // Uses native hierarchy.
                LabeledContent("Embedding", value: optionalRetrievalStatus(modelID: Project5ModelCatalog.embedding)) // Reports only actual catalog installation evidence.
                LabeledContent("Reranker", value: optionalRetrievalStatus(modelID: Project5ModelCatalog.reranker)) // Reports only actual catalog installation evidence.
                Text("Deterministic lexical retrieval remains available with no embedding or reranker installed. Project chats default to memory on; normal chats have no project scope.") // States real zero-model functionality and isolation defaults.
                    .font(.caption) // Keeps explanatory copy compact.
                    .foregroundStyle(.secondary) // Preserves native Settings hierarchy.
                Button("Open Project Index Controls") { appState.selection = .projects } // Navigates to source-aware per-document status and safe reindex actions.
                    .help("Open Projects to inspect changed sources and rebuild only the affected document index.") // Avoids advertising a fake global physical embedding rebuild.
            } // Ends Project Memory settings.

            Section("Local server") {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", value: $appState.serverPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }

                Toggle("Automatically choose another free port", isOn: $appState.autoSelectFreePort)

                Text(
                    appState.autoSelectFreePort
                    ? "If this port is busy, AutoMLX Studio will try the next available local port automatically."
                    : "If this port is busy, AutoMLX Studio will stop and report the process using it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Voice") { // Keeps optional response speech separate from model and server configuration.
                Toggle("Send automatically after transcription", isOn: $appState.sendAutomaticallyAfterTranscription) // Exposes the requested opt-in ASR draft policy.
                Text("Off by default. When disabled, the local transcript appears in the composer and remains editable before sending.") // Explains the safe default and exact opt-in effect.
                    .font(.caption) // Keeps supporting behavior subordinate.
                    .foregroundStyle(.secondary) // Preserves the native Settings hierarchy.
                Toggle("Speak assistant responses", isOn: $appState.speakAssistantResponses) // Exposes the requested explicit opt-in TTS policy.
                Text("Off by default. Assistant text is stored first; missing mlx-audio, synthesis, or playback errors never remove the response.") // States the non-destructive service behavior precisely.
                    .font(.caption) // Keeps supporting behavior subordinate.
                    .foregroundStyle(.secondary) // Preserves the native Settings hierarchy.
            } // Ends Voice settings section.

            Section {
                Button("Save Settings") {
                    appState.saveSettings()
                    appState.statusText = "Settings saved"
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseRepoFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            appState.mlxRepoPath = url.path
            appState.saveSettings()
        }
    }

    private var agentQualityDescription: String { // Describes actual agent stages for the selected application default.
        switch appState.defaultAgentQuality { // Selects the exact deterministic execution policy.
        case .fast: return "Fast runs the primary specialist only unless a mandatory service such as Vision is required." // Describes the latency-first plan.
        case .balanced: return "Balanced runs the specialist and reviewer when useful, then preserves the reviewed answer." // Describes the default validation plan.
        case .thorough: return "Thorough runs specialist, reviewer, and final composer with bounded context." // Describes the full bounded plan.
        } // Ends quality description selection.
    } // Ends agent-quality supporting copy.

    private func optionalRetrievalStatus(modelID: String) -> String { // Formats audited optional-model state without triggering discovery or downloads.
        guard let model = appState.modelRegistry.model(id: modelID) else { return "Not installed" } // Reports absent optional catalog entries honestly.
        switch model.installationState { // Maps actual offline installation inspection into concise Settings text.
        case .installed: return "Installed · runtime not validated" // Distinguishes weights from a working physical adapter.
        case .downloading: return "Downloading" // Preserves current inspector evidence without touching lock files.
        case .notInstalled: return "Not installed" // Reports absent files without network suggestions.
        case .invalid: return "Unavailable" // Reports invalid local structure.
        } // Ends optional retrieval-model status mapping.
    } // Ends optional retrieval status formatting.
}
