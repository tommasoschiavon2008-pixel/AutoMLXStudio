import Foundation // Supplies immutable session configuration and typed construction errors.

@MainActor // Captures UI-owned configuration once before any model turn.
final class EngineeringSessionBuilder: EngineeringSessionBuilding { // Centralizes the production engine, routing, approval, and Mac tool graph.
    private let dispatcher: Result<ModelBackendDispatcher, Error> // Retains validated assembly or an actionable configuration failure without crashing app startup.
    private let approvalBroker: EngineeringApprovalBroker // Shares the exact UI approval authority.
    private let registryProvider: () -> ModelRegistry // Resolves current assignments only when creating a session.
    private let remoteModelsProvider: () -> [RemoteDiscoveredModel] // Supplies discovery evidence without inventing capabilities.

    init(backends: [any ModelInferenceBackend], approvalBroker: EngineeringApprovalBroker, registryProvider: @escaping () -> ModelRegistry, remoteModelsProvider: @escaping () -> [RemoteDiscoveredModel]) { // Allows deterministic dependency injection and captures duplicate backend errors.
        self.dispatcher = Result { ModelBackendDispatcher(registry: try ModelBackendRegistry(backends: backends)) } // Uses the existing authoritative backend registry exactly once.
        self.approvalBroker = approvalBroker // Stores one approval owner.
        self.registryProvider = registryProvider // Stores the app's registry snapshot provider.
        self.remoteModelsProvider = remoteModelsProvider // Stores the app's discovery snapshot provider.
    } // Ends builder construction.

    func makeSession(workspace: EngineeringWorkspace, preferredRemoteTarget: ModelGenerationTarget?) throws -> EngineeringSessionComponents { // Creates one bounded run over one authorized workspace.
        let registry = registryProvider() // Freezes assignments so sidebar edits cannot redirect an active session.
        let remoteModels = remoteModelsProvider() // Freezes the selected discovery evidence.
        let routeProvider: EngineeringAgentModelBackendAdapter.RouteProvider = { phase in // Resolves optional quality phases only when the engine requests them.
            try Self.route(phase: phase, registry: registry, remoteTarget: preferredRemoteTarget, remoteModels: remoteModels) // Delegates eligibility and fallback ordering to ModelRouter.
        } // Ends the immutable per-session route provider.
        _ = try Self.route(phase: .primary, registry: registry, remoteTarget: preferredRemoteTarget, remoteModels: remoteModels) // Rejects unusable primary configuration before any tool executes.
        let runtime = EngineeringToolRuntime(workspace: workspace, approvalProvider: approvalBroker, requiresMutationApproval: true) // Requires exact user approval for edits and build scripts while keeping every tool on the Mac.
        let model = EngineeringAgentModelBackendAdapter(dispatcher: try dispatcher.get(), routeProvider: routeProvider) // Normalizes local strict JSON and remote native multi-turn calls.
        let engine = EngineeringAgentEngine(modelGenerator: model, toolExecutor: EngineeringAgentToolRuntimeAdapter(runtime: runtime)) // Gives the bounded loop only typed model and tool interfaces.
        return EngineeringSessionComponents(engine: engine, toolRuntime: runtime) // Returns the exact run owners for Stop and result inspection.
    } // Ends session assembly.

    nonisolated static func route(phase: EngineeringAgentModelPhase, registry: ModelRegistry, remoteTarget: ModelGenerationTarget?, remoteModels: [RemoteDiscoveredModel]) throws -> ModelGenerationRoutePlan { // Builds immutable phase inputs without transport-specific execution.
        let agentID: String // Selects the existing logical assignment for this phase.
        switch phase { // Keeps repair on the same primary route and quality stages tool-free through the adapter.
        case .primary, .argumentRepair: agentID = AgentID.engineering // Uses the configured Engineering coding assignment.
        case .reviewer: agentID = AgentID.reviewer // Uses the existing Reviewer assignment.
        case .composer: agentID = AgentID.finalComposer // Uses the existing Composer assignment.
        } // Ends phase assignment selection.
        let assignment = registry.assignments.first { $0.agentID == agentID } // Reads only the explicitly persisted assignment.
        let required = AgentRegistry().agent(id: agentID)?.requiredCapabilities ?? [] // Preserves domain capability requirements for local catalog models.
        var models = registry.models.map { profile in // Converts physical local records without a second selection algorithm.
            RoutableGenerationModel(id: profile.id, logicalModelID: profile.id, target: ModelGenerationTarget(backendID: .localMLX, location: .local, modelID: profile.id), capabilities: ModelCapabilityProfile(values: [.text: profile.backend == .mlxLM && required.isSubset(of: profile.capabilities) ? .supported : .unsupported, .toolCalling: .unsupported]), availability: profile.installationState == .installed ? .available : .unavailable, isEnabled: profile.enabled) // Rejects missing files, incompatible modalities, and disabled catalog entries.
        } // Ends local routing-record conversion.
        var preferred = assignment?.preferredModelID ?? "" // Leaves missing assignments explicitly ineligible.
        var fallback = assignment?.fallbackModelIDs ?? [] // Never searches undeclared catalog alternatives.
        let usesRemote = (phase == .primary || phase == .argumentRepair) && remoteTarget != nil // Restricts remote preference to the Engineering primary and repair phases.
        if usesRemote, let remoteTarget { // Adds only the explicitly selected, discovered remote identity.
            let record = remoteModels.first { $0.id == remoteTarget.modelID && remoteTarget.location == .remote(serverID: $0.serverID) && $0.backendID == remoteTarget.backendID } // Matches server, backend, and model together.
            let remoteID = "engineering-selected-remote" // Uses a private route-record identity independent from the provider model ID.
            models.append(RoutableGenerationModel(id: remoteID, logicalModelID: remoteTarget.modelID, target: remoteTarget, capabilities: record?.capabilities ?? ModelCapabilityProfile(), availability: record?.availability == .available ? .available : .unavailable)) // Requires observed identity availability while keeping model capabilities explicitly unknown.
            fallback = preferred.isEmpty ? fallback : [preferred] + fallback // Preserves the configured local Engineering assignment as the visible remote recovery route.
            preferred = remoteID // Makes the user's remote selection the initial target.
        } // Ends explicit remote-primary routing.
        return try ModelRouter().makeGenerationRoute(for: ModelGenerationRoutingRequest(agentID: agentID, preferredModelID: preferred, orderedFallbackModelIDs: fallback, allowsUnknownCapabilities: usesRemote), models: models) // Centralizes capability validation, deterministic ordering, and rejection traces.
    } // Ends phase route assembly.
} // Ends the single Engineering production session builder.
