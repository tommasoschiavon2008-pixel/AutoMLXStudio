import Foundation // Supplies UUID, localized errors, and backend-neutral value construction.

enum ChatModelChoiceState: Equatable, Sendable { // Describes whether a visible exact Chat target can start a new generation.
    case available // Indicates current catalog evidence permits generation.
    case unknown // Indicates a configured target has no current discovery observation but may be attempted explicitly.
    case unavailable(String) // Indicates a bounded reason prevents generation while preserving the saved selection.
} // Ends visible Chat model choice states.

struct ChatModelChoice: Identifiable, Equatable, Sendable { // Presents one backend-qualified model without endpoint or credential data.
    let target: ModelGenerationTarget // Stores the exact backend, server, and provider model identity.
    let displayName: String // Stores a concise model label shown in the shared Chat picker.
    let groupName: String // Stores the local or named-server grouping label.
    let state: ChatModelChoiceState // Stores honest current availability evidence.
    let capabilities: ModelCapabilityProfile // Stores discovery-backed or explicitly known capability evidence.

    var id: ModelGenerationTarget { target } // Prevents collisions between equal model names on different servers or backends.

    var isSelectable: Bool { // Reports whether the picker may use this item for a new generation.
        switch state { // Interprets the explicit availability state.
        case .available, .unknown: return true // Allows installed local models and explicitly configured but undiscovered remote targets.
        case .unavailable: return false // Prevents known invalid, removed, or disabled targets from starting work.
        } // Ends selection-state interpretation.
    } // Ends selectable-state access.
} // Ends one Chat model picker record.

enum ChatModelCatalog { // Builds deterministic local and remote picker records without network or persistence side effects.
    static func choices(localModels: [ModelProfile], remoteProfiles: [RemoteServerProfile], remoteModelsByServerID: [UUID: [RemoteDiscoveredModel]], preserving savedTarget: ModelGenerationTarget?) -> [ChatModelChoice] { // Combines current local registry and app-owned remote observations.
        var result = localModels.filter { $0.backend == .mlxLM }.sorted { lhs, rhs in // Restricts Chat text choices to the existing local text backend.
            if lhs.displayName != rhs.displayName { return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending } // Sorts user-facing names deterministically.
            return lhs.id < rhs.id // Uses stable model identity as a final tie breaker.
        }.map { profile in // Converts every visible local text profile into one exact backend target.
            var capabilities = ModelCapabilityProfile(values: [.text: .supported]) // Records verified text support for the local MLX text catalog family.
            capabilities.set(profile.capabilities.contains(.vision) ? .supported : .unknown, for: .vision) // Preserves only locally declared Vision evidence.
            let state: ChatModelChoiceState = profile.enabled && profile.installationState == .installed ? .available : .unavailable(profile.enabled ? "The local model is not installed." : "The local model is disabled.") // Reflects current durable local usability without loading a model.
            return ChatModelChoice(target: ModelGenerationTarget(backendID: .localMLX, location: .local, modelID: profile.id), displayName: profile.displayName, groupName: "On this Mac", state: state, capabilities: capabilities) // Produces one collision-safe local choice.
        } // Ends local model conversion.
        for profile in remoteProfiles.sorted(by: { lhs, rhs in lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending }) { // Adds each configured server in stable display order.
            let discovered = remoteModelsByServerID[profile.id] // Distinguishes never-discovered state from a successful empty discovery list.
            for model in (discovered ?? []).sorted(by: { $0.id.localizedStandardCompare($1.id) == .orderedAscending }) { // Adds only actual discovery results for the server.
                let state: ChatModelChoiceState = profile.isEnabled ? .available : .unavailable("The remote server is disabled.") // Prevents generation through explicitly disabled configuration.
                result.append(ChatModelChoice(target: ModelGenerationTarget(backendID: model.backendID, location: .remote(serverID: profile.id), modelID: model.id), displayName: model.id, groupName: profile.displayName, state: state, capabilities: model.capabilities)) // Preserves server-qualified identity even when model names collide.
            } // Ends discovered model conversion.
            if let savedTarget, case .remote(let serverID) = savedTarget.location, serverID == profile.id, !result.contains(where: { $0.target == savedTarget }) { // Keeps an exact persisted remote choice visible across restart or changed discovery.
                let state: ChatModelChoiceState // Declares the honest reason associated with the preserved choice.
                if !profile.isEnabled { state = .unavailable("The remote server is disabled.") } // Retains selection while preventing work through disabled configuration.
                else if discovered != nil { state = .unavailable("The selected model is no longer reported by this server.") } // Treats a completed discovery omission as current negative evidence.
                else { state = .unknown } // Allows an explicit saved target to be attempted before a new discovery check.
                result.append(ChatModelChoice(target: savedTarget, displayName: savedTarget.modelID, groupName: profile.displayName, state: state, capabilities: ModelCapabilityProfile())) // Restores no endpoint or token data into the picker record.
            } // Ends saved remote selection preservation.
        } // Ends remote server conversion.
        return result // Returns local choices first followed by named remote-server groups.
    } // Ends deterministic Chat catalog construction.

    static func choice(for target: ModelGenerationTarget, in choices: [ChatModelChoice]) -> ChatModelChoice? { // Resolves exact backend, server, and model identity.
        choices.first { $0.target == target } // Never falls back to an equal provider model name on another server.
    } // Ends exact choice lookup.
} // Ends Chat model catalog construction.

struct ChatGenerationSessionOutput: Equatable, Sendable { // Returns visible text, citations, and truthful provider-neutral metadata.
    let text: String // Stores a validated non-empty assistant response.
    let citations: [LocalMemoryCitation] // Stores only Project Memory excerpts actually injected into this request.
    let metadata: ChatGenerationMetadata // Stores exact target, usage, duration, and non-streaming timing truthfully.
} // Ends one completed normal Chat result.

enum ChatGenerationSessionError: LocalizedError, Equatable, Sendable { // Defines controlled failures for ordinary Chat without Engineering tool execution.
    case targetUnavailable(String) // Reports known disabled, removed, missing, or undiscovered target state.
    case emptyResponse // Rejects a backend response with neither safe text nor an explicit supported Chat action.
    case toolCallsUnsupported(Int) // Rejects native tool calls because normal Chat never executes Engineering tools.
    case backendFailure(String) // Reports one bounded adapter-declared operational failure.

    var errorDescription: String? { // Produces concise UI-safe failure text.
        switch self { // Selects the exact normal Chat failure category.
        case .targetUnavailable(let reason): return reason // Uses the catalog's already bounded corrective state.
        case .emptyResponse: return "The selected model returned no visible assistant text." // Avoids exposing private reasoning or malformed response bodies.
        case .toolCallsUnsupported(let count): return "Normal Chat received \(count) tool call\(count == 1 ? "" : "s") and did not execute them. Use Engineering for approved workspace tools." // Makes the no-execution boundary explicit.
        case .backendFailure(let summary): return summary // Uses only normalized bounded adapter evidence.
        } // Ends error-description selection.
    } // Ends localized Chat session errors.
} // Ends ordinary Chat failures.

struct ChatGenerationSession: Sendable { // Executes ordinary text Chat through the same backend-neutral dispatcher used by distributed Engineering.
    let dispatcher: ModelBackendDispatcher // Owns exact local or remote adapter dispatch without selecting a transport in UI code.
    let memoryStore: ProjectMemoryStore // Supplies optional project-isolated retrieval for Project Chat.
    let systemInstructions: String // Supplies the centralized general-agent instruction independently from backend choice.

    func generate(target: ModelGenerationTarget, priorMessages: [ChatMessage], currentUserText: String, projectID: UUID?, usesProjectMemory: Bool, contextLimits: ProjectContextLimits) async throws -> ChatGenerationSessionOutput { // Executes one immutable target and conversation snapshot.
        try Task.checkCancellation() // Stops before retrieval or backend work after an immediate Stop action.
        let memory = try await projectContext(currentUserText: currentUserText, projectID: projectID, enabled: usesProjectMemory, limits: contextLimits) // Retrieves only the selected project's bounded untrusted data when explicitly enabled.
        try Task.checkCancellation() // Stops before constructing or dispatching model input after retrieval.
        let candidateID = Self.candidateID(for: target) // Builds a stable backend-qualified route record identity.
        let routable = RoutableGenerationModel(id: candidateID, logicalModelID: target.modelID, target: target, capabilities: ModelCapabilityProfile(values: [.text: .supported]), availability: .available) // Creates one exact no-fallback Chat route candidate.
        let routingRequest = ModelGenerationRoutingRequest(agentID: AgentID.general, preferredModelID: candidateID, requiredCapabilities: [.text], fallbackPolicy: .disabled, allowsUnknownCapabilities: false, allowsUnknownAvailability: false) // Forbids silent backend or model substitution.
        let route = try ModelRouter().makeGenerationRoute(for: routingRequest, models: [routable]) // Applies shared target validation and selection tracing.
        let messages = Self.normalizedMessages(priorMessages: priorMessages, currentUserText: currentUserText) // Builds exact multi-turn role order without duplicating the current user turn.
        let instructions = memory.contextText.isEmpty ? systemInstructions : systemInstructions + "\n\n" + memory.contextText // Places bounded untrusted Project Memory under its explicit non-instruction envelope.
        let request = ModelGenerationRequest(target: target, systemInstructions: instructions, messages: messages, tools: [], temperature: nil, maxOutputTokens: nil, stopSequences: [], attachments: []) // Advertises no tools and no unsupported attachment or sampling assumptions.
        do { // Executes and validates the selected backend response.
            let output = try await dispatcher.generate(request: request, using: route) // Routes both local and remote text through the shared dispatcher.
            try Task.checkCancellation() // Rejects a response that arrived after user cancellation.
            if !output.result.toolCalls.isEmpty { throw ChatGenerationSessionError.toolCallsUnsupported(output.result.toolCalls.count) } // Never executes normal Chat tool calls even when a provider returns them unexpectedly.
            guard let text = output.result.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { throw ChatGenerationSessionError.emptyResponse } // Requires visible assistant text and never substitutes reasoning metadata.
            let metadata = ChatGenerationMetadata(target: target, usage: output.result.usage, durationMilliseconds: output.result.durationMilliseconds, finishReason: output.result.finishReason, toolCallCount: 0, timeToFirstTokenMilliseconds: nil) // Preserves actual accounting while leaving TTFT absent for non-streaming delivery.
            return ChatGenerationSessionOutput(text: text, citations: memory.citations, metadata: metadata) // Returns only safe visible and operational values.
        } catch let error as ChatGenerationSessionError { // Preserves controlled validation and tool-call failures exactly.
            throw error // Avoids obscuring an actionable normal Chat boundary.
        } catch is CancellationError { // Handles direct cooperative cancellation.
            throw CancellationError() // Preserves cancellation semantics for AppState.
        } catch let error as ModelBackendDispatchError { // Converts dispatcher traces into the most useful safe adapter evidence.
            if error.trace.terminalState == .cancelled { throw CancellationError() } // Maps dispatcher cancellation back to the owned Chat task.
            throw ChatGenerationSessionError.backendFailure(Self.safeFailureSummary(from: error)) // Reports a bounded status without response bodies, prompts, or credentials.
        } catch { // Handles routing and registry failures without reflecting arbitrary associated values.
            throw ChatGenerationSessionError.backendFailure(Self.bounded(error.localizedDescription)) // Bounds the typed framework diagnostic for the visible error state.
        } // Ends generation error normalization.
    } // Ends ordinary text Chat generation.

    private func projectContext(currentUserText: String, projectID: UUID?, enabled: Bool, limits: ProjectContextLimits) async throws -> ProjectContextAssemblyResult { // Builds optional project-scoped context without reading another conversation or project.
        guard enabled, let projectID else { return .empty } // Skips retrieval for normal Chat and disabled Project Memory.
        let query = ProjectMemoryQueryBuilder().build(currentRequest: currentUserText) // Uses only the current user request under the bounded query contract.
        let retrieval = try await ProjectMemoryRetrievalService(memoryStore: memoryStore).retrieve(query: query, projectID: projectID, options: ProjectRetrievalOptions()) // Runs the existing deterministic hybrid-or-lexical pipeline.
        return try await ProjectContextAssembler(limits: limits).assemble(retrieval) // Applies injection boundaries, citation traceability, and hard budgets.
    } // Ends optional Project Memory assembly.

    private static func normalizedMessages(priorMessages: [ChatMessage], currentUserText: String) -> [ModelGenerationMessage] { // Converts visible history to provider-neutral roles in exact order.
        let history = priorMessages.compactMap { message -> ModelGenerationMessage? in // Preserves every valid visible prior turn once.
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines) // Removes transport-irrelevant edge whitespace only.
            guard !content.isEmpty else { return nil } // Omits empty legacy placeholders that cannot contribute conversational meaning.
            if message.role.caseInsensitiveCompare("user") == .orderedSame { return ModelGenerationMessage(role: .user, content: content) } // Preserves a prior user turn exactly once.
            if message.role.caseInsensitiveCompare("assistant") == .orderedSame { return ModelGenerationMessage(role: .assistant, content: content) } // Preserves a prior assistant turn exactly once.
            return nil // Excludes any corrupted internal role from backend context.
        } // Ends visible history conversion.
        return history + [ModelGenerationMessage(role: .user, content: currentUserText)] // Appends the current user request once after all prior turns.
    } // Ends multi-turn message normalization.

    private static func candidateID(for target: ModelGenerationTarget) -> String { // Creates a collision-safe internal route identity from the full target tuple.
        let location: String // Declares a stable location component.
        switch target.location { // Encodes local or exact server ownership.
        case .local: location = "local" // Uses the fixed Mac location marker.
        case .remote(let serverID): location = serverID.uuidString.lowercased() // Uses the full stable server UUID without endpoint data.
        } // Ends location encoding.
        return "chat|\(target.backendID.rawValue)|\(location)|\(target.modelID)" // Includes backend, server, and provider model to prevent collisions.
    } // Ends route record identity construction.

    private static func safeFailureSummary(from error: ModelBackendDispatchError) -> String { // Extracts only adapter-declared safe operational evidence from a dispatcher failure.
        guard let outcome = error.trace.attempts.last?.outcome else { return bounded(error.localizedDescription) } // Falls back to the dispatcher's generic typed diagnostic when no adapter ran.
        switch outcome { // Reads the final content-free attempt result.
        case .fallbackEligibleFailure(let summary), .terminalFailure(let summary): return bounded(summary) // Returns the backend's already safe redacted summary.
        case .cancelled: return "Generation was cancelled." // Preserves cancellation meaning without exposing internal errors.
        case .succeeded: return bounded(error.localizedDescription) // Handles an unlikely post-success dispatcher invariant error generically.
        } // Ends final-attempt summary selection.
    } // Ends safe failure extraction.

    private static func bounded(_ value: String) -> String { // Bounds visible operational failure text defensively.
        let compact = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) // Flattens repeated whitespace into one readable line.
        return compact.isEmpty ? "Chat generation failed." : String(compact.prefix(512)) // Supplies a stable fallback and strict display bound.
    } // Ends diagnostic bounding.
} // Ends shared-dispatcher normal Chat session.
