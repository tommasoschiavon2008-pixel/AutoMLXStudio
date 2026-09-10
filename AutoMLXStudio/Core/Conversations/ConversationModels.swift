import Foundation // Supplies Codable persistence, stable UUID values, dates, and deterministic string normalization.

enum AgentExecutionQuality: String, CaseIterable, Identifiable, Equatable, Sendable { // Represents an optional user-selected quality policy without coupling conversations to transient agent objects.
    case fast = "Fast" // Favors the shortest supported workflow and lowest practical latency.
    case balanced = "Balanced" // Uses the product's normal latency-versus-quality policy.
    case thorough = "Thorough" // Favors the fullest supported review and composition workflow.

    var id: String { rawValue } // Gives SwiftUI a stable display-friendly identity.
} // Ends the persisted execution-quality choices.

extension AgentExecutionQuality: Codable { // Adds tolerant decoding so earlier lowercase prototypes remain readable.
    init(from decoder: Decoder) throws { // Decodes one case-insensitive persisted quality value.
        let container = try decoder.singleValueContainer() // Opens the single raw-string value.
        let value = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() // Normalizes legacy capitalization without accepting unrelated values.
        switch value { // Maps the bounded persisted vocabulary to the typed policy.
        case "fast": self = .fast // Restores the fast policy.
        case "balanced": self = .balanced // Restores the balanced policy.
        case "thorough": self = .thorough // Restores the thorough policy.
        default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown agent execution quality.") // Rejects unknown future or corrupted values explicitly.
        } // Ends quality-value selection.
    } // Ends tolerant quality decoding.

    func encode(to encoder: Encoder) throws { // Persists the stable human-readable raw value.
        var container = encoder.singleValueContainer() // Opens the single-value encoder.
        try container.encode(rawValue) // Writes exactly Fast, Balanced, or Thorough.
    } // Ends stable quality encoding.
} // Ends Codable support for execution quality.

enum ConversationPersistenceSchema { // Publishes the local snapshot compatibility boundary for migrations and tests.
    static let minimumSupportedVersion = 0 // Accepts the explicit prototype schema and legacy unwrapped conversation arrays.
    static let currentVersion = 1 // Writes the first production schema containing memory and quality preferences.
} // Ends conversation schema-version constants.

struct Conversation: Identifiable, Codable, Equatable, Sendable { // Stores only user-visible chat data and durable preferences, never runtime prompts or private reasoning.
    static let maximumTitleLength = 80 // Bounds editable titles so persistence and sidebar presentation remain predictable.
    static let defaultTitle = "New Conversation" // Supplies a deterministic title until a visible user message exists.

    let id: UUID // Stores the stable conversation identity across renames and application restarts.
    var projectID: UUID? // Associates the chat with one project without embedding project documents in conversation storage.
    var title: String // Stores the deterministic or explicitly edited visible title.
    var messages: [ChatMessage] // Stores only existing visible user and assistant messages with their public attachment metadata.
    let createdAt: Date // Records when the conversation was first persisted.
    var updatedAt: Date // Records the latest durable message or metadata mutation.
    var useProjectMemory: Bool // Persists the user's retrieval preference independently for each conversation.
    var qualityOverride: AgentExecutionQuality? // Persists an optional override while nil continues to use the application default.
    var titleWasEdited: Bool // Prevents a later first message from overwriting an explicitly renamed title.

    init(id: UUID = UUID(), projectID: UUID? = nil, title: String? = nil, messages: [ChatMessage] = [], createdAt: Date = Date(), updatedAt: Date? = nil, useProjectMemory: Bool? = nil, qualityOverride: AgentExecutionQuality? = nil, titleWasEdited: Bool? = nil) { // Creates a complete backward-compatible conversation value.
        self.id = id // Stores the supplied or generated durable identity.
        self.projectID = projectID // Stores the optional project association.
        self.messages = messages // Stores only the caller-supplied visible history.
        self.title = title.map(Self.normalizedTitleText) ?? Self.derivedTitle(from: messages) // Uses an explicit normalized title or derives one without an LLM call.
        self.createdAt = createdAt // Stores the immutable creation time.
        self.updatedAt = updatedAt ?? createdAt // Uses creation time until the first durable mutation.
        self.useProjectMemory = useProjectMemory ?? (projectID != nil) // Defaults memory ON for project chats and OFF for ordinary chats.
        self.qualityOverride = qualityOverride // Stores a real override only when the user selected one.
        self.titleWasEdited = titleWasEdited ?? (title != nil) // Treats an explicitly supplied title as user-owned by default.
    } // Ends complete conversation construction.

    static func derivedTitle(from messages: [ChatMessage]) -> String { // Derives a stable bounded title from the first non-empty visible user message.
        guard let userText = messages.lazy.filter({ $0.role.caseInsensitiveCompare("user") == .orderedSame }).map({ normalizedTitleText($0.content) }).first(where: { !$0.isEmpty }) else { return defaultTitle } // Ignores assistant text and blank user entries without invoking a model.
        guard userText.count > maximumTitleLength else { return userText } // Preserves short visible requests exactly after whitespace normalization.
        let contentLimit = maximumTitleLength - 1 // Reserves one character for the visible ellipsis.
        let hardPrefix = String(userText.prefix(contentLimit)) // Takes a Unicode-character-safe bounded prefix.
        if let lastSpace = hardPrefix.lastIndex(of: " ") { // Looks for a natural word boundary inside the bounded prefix.
            let boundaryLength = hardPrefix.distance(from: hardPrefix.startIndex, to: lastSpace) // Measures the candidate boundary in user-visible characters.
            if boundaryLength >= maximumTitleLength / 2 { return String(hardPrefix[..<lastSpace]) + "…" } // Uses a reasonably late word boundary instead of producing an excessively short title.
        } // Ends natural-boundary handling.
        return hardPrefix + "…" // Falls back to a hard Unicode-safe truncation for a long uninterrupted token.
    } // Ends deterministic title derivation.

    static func normalizedTitleText(_ value: String) -> String { // Produces one-line deterministic visible title text.
        value.split(whereSeparator: { $0.isWhitespace }).map(String.init).joined(separator: " ") // Collapses all whitespace runs while preserving every non-whitespace character.
    } // Ends title normalization.

    private enum CodingKeys: String, CodingKey { // Defines stable keys for current and legacy conversation JSON.
        case id // Persists stable identity.
        case projectID // Persists optional project ownership.
        case title // Persists the editable visible title.
        case messages // Persists visible chat history.
        case createdAt // Persists creation time.
        case updatedAt // Persists last mutation time.
        case useProjectMemory // Persists the retrieval preference introduced with schema version one.
        case qualityOverride // Persists the optional quality override introduced with schema version one.
        case titleWasEdited // Persists whether deterministic title replacement remains allowed.
    } // Ends conversation coding keys.

    init(from decoder: Decoder) throws { // Restores current conversations and safely supplies defaults for earlier records.
        let container = try decoder.container(keyedBy: CodingKeys.self) // Opens the stable keyed representation.
        id = try container.decode(UUID.self, forKey: .id) // Requires the durable identity rather than silently replacing it.
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID) // Restores optional project ownership.
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? [] // Treats a missing legacy message collection as empty.
        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title).map(Self.normalizedTitleText) // Normalizes a legacy multiline title when present.
        title = decodedTitle ?? Self.derivedTitle(from: messages) // Derives a title only when the persisted legacy record has none.
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0) // Gives timestamp-free prototypes a deterministic migration value.
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt // Preserves creation time when a legacy update timestamp is absent.
        useProjectMemory = try container.decodeIfPresent(Bool.self, forKey: .useProjectMemory) ?? (projectID != nil) // Migrates missing preferences to the documented project-aware default.
        qualityOverride = try container.decodeIfPresent(AgentExecutionQuality.self, forKey: .qualityOverride) // Leaves legacy conversations on the application-wide quality policy.
        let derivedTitle = Self.derivedTitle(from: messages) // Computes the only title an unedited legacy record would have received.
        titleWasEdited = try container.decodeIfPresent(Bool.self, forKey: .titleWasEdited) ?? (title != derivedTitle) // Infers edit ownership without overwriting a distinct legacy title.
    } // Ends backward-compatible conversation decoding.
} // Ends durable conversation metadata and history.

enum ConversationListScope: Equatable, Sendable { // Makes project filtering explicit instead of overloading a nil project identifier.
    case all // Includes normal and project conversations.
    case project(UUID) // Includes only conversations owned by one exact project UUID.
    case withoutProject // Includes only ordinary conversations with no project association.
} // Ends explicit conversation-list scopes.

enum ConversationStoreError: LocalizedError, Equatable, Sendable { // Defines typed bounded failures for validation, lookup, schema, corruption, and persistence.
    case invalidTitle(String) // Reports an empty or overlong editable title with bounded detail.
    case invalidMessageRole(String) // Prevents hidden system or internal-role messages from entering visible conversation persistence.
    case conversationNotFound(UUID) // Reports selection-independent lookup or mutation of an unknown identity.
    case conversationAlreadyExists(UUID) // Prevents an explicit UUID from silently replacing an existing conversation.
    case unsupportedSchemaVersion(Int) // Reports a snapshot written by an incompatible future schema.
    case corruptedStore(String) // Reports malformed or internally inconsistent JSON without exposing unbounded decoder output.
    case persistenceFailed(String) // Reports bounded local filesystem or encoding failures.

    var errorDescription: String? { // Produces concise diagnostics suitable for tests and future UI presentation.
        switch self { // Selects the exact typed failure description.
        case let .invalidTitle(detail): return "Invalid conversation title: \(detail)" // Explains title validation failure.
        case let .invalidMessageRole(role): return "Conversation messages may contain only visible user or assistant roles; received \(role)." // Explains the no-hidden-prompt storage boundary.
        case let .conversationNotFound(id): return "Conversation was not found: \(id.uuidString)." // Identifies the missing stable UUID.
        case let .conversationAlreadyExists(id): return "Conversation already exists: \(id.uuidString)." // Identifies the conflicting stable UUID.
        case let .unsupportedSchemaVersion(version): return "Unsupported conversation schema version: \(version)." // Identifies the incompatible snapshot version.
        case let .corruptedStore(detail): return "Conversation storage is corrupted: \(detail)" // Reports bounded decoder or invariant evidence.
        case let .persistenceFailed(detail): return "Conversation persistence failed: \(detail)" // Reports bounded filesystem or encoder evidence.
        } // Ends typed error-description selection.
    } // Ends localized conversation-store errors.
} // Ends typed conversation persistence failures.
