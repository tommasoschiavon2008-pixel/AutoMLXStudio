import Foundation // Supplies LocalizedError and Sendable value support for backend-neutral routing.

enum ModelGenerationRouteAvailability: String, Equatable, Sendable { // Describes only evidence-backed routing availability without local-filesystem assumptions.
    case available // Indicates that the exact local or remote target is currently eligible for selection.
    case unknown // Indicates that no current availability observation exists for the target.
    case unavailable // Indicates that a current observation makes the target ineligible.
} // Ends explicit generation-target availability states.

enum ModelGenerationFallbackPolicy: String, Equatable, Sendable { // Controls whether routing may consider the assignment's explicit ordered alternatives.
    case disabled // Restricts execution to the preferred configured model only.
    case orderedCompatible // Allows only explicitly listed alternatives that satisfy every routing requirement.
} // Ends generation fallback policy choices.

struct RoutableGenerationModel: Identifiable, Equatable, Sendable { // Connects one logical catalog record to one exact physical generation target.
    let id: String // Stores the stable assignment-facing record identifier independently from transport details.
    let logicalModelID: String // Groups transport-specific records under the logical model identity visible to orchestration.
    let target: ModelGenerationTarget // Resolves the record to the exact backend, location, and provider-facing model identifier.
    let capabilities: ModelCapabilityProfile // Preserves supported, unsupported, and unknown capability evidence independently.
    let availability: ModelGenerationRouteAvailability // Records whether selection currently has enough availability evidence.
    let isEnabled: Bool // Honors an explicit catalog or user disablement before backend resolution.

    init(id: String, logicalModelID: String, target: ModelGenerationTarget, capabilities: ModelCapabilityProfile, availability: ModelGenerationRouteAvailability, isEnabled: Bool = true) { // Constructs one immutable logical-to-physical routing record.
        self.id = id // Stores the unique catalog record identity.
        self.logicalModelID = logicalModelID // Stores the transport-independent logical model identity.
        self.target = target // Stores the exact executable generation target.
        self.capabilities = capabilities // Stores only capability evidence supplied by discovery or configuration.
        self.availability = availability // Stores the current explicit availability observation.
        self.isEnabled = isEnabled // Stores the explicit routing enablement choice.
    } // Ends routable model construction.
} // Ends the routable logical model record.

struct ModelGenerationRoutingRequest: Equatable, Sendable { // Carries one agent assignment and its bounded transport-neutral selection policy.
    let agentID: String // Identifies the logical agent requesting generation for trace attribution only.
    let preferredModelID: String // Names the preferred routable catalog record without exposing backend branching to the agent.
    let orderedFallbackModelIDs: [String] // Names only explicitly authorized fallback records in deterministic order.
    let requiredCapabilities: Set<ModelCapabilityKind> // Requires each selected record to satisfy the stage's actual modality needs.
    let fallbackPolicy: ModelGenerationFallbackPolicy // Controls whether the ordered alternatives may be considered.
    let allowsUnknownCapabilities: Bool // Allows an explicitly configured model with incomplete metadata only when the caller deliberately opts in.
    let allowsUnknownAvailability: Bool // Allows an unobserved target only when the caller deliberately accepts that uncertainty.

    init(agentID: String, preferredModelID: String, orderedFallbackModelIDs: [String] = [], requiredCapabilities: Set<ModelCapabilityKind> = [.text], fallbackPolicy: ModelGenerationFallbackPolicy = .orderedCompatible, allowsUnknownCapabilities: Bool = false, allowsUnknownAvailability: Bool = false) { // Creates a conservative explicit routing request.
        self.agentID = agentID // Stores the trace identity without granting the agent transport authority.
        self.preferredModelID = preferredModelID // Stores the exact preferred catalog record.
        self.orderedFallbackModelIDs = orderedFallbackModelIDs // Preserves caller-specified fallback order without catalog-wide discovery.
        self.requiredCapabilities = requiredCapabilities // Stores the exact capability contract for every candidate.
        self.fallbackPolicy = fallbackPolicy // Stores the explicit fallback decision.
        self.allowsUnknownCapabilities = allowsUnknownCapabilities // Stores the caller's explicit capability-uncertainty choice.
        self.allowsUnknownAvailability = allowsUnknownAvailability // Stores the caller's explicit availability-uncertainty choice.
    } // Ends generation routing request construction.
} // Ends the transport-neutral generation routing request.

enum ModelGenerationRoutePosition: Equatable, Sendable { // Identifies where one considered record appeared in the explicit assignment.
    case preferred // Marks the assignment's preferred record.
    case fallback(index: Int) // Marks the zero-based position in the ordered fallback list.
} // Ends assignment-position metadata.

enum ModelGenerationRouteRejection: Equatable, Sendable { // Records only operational reasons that made a configured record ineligible.
    case missingRecord // Indicates that the assignment referenced no unique catalog record.
    case duplicateRecord // Indicates that multiple catalog records used the same supposedly unique identifier.
    case duplicateTarget // Prevents retrying the same physical target under a second catalog alias.
    case disabled // Indicates that the exact catalog record was explicitly disabled.
    case unknownAvailability // Indicates that conservative routing rejected an unobserved target.
    case unavailable // Indicates that current evidence marked the target unavailable.
    case unsupportedCapabilities([ModelCapabilityKind]) // Lists required capabilities explicitly known to be unsupported.
    case unknownCapabilities([ModelCapabilityKind]) // Lists required capabilities rejected because support remains unknown.
    case invalidTarget // Indicates an empty identity or a local/remote backend-location contradiction.
    case fallbackDisabled // Indicates that policy intentionally skipped an otherwise configured fallback reference.
    case duplicateReference // Indicates that the assignment repeated a previously considered record identifier.
} // Ends route-rejection metadata.

enum ModelGenerationRouteDisposition: Equatable, Sendable { // Describes the deterministic routing result for one configured reference.
    case eligible // Indicates that the record entered the executable preferred-plus-fallback plan.
    case rejected(ModelGenerationRouteRejection) // Indicates that validation removed the record from the executable plan.
    case skipped(ModelGenerationRouteRejection) // Indicates that explicit policy prevented consideration before validation.
} // Ends per-reference routing disposition states.

struct ModelGenerationRouteEvent: Equatable, Sendable { // Captures one content-free selection observation for diagnostics and tests.
    let candidateID: String // Records the exact assignment reference that was considered.
    let logicalModelID: String? // Records the resolved logical identity only when one unique record existed.
    let target: ModelGenerationTarget? // Records the exact resolved target only when one unique record existed.
    let position: ModelGenerationRoutePosition // Records preferred or ordered-fallback provenance.
    let disposition: ModelGenerationRouteDisposition // Records eligibility, rejection, or policy skipping without prompts or model output.
} // Ends one generation-route event.

struct ModelGenerationSelectionTrace: Equatable, Sendable { // Preserves the complete deterministic selection path without hidden reasoning.
    let agentID: String // Attributes the operational selection trace to the requesting logical agent.
    let initialCandidateID: String? // Identifies the first executable record or remains nil when routing exhausted all references.
    let events: [ModelGenerationRouteEvent] // Preserves configured consideration order and bounded rejection metadata.
} // Ends the generation selection trace.

struct ModelGenerationRouteStep: Equatable, Sendable { // Binds one eligible model record to its assignment provenance for execution.
    let model: RoutableGenerationModel // Supplies the logical identity, capabilities, and concrete target.
    let position: ModelGenerationRoutePosition // Supplies preferred or explicit ordered-fallback provenance.

    var isFallback: Bool { // Reports whether execution reached this step through explicit fallback policy.
        if case .fallback = position { return true } // Recognizes only assignment fallback positions.
        return false // Leaves the preferred position classified as the primary attempt.
    } // Ends fallback provenance lookup.
} // Ends one executable generation-route step.

struct ModelGenerationRoutePlan: Equatable, Sendable { // Carries the preferred target and every compatible explicit runtime fallback.
    let agentID: String // Identifies the requesting logical agent for execution trace continuity.
    let steps: [ModelGenerationRouteStep] // Stores only validated executable targets in preferred-then-fallback order.
    let selectionTrace: ModelGenerationSelectionTrace // Stores every accepted, rejected, and policy-skipped configured reference.

    var initialTarget: ModelGenerationTarget? { // Exposes the exact target a caller should place in its first normalized request.
        steps.first?.model.target // Returns the first validated target without inventing a placeholder.
    } // Ends initial-target lookup.
} // Ends the executable generation route plan.

enum ModelGenerationRoutingError: LocalizedError, Equatable, Sendable { // Reports routing exhaustion while preserving its operational trace.
    case noEligibleTarget(agentID: String, trace: ModelGenerationSelectionTrace) // Indicates that no configured preferred or allowed fallback record passed validation.

    var errorDescription: String? { // Produces one bounded user-facing routing diagnostic.
        switch self { // Selects the stable message for the typed routing failure.
        case .noEligibleTarget(let agentID, _): return "No eligible configured generation target is available for \(agentID)." // Reports exhaustion without exposing prompts or backend internals.
        } // Ends routing-error message selection.
    } // Ends localized routing-error rendering.
} // Ends generation-routing failures.

extension ModelRouter { // Adds backend-neutral routing without changing the established V0.2 local-registry API.
    func makeGenerationRoute(for request: ModelGenerationRoutingRequest, models: [RoutableGenerationModel]) throws -> ModelGenerationRoutePlan { // Resolves only the preferred record and explicitly ordered compatible fallbacks.
        let references = [(request.preferredModelID, ModelGenerationRoutePosition.preferred)] + request.orderedFallbackModelIDs.enumerated().map { ($0.element, ModelGenerationRoutePosition.fallback(index: $0.offset)) } // Builds one deterministic configured-reference sequence.
        var steps: [ModelGenerationRouteStep] = [] // Collects validated executable targets in assignment order.
        var events: [ModelGenerationRouteEvent] = [] // Collects complete content-free selection evidence.
        var consideredRecordIDs = Set<String>() // Prevents duplicate assignment references from producing duplicate attempts.
        var acceptedTargets = Set<ModelGenerationTarget>() // Prevents aliases from retrying one already planned physical target.
        for (candidateID, position) in references { // Evaluates only records named by this exact assignment.
            if case .fallback = position, request.fallbackPolicy == .disabled { // Applies the no-fallback policy before catalog validation.
                events.append(ModelGenerationRouteEvent(candidateID: candidateID, logicalModelID: nil, target: nil, position: position, disposition: .skipped(.fallbackDisabled))) // Records the deliberate policy skip.
                continue // Never inspects or executes disabled fallbacks.
            } // Ends fallback-policy enforcement.
            guard consideredRecordIDs.insert(candidateID).inserted else { // Detects a repeated preferred or fallback reference.
                events.append(ModelGenerationRouteEvent(candidateID: candidateID, logicalModelID: nil, target: nil, position: position, disposition: .skipped(.duplicateReference))) // Records de-duplication without a second attempt.
                continue // Skips the repeated reference.
            } // Ends duplicate-reference handling.
            let matches = models.filter { $0.id == candidateID } // Resolves the assignment reference without crashing on malformed duplicate catalog entries.
            guard matches.count == 1, let model = matches.first else { // Requires exactly one unambiguous catalog record.
                let rejection: ModelGenerationRouteRejection = matches.isEmpty ? .missingRecord : .duplicateRecord // Distinguishes stale assignments from malformed catalogs.
                events.append(ModelGenerationRouteEvent(candidateID: candidateID, logicalModelID: nil, target: nil, position: position, disposition: .rejected(rejection))) // Records the exact catalog-resolution failure.
                continue // Proceeds only to an explicitly configured successor.
            } // Ends unique-record resolution.
            guard Self.hasValidGenerationTarget(model) else { // Validates identity and backend-location invariants before backend lookup.
                events.append(ModelGenerationRouteEvent(candidateID: candidateID, logicalModelID: model.logicalModelID, target: model.target, position: position, disposition: .rejected(.invalidTarget))) // Records a caller-owned target-contract failure.
                continue // Prevents contradictory target dispatch.
            } // Ends target-contract validation.
            guard model.isEnabled else { // Honors the exact catalog record's enablement state.
                events.append(ModelGenerationRouteEvent(candidateID: candidateID, logicalModelID: model.logicalModelID, target: model.target, position: position, disposition: .rejected(.disabled))) // Records explicit disablement.
                continue // Avoids backend resolution for a disabled record.
            } // Ends record enablement enforcement.
            if model.availability == .unavailable { // Rejects targets with current negative availability evidence.
                events.append(ModelGenerationRouteEvent(candidateID: candidateID, logicalModelID: model.logicalModelID, target: model.target, position: position, disposition: .rejected(.unavailable))) // Records evidence-backed unavailability.
                continue // Advances only to a configured fallback.
            } // Ends unavailable-target handling.
            if model.availability == .unknown, !request.allowsUnknownAvailability { // Applies conservative availability policy to unobserved targets.
                events.append(ModelGenerationRouteEvent(candidateID: candidateID, logicalModelID: model.logicalModelID, target: model.target, position: position, disposition: .rejected(.unknownAvailability))) // Records uncertainty rather than misreporting unavailability.
                continue // Advances only when uncertainty was not explicitly accepted.
            } // Ends unknown-availability handling.
            let unsupported = request.requiredCapabilities.filter { model.capabilities.support(for: $0) == .unsupported }.sorted { $0.rawValue < $1.rawValue } // Collects capabilities proven incompatible in stable order.
            guard unsupported.isEmpty else { // Requires no known capability contradiction.
                events.append(ModelGenerationRouteEvent(candidateID: candidateID, logicalModelID: model.logicalModelID, target: model.target, position: position, disposition: .rejected(.unsupportedCapabilities(unsupported)))) // Records the exact incompatible capabilities.
                continue // Never weakens the requested capability contract during fallback.
            } // Ends unsupported-capability enforcement.
            let unknown = request.requiredCapabilities.filter { model.capabilities.support(for: $0) == .unknown }.sorted { $0.rawValue < $1.rawValue } // Collects incomplete capability metadata in stable order.
            if !unknown.isEmpty, !request.allowsUnknownCapabilities { // Applies conservative capability policy unless uncertainty was deliberately accepted.
                events.append(ModelGenerationRouteEvent(candidateID: candidateID, logicalModelID: model.logicalModelID, target: model.target, position: position, disposition: .rejected(.unknownCapabilities(unknown)))) // Preserves uncertainty in the route trace.
                continue // Advances only to a configured compatible successor.
            } // Ends unknown-capability handling.
            guard acceptedTargets.insert(model.target).inserted else { // Prevents aliases from causing an identical physical retry loop.
                events.append(ModelGenerationRouteEvent(candidateID: candidateID, logicalModelID: model.logicalModelID, target: model.target, position: position, disposition: .skipped(.duplicateTarget))) // Records target-level de-duplication.
                continue // Avoids retrying an already planned endpoint and model.
            } // Ends duplicate-target handling.
            steps.append(ModelGenerationRouteStep(model: model, position: position)) // Adds the validated preferred or fallback step.
            events.append(ModelGenerationRouteEvent(candidateID: candidateID, logicalModelID: model.logicalModelID, target: model.target, position: position, disposition: .eligible)) // Records complete positive selection evidence.
        } // Ends configured reference evaluation.
        let trace = ModelGenerationSelectionTrace(agentID: request.agentID, initialCandidateID: steps.first?.model.id, events: events) // Finalizes the selection trace without model prompts or outputs.
        guard !steps.isEmpty else { throw ModelGenerationRoutingError.noEligibleTarget(agentID: request.agentID, trace: trace) } // Fails only after every permitted configured reference was traced.
        return ModelGenerationRoutePlan(agentID: request.agentID, steps: steps, selectionTrace: trace) // Returns the preferred executable target plus only compatible explicit fallbacks.
    } // Ends backend-neutral generation routing.

    private static func hasValidGenerationTarget(_ model: RoutableGenerationModel) -> Bool { // Validates stable identities and transport-location consistency without side effects.
        guard !model.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !model.logicalModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !model.target.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false } // Rejects empty record, logical, or provider identities.
        switch model.target.location { // Checks location against the stable backend family.
        case .local: return model.target.backendID == .localMLX // Allows only the actual local MLX backend to own local resources.
        case .remote: return model.target.backendID != .localMLX // Prevents a remote record from entering the Mac-only MLX resource path.
        } // Ends backend-location consistency validation.
    } // Ends generation-target validation.
} // Ends the source-compatible ModelRouter extension.
