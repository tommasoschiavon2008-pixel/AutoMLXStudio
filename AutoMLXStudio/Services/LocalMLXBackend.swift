import Foundation // Supplies Date, monotonic timing, and bounded string normalization for the local backend adapter.

enum LocalMLXBackendError: LocalizedError, Equatable, Sendable { // Defines typed local adapter failures without retaining prompts, responses, or raw server bodies.
    case invalidTarget // Indicates that the request did not select the local MLX backend and local execution location.
    case modelUnavailable // Indicates that the selected model has no current local catalog profile.
    case incompatibleModel // Indicates that the profile does not use the existing MLX text runtime.
    case unsupportedNativeTools // Indicates that the existing plain-text MLX client cannot advertise provider-native tool schemas.
    case unsupportedAttachments // Indicates that the existing MLX text client cannot accept normalized attachments.
    case unsupportedParameters // Indicates that the caller supplied sampling or stop options the existing client cannot forward faithfully.
    case invalidConversation // Indicates that messages cannot be represented without losing required role or correlation metadata.
    case invalidOutputLimit // Indicates that the requested output bound is outside the adapter's explicit safe range.
    case resourceUnavailable // Indicates that local model validation or serialized preparation failed.
    case inferenceFailed // Indicates that the prepared local endpoint did not return usable user-facing content.
    case cancelled // Indicates user or task cancellation without marking the local model failed.

    var errorDescription: String? { // Produces fixed content-free diagnostics suitable for traces and UI.
        switch self { // Selects the matching local adapter diagnostic.
        case .invalidTarget: return "The request does not identify a valid local MLX generation target." // Reports a typed target mismatch.
        case .modelUnavailable: return "The selected local model is not present in the current catalog snapshot." // Reports missing local configuration without echoing identifiers.
        case .incompatibleModel: return "The selected local model is not compatible with the MLX text completion runtime." // Reports backend-family mismatch.
        case .unsupportedNativeTools: return "The current local MLX completion client does not support provider-native tool schemas." // Makes native-tool unavailability explicit for strict structured fallback routing.
        case .unsupportedAttachments: return "The current local MLX text backend does not support attachments." // Prevents unverified multimodal transmission.
        case .unsupportedParameters: return "The current local MLX client cannot faithfully forward the requested sampling or stop parameters." // Prevents silently ignored options.
        case .invalidConversation: return "The normalized conversation cannot be represented by the current local MLX text client." // Reports role or correlation incompatibility without content.
        case .invalidOutputLimit: return "The local MLX output limit must be between 1 and 8192 tokens." // Reports the exact inspectable safety bound.
        case .resourceUnavailable: return "The local MLX model could not be validated or prepared." // Avoids retaining filesystem or process diagnostics in generic model traces.
        case .inferenceFailed: return "The local MLX endpoint did not return usable assistant content." // Avoids retaining raw local server response bodies.
        case .cancelled: return "Local MLX generation was cancelled." // Distinguishes cancellation from model failure.
        } // Ends local error message selection.
    } // Ends localized local error rendering.
} // Ends local backend failures.

extension LocalMLXBackendError: ModelBackendFailureClassifying { // Supplies generic dispatcher semantics for every local adapter failure.
    var modelBackendFailureDisposition: ModelBackendFailureDisposition { // Separates availability failures from caller errors and cancellation.
        switch self { // Selects the safe dispatcher behavior.
        case .cancelled: return .cancelled // Prevents cancellation from loading or invoking an explicit fallback.
        case .modelUnavailable, .incompatibleModel, .resourceUnavailable, .inferenceFailed: return .fallbackEligible // Allows only another already validated explicit model target.
        case .invalidTarget, .unsupportedNativeTools, .unsupportedAttachments, .unsupportedParameters, .invalidConversation, .invalidOutputLimit: return .terminal // Stops when fallback would hide a request or adapter contract mismatch.
        } // Ends local failure classification.
    } // Ends local failure disposition.

    var modelBackendSafeSummary: String { // Supplies the fixed content-free local diagnostic to dispatcher traces.
        errorDescription ?? "Local MLX generation failed." // Uses a fixed fallback if localization is unexpectedly absent.
    } // Ends local backend safe summary.
} // Ends local failure classification conformance.

actor LocalMLXBackend: ModelInferenceBackend { // Adapts the existing serialized resource manager and plain-text MLX client to normalized backend requests.
    typealias ModelProvider = @Sendable (String) async -> ModelProfile? // Resolves the latest local catalog profile without coupling the backend to AppState.
    typealias ConfigurationProvider = @Sendable () async -> ModelRuntimeConfiguration // Resolves the latest local runtime paths and port policy at generation time.
    typealias OutputHandler = @Sendable (String) -> Void // Receives local process output without storing it in generation traces.

    nonisolated let id: ModelBackendID = .localMLX // Publishes the stable backend identity without an actor hop.
    private let resourceManager: any ModelResourceManaging // Owns all local validation, loading, switching, and failure cleanup.
    private let completionClient: any LLMCompleting // Reuses the existing system-prompt-aware MLX completion interface.
    private let modelProvider: ModelProvider // Resolves model metadata dynamically for each exact target.
    private let configurationProvider: ConfigurationProvider // Resolves current runtime configuration dynamically for each exact request.
    private let onOutput: OutputHandler // Forwards process diagnostics only to the caller-provided local observer.

    init(resourceManager: any ModelResourceManaging, completionClient: any LLMCompleting, modelProvider: @escaping ModelProvider, configurationProvider: @escaping ConfigurationProvider, onOutput: @escaping OutputHandler = { _ in }) { // Creates a dependency-injected production or deterministic-test local backend.
        self.resourceManager = resourceManager // Stores the sole local lifecycle authority.
        self.completionClient = completionClient // Stores the existing local completion adapter.
        self.modelProvider = modelProvider // Stores the dynamic catalog resolver.
        self.configurationProvider = configurationProvider // Stores the dynamic runtime-configuration resolver.
        self.onOutput = onOutput // Stores the local-only process-output observer.
    } // Ends local backend construction.

    func health(for target: ModelGenerationTarget) async -> ModelBackendHealth { // Performs non-loading local profile and dependency validation for one exact target.
        let start = DispatchTime.now().uptimeNanoseconds // Starts monotonic validation timing.
        do { // Resolves and validates without starting a model process.
            try Task.checkCancellation() // Stops before catalog or resource-manager work when already cancelled.
            let profile = try await resolve(target: target) // Resolves the exact current local model profile.
            let configuration = await configurationProvider() // Resolves current paths and port policy without global state access here.
            try await resourceManager.validateAvailability(model: profile, configuration: configuration) // Reuses central local installation and dependency validation without loading.
            try Task.checkCancellation() // Avoids reporting healthy after a concurrent cancellation.
            return ModelBackendHealth(status: .healthy, latencyMilliseconds: Self.milliseconds(since: start), checkedAt: Date(), serverKind: "MLX LM", apiCompatible: true, discoveredModelCount: nil, conciseError: nil) // Reports only validation-backed local readiness facts.
        } catch { // Maps cancellation or validation failure to an evidence-based health state.
            let cancelled = Task.isCancelled || error is CancellationError || (error as? LocalMLXBackendError) == .cancelled // Recognizes cancellation without declaring local degradation.
            return ModelBackendHealth(status: cancelled ? .unknown : .unavailable, latencyMilliseconds: Self.milliseconds(since: start), checkedAt: Date(), serverKind: "MLX LM", apiCompatible: false, discoveredModelCount: nil, conciseError: cancelled ? LocalMLXBackendError.cancelled.errorDescription : LocalMLXBackendError.resourceUnavailable.errorDescription) // Returns fixed content-free health diagnostics.
        } // Ends local health validation.
    } // Ends local backend health observation.

    func generate(request: ModelGenerationRequest) async throws -> ModelGenerationResult { // Validates, prepares, and invokes one normalized local text generation.
        try Task.checkCancellation() // Stops before catalog or local lifecycle work when already cancelled.
        let profile = try await resolve(target: request.target) // Resolves the exact selected local catalog profile.
        let normalized = try normalize(request: request, profile: profile) // Validates that the existing completion API can represent the request faithfully.
        let configuration = await configurationProvider() // Resolves current local executable, repository, and port settings.
        let start = DispatchTime.now().uptimeNanoseconds // Starts end-to-end backend timing before serialized resource preparation.
        let preparation: ModelPreparation // Holds the exact ready endpoint returned by the sole local resource owner.
        do { // Separates lifecycle failure from completion failure.
            preparation = try await resourceManager.prepare(model: profile, configuration: configuration, onOutput: onOutput) // Loads or reuses only the selected local model through central ownership.
        } catch { // Converts process, dependency, and memory-budget failures into fixed adapter semantics.
            if Task.isCancelled || error is CancellationError { throw LocalMLXBackendError.cancelled } // Preserves cancellation without fallback or degradation.
            throw LocalMLXBackendError.resourceUnavailable // Avoids retaining raw process or filesystem diagnostics in generic model traces.
        } // Ends serialized local preparation handling.
        try Self.checkCancellation() // Stops between model preparation and completion without marking a warm model failed.
        let text: String // Holds only user-facing content returned by the existing reasoning-safe completion client.
        do { // Invokes the prepared local endpoint exactly once.
            text = try await completionClient.complete(LLMCompletionRequest(serverPort: preparation.port, model: profile.completionModel, systemPrompt: request.systemInstructions, history: normalized.history, userPrompt: normalized.userPrompt, maxTokens: normalized.maxTokens)) // Maps normalized transport-neutral fields to the existing local client.
            try Self.checkCancellation() // Honors cancellation even if the completion client returns after ignoring its cancellation signal.
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { // Requires actual user-facing output from the local endpoint.
                await resourceManager.markFailed(modelID: profile.id, reason: LocalMLXBackendError.inferenceFailed.errorDescription ?? "Local inference failed.") // Clears only the exact failing local model before any explicit fallback.
                throw LocalMLXBackendError.inferenceFailed // Reports a typed content-free failure.
            } // Ends empty-output validation.
        } catch let error as LocalMLXBackendError { // Preserves already normalized local cancellation or inference failure.
            throw error // Returns the typed local error unchanged.
        } catch { // Normalizes arbitrary completion-client failures without persisting local server response bodies.
            if Task.isCancelled || error is CancellationError { throw LocalMLXBackendError.cancelled } // Leaves a successfully prepared model warm after cancellation.
            await resourceManager.markFailed(modelID: profile.id, reason: LocalMLXBackendError.inferenceFailed.errorDescription ?? "Local inference failed.") // Performs central exact-model cleanup before fallback may prepare another local target.
            throw LocalMLXBackendError.inferenceFailed // Returns a fixed safe error rather than arbitrary NSError content.
        } // Ends local completion handling.
        return ModelGenerationResult(text: text, toolCalls: [], usage: nil, finishReason: .stop, modelID: request.target.modelID, backendID: id, durationMilliseconds: Self.milliseconds(since: start)) // Normalizes the plain-text local response without claiming native calls or token usage.
    } // Ends local generation.

    private func resolve(target: ModelGenerationTarget) async throws -> ModelProfile { // Resolves one exact local target to current catalog metadata.
        guard target.backendID == id, target.location == .local, !target.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LocalMLXBackendError.invalidTarget } // Requires the typed local backend, local location, and non-empty model identity.
        guard let profile = await modelProvider(target.modelID) else { throw LocalMLXBackendError.modelUnavailable } // Requires a current exact local catalog profile.
        guard profile.id == target.modelID, profile.backend == .mlxLM, profile.supportsTextChat else { throw LocalMLXBackendError.incompatibleModel } // Prevents identity substitution and non-text runtime use.
        return profile // Returns the validated immutable local profile snapshot.
    } // Ends local profile resolution.

    private func normalize(request: ModelGenerationRequest, profile: ModelProfile) throws -> (history: [LLMConversationMessage], userPrompt: String, maxTokens: Int) { // Validates lossless mapping to the existing plain-text completion client.
        guard profile.backend == .mlxLM else { throw LocalMLXBackendError.incompatibleModel } // Reaffirms the exact supported runtime family before message conversion.
        guard request.tools.isEmpty else { throw LocalMLXBackendError.unsupportedNativeTools } // Requires the higher-level adapter to select strict JSON fallback for local tool use.
        guard request.attachments.isEmpty else { throw LocalMLXBackendError.unsupportedAttachments } // Prevents silently dropping unverified multimodal inputs.
        guard request.temperature == nil, request.stopSequences.isEmpty else { throw LocalMLXBackendError.unsupportedParameters } // Prevents silently ignoring provider parameters absent from LLMCompleting.
        guard let finalMessage = request.messages.last, finalMessage.role == .user, finalMessage.toolCallID == nil, finalMessage.name == nil, finalMessage.assistantToolCalls.isEmpty else { throw LocalMLXBackendError.invalidConversation } // Requires one representable final user prompt without provider-only metadata.
        let historyMessages = request.messages.dropLast() // Separates the final user request because LLMCompletionRequest appends it explicitly.
        guard historyMessages.allSatisfy({ $0.role != .tool && $0.toolCallID == nil && $0.name == nil && $0.assistantToolCalls.isEmpty }) else { throw LocalMLXBackendError.invalidConversation } // Prevents loss of native call correlation in the plain-text local client.
        let maxTokens = request.maxOutputTokens ?? 512 // Uses the established ordinary local completion bound when the caller omits one.
        guard (1...8_192).contains(maxTokens) else { throw LocalMLXBackendError.invalidOutputLimit } // Applies an explicit finite output-token safety range.
        let history = historyMessages.map { LLMConversationMessage(role: $0.role.rawValue, content: $0.content) } // Preserves representable message order and text without application objects.
        return (history, finalMessage.content, maxTokens) // Returns the exact existing-client input components.
    } // Ends normalized local request conversion.

    private static func checkCancellation() throws { // Converts cooperative task cancellation into the adapter's typed cancellation contract.
        do { try Task.checkCancellation() } catch { throw LocalMLXBackendError.cancelled } // Avoids reporting cancellation as inference or model failure.
    } // Ends typed cancellation checking.

    private static func milliseconds(since start: UInt64) -> Int { // Converts monotonic nanoseconds into bounded whole milliseconds.
        let elapsed = DispatchTime.now().uptimeNanoseconds >= start ? DispatchTime.now().uptimeNanoseconds - start : 0 // Guards against an unexpected monotonic underflow.
        let milliseconds = elapsed / 1_000_000 // Converts nanoseconds to whole milliseconds.
        return milliseconds > UInt64(Int.max) ? Int.max : Int(milliseconds) // Saturates values outside the platform Int range.
    } // Ends local duration conversion.
} // Ends the local MLX inference backend adapter.
