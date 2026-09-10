import Foundation // Supplies Codable, UUID, Date, and URL value support for transport-independent backend contracts.

enum ModelBackendID: String, Codable, CaseIterable, Hashable, Sendable { // Gives every inference transport a stable typed identity.
    case localMLX = "local-mlx" // Identifies the existing in-process Mac MLX execution path.
    case remoteOpenAICompatible = "remote-openai-compatible" // Identifies private OpenAI-compatible HTTP inference servers.
    case remoteOllama = "remote-ollama" // Reserves a stable identity for a future bounded Ollama adapter.
} // Ends the stable backend identifier definition.

enum ModelExecutionLocation: Codable, Equatable, Hashable, Sendable { // Distinguishes local model resources from server-owned remote models.
    case local // Represents a model whose lifecycle belongs to this Mac.
    case remote(serverID: UUID) // Represents a model managed by one explicitly configured remote server.
} // Ends the execution-location definition.

struct ModelGenerationTarget: Codable, Equatable, Hashable, Sendable { // Identifies the exact transport and physical model for one generation.
    let backendID: ModelBackendID // Selects the backend implementation without raw-string comparisons.
    let location: ModelExecutionLocation // Records whether resources live on the Mac or on a configured server.
    let modelID: String // Stores the provider-facing model identifier without assuming a filesystem path.
} // Ends the concrete generation-target model.

enum ModelCapabilityKind: String, Codable, CaseIterable, Hashable, Sendable { // Lists capabilities that a backend or discovered model may report reliably.
    case text // Represents ordinary text generation support.
    case toolCalling = "tool-calling" // Represents native structured function-call support.
    case vision // Represents image-input understanding support.
    case embeddings // Represents vector embedding generation support.
    case reranking // Represents result reranking support.
    case streaming // Represents incremental response delivery support.
} // Ends the capability-kind taxonomy.

enum ModelCapabilitySupport: String, Codable, Equatable, Sendable { // Preserves uncertainty instead of converting missing metadata into false claims.
    case unknown // Indicates the server supplied no trustworthy capability evidence.
    case supported // Indicates the capability is known to be available.
    case unsupported // Indicates the capability is known to be unavailable.
} // Ends the tri-state capability value.

struct ModelCapabilityProfile: Codable, Equatable, Sendable { // Stores independently known support for every optional model capability.
    private var values: [ModelCapabilityKind: ModelCapabilitySupport] // Keeps only explicit observations while treating omissions as unknown.

    init(values: [ModelCapabilityKind: ModelCapabilitySupport] = [:]) { // Creates a capability profile from trustworthy observations only.
        self.values = values // Retains the supplied observations without inventing missing metadata.
    } // Ends capability-profile construction.

    func support(for capability: ModelCapabilityKind) -> ModelCapabilitySupport { // Resolves one capability while preserving unknown as the default.
        values[capability] ?? .unknown // Returns the explicit observation or an honest unknown state.
    } // Ends capability lookup.

    mutating func set(_ support: ModelCapabilitySupport, for capability: ModelCapabilityKind) { // Updates one capability after actual configuration or validation.
        values[capability] = support // Stores the new evidence without affecting unrelated capability states.
    } // Ends capability mutation.
} // Ends the capability-profile value.

enum JSONValue: Codable, Equatable, Sendable { // Represents bounded provider-neutral JSON used by tool schemas and arguments.
    case string(String) // Stores a JSON string.
    case number(Double) // Stores a finite JSON number.
    case boolean(Bool) // Stores a JSON Boolean.
    case object([String: JSONValue]) // Stores a JSON object with typed child values.
    case array([JSONValue]) // Stores a JSON array with typed child values.
    case null // Stores an explicit JSON null.

    init(from decoder: Decoder) throws { // Decodes one arbitrary JSON value without exposing provider dictionaries.
        let container = try decoder.singleValueContainer() // Reads the value through a single-value container.
        if container.decodeNil() { // Detects explicit JSON null before attempting scalar decoding.
            self = .null // Preserves the explicit null value.
        } else if let value = try? container.decode(Bool.self) { // Tries Boolean before number because NSNumber can bridge both forms.
            self = .boolean(value) // Stores the decoded Boolean.
        } else if let value = try? container.decode(Double.self) { // Tries a numeric representation after Boolean.
            guard value.isFinite else { // Rejects non-finite values that are invalid in strict JSON.
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "JSON numbers must be finite.") // Reports a bounded structural error.
            } // Ends finite-number validation.
            self = .number(value) // Stores the decoded finite number.
        } else if let value = try? container.decode(String.self) { // Tries a JSON string after scalar numeric forms.
            self = .string(value) // Stores the decoded string.
        } else if let value = try? container.decode([String: JSONValue].self) { // Tries an object before an array.
            self = .object(value) // Stores the recursively decoded object.
        } else if let value = try? container.decode([JSONValue].self) { // Tries a recursively typed array last.
            self = .array(value) // Stores the recursively decoded array.
        } else { // Handles values outside the supported strict JSON domain.
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.") // Rejects malformed or unsupported input safely.
        } // Ends JSON variant selection.
    } // Ends arbitrary JSON decoding.

    func encode(to encoder: Encoder) throws { // Encodes the provider-neutral value as strict JSON.
        var container = encoder.singleValueContainer() // Creates a single-value encoding container.
        switch self { // Selects the matching JSON representation.
        case .string(let value): // Handles string values.
            try container.encode(value) // Encodes the string verbatim.
        case .number(let value): // Handles numeric values.
            guard value.isFinite else { // Prevents invalid NaN and infinity JSON payloads.
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "JSON numbers must be finite.")) // Reports a bounded encoding failure.
            } // Ends finite-number validation.
            try container.encode(value) // Encodes the finite number.
        case .boolean(let value): // Handles Boolean values.
            try container.encode(value) // Encodes the Boolean.
        case .object(let value): // Handles object values.
            try container.encode(value) // Encodes all keyed children recursively.
        case .array(let value): // Handles array values.
            try container.encode(value) // Encodes all ordered children recursively.
        case .null: // Handles explicit JSON null.
            try container.encodeNil() // Encodes the null marker.
        } // Ends JSON encoding selection.
    } // Ends arbitrary JSON encoding.

    var objectValue: [String: JSONValue]? { // Exposes a strictly typed object only when the value is actually an object.
        guard case .object(let object) = self else { // Rejects scalar and array values at the tool boundary.
            return nil // Reports that no object representation exists.
        } // Ends object-shape validation.
        return object // Returns the validated object contents.
    } // Ends strict object extraction.
} // Ends the provider-neutral JSON value.

enum ModelMessageRole: String, Codable, Equatable, Sendable { // Defines roles accepted by backend-neutral conversation messages.
    case system // Represents explicit system-level instructions.
    case user // Represents user-authored input.
    case assistant // Represents model-authored context.
    case tool // Represents a local tool result returned to the model.
} // Ends the message-role definition.

struct ModelGenerationMessage: Codable, Equatable, Sendable { // Carries one normalized conversation item into any model backend.
    let role: ModelMessageRole // Identifies the semantic author of the message.
    let content: String // Stores text only, avoiding provider-specific message dictionaries.
    let toolCallID: String? // Links a tool result to the native call that requested it when applicable.
    let name: String? // Optionally identifies a tool response without embedding runtime objects.
    let assistantToolCalls: [ModelToolCall] // Preserves prior assistant-native calls so subsequent tool results retain valid multi-turn context.

    init(role: ModelMessageRole, content: String, toolCallID: String? = nil, name: String? = nil, assistantToolCalls: [ModelToolCall] = []) { // Creates a normalized message with source-compatible optional tool correlation metadata.
        self.role = role // Stores the semantic role.
        self.content = content // Stores the bounded textual content chosen by the caller.
        self.toolCallID = toolCallID // Stores the optional native tool-call correlation identifier.
        self.name = name // Stores the optional provider-safe tool name.
        self.assistantToolCalls = assistantToolCalls // Stores prior validated calls without executing or flattening them into text.
    } // Ends normalized message construction.
} // Ends the backend-neutral message value.

struct ModelToolSchema: Codable, Equatable, Sendable { // Describes one locally implemented tool to a model without granting execution authority.
    let name: String // Stores the stable function name exposed to the model.
    let description: String // Stores concise usage guidance for the model.
    let parameters: JSONValue // Stores a strict JSON Schema object for arguments.
} // Ends the model-visible tool schema.

enum ModelAttachmentKind: String, Codable, Equatable, Sendable { // Reserves transport-neutral attachment categories for capability-aware backends.
    case image // Represents an image input that requires verified vision support.
    case document // Represents a document reference that requires an explicit backend adapter.
} // Ends the attachment-kind definition.

struct ModelGenerationAttachment: Codable, Equatable, Sendable { // References an attachment without exposing application-specific attachment objects.
    let id: UUID // Supplies a stable correlation identifier.
    let kind: ModelAttachmentKind // Declares the required modality.
    let mimeType: String // Supplies the validated media type.
    let data: Data // Stores the exact bounded payload selected for transmission.
} // Ends the backend-neutral attachment value.

struct ModelGenerationRequest: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible { // Defines one complete inference request independently from HTTP or MLX details.
    let target: ModelGenerationTarget // Selects the backend, server location, and exact model.
    let systemInstructions: String // Carries centralized agent instructions without duplicating agent logic per backend.
    let messages: [ModelGenerationMessage] // Carries normalized recent context and the current user input.
    let tools: [ModelToolSchema] // Advertises locally implemented tools without executing them remotely.
    let temperature: Double? // Supplies optional sampling temperature only when intentionally configured.
    let maxOutputTokens: Int? // Bounds output generation when the target protocol supports the option.
    let stopSequences: [String] // Supplies explicit provider-neutral stop sequences.
    let attachments: [ModelGenerationAttachment] // Carries attachments only to backends that verify matching capability support.

    init(target: ModelGenerationTarget, systemInstructions: String, messages: [ModelGenerationMessage], tools: [ModelToolSchema] = [], temperature: Double? = nil, maxOutputTokens: Int? = nil, stopSequences: [String] = [], attachments: [ModelGenerationAttachment] = []) { // Creates a complete transport-neutral generation request.
        self.target = target // Stores the exact target selection.
        self.systemInstructions = systemInstructions // Stores centralized instructions.
        self.messages = messages // Stores normalized conversational input.
        self.tools = tools // Stores optional native tool definitions.
        self.temperature = temperature // Stores optional temperature without inventing a default.
        self.maxOutputTokens = maxOutputTokens // Stores the optional output bound.
        self.stopSequences = stopSequences // Stores explicit stop conditions.
        self.attachments = attachments // Stores explicitly selected attachments.
    } // Ends request construction.

    var description: String { // Produces a content-safe operational summary for logs and traces.
        "ModelGenerationRequest(target: \(target.modelID), backend: \(target.backendID.rawValue), messages: \(messages.count), tools: \(tools.map(\.name)), attachments: \(attachments.count))" // Omits instructions, message contents, attachment bytes, and all authentication data.
    } // Ends the safe request summary.

    var debugDescription: String { // Keeps debug rendering subject to the same secret-safe boundary.
        description // Reuses the deliberately content-safe operational summary.
    } // Ends safe debug rendering.
} // Ends the backend-neutral generation request.

struct ModelToolCall: Codable, Equatable, Sendable { // Represents one validated native function request returned by a model.
    let id: String // Stores the provider correlation identifier.
    let name: String // Stores the exact local tool name requested by the model.
    let arguments: [String: JSONValue] // Stores only a valid JSON object after strict decoding.
} // Ends the normalized model tool call.

struct ModelGenerationUsage: Codable, Equatable, Sendable { // Normalizes optional provider token accounting without requiring it.
    let inputTokens: Int? // Stores prompt-token usage when reported reliably.
    let outputTokens: Int? // Stores completion-token usage when reported reliably.
    let totalTokens: Int? // Stores total-token usage when reported reliably.
} // Ends normalized generation usage.

struct ModelFinishReason: RawRepresentable, Codable, Equatable, Hashable, Sendable { // Preserves both common and provider-specific completion reasons safely.
    let rawValue: String // Stores the normalized provider reason.

    static let stop = ModelFinishReason(rawValue: "stop") // Identifies a normal text stop.
    static let length = ModelFinishReason(rawValue: "length") // Identifies an output limit.
    static let toolCalls = ModelFinishReason(rawValue: "tool_calls") // Identifies a native tool request.
    static let contentFilter = ModelFinishReason(rawValue: "content_filter") // Identifies provider-side filtering when reported.
} // Ends the normalized finish-reason value.

struct ModelGenerationResult: Codable, Equatable, Sendable { // Normalizes every backend response for agents and routing layers.
    let text: String? // Stores assistant text when supplied.
    let toolCalls: [ModelToolCall] // Stores validated native tool calls for local execution.
    let usage: ModelGenerationUsage? // Stores optional normalized usage accounting.
    let finishReason: ModelFinishReason? // Stores the optional provider completion reason.
    let modelID: String // Stores the actual provider-reported model identifier when available.
    let backendID: ModelBackendID // Records the transport that produced the response.
    let durationMilliseconds: Int // Records end-to-end backend duration for operational tracing.
} // Ends the normalized generation result.

enum ModelBackendHealthStatus: String, Codable, Equatable, Sendable { // Defines evidence-based backend and remote-model health states.
    case unknown // Indicates no reliable health evidence or a user cancellation.
    case healthy // Indicates a compatible API responded successfully.
    case degraded // Indicates the API responded but reported a bounded compatibility issue.
    case unavailable // Indicates this backend or configuration cannot currently serve requests.
    case serverOffline = "server-offline" // Indicates the configured server could not be reached.
} // Ends the backend health-state definition.

struct ModelBackendHealth: Codable, Equatable, Sendable { // Captures one explicit API-level connection check.
    let status: ModelBackendHealthStatus // Stores the evidence-based health state.
    let latencyMilliseconds: Int? // Stores measured API response latency when available.
    let checkedAt: Date // Records when the observation was made.
    let serverKind: String? // Stores a concise detected server identifier only when response headers provide it.
    let apiCompatible: Bool // Indicates whether a usable expected API response was decoded.
    let discoveredModelCount: Int? // Stores the number of models reported by a compatible discovery endpoint.
    let conciseError: String? // Stores a bounded redacted operational error for UI presentation.
} // Ends the backend health observation.

enum RemoteModelAvailability: String, Codable, Equatable, Sendable { // Tracks discovery availability independently from local installation state.
    case available // Indicates the model appeared in a successful server discovery response.
    case unknown // Indicates discovery has not established current availability.
} // Ends remote model availability.

struct RemoteDiscoveredModel: Identifiable, Codable, Equatable, Sendable { // Represents trustworthy metadata returned by one configured remote server.
    let id: String // Stores the provider model identifier and satisfies Identifiable.
    let serverID: UUID // Identifies the configured server that owns the model lifecycle.
    let backendID: ModelBackendID // Identifies the transport required to generate with the model.
    let availability: RemoteModelAvailability // Stores only the availability proven by discovery.
    let capabilities: ModelCapabilityProfile // Preserves unknown capabilities unless explicitly configured or validated.
} // Ends discovered remote model metadata.

protocol ModelInferenceBackend: Sendable { // Defines the transport-independent model execution boundary shared by local and remote adapters without colliding with the established runtime-family enum.
    var id: ModelBackendID { get } // Exposes a stable backend identity for routing and tracing.
    func health(for target: ModelGenerationTarget) async -> ModelBackendHealth // Performs an API-level health observation for a concrete target.
    func generate(request: ModelGenerationRequest) async throws -> ModelGenerationResult // Executes one normalized generation request.
} // Ends the model inference backend protocol.
