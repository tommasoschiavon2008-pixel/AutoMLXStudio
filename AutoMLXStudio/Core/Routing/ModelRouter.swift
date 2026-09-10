import Foundation // Supplies LocalizedError and deterministic set operations.

enum ModelRouterError: LocalizedError, Equatable { // Defines traceable deterministic model-selection failures.
    case missingAssignment(String) // Reports an agent with no persisted selection policy.
    case noUsableModel(String) // Reports exhaustion of preferred, fallback, capability, and legacy candidates.

    var errorDescription: String? { // Produces concise trace and user-facing diagnostics.
        switch self { // Selects a message for the current routing failure.
        case let .missingAssignment(agentID): return "No model assignment is registered for \(agentID)." // Describes missing persisted assignment state.
        case let .noUsableModel(agentID): return "No installed, enabled, compatible text model is available for \(agentID)." // Describes complete deterministic fallback exhaustion.
        } // Ends model-router error selection.
    } // Ends localized error access.
} // Ends ModelRouter failure definitions.

protocol ModelRouting { // Isolates deterministic physical model selection for future policy evolution.
    func selectModel(for agent: AgentDefinition, registry: ModelRegistry, activeModelID: String?, policy: ModelSwitchPolicy, excluding: Set<String>) throws -> ModelSelection // Resolves one actual model without starting a runtime.
} // Ends the ModelRouter interface.

struct ModelRouter: ModelRouting { // Selects installed text models from assignments, capabilities, and explicit fallback policy.
    func selectModel( // Resolves the best usable physical model for one agent stage.
        for agent: AgentDefinition, // Accepts responsibility and required capabilities independently from models.
        registry: ModelRegistry, // Accepts the current persisted catalog snapshot.
        activeModelID: String?, // Accepts the one model currently resident in unified memory.
        policy: ModelSwitchPolicy, // Accepts the deterministic quality-versus-switching policy.
        excluding: Set<String> = [] // Accepts models already failed during the current agent stage.
    ) throws -> ModelSelection { // Begins deterministic model selection.
        guard let assignment = registry.assignment(for: agent.id) else { throw ModelRouterError.missingAssignment(agent.id) } // Requires an explicit agent assignment.
        let preferredID = assignment.preferredModelID // Captures the requested model for trace and fallback comparison.

        if let activeModelID, shouldReuseActiveModel(activeModelID, assignment: assignment, policy: policy), let active = usableModel(id: activeModelID, for: agent, registry: registry, excluding: excluding) { // Applies the explicit no-switch policy before loading a new model.
            return selection(agentID: agent.id, preferredID: preferredID, selectedID: active.id, reason: active.id == preferredID ? .preferredModel : .activeModelReuse) // Records preferred or fallback active reuse deterministically.
        } // Ends active-model reuse selection.

        if let preferredID, let preferred = usableModel(id: preferredID, for: agent, registry: registry, excluding: excluding) { // Tries the agent's requested physical model first.
            return selection(agentID: agent.id, preferredID: preferredID, selectedID: preferred.id, reason: .preferredModel) // Records successful preferred-model resolution.
        } // Ends preferred model selection.

        for fallbackID in assignment.fallbackModelIDs { // Tries declared physical fallbacks in persisted order.
            if let fallback = usableModel(id: fallbackID, for: agent, registry: registry, excluding: excluding), !fallback.isLegacyFallback { // Leaves the migrated legacy model for the required final fallback position.
                return selection(agentID: agent.id, preferredID: preferredID, selectedID: fallback.id, reason: .declaredFallback) // Records explicit assignment fallback.
            } // Ends current declared-fallback validation.
        } // Ends declared fallback iteration.

        if let capabilityPreferredID = registry.preferredModelID(for: assignment.preferredCapability), let capabilityPreferred = usableModel(id: capabilityPreferredID, for: agent, registry: registry, excluding: excluding) { // Tries the user's capability-level preference after the agent's declared fallback chain.
            return selection(agentID: agent.id, preferredID: preferredID, selectedID: capabilityPreferred.id, reason: .capabilityPreference) // Records capability-default recovery before generic compatible selection.
        } // Ends capability preference selection.

        let compatible = registry.models(supporting: agent.requiredCapabilities, backends: compatibleBackends(for: agent)) // Finds enabled installed models only within the agent's valid backend family.
        if let capabilityFallback = compatible.first(where: { !$0.isLegacyFallback && !excluding.contains($0.id) }) { // Selects the first stable non-legacy compatible profile.
            return selection(agentID: agent.id, preferredID: preferredID, selectedID: capabilityFallback.id, reason: .capabilityFallback) // Records registry capability recovery.
        } // Ends compatible capability fallback selection.

        if let legacy = usableModel(id: registry.legacyFallbackModelID, for: agent, registry: registry, excluding: excluding) { // Uses the exact migrated V0.1 model only after every V0.2 option.
            return selection(agentID: agent.id, preferredID: preferredID, selectedID: legacy.id, reason: .legacyFallback) // Records backward-compatible final recovery.
        } // Ends legacy fallback selection.

        throw ModelRouterError.noUsableModel(agent.id) // Fails gracefully only after every deterministic path is exhausted.
    } // Ends deterministic model selection.

    private func shouldReuseActiveModel(_ activeModelID: String, assignment: ModelAssignment, policy: ModelSwitchPolicy) -> Bool { // Evaluates the explicit switching-cost policy without model inference.
        guard assignment.allowsRuntimeReuse else { return false } // Honors agents that require a new model decision every stage.
        switch policy { // Selects reuse breadth for the configured policy.
        case .qualityPreferred: return false // Requires the preferred selection path even when another compatible model is active.
        case .balanced: return activeModelID == assignment.preferredModelID || assignment.fallbackModelIDs.contains(activeModelID) // Reuses only preferred or declared alternatives.
        case .minimizeSwitches: return true // Allows any compatible active model to avoid a server restart.
        } // Ends switch-policy evaluation.
    } // Ends active-model reuse policy.

    private func usableModel(id: String, for agent: AgentDefinition, registry: ModelRegistry, excluding: Set<String>) -> ModelProfile? { // Applies every runtime-independent usability rule consistently.
        guard !excluding.contains(id), let profile = registry.model(id: id) else { return nil } // Ignores failed or missing registry identifiers.
        guard profile.enabled, profile.installationState == .installed, compatibleBackends(for: agent).contains(profile.backend) else { return nil } // Requires enabled, installed, backend-compatible models.
        guard profile.runtimeState != .failed, profile.runtimeState != .unavailable || profile.isLegacyFallback else { return nil } // Ignores known runtime failures while preserving the explicit migrated fallback.
        guard agent.requiredCapabilities.isSubset(of: profile.capabilities) else { return nil } // Requires every capability declared by the agent.
        return profile // Returns the validated deterministic candidate.
    } // Ends model usability filtering.

    private func compatibleBackends(for agent: AgentDefinition) -> Set<ModelBackend> { // Maps agent capabilities to explicit runtime families without repository hard-coding.
        agent.requiredCapabilities.contains(.vision) ? [.mlxVLM] : [.mlxLM] // Keeps Vision on VLM and every existing LLM agent on the proven text server.
    } // Ends agent backend-family resolution.

    private func selection(agentID: String, preferredID: String?, selectedID: String, reason: ModelSelectionReason) -> ModelSelection { // Creates consistent traceable selection metadata.
        ModelSelection(requestedAgentID: agentID, preferredModelID: preferredID, selectedModelID: selectedID, reason: reason, usedFallback: preferredID != selectedID) // Records whether selection diverged from the assignment preference.
    } // Ends selection construction.
} // Ends the deterministic V0.2 ModelRouter.
