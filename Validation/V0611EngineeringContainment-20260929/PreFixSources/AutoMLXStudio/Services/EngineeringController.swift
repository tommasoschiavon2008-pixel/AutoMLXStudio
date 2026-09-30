import Combine // Supplies ObservableObject publication for the native Engineering workspace surface.
import Foundation // Supplies URLs, UUIDs, tasks, dates, and bounded string handling.

struct EngineeringSessionComponents: Sendable { // Bundles the exact actors owned by one Engineering run without exposing implementation details to SwiftUI.
    let engine: EngineeringAgentEngine // Owns the single bounded model/tool loop for this run.
    let toolRuntime: EngineeringToolRuntime // Owns contained filesystem and exact-child process execution for this run.
} // Ends one concrete Engineering session bundle.

@MainActor // Keeps dependency assembly next to the application state that owns model configuration.
protocol EngineeringSessionBuilding { // Abstracts local/remote model composition from workspace and UI state management.
    func makeSession(workspace: EngineeringWorkspace, preferredRemoteTarget: ModelGenerationTarget?) throws -> EngineeringSessionComponents // Creates one run-scoped engine and runtime for the authorized workspace.
} // Ends Engineering session construction boundary.

enum EngineeringControllerNoticeKind: Equatable, Sendable { // Distinguishes accessible operational feedback without depending on color alone.
    case information // Represents neutral workspace or session guidance.
    case success // Represents a completed authorization, run, diff, or rollback action.
    case error // Represents a bounded configuration, storage, model, or runtime failure.
} // Ends Engineering notice categories.

struct EngineeringControllerNotice: Identifiable, Equatable, Sendable { // Carries one concise state change to the Engineering view.
    let id: UUID // Gives repeated notices independent announcement identity.
    let kind: EngineeringControllerNoticeKind // Supplies semantic presentation information.
    let message: String // Stores bounded secret-redacted user-facing copy.

    init(kind: EngineeringControllerNoticeKind, message: String) { // Creates one fresh bounded notice.
        self.id = UUID() // Allocates stable SwiftUI identity without deriving it from message data.
        self.kind = kind // Stores the semantic notice category.
        self.message = String(EngineeringSecretRedactor.redact(message).prefix(512)) // Applies secret protection and a concise display bound.
    } // Ends Engineering notice construction.
} // Ends one Engineering controller notice.

@MainActor // Serializes all published application state while heavy work remains inside actors and async services.
final class EngineeringController: ObservableObject { // Coordinates authorized workspaces, bounded sessions, approvals, changes, and optional Project Memory.
    @Published private(set) var workspaces: [EngineeringWorkspaceDescriptor] = [] // Stores durable user-authorized workspace descriptors in recency order.
    @Published private(set) var selectedWorkspaceID: UUID? // Identifies the exact active authorization without exposing a mutable URL.
    @Published var taskText = "" // Stores the visible user engineering objective.
    @Published var quality: AgentExecutionQuality = .balanced // Selects the fixed 8, 16, or 30 turn ceiling.
    @Published var useProjectMemory = false // Keeps knowledge retrieval explicitly opt-in and separate from filesystem authorization.
    @Published var selectedProjectID: UUID? // Identifies the optional isolated Project Memory source.
    @Published var projectContextBudgetPreset: ProjectContextBudgetPreset = .balanced // Applies an existing named hard context budget.
    @Published var prefersRemoteModel = false // Records an explicit remote-primary preference without silently changing execution location.
    @Published var selectedRemoteServerID: UUID? // Identifies the configured server selected by the user.
    @Published var selectedRemoteModelID: String? // Identifies the exact discovered provider model selected by the user.
    @Published private(set) var isLoadingWorkspaces = false // Reports descriptor restoration without blocking the window.
    @Published private(set) var isRunning = false // Reports ownership of one bounded Engineering session.
    @Published private(set) var statusText = "No workspace selected" // Reports concise current Engineering state.
    @Published private(set) var result: EngineeringAgentSessionResult? // Stores the latest complete or partial evidence-based result.
    @Published private(set) var activity: [EngineeringAgentEvent] = [] // Stores trace-safe model and tool events from the latest run.
    @Published private(set) var changes: [EngineeringChangeRecord] = [] // Stores only app-owned reversible transactions for the active workspace.
    @Published var selectedChangeID: UUID? // Identifies the transaction currently shown in the diff pane.
    @Published private(set) var selectedDiff = "" // Stores the bounded Git-independent unified diff for the selected transaction.
    @Published private(set) var pendingApproval: EngineeringApprovalRequest? // Stores the exact command awaiting Allow Once or Deny.
    @Published private(set) var activeModelID: String? // Reports the actual successful model attempt when one exists.
    @Published private(set) var activeBackendID: String? // Reports the actual successful local or remote backend identity.
    @Published var notice: EngineeringControllerNotice? // Exposes one bounded accessible operation result.

    private let workspaceStore: EngineeringWorkspaceStore // Owns durable authorization descriptors outside Project Memory.
    private let memoryRetrievalService: ProjectMemoryRetrievalService // Performs isolated bounded retrieval only after explicit opt-in.
    private let sessionBuilder: any EngineeringSessionBuilding // Assembles run-scoped local/remote inference without transport branching in this controller.
    private let approvalBroker: EngineeringApprovalBroker // Owns exact nonblocking approval continuations for the Mac runtime.
    private var workspace: EngineeringWorkspace? // Retains the actor whose canonical root is the active filesystem authority.
    private var sessionTask: Task<Void, Never>? // Retains only the exact controller-owned run for cooperative Stop.
    private var activeEngine: EngineeringAgentEngine? // Retains the exact engine that Stop may cancel.
    private var activeToolRuntime: EngineeringToolRuntime? // Retains the exact process runtime that Stop may cancel.
    private var approvalObservationTask: Task<Void, Never>? // Retains the one stream consumer that publishes pending approval requests.
    private var activeRunID: UUID? // Prevents late cleanup from an older run clearing a newer session.
    private struct RunConfiguration { // Freezes mutable form fields at the user's Run action.
        let task: String // Stores the exact submitted objective.
        let remoteTarget: ModelGenerationTarget? // Stores the explicitly selected inference target.
        let quality: AgentExecutionQuality // Stores the hard iteration and quality-stage policy.
        let memoryProjectID: UUID? // Stores only an explicitly opted-in Project Memory source.
        let contextPreset: ProjectContextBudgetPreset // Stores the selected context bound.
    } // Ends immutable run inputs.

    init(workspaceStore: EngineeringWorkspaceStore = EngineeringWorkspaceStore(), memoryStore: ProjectMemoryStore, sessionBuilder: any EngineeringSessionBuilding, approvalBroker: EngineeringApprovalBroker) { // Creates the production or injectable Engineering coordinator.
        self.workspaceStore = workspaceStore // Stores the independent workspace authorization catalog.
        self.memoryRetrievalService = ProjectMemoryRetrievalService(memoryStore: memoryStore) // Creates lexical-first optional retrieval over the existing isolated store.
        self.sessionBuilder = sessionBuilder // Stores application-owned model/runtime assembly.
        self.approvalBroker = approvalBroker // Stores the exact approval authority used by the runtime.
        self.approvalObservationTask = Task { [weak self, approvalBroker] in // Starts one lightweight asynchronous request observer.
            let stream = await approvalBroker.requestStream() // Subscribes without blocking the main actor or runtime actor.
            for await request in stream { // Receives only exact typed approval requests.
                guard !Task.isCancelled else { break } // Stops observation when this controller is released or explicitly cancelled.
                self?.pendingApproval = request // Publishes the exact command, risk, workspace, and reason to SwiftUI.
            } // Ends approval-stream consumption.
        } // Ends approval observer creation.
    } // Ends Engineering controller construction.

    deinit { approvalObservationTask?.cancel(); sessionTask?.cancel() } // Releases exact owned observers and work without retaining an orphaned stream consumer.

    var selectedWorkspace: EngineeringWorkspaceDescriptor? { // Resolves the current descriptor from durable published state.
        guard let selectedWorkspaceID else { return nil } // Distinguishes no authorization from an unavailable authorization.
        return workspaces.first { $0.id == selectedWorkspaceID } // Returns only the exact catalog identity.
    } // Ends active workspace descriptor lookup.

    var canRun: Bool { // Reports whether the primary action has all required local state.
        !isRunning && !isLoadingWorkspaces && workspace != nil && !taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!prefersRemoteModel || requestedRemoteTarget != nil) && (!useProjectMemory || selectedProjectID != nil) // Requires stable workspace authority, task, complete remote selection, and an explicit opted-in memory source.
    } // Ends Run eligibility.

    var executionLocationLabel: String { // Produces an honest local-versus-remote label for the current or most recent execution.
        if let activeBackendID { return activeBackendID == ModelBackendID.localMLX.rawValue ? "Local — Mac" : "Remote — configured server" } // Uses actual successful backend evidence after a run.
        return prefersRemoteModel ? (requestedRemoteTarget == nil ? "Remote · selection required" : "Remote — configured server") : "Local — Mac" // Never labels incomplete remote configuration as local execution.
    } // Ends execution-location visibility.

    func loadWorkspaces() async { // Restores authorization metadata and reopens the most recent reachable workspace.
        guard !isLoadingWorkspaces, !isRunning, workspace == nil else { return } // Makes page re-entry idempotent and preserves active or completed session state.
        isLoadingWorkspaces = true // Publishes bounded descriptor loading.
        defer { isLoadingWorkspaces = false } // Clears loading on every outcome.
        do { // Loads and opens only app-owned metadata and the selected directory boundary.
            workspaces = await workspaceStore.all() // Reads stable recency-ordered descriptors from actor isolation.
            if selectedWorkspaceID == nil || !workspaces.contains(where: { $0.id == selectedWorkspaceID }) { selectedWorkspaceID = workspaces.first?.id } // Preserves a valid selection or chooses the latest authorization.
            if let selectedWorkspaceID { try await openWorkspace(id: selectedWorkspaceID) } // Reopens only the exact selected descriptor.
            else { statusText = "Open a workspace to begin" } // Shows a useful empty state without creating filesystem authority implicitly.
        } catch { // Handles stale bookmarks, missing roots, or bounded catalog failures.
            workspace = nil // Prevents a stale actor from retaining authority after reopen failure.
            statusText = "Workspace unavailable" // Keeps the persistent status concise.
            notice = EngineeringControllerNotice(kind: .error, message: error.localizedDescription) // Shows bounded actionable detail.
        } // Ends workspace restoration recovery.
    } // Ends workspace catalog loading.

    func authorizeWorkspace(directoryURL: URL, associatedProjectID: UUID? = nil) async { // Records one folder explicitly selected by the user.
        guard !isRunning, !isLoadingWorkspaces else { return } // Prevents replacing filesystem authority during a run or another open operation.
        isLoadingWorkspaces = true // Serializes authorization across actor suspension points.
        defer { isLoadingWorkspaces = false } // Releases workspace selection ownership on every outcome.
        do { // Creates durable authorization before opening the live actor.
            let descriptor = try await workspaceStore.authorize(directoryURL: directoryURL, associatedProjectID: associatedProjectID) // Persists bookmark and canonical fallback path without scanning contents.
            workspaces = await workspaceStore.all() // Reloads actual durable ordering.
            selectedWorkspaceID = descriptor.id // Selects only the newly authorized identity.
            try await openWorkspace(id: descriptor.id) // Establishes the canonical contained runtime boundary.
            notice = EngineeringControllerNotice(kind: .success, message: "Opened Engineering workspace \(descriptor.displayName).") // Confirms the exact authorization action.
        } catch { // Handles missing directories, bookmark, persistence, or canonicalization failures.
            notice = EngineeringControllerNotice(kind: .error, message: error.localizedDescription) // Publishes bounded safe feedback.
        } // Ends workspace authorization recovery.
    } // Ends explicit workspace authorization.

    func selectWorkspace(id: UUID) async { // Switches to one previously authorized workspace without changing its contents.
        guard !isRunning, !isLoadingWorkspaces, id != selectedWorkspaceID else { return } // Preserves active authority and avoids clearing state on redundant selection.
        isLoadingWorkspaces = true // Serializes selection across actor suspension points.
        defer { isLoadingWorkspaces = false } // Releases selection ownership on every outcome.
        do { // Reopens and records recency through the actor-owned catalog.
            _ = try await workspaceStore.updateLastOpened(id: id) // Persists only last-opened metadata.
            workspaces = await workspaceStore.all() // Refreshes stable recency order after the metadata update.
            try await openWorkspace(id: id) // Establishes the newly selected canonical boundary.
        } catch { // Handles removed, stale, or unavailable workspace state.
            notice = EngineeringControllerNotice(kind: .error, message: error.localizedDescription) // Reports the exact bounded failure.
        } // Ends workspace selection recovery.
    } // Ends workspace switching.

    func removeWorkspaceAuthorization(id: UUID) async { // Removes only app-owned authorization metadata and never deletes external source files.
        guard !isRunning else { return } // Prevents authority removal while a session owns the workspace.
        do { // Removes the exact descriptor and refreshes selection.
            try await workspaceStore.remove(id: id) // Deletes only one catalog record.
            workspaces = await workspaceStore.all() // Reloads remaining durable authorizations.
            if selectedWorkspaceID == id { // Clears live state only when the active authorization was removed.
                selectedWorkspaceID = workspaces.first?.id // Chooses the next recent authorization when available.
                workspace = nil // Drops the removed live authority before reopening any successor.
                changes = [] // Removes transaction rows belonging to the old workspace.
                selectedChangeID = nil // Clears cross-workspace transaction selection.
                selectedDiff = "" // Clears diff text belonging to the removed workspace.
                if let selectedWorkspaceID { try await openWorkspace(id: selectedWorkspaceID) } else { statusText = "Open a workspace to begin" } // Reopens a remaining workspace or returns to the empty state.
            } // Ends active-authorization removal handling.
            notice = EngineeringControllerNotice(kind: .information, message: "Workspace authorization removed. Source files were not deleted.") // States the non-destructive scope explicitly.
        } catch { // Handles bounded catalog persistence or reopen failures.
            notice = EngineeringControllerNotice(kind: .error, message: error.localizedDescription) // Publishes safe actionable feedback.
        } // Ends authorization removal recovery.
    } // Ends non-destructive workspace removal.

    func run() { // Starts one controller-owned bounded session without blocking SwiftUI.
        guard canRun, sessionTask == nil else { return } // Rejects incomplete or overlapping requests.
        let runID = UUID() // Allocates exact ownership identity before asynchronous preparation.
        let configuration = RunConfiguration(task: taskText.trimmingCharacters(in: .whitespacesAndNewlines), remoteTarget: requestedRemoteTarget, quality: quality, memoryProjectID: useProjectMemory ? selectedProjectID : nil, contextPreset: projectContextBudgetPreset) // Captures all visible inputs before the task can suspend.
        activeRunID = runID // Publishes ownership against stale cleanup races.
        isRunning = true // Enables the visible Stop action immediately.
        result = nil // Clears only the prior terminal result while retaining prior workspace history.
        activity = [EngineeringAgentEvent(kind: .sessionStarted, summary: "Preparing the authorized Engineering workspace.")] // Shows immediate trace-safe activity before model inference.
        statusText = "Preparing Engineering session…" // Reports nonblocking preparation.
        sessionTask = Task { [weak self] in // Owns retrieval, model loop, tools, reviewer, and composer as one cancellable operation.
            await self?.performRun(runID: runID, configuration: configuration) // Executes only through actor-backed services using the submitted inputs.
        } // Ends controller-owned session task creation.
    } // Ends Engineering session start.

    func stop() { // Propagates cancellation through the exact current controller-owned session.
        guard isRunning else { return } // Ignores Stop while no session owns work.
        statusText = "Stopping Engineering session…" // Reports cooperative exact-owner cleanup.
        sessionTask?.cancel() // Cancels retrieval, backend inference, and the engine await chain.
        let engine = activeEngine // Captures only the currently owned engine.
        let runtime = activeToolRuntime // Captures only the currently owned tool runtime.
        Task { [approvalBroker] in // Crosses actor boundaries without blocking the main actor.
            await engine?.cancelActiveSession() // Cancels only the engine's exact active child task.
            await runtime?.cancel() // Terminates only a Process owned by this Engineering runtime.
            await approvalBroker.cancelAll() // Resolves pending decisions as Deny without granting late authority.
        } // Ends exact cancellation propagation.
        pendingApproval = nil // Removes a now-invalid Allow Once surface immediately.
    } // Ends Engineering Stop handling.

    func resolveApproval(_ decision: EngineeringApprovalDecision) { // Applies one visible Allow Once or Deny choice to the exact pending request.
        guard let request = pendingApproval else { return } // Refuses a stale decision with no displayed request.
        Task { [weak self, approvalBroker] in // Resolves the actor-owned continuation without blocking SwiftUI.
            let accepted = await approvalBroker.resolve(id: request.id, decision: decision) // Applies the decision only if the exact request remains pending.
            if accepted, self?.pendingApproval?.id == request.id { self?.pendingApproval = nil } // Clears only the matching UI request after confirmed resolution.
        } // Ends approval decision task.
    } // Ends exact approval resolution.

    func refreshChanges() async { // Reloads only app-owned transaction history for the active workspace.
        guard let workspace else { changes = []; return } // Clears stale rows when no live workspace authority exists.
        changes = await workspace.changes() // Reads bounded durable records from actor isolation.
        if let selectedChangeID, !changes.contains(where: { $0.id == selectedChangeID }) { self.selectedChangeID = nil; selectedDiff = "" } // Clears a transaction selection that no longer belongs to current history.
    } // Ends transaction refresh.

    func showDiff(changeID: UUID?) async { // Loads one bounded Git-independent diff without reading the whole repository.
        selectedChangeID = changeID // Publishes the exact selected transaction identity.
        guard let changeID, let workspace else { selectedDiff = ""; return } // Clears the pane for no selection or no authority.
        do { // Requests only the stored before/after transaction.
            selectedDiff = try await workspace.unifiedDiff(changeID: changeID) // Produces a bounded secret-redacted unified diff.
        } catch { // Handles missing, cross-workspace, corrupt, or oversized history.
            selectedDiff = "" // Prevents stale diff text from being mistaken for the current transaction.
            notice = EngineeringControllerNotice(kind: .error, message: error.localizedDescription) // Reports bounded safe feedback.
        } // Ends diff loading recovery.
    } // Ends transaction diff inspection.

    func rollbackSelectedChange() async { // Reverses only the exact app-owned transaction after the view confirms intent.
        guard !isRunning, let selectedChangeID, let workspace else { return } // Prevents rollback racing a live agent or lacking exact transaction authority.
        do { // Applies conflict-safe rollback through the workspace actor.
            let rollback = try await workspace.rollback(changeID: selectedChangeID) // Refuses to erase any unrelated later user edit.
            await refreshChanges() // Reloads actual durable history including the reversal record.
            await showDiff(changeID: rollback.id) // Shows the exact reversal rather than the stale original diff.
            notice = EngineeringControllerNotice(kind: .success, message: "Rolled back the selected app-owned change.") // Confirms the scoped action.
        } catch { // Handles conflicts or missing transaction state without mutating external bytes.
            notice = EngineeringControllerNotice(kind: .error, message: error.localizedDescription) // Reports why rollback was safely refused.
        } // Ends rollback recovery.
    } // Ends conflict-aware rollback.

    private var requestedRemoteTarget: ModelGenerationTarget? { // Resolves complete explicit remote selection into a typed target.
        guard prefersRemoteModel, let serverID = selectedRemoteServerID, let modelID = selectedRemoteModelID?.trimmingCharacters(in: .whitespacesAndNewlines), !modelID.isEmpty else { return nil } // Requires a user-selected server and exact model identity.
        return ModelGenerationTarget(backendID: .remoteOpenAICompatible, location: .remote(serverID: serverID), modelID: modelID) // Creates no local path, IP scan, cloud identity, or implicit server choice.
    } // Ends typed remote target construction.

    private func openWorkspace(id: UUID) async throws { // Creates a fresh canonical workspace actor away from the main actor's rendering work.
        guard let descriptor = workspaces.first(where: { $0.id == id }) else { throw EngineeringRuntimeError.workspaceUnavailable(id.uuidString) } // Requires one exact durable catalog record.
        let opened = try await Task.detached(priority: .userInitiated) { try EngineeringWorkspace(descriptor: descriptor) }.value // Resolves bookmark, canonical root, and history outside the MainActor.
        workspace = opened // Publishes the new sole live filesystem authority only after successful construction.
        selectedWorkspaceID = descriptor.id // Keeps published identity synchronized with the live actor.
        statusText = "Ready · \(descriptor.displayName)" // Shows the bounded active workspace name.
        result = nil // Avoids presenting another workspace's terminal result.
        activity = [] // Avoids presenting another workspace's operational trace.
        activeModelID = nil // Clears model evidence belonging to the prior workspace session.
        activeBackendID = nil // Clears backend evidence belonging to the prior workspace session.
        await refreshChanges() // Loads only this workspace's app-owned transaction history.
    } // Ends canonical workspace opening.

    private func performRun(runID: UUID, configuration: RunConfiguration) async { // Executes optional memory retrieval and the complete bounded agent state machine.
        guard let workspace, let descriptor = selectedWorkspace else { finishRun(runID: runID, status: "Workspace unavailable", error: "Open an authorized workspace before running Engineering Mode."); return } // Requires one consistent live authority and descriptor.
        let normalizedTask = configuration.task // Uses the submitted objective even if another UI updates the draft.
        let remoteTarget = configuration.remoteTarget // Uses the submitted target for every primary turn.
        let quality = configuration.quality // Keeps iteration ceilings and quality stages immutable.
        do { // Prepares bounded orientation and optional isolated knowledge context.
            let components = try sessionBuilder.makeSession(workspace: workspace, preferredRemoteTarget: remoteTarget) // Freezes route assignments before asynchronous workspace or memory preparation.
            activeEngine = components.engine // Registers exact cancellation ownership before suspension.
            activeToolRuntime = components.toolRuntime // Registers exact process ownership before suspension.
            let entries = try await workspace.listDirectory() // Reads only bounded direct children through canonical containment.
            try Task.checkCancellation() // Stops before memory or model work when the user pressed Stop during listing.
            let overview = entries.prefix(120).map { "\($0.isDirectory ? "directory" : "file"): \($0.relativePath)" }.joined(separator: "\n") // Produces a small traceable orientation map without recursive repository ingestion.
            let memoryContext = try await prepareProjectMemoryContext(task: normalizedTask, projectID: configuration.memoryProjectID, preset: configuration.contextPreset) // Retrieves only from the submitted opt-in source and bound.
            try Task.checkCancellation() // Stops before constructing model and runtime actors after optional retrieval.
            activeEngine = components.engine // Publishes only the exact engine owned by this run.
            activeToolRuntime = components.toolRuntime // Publishes only the exact runtime owned by this run.
            let allowedTools = Set(EngineeringToolRuntime.definitions.map { $0.name.rawValue }) // Applies the complete registered typed tool set as an explicit plan boundary.
            let plan = EngineeringExecutionPlan(workspaceID: descriptor.id, workspaceName: descriptor.displayName, quality: quality, allowedToolNames: allowedTools, reviewerEnabled: quality != .fast, composerEnabled: quality == .thorough, verificationExpected: true) // Maps visible quality to fixed iteration and bounded quality-stage policy.
            statusText = remoteTarget == nil ? "Engineering Agent · Local — Mac" : "Engineering Agent · Remote primary" // Makes requested execution location visible without pre-claiming success.
            let sessionResult = await components.engine.execute(EngineeringAgentInput(task: normalizedTask, workspaceOverview: overview, projectMemoryContext: memoryContext), plan: plan, onEvents: { [weak self] events in // Streams operational metadata without publishing model reasoning or file contents.
                Task { @MainActor [weak self] in // Delivers actor-independent progress to SwiftUI.
                    guard let self, self.activeRunID == runID, self.isRunning else { return } // Rejects late updates after Stop cleanup or a newer run.
                    self.activity = events // Shows requested and completed tools while the session is running.
                    if let attempt = events.last(where: { $0.kind == .modelAttempt && $0.succeeded == true }) { self.activeModelID = attempt.modelID; self.activeBackendID = attempt.backendID } // Reports actual routed model evidence in real time.
                } // Ends main-actor event delivery.
            }) // Runs the single-owner bounded loop with external content marked as data.
            result = sessionResult // Publishes the complete or partial terminal evidence.
            activity = sessionResult.events // Publishes trace-safe model, fallback, tool, reviewer, composer, and cancellation events.
            activeModelID = sessionResult.events.last(where: { $0.kind == .modelAttempt && $0.succeeded == true })?.modelID // Reports only an actually successful model attempt.
            activeBackendID = sessionResult.events.last(where: { $0.kind == .modelAttempt && $0.succeeded == true })?.backendID // Reports only an actually successful backend attempt.
            await refreshChanges() // Publishes exact app-owned transactions even after cancellation or partial failure.
            statusText = Self.statusText(for: sessionResult) // Maps the typed terminal state without relying on model prose.
            notice = EngineeringControllerNotice(kind: sessionResult.status == .completed ? .success : .information, message: sessionResult.verification.detail) // Reports evidence state independently from the final candidate.
            finishRun(runID: runID) // Releases only this exact completed run's UI ownership.
        } catch is CancellationError { // Handles cancellation during workspace overview, Project Memory, or dependency assembly.
            statusText = "Engineering session cancelled" // Reports the user-owned stop distinctly from failure.
            notice = EngineeringControllerNotice(kind: .information, message: "Cancellation preserved the current workspace and any completed app-owned changes.") // States the no-auto-rollback policy.
            await refreshChanges() // Shows any mutation that completed before cancellation.
            finishRun(runID: runID) // Releases only this exact cancelled run.
        } catch { // Handles bounded workspace, memory, routing, or construction failure.
            finishRun(runID: runID, status: "Engineering session failed", error: error.localizedDescription) // Publishes safe failure and releases exact ownership.
        } // Ends complete run recovery.
    } // Ends Engineering session execution.

    private func prepareProjectMemoryContext(task: String, projectID: UUID?, preset: ProjectContextBudgetPreset) async throws -> String? { // Retrieves bounded knowledge from immutable submitted configuration.
        guard let selectedProjectID = projectID else { return nil } // Performs no Project Memory I/O without the submitted opt-in source.
        let query = ProjectMemoryQueryBuilder().build(currentRequest: task) // Uses only the current visible request and existing hard query limits.
        guard !query.isEmpty else { return nil } // Avoids broad retrieval for an empty query.
        let limits = preset.limits // Uses the submitted named context budget.
        let options = ProjectRetrievalOptions(resultLimit: limits.maxChunks, candidateLimit: max(limits.maxChunks * 2, limits.maxChunks), usesHybridRanking: false) // Uses deterministic lexical retrieval without pretending optional model runtimes exist.
        let retrieval = try await memoryRetrievalService.retrieve(query: query, projectID: selectedProjectID, options: options) // Searches only the exact isolated project.
        let assembly = try await ProjectContextAssembler(limits: limits).assemble(retrieval) // Applies fairness, delimiter, source, and total-character bounds.
        return assembly.contextText.isEmpty ? nil : assembly.contextText // Supplies only the complete injection-resistant data envelope when evidence exists.
    } // Ends optional Project Memory preparation.

    private func finishRun(runID: UUID, status: String? = nil, error: String? = nil) { // Releases UI ownership only for the exact run that is still active.
        guard activeRunID == runID else { return } // Prevents stale asynchronous cleanup from touching a later session.
        if let status { statusText = status } // Applies an explicit terminal status when supplied.
        if let error { notice = EngineeringControllerNotice(kind: .error, message: error) } // Publishes bounded secret-safe failure detail when supplied.
        isRunning = false // Returns the primary action to Run state.
        activeRunID = nil // Clears exact run ownership.
        sessionTask = nil // Releases the completed controller task.
        activeEngine = nil // Releases the run-scoped engine after all result state was copied.
        activeToolRuntime = nil // Releases the run-scoped process runtime after exact cleanup.
        pendingApproval = nil // Removes any stale approval surface after session termination.
    } // Ends exact run cleanup.

    private static func statusText(for result: EngineeringAgentSessionResult) -> String { // Maps terminal state to concise consistent UI vocabulary.
        switch result.status { // Selects the exact typed outcome.
        case .completed: return result.verification.state == .verified ? "Completed · Verified" : "Completed · Unverified" // Separates completion from evidence.
        case .cancelled: return "Cancelled · Changes preserved" // States cancellation and no automatic rollback.
        case .permissionDenied: return "Stopped · Permission denied" // Reports policy termination distinctly.
        case .iterationLimit: return "Stopped · Iteration limit" // Reports the configured ceiling honestly.
        case .loopDetected: return "Stopped · Repeated loop detected" // Reports strategy-loop protection.
        case .busy: return "Busy · Another session is active" // Reports single-owner rejection.
        case .failed: return "Failed" // Uses the result's separate bounded failure detail for explanation.
        } // Ends terminal status mapping.
    } // Ends Engineering status rendering.
} // Ends the native Engineering application coordinator.
