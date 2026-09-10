import Foundation // Supplies actors, timing, and localized resource errors.

enum ModelResourceError: LocalizedError, Equatable { // Defines deterministic validation and lifecycle failures.
    case disabledModel(String) // Reports a user-disabled model selected outside normal routing.
    case unsupportedBackend(ModelBackend) // Reports a registered backend that has no executable process adapter connected yet.
    case executableMissing(String) // Reports an unavailable mlx-lm server executable.
    case invalidModel(String, String) // Reports an absent or incomplete physical model folder.
    case transitionFailed(String, String) // Reports a server stop/load/readiness failure.
    case unsafeShutdown(String) // Reports an owned process whose exit could not be confirmed, blocking all replacement starts.
    case resourceBusy(String) // Reports a concurrent owned one-shot runtime that must finish before an incompatible load.
    case budgetExceeded(String) // Reports a deterministic unified-memory budget refusal.

    var errorDescription: String? { // Produces bounded trace and UI diagnostics.
        switch self { // Selects a message for the current resource failure.
        case let .disabledModel(name): return "\(name) is disabled." // Describes an explicit user configuration block.
        case let .unsupportedBackend(backend): return "\(backend.displayName) is registered, but no executable inference adapter is connected yet." // Describes an intentionally controlled foundation-only backend.
        case let .executableMissing(path): return "MLX server executable not found: \(path)" // Describes the missing runtime binary.
        case let .invalidModel(name, reason): return "\(name) is unavailable: \(reason)" // Describes local installation validation failure.
        case let .transitionFailed(name, reason): return "Could not load \(name): \(reason)" // Describes a server lifecycle failure.
        case let .unsafeShutdown(reason): return "Managed model shutdown is unconfirmed. Replacement startup is blocked. \(reason)" // Describes the hard no-overlap safety state.
        case let .resourceBusy(reason): return "Model resources are busy. \(reason)" // Describes a temporary incompatible owned runtime.
        case let .budgetExceeded(reason): return "Model memory budget rejected the load. \(reason)" // Describes a host-aware safety refusal.
        } // Ends resource-error message selection.
    } // Ends localized resource error access.
} // Ends ModelResourceManager error definitions.

struct ModelRuntimeConfiguration: Equatable { // Carries existing MLX server settings into one serialized transition.
    let executableDirectory: String // Stores the existing virtual-environment binary folder.
    let repoPath: String // Stores the existing mlx-lm repository working directory.
    let requestedPort: Int // Stores the user's preferred local port.
    let autoSelectPort: Bool // Stores whether the existing next-free-port rule may run.
    let transitionTimeoutMilliseconds: Int // Stores the graceful shutdown deadline before an owned process may be force-terminated.

    init(executableDirectory: String, repoPath: String, requestedPort: Int, autoSelectPort: Bool, transitionTimeoutMilliseconds: Int = 3_000) { // Keeps existing call sites compatible while making the safety deadline configurable.
        self.executableDirectory = executableDirectory // Stores the configured virtual-environment binary folder.
        self.repoPath = repoPath // Stores the configured MLX repository working directory.
        self.requestedPort = requestedPort // Stores the preferred local server port.
        self.autoSelectPort = autoSelectPort // Stores whether automatic next-free-port selection is allowed.
        self.transitionTimeoutMilliseconds = max(0, transitionTimeoutMilliseconds) // Normalizes invalid negative deadlines to an immediate graceful check.
    } // Ends runtime-configuration construction.
} // Ends runtime configuration values.

struct ModelPreparation: Equatable { // Reports the actual resource work performed for one selected model.
    let modelID: String // Identifies the model active after preparation.
    let previousModelID: String? // Identifies the model stopped before preparation, when any.
    let port: Int // Stores the actual ready port after automatic selection.
    let didSwitch: Bool // Records whether active model identity changed.
    let reusedExistingLoad: Bool // Records a no-restart optimization or coalesced duplicate request.
    let loadDurationMilliseconds: Int // Records stop plus readiness time for trace metadata.
    let launchReference: String // Records the validated local model path or repository reference supplied to the backend.
    let stopDurationMilliseconds: Int // Records verified graceful plus optional forced shutdown time.
    let coldLoadDurationMilliseconds: Int // Records startup-to-readiness time without the preceding stop interval.
    let reuseDurationMilliseconds: Int // Records the measured warm-reuse decision cost without inventing a load.
    let switchingOverheadMilliseconds: Int // Records deterministic transition overhead outside stop and cold-load work.
    let forcedTermination: Bool // Records whether the prior owned process required force after the graceful deadline.
    let memoryBeforeStop: ModelMemorySnapshot? // Records memory for the exact outgoing owned PID before shutdown.
    let memoryAfterStop: ModelMemorySnapshot? // Records memory after verified release without sampling unrelated processes.
    let memoryAfterLoad: ModelMemorySnapshot? // Records memory for the exact newly owned PID after readiness.

    init(modelID: String, previousModelID: String?, port: Int, didSwitch: Bool, reusedExistingLoad: Bool, loadDurationMilliseconds: Int, launchReference: String = "", stopDurationMilliseconds: Int = 0, coldLoadDurationMilliseconds: Int = 0, reuseDurationMilliseconds: Int = 0, switchingOverheadMilliseconds: Int = 0, forcedTermination: Bool = false, memoryBeforeStop: ModelMemorySnapshot? = nil, memoryAfterStop: ModelMemorySnapshot? = nil, memoryAfterLoad: ModelMemorySnapshot? = nil) { // Preserves older tests while exposing the complete V0.2.1 hardware-validation metrics.
        self.modelID = modelID // Stores the ready physical model identity.
        self.previousModelID = previousModelID // Stores the outgoing physical model identity when present.
        self.port = port // Stores the verified ready endpoint.
        self.didSwitch = didSwitch // Stores whether the active physical identity changed.
        self.reusedExistingLoad = reusedExistingLoad // Stores whether startup was skipped because the model was warm.
        self.loadDurationMilliseconds = loadDurationMilliseconds // Stores complete resource-stage time.
        self.launchReference = launchReference // Stores the exact validated backend launch reference.
        self.stopDurationMilliseconds = stopDurationMilliseconds // Stores verified shutdown time.
        self.coldLoadDurationMilliseconds = coldLoadDurationMilliseconds // Stores startup-to-ready time.
        self.reuseDurationMilliseconds = reuseDurationMilliseconds // Stores warm reuse decision time.
        self.switchingOverheadMilliseconds = switchingOverheadMilliseconds // Stores non-stop, non-load transition overhead.
        self.forcedTermination = forcedTermination // Stores whether force was required for the prior owned process.
        self.memoryBeforeStop = memoryBeforeStop // Stores the outgoing tracked-process sample.
        self.memoryAfterStop = memoryAfterStop // Stores the post-release host sample.
        self.memoryAfterLoad = memoryAfterLoad // Stores the incoming tracked-process sample.
    } // Ends model-preparation construction.
} // Ends model-preparation metadata.

struct ModelResourceSnapshot: Equatable { // Exposes actor-isolated runtime facts to observable AppState and tests.
    let activeModelID: String? // Identifies the only medium text model currently loaded.
    let activePort: Int? // Identifies the local endpoint serving the active model.
    let states: [String: ModelRuntimeState] // Stores known lifecycle state for every model touched by the manager.
} // Ends resource-manager snapshot values.

struct OneShotResourceReservation: Equatable, Sendable { // Records central permission for one bounded Vision or Audio subprocess.
    let modelID: String // Identifies the exact reserved physical model.
    let resourceClass: ModelResourceClass // Identifies the residency category reserved by the process.
    let decision: ResidencyDecision // Records whether the manager loaded alongside, reused, or released a prior large model.
    let budget: ResourceBudget // Records the host budget used for the decision.
} // Ends one-shot resource reservation metadata.

protocol ModelServerControlling: Sendable { // Isolates process management so lifecycle concurrency can be tested without loading models.
    func start(modelReference: String, configuration: ModelRuntimeConfiguration, onOutput: @escaping (String) -> Void) async throws -> Int // Starts one model and waits for readiness.
    func stop() async // Stops the one managed model process and waits for release.
    func stop(timeoutMilliseconds: Int) async throws -> ManagedProcessStopResult // Stops the exact owned process and reports verified lifecycle metrics.
    func managedProcessID() async -> Int32? // Returns only the process identifier owned by this controller.
} // Ends model-server control abstraction.

extension ModelServerControlling { // Supplies source-compatible metrics behavior for deterministic fake controllers.
    func stop(timeoutMilliseconds: Int) async throws -> ManagedProcessStopResult { // Adapts a legacy awaited stop to the verified result contract used by tests.
        let start = DispatchTime.now().uptimeNanoseconds // Starts monotonic fake or alternate-controller stop timing.
        await stop() // Awaits the controller's existing full-release guarantee.
        let duration = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000) // Measures the compatibility stop path.
        return ManagedProcessStopResult(processID: nil, durationMilliseconds: duration, forcedTermination: false, exitConfirmed: true) // Reports a verified compatibility release without claiming an owned PID.
    } // Ends compatibility detailed stop.

    func managedProcessID() async -> Int32? { nil } // Avoids inventing a process identity for fake or alternate controllers.
} // Ends source-compatible controller behavior.

final class MLXModelServerController: ModelServerControlling, @unchecked Sendable { // Adapts the existing MLXService to actor-safe lifecycle calls.
    private let service: MLXService // Stores the one existing server and networking service instance.

    init(service: MLXService) { // Injects the existing service instead of creating another server implementation.
        self.service = service // Preserves a single process owner across Chat, Models, Benchmark, and Optimize.
    } // Ends controller construction.

    func start(modelReference: String, configuration: ModelRuntimeConfiguration, onOutput: @escaping (String) -> Void) async throws -> Int { // Starts one selected text model through the existing implementation.
        try await service.startServer(executableDirectory: configuration.executableDirectory, repoPath: configuration.repoPath, model: modelReference, requestedPort: configuration.requestedPort, autoSelectPort: configuration.autoSelectPort, onOutput: onOutput) // Delegates executable validation, port selection, process launch, and readiness.
    } // Ends existing-service startup delegation.

    func stop() async { // Stops the single existing server before a model transition.
        await service.stopServerAndWait() // Waits until the prior medium model process releases memory and its port.
    } // Ends existing-service stop delegation.

    func stop(timeoutMilliseconds: Int) async throws -> ManagedProcessStopResult { // Stops and verifies only the Process retained by this MLXService instance.
        try await service.stopServerAndWait(gracefulTimeoutMilliseconds: timeoutMilliseconds) // Delegates graceful deadline, exact-PID force, and exit confirmation.
    } // Ends production detailed stop delegation.

    func managedProcessID() async -> Int32? { // Exposes only the MLXService-owned process to the memory sampler.
        service.managedServerProcessID() // Returns no identifier for unrelated Python or server processes.
    } // Ends managed process identity delegation.
} // Ends the MLX server controller adapter.

protocol ModelResourceManaging: Sendable { // Isolates serialized model lifecycle behavior from WorkflowEngine.
    func prepare(model: ModelProfile, configuration: ModelRuntimeConfiguration, onOutput: @escaping (String) -> Void) async throws -> ModelPreparation // Makes one selected model ready.
    func markFailed(modelID: String, reason: String) async // Marks and unloads a model after an inference failure.
    func stop() async // Stops any active or transitioning model.
    func snapshot() async -> ModelResourceSnapshot // Returns observable lifecycle metadata.
    func validateAvailability(model: ModelProfile, configuration: ModelRuntimeConfiguration) async throws // Validates any registered backend without starting it.
    func dependencyStatuses(configuration: ModelRuntimeConfiguration) async -> [RuntimeDependencyStatus] // Returns read-only backend dependency discovery owned by the central manager.
} // Ends resource-manager interface.

actor ModelResourceManager: ModelResourceManaging { // Serializes every medium text-model transition and prevents duplicate loads.
    private let controller: any ModelServerControlling // Owns the single underlying server process controller.
    private let adapters: ModelRuntimeAdapterRegistry // Owns backend-specific validation and dependency discovery centrally.
    private let memorySampler: ModelMemorySampler // Samples only explicit controller-owned process identifiers.
    private var activeModelID: String? // Tracks the only loaded text model identity.
    private var activePort: Int? // Tracks the ready endpoint for the active model.
    private var states: [String: ModelRuntimeState] = [:] // Tracks lifecycle states without conflating them with persisted installation state.
    private var transitionTask: Task<ModelPreparation, Error>? // Coalesces concurrent requests while a model is loading.
    private var transitionTargetID: String? // Identifies the model represented by the current transition task.
    private var lastTransitionTimeoutMilliseconds = 3_000 // Retains the latest configured graceful deadline for failure cleanup and explicit stop.
    private var stopSafetyFailure: String? // Blocks replacement startup after any unconfirmed owned-process shutdown.
    private let budget: ResourceBudget // Stores the host-derived conservative unified-memory envelope.
    private var activeLargeEstimate: ResidentModelEstimate? // Tracks the one resident or reserved large text/Vision resource.
    private var activeSmallEstimates: [String: ResidentModelEstimate] = [:] // Tracks bounded audio and future small-runtime reservations by physical model ID.
    private var knownEstimates: [String: ResidentModelEstimate] = [:] // Retains validated registry estimates so coalesced transition completion restores the exact target.

    init(service: MLXService) { // Creates the production resource manager around the existing MLX service.
        self.controller = MLXModelServerController(service: service) // Preserves one server process implementation.
        self.adapters = ModelRuntimeAdapterRegistry() // Registers text, Vision, and Voice validation boundaries under one authority.
        self.memorySampler = ModelMemorySampler() // Creates the bounded exact-PID memory sampler.
        self.budget = ResourceBudget.current() // Derives the resource envelope from this Mac's actual physical memory.
    } // Ends production resource-manager construction.

    init(controller: any ModelServerControlling, adapters: ModelRuntimeAdapterRegistry = ModelRuntimeAdapterRegistry(), memorySampler: ModelMemorySampler = ModelMemorySampler()) { // Creates an injectable resource manager for deterministic lifecycle tests.
        self.controller = controller // Stores the fake or alternate server controller.
        self.adapters = adapters // Stores injectable backend validation boundaries.
        self.memorySampler = memorySampler // Stores the bounded sampler used by production and tests.
        self.budget = ResourceBudget.current() // Uses the same host-aware budget in deterministic lifecycle tests.
    } // Ends injectable resource-manager construction.

    func prepare(model: ModelProfile, configuration: ModelRuntimeConfiguration, onOutput: @escaping (String) -> Void = { _ in }) async throws -> ModelPreparation { // Makes one model ready while honoring the single-large-model rule.
        if let stopSafetyFailure { throw ModelResourceError.transitionFailed(model.displayName, stopSafetyFailure) } // Prevents any replacement launch after an unconfirmed prior shutdown.
        if activeLargeEstimate?.resourceClass == .largeVision { throw ModelResourceError.resourceBusy("A managed Vision inference is still active.") } // Never overlaps a text server with a large Vision subprocess.
        lastTransitionTimeoutMilliseconds = configuration.transitionTimeoutMilliseconds // Retains the caller's explicit safety deadline for later inference-failure cleanup.
        do { // Performs validation before stopping a currently working model.
            try await validateAvailability(model: model, configuration: configuration) // Validates installation, enablement, backend, and runtime dependency centrally.
            guard model.backend == .mlxLM else { throw ModelResourceError.unsupportedBackend(model.backend) } // Keeps process launch limited to the proven text controller after reporting any concrete non-text installation or dependency gap.
        } catch { // Converts validation failure into authoritative runtime state.
            states[model.id] = .unavailable // Prevents a known-invalid model from appearing loadable.
            throw error // Preserves the exact validation diagnostic for fallback and trace handling.
        } // Ends launch preflight validation.
        let requestedEstimate = Self.estimate(for: model) // Converts registry memory metadata into conservative residency bytes.
        knownEstimates[model.id] = requestedEstimate // Retains the target estimate across actor reentrancy and coalesced transition completion.
        let residency = ModelResidencyPolicy.decide(target: requestedEstimate, activeLarge: activeLargeEstimate, activeSmall: Array(activeSmallEstimates.values), budget: budget) // Applies the host-aware policy before text process work.
        if case let .reject(reason) = residency { throw ModelResourceError.budgetExceeded(reason) } // Rejects an unsafe text load before stopping or starting any process.
        activeLargeEstimate = requestedEstimate // Reserves large-text ownership so concurrent one-shot requests see the in-flight target conservatively.

        let preparationStart = DispatchTime.now().uptimeNanoseconds // Starts complete load-or-reuse timing before the warm fast path.
        if activeModelID == model.id, let activePort { // Avoids restarting a model already ready on the managed server.
            states[model.id] = .loaded // Reaffirms the authoritative loaded state.
            let reuseDuration = Self.elapsedMilliseconds(since: preparationStart) // Measures the actual warm decision instead of claiming an unmeasured duration.
            return ModelPreparation(modelID: model.id, previousModelID: model.id, port: activePort, didSwitch: false, reusedExistingLoad: true, loadDurationMilliseconds: reuseDuration, launchReference: model.launchReference, reuseDurationMilliseconds: reuseDuration, memoryAfterLoad: memorySampler.snapshot(trackedProcessID: await controller.managedProcessID())) // Reports verified warm reuse without restarting the process.
        } // Ends already-loaded fast path.

        if let existingTask = transitionTask, let existingTargetID = transitionTargetID { // Serializes against an in-flight stop/load operation.
            if existingTargetID == model.id { // Coalesces duplicate concurrent requests for the same target.
                let preparation = try await finish(existingTask, targetID: existingTargetID) // Waits for the one physical load operation.
                return ModelPreparation(modelID: preparation.modelID, previousModelID: preparation.previousModelID, port: preparation.port, didSwitch: preparation.didSwitch, reusedExistingLoad: true, loadDurationMilliseconds: preparation.loadDurationMilliseconds, launchReference: preparation.launchReference, stopDurationMilliseconds: preparation.stopDurationMilliseconds, coldLoadDurationMilliseconds: preparation.coldLoadDurationMilliseconds, reuseDurationMilliseconds: preparation.loadDurationMilliseconds, switchingOverheadMilliseconds: preparation.switchingOverheadMilliseconds, forcedTermination: preparation.forcedTermination, memoryBeforeStop: preparation.memoryBeforeStop, memoryAfterStop: preparation.memoryAfterStop, memoryAfterLoad: preparation.memoryAfterLoad) // Marks the duplicate request as shared reuse while preserving physical transition evidence.
            } // Ends duplicate target coalescing.
            _ = try? await finish(existingTask, targetID: existingTargetID) // Waits for the earlier different transition before evaluating the requested model.
            return try await prepare(model: model, configuration: configuration, onOutput: onOutput) // Re-enters selection against the now-stable active state.
        } // Ends in-flight transition serialization.

        let previousModelID = activeModelID // Captures the model that will be unloaded for trace metadata.
        if let previousModelID { states[previousModelID] = .stopping } // Makes the outgoing lifecycle state observable.
        states[model.id] = .loading // Makes the incoming lifecycle state observable.
        activeModelID = nil // Enforces that no model is considered active during the transition.
        activePort = nil // Clears the endpoint until readiness succeeds.
        let controller = self.controller // Captures the Sendable server controller outside actor mutation.
        let memorySampler = self.memorySampler // Captures the immutable sampler for the detached transition task.
        let task = Task<ModelPreparation, Error> { // Creates the one coalescible physical transition operation.
            let outgoingProcessID = await controller.managedProcessID() // Reads only the exact process owned by this controller.
            let memoryBeforeStop = previousModelID == nil ? nil : memorySampler.snapshot(trackedProcessID: outgoingProcessID) // Samples the outgoing owned process before requesting release.
            let stopResult: ManagedProcessStopResult // Declares verified shutdown facts for the outgoing runtime.
            do { // Separates outgoing shutdown failure from incoming startup failure.
                if previousModelID != nil { stopResult = try await controller.stop(timeoutMilliseconds: configuration.transitionTimeoutMilliseconds) } // Fully releases the prior medium model before loading another.
                else { stopResult = ManagedProcessStopResult(processID: nil, durationMilliseconds: 0, forcedTermination: false, exitConfirmed: true) } // Records that no prior resource needed release.
                guard stopResult.exitConfirmed else { throw ModelResourceError.unsafeShutdown("The previous owned process did not confirm exit.") } // Enforces the no-overlap invariant for every controller.
            } catch let error as ModelResourceError { // Preserves an already typed unsafe shutdown result.
                throw error // Returns the hard safety failure unchanged.
            } catch { // Converts controller timeout or refusal into the hard safety state.
                throw ModelResourceError.unsafeShutdown(error.localizedDescription) // Prevents any later prepare from treating the process as released.
            } // Ends verified outgoing shutdown handling.
            let memoryAfterStop = memorySampler.snapshot() // Captures post-release host memory without sampling unrelated processes.
            do { // Attempts one start and readiness cycle for the selected model.
                let coldLoadStart = DispatchTime.now().uptimeNanoseconds // Starts startup-to-readiness timing after verified release.
                let port = try await controller.start(modelReference: model.launchReference, configuration: configuration, onOutput: onOutput) // Reuses the existing auto-port and readiness implementation.
                let coldLoadDuration = Self.elapsedMilliseconds(since: coldLoadStart) // Measures only backend startup and readiness.
                let totalDuration = Self.elapsedMilliseconds(since: preparationStart) // Measures complete validation-adjacent resource work.
                let overhead = max(0, totalDuration - stopResult.durationMilliseconds - coldLoadDuration) // Separates bounded coordinator overhead from stop and cold load.
                let incomingProcessID = await controller.managedProcessID() // Reads only the newly created controller-owned process identifier.
                let memoryAfterLoad = memorySampler.snapshot(trackedProcessID: incomingProcessID) // Samples the incoming owned process after readiness.
                return ModelPreparation(modelID: model.id, previousModelID: previousModelID, port: port, didSwitch: previousModelID != model.id, reusedExistingLoad: false, loadDurationMilliseconds: totalDuration, launchReference: model.launchReference, stopDurationMilliseconds: stopResult.durationMilliseconds, coldLoadDurationMilliseconds: coldLoadDuration, switchingOverheadMilliseconds: overhead, forcedTermination: stopResult.forcedTermination, memoryBeforeStop: memoryBeforeStop, memoryAfterStop: memoryAfterStop, memoryAfterLoad: memoryAfterLoad) // Returns complete authoritative ready-state and hardware metrics.
            } catch { // Converts the existing server diagnostic into a model-specific transition error.
                do { // Requires cleanup confirmation before any fallback may load.
                    let cleanup = try await controller.stop(timeoutMilliseconds: configuration.transitionTimeoutMilliseconds) // Cleans up only a partially started owned process.
                    guard cleanup.exitConfirmed else { throw ModelResourceError.unsafeShutdown("A partially started process did not confirm exit after startup failure.") } // Blocks fallback when alternate controllers cannot confirm cleanup.
                } catch let cleanupError as ModelResourceError { // Preserves a typed hard safety failure.
                    throw cleanupError // Returns the hard block instead of the original startup failure.
                } catch { // Converts cleanup refusal into the hard safety state.
                    throw ModelResourceError.unsafeShutdown("Startup failed, then owned-process cleanup failed: \(error.localizedDescription)") // Prevents overlapping fallback startup.
                } // Ends verified partial-start cleanup.
                throw ModelResourceError.transitionFailed(model.displayName, error.localizedDescription) // Preserves actionable port, executable, or readiness context.
            } // Ends server startup recovery.
        } // Ends physical transition task creation.
        transitionTask = task // Publishes the in-flight operation for duplicate and competing callers.
        transitionTargetID = model.id // Publishes the in-flight target identity.
        return try await finish(task, targetID: model.id) // Commits success or failure exactly once from the shared task result.
    } // Ends serialized model preparation.

    func markFailed(modelID: String, reason: String) async { // Removes a failing inference model from the active runtime before fallback selection.
        states[modelID] = .failed // Records the model-specific failure for UI and subsequent routing snapshots.
        guard activeModelID == modelID else { return } // Leaves another active model untouched.
        activeModelID = nil // Stops advertising the failing model immediately.
        activePort = nil // Clears the failing endpoint immediately.
        if activeLargeEstimate?.modelID == modelID { activeLargeEstimate = nil } // Releases the failed text model's residency estimate immediately.
        do { // Verifies release before a fallback model may be selected.
            let result = try await controller.stop(timeoutMilliseconds: lastTransitionTimeoutMilliseconds) // Stops only the exact owned process with the active configuration deadline.
            guard result.exitConfirmed else { throw MLXServiceError.processRefusedToStop(result.processID ?? -1) } // Treats a non-confirming alternate controller as unsafe.
        } catch { // Retains a hard lifecycle block instead of risking two resident models.
            stopSafetyFailure = "The failed model process did not confirm exit. No replacement model will start. \(error.localizedDescription)" // Supplies bounded actionable trace context.
        } // Ends verified inference-failure cleanup.
    } // Ends inference-failure handling.

    func stop() async { // Stops all current or in-flight model work deterministically.
        if let transitionTask, let transitionTargetID { _ = try? await finish(transitionTask, targetID: transitionTargetID) } // Lets an in-flight launch reach a known state before stopping it.
        if let activeModelID { states[activeModelID] = .stopping } // Makes the outgoing active state observable.
        do { // Uses the detailed stop contract so a failed explicit shutdown remains visible.
            let result = try await controller.stop(timeoutMilliseconds: lastTransitionTimeoutMilliseconds) // Stops only the exact controller-owned process.
            guard result.exitConfirmed else { throw ModelResourceError.unsafeShutdown("The controller did not confirm managed process exit.") } // Preserves a hard block for alternate controllers that return an unconfirmed result.
            stopSafetyFailure = nil // Clears a prior safety block only after verified release.
        } catch { // Preserves unsafe shutdown state for the next prepare attempt.
            stopSafetyFailure = "The managed process did not confirm exit. \(error.localizedDescription)" // Blocks replacement startup until a later verified stop succeeds.
        } // Ends explicit verified shutdown.
        if let activeModelID { states[activeModelID] = .unloaded } // Records that the prior model is installed but no longer resident.
        activeModelID = nil // Clears the authoritative active model identity.
        activePort = nil // Clears the authoritative endpoint.
        if activeLargeEstimate?.resourceClass == .largeText { activeLargeEstimate = nil } // Releases only text-server residency while preserving independent one-shot reservations.
        transitionTask = nil // Clears any completed task reference.
        transitionTargetID = nil // Clears any completed transition target.
    } // Ends resource-manager stop.

    func snapshot() -> ModelResourceSnapshot { // Exposes immutable actor state for AppState and deterministic tests.
        ModelResourceSnapshot(activeModelID: activeModelID, activePort: activePort, states: states) // Returns active identity, endpoint, and per-model states atomically.
    } // Ends runtime snapshot access.

    func resourceBudget() -> ResourceBudget { // Exposes the immutable host-derived memory envelope to Models and Settings UI.
        budget // Returns the same budget used by every residency decision.
    } // Ends resource-budget access.

    func residencyDecision(for model: ModelProfile) -> ResidencyDecision { // Previews the exact current reuse, load, switch, or rejection choice without mutating processes.
        ModelResidencyPolicy.decide(target: Self.estimate(for: model), activeLarge: activeLargeEstimate, activeSmall: Array(activeSmallEstimates.values), budget: budget) // Applies the pure policy to authoritative actor state.
    } // Ends current residency preview.

    func reserveOneShot(model: ModelProfile, configuration: ModelRuntimeConfiguration) async throws -> OneShotResourceReservation { // Reserves a validated Vision or Audio process under the central unified-memory policy.
        guard model.backend == .mlxVLM || model.backend == .mlxAudio else { throw ModelResourceError.unsupportedBackend(model.backend) } // Limits one-shot execution to implemented non-text MLX backends.
        if let stopSafetyFailure { throw ModelResourceError.transitionFailed(model.displayName, stopSafetyFailure) } // Preserves a hard no-overlap block after unconfirmed text shutdown.
        try await validateAvailability(model: model, configuration: configuration) // Revalidates files, enablement, backend package, and runtime immediately before reservation.
        let target = Self.estimate(for: model) // Converts the selected profile into deterministic planning metadata.
        if target.resourceClass == .largeVision, activeLargeEstimate?.resourceClass == .largeVision { throw ModelResourceError.resourceBusy("Another managed Vision inference is already active.") } // Serializes large Vision work explicitly.
        if activeSmallEstimates[model.id] != nil { throw ModelResourceError.resourceBusy("The same managed audio model is already active.") } // Prevents duplicate one-shot ownership for one audio model.
        let decision = ModelResidencyPolicy.decide(target: target, activeLarge: activeLargeEstimate, activeSmall: Array(activeSmallEstimates.values), budget: budget) // Decides coexistence or release from current facts.
        if case let .reject(reason) = decision { throw ModelResourceError.budgetExceeded(reason) } // Rejects unsafe work before changing any process state.
        if case .switchFrom = decision { // Releases a resident text server before Vision or memory-heavy audio work.
            guard activeLargeEstimate?.resourceClass == .largeText else { throw ModelResourceError.resourceBusy("The active large runtime cannot be interrupted by this request.") } // Never interrupts a separate in-flight Vision process.
            await stop() // Stops only the exact app-owned text server and waits for release.
            if let stopSafetyFailure { throw ModelResourceError.transitionFailed(model.displayName, stopSafetyFailure) } // Blocks one-shot startup if exact-process exit was not confirmed.
        } // Ends required large-text release.
        if target.resourceClass == .largeVision { activeLargeEstimate = target } // Reserves exclusive large-model ownership for Vision.
        else { activeSmallEstimates[target.modelID] = target } // Reserves budgeted coexistence for Audio or future small runtimes.
        return OneShotResourceReservation(modelID: target.modelID, resourceClass: target.resourceClass, decision: decision, budget: budget) // Returns traceable reservation facts to the runtime service.
    } // Ends one-shot reservation.

    func releaseOneShot(_ reservation: OneShotResourceReservation) { // Releases only the exact one-shot reservation supplied by its owning service.
        if reservation.resourceClass == .largeVision, activeLargeEstimate?.modelID == reservation.modelID { activeLargeEstimate = nil } // Releases exclusive Vision ownership when IDs match.
        if reservation.resourceClass != .largeVision { activeSmallEstimates.removeValue(forKey: reservation.modelID) } // Releases the exact small-runtime budget entry.
    } // Ends one-shot reservation release.

    func validateAvailability(model: ModelProfile, configuration: ModelRuntimeConfiguration) async throws { // Validates any backend through the central immutable adapter registry.
        guard let adapter = adapters.adapter(for: model.backend) else { throw ModelResourceError.unsupportedBackend(model.backend) } // Rejects backends that have no implemented runtime boundary.
        try await adapter.validate(model: model, configuration: configuration) // Performs side-effect-free installation and dependency checks.
    } // Ends central backend validation.

    func dependencyStatuses(configuration: ModelRuntimeConfiguration) -> [RuntimeDependencyStatus] { // Exposes read-only dependency evidence for Models and tests.
        adapters.dependencyStatuses(configuration: configuration) // Returns the stable text, Vision, and Voice dependency order.
    } // Ends central dependency discovery.

    private func finish(_ task: Task<ModelPreparation, Error>, targetID: String) async throws -> ModelPreparation { // Commits a shared transition task result idempotently.
        do { // Awaits the physical stop/load operation.
            let preparation = try await task.value // Receives the actual ready model and port.
            if let previousModelID = preparation.previousModelID, previousModelID != preparation.modelID { states[previousModelID] = .unloaded } // Marks the outgoing model released.
            activeModelID = preparation.modelID // Publishes the one loaded model identity.
            activePort = preparation.port // Publishes the ready endpoint.
            activeLargeEstimate = knownEstimates[preparation.modelID] // Restores the exact successful text target after any competing actor calls.
            states[preparation.modelID] = .loaded // Publishes the loaded lifecycle state.
            stopSafetyFailure = nil // Confirms the preceding release/start lifecycle completed safely.
            if transitionTargetID == targetID { transitionTask = nil; transitionTargetID = nil } // Clears only the task represented by this completion.
            return preparation // Returns the same result to every coalesced caller.
        } catch { // Commits a failed transition without discarding its diagnostic.
            states[targetID] = .failed // Marks the failed incoming model for routing and UI.
            activeModelID = nil // Confirms no model is loaded after a failed replacement.
            activePort = nil // Confirms no endpoint is ready after failure.
            if activeLargeEstimate?.modelID == targetID { activeLargeEstimate = nil } // Releases only the failed target's pending residency estimate.
            if case let ModelResourceError.unsafeShutdown(reason) = error { stopSafetyFailure = reason } // Retains a hard block after any unconfirmed outgoing or cleanup shutdown.
            if transitionTargetID == targetID { transitionTask = nil; transitionTargetID = nil } // Clears only the failed task represented here.
            throw error // Preserves the concrete transition failure for fallback handling.
        } // Ends transition result commit.
    } // Ends shared transition commit.

    private static func elapsedMilliseconds(since start: UInt64) -> Int { // Converts monotonic transition timing to trace-friendly milliseconds.
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000) // Returns non-negative whole milliseconds.
    } // Ends transition timing conversion.

    private static func estimate(for model: ModelProfile) -> ResidentModelEstimate { // Converts optional registry gigabytes into a conservative byte estimate for central policy.
        let fallbackGB: Double // Declares a safe estimate when imported legacy profiles lack catalog metadata.
        switch model.backend { // Selects conservative fallback memory by backend family.
        case .mlxLM: fallbackGB = 8.0 // Reserves a large text envelope for unknown text models.
        case .mlxVLM: fallbackGB = 8.0 // Reserves a large Vision envelope for unknown VLMs.
        case .mlxAudio: fallbackGB = 4.0 // Reserves a bounded but conservative audio envelope.
        case .embedding, .reranker: fallbackGB = 1.0 // Reserves a small future retrieval envelope.
        } // Ends fallback estimate selection.
        let gigabytes = max(0, model.approximateMemoryGB ?? fallbackGB) // Normalizes negative imported metadata and applies the fallback.
        let bytes = UInt64(min(Double(UInt64.max), gigabytes * 1_073_741_824)) // Converts binary gigabytes without overflowing UInt64.
        let resourceClass: ModelResourceClass // Declares policy class from the physical backend.
        switch model.backend { // Maps backend ownership to central resource classes.
        case .mlxLM: resourceClass = .largeText // Maps the proven server backend to exclusive large text.
        case .mlxVLM: resourceClass = .largeVision // Maps Vision to exclusive large-model ownership.
        case .mlxAudio: resourceClass = .smallAudio // Maps ASR and TTS to budgeted small-resource coexistence.
        case .embedding: resourceClass = .embedding // Maps future embedding runtime directly.
        case .reranker: resourceClass = .reranker // Maps future reranker runtime directly.
        } // Ends backend-to-resource mapping.
        return ResidentModelEstimate(modelID: model.id, resourceClass: resourceClass, estimatedBytes: bytes) // Returns immutable planning facts.
    } // Ends registry-estimate conversion.
} // Ends the single-model resource-manager actor.

final class MLXStartContinuationGate: @unchecked Sendable { // Guarantees one async continuation resume across overlapping callbacks.
    private let lock = NSLock() // Serializes terminal callback handling.
    private var continuation: CheckedContinuation<Int, Error>? // Stores the pending async server-start continuation.

    init(continuation: CheckedContinuation<Int, Error>) { // Captures the continuation created by MLXService.
        self.continuation = continuation // Stores the continuation until the first terminal callback.
    } // Ends continuation-gate construction.

    func succeed(_ port: Int) { // Completes startup with the actual ready port.
        resolve(.success(port)) // Uses the single locked terminal path.
    } // Ends successful resolution.

    func fail(_ message: String) { // Completes startup with an actionable existing service diagnostic.
        let error = NSError(domain: "AutoMLXStudio.ModelServer", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) // Wraps callback text in a LocalizedError-compatible value.
        resolve(.failure(error)) // Uses the single locked terminal path.
    } // Ends failed resolution.

    private func resolve(_ result: Result<Int, Error>) { // Resumes the continuation at most once.
        lock.lock() // Begins exclusive terminal callback handling.
        guard let continuation else { lock.unlock(); return } // Ignores later exit or readiness callbacks safely.
        self.continuation = nil // Clears the continuation before resuming to prevent reentrancy duplication.
        lock.unlock() // Releases the lock before executing continuation machinery.
        continuation.resume(with: result) // Completes the awaiting async server call.
    } // Ends single terminal resolution.
} // Ends async startup continuation gate.
