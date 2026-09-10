import Foundation // Supplies Error, Date, URL error classification, and monotonic timing for backend dispatch.

enum ModelBackendFailureDisposition: String, Equatable, Sendable { // Classifies whether a backend failure may advance through the already authorized route.
    case fallbackEligible // Allows the next explicit compatible route step after an availability or inference failure.
    case terminal // Stops execution because fallback would hide a caller, configuration, or contract error.
    case cancelled // Stops immediately without touching any fallback backend.
} // Ends backend failure dispositions.

protocol ModelBackendFailureClassifying: Error { // Lets backend adapters expose safe fallback semantics without coupling the dispatcher to transport details.
    var modelBackendFailureDisposition: ModelBackendFailureDisposition { get } // Declares fallback, terminal, or cancellation behavior.
    var modelBackendSafeSummary: String { get } // Supplies bounded operational metadata that contains no prompts, responses, or credentials.
} // Ends backend failure classification contract.

enum ModelBackendRegistryError: LocalizedError, Equatable, Sendable { // Defines immutable backend-registration and target-resolution failures.
    case duplicateBackend(ModelBackendID) // Prevents ambiguous dispatch when two adapters claim one stable backend identifier.
    case backendUnavailable(ModelBackendID) // Reports that no registered adapter implements the requested backend.
    case invalidTarget // Reports an empty model identifier or a backend-location contradiction.

    var errorDescription: String? { // Produces stable content-free diagnostics for dispatch traces.
        switch self { // Selects the matching registry diagnostic.
        case .duplicateBackend(let backendID): return "Multiple adapters registered backend \(backendID.rawValue)." // Identifies only the duplicate stable backend key.
        case .backendUnavailable(let backendID): return "No adapter is registered for backend \(backendID.rawValue)." // Identifies only the unavailable stable backend key.
        case .invalidTarget: return "The generation target has an invalid model identity or backend location." // Avoids echoing untrusted target text.
        } // Ends registry-error message selection.
    } // Ends localized registry-error rendering.
} // Ends backend registry failures.

extension ModelBackendRegistryError: ModelBackendFailureClassifying { // Gives target-resolution failures explicit fallback semantics.
    var modelBackendFailureDisposition: ModelBackendFailureDisposition { // Classifies registry resolution without transport assumptions.
        switch self { // Separates an unavailable adapter from invalid caller contracts.
        case .backendUnavailable: return .fallbackEligible // Allows a separately registered explicit fallback target to recover.
        case .duplicateBackend, .invalidTarget: return .terminal // Stops on ambiguous configuration or contradictory target identity.
        } // Ends registry failure classification.
    } // Ends registry failure disposition.

    var modelBackendSafeSummary: String { // Supplies the already content-free localized registry diagnostic.
        errorDescription ?? "Model backend registry failure." // Uses a fixed fallback if localization is unexpectedly absent.
    } // Ends registry failure summary.
} // Ends registry-error classification conformance.

struct ModelBackendRegistry: Sendable { // Owns one immutable exact adapter per stable backend identity.
    private let backends: [ModelBackendID: any ModelInferenceBackend] // Stores only Sendable transport adapters and no local resource manager.

    init(backends: [any ModelInferenceBackend]) throws { // Builds deterministic lookup while rejecting duplicate adapter claims.
        var resolved: [ModelBackendID: any ModelInferenceBackend] = [:] // Collects validated unique adapter registrations.
        for backend in backends { // Validates each injected local or remote backend once.
            guard resolved[backend.id] == nil else { throw ModelBackendRegistryError.duplicateBackend(backend.id) } // Rejects ambiguous stable identifiers without crashing.
            resolved[backend.id] = backend // Registers the exact Sendable adapter under its typed identity.
        } // Ends backend registration.
        self.backends = resolved // Publishes the immutable validated lookup table.
    } // Ends backend registry construction.

    func backend(for target: ModelGenerationTarget) throws -> any ModelInferenceBackend { // Resolves one target without starting, loading, or counting any model resource.
        try Self.validate(target) // Enforces backend-location invariants before adapter lookup.
        guard let backend = backends[target.backendID] else { throw ModelBackendRegistryError.backendUnavailable(target.backendID) } // Requires the exact typed adapter selected by routing.
        return backend // Returns only the requested adapter and never substitutes another backend implicitly.
    } // Ends exact backend resolution.

    func health(for target: ModelGenerationTarget) async -> ModelBackendHealth { // Delegates health observation to the exact selected adapter without fallback side effects.
        do { // Attempts only registry validation and exact adapter health.
            let backend = try backend(for: target) // Resolves the requested typed backend without resource-manager work.
            return await backend.health(for: target) // Returns the backend's evidence-based health observation.
        } catch { // Converts registry configuration failure into an explicit unavailable observation.
            return ModelBackendHealth(status: .unavailable, latencyMilliseconds: nil, checkedAt: Date(), serverKind: nil, apiCompatible: false, discoveredModelCount: nil, conciseError: Self.safeSummary(for: error)) // Reports no invented connectivity or model facts.
        } // Ends registry health resolution.
    } // Ends exact backend health observation.

    private static func validate(_ target: ModelGenerationTarget) throws { // Enforces exact transport ownership before any adapter receives the request.
        guard !target.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ModelBackendRegistryError.invalidTarget } // Rejects empty provider model identities.
        switch target.location { // Compares physical location with the selected stable backend family.
        case .local: guard target.backendID == .localMLX else { throw ModelBackendRegistryError.invalidTarget } // Keeps local execution exclusively on the MLX adapter.
        case .remote: guard target.backendID != .localMLX else { throw ModelBackendRegistryError.invalidTarget } // Ensures remote targets never enter Mac MLX resource ownership.
        } // Ends location validation.
    } // Ends target-contract validation.

    private static func safeSummary(for error: Error) -> String { // Produces bounded registry health diagnostics without trusting arbitrary error descriptions.
        if let classified = error as? any ModelBackendFailureClassifying { return String(classified.modelBackendSafeSummary.prefix(512)) } // Uses only an adapter-declared safe operational summary.
        return "Backend registry operation failed (\(String(describing: type(of: error))))." // Falls back to the error type without serializing associated data.
    } // Ends registry health diagnostic normalization.
} // Ends the immutable backend registry.

enum ModelBackendAttemptOutcome: Equatable, Sendable { // Records the operational result of one exact backend attempt.
    case succeeded // Indicates that the backend produced a validated normalized result.
    case fallbackEligibleFailure(String) // Records a bounded failure that allowed the next explicit route step.
    case terminalFailure(String) // Records a bounded failure that prohibited fallback.
    case cancelled // Records cancellation without treating it as backend degradation.
} // Ends per-attempt execution outcomes.

struct ModelBackendAttemptTrace: Equatable, Sendable { // Captures one exact target attempt without prompts, tool arguments, or model output.
    let ordinal: Int // Records one-based execution order across preferred and fallback attempts.
    let candidateID: String // Records the exact routable catalog record attempted.
    let logicalModelID: String // Records the logical model identity independently from transport.
    let target: ModelGenerationTarget // Records the exact backend, location, and provider model selected.
    let position: ModelGenerationRoutePosition // Records preferred or explicit ordered-fallback provenance.
    let durationMilliseconds: Int // Records measured backend attempt latency.
    let outcome: ModelBackendAttemptOutcome // Records success, bounded failure, or cancellation semantics.
} // Ends one backend attempt trace entry.

enum ModelBackendExecutionTerminalState: String, Equatable, Sendable { // Summarizes how one dispatcher operation ended.
    case succeeded // Indicates that one planned target returned a valid normalized result.
    case exhausted // Indicates that every eligible explicit target failed with fallback-eligible errors.
    case terminalFailure // Indicates that a non-fallback-safe error stopped the route.
    case cancelled // Indicates that cancellation stopped the route before any further backend work.
} // Ends dispatcher terminal states.

struct ModelBackendExecutionTrace: Equatable, Sendable { // Combines static selection evidence with actual execution attempts.
    let selection: ModelGenerationSelectionTrace // Preserves every eligible, rejected, and policy-skipped configured model record.
    let attempts: [ModelBackendAttemptTrace] // Preserves only operational metadata for targets actually attempted.
    let selectedCandidateID: String? // Identifies the successful catalog record or remains nil for failure and cancellation.
    let usedFallback: Bool // Reports whether the successful result came from an explicit fallback step.
    let terminalState: ModelBackendExecutionTerminalState // Reports success, exhaustion, terminal failure, or cancellation precisely.
} // Ends complete backend execution trace.

struct ModelBackendDispatchOutput: Equatable, Sendable { // Returns a normalized generation result together with its transparent route evidence.
    let result: ModelGenerationResult // Supplies provider-independent text, native calls, usage, and finish metadata.
    let trace: ModelBackendExecutionTrace // Supplies content-free preferred and fallback execution evidence.
} // Ends successful dispatcher output.

enum ModelBackendDispatchError: LocalizedError, Equatable, Sendable { // Preserves complete execution evidence for every unsuccessful terminal outcome.
    case invalidRoute(summary: String, trace: ModelBackendExecutionTrace) // Reports an empty plan or request-target contract mismatch.
    case exhausted(trace: ModelBackendExecutionTrace) // Reports failure of every eligible explicit target.
    case terminalFailure(trace: ModelBackendExecutionTrace) // Reports a non-fallback-safe adapter or request failure.
    case cancelled(trace: ModelBackendExecutionTrace) // Reports cancellation without attempting any remaining fallback.

    var trace: ModelBackendExecutionTrace { // Exposes operational evidence uniformly to coordinators and agent adapters.
        switch self { // Extracts the trace from every typed error variant.
        case .invalidRoute(_, let trace), .exhausted(let trace), .terminalFailure(let trace), .cancelled(let trace): return trace // Returns the complete content-free execution evidence.
        } // Ends dispatch-error trace extraction.
    } // Ends uniform trace access.

    var errorDescription: String? { // Produces concise terminal diagnostics without serializing provider data.
        switch self { // Selects a stable diagnostic for each dispatcher terminal state.
        case .invalidRoute(let summary, _): return summary // Returns the caller-contract diagnostic already created by the dispatcher.
        case .exhausted: return "Every eligible configured generation target failed." // Reports explicit-route exhaustion without raw backend content.
        case .terminalFailure: return "Generation stopped after a non-fallback-safe backend failure." // Explains why no additional target was attempted.
        case .cancelled: return "Generation was cancelled before any further backend fallback." // Distinguishes cancellation from backend unavailability.
        } // Ends dispatch-error message selection.
    } // Ends localized dispatcher-error rendering.
} // Ends typed dispatcher failures.

struct ModelBackendDispatcher: Sendable { // Executes one validated route while keeping model selection independent from transport implementations.
    typealias RequestFactory = @Sendable (RoutableGenerationModel) throws -> ModelGenerationRequest // Builds target-specific normalized requests without exposing application objects to backends.
    private let registry: ModelBackendRegistry // Resolves exact targets to immutable local or remote backend adapters.

    init(registry: ModelBackendRegistry) { // Creates a dispatcher around one validated backend registry.
        self.registry = registry // Stores the registry without taking ownership of any ModelResourceManager.
    } // Ends dispatcher construction.

    func generate(request: ModelGenerationRequest, using route: ModelGenerationRoutePlan) async throws -> ModelBackendDispatchOutput { // Executes a prebuilt request and retargets only its transport-neutral target across fallbacks.
        guard request.target == route.initialTarget else { // Requires callers to build the first request against the router's actual initial target.
            let trace = Self.trace(route: route, attempts: [], selectedCandidateID: nil, usedFallback: false, terminalState: .terminalFailure) // Creates an evidence-preserving caller-contract trace.
            throw ModelBackendDispatchError.invalidRoute(summary: "The generation request target does not match the route's initial target.", trace: trace) // Stops rather than silently ignoring an inconsistent request.
        } // Ends initial request-target validation.
        return try await generate(using: route) { model in // Reuses the target-aware dispatcher path for every planned step.
            ModelGenerationRequest(target: model.target, systemInstructions: request.systemInstructions, messages: request.messages, tools: request.tools, temperature: request.temperature, maxOutputTokens: request.maxOutputTokens, stopSequences: request.stopSequences, attachments: request.attachments) // Changes only the exact target while preserving normalized request content.
        } // Ends convenience dispatch delegation.
    } // Ends fixed-payload route execution.

    func generate(using route: ModelGenerationRoutePlan, requestFactory: RequestFactory) async throws -> ModelBackendDispatchOutput { // Executes preferred then only compatible explicit fallbacks with target-aware request normalization.
        guard !route.steps.isEmpty else { // Rejects manually constructed empty plans even though ModelRouter never produces one.
            let trace = Self.trace(route: route, attempts: [], selectedCandidateID: nil, usedFallback: false, terminalState: .terminalFailure) // Preserves any supplied static selection evidence.
            throw ModelBackendDispatchError.invalidRoute(summary: "The generation route contains no executable target.", trace: trace) // Stops before backend resolution.
        } // Ends empty-route validation.
        var attempts: [ModelBackendAttemptTrace] = [] // Collects content-free actual execution evidence in route order.
        for (offset, step) in route.steps.enumerated() { // Executes only the validated preferred and explicit ordered-fallback steps.
            if Task.isCancelled { // Stops at the boundary before request construction or backend lookup.
                let trace = Self.trace(route: route, attempts: attempts, selectedCandidateID: nil, usedFallback: false, terminalState: .cancelled) // Preserves completed earlier attempts without inventing a new one.
                throw ModelBackendDispatchError.cancelled(trace: trace) // Prevents any remaining local or remote target from running.
            } // Ends pre-attempt cancellation enforcement.
            let start = ContinuousClock.now // Starts monotonic timing for this exact planned target.
            do { // Builds, resolves, and executes one target-specific backend request.
                let request = try requestFactory(step.model) // Lets the adapter express only capabilities actually supported by this selected model.
                guard request.target == step.model.target else { throw ModelBackendRegistryError.invalidTarget } // Prevents a request factory from escaping the router's exact target.
                let backend = try registry.backend(for: step.model.target) // Resolves the exact backend without touching local resources for a remote target.
                let result = try await backend.generate(request: request) // Delegates one normalized request to the selected transport adapter.
                try Task.checkCancellation() // Honors cancellation even if a backend returned after ignoring its own cancellation signal.
                guard result.backendID == step.model.target.backendID else { // Validates normalized response provenance before reporting success.
                    let duration = Self.milliseconds(since: start) // Measures the complete contract-violating attempt.
                    attempts.append(Self.attempt(ordinal: offset + 1, step: step, duration: duration, outcome: .terminalFailure("Backend response identity did not match the routed target."))) // Records only stable contract metadata.
                    let trace = Self.trace(route: route, attempts: attempts, selectedCandidateID: nil, usedFallback: false, terminalState: .terminalFailure) // Finalizes the stopped execution trace.
                    throw ModelBackendDispatchError.terminalFailure(trace: trace) // Stops because adapter identity mismatch is not an availability fallback.
                } // Ends backend response-provenance validation.
                let duration = Self.milliseconds(since: start) // Measures successful target execution.
                attempts.append(Self.attempt(ordinal: offset + 1, step: step, duration: duration, outcome: .succeeded)) // Records success without response content.
                let trace = Self.trace(route: route, attempts: attempts, selectedCandidateID: step.model.id, usedFallback: step.isFallback, terminalState: .succeeded) // Finalizes transparent preferred-or-fallback success metadata.
                return ModelBackendDispatchOutput(result: result, trace: trace) // Returns normalized output and complete operational evidence.
            } catch let dispatchError as ModelBackendDispatchError { // Preserves an already finalized internal dispatcher contract failure.
                throw dispatchError // Avoids wrapping or duplicating its final attempt trace.
            } catch { // Classifies backend, registry, request-factory, and cancellation failures consistently.
                let duration = Self.milliseconds(since: start) // Measures the complete failed attempt.
                let classification = Self.classify(error) // Obtains bounded safe fallback semantics without raw provider data.
                switch classification.disposition { // Applies cancellation and fallback policy from the classified error.
                case .cancelled: // Handles both cooperative task and transport-specific cancellation.
                    attempts.append(Self.attempt(ordinal: offset + 1, step: step, duration: duration, outcome: .cancelled)) // Records cancellation for the exact in-flight target.
                    let trace = Self.trace(route: route, attempts: attempts, selectedCandidateID: nil, usedFallback: false, terminalState: .cancelled) // Finalizes cancellation evidence.
                    throw ModelBackendDispatchError.cancelled(trace: trace) // Stops without touching the next configured fallback.
                case .terminal: // Handles invalid requests, configuration contradictions, and unknown unclassified errors.
                    attempts.append(Self.attempt(ordinal: offset + 1, step: step, duration: duration, outcome: .terminalFailure(classification.summary))) // Records the bounded safe operational diagnostic.
                    let trace = Self.trace(route: route, attempts: attempts, selectedCandidateID: nil, usedFallback: false, terminalState: .terminalFailure) // Finalizes terminal failure evidence.
                    throw ModelBackendDispatchError.terminalFailure(trace: trace) // Stops without hiding the contract failure behind another model.
                case .fallbackEligible: // Handles typed backend availability or inference failures.
                    attempts.append(Self.attempt(ordinal: offset + 1, step: step, duration: duration, outcome: .fallbackEligibleFailure(classification.summary))) // Records why the explicit route may advance.
                    continue // Advances only to the next step already authorized and validated by ModelRouter.
                } // Ends failure disposition handling.
            } // Ends one target attempt.
        } // Ends preferred-plus-explicit-fallback execution.
        let trace = Self.trace(route: route, attempts: attempts, selectedCandidateID: nil, usedFallback: false, terminalState: .exhausted) // Finalizes complete explicit-route exhaustion evidence.
        throw ModelBackendDispatchError.exhausted(trace: trace) // Reports failure without scanning for unrelated catalog models.
    } // Ends target-aware route execution.

    private static func classify(_ error: Error) -> (disposition: ModelBackendFailureDisposition, summary: String) { // Normalizes failure behavior without retaining provider response bodies.
        if Task.isCancelled || error is CancellationError { return (.cancelled, "Generation was cancelled.") } // Gives cooperative cancellation absolute priority over fallback.
        if let urlError = error as? URLError, urlError.code == .cancelled { return (.cancelled, "Generation transport was cancelled.") } // Recognizes URLSession cancellation even when wrapped outside a backend.
        if let classified = error as? any ModelBackendFailureClassifying { return (classified.modelBackendFailureDisposition, bounded(classified.modelBackendSafeSummary)) } // Trusts only adapters that explicitly promise a safe operational summary.
        return (.terminal, "Unclassified backend failure (\(String(describing: type(of: error)))).") // Stops conservatively without serializing arbitrary error-associated data.
    } // Ends backend failure classification.

    private static func attempt(ordinal: Int, step: ModelGenerationRouteStep, duration: Int, outcome: ModelBackendAttemptOutcome) -> ModelBackendAttemptTrace { // Creates one consistent content-free attempt entry.
        ModelBackendAttemptTrace(ordinal: ordinal, candidateID: step.model.id, logicalModelID: step.model.logicalModelID, target: step.model.target, position: step.position, durationMilliseconds: duration, outcome: outcome) // Records route identity, timing, and operational outcome only.
    } // Ends attempt trace construction.

    private static func trace(route: ModelGenerationRoutePlan, attempts: [ModelBackendAttemptTrace], selectedCandidateID: String?, usedFallback: Bool, terminalState: ModelBackendExecutionTerminalState) -> ModelBackendExecutionTrace { // Creates one complete execution trace consistently.
        ModelBackendExecutionTrace(selection: route.selectionTrace, attempts: attempts, selectedCandidateID: selectedCandidateID, usedFallback: usedFallback, terminalState: terminalState) // Combines static selection and actual execution evidence without content.
    } // Ends execution trace construction.

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int { // Converts monotonic duration to bounded whole milliseconds.
        let components = start.duration(to: .now).components // Reads signed seconds and attoseconds from the monotonic clock.
        let seconds = max(0, components.seconds) // Guards against an unexpected negative clock duration.
        let milliseconds = seconds.multipliedReportingOverflow(by: 1_000) // Detects pathological durations before Int conversion.
        guard !milliseconds.overflow else { return Int.max } // Saturates an impossible overflow rather than trapping.
        let fractional = max(0, components.attoseconds / 1_000_000_000_000_000) // Converts non-negative attoseconds to whole milliseconds.
        let total = milliseconds.partialValue.addingReportingOverflow(fractional) // Detects overflow while combining whole and fractional milliseconds.
        guard !total.overflow, total.partialValue <= Int64(Int.max) else { return Int.max } // Saturates values outside the platform Int range.
        return Int(total.partialValue) // Returns the safe whole-millisecond duration.
    } // Ends monotonic duration conversion.

    private static func bounded(_ summary: String) -> String { // Bounds adapter-declared operational summaries before retaining them in traces.
        let oneLine = summary.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ") // Removes multiline formatting that could imitate separate trace events.
        return String(oneLine.prefix(512)) // Retains at most 512 user-visible characters.
    } // Ends trace-summary bounding.
} // Ends backend-neutral preferred-plus-fallback dispatch.

extension RemoteInferenceError: ModelBackendFailureClassifying { // Connects the remote adapter's existing typed fallback contract to generic dispatch.
    var modelBackendFailureDisposition: ModelBackendFailureDisposition { // Maps remote cancellation and availability semantics without transport branching in the dispatcher.
        if case .cancelled = self { return .cancelled } // Ensures remote cancellation never starts a local or second remote fallback.
        return isFallbackEligible ? .fallbackEligible : .terminal // Reuses the remote adapter's explicit safe fallback classification.
    } // Ends remote failure disposition mapping.

    var modelBackendSafeSummary: String { // Supplies the remote adapter's already redacted bounded diagnostic.
        errorDescription ?? "Remote inference failed." // Uses a fixed content-free fallback if localization is unexpectedly absent.
    } // Ends remote safe-summary mapping.
} // Ends remote failure classification conformance.
