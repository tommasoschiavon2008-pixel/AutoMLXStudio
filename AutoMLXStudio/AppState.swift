import Combine // Supplies observation forwarding from the dedicated workspace controller into the app-wide SwiftUI environment object.
import Foundation // Supplies persistence, URLs, dates, and structured concurrency used by application state.
import SwiftUI // Supplies ObservableObject publication and application navigation state.

@MainActor
final class AppState: ObservableObject {
    @Published var selection: SidebarItem? = .dashboard
    @Published var mlxRepoPath: String
    @Published var modelIdentifier: String
    @Published var outputModelPath: String
    @Published var serverPort: Int
    @Published var autoSelectFreePort: Bool
    @Published var hardware = HardwareProfile()
    @Published var serverRunning = false
    @Published var statusText = "Ready"
    @Published var logText = ""
    @Published private(set) var isGenerating = false // Reports one owned Chat workflow so the UI can expose honest Stop behavior.
    @Published var optimizationProfile: OptimizationProfile = .balanced
    @Published var targetMemoryGB: Double = 12
    @Published var benchmarkResults: [BenchmarkResult] = []
    @Published var activeProcessDescription: String?
    @Published private(set) var workflowHistory: [WorkflowTrace] = [] // Stores real recent orchestration metadata for Chat and Agents views.
    @Published var modelRegistry: ModelRegistry // Stores observable V0.2 catalog, installation, assignment, and runtime state.
    @Published var modelSwitchPolicy: ModelSwitchPolicy = .balanced // Stores the persisted explicit model switching optimization.
    @Published private(set) var activeModelID: String? // Exposes the one physical text model currently loaded.
    @Published private(set) var modelTestResults: [String: ModelTestResult] = [:] // Exposes user-triggered model validation feedback.
    @Published var speakAssistantResponses = false // Stores the explicit opt-in TTS policy; text remains authoritative when speech fails.
    @Published var sendAutomaticallyAfterTranscription = false // Stores the explicit opt-in Voice auto-send policy; editable drafts remain the default.
    @Published var defaultAgentQuality: AgentExecutionQuality = .balanced // Stores the persisted default agent-execution policy independently from model switching.
    @Published var projectContextBudgetPreset: ProjectContextBudgetPreset = .balanced // Stores the persisted bounded Project Memory context policy.

    let mlxService = MLXService()
    let remoteServerStore = RemoteServerStore() // Owns persisted server profiles and Keychain-backed credential access.
    lazy var remoteInferenceBackend = RemoteInferenceBackend(profileProvider: remoteServerStore) // Shares one remote discovery and generation authority.
    lazy var remoteModelsController = RemoteModelsController(store: remoteServerStore, inferenceService: remoteInferenceBackend) // Keeps remote configuration alive when changing pages.
    let hardwareService = HardwareService()
    let agentRegistry = AgentRegistry() // Exposes the centralized V0.1 agent definitions to read-only UI surfaces.
    let workspace = WorkspaceController() // Owns durable projects, conversations, visible messages, and document-ingestion state outside the model runtime.
    private var pendingVoiceTraceEvents: [VoiceServiceTraceEvent] = [] // Carries capture and ASR evidence into the next manually sent request.
    private var workspaceObservation: AnyCancellable? // Forwards nested workspace changes through this existing environment object without duplicating persisted state.
    private var generationTask: Task<Void, Never>? // Retains only the current app-started Chat workflow for exact cooperative cancellation.
    lazy var modelResourceManager = ModelResourceManager(service: mlxService) // Serializes all manual and workflow-driven server transitions.
    let engineeringApprovalBroker = EngineeringApprovalBroker() // Owns exact one-shot decisions for Engineering tools.
    lazy var localInferenceBackend: LocalMLXBackend = { // Shares the existing resource manager rather than creating another MLX process owner.
        let initialConfiguration = runtimeConfiguration // Supplies a stable fallback if the application state has been released.
        return LocalMLXBackend(resourceManager: modelResourceManager, completionClient: MLXCompletionClient(service: mlxService), modelProvider: { [weak self] id in await self?.modelRegistry.model(id: id) }, configurationProvider: { [weak self] in await self?.runtimeConfiguration ?? initialConfiguration }) // Resolves current profiles and configuration without a retain cycle.
    }() // Ends shared local backend construction.
    lazy var engineeringSessionBuilder = EngineeringSessionBuilder(backends: [localInferenceBackend, remoteInferenceBackend], approvalBroker: engineeringApprovalBroker, registryProvider: { [weak self] in self?.modelRegistry ?? ModelRegistry(models: [], assignments: [], legacyFallbackModelID: "") }, remoteModelsProvider: { [weak self] in self?.remoteModelsController.modelsByServerID.values.flatMap { $0 } ?? [] }) // Centralizes immutable run configuration with weak app-state providers.
    lazy var engineeringController = EngineeringController(memoryStore: workspace.memoryStore, sessionBuilder: engineeringSessionBuilder, approvalBroker: engineeringApprovalBroker) // Preserves session, model, project, approvals, and results across sidebar navigation.
    lazy var voiceController = VoiceConversationController( // Owns microphone, real MLX Audio ASR/TTS, and one playback service rather than agents.
        speechToTextService: MLXASRRuntimeAdapter( // Connects actual Qwen3-ASR through the inspected installed mlx-audio entrypoint.
            modelProvider: { [unowned self] in self.modelRegistry.model(id: Project5ModelCatalog.speechToText) }, // Resolves the latest persisted ASR profile at invocation time.
            configurationProvider: { [unowned self] in self.runtimeConfiguration }, // Resolves the latest configured virtual environment at invocation time.
            resourceManager: modelResourceManager // Coordinates ASR coexistence or safe text release centrally.
        ), // Ends production ASR adapter construction.
        textToSpeechService: MLXTTSRuntimeAdapter( // Connects actual Qwen3-TTS through the inspected installed mlx-audio entrypoint.
            modelProvider: { [unowned self] in self.modelRegistry.model(id: Project5ModelCatalog.textToSpeech) }, // Resolves the latest persisted TTS profile at invocation time.
            configurationProvider: { [unowned self] in self.runtimeConfiguration }, // Resolves the latest configured virtual environment at invocation time.
            resourceManager: modelResourceManager // Coordinates TTS coexistence or safe text release centrally.
        ) // Ends production TTS adapter construction.
    ) // Ends real Voice controller construction.
    lazy var workflowEngine = WorkflowEngine( // Builds orchestration outside AppState while reusing its working MLX service.
        client: MLXCompletionClient(service: mlxService), // Adapts the existing local completion endpoint.
        registry: agentRegistry, // Guarantees the engine and Agents view use the same definitions.
        resourceManager: modelResourceManager, // Gives V0.2 workflow stages one authoritative server lifecycle owner.
        visionService: MLXVLMVisionService(resourceManager: modelResourceManager), // Connects actual offline mlx-vlm execution under the same unified-memory authority.
        memoryStore: workspace.memoryStore // Gives the opt-in integrated workflow the exact durable Project Memory authority already owned by WorkspaceController.
    ) // Ends lazy workflow-engine construction.

    init(startsBackgroundTasks: Bool = true) { // Allows graph tests to inspect ownership without starting workspace or hardware bootstrap tasks.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.mlxRepoPath = UserDefaults.standard.string(forKey: "mlxRepoPath")
            ?? "/Volumes/Crucial X9 Pro/app/MLX/mlx-lm-main" // Uses the provided working environment only when no persisted path exists.
        let savedModelIdentifier = UserDefaults.standard.string(forKey: "modelIdentifier")
            ?? "mlx-community/Llama-3.2-3B-Instruct-4bit" // Reads the proven V0.1 setting before V0.2 registry migration.
        self.modelIdentifier = savedModelIdentifier // Preserves the legacy/fallback setting and existing Optimize/Benchmark inputs.
        self.modelRegistry = ModelRegistry.defaultRegistry(legacyIdentifier: savedModelIdentifier) // Creates the offline catalog and migrates the V0.1 model on first launch.
        self.outputModelPath = UserDefaults.standard.string(forKey: "outputModelPath")
            ?? "\(home)/Models/AutoMLX"
        let savedPort = UserDefaults.standard.integer(forKey: "serverPort")
        self.serverPort = savedPort == 0 ? 8080 : savedPort
        if UserDefaults.standard.object(forKey: "autoSelectFreePort") == nil {
            self.autoSelectFreePort = true
        } else {
            self.autoSelectFreePort = UserDefaults.standard.bool(forKey: "autoSelectFreePort")
        }
        if let savedQuality = UserDefaults.standard.string(forKey: "defaultAgentQuality"), let quality = AgentExecutionQuality(rawValue: savedQuality) { self.defaultAgentQuality = quality } // Restores Fast, Balanced, or Thorough while retaining Balanced for older installations.
        if let savedPreset = UserDefaults.standard.string(forKey: "projectContextBudgetPreset"), let preset = ProjectContextBudgetPreset(rawValue: savedPreset) { self.projectContextBudgetPreset = preset } // Restores the bounded context preset while retaining Balanced for older installations.

        loadPersistentState() // Restores benchmarks, user assignments, catalog edits, and switching policy.
        workspaceObservation = workspace.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() } // Makes nested project and conversation mutations refresh existing environment-object views.

        guard startsBackgroundTasks else { return } // Preserves normal app startup and permits read-only dependency-graph inspection in tests.

        Task {
            await workspace.load() // Restores durable project and conversation state independently from hardware discovery.
            hardware = await hardwareService.readProfile()
            targetMemoryGB = max(4, min(12, hardware.memoryGB * 0.75))
        }
    }

    var chatMessages: [ChatMessage] { workspace.messages } // Preserves the existing read-only Chat UI surface while making the durable selected conversation authoritative.


    private var stateFileURL: URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("AutoMLXStudio", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory.appendingPathComponent("state.json")
    }

    private func loadPersistentState() {
        guard let data = try? Data(contentsOf: stateFileURL), let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { // Decodes both V0.1 and V0.2 state because new fields are optional.
            modelRegistry = ModelRegistry.migrated(nil, legacyIdentifier: modelIdentifier) // Keeps first-launch catalog migration explicit when no state file exists.
            return // Leaves existing benchmark defaults unchanged.
        } // Ends persisted-state availability validation.
        benchmarkResults = state.benchmarkResults // Restores the existing benchmark history unchanged.
        modelRegistry = ModelRegistry.migrated(state.modelRegistry, legacyIdentifier: modelIdentifier) // Merges user edits with any missing catalog entries and rechecks installation.
        modelSwitchPolicy = state.modelSwitchPolicy ?? .balanced // Uses the requested balanced V0.2 default for older state files.
        speakAssistantResponses = state.speakAssistantResponses ?? false // Keeps optional response speech disabled for all older installations.
        sendAutomaticallyAfterTranscription = state.sendAutomaticallyAfterTranscription ?? false // Keeps editable Voice drafts as the backward-compatible default.
    }

    private func savePersistentState() {
        let state = PersistedState(benchmarkResults: benchmarkResults, modelRegistry: modelRegistry, modelSwitchPolicy: modelSwitchPolicy, speakAssistantResponses: speakAssistantResponses, sendAutomaticallyAfterTranscription: sendAutomaticallyAfterTranscription) // Persists existing benchmarks, model configuration, and both opt-in Voice policies.
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateFileURL, options: .atomic)
    }

    func saveSettings() {
        modelRegistry.ensureLegacyFallback(identifier: modelIdentifier) // Keeps the editable legacy field synchronized with final model-routing recovery.
        UserDefaults.standard.set(mlxRepoPath, forKey: "mlxRepoPath")
        UserDefaults.standard.set(modelIdentifier, forKey: "modelIdentifier")
        UserDefaults.standard.set(outputModelPath, forKey: "outputModelPath")
        UserDefaults.standard.set(serverPort, forKey: "serverPort")
        UserDefaults.standard.set(autoSelectFreePort, forKey: "autoSelectFreePort")
        UserDefaults.standard.set(defaultAgentQuality.rawValue, forKey: "defaultAgentQuality") // Persists the agent-execution default independently from model switching policy.
        UserDefaults.standard.set(projectContextBudgetPreset.rawValue, forKey: "projectContextBudgetPreset") // Persists only the named safe context preset rather than arbitrary unbounded values.
        savePersistentState() // Persists assignments, catalog edits, and switching policy with the existing Save action.
    }

    var runtimeConfiguration: ModelRuntimeConfiguration { // Builds one immutable server configuration for manual and workflow-driven loads.
        ModelRuntimeConfiguration(executableDirectory: executableDirectory, repoPath: mlxRepoPath, requestedPort: serverPort, autoSelectPort: autoSelectFreePort) // Reuses every existing MLX path and port setting.
    } // Ends runtime configuration access.

    var pythonPath: String {
        "\(mlxRepoPath)/.venv/bin/python"
    }

    var executableDirectory: String {
        "\(mlxRepoPath)/.venv/bin"
    }

    var environmentReady: Bool {
        FileManager.default.isExecutableFile(atPath: pythonPath)
            && FileManager.default.isExecutableFile(atPath: "\(executableDirectory)/mlx_lm.server")
    }

    func appendLog(_ value: String) {
        logText += value
        if !value.hasSuffix("\n") { logText += "\n" }
    }

    func startServer() {
        saveSettings() // Persists paths and synchronizes the legacy fallback before launch.
        guard environmentReady else { statusText = "MLX environment not found"; appendLog("Missing executable: \(pythonPath)"); return } // Preserves the existing environment validation and diagnostic.
        guard !serverRunning else { return } // Avoids duplicate manual starts.
        guard let legacyProfile = modelRegistry.model(id: modelRegistry.legacyFallbackModelID) else { statusText = "Legacy fallback model is unavailable"; return } // Requires the migrated V0.1 profile.
        statusText = "Starting legacy fallback model…" // Makes the exact manual launch behavior clear in V0.2.
        activeProcessDescription = "MLX inference server" // Preserves the existing status-bar activity.
        Task { // Runs the serialized resource transition without blocking the main actor.
            do { // Attempts the same existing server startup through the one V0.2 lifecycle owner.
                let preparation = try await modelResourceManager.prepare(model: legacyProfile, configuration: runtimeConfiguration) { [weak self] text in Task { @MainActor in self?.appendLog(text) } } // Loads the legacy/fallback model and preserves process output.
                serverPort = preparation.port // Stores the actual automatically selected port.
                serverRunning = true // Marks the ready managed endpoint available to Chat.
                activeModelID = preparation.modelID // Shows the exact loaded physical model in Models UI.
                statusText = "MLX server running on port \(preparation.port)" // Preserves familiar runtime status copy.
                activeProcessDescription = nil // Clears the status-bar activity after readiness.
                await synchronizeRuntimeSnapshot() // Mirrors actor lifecycle state into the observable registry.
                saveSettings() // Persists the actual port and V0.2 registry state.
            } catch { // Recovers from validation, port, executable, process, or readiness failure.
                serverRunning = false // Prevents Chat from using a failed endpoint.
                activeModelID = nil // Clears any stale loaded-model badge.
                statusText = error.localizedDescription // Shows the actionable resource-manager diagnostic.
                appendLog(error.localizedDescription) // Preserves the existing deterministic log history.
                activeProcessDescription = nil // Clears the status-bar activity after failure.
                await synchronizeRuntimeSnapshot() // Reflects failed or unavailable state in Models UI.
            } // Ends manual server start recovery.
        } // Ends asynchronous manual server start.
    }

    func stopServer() {
        serverRunning = false // Disables Chat immediately while the actor releases the process.
        statusText = "Stopping server…" // Makes the bounded awaited stop visible.
        activeProcessDescription = "Stopping MLX server" // Shows resource work in the existing status bar.
        Task { // Stops through the same lifecycle owner used by workflow switching.
            await modelResourceManager.stop() // Waits for graceful or bounded forced process termination.
            activeModelID = nil // Clears the one-loaded-model badge.
            statusText = "Server stopped" // Preserves the existing final stop status.
            activeProcessDescription = nil // Clears status-bar activity.
            await synchronizeRuntimeSnapshot() // Marks prior active model unloaded in Models UI.
        } // Ends asynchronous managed stop.
    }

    func sendChat(_ prompt: String) async { // Preserves the text-only V0.1/V0.2 call surface.
        await sendChat(UserRequest(text: prompt)) // Delegates to the typed request path with no attachments.
    } // Ends text-only Chat compatibility.

    func sendChat(_ request: UserRequest) async { // Sends one typed text, image, or future media request through attachment-aware orchestration.
        guard generationTask == nil else { return } // Prevents overlapping workflows from interleaving messages or competing for the one managed model runtime.
        isGenerating = true // Publishes the owned generation before starting persistence, retrieval, or model work.
        let task = Task { [weak self] in guard let self else { return }; await self.performSendChat(request) } // Retains an exact cancellable Void task spanning the complete visible request lifecycle.
        generationTask = task // Makes the exact app-started task available to the Stop action.
        await task.value // Keeps the source-compatible async API complete only after the owned workflow finishes or cancels.
        generationTask = nil // Releases the completed task handle without affecting any resident ready model.
        isGenerating = false // Restores composer availability after every success, partial recovery, failure, or cancellation.
    } // Ends owned typed Chat execution.

    func cancelGeneration() { // Cancels only work started for the current Chat request and never signals unrelated processes.
        generationTask?.cancel() // Propagates cooperative cancellation through retrieval, URLSession inference, Vision, and bounded stage boundaries.
        voiceController.stopPlayback() // Stops only playback owned by this application when response speech has already begun.
        statusText = "Cancelling workflow…" // Gives immediate honest feedback while the task unwinds and preserves any completed specialist candidate.
    } // Ends exact Chat generation cancellation.

    private func performSendChat(_ request: UserRequest) async { // Performs one durable request inside the exact task retained by sendChat.
        let normalizedText = request.text.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes only the visible textual portion.
        guard !normalizedText.isEmpty || !request.attachments.isEmpty else { return } // Allows image-only requests while rejecting a completely empty submission.
        if workspace.selectedConversation == nil { // Handles a send that occurs before first-launch workspace restoration completes.
            do { _ = try await workspace.createConversation(projectID: nil) } // Creates one durable normal conversation rather than an orphan in-memory transcript.
            catch { statusText = "Conversation unavailable"; workspace.errorMessage = error.localizedDescription; return } // Stops before inference when the user message cannot be stored safely.
        } // Ends durable destination recovery.
        let conversationHistory = chatMessages // Captures prior context before appending the current request.
        let visibleText = normalizedText.isEmpty ? "Image attachment" : normalizedText // Gives attachment-only messages an accessible visible label.
        let userMessage = ChatMessage(role: "user", content: visibleText, attachments: request.attachments) // Preserves validated URL-backed attachment metadata on its originating message.
        do { try await workspace.appendMessage(userMessage) } // Persists the visible user request atomically before any expensive model execution.
        catch { statusText = "Could not save message"; workspace.errorMessage = error.localizedDescription; return } // Avoids generating an answer for history the application could not durably associate.
        if Task.isCancelled { statusText = "Workflow cancelled"; return } // Honors Stop before any model selection or process work begins.
        activeProcessDescription = "Multi-model workflow" // Makes serialized model selection and switching visible in the status bar.
        let selectedConversation = workspace.selectedConversation // Captures one coherent durable preference snapshot before asynchronous retrieval and inference begin.
        let workflowOptions = WorkflowRequestOptions( // Builds the explicit V0.5 execution contract without changing any legacy overload.
            conversationID: selectedConversation?.id, // Links the operational trace to the exact durable visible conversation.
            projectID: selectedConversation?.projectID, // Restricts retrieval to the one project associated with this conversation or disables it for normal Chat.
            memoryPreference: selectedConversation?.useProjectMemory, // Honors the visible persisted Project Memory toggle rather than applying an implicit global choice.
            quality: selectedConversation?.qualityOverride ?? defaultAgentQuality, // Applies the per-conversation override first and the persisted application default otherwise.
            contextLimits: projectContextBudgetPreset.limits // Applies the named persisted hard budget selected in Settings.
        ) // Ends the immutable per-request Project Chat execution options.
        let result = await workflowEngine.execute( // Sends Chat through the real orchestration layer instead of direct inference.
            request: UserRequest(text: normalizedText, attachments: request.attachments), // Supplies the normalized typed request without copying media bytes.
            conversationHistory: conversationHistory, // Supplies only conversation messages that existed before the request.
            modelRegistry: modelRegistry, // Supplies persisted V0.2 assignments and installed model state.
            runtimeConfiguration: runtimeConfiguration, // Reuses the existing MLX environment and automatic port selection.
            switchPolicy: modelSwitchPolicy, // Applies the explicit quality-versus-switching policy.
            options: workflowOptions, // Enables real Project Memory, trace linkage, and Fast/Balanced/Thorough behavior for every durable conversation.
            onOutput: { [weak self] text in Task { @MainActor in self?.appendLog(text) } } // Preserves real server transition diagnostics.
        ) // Ends workflow execution.
        let assistantMessage = ChatMessage(role: "assistant", content: result.answer, workflowTraceID: result.trace.id, citations: result.citations, generationStatus: result.generationStatus, agentID: result.trace.specialistID, modelID: result.trace.modelIdentifier) // Links exact trace, grounding, delivery, agent, and physical-model metadata to the durable response.
        do { try await workspace.appendMessage(assistantMessage) } // Persists the best complete or partial visible answer before optional speech or transient UI updates.
        catch { workspace.errorMessage = error.localizedDescription; appendLog("Conversation persistence failed: \(error.localizedDescription)") } // Preserves runtime evidence while reporting the local storage failure explicitly.
        let shouldSpeak = result.generationStatus == .complete && !Task.isCancelled // Prevents cancelled, failed, or partially unwinding output from starting new TTS work.
        let speechEvent = await voiceController.synthesizeAndPlayAssistantResponse(result.answer, enabled: speakAssistantResponses && shouldSpeak) // Runs optional speech only after the assistant text is safely stored.
        let serviceEvents = pendingVoiceTraceEvents + (speechEvent.map { [$0] } ?? []) // Combines prior capture/ASR with post-response TTS service evidence.
        pendingVoiceTraceEvents = [] // Consumes Voice draft trace events exactly once after a manual send.
        let completedTrace = appendingVoiceServiceEvents(serviceEvents, to: result.trace) // Places Voice service steps around the existing agent workflow without calling them agents.
        workflowHistory.insert(completedTrace, at: 0) // Makes the completed trace immediately available to both UI surfaces.
        if workflowHistory.count > 30 { workflowHistory.removeLast(workflowHistory.count - 30) } // Bounds in-memory trace history for V0.1.
        if let speechFailure = voiceController.speechFailureMessage { appendLog("Optional speech failed: \(speechFailure)") } // Preserves TTS diagnostics without replacing the stored assistant response.
        if result.trace.status != .succeeded { appendLog("Workflow \(result.trace.status.rawValue): \(result.trace.steps.filter { $0.status == .failed }.map(\.detail).joined(separator: " | "))") } // Records degraded and failed stages in the existing deterministic log.
        if let actualPort = result.activeServerPort { serverPort = actualPort } // Persists the port selected during the final model transition.
        activeModelID = result.activeModelID // Reflects the physical model left loaded after the workflow.
        serverRunning = result.activeServerPort != nil // Keeps Chat available only while a managed endpoint remains ready.
        statusText = result.generationStatus == .cancelled ? "Workflow cancelled" : result.trace.status == .failed ? "Workflow failed" : "Workflow complete" // Summarizes cancellation separately from runtime failure.
        activeProcessDescription = nil // Clears status-bar activity after all stage transitions.
        await synchronizeRuntimeSnapshot() // Mirrors model lifecycle states into the Models and Agents pages.
        saveSettings() // Persists actual port, assignments, and runtime-independent user configuration.
    } // Ends durable typed Chat execution.

    func consumeVoiceDraftForComposer() -> String? { // Moves a successful transcription into Chat without sending it automatically.
        guard let draft = voiceController.consumeLatestDraft() else { return nil } // Requires one ready controller-owned transcription.
        pendingVoiceTraceEvents = draft.traceEvents // Retains capture and ASR service evidence until the user explicitly sends.
        return draft.text // Returns only the transcript for visible composer insertion.
    } // Ends Voice draft consumption.

    func runtimeDependencyStatuses() async -> [RuntimeDependencyStatus] { // Exposes central read-only backend discovery to Models and verification tests.
        await modelResourceManager.dependencyStatuses(configuration: runtimeConfiguration) // Delegates all backend authority to ModelResourceManager.
    } // Ends runtime dependency status access.

    private func appendingVoiceServiceEvents(_ events: [VoiceServiceTraceEvent], to trace: WorkflowTrace) -> WorkflowTrace { // Integrates service evidence without mutating or relabeling agent execution.
        let serviceSteps = events.map { event in // Converts each Voice service event into the shared operational trace vocabulary.
            WorkflowStep(stage: workflowStage(for: event.kind), name: event.name, detail: event.detail, durationMilliseconds: event.durationMilliseconds, status: workflowStatus(for: event.status)) // Preserves exact service identity, timing, outcome, and privacy-safe detail.
        } // Ends Voice event conversion.
        let prefix = serviceSteps.filter { $0.stage == .microphoneCapture || $0.stage == .speechToText } // Places input services before attachment validation and routing.
        let suffix = serviceSteps.filter { $0.stage == .textToSpeech || $0.stage == .audioPlayback } // Places output services after the stored textual workflow result.
        return WorkflowTrace(id: trace.id, createdAt: trace.createdAt, intent: trace.intent, specialistID: trace.specialistID, specialistName: trace.specialistName, modelIdentifier: trace.modelIdentifier, totalDurationMilliseconds: trace.totalDurationMilliseconds + serviceSteps.reduce(0) { $0 + $1.durationMilliseconds }, status: trace.status, steps: prefix + trace.steps + suffix, modelExecutions: trace.modelExecutions, attachmentMetadata: trace.attachmentMetadata ?? [], conversationID: trace.conversationID, projectID: trace.projectID, quality: trace.quality, memory: trace.memory) // Returns one trace with unchanged agent, Project Memory, association, and quality metadata plus explicit Voice service ordering.
    } // Ends Voice service trace integration.

    private func workflowStage(for kind: VoiceServiceKind) -> WorkflowStage { // Maps service kinds to the existing typed workflow-stage vocabulary.
        switch kind { // Selects the exact non-agent stage.
        case .microphoneCapture: return .microphoneCapture // Maps local recording.
        case .speechToText: return .speechToText // Maps ASR inference.
        case .textToSpeech: return .textToSpeech // Maps optional response synthesis.
        case .audioPlayback: return .audioPlayback // Maps explicit playback.
        } // Ends service-stage mapping.
    } // Ends service-stage conversion.

    private func workflowStatus(for status: VoiceServiceTraceStatus) -> WorkflowStepStatus { // Maps Voice service outcomes without losing skip semantics.
        switch status { // Selects the corresponding shared workflow outcome.
        case .succeeded: return .succeeded // Preserves successful service completion.
        case .skipped: return .skipped // Preserves intentional disabled-policy skips.
        case .failed: return .failed // Preserves controlled service failure.
        } // Ends service-status mapping.
    } // Ends service-status conversion.

    var latestWorkflowTrace: WorkflowTrace? { workflowHistory.first } // Exposes the latest actual workflow without duplicating storage.

    func workflowTrace(id: UUID?) -> WorkflowTrace? { // Resolves metadata for an individual assistant message.
        guard let id else { return nil } // Ignores legacy messages that have no orchestration trace.
        return workflowHistory.first { $0.id == id } // Returns the matching recent trace when it is still retained.
    } // Ends message-to-trace lookup.

    func refreshModelInstallations() { // Rechecks the offline Project 5 folder on explicit user request.
        modelRegistry.refreshInstallationStates() // Validates config, weights, folder state, and disk size for every catalog entry.
        savePersistentState() // Persists refreshed local paths and installation facts.
        statusText = "Model catalog refreshed" // Confirms the deterministic offline scan.
    } // Ends model installation refresh.

    func setModelEnabled(_ enabled: Bool, modelID: String) { // Applies the Models page enable or disable action.
        modelRegistry.setEnabled(enabled, modelID: modelID) // Updates deterministic routing availability.
        savePersistentState() // Persists the user choice immediately.
        if !enabled, activeModelID == modelID { stopServer() } // Unloads a model that can no longer be selected.
    } // Ends model enabled-state update.

    func setModelLocalPath(_ path: String?, modelID: String) { // Applies a manually selected local model folder.
        modelRegistry.setLocalPath(path, modelID: modelID) // Stores and immediately validates the folder.
        savePersistentState() // Persists the offline path and detected state.
        statusText = modelRegistry.model(id: modelID)?.installationState == .installed ? "Local model folder validated" : "Local model folder is not usable" // Reports validation outcome without hiding details in Models UI.
    } // Ends local model folder update.

    func setPreferredModel(_ modelID: String?, forAgent agentID: String) { // Applies an Agents page preferred-model Picker change.
        modelRegistry.setPreferredModel(modelID, forAgent: agentID) // Updates only the separate agent assignment.
        savePersistentState() // Persists the assignment immediately.
        statusText = "Agent model assignment saved" // Confirms the deterministic configuration change.
    } // Ends agent preferred-model update.

    func setPreferredModel(_ modelID: String, for capability: ModelCapability) { // Applies a Models page capability preference action.
        modelRegistry.setPreferredModel(modelID, for: capability) // Stores the capability default independently from agents.
        savePersistentState() // Persists the capability preference immediately.
        statusText = "Preferred \(capability.displayName) model saved" // Confirms the exact preference changed.
    } // Ends capability preferred-model update.

    func compatibleModels(for agent: AgentDefinition) -> [ModelProfile] { // Supplies compatible Picker choices without hiding not-yet-installed catalog entries.
        let requiredBackend: ModelBackend = agent.requiredCapabilities.contains(.vision) ? .mlxVLM : .mlxLM // Keeps Vision assignments on the VLM boundary while all existing text agents remain on MLX LM.
        return modelRegistry.models.filter { profile in profile.backend == requiredBackend && agent.requiredCapabilities.isSubset(of: profile.capabilities) } // Requires the correct backend and every agent capability while leaving installation visible in the label.
    } // Ends compatible agent-model suggestions.

    func resolvedModel(for agent: AgentDefinition) -> ModelProfile? { // Resolves the same actual model Agents UI would receive at this moment.
        guard let selection = try? ModelRouter().selectModel(for: agent, registry: modelRegistry, activeModelID: activeModelID, policy: modelSwitchPolicy, excluding: []) else { return nil } // Applies the production deterministic policy without changing runtime state.
        return modelRegistry.model(id: selection.selectedModelID) // Returns the selected physical model profile for display.
    } // Ends current model resolution preview.

    func fallbackModelNames(for agent: AgentDefinition) -> String { // Formats explicit assignment fallback models for the Agents table.
        guard let assignment = modelRegistry.assignment(for: agent.id) else { return agent.requiredCapabilities.contains(.vision) ? "No text fallback" : "Legacy fallback" } // Handles an incomplete persisted assignment without suggesting an unsafe cross-backend fallback.
        let names = assignment.fallbackModelIDs.compactMap { modelRegistry.model(id: $0)?.displayName } // Resolves stable fallback IDs to concise display names.
        if agent.requiredCapabilities.contains(.vision) { return names.isEmpty ? "No text fallback" : names.joined(separator: ", ") } // Makes the typed Vision boundary explicit and never advertises a text-only fallback.
        return (names + ["Legacy: \(modelRegistry.model(id: modelRegistry.legacyFallbackModelID)?.displayName ?? modelIdentifier)"]).joined(separator: ", ") // Makes the required final V0.1 fallback explicit.
    } // Ends fallback-model formatting.

    func testModel(_ modelID: String) { // Runs the Models page deterministic load-and-completion validation.
        guard let profile = modelRegistry.model(id: modelID) else { return } // Ignores stale model actions safely.
        if profile.backend != .mlxLM { // Uses backend-specific validation without sending a text-only health prompt to Vision or Voice.
            modelTestResults[modelID] = ModelTestResult(modelID: modelID, status: .running, message: "Validating \(profile.backend.displayName) installation and dependency…", loadMilliseconds: nil, inferenceMilliseconds: nil, date: Date()) // Shows immediate backend-specific progress.
            activeProcessDescription = "Testing \(profile.displayName)" // Makes read-only validation visible in the existing status bar.
            Task { // Performs central adapter validation without starting a process or changing the active text model.
                do { // Attempts installation, enablement, backend, and dependency validation.
                    try await modelResourceManager.validateAvailability(model: profile, configuration: runtimeConfiguration) // Reuses the sole backend-adapter authority.
                    modelTestResults[modelID] = ModelTestResult(modelID: modelID, status: .succeeded, message: "\(profile.backend.displayName) installation and runtime dependency are available. Inference launch is not enabled by this foundation.", loadMilliseconds: nil, inferenceMilliseconds: nil, date: Date()) // Reports only what validation proved.
                    statusText = "\(profile.displayName) backend validation passed" // Summarizes the backend-specific result.
                } catch { // Reports incomplete installation or missing optional dependency without disturbing the text server.
                    modelTestResults[modelID] = ModelTestResult(modelID: modelID, status: .failed, message: error.localizedDescription, loadMilliseconds: nil, inferenceMilliseconds: nil, date: Date()) // Shows the exact controlled adapter diagnostic.
                    appendLog("Backend test failed: \(error.localizedDescription)") // Preserves the dependency or installation evidence.
                    statusText = "\(profile.displayName) backend validation failed" // Summarizes the failed read-only validation.
                } // Ends backend-specific validation recovery.
                activeProcessDescription = nil // Clears status-bar activity without changing active model state.
            } // Ends asynchronous backend validation.
            return // Prevents non-text models from reaching the mlx_lm completion endpoint.
        } // Ends non-text backend test path.
        modelTestResults[modelID] = ModelTestResult(modelID: modelID, status: .running, message: "Loading and testing…", loadMilliseconds: nil, inferenceMilliseconds: nil, date: Date()) // Shows immediate progress without a modal.
        activeProcessDescription = "Testing \(profile.displayName)" // Makes physical model work visible in the existing status bar.
        Task { // Runs serialized loading and inference without blocking SwiftUI.
            let previousSnapshot = await modelResourceManager.snapshot() // Captures the user's prior active model and port for restoration.
            let previousProfile = previousSnapshot.activeModelID.flatMap { modelRegistry.model(id: $0) } // Resolves the previous physical model when any.
            do { // Attempts validation, model preparation, and a short non-empty completion.
                let preparation = try await modelResourceManager.prepare(model: profile, configuration: runtimeConfiguration) { [weak self] text in Task { @MainActor in self?.appendLog(text) } } // Loads or reuses the selected model through the one resource manager.
                let inferenceStart = DispatchTime.now().uptimeNanoseconds // Starts inference-only timing.
                let response = try await MLXCompletionClient(service: mlxService).complete(LLMCompletionRequest(serverPort: preparation.port, model: profile.completionModel, systemPrompt: "Return one short plain-text answer. Do not include analysis.", history: [], userPrompt: "Reply with the word OK.", maxTokens: 16)) // Sends a deterministic bounded text-model health prompt.
                let inferenceMilliseconds = Int((DispatchTime.now().uptimeNanoseconds - inferenceStart) / 1_000_000) // Measures non-streaming completion time.
                guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkflowEngineError.emptyResponse(profile.displayName) } // Rejects an HTTP success without usable model output.
                modelTestResults[modelID] = ModelTestResult(modelID: modelID, status: .succeeded, message: "Ready response received. First-token timing is unavailable from the current non-streaming endpoint.", loadMilliseconds: preparation.loadDurationMilliseconds, inferenceMilliseconds: inferenceMilliseconds, date: Date()) // Reports actual load and inference timing without inventing unavailable metrics.
                statusText = "\(profile.displayName) test passed" // Confirms model validation globally.
                await restoreRuntimeAfterModelTest(previousProfile: previousProfile, testedModelID: modelID) // Restores the user's prior managed server state when a switch was necessary.
            } catch { // Recovers from local validation, server loading, or completion failure.
                await modelResourceManager.markFailed(modelID: modelID, reason: error.localizedDescription) // Unloads a model that failed after readiness or validation.
                modelTestResults[modelID] = ModelTestResult(modelID: modelID, status: .failed, message: error.localizedDescription, loadMilliseconds: nil, inferenceMilliseconds: nil, date: Date()) // Shows the concrete bounded failure inline.
                appendLog("Model test failed: \(error.localizedDescription)") // Preserves diagnostics in the existing log.
                statusText = "\(profile.displayName) test failed" // Summarizes the failed action.
                await restoreRuntimeAfterModelTest(previousProfile: previousProfile, testedModelID: modelID) // Restores the user's prior model even after a failed test.
            } // Ends model-test recovery.
            activeProcessDescription = nil // Clears status-bar activity after restoration.
            await synchronizeRuntimeSnapshot() // Mirrors final loaded, unloaded, or failed states into Models UI.
            savePersistentState() // Persists user configuration without persisting a stale loaded process claim.
        } // Ends asynchronous model test.
    } // Ends Models page Test action.

    private func restoreRuntimeAfterModelTest(previousProfile: ModelProfile?, testedModelID: String) async { // Avoids unnecessarily changing the user's running chat model.
        if let previousProfile, previousProfile.id != testedModelID { // Restores a different model that was active before testing.
            do { // Attempts a normal serialized transition back to the user's prior model.
                let restored = try await modelResourceManager.prepare(model: previousProfile, configuration: runtimeConfiguration) { [weak self] text in Task { @MainActor in self?.appendLog(text) } } // Reuses the same validated lifecycle path for restoration.
                serverPort = restored.port // Restores the actual ready endpoint.
                serverRunning = true // Keeps Chat available after successful restoration.
                activeModelID = restored.modelID // Restores the original loaded badge.
            } catch { // Handles a prior model that can no longer be restored.
                appendLog("Could not restore previous model: \(error.localizedDescription)") // Preserves the concrete restoration diagnostic.
                serverRunning = false // Prevents Chat from using an absent endpoint.
                activeModelID = nil // Clears stale loaded identity.
            } // Ends prior-model restoration recovery.
        } else if previousProfile == nil { // Returns to the original offline state when no server was running before Test.
            await modelResourceManager.stop() // Releases the tested model and unified memory.
            serverRunning = false // Restores the prior Chat availability state.
            activeModelID = nil // Clears the tested model loaded badge.
        } else { // Leaves the tested model active when it was already the user's running model.
            let snapshot = await modelResourceManager.snapshot() // Reads its actual ready port after the test.
            serverPort = snapshot.activePort ?? serverPort // Preserves the endpoint when readiness remains valid.
            serverRunning = snapshot.activePort != nil // Reflects actual managed runtime availability.
            activeModelID = snapshot.activeModelID // Reflects actual loaded identity.
        } // Ends model-test state restoration selection.
    } // Ends model-test runtime restoration.

    private func synchronizeRuntimeSnapshot() async { // Mirrors actor-isolated lifecycle facts into observable UI state.
        let snapshot = await modelResourceManager.snapshot() // Reads active identity, port, and all touched model states atomically.
        modelRegistry.applyRuntimeSnapshot(snapshot) // Updates Models and Agents without exposing actor mutation to views.
        activeModelID = snapshot.activeModelID // Updates the global one-loaded-model identity.
        if let activePort = snapshot.activePort { serverPort = activePort } // Keeps automatic free-port selection synchronized.
    } // Ends runtime snapshot synchronization.

    func runDynamicQuantization() {
        saveSettings()
        guard environmentReady else {
            statusText = "MLX environment not found"
            return
        }

        statusText = "Dynamic quantization running…"
        activeProcessDescription = "Dynamic quantization"

        let destination = "\(outputModelPath)-\(optimizationProfile.rawValue.lowercased())"

        mlxService.runDynamicQuantization(
            executableDirectory: executableDirectory,
            repoPath: mlxRepoPath,
            model: modelIdentifier,
            outputPath: destination,
            targetBPW: optimizationProfile.targetBPW,
            lowBits: optimizationProfile.lowBits,
            highBits: optimizationProfile.highBits,
            onOutput: { [weak self] text in
                Task { @MainActor in self?.appendLog(text) }
            },
            onExit: { [weak self] code in
                Task { @MainActor in
                    self?.activeProcessDescription = nil
                    self?.statusText = code == 0 ? "Quantization complete" : "Quantization failed (\(code))"
                }
            }
        )
    }

    func runBenchmark() {
        saveSettings()
        guard environmentReady else {
            statusText = "MLX environment not found"
            return
        }

        statusText = "Benchmark running…"
        activeProcessDescription = "Benchmark"

        mlxService.runBenchmark(
            executableDirectory: executableDirectory,
            repoPath: mlxRepoPath,
            model: modelIdentifier,
            onOutput: { [weak self] text in
                Task { @MainActor in self?.appendLog(text) }
            },
            onResult: { [weak self] result in
                Task { @MainActor in
                    self?.benchmarkResults.insert(result, at: 0)
                    self?.savePersistentState()
                    self?.statusText = "Benchmark complete"
                    self?.activeProcessDescription = nil
                }
            },
            onFailure: { [weak self] error in
                Task { @MainActor in
                    self?.appendLog("Benchmark error: \(error)")
                    self?.statusText = "Benchmark failed"
                    self?.activeProcessDescription = nil
                }
            }
        )
    }
}
