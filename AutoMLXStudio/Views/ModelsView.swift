import SwiftUI // Supplies the native macOS model registry interface.
import AppKit // Supplies folder selection and Finder reveal actions.

struct ModelsView: View { // Displays persisted V0.2 physical models and their real runtime state.
    @EnvironmentObject private var appState: AppState // Reads and mutates the observable model registry through controlled AppState actions.
    @State private var dependencyStatuses: [RuntimeDependencyStatus] = [] // Stores read-only backend discovery results for this Models surface.
    @State private var installationReports: [String: ModelInstallationReport] = [:] // Stores reusable audited file, lock, and runtime classifications for each visible model.
    private let resourceBudget = ResourceBudget.current() // Displays the same host-derived conservative budget formula used by ModelResourceManager.

    var body: some View { // Defines the complete Models destination.
        ScrollView { // Keeps the catalog usable in shorter desktop windows.
            VStack(alignment: .leading, spacing: 22) { // Matches the established Dashboard and Agents spacing rhythm.
                header // Shows page identity and the offline refresh action.
                runtimeSection // Shows the one-active-model memory rule and current runtime facts.
                dependencySection // Shows text, Vision, and Voice dependency availability independently.
                registrySection // Shows every requested V0.2, V0.3, V0.4, and migrated legacy profile.
            } // Ends the Models page stack.
            .padding(24) // Matches existing detail-page insets.
            .frame(maxWidth: .infinity, alignment: .leading) // Keeps the operational content aligned to the native detail surface.
        } // Ends the scrollable Models surface.
        .background(Color(nsColor: .windowBackgroundColor)) // Preserves dark and light native macOS appearances.
        .task { await refreshDiagnostics() } // Discovers configured environment dependencies and read-only model installation evidence together.
    } // Ends the Models view body.

    private var header: some View { // Renders the destination title and explicit offline behavior.
        HStack(alignment: .top, spacing: 18) { // Aligns explanatory copy with the catalog refresh action.
            VStack(alignment: .leading, spacing: 5) { // Matches the existing top-level heading cadence.
                Text("Models") // Names the V0.2 sidebar destination.
                    .font(.largeTitle.bold()) // Uses the established page-title hierarchy.
                Text("Installed local model catalog, assignments, and single-server runtime state.") // States exactly what this surface controls.
                    .foregroundStyle(.secondary) // Keeps supporting copy visually subordinate.
                Text(appState.modelRegistry.modelsRoot) // Shows the exact offline detection root.
                    .font(.caption.monospaced()) // Makes a filesystem path easy to scan and copy.
                    .foregroundStyle(.secondary) // Keeps path detail subordinate.
                    .textSelection(.enabled) // Allows users to copy the folder path.
            } // Ends Models heading copy.
            Spacer() // Pushes the secondary refresh action to the trailing edge.
            Button("Refresh catalog", systemImage: "arrow.clockwise") { // Uses a native verb-plus-object action.
                appState.refreshModelInstallations() // Re-runs deterministic offline installation detection.
                Task { await refreshDiagnostics() } // Refreshes dependency and installation-auditor evidence in the same explicit action.
            } // Ends refresh action.
            .buttonStyle(.bordered) // Keeps refresh secondary to model actions.
            .disabled(appState.activeProcessDescription != nil) // Avoids changing installation state while a model transition is active.
        } // Ends header layout.
    } // Ends Models header.

    private var runtimeSection: some View { // Summarizes the one-large-text-model runtime invariant.
        GroupBox("Runtime") { // Uses one native grouped surface instead of metric cards.
            HStack(alignment: .center, spacing: 22) { // Arranges active model, server, policy, and memory rule in one scannable row.
                labeledRuntimeValue("Loaded model", activeModelName, symbol: appState.activeModelID == nil ? "circle" : "checkmark.circle.fill") // Shows the authoritative one loaded model.
                Divider() // Separates runtime fields using the existing component vocabulary.
                    .frame(height: 34) // Keeps the divider proportional to the compact row.
                labeledRuntimeValue("Server", appState.serverRunning ? "Port \(appState.serverPort)" : "Offline", symbol: "network") // Shows actual endpoint availability.
                Divider() // Separates the next runtime field.
                    .frame(height: 34) // Keeps the divider compact.
                labeledRuntimeValue("Switch policy", appState.modelSwitchPolicy.displayName, symbol: "arrow.triangle.swap") // Shows the persisted deterministic policy.
                Divider() // Separates switching policy from host-aware memory budget.
                    .frame(height: 34) // Keeps the divider compact.
                labeledRuntimeValue("Model budget", byteCount(resourceBudget.usableForModelsBytes), symbol: "memorychip") // Shows actual usable bytes after the conservative system reserve.
                Spacer(minLength: 12) // Gives the invariant explanation flexible trailing space.
                Label("One large Text or Vision model; Audio only when budget-safe", systemImage: "checkmark.shield") // States the complete residency invariant explicitly.
                    .font(.callout) // Keeps operational guidance readable but restrained.
                    .foregroundStyle(.secondary) // Avoids decorative emphasis.
            } // Ends runtime summary row.
            .padding(8) // Matches existing GroupBox internal spacing.
        } // Ends runtime summary container.
    } // Ends runtime section.

    private var dependencySection: some View { // Separates runtime package availability from model installation state.
        GroupBox("Backend dependencies") { // Uses a compact native grouped surface consistent with the existing Models page.
            VStack(alignment: .leading, spacing: 8) { // Lists the registered adapters in deterministic order.
                ForEach(dependencyStatuses, id: \.backend) { status in // Renders one authoritative result per backend.
                    HStack(spacing: 8) { // Aligns state, backend identity, and concrete detail.
                        Image(systemName: status.isAvailable ? "checkmark.circle.fill" : "xmark.circle") // Communicates dependency state without relying on color alone.
                            .foregroundStyle(status.isAvailable ? .green : .secondary) // Uses restrained semantic state color.
                        Text(status.backend.displayName) // Shows the exact backend family.
                            .font(.callout.weight(.medium)) // Makes backend identity scannable.
                            .frame(width: 92, alignment: .leading) // Aligns details across the compact list.
                        Text(status.detail) // Shows discovered entrypoint or required missing package.
                            .font(.caption) // Keeps operational evidence subordinate.
                            .foregroundStyle(.secondary) // Preserves native hierarchy.
                            .textSelection(.enabled) // Allows copying exact dependency diagnostics.
                        Spacer() // Keeps the detail aligned to the leading edge.
                    } // Ends dependency result row.
                } // Ends backend dependency iteration.
            } // Ends dependency list.
            .padding(8) // Matches the Runtime GroupBox inset.
        } // Ends backend dependency container.
    } // Ends backend dependency section.

    private var registrySection: some View { // Displays every actual ModelRegistry profile.
        GroupBox("Model registry") { // Uses one native list container rather than repeated cards.
            VStack(spacing: 0) { // Builds a dense, stable catalog list.
                ForEach(Array(appState.modelRegistry.models.enumerated()), id: \.element.id) { index, profile in // Reads the persisted registry in stable order.
                    if index > 0 { Divider() } // Separates profiles without nested containers.
                    modelRow(profile) // Renders physical identity, state, path, capabilities, and actions.
                } // Ends model registry iteration.
            } // Ends dense model list.
            .padding(.vertical, 2) // Adds restrained breathing room inside the GroupBox.
        } // Ends model registry container.
    } // Ends model registry section.

    private func modelRow(_ profile: ModelProfile) -> some View { // Renders one persisted model profile and its supported actions.
        VStack(alignment: .leading, spacing: 10) { // Keeps identity, technical metadata, controls, and feedback together.
            HStack(alignment: .top, spacing: 14) { // Aligns model identity with state badges and actions.
                Image(systemName: backendSymbol(profile.backend)) // Uses a semantic native symbol for the runtime backend.
                    .font(.title3) // Gives backend identity enough scanning presence.
                    .foregroundStyle(.secondary) // Avoids decorative accent color.
                    .frame(width: 28) // Aligns every model row.
                    .accessibilityHidden(true) // Leaves adjacent text as the meaningful accessible label.
                VStack(alignment: .leading, spacing: 3) { // Groups display name and exact repository.
                    HStack(spacing: 7) { // Keeps optional legacy identity adjacent to the model name.
                        Text(profile.displayName) // Shows concise catalog identity.
                            .font(.headline) // Establishes row hierarchy.
                        if profile.isLegacyFallback { // Identifies the compatibility model without changing its normal controls.
                            Text("Legacy fallback") // Explains the V0.1 migration role.
                                .font(.caption.weight(.medium)) // Keeps the badge compact.
                                .padding(.horizontal, 7) // Creates a familiar native tag silhouette.
                                .padding(.vertical, 2) // Keeps tag height restrained.
                                .background(.quaternary) // Uses a neutral native state surface.
                                .clipShape(Capsule()) // Uses pill geometry only for a short badge.
                        } // Ends legacy badge display.
                    } // Ends name and badge row.
                    Text(profile.repositoryID) // Shows the exact physical repository identifier.
                        .font(.caption.monospaced()) // Distinguishes machine identity from display copy.
                        .foregroundStyle(.secondary) // Keeps repository detail subordinate.
                        .textSelection(.enabled) // Allows copying the repository ID.
                } // Ends model identity group.
                .frame(maxWidth: .infinity, alignment: .leading) // Gives long repositories available width.
                installationLabel(profile) // Shows installed, absent, or invalid state with text and symbol.
                healthLabel(profile) // Shows observation-based Unknown, Healthy, Degraded, Unavailable, or Downloading state.
                runtimeLabel(profile) // Shows loaded, loading, unloaded, failed, or unavailable state.
                Toggle("Enabled", isOn: enabledBinding(profile.id)) // Provides the requested enable/disable action with a native control.
                    .toggleStyle(.switch) // Uses the standard macOS switch vocabulary.
                    .labelsHidden() // Avoids repeating the adjacent state context visually.
                    .help(profile.enabled ? "Disable model" : "Enable model") // Preserves an explicit accessible hover label.
            } // Ends model identity and state row.

            HStack(alignment: .firstTextBaseline, spacing: 18) { // Arranges backend, capability, disk, and memory metadata compactly.
                metadataValue("Backend", profile.backend.displayName) // Shows the runtime family independently from the agent.
                metadataValue("Capabilities", capabilityText(profile.capabilities), flexible: true) // Shows every typed future-capable role.
                metadataValue("Disk", diskText(profile.approximateDiskGB)) // Shows detected physical size when available.
                metadataValue("Memory estimate", memoryText(profile.approximateMemoryGB)) // Shows informational unified-memory planning context.
            } // Ends technical metadata row.
            .padding(.leading, 42) // Aligns metadata with text rather than the backend icon.

            HStack(spacing: 10) { // Shows local path and requested model actions on one desktop-native row.
                Text(profile.localPath ?? "Repository-backed legacy model") // Shows the exact local folder or migration behavior.
                    .font(.caption.monospaced()) // Keeps filesystem text precise.
                    .foregroundStyle(.secondary) // Keeps path visually subordinate.
                    .lineLimit(1) // Prevents a long external-volume path from inflating row height.
                    .truncationMode(.middle) // Preserves both root volume and model folder name.
                    .help(profile.localPath ?? profile.repositoryID) // Exposes the complete path or repository on hover.
                    .textSelection(.enabled) // Allows copying the configured local path.
                    .frame(maxWidth: .infinity, alignment: .leading) // Gives path text flexible width.
                Button("Select folder…") { chooseFolder(for: profile) } // Provides the requested manual local folder action.
                    .disabled(appState.activeProcessDescription != nil) // Prevents path mutation during a model transition.
                Button("Reveal in Finder") { reveal(profile) } // Provides the requested native folder reveal action.
                    .disabled(!canReveal(profile)) // Avoids a Finder action for absent folders.
                Menu("Set preferred") { // Provides capability-level preference actions without a modal.
                    ForEach(profile.capabilities.sorted(by: { $0.displayName < $1.displayName }), id: \.self) { capability in // Lists stable readable capability choices.
                        Button { appState.setPreferredModel(profile.id, for: capability) } label: { // Persists one capability default.
                            if appState.modelRegistry.preferredModelID(for: capability) == profile.id { Label(capability.displayName, systemImage: "checkmark") } // Shows current preference with a native checkmark.
                            else { Text(capability.displayName) } // Shows an available capability action.
                        } // Ends capability preference button.
                    } // Ends capability menu iteration.
                } // Ends capability preference menu.
                Button(testActionLabel(profile)) { appState.testModel(profile.id) } // Runs text inference or backend-specific Vision/Voice validation as appropriate.
                    .buttonStyle(.borderedProminent) // Gives the row's primary validation action clear emphasis.
                    .disabled(!canTest(profile)) // Enables Test only for installed, enabled V0.2 text models when no other work is active.
            } // Ends model path and actions row.
            .padding(.leading, 42) // Aligns actions with text content.

            if let test = appState.modelTestResults[profile.id] { // Shows real Test progress or result inline.
                testResult(test) // Renders measured load and inference timing or failure detail.
                    .padding(.leading, 42) // Aligns feedback with the row content.
            } else if let detail = installationDetail(profile) { // Shows reusable auditor diagnostics before a Test action exists.
                Label(detail, systemImage: installationReport(profile).status == .invalid ? "exclamationmark.triangle" : "folder.badge.questionmark") // Communicates audited state with text and symbol.
                    .font(.caption) // Keeps diagnostic subordinate to identity.
                    .foregroundStyle(installationReport(profile).status == .invalid ? .orange : .secondary) // Uses semantic warning color only for invalid contents.
                    .padding(.leading, 42) // Aligns diagnostic with row content.
            } // Ends optional result or validation diagnostic display.
        } // Ends one model row stack.
        .padding(.horizontal, 8) // Aligns content inside the GroupBox border.
        .padding(.vertical, 12) // Provides comfortable dense desktop spacing.
    } // Ends model row rendering.

    private func labeledRuntimeValue(_ label: String, _ value: String, symbol: String) -> some View { // Creates one compact runtime summary field.
        HStack(spacing: 8) { // Aligns semantic symbol with label and value.
            Image(systemName: symbol) // Shows non-color operational state.
                .foregroundStyle(value == "Offline" ? Color.secondary : Color.green) // Uses green only for an active positive state.
                .accessibilityHidden(true) // Leaves combined text as the accessible value.
            VStack(alignment: .leading, spacing: 2) { // Groups field label and current value.
                Text(label) // Shows the runtime field name.
                    .font(.caption) // Keeps label subordinate.
                    .foregroundStyle(.secondary) // Uses native secondary hierarchy.
                Text(value) // Shows the current real runtime value.
                    .font(.callout.weight(.medium)) // Makes the value scannable.
                    .lineLimit(1) // Keeps the summary row compact.
            } // Ends runtime value text.
        } // Ends compact runtime field.
        .accessibilityElement(children: .combine) // Presents label and value as one accessible unit.
    } // Ends runtime value rendering.

    private func metadataValue(_ label: String, _ value: String, flexible: Bool = false) -> some View { // Creates a consistent technical metadata field.
        VStack(alignment: .leading, spacing: 2) { // Groups metadata label and value.
            Text(label) // Shows the technical field name.
                .font(.caption2) // Keeps dense metadata labels subordinate.
                .foregroundStyle(.secondary) // Uses native secondary text.
            Text(value) // Shows actual typed metadata.
                .font(.caption) // Keeps the registry readable at desktop density.
                .lineLimit(1) // Prevents metadata from changing row rhythm.
        } // Ends metadata text group.
        .frame(maxWidth: flexible ? .infinity : nil, alignment: .leading) // Gives only capabilities flexible width.
    } // Ends metadata field rendering.

    private func installationLabel(_ profile: ModelProfile) -> some View { // Shows installation state with text and symbol.
        let report = installationReport(profile) // Resolves the reusable file-and-runtime classification for this model.
        return Label(report.status.displayName, systemImage: installationSymbol(report.status)) // Uses non-color state communication.
            .font(.caption.weight(.medium)) // Keeps state compact and scannable.
            .foregroundStyle(report.status == .complete ? .green : report.status == .invalid ? .orange : .secondary) // Applies semantic color in addition to text.
            .frame(width: 150, alignment: .leading) // Accommodates the precise downloading and runtime-unavailable labels.
    } // Ends installation state label.

    private func installationReport(_ profile: ModelProfile) -> ModelInstallationReport { // Resolves cached audit evidence with a safe synchronous fallback during first render.
        if let report = installationReports[profile.id] { return report } // Reuses the explicit refresh result when available.
        let status: ModelInstallationStatus // Declares a lightweight persisted-state bridge used only before the background audit completes.
        switch profile.installationState { // Maps existing launch state without recursively scanning a multi-gigabyte directory on the render path.
        case .installed: status = runtimeAvailable(for: profile.backend) == false ? .runtimeUnavailable : .complete // Preserves runtime dependency evidence when it is already known.
        case .notInstalled: status = .notInstalled // Preserves an absent external volume or model folder.
        case .downloading: status = .downloading // Preserves the explicitly incomplete transfer state.
        case .invalid: status = .invalid // Preserves malformed or incomplete persisted validation state.
        } // Ends lightweight status mapping.
        return ModelInstallationReport(modelID: profile.id, status: status, diskBytes: UInt64(max(0, (profile.approximateDiskGB ?? 0) * 1_073_741_824)), missingFiles: [], activeLocks: [], warnings: profile.statusDetail.map { [$0] } ?? []) // Avoids synchronous filesystem work while providing honest initial UI metadata.
    } // Ends installation-report resolution.

    private func installationDetail(_ profile: ModelProfile) -> String? { // Produces bounded exact gaps and lock evidence for an unavailable model row.
        let report = installationReport(profile) // Reads one consistent classification and evidence value.
        guard report.status != .complete else { return nil } // Avoids adding diagnostic clutter to launch-ready rows.
        let missing = report.missingFiles.isEmpty ? nil : "Missing: \(report.missingFiles.prefix(5).joined(separator: ", "))." // Bounds required-artifact detail for dense rows.
        let locks = report.activeLocks.isEmpty ? nil : "Lock files detected: \(report.activeLocks.count); files were left untouched." // Reports exact lock count without exposing private paths in the default row.
        let warning = report.warnings.first // Selects one stable non-fatal explanation when no stronger evidence exists.
        let pieces = [missing, locks, warning, profile.statusDetail].compactMap { $0 } // Combines reusable evidence with the existing persisted fallback diagnostic.
        return pieces.first // Keeps the row concise while the status label retains the exact classification.
    } // Ends installation-detail formatting.

    private func runtimeAvailable(for backend: ModelBackend) -> Bool? { // Resolves backend dependency availability when discovery has completed.
        dependencyStatuses.first(where: { $0.backend == backend })?.isAvailable // Returns nil during first render and a concrete result afterward.
    } // Ends backend runtime availability lookup.

    private func refreshDiagnostics() async { // Refreshes dependency and model installation state as one explicit read-only operation.
        let statuses = await appState.runtimeDependencyStatuses() // Discovers the configured Python environment without imports or writes.
        dependencyStatuses = statuses // Publishes dependency evidence before building backend-aware reports.
        let profiles = appState.modelRegistry.models // Captures immutable value metadata before leaving the main actor for filesystem inspection.
        installationReports = await Task.detached(priority: .utility) { // Keeps recursive model-directory inspection away from the SwiftUI render and interaction path.
            Dictionary(uniqueKeysWithValues: profiles.map { profile in // Audits every stable catalog profile using the matching runtime state.
            let runtime = statuses.first(where: { $0.backend == profile.backend })?.isAvailable // Resolves runtime availability for implemented backends.
            return (profile.id, ModelInstallationAuditor.report(for: profile, runtimeAvailable: runtime)) // Stores the complete read-only report by stable model ID.
            }) // Ends installation-report dictionary construction.
        }.value // Publishes the completed read-only audit atomically on the main actor.
    } // Ends Models diagnostics refresh.

    private func runtimeLabel(_ profile: ModelProfile) -> some View { // Shows the latest resource-manager lifecycle state.
        Label(profile.runtimeState.displayName, systemImage: runtimeSymbol(profile.runtimeState)) // Uses a native lifecycle symbol and explicit text.
            .font(.caption.weight(.medium)) // Keeps state compact.
            .foregroundStyle(profile.runtimeState == .loaded ? .green : profile.runtimeState == .failed ? .red : profile.runtimeState == .loading || profile.runtimeState == .stopping ? .orange : .secondary) // Uses restrained semantic lifecycle color.
            .frame(width: 90, alignment: .leading) // Aligns runtime states across rows.
    } // Ends runtime state label.

    private func healthLabel(_ profile: ModelProfile) -> some View { // Classifies only actual installation, dependency, runtime, and explicit Test observations.
        let health = displayedHealth(for: profile) // Resolves one conservative non-persisted health value.
        return Label(health.rawValue, systemImage: health.symbol) // Communicates health with both text and a semantic native symbol.
            .font(.caption.weight(.medium)) // Keeps health compact beside installation and lifecycle state.
            .foregroundStyle(health.color) // Applies restrained semantic color in addition to explicit text.
            .frame(width: 105, alignment: .leading) // Aligns the five health states across model rows.
            .help(health.detail) // Explains which concrete observation supports the current classification.
    } // Ends model health label.

    private func displayedHealth(for profile: ModelProfile) -> DisplayedModelHealth { // Derives health without filesystem work, inference, or one-cancellation degradation.
        let report = installationReport(profile) // Reads the latest explicit offline auditor classification.
        switch report.status { // Gives unavailable structural or dependency evidence precedence over runtime assumptions.
        case .downloading: return .downloading // Preserves incomplete external-transfer evidence without touching locks.
        case .notInstalled, .invalid, .incomplete, .runtimeUnavailable: return .unavailable // Requires complete files and a known runtime dependency before health can be exercised.
        case .complete: break // Continues to actual runtime and explicit test evidence only after structural validation.
        } // Ends installation health gate.
        if let test = appState.modelTestResults[profile.id] { // Uses only an explicit user-triggered validation observation.
            switch test.status { case .succeeded: return .healthy; case .failed: return .degraded; case .running: return .unknown } // Distinguishes completed success/failure from in-progress uncertainty.
        } // Ends explicit test observation.
        if profile.runtimeState == .loaded { return .healthy } // Treats a currently ready managed runtime as positive observed health.
        if profile.runtimeState == .failed { return .degraded } // Treats a recorded non-cancellation runtime failure as degraded rather than structurally unavailable.
        if profile.runtimeState == .unavailable { return .unavailable } // Preserves central resource-manager unavailability evidence.
        return .unknown // Avoids calling a merely installed but never exercised model healthy.
    } // Ends conservative model health derivation.

    private func testResult(_ result: ModelTestResult) -> some View { // Renders actual model test feedback without a modal.
        HStack(alignment: .firstTextBaseline, spacing: 8) { // Aligns state, message, and measured timing.
            Image(systemName: testSymbol(result.status)) // Communicates running, success, or failure nonverbally.
                .foregroundStyle(testColor(result.status)) // Applies semantic test state color.
                .accessibilityLabel(result.status.rawValue.capitalized) // Announces test state to assistive technology.
            Text(result.message) // Shows the concrete test response or error.
                .fixedSize(horizontal: false, vertical: true) // Allows bounded diagnostics to wrap.
            if let load = result.loadMilliseconds { Text("Load \(WorkflowTraceSummaryView.duration(load))").monospacedDigit() } // Shows measured model load time when available.
            if let inference = result.inferenceMilliseconds { Text("Inference \(WorkflowTraceSummaryView.duration(inference))").monospacedDigit() } // Shows measured completion time when available.
        } // Ends inline model test feedback.
        .font(.caption) // Keeps feedback subordinate to model identity.
        .foregroundStyle(result.status == .failed ? .red : .secondary) // Uses explicit error color only for failure.
    } // Ends model test feedback rendering.

    private var activeModelName: String { // Resolves the active model's concise display name.
        guard let activeModelID = appState.activeModelID else { return "None" } // Reports the offline state explicitly.
        return appState.modelRegistry.model(id: activeModelID)?.displayName ?? activeModelID // Uses catalog identity or a safe raw fallback.
    } // Ends active model name resolution.

    private func enabledBinding(_ modelID: String) -> Binding<Bool> { // Creates a controlled Toggle binding without exposing registry mutation to the view.
        Binding(get: { appState.modelRegistry.model(id: modelID)?.enabled ?? false }, set: { appState.setModelEnabled($0, modelID: modelID) }) // Reads current state and delegates persistence to AppState.
    } // Ends enabled-state binding.

    private func canTest(_ profile: ModelProfile) -> Bool { // Applies explicit Test action availability rules.
        profile.enabled && [.mlxLM, .mlxVLM, .mlxAudio].contains(profile.backend) && appState.activeProcessDescription == nil // Allows controlled backend validation even when an incomplete folder or missing package is expected.
    } // Ends Test availability evaluation.

    private func testActionLabel(_ profile: ModelProfile) -> String { // Makes each action describe the backend behavior it validates.
        switch profile.backend { // Selects a concise backend-specific label.
        case .mlxLM: return "Test Text" // Runs real load and bounded completion.
        case .mlxVLM: return "Test Vision" // Runs installation and mlx-vlm dependency validation only.
        case .mlxAudio where profile.capabilities.contains(.speechToText): return "Test Transcription" // Labels the dedicated ASR model action precisely.
        case .mlxAudio where profile.capabilities.contains(.textToSpeech): return "Test Speech" // Labels the dedicated TTS model action precisely.
        case .mlxAudio: return "Test Audio" // Uses a bounded fallback for future general audio models.
        case .embedding, .reranker: return "Unavailable" // Keeps out-of-scope future backends explicit.
        } // Ends test-label selection.
    } // Ends backend-specific test label.

    private func canReveal(_ profile: ModelProfile) -> Bool { // Checks whether Finder can reveal the configured folder.
        guard let localPath = profile.localPath else { return false } // Requires a physical local path.
        return FileManager.default.fileExists(atPath: localPath) // Enables reveal only for an existing path.
    } // Ends Finder action availability.

    private func chooseFolder(for profile: ModelProfile) { // Presents the native macOS local model folder picker.
        let panel = NSOpenPanel() // Creates the standard macOS open panel.
        panel.canChooseDirectories = true // Allows physical model folders.
        panel.canChooseFiles = false // Prevents choosing an individual weight or config file.
        panel.allowsMultipleSelection = false // Keeps one local path per model profile.
        panel.prompt = "Select Model Folder" // Uses a precise verb-plus-object confirmation label.
        if let localPath = profile.localPath { panel.directoryURL = URL(fileURLWithPath: localPath, isDirectory: true).deletingLastPathComponent() } // Opens near the expected Project 5 folder when available.
        if panel.runModal() == .OK, let url = panel.url { appState.setModelLocalPath(url.path, modelID: profile.id) } // Stores and validates the selected folder atomically.
    } // Ends native folder selection.

    private func reveal(_ profile: ModelProfile) { // Reveals one existing local model folder in Finder.
        guard let localPath = profile.localPath else { return } // Ignores absent local paths safely.
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: localPath, isDirectory: true)]) // Uses the standard Finder reveal behavior.
    } // Ends Finder reveal action.

    private func capabilityText(_ capabilities: Set<ModelCapability>) -> String { // Formats typed model capabilities in stable order.
        capabilities.map(\.displayName).sorted().joined(separator: ", ") // Produces a concise deterministic list.
    } // Ends capability formatting.

    private func diskText(_ diskGB: Double?) -> String { // Formats optional detected disk size.
        diskGB.map { String(format: "%.2f GB", $0) } ?? "Unknown" // Shows binary gigabytes or an honest unknown value.
    } // Ends disk-size formatting.

    private func memoryText(_ memoryGB: Double?) -> String { // Formats optional catalog memory estimate.
        memoryGB.map { String(format: "≈ %.1f GB", $0) } ?? "Unknown" // Shows an explicitly approximate value or honest unknown.
    } // Ends memory-estimate formatting.

    private func byteCount(_ bytes: UInt64) -> String { // Formats resource-budget bytes using native binary memory units.
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory) // Returns concise locale-aware model budget text.
    } // Ends resource-budget byte formatting.

    private func backendSymbol(_ backend: ModelBackend) -> String { // Maps runtime families to semantic SF Symbols.
        switch backend { // Selects a symbol for the backend family.
        case .mlxLM: return "text.bubble" // Represents text generation.
        case .mlxVLM: return "eye" // Represents future visual understanding.
        case .mlxAudio: return "waveform" // Represents future speech and audio runtime.
        case .embedding: return "square.grid.3x3" // Represents future vector generation.
        case .reranker: return "arrow.up.arrow.down" // Represents future ranking.
        } // Ends backend-symbol selection.
    } // Ends backend symbol mapping.

    private func installationSymbol(_ state: ModelInstallationStatus) -> String { // Maps reusable installation state to native semantic symbols.
        switch state { // Selects a symbol for installation state.
        case .complete: return "checkmark.circle.fill" // Marks validated local and runtime availability.
        case .downloading: return "arrow.down.circle.dotted" // Marks a present but incomplete folder without treating it as launchable.
        case .notInstalled: return "arrow.down.circle" // Marks an absent optional local model without offering download.
        case .invalid: return "exclamationmark.triangle.fill" // Marks an incomplete folder.
        case .incomplete: return "folder.badge.questionmark" // Marks missing launch artifacts without transfer evidence.
        case .runtimeUnavailable: return "puzzlepiece.extension" // Marks a complete model whose backend dependency is absent.
        } // Ends installation-symbol selection.
    } // Ends installation symbol mapping.

    private func runtimeSymbol(_ state: ModelRuntimeState) -> String { // Maps runtime lifecycle state to native symbols.
        switch state { // Selects a symbol for the current lifecycle state.
        case .installed, .unloaded: return "pause.circle" // Marks a usable but non-resident model.
        case .loading: return "hourglass" // Marks a model currently loading.
        case .loaded: return "checkmark.circle.fill" // Marks the one active model.
        case .stopping: return "stop.circle" // Marks an outgoing server process.
        case .failed: return "xmark.octagon.fill" // Marks a failed load or inference.
        case .unavailable: return "nosign" // Marks a model that cannot currently launch.
        } // Ends runtime-symbol selection.
    } // Ends runtime symbol mapping.

    private func testSymbol(_ status: ModelTestStatus) -> String { // Maps model test lifecycle state to native symbols.
        switch status { // Selects a symbol for the current test state.
        case .running: return "hourglass" // Marks active loading or inference.
        case .succeeded: return "checkmark.circle.fill" // Marks successful non-empty validation.
        case .failed: return "xmark.octagon.fill" // Marks model test failure.
        } // Ends test-symbol selection.
    } // Ends test symbol mapping.

    private func testColor(_ status: ModelTestStatus) -> Color { // Maps model test state to restrained semantic color.
        switch status { // Selects a color for the current test state.
        case .running: return .orange // Marks active work visibly.
        case .succeeded: return .green // Marks success.
        case .failed: return .red // Marks failure.
        } // Ends test-color selection.
    } // Ends test color mapping.
} // Ends the V0.2 Models view.

private enum DisplayedModelHealth: String { // Defines the requested observation-based health vocabulary without changing persisted runtime state.
    case unknown = "Unknown" // Indicates complete installation with no finished validation or ready runtime observation.
    case healthy = "Healthy" // Indicates an explicit successful test or currently ready managed runtime.
    case degraded = "Degraded" // Indicates a recorded non-cancellation test or runtime failure after structural availability.
    case unavailable = "Unavailable" // Indicates absent/incomplete files, missing dependency, disabled launch, or central unavailability.
    case downloading = "Downloading" // Indicates actual auditor evidence of an incomplete externally managed transfer.

    var symbol: String { // Maps health to a native non-color semantic indicator.
        switch self { case .unknown: return "questionmark.circle"; case .healthy: return "heart.circle.fill"; case .degraded: return "exclamationmark.triangle.fill"; case .unavailable: return "nosign"; case .downloading: return "arrow.down.circle.dotted" } // Covers every health state exhaustively.
    } // Ends health symbol mapping.

    var color: Color { // Maps health to restrained semantic color while retaining explicit text.
        switch self { case .healthy: return .green; case .degraded: return .orange; case .unavailable: return .red; case .downloading: return .blue; case .unknown: return .secondary } // Distinguishes observed positive, warning, unavailable, transfer, and unknown states.
    } // Ends health color mapping.

    var detail: String { // Explains the evidence semantics behind each health label.
        switch self { case .unknown: return "Installation is complete, but no successful runtime observation has been recorded."; case .healthy: return "A ready runtime or explicit model test succeeded."; case .degraded: return "A non-cancellation runtime or explicit model test failed after installation validation."; case .unavailable: return "Required model files or runtime dependency are unavailable."; case .downloading: return "The local folder contains evidence of an incomplete externally managed download." } // Produces one bounded explanation per state.
    } // Ends health detail mapping.
} // Ends displayed model health vocabulary.
