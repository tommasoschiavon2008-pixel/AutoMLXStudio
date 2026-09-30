import Foundation // Supplies URLSession, Codable, cancellation, timing, and bounded error utilities.

enum RemoteInferenceError: LocalizedError, Equatable, Sendable { // Defines typed remote failures that routing can inspect for explicit fallback decisions.
    case invalidTarget // Indicates the request did not identify a remote OpenAI-compatible target.
    case profileNotFound // Indicates the selected remote server no longer exists.
    case serverDisabled // Indicates the user disabled the selected server.
    case backendMismatch // Indicates the profile and backend adapter types differ.
    case authenticationUnavailable // Indicates bearer authentication is configured but no token is available.
    case unsupportedAttachments // Indicates this text-only adapter received unverified attachment input.
    case invalidRequest(String) // Stores one bounded request-validation diagnostic.
    case httpStatus(code: Int, message: String) // Stores a bounded redacted provider HTTP failure.
    case incompatibleAPI(String) // Indicates the endpoint did not satisfy the expected API contract.
    case malformedResponse(String) // Indicates provider JSON could not be normalized safely.
    case malformedToolCall(String) // Indicates a native tool request failed strict structural validation.
    case timedOut // Indicates a configured network deadline elapsed.
    case cancelled // Indicates user or task cancellation rather than server degradation.
    case connectionLost // Indicates the private server became unreachable during a request.
    case networkUnavailable // Indicates macOS reported that this process has no usable network path.
    case transport(String) // Stores one bounded redacted transport diagnostic.

    var isFallbackEligible: Bool { // Tells ModelRouter whether a compatible explicit fallback may be attempted.
        switch self { // Classifies failures without performing the fallback inside the transport layer.
        case .cancelled, .invalidRequest, .unsupportedAttachments, .invalidTarget: // Keeps user cancellation and caller contract errors from silently changing models.
            return false // Requires the caller to stop or repair the request.
        case .profileNotFound, .serverDisabled, .backendMismatch, .authenticationUnavailable, .httpStatus, .incompatibleAPI, .malformedResponse, .malformedToolCall, .timedOut, .connectionLost, .networkUnavailable, .transport: // Covers remote availability and compatibility failures.
            return true // Allows only the router's already configured compatible fallback policy.
        } // Ends fallback classification.
    } // Ends fallback eligibility.

    var errorDescription: String? { // Produces a concise redacted message suitable for UI traces.
        switch self { // Selects the matching bounded failure description.
        case .invalidTarget: // Handles requests addressed to another transport or local location.
            return "The generation target is not a remote OpenAI-compatible model." // Explains the typed target mismatch.
        case .profileNotFound: // Handles removed configuration.
            return "The selected remote server profile no longer exists." // Avoids echoing stale identifiers.
        case .serverDisabled: // Handles an explicitly disabled profile.
            return "The selected remote server is disabled." // Preserves the user's configuration decision.
        case .backendMismatch: // Handles adapter/profile mismatch.
            return "The selected server requires a different remote backend adapter." // Explains the typed transport mismatch.
        case .authenticationUnavailable: // Handles missing Keychain state.
            return "This server requires a bearer token, but no token is available." // Reports missing auth without credential detail.
        case .unsupportedAttachments: // Handles unverified modality input.
            return "This remote text backend has not verified attachment support." // Prevents accidental multimodal claims or transmission.
        case .invalidRequest(let message): // Handles a caller-side schema or bound violation.
            return message // Returns the already bounded request diagnostic.
        case .httpStatus(let code, let message): // Handles non-success HTTP responses.
            return "Remote server returned HTTP \(code): \(message)" // Combines only status and redacted bounded provider text.
        case .incompatibleAPI(let message): // Handles discovery or response-contract incompatibility.
            return message // Returns the already bounded compatibility diagnostic.
        case .malformedResponse(let message): // Handles response normalization failures.
            return message // Returns the already bounded structure diagnostic.
        case .malformedToolCall(let message): // Handles unsafe native tool-call payloads.
            return message // Returns the already bounded tool-call diagnostic.
        case .timedOut: // Handles configured deadline expiration.
            return "The remote server request timed out." // Avoids misreporting timeout as permanent model degradation.
        case .cancelled: // Handles cooperative cancellation.
            return "The remote server request was cancelled." // Distinguishes user cancellation from server failure.
        case .connectionLost: // Handles reachability loss during inference.
            return "The connection to the remote server was lost." // Reports a retry/fallback-ready private-network failure.
        case .networkUnavailable: // Handles a process-specific unavailable network path, including macOS local-network privacy denial.
            return "This Mac cannot access the remote server. Check AutoMLX Studio in System Settings > Privacy & Security > Local Network, then check the Mac network connection." // Gives the user a way to repair permission or connectivity without claiming the server itself failed.
        case .transport(let message): // Handles other bounded networking failures.
            return message // Returns only sanitized transport text.
        } // Ends remote failure rendering.
    } // Ends localized remote error presentation.
} // Ends typed remote inference failures.

actor RemoteInferenceBackend: ModelInferenceBackend { // Implements multi-profile OpenAI-compatible inference with actor-isolated discovery caching.
    private struct DiscoveryCacheEntry: Sendable { // Stores one conservative per-server discovery snapshot.
        let models: [RemoteDiscoveredModel] // Stores only normalized trustworthy remote model records.
        let observedAt: Date // Records when the server was actually queried.
        let serverKind: String? // Stores a bounded detected server label from response headers.
        let latencyMilliseconds: Int // Stores measured API response latency.
    } // Ends the discovery cache entry.

    private struct OpenAIModelsResponse: Decodable { // Decodes only the documented portion of an OpenAI-compatible model listing.
        struct Item: Decodable { // Decodes one provider model record.
            let id: String // Reads the only metadata required and safe to trust universally.
        } // Ends the provider model item.
        let data: [Item] // Reads the returned model collection.
    } // Ends the provider discovery response.

    private struct OpenAIChatRequest: Encodable { // Encodes only intentionally supported OpenAI-compatible generation fields.
        struct Message: Encodable { // Encodes one normalized conversation message.
            struct AssistantToolCall: Encodable { // Re-encodes a prior normalized assistant function request for multi-turn context.
                struct Function: Encodable { // Encodes one prior function name and strict JSON argument string.
                    let name: String // Stores the previously validated local tool name.
                    let arguments: String // Stores the prior arguments as a provider-compatible JSON object string.
                } // Ends prior assistant function content.
                let id: String // Stores the prior provider correlation identifier.
                let type: String // Fixes the only supported native call type to function.
                let function: Function // Stores the normalized prior function content.
            } // Ends the prior assistant tool-call value.

            let role: String // Stores the provider-compatible role.
            let content: String // Stores the selected textual content.
            let toolCallID: String? // Correlates tool results with native calls when present.
            let name: String? // Optionally identifies a tool result.
            let toolCalls: [AssistantToolCall]? // Preserves prior assistant-native calls only when the message owns them.

            enum CodingKeys: String, CodingKey { // Maps normalized Swift names to stable API field names.
                case role // Keeps the standard role key.
                case content // Keeps the standard content key.
                case toolCallID = "tool_call_id" // Maps the native tool correlation field.
                case name // Keeps the optional tool name key.
                case toolCalls = "tool_calls" // Maps prior assistant function requests for valid tool-result context.
            } // Ends message coding keys.
        } // Ends the provider request message.

        struct Tool: Encodable { // Encodes one locally implemented function schema for native model selection.
            struct Function: Encodable { // Encodes the provider function declaration.
                let name: String // Stores the validated function name.
                let description: String // Stores concise function guidance.
                let parameters: JSONValue // Stores the validated object-shaped JSON Schema.
            } // Ends the function declaration.
            let type: String // Fixes the provider tool type to function.
            let function: Function // Stores the normalized function declaration.
        } // Ends the provider tool declaration.

        let model: String // Selects the exact discovered remote model identifier.
        let messages: [Message] // Sends normalized system, conversation, and tool-result messages.
        let tools: [Tool]? // Sends native function schemas only when present.
        let temperature: Double? // Sends temperature only when deliberately configured.
        let maxTokens: Int? // Sends an output limit only when deliberately configured.
        let stop: [String]? // Sends explicit stop sequences only when present.
        let stream: Bool // Explicitly requests a complete non-streaming response from this bounded adapter.

        enum CodingKeys: String, CodingKey { // Maps normalized Swift names to OpenAI-compatible field names.
            case model // Keeps the standard model key.
            case messages // Keeps the standard messages key.
            case tools // Keeps the standard tools key.
            case temperature // Keeps the standard temperature key.
            case maxTokens = "max_tokens" // Maps the standard output-token field.
            case stop // Keeps the standard stop key.
            case stream // Keeps the standard streaming-selection key.
        } // Ends chat request coding keys.
    } // Ends the provider chat request.

    private struct OpenAIChatResponse: Decodable { // Decodes only provider fields required by the normalized result.
        struct Choice: Decodable { // Decodes one completion choice.
            struct Message: Decodable { // Decodes assistant text and native tool calls.
                struct ToolCall: Decodable { // Decodes one provider-native function request.
                    struct Function: Decodable { // Decodes the function name and JSON argument string.
                        let name: String // Reads the requested local tool name.
                        let arguments: String // Reads the provider's strict JSON argument envelope.
                    } // Ends provider function-call content.
                    let id: String // Reads the correlation identifier.
                    let type: String? // Reads the optional provider call type for strict validation.
                    let function: Function // Reads the requested function data.
                } // Ends provider-native tool call.
                let content: String? // Reads optional assistant text.
                let toolCalls: [ToolCall]? // Reads optional native function requests.

                enum CodingKeys: String, CodingKey { // Maps provider snake-case fields.
                    case content // Keeps the standard assistant content key.
                    case toolCalls = "tool_calls" // Maps the native tool-call collection.
                } // Ends response message coding keys.
            } // Ends provider response message.
            let message: Message // Reads the normalized assistant message container.
            let finishReason: String? // Reads the optional provider completion reason.

            enum CodingKeys: String, CodingKey { // Maps provider snake-case fields.
                case message // Keeps the standard message key.
                case finishReason = "finish_reason" // Maps the standard completion reason key.
            } // Ends response choice coding keys.
        } // Ends provider response choice.

        struct Usage: Decodable { // Decodes optional standard token accounting.
            let promptTokens: Int? // Reads input-token usage when supplied.
            let completionTokens: Int? // Reads output-token usage when supplied.
            let totalTokens: Int? // Reads total-token usage when supplied.

            enum CodingKeys: String, CodingKey { // Maps provider snake-case usage fields.
                case promptTokens = "prompt_tokens" // Maps input-token accounting.
                case completionTokens = "completion_tokens" // Maps output-token accounting.
                case totalTokens = "total_tokens" // Maps total-token accounting.
            } // Ends usage coding keys.
        } // Ends provider usage data.

        let model: String? // Reads the actual provider model identifier when returned.
        let choices: [Choice] // Reads completion choices and lets the adapter select one deterministically.
        let usage: Usage? // Reads optional usage accounting.
    } // Ends the provider chat response.

    private struct OpenAIErrorEnvelope: Decodable { // Decodes only the common bounded provider error message.
        struct Body: Decodable { // Decodes the nested error object.
            let message: String? // Reads optional human-readable server text for redacted diagnostics.
        } // Ends the provider error body.
        let error: Body // Reads the common nested error envelope.
    } // Ends provider error-envelope decoding.

    nonisolated let id: ModelBackendID = .remoteOpenAICompatible // Exposes a stable transport identity without requiring actor hops.
    private let profileProvider: any RemoteServerProfileProviding // Resolves current multi-server snapshots and boundary-only credentials.
    private let session: URLSession // Owns the injected cancellable network transport.
    private let cacheTTL: TimeInterval // Controls conservative discovery reuse without polling servers aggressively.
    private let maximumDiscoveryBytes = 2 * 1_024 * 1_024 // Bounds model-list memory to two MiB.
    private let maximumGenerationBytes = 16 * 1_024 * 1_024 // Bounds complete chat responses to sixteen MiB.
    private let maximumToolArgumentBytes = 64 * 1_024 // Bounds each strict native tool argument envelope to sixty-four KiB.
    private var discoveryCache: [UUID: DiscoveryCacheEntry] = [:] // Stores independent cache entries for every configured server.

    init(profileProvider: any RemoteServerProfileProviding, session: URLSession = .shared, cacheTTL: TimeInterval = 30) { // Creates an adapter with injectable persistence and deterministic network transport.
        self.profileProvider = profileProvider // Stores the multi-profile configuration boundary.
        self.session = session // Stores the injectable URLSession used by health, discovery, and generation.
        self.cacheTTL = max(0, cacheTTL) // Prevents negative cache lifetimes while allowing tests to disable caching.
    } // Ends remote backend construction.

    func health(for target: ModelGenerationTarget) async -> ModelBackendHealth { // Performs a real API-level compatibility check rather than a TCP-only probe.
        let checkedAt = Date() // Captures a stable observation timestamp before asynchronous work.
        do { // Converts typed transport outcomes into evidence-based health state.
            let (serverID, profile) = try await resolve(target: target) // Resolves and validates the exact configured server snapshot.
            let token = try await authorizationToken(for: profile) // Retrieves authentication only at the request boundary.
            let observation = try await performDiscovery(serverID: serverID, profile: profile, token: token) // Queries and decodes the actual models API.
            discoveryCache[serverID] = observation // Refreshes the conservative per-server cache after a live check.
            let targetExists = observation.models.contains { $0.id == target.modelID } // Checks the selected model against the compatible discovery response.
            let status: ModelBackendHealthStatus = targetExists ? .healthy : .degraded // Distinguishes a usable selected model from a compatible server missing that model.
            let error = targetExists ? nil : "The server API is compatible, but the selected model was not discovered." // Produces a concise actionable model-level diagnostic.
            return ModelBackendHealth(status: status, latencyMilliseconds: observation.latencyMilliseconds, checkedAt: checkedAt, serverKind: observation.serverKind, apiCompatible: true, discoveredModelCount: observation.models.count, conciseError: error) // Returns the complete API-level health observation.
        } catch let error as RemoteInferenceError { // Handles all typed remote outcomes deterministically.
            let status: ModelBackendHealthStatus // Selects a health state without treating cancellation as degradation.
            switch error { // Classifies only available evidence.
            case .cancelled: // Handles user or parent-task cancellation.
                status = .unknown // Avoids changing model health from a user action.
            case .timedOut, .connectionLost, .transport: // Handles server reachability failures.
                status = .serverOffline // Records that the usable API could not be reached.
            case .networkUnavailable: // Handles a Mac-side path or permission failure rather than a proven server outage.
                status = .unavailable // Keeps a process-local restriction separate from server-offline health.
            case .incompatibleAPI, .malformedResponse, .malformedToolCall, .httpStatus: // Handles reachable but unusable protocol behavior.
                status = .degraded // Records an API-level compatibility problem.
            case .invalidTarget, .profileNotFound, .serverDisabled, .backendMismatch, .authenticationUnavailable, .unsupportedAttachments, .invalidRequest: // Handles configuration or caller availability failures.
                status = .unavailable // Records that this target cannot currently be used.
            } // Ends health error classification.
            return ModelBackendHealth(status: status, latencyMilliseconds: nil, checkedAt: checkedAt, serverKind: nil, apiCompatible: false, discoveredModelCount: nil, conciseError: error.localizedDescription) // Returns a bounded redacted failed observation.
        } catch { // Handles unexpected provider/store failures through the same redaction boundary.
            let message = Self.redacted(error.localizedDescription, knownSecrets: []) // Sanitizes and bounds the unexpected diagnostic.
            return ModelBackendHealth(status: .serverOffline, latencyMilliseconds: nil, checkedAt: checkedAt, serverKind: nil, apiCompatible: false, discoveredModelCount: nil, conciseError: message) // Avoids crashing or claiming API health.
        } // Ends API-level health checking.
    } // Ends backend health observation.

    func discoverModels(serverID: UUID, forceRefresh: Bool = false) async throws -> [RemoteDiscoveredModel] { // Lists one configured server's models with conservative per-profile caching.
        if !forceRefresh, let cached = discoveryCache[serverID], Date().timeIntervalSince(cached.observedAt) < cacheTTL { // Reuses only a fresh exact-server snapshot.
            return cached.models // Avoids hammering the private server.
        } // Ends fresh-cache handling.
        guard let storedProfile = try await profileProvider.profile(id: serverID) else { // Resolves the exact current profile snapshot.
            throw RemoteInferenceError.profileNotFound // Reports removal without racing stale mutable configuration.
        } // Ends profile existence validation.
        let profile = try storedProfile.validated() // Revalidates the snapshot before endpoint construction.
        guard profile.isEnabled else { // Honors the user's explicit enabled state.
            throw RemoteInferenceError.serverDisabled // Prevents disabled server network traffic.
        } // Ends enabled-state validation.
        guard profile.backendID == id else { // Restricts this adapter to OpenAI-compatible profiles.
            throw RemoteInferenceError.backendMismatch // Leaves optional Ollama behavior to its own future adapter.
        } // Ends backend-type validation.
        let token = try await authorizationToken(for: profile) // Retrieves an optional bearer token only for this network operation.
        let observation = try await performDiscovery(serverID: serverID, profile: profile, token: token) // Queries and normalizes the real models endpoint.
        discoveryCache[serverID] = observation // Stores one isolated per-server cache entry.
        return observation.models // Returns only normalized remote model records.
    } // Ends remote model discovery.

    func invalidateDiscoveryCache(serverID: UUID? = nil) { // Supports explicit refresh and profile-removal coordination without server polling.
        if let serverID { // Handles one exact profile invalidation.
            discoveryCache.removeValue(forKey: serverID) // Removes only the matching server snapshot.
        } else { // Handles deliberate full refresh.
            discoveryCache.removeAll(keepingCapacity: true) // Clears observations while retaining bounded dictionary capacity.
        } // Ends cache invalidation selection.
    } // Ends discovery cache invalidation.

    func generate(request: ModelGenerationRequest) async throws -> ModelGenerationResult { // Executes one complete OpenAI-compatible generation and normalizes its response.
        try Task.checkCancellation() // Stops before profile, Keychain, or network work when already cancelled.
        let (_, profile) = try await resolve(target: request.target) // Resolves the exact immutable server snapshot selected by routing.
        guard request.attachments.isEmpty else { // Requires verified modality support before transmitting attachment payloads.
            throw RemoteInferenceError.unsupportedAttachments // Keeps the V0.6 adapter text-and-tools only.
        } // Ends attachment capability enforcement.
        let payload = try makeChatPayload(from: request) // Validates and encodes only supported provider fields.
        let token = try await authorizationToken(for: profile) // Retrieves authentication only immediately before constructing the request.
        let endpoint = try endpoint(named: "chat/completions", profile: profile) // Builds the credential-free generation URL.
        var urlRequest = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: profile.inferenceTimeoutSeconds) // Creates a bounded non-caching generation request.
        urlRequest.httpMethod = "POST" // Selects the documented OpenAI-compatible generation method.
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type") // Declares the strict JSON request body.
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept") // Requests a complete JSON response rather than HTML or streaming data.
        if let token { // Adds authentication only for profiles explicitly configured to require it.
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") // Constructs the sensitive header solely at the network boundary.
        } // Ends boundary-only authentication construction.
        urlRequest.httpBody = payload // Attaches the provider payload without any application object serialization.
        let start = ContinuousClock.now // Starts monotonic duration measurement immediately before transport.
        let (data, response) = try await perform(urlRequest, knownToken: token) // Executes the cancellable bounded HTTP request.
        let duration = Self.milliseconds(since: start) // Converts monotonic elapsed time into trace-friendly milliseconds.
        guard data.count <= maximumGenerationBytes else { // Rejects unexpectedly large complete responses before decoding.
            throw RemoteInferenceError.malformedResponse("Remote generation response exceeded the 16 MiB safety limit.") // Reports a bounded structural failure.
        } // Ends response-size enforcement.
        try validateHTTP(response: response, data: data, token: token) // Converts non-success or non-HTTP responses into typed redacted failures.
        let providerResponse: OpenAIChatResponse // Holds the strictly decoded provider response.
        do { // Bounds JSON decoder diagnostics that may include provider fragments.
            providerResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data) // Decodes only declared standard fields.
        } catch { // Handles malformed or incompatible provider JSON.
            throw RemoteInferenceError.malformedResponse("Remote generation response was not valid OpenAI-compatible JSON.") // Avoids exposing raw response content.
        } // Ends provider response decoding.
        guard let choice = providerResponse.choices.first else { // Requires at least one usable completion choice.
            throw RemoteInferenceError.malformedResponse("Remote generation response contained no choices.") // Rejects an unusable success envelope.
        } // Ends completion-choice validation.
        let toolCalls = try normalizeToolCalls(choice.message.toolCalls ?? []) // Strictly validates every native function request before exposing it locally.
        let text = choice.message.content // Preserves optional assistant text alongside native tool calls.
        guard text != nil || !toolCalls.isEmpty else { // Requires actual normalized model output.
            throw RemoteInferenceError.malformedResponse("Remote generation response contained neither text nor tool calls.") // Rejects an empty success envelope safely.
        } // Ends normalized-content validation.
        let usage = try normalizeUsage(providerResponse.usage) // Validates optional non-negative usage accounting.
        let actualModel = providerResponse.model?.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes optional provider model identity.
        let resultModelID = actualModel.flatMap { $0.isEmpty ? nil : $0 } ?? request.target.modelID // Uses a non-empty reported model or safely retains the requested target identity.
        return ModelGenerationResult(text: text, toolCalls: toolCalls, usage: usage, finishReason: choice.finishReason.map(ModelFinishReason.init(rawValue:)), modelID: resultModelID, backendID: id, durationMilliseconds: duration) // Returns a complete provider-neutral generation result.
    } // Ends remote generation.

    private func resolve(target: ModelGenerationTarget) async throws -> (UUID, RemoteServerProfile) { // Resolves a typed target to one validated immutable profile snapshot.
        guard target.backendID == id, case .remote(let serverID) = target.location, !target.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { // Requires this adapter, one explicit server, and one exact model identifier.
            throw RemoteInferenceError.invalidTarget // Rejects local, other-backend, or empty-model requests.
        } // Ends typed target validation.
        guard let storedProfile = try await profileProvider.profile(id: serverID) else { // Reads the current exact profile snapshot.
            throw RemoteInferenceError.profileNotFound // Reports concurrent removal safely.
        } // Ends profile existence validation.
        let profile: RemoteServerProfile // Holds the normalized non-secret snapshot.
        do { // Converts configuration errors into a transport-safe domain error.
            profile = try storedProfile.validated() // Revalidates endpoint fields at request time.
        } catch { // Handles malformed persisted or injected configuration.
            throw RemoteInferenceError.transport(Self.redacted(error.localizedDescription, knownSecrets: [])) // Avoids leaking raw profile data.
        } // Ends profile validation.
        guard profile.isEnabled else { // Honors current user disablement before Keychain or network access.
            throw RemoteInferenceError.serverDisabled // Stops disabled server use.
        } // Ends enabled-state enforcement.
        guard profile.backendID == id else { // Requires the exact adapter selected by the profile.
            throw RemoteInferenceError.backendMismatch // Prevents accidental OpenAI/Ollama protocol mixing.
        } // Ends backend-type enforcement.
        return (serverID, profile) // Returns the stable server identity and immutable validated snapshot.
    } // Ends target resolution.

    private func authorizationToken(for profile: RemoteServerProfile) async throws -> String? { // Retrieves authentication only at the network boundary.
        switch profile.authenticationMode { // Honors the explicit persisted auth configuration.
        case .none: // Handles intentionally unauthenticated private servers.
            return nil // Constructs no Authorization header.
        case .bearerToken: // Handles Keychain-backed bearer authentication.
            let token = try await profileProvider.token(for: profile.id) // Reads the credential without adding it to request models or cache.
            guard let token, !token.isEmpty else { // Requires a non-empty secret when bearer mode is selected.
                throw RemoteInferenceError.authenticationUnavailable // Reports missing Keychain state without exposing content.
            } // Ends token presence validation.
            return token // Returns the secret only to immediate request construction.
        } // Ends authentication mode selection.
    } // Ends boundary-only token resolution.

    private func performDiscovery(serverID: UUID, profile: RemoteServerProfile, token: String?) async throws -> DiscoveryCacheEntry { // Performs and normalizes one real models API request.
        let endpoint = try endpoint(named: "models", profile: profile) // Builds the credential-free discovery endpoint.
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: profile.connectionTimeoutSeconds) // Creates a bounded fresh API request.
        request.httpMethod = "GET" // Selects the documented discovery method.
        request.setValue("application/json", forHTTPHeaderField: "Accept") // Requests JSON rather than a server HTML page.
        if let token { // Handles profiles that explicitly require bearer authentication.
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") // Constructs the sensitive header only at this network boundary.
        } // Ends discovery authentication construction.
        let start = ContinuousClock.now // Begins monotonic API latency measurement.
        let (data, response) = try await perform(request, knownToken: token) // Executes the cancellable discovery request.
        let latency = Self.milliseconds(since: start) // Converts elapsed time to trace-friendly milliseconds.
        guard data.count <= maximumDiscoveryBytes else { // Rejects unexpectedly large model listings before decoding.
            throw RemoteInferenceError.incompatibleAPI("Remote model listing exceeded the 2 MiB safety limit.") // Reports a bounded compatibility failure.
        } // Ends discovery-size enforcement.
        try validateHTTP(response: response, data: data, token: token) // Rejects status, HTML, and non-HTTP failures before decoding.
        let providerResponse: OpenAIModelsResponse // Holds the strict discovery envelope.
        do { // Bounds raw decoder diagnostics.
            providerResponse = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data) // Decodes only the standard model identifier list.
        } catch { // Handles HTML success pages or incompatible JSON shapes.
            throw RemoteInferenceError.incompatibleAPI("Server did not return a valid OpenAI-compatible model listing.") // Avoids claiming health from a TCP or arbitrary HTTP response.
        } // Ends discovery decoding.
        var seenIDs = Set<String>() // Tracks duplicate provider model identifiers deterministically.
        var models: [RemoteDiscoveredModel] = [] // Collects normalized trustworthy discovery records.
        for item in providerResponse.data { // Validates every returned provider record.
            let modelID = item.id.trimmingCharacters(in: .whitespacesAndNewlines) // Removes accidental surrounding whitespace.
            guard !modelID.isEmpty, modelID.count <= 1_024 else { // Requires a bounded usable provider identifier.
                throw RemoteInferenceError.incompatibleAPI("Server returned an invalid model identifier.") // Rejects ambiguous discovery data.
            } // Ends model identifier validation.
            guard seenIDs.insert(modelID).inserted else { // Detects duplicate records without treating them as separate models.
                continue // Keeps the first stable provider occurrence only.
            } // Ends duplicate handling.
            models.append(RemoteDiscoveredModel(id: modelID, serverID: serverID, backendID: id, availability: .available, capabilities: ModelCapabilityProfile())) // Records only proven identity, location, backend, and availability while leaving capabilities unknown.
        } // Ends provider model normalization.
        let serverKind = Self.detectServerKind(response: response) // Derives an optional bounded label from response headers only.
        return DiscoveryCacheEntry(models: models, observedAt: Date(), serverKind: serverKind, latencyMilliseconds: latency) // Returns one complete live observation for health and cache use.
    } // Ends live model discovery.

    private func makeChatPayload(from request: ModelGenerationRequest) throws -> Data { // Validates and encodes a bounded OpenAI-compatible request body.
        let modelID = request.target.modelID.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes the selected provider model identifier.
        guard !modelID.isEmpty, modelID.count <= 1_024 else { // Requires a bounded exact model selection.
            throw RemoteInferenceError.invalidRequest("Remote model identifier is empty or too long.") // Rejects invalid provider addressing.
        } // Ends model identifier validation.
        if let temperature = request.temperature, (!temperature.isFinite || temperature < 0 || temperature > 2) { // Validates only explicitly supplied OpenAI-compatible sampling values.
            throw RemoteInferenceError.invalidRequest("Temperature must be between 0 and 2.") // Rejects non-finite or out-of-range sampling values.
        } // Ends temperature validation.
        if let maximum = request.maxOutputTokens, !(1...1_000_000).contains(maximum) { // Requires a positive bounded output limit when supplied.
            throw RemoteInferenceError.invalidRequest("Maximum output tokens must be between 1 and 1000000.") // Rejects impossible or effectively unbounded generation values.
        } // Ends output-token validation.
        guard request.stopSequences.count <= 16, request.stopSequences.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1_024 }) else { // Bounds explicit stop configuration.
            throw RemoteInferenceError.invalidRequest("Stop sequences must contain at most 16 non-empty values of at most 1024 bytes each.") // Rejects excessive provider options.
        } // Ends stop-sequence validation.
        var messages: [OpenAIChatRequest.Message] = [] // Collects normalized provider messages.
        if !request.systemInstructions.isEmpty { // Sends centralized instructions only when present.
            messages.append(OpenAIChatRequest.Message(role: ModelMessageRole.system.rawValue, content: request.systemInstructions, toolCallID: nil, name: nil, toolCalls: nil)) // Adds one explicit system message before conversational context.
        } // Ends system instruction mapping.
        messages.append(contentsOf: try request.messages.map { message in // Maps backend-neutral conversation items without application objects.
            guard message.assistantToolCalls.isEmpty || message.role == .assistant else { // Allows native calls only on the assistant message that originally requested them.
                throw RemoteInferenceError.invalidRequest("Only assistant messages may contain prior native tool calls.") // Rejects malformed conversation topology before network transmission.
            } // Ends prior call role validation.
            let assistantCalls = try message.assistantToolCalls.map { call -> OpenAIChatRequest.Message.AssistantToolCall in // Re-encodes each normalized prior call deterministically.
                guard !call.id.isEmpty, call.id.utf8.count <= 512, Self.isValidToolName(call.name) else { // Revalidates bounded identity and tool-name grammar at the provider boundary.
                    throw RemoteInferenceError.invalidRequest("Prior assistant tool calls contain an invalid identifier or tool name.") // Rejects corrupted persisted context safely.
                } // Ends prior call identity validation.
                let argumentData: Data // Holds the strict object JSON for one prior call.
                do { // Bounds JSON encoding errors without reflecting argument values.
                    let encoder = JSONEncoder() // Creates a deterministic provider argument encoder.
                    encoder.outputFormatting = [.sortedKeys] // Stabilizes prior argument ordering for reproducible requests and tests.
                    argumentData = try encoder.encode(JSONValue.object(call.arguments)) // Encodes only the normalized object-shaped argument dictionary.
                } catch { // Handles an unexpected argument encoding failure.
                    throw RemoteInferenceError.invalidRequest("Prior assistant tool-call arguments could not be encoded safely.") // Avoids exposing argument content.
                } // Ends prior argument encoding.
                guard argumentData.count <= maximumToolArgumentBytes, let arguments = String(data: argumentData, encoding: .utf8) else { // Enforces the same size and UTF-8 contract used for incoming calls.
                    throw RemoteInferenceError.invalidRequest("Prior assistant tool-call arguments exceed the safe size or encoding limit.") // Rejects unsafe conversation context.
                } // Ends prior argument bounds validation.
                let function = OpenAIChatRequest.Message.AssistantToolCall.Function(name: call.name, arguments: arguments) // Builds the provider-compatible prior function content.
                return OpenAIChatRequest.Message.AssistantToolCall(id: call.id, type: "function", function: function) // Returns one valid native prior call without executing it.
            } // Ends prior assistant tool-call encoding.
            return OpenAIChatRequest.Message(role: message.role.rawValue, content: message.content, toolCallID: message.toolCallID, name: message.name, toolCalls: assistantCalls.isEmpty ? nil : assistantCalls) // Preserves normalized text, tool-result correlation, and assistant calls.
        }) // Ends normalized multi-turn message mapping.
        guard !messages.isEmpty else { // Requires actual instructions or conversational input.
            throw RemoteInferenceError.invalidRequest("A remote generation request must contain at least one message or system instruction.") // Rejects an empty inference payload.
        } // Ends message presence validation.
        var seenToolNames = Set<String>() // Detects ambiguous duplicate tool declarations.
        let tools = try request.tools.map { schema -> OpenAIChatRequest.Tool in // Validates every locally implemented tool schema before advertising it.
            guard Self.isValidToolName(schema.name), seenToolNames.insert(schema.name).inserted else { // Requires a stable unique function identifier.
                throw RemoteInferenceError.invalidRequest("Tool names must be unique and contain 1 to 64 letters, numbers, underscores, or hyphens.") // Rejects provider-ambiguous function declarations.
            } // Ends tool-name validation.
            guard schema.description.utf8.count <= 4_096 else { // Bounds model-visible tool guidance.
                throw RemoteInferenceError.invalidRequest("Tool descriptions must not exceed 4096 bytes.") // Prevents accidental excessive schema payloads.
            } // Ends tool-description validation.
            guard schema.parameters.objectValue != nil else { // Requires the parameters schema to be a JSON object.
                throw RemoteInferenceError.invalidRequest("Tool parameters must be a JSON object schema.") // Rejects scalar or array schemas before network transmission.
            } // Ends tool schema shape validation.
            return OpenAIChatRequest.Tool(type: "function", function: OpenAIChatRequest.Tool.Function(name: schema.name, description: schema.description, parameters: schema.parameters)) // Maps the validated local capability to the provider declaration.
        } // Ends tool schema normalization.
        let providerRequest = OpenAIChatRequest(model: modelID, messages: messages, tools: tools.isEmpty ? nil : tools, temperature: request.temperature, maxTokens: request.maxOutputTokens, stop: request.stopSequences.isEmpty ? nil : request.stopSequences, stream: false) // Builds the complete intentionally supported payload.
        do { // Bounds encoder diagnostics behind the request domain error.
            return try JSONEncoder().encode(providerRequest) // Encodes only declared provider fields.
        } catch let error as RemoteInferenceError { // Preserves typed validation failures raised during tool mapping.
            throw error // Returns the safe typed error unchanged.
        } catch { // Handles unexpected JSON encoding failure.
            throw RemoteInferenceError.invalidRequest("Remote generation request could not be encoded safely.") // Avoids exposing request contents through encoder diagnostics.
        } // Ends provider request encoding.
    } // Ends provider payload construction.

    private func normalizeToolCalls(_ calls: [OpenAIChatResponse.Choice.Message.ToolCall]) throws -> [ModelToolCall] { // Strictly normalizes provider-native function requests for local execution.
        var seenCallIDs = Set<String>() // Detects duplicate correlation identifiers.
        return try calls.map { call in // Validates every call before returning any normalized collection.
            let callID = call.id.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes the provider correlation identifier.
            let name = call.function.name.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes the requested function name.
            guard !callID.isEmpty, callID.utf8.count <= 512, seenCallIDs.insert(callID).inserted else { // Requires a unique bounded correlation identity.
                throw RemoteInferenceError.malformedToolCall("Remote model returned a missing, duplicate, or excessive tool-call identifier.") // Rejects ambiguous execution correlation.
            } // Ends call identifier validation.
            guard call.type == "function" else { // Accepts only the native function-call type this runtime understands.
                throw RemoteInferenceError.malformedToolCall("Remote model returned an unsupported tool-call type.") // Rejects unknown provider actions safely.
            } // Ends tool-call type validation.
            guard Self.isValidToolName(name) else { // Applies the same strict function-name grammar used by advertised schemas.
                throw RemoteInferenceError.malformedToolCall("Remote model returned an invalid tool name.") // Prevents natural-language or shell-like names from reaching runtime dispatch.
            } // Ends returned tool-name validation.
            guard call.function.arguments.utf8.count <= maximumToolArgumentBytes else { // Bounds argument decoding and downstream memory use.
                throw RemoteInferenceError.malformedToolCall("Remote model tool arguments exceeded the 64 KiB safety limit.") // Rejects an oversized function request.
            } // Ends tool-argument size enforcement.
            guard let data = call.function.arguments.data(using: .utf8) else { // Converts only valid UTF-8 JSON argument text.
                throw RemoteInferenceError.malformedToolCall("Remote model tool arguments were not valid UTF-8.") // Rejects undecodable argument text.
            } // Ends argument byte conversion.
            let decoded: JSONValue // Holds the strict provider-neutral argument value.
            do { // Bounds raw JSON decoder diagnostics.
                decoded = try JSONDecoder().decode(JSONValue.self, from: data) // Decodes strict JSON rather than parsing natural-language commands.
            } catch { // Handles malformed JSON argument strings.
                throw RemoteInferenceError.malformedToolCall("Remote model tool arguments were not valid JSON.") // Rejects unsafe or ambiguous function input.
            } // Ends argument JSON decoding.
            guard let arguments = decoded.objectValue else { // Requires the standard object-shaped function argument contract.
                throw RemoteInferenceError.malformedToolCall("Remote model tool arguments must be a JSON object.") // Rejects scalar, array, and null tool inputs.
            } // Ends argument shape validation.
            return ModelToolCall(id: callID, name: name, arguments: arguments) // Returns a fully validated local runtime request without executing it.
        } // Ends native tool-call normalization.
    } // Ends strict tool-call decoding.

    private func normalizeUsage(_ usage: OpenAIChatResponse.Usage?) throws -> ModelGenerationUsage? { // Validates optional provider token accounting.
        guard let usage else { // Preserves absence rather than inventing metrics.
            return nil // Reports no normalized usage.
        } // Ends absent-usage handling.
        let values = [usage.promptTokens, usage.completionTokens, usage.totalTokens].compactMap { $0 } // Collects only provider-reported counts.
        guard values.allSatisfy({ $0 >= 0 }) else { // Requires non-negative accounting.
            throw RemoteInferenceError.malformedResponse("Remote generation response reported negative token usage.") // Rejects untrustworthy metrics.
        } // Ends usage validation.
        return ModelGenerationUsage(inputTokens: usage.promptTokens, outputTokens: usage.completionTokens, totalTokens: usage.totalTokens) // Returns normalized optional counts without calculating missing fields.
    } // Ends usage normalization.

    private func endpoint(named component: String, profile: RemoteServerProfile) throws -> URL { // Appends one fixed API component to a validated credential-free base URL.
        do { // Converts configuration errors into bounded transport failures.
            return try profile.baseURL().appendingPathComponent(component, isDirectory: false) // Uses Foundation path construction rather than raw string concatenation.
        } catch { // Handles unexpected endpoint construction failure.
            throw RemoteInferenceError.transport("The remote server endpoint could not be constructed safely.") // Avoids echoing raw host or path input.
        } // Ends endpoint construction.
    } // Ends endpoint resolution.

    private func perform(_ request: URLRequest, knownToken: String?) async throws -> (Data, URLResponse) { // Executes one cancellable URLSession request and maps network failures deterministically.
        do { // Converts URLSession and cooperative cancellation errors into the typed remote domain.
            try Task.checkCancellation() // Stops before starting transport if the parent task was cancelled.
            let result = try await session.data(for: request) // Executes through the injected session so tests can remain offline and deterministic.
            try Task.checkCancellation() // Discards a completed response when cancellation won the race.
            return result // Returns response bytes and metadata for bounded validation.
        } catch is CancellationError { // Handles Swift cooperative cancellation directly.
            throw RemoteInferenceError.cancelled // Preserves cancellation as a non-health-changing outcome.
        } catch let error as URLError { // Handles Foundation networking failures by stable error code.
            switch error.code { // Maps only semantics useful to routing and UI.
            case .cancelled: // Handles URLSession cancellation.
                throw RemoteInferenceError.cancelled // Preserves user cancellation separately from server loss.
            case .timedOut: // Handles URLSession deadline expiration.
                throw RemoteInferenceError.timedOut // Exposes an explicit fallback-ready timeout.
            case .notConnectedToInternet: // Handles macOS no-path reports, including a local-network privacy denial.
                throw RemoteInferenceError.networkUnavailable // Preserves the process-side failure category instead of reporting a dropped server connection.
            case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed: // Handles private-server reachability loss.
                throw RemoteInferenceError.connectionLost // Avoids leaking endpoint details from the underlying error.
            default: // Handles other TLS, protocol, and transport failures.
                throw RemoteInferenceError.transport(Self.redacted(error.localizedDescription, knownSecrets: [knownToken].compactMap { $0 })) // Sanitizes any credential echo and bounds the diagnostic.
            } // Ends URL error mapping.
        } catch { // Handles non-URLError transport failures from injected or system protocols.
            if Task.isCancelled { // Detects cancellation wrapped by a custom transport.
                throw RemoteInferenceError.cancelled // Preserves cancellation semantics.
            } // Ends wrapped cancellation handling.
            throw RemoteInferenceError.transport(Self.redacted(error.localizedDescription, knownSecrets: [knownToken].compactMap { $0 })) // Returns only a bounded redacted transport message.
        } // Ends network execution and mapping.
    } // Ends cancellable transport execution.

    private func validateHTTP(response: URLResponse, data: Data, token: String?) throws { // Requires a successful HTTP JSON API response before provider decoding.
        guard let http = response as? HTTPURLResponse else { // Rejects arbitrary URLProtocol responses without HTTP semantics.
            throw RemoteInferenceError.incompatibleAPI("Remote server did not return an HTTP response.") // Avoids equating transport completion with API compatibility.
        } // Ends HTTP response validation.
        guard (200...299).contains(http.statusCode) else { // Converts every non-success status into a bounded redacted typed failure.
            let message = Self.providerErrorMessage(data: data, token: token) // Extracts only safe concise provider text.
            throw RemoteInferenceError.httpStatus(code: http.statusCode, message: message) // Preserves status for routing and diagnostics.
        } // Ends HTTP status validation.
        if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(), !contentType.contains("json") { // Rejects common HTML success pages while tolerating absent headers from compatible local servers.
            throw RemoteInferenceError.incompatibleAPI("Remote server response was not JSON.") // Prevents a false healthy state from an unrelated web service.
        } // Ends content-type compatibility validation.
    } // Ends HTTP response validation.

    private static func providerErrorMessage(data: Data, token: String?) -> String { // Extracts one bounded provider error without exposing response bodies or credentials.
        let limited = Data(data.prefix(64 * 1_024)) // Bounds error decoding to sixty-four KiB.
        if let envelope = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: limited), let message = envelope.error.message, !message.isEmpty { // Prefers the common structured provider error field.
            return redacted(message, knownSecrets: [token].compactMap { $0 }) // Sanitizes and bounds structured server text.
        } // Ends structured provider error extraction.
        if let text = String(data: limited, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { // Uses plain text only as a bounded diagnostic fallback.
            return redacted(text, knownSecrets: [token].compactMap { $0 }) // Removes known and likely credentials before presentation.
        } // Ends plain-text error extraction.
        return "The server returned an error without a readable message." // Supplies a stable fallback without raw bytes.
    } // Ends provider error normalization.

    private static func redacted(_ input: String, knownSecrets: [String]) -> String { // Removes credential-shaped text and enforces a concise log/UI bound.
        var value = input // Copies the untrusted diagnostic for in-memory sanitization.
        for secret in knownSecrets where !secret.isEmpty { // Removes every exact credential currently known at the request boundary.
            value = value.replacingOccurrences(of: secret, with: "[REDACTED]") // Replaces all literal secret occurrences.
        } // Ends exact-secret redaction.
        let patterns = [ // Defines conservative credential patterns independent from any provider.
            "(?i)bearer\\s+[A-Za-z0-9._~+\\-/=]+", // Matches Authorization bearer values.
            "(?i)(authorization|api[_-]?key|token)(\\s*[:=]\\s*)[^\\s,;\\\"']+", // Matches common labeled credential fields.
            "(?i)sk-[A-Za-z0-9_-]{8,}" // Matches common API-key-shaped values without assuming a cloud dependency.
        ] // Ends credential-pattern declarations.
        for pattern in patterns { // Applies every conservative pattern to the untrusted text.
            guard let expression = try? NSRegularExpression(pattern: pattern) else { // Keeps an internal regex construction failure from affecting inference.
                continue // Skips only the invalid internal pattern.
            } // Ends regex construction.
            let range = NSRange(value.startIndex..<value.endIndex, in: value) // Maps the current Swift string to the regular-expression range.
            value = expression.stringByReplacingMatches(in: value, range: range, withTemplate: "[REDACTED]") // Replaces credential-shaped substrings.
        } // Ends pattern-based redaction.
        let singleLine = value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) // Produces compact UI-safe text.
        guard singleLine.count > 512 else { // Enforces a concise provider diagnostic limit.
            return singleLine.isEmpty ? "Remote server request failed." : singleLine // Returns non-empty bounded text.
        } // Ends diagnostic-length check.
        return String(singleLine.prefix(509)) + "..." // Truncates without including additional untrusted content.
    } // Ends log and UI redaction.

    private static func detectServerKind(response: URLResponse) -> String? { // Derives a best-effort server label only from HTTP response headers.
        guard let http = response as? HTTPURLResponse else { // Requires HTTP header semantics.
            return nil // Reports no detected server kind for other response types.
        } // Ends HTTP response validation.
        if http.value(forHTTPHeaderField: "x-lmstudio-version") != nil { // Detects LM Studio's explicit version header without persisting the value.
            return "LM Studio" // Returns the stable server family label.
        } // Ends LM Studio detection.
        if let server = http.value(forHTTPHeaderField: "Server"), !server.isEmpty { // Uses a standard server header when available.
            return String(redacted(server, knownSecrets: []).prefix(100)) // Bounds and sanitizes the untrusted header value.
        } // Ends standard server-header detection.
        return nil // Preserves unknown rather than guessing a server family.
    } // Ends server-kind detection.

    private static func isValidToolName(_ name: String) -> Bool { // Applies one strict provider-compatible function-name grammar.
        guard (1...64).contains(name.utf8.count) else { // Bounds names before regular-expression work.
            return false // Rejects empty and excessive names.
        } // Ends tool-name length validation.
        return name.unicodeScalars.allSatisfy { scalar in // Validates every Unicode scalar against the ASCII function-name grammar.
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-" // Allows only letters, digits, underscore, and hyphen.
        } // Ends tool-name scalar validation.
    } // Ends strict tool-name validation.

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int { // Converts monotonic duration into bounded whole milliseconds.
        let duration = start.duration(to: .now) // Measures elapsed monotonic time.
        let components = duration.components // Reads integer seconds and attoseconds without floating-point clock drift.
        let milliseconds = components.seconds * 1_000 + Int64(components.attoseconds / 1_000_000_000_000_000) // Converts attoseconds to milliseconds and combines them with seconds.
        return Int(clamping: milliseconds) // Safely clamps an extreme duration to the platform Int range.
    } // Ends duration conversion.
} // Ends the actor-isolated OpenAI-compatible remote inference backend.
