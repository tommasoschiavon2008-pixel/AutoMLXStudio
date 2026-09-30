import Foundation // Supplies actor-safe local filesystem access and deterministic Codable JSON persistence.

private struct ConversationStoreSnapshot: Codable { // Wraps all conversation records in an explicitly versioned local transaction.
    let schemaVersion: Int // Records the decoder compatibility contract used by this snapshot.
    var conversations: [Conversation] // Stores only durable visible conversation values and user preferences.
} // Ends the versioned conversation transaction.

private struct ConversationSchemaProbe: Decodable { // Reads the version before decoding a potentially incompatible future payload.
    let schemaVersion: Int // Stores the version value required for compatibility selection.
} // Ends the lightweight schema probe.

actor ConversationStore { // Serializes selection-independent conversation reads and atomic mutations without owning UI selection state.
    static let snapshotFilename = "conversations.json" // Exposes the fixed app-owned filename for deterministic diagnostics and tests.

    private let rootURL: URL // Stores the exact dedicated persistence directory.
    private let snapshotURL: URL // Stores the exact app-owned JSON transaction path.
    private let encoder: JSONEncoder // Reuses one actor-confined deterministic encoder.
    private let decoder: JSONDecoder // Reuses one actor-confined matching decoder.

    init(rootURL: URL? = nil) { // Creates a durable production store or an isolated injectable test store.
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] // Resolves the user-scoped Application Support root.
        let resolvedRoot = rootURL ?? applicationSupport.appendingPathComponent("AutoMLXStudio/Conversations", isDirectory: true) // Uses a dedicated app-owned subtree without touching project documents.
        self.rootURL = resolvedRoot // Stores the resolved containment root.
        self.snapshotURL = resolvedRoot.appendingPathComponent(Self.snapshotFilename, isDirectory: false) // Resolves one fixed filename without user-controlled path components.
        self.encoder = JSONEncoder() // Creates the actor-confined JSON encoder.
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys] // Produces deterministic inspectable snapshots.
        self.encoder.dateEncodingStrategy = .deferredToDate // Uses Date's native reference-epoch representation so persistence preserves every representable subsecond bit without large-epoch arithmetic loss.
        self.decoder = JSONDecoder() // Creates the actor-confined JSON decoder.
        self.decoder.dateDecodingStrategy = .custom { decoder in // Accepts both precise current numbers and ISO-8601 snapshots written by earlier releases.
            let container = try decoder.singleValueContainer() // Opens the one timestamp value without assuming its representation.
            if let seconds = try? container.decode(Double.self) { return Date(timeIntervalSinceReferenceDate: seconds) } // Restores the current lossless Date-native floating-point timestamp.
            let text = try container.decode(String.self) // Reads a legacy timestamp only after numeric decoding does not apply.
            let formatter = ISO8601DateFormatter() // Uses a local mutable formatter so no shared non-Sendable state crosses actor boundaries.
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds] // First accepts legacy ISO-8601 values that retained fractions.
            if let date = formatter.date(from: text) { return date } // Restores a fractional legacy timestamp.
            formatter.formatOptions = [.withInternetDateTime] // Falls back to the original whole-second `.iso8601` snapshots.
            if let date = formatter.date(from: text) { return date } // Restores an original legacy timestamp.
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported conversation timestamp.") // Routes every unknown representation through the existing bounded corruption boundary.
        } // Ends backward-compatible precise timestamp decoding.
    } // Ends store construction.

    func listConversations(scope: ConversationListScope = .all) throws -> [Conversation] { // Lists a deterministic snapshot using an explicit project filter.
        let allConversations = try loadSnapshot().conversations // Reads the latest atomic transaction from disk.
        let filtered: [Conversation] // Declares the exact requested ownership subset.
        switch scope { // Applies filtering without retaining any selected conversation inside the store.
        case .all: filtered = allConversations // Includes every normal and project chat.
        case let .project(projectID): filtered = allConversations.filter { $0.projectID == projectID } // Includes only one exact project UUID.
        case .withoutProject: filtered = allConversations.filter { $0.projectID == nil } // Includes only ordinary non-project chats.
        } // Ends explicit scope filtering.
        return Self.sortedForDisplay(filtered) // Returns newest activity first with stable UUID tie-breaking.
    } // Ends deterministic conversation listing.

    func conversations(projectID: UUID) throws -> [Conversation] { // Provides a concise exact-project lookup for Projects UI integration.
        try listConversations(scope: .project(projectID)) // Delegates to the same isolated filtering and sort policy.
    } // Ends project-specific conversation listing.

    func conversation(id: UUID) throws -> Conversation { // Loads one conversation directly without depending on UI selection.
        let snapshot = try loadSnapshot() // Reads the latest durable transaction.
        guard let conversation = snapshot.conversations.first(where: { $0.id == id }) else { throw ConversationStoreError.conversationNotFound(id) } // Distinguishes an unknown UUID from an empty store.
        return conversation // Returns the exact durable value.
    } // Ends identity-based lookup.

    func createConversation(id: UUID = UUID(), projectID: UUID? = nil, title: String? = nil, messages: [ChatMessage] = [], useProjectMemory: Bool? = nil, qualityOverride: AgentExecutionQuality? = nil, selectedModelTarget: ModelGenerationTarget? = nil, now: Date = Date()) throws -> Conversation { // Creates and immediately persists one complete conversation.
        var snapshot = try loadSnapshot() // Reads the current transaction before checking identity uniqueness.
        guard !snapshot.conversations.contains(where: { $0.id == id }) else { throw ConversationStoreError.conversationAlreadyExists(id) } // Prevents accidental replacement when an explicit UUID is reused.
        try Self.validateVisibleMessages(messages) // Rejects internal system or reasoning-role records at the persistence boundary.
        try Self.validateModelTarget(selectedModelTarget) // Rejects malformed backend and location combinations before persistence.
        let requestedTitle = title.map(Conversation.normalizedTitleText) ?? Conversation.derivedTitle(from: messages) // Uses a normalized explicit title or deterministic first-user-message derivation.
        let validTitle = try Self.validatedTitle(requestedTitle) // Enforces the shared non-empty bounded title contract.
        let conversation = Conversation(id: id, projectID: projectID, title: validTitle, messages: messages, createdAt: now, updatedAt: now, useProjectMemory: useProjectMemory, qualityOverride: qualityOverride, selectedModelTarget: selectedModelTarget, titleWasEdited: title != nil) // Applies documented defaults and preserves the exact optional Chat target.
        snapshot.conversations.append(conversation) // Adds the new stable identity to the in-memory transaction.
        try save(snapshot) // Atomically commits the complete updated collection before returning success.
        return conversation // Returns exactly the persisted conversation.
    } // Ends durable conversation creation.

    func updateConversation(_ candidate: Conversation, now: Date = Date()) throws -> Conversation { // Replaces editable metadata and visible messages by stable UUID while preserving creation identity.
        var snapshot = try loadSnapshot() // Reads the current transaction for a selection-independent update.
        guard let index = snapshot.conversations.firstIndex(where: { $0.id == candidate.id }) else { throw ConversationStoreError.conversationNotFound(candidate.id) } // Requires an existing durable identity.
        let current = snapshot.conversations[index] // Captures immutable creation metadata and current title ownership.
        try Self.validateVisibleMessages(candidate.messages) // Prevents full-value updates from persisting internal roles.
        try Self.validateModelTarget(candidate.selectedModelTarget) // Prevents full-value updates from introducing an invalid target.
        let validTitle = try Self.validatedTitle(candidate.title) // Normalizes and validates the edited visible title.
        let titleWasEdited = candidate.titleWasEdited || validTitle != current.title // Treats a direct title change as an explicit edit even if the caller omitted the flag.
        let updatedAt = max(now, current.updatedAt) // Keeps activity time monotonic if a caller supplies an earlier clock value.
        let updated = Conversation(id: current.id, projectID: candidate.projectID, title: validTitle, messages: candidate.messages, createdAt: current.createdAt, updatedAt: updatedAt, useProjectMemory: candidate.useProjectMemory, qualityOverride: candidate.qualityOverride, selectedModelTarget: candidate.selectedModelTarget, titleWasEdited: titleWasEdited) // Rebuilds the durable value while ignoring attempts to replace identity or creation time.
        snapshot.conversations[index] = updated // Replaces only the matching stable UUID.
        try save(snapshot) // Atomically commits the complete transaction.
        return updated // Returns the normalized persisted value.
    } // Ends full conversation update.

    func append(_ message: ChatMessage, to conversationID: UUID, now: Date = Date()) throws -> Conversation { // Appends one visible message and updates title and activity in one atomic transaction.
        try Self.validateVisibleMessages([message]) // Rejects hidden system or internal-role messages before touching storage.
        var snapshot = try loadSnapshot() // Reads the current durable collection.
        guard let index = snapshot.conversations.firstIndex(where: { $0.id == conversationID }) else { throw ConversationStoreError.conversationNotFound(conversationID) } // Requires one exact destination identity.
        var conversation = snapshot.conversations[index] // Copies the selected value for an isolated mutation.
        let hadUserMessage = conversation.messages.contains(where: { $0.role.caseInsensitiveCompare("user") == .orderedSame && !Conversation.normalizedTitleText($0.content).isEmpty }) // Detects whether deterministic first-user title derivation already occurred.
        conversation.messages.append(message) // Stores the public message value without adding prompts or runtime reasoning fields.
        if !conversation.titleWasEdited && !hadUserMessage && message.role.caseInsensitiveCompare("user") == .orderedSame { conversation.title = Conversation.derivedTitle(from: conversation.messages) } // Derives the title exactly once from the first non-empty user message unless the user renamed it.
        conversation.updatedAt = max(now, conversation.updatedAt) // Advances activity monotonically.
        snapshot.conversations[index] = conversation // Replaces only the destination record.
        try save(snapshot) // Atomically persists the appended message and derived title together.
        return conversation // Returns the complete durable post-append value.
    } // Ends visible-message append.

    func renameConversation(id: UUID, title: String, now: Date = Date()) throws -> Conversation { // Renames one conversation without changing its identity, ownership, or messages.
        var snapshot = try loadSnapshot() // Reads the current durable transaction.
        guard let index = snapshot.conversations.firstIndex(where: { $0.id == id }) else { throw ConversationStoreError.conversationNotFound(id) } // Requires the exact stable identity.
        let validTitle = try Self.validatedTitle(title) // Normalizes and bounds the requested visible title.
        snapshot.conversations[index].title = validTitle // Changes only the display title.
        snapshot.conversations[index].titleWasEdited = true // Prevents automatic derivation from overwriting this explicit choice.
        snapshot.conversations[index].updatedAt = max(now, snapshot.conversations[index].updatedAt) // Records monotonic rename activity.
        try save(snapshot) // Atomically commits the metadata-only mutation.
        return snapshot.conversations[index] // Returns the renamed durable record.
    } // Ends safe conversation rename.

    func setUseProjectMemory(_ enabled: Bool, conversationID: UUID, now: Date = Date()) throws -> Conversation { // Persists the real per-conversation retrieval preference for future workflow integration.
        var snapshot = try loadSnapshot() // Reads the current transaction.
        guard let index = snapshot.conversations.firstIndex(where: { $0.id == conversationID }) else { throw ConversationStoreError.conversationNotFound(conversationID) } // Requires an existing conversation identity.
        snapshot.conversations[index].useProjectMemory = enabled // Stores the user's explicit preference without changing project ownership.
        snapshot.conversations[index].updatedAt = max(now, snapshot.conversations[index].updatedAt) // Records monotonic preference activity.
        try save(snapshot) // Atomically commits the preference.
        return snapshot.conversations[index] // Returns the updated durable record.
    } // Ends memory-preference update.

    func setQualityOverride(_ quality: AgentExecutionQuality?, conversationID: UUID, now: Date = Date()) throws -> Conversation { // Persists or clears the optional quality policy independently of UI selection.
        var snapshot = try loadSnapshot() // Reads the current transaction.
        guard let index = snapshot.conversations.firstIndex(where: { $0.id == conversationID }) else { throw ConversationStoreError.conversationNotFound(conversationID) } // Requires an existing conversation identity.
        snapshot.conversations[index].qualityOverride = quality // Stores the selected policy or nil for the application default.
        snapshot.conversations[index].updatedAt = max(now, snapshot.conversations[index].updatedAt) // Records monotonic preference activity.
        try save(snapshot) // Atomically commits the quality preference.
        return snapshot.conversations[index] // Returns the updated durable record.
    } // Ends quality-preference update.

    func setExecutionMode(_ mode: ChatExecutionMode, conversationID: UUID, now: Date = Date()) throws -> Conversation { // Persists the user-selected agent/direct route without changing model assignments.
        var snapshot = try loadSnapshot() // Opens the current durable conversation transaction.
        guard let index = snapshot.conversations.firstIndex(where: { $0.id == conversationID }) else { throw ConversationStoreError.conversationNotFound(conversationID) } // Requires the exact selected conversation.
        snapshot.conversations[index].executionMode = mode // Changes only the explicit execution-mode preference.
        snapshot.conversations[index].updatedAt = max(now, snapshot.conversations[index].updatedAt) // Records monotonic configuration activity.
        try save(snapshot) // Atomically persists the new route choice.
        return snapshot.conversations[index] // Returns the actual committed value for UI publication.
    } // Ends execution-mode preference update.

    func setSelectedModelTarget(_ target: ModelGenerationTarget?, conversationID: UUID, now: Date = Date()) throws -> Conversation { // Persists one exact Chat inference selection independently of current UI selection.
        try Self.validateModelTarget(target) // Rejects malformed model identities and backend-location mismatches before loading the transaction.
        var snapshot = try loadSnapshot() // Reads the current durable conversation collection.
        guard let index = snapshot.conversations.firstIndex(where: { $0.id == conversationID }) else { throw ConversationStoreError.conversationNotFound(conversationID) } // Requires the exact stable conversation identity.
        snapshot.conversations[index].selectedModelTarget = target // Stores the exact backend-qualified choice or nil for deterministic local default selection.
        snapshot.conversations[index].updatedAt = max(now, snapshot.conversations[index].updatedAt) // Records monotonic preference activity.
        try save(snapshot) // Atomically commits the selection without changing messages or credentials.
        return snapshot.conversations[index] // Returns the complete normalized persisted conversation.
    } // Ends Chat model-selection persistence.

    @discardableResult func deleteConversation(id: UUID) throws -> Conversation { // Deletes only one app-owned conversation record and returns the removed value for caller confirmation.
        var snapshot = try loadSnapshot() // Reads the current durable collection.
        guard let index = snapshot.conversations.firstIndex(where: { $0.id == id }) else { throw ConversationStoreError.conversationNotFound(id) } // Requires an exact stable identity instead of treating a typo as success.
        let removed = snapshot.conversations.remove(at: index) // Removes only the matched in-memory conversation.
        try save(snapshot) // Atomically replaces the app-owned snapshot without touching Project Memory or source documents.
        return removed // Returns the exact deleted record.
    } // Ends single-conversation deletion.

    @discardableResult func deleteConversations(projectID: UUID) throws -> Int { // Applies the explicit policy that project deletion may remove only chats associated with that exact UUID.
        var snapshot = try loadSnapshot() // Reads all conversation ownership metadata.
        let originalCount = snapshot.conversations.count // Captures the collection size before filtering.
        snapshot.conversations.removeAll(where: { $0.projectID == projectID }) // Removes only exact project-owned conversations and never accesses project files.
        let removedCount = originalCount - snapshot.conversations.count // Calculates the number of policy-owned records removed.
        if removedCount > 0 { try save(snapshot) } // Avoids an unnecessary filesystem mutation when the project has no conversations.
        return removedCount // Reports the exact policy effect to the caller.
    } // Ends exact-project conversation deletion.

    private func loadSnapshot() throws -> ConversationStoreSnapshot { // Loads and migrates one complete transaction with typed bounded corruption reporting.
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return ConversationStoreSnapshot(schemaVersion: ConversationPersistenceSchema.currentVersion, conversations: []) } // Treats a never-used store as an empty current-schema transaction.
        let data: Data // Declares the exact app-owned snapshot bytes.
        do { data = try Data(contentsOf: snapshotURL, options: [.mappedIfSafe]) } // Reads only the fixed conversation snapshot path.
        catch { throw ConversationStoreError.persistenceFailed(Self.bounded(error.localizedDescription)) } // Distinguishes filesystem access failure from malformed JSON.
        if let probe = try? decoder.decode(ConversationSchemaProbe.self, from: data) { // Detects a wrapped versioned transaction before decoding its full shape.
            guard probe.schemaVersion >= ConversationPersistenceSchema.minimumSupportedVersion && probe.schemaVersion <= ConversationPersistenceSchema.currentVersion else { throw ConversationStoreError.unsupportedSchemaVersion(probe.schemaVersion) } // Rejects incompatible future and invalid negative schema versions explicitly.
            let decoded: ConversationStoreSnapshot // Declares the compatible full transaction.
            do { decoded = try decoder.decode(ConversationStoreSnapshot.self, from: data) } // Decodes only after the version passes the compatibility boundary.
            catch { throw ConversationStoreError.corruptedStore(Self.bounded(error.localizedDescription)) } // Converts malformed compatible JSON into a bounded typed corruption error.
            try Self.validateLoadedSnapshot(decoded) // Detects duplicate identities, invalid titles, and hidden message roles as corruption.
            return ConversationStoreSnapshot(schemaVersion: ConversationPersistenceSchema.currentVersion, conversations: decoded.conversations) // Migrates supported older wrappers in memory for their next atomic write.
        } // Ends wrapped-schema loading.
        let legacy: [Conversation] // Declares the supported schema-zero unwrapped array representation.
        do { legacy = try decoder.decode([Conversation].self, from: data) } // Restores prototype arrays using Conversation's field-level migration defaults.
        catch { throw ConversationStoreError.corruptedStore(Self.bounded(error.localizedDescription)) } // Reports neither-versioned-nor-legacy payloads as typed bounded corruption.
        let migrated = ConversationStoreSnapshot(schemaVersion: ConversationPersistenceSchema.currentVersion, conversations: legacy) // Wraps the legacy records in the current in-memory schema.
        try Self.validateLoadedSnapshot(migrated) // Validates migrated content before exposing it to application code.
        return migrated // Returns the safe migration transaction for reading or the next atomic mutation.
    } // Ends snapshot loading and migration.

    private func save(_ snapshot: ConversationStoreSnapshot) throws { // Atomically replaces the complete app-owned conversation transaction.
        do { // Contains directory creation, deterministic encoding, and the atomic write as one typed operation.
            try Self.validateMutationSnapshot(snapshot) // Revalidates all visible records before any bytes are written.
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true) // Creates only the dedicated conversation persistence directory.
            let stableConversations = snapshot.conversations.sorted { $0.id.uuidString < $1.id.uuidString } // Orders records independently of UI sorting for deterministic JSON output.
            let currentSnapshot = ConversationStoreSnapshot(schemaVersion: ConversationPersistenceSchema.currentVersion, conversations: stableConversations) // Always upgrades mutations to the current schema version.
            let data = try encoder.encode(currentSnapshot) // Encodes the complete transaction before opening the destination replacement.
            try data.write(to: snapshotURL, options: .atomic) // Replaces only the fixed app-owned JSON file atomically.
        } catch let error as ConversationStoreError { throw error } // Preserves typed validation failures without obscuring their category.
        catch { throw ConversationStoreError.persistenceFailed(Self.bounded(error.localizedDescription)) } // Converts encoder and filesystem failures into bounded domain errors.
    } // Ends atomic snapshot persistence.

    private static func validateLoadedSnapshot(_ snapshot: ConversationStoreSnapshot) throws { // Treats invariant failures originating on disk as store corruption.
        do { try validateMutationSnapshot(snapshot) } // Reuses the exact mutation invariants for decoded records.
        catch { throw ConversationStoreError.corruptedStore(bounded(error.localizedDescription)) } // Reclassifies invalid persisted content with a bounded typed corruption detail.
    } // Ends decoded-snapshot validation.

    private static func validateMutationSnapshot(_ snapshot: ConversationStoreSnapshot) throws { // Enforces identity, title, and visible-message invariants before persistence.
        let identities = snapshot.conversations.map(\.id) // Collects every durable conversation UUID.
        guard Set(identities).count == identities.count else { throw ConversationStoreError.corruptedStore("duplicate conversation identifiers were detected.") } // Prevents ambiguous selection-independent lookups.
        for conversation in snapshot.conversations { // Validates every record in the atomic transaction.
            _ = try validatedTitle(conversation.title) // Enforces one-line non-empty bounded visible titles.
            try validateVisibleMessages(conversation.messages) // Enforces the no-hidden-system-message persistence boundary.
            try validateModelTarget(conversation.selectedModelTarget) // Enforces backend-qualified model identity integrity.
        } // Ends transaction record validation.
    } // Ends mutation-snapshot validation.

    private static func validateVisibleMessages(_ messages: [ChatMessage]) throws { // Allows only public user and assistant records in durable history.
        for message in messages { // Inspects each caller-supplied message role without interpreting its visible content.
            let role = message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() // Normalizes harmless role capitalization and surrounding whitespace.
            guard role == "user" || role == "assistant" else { throw ConversationStoreError.invalidMessageRole(bounded(message.role.isEmpty ? "an empty role" : message.role)) } // Rejects system, developer, tool, reasoning, and unknown internal roles.
        } // Ends visible-role validation.
    } // Ends hidden-message persistence protection.

    private static func validateModelTarget(_ target: ModelGenerationTarget?) throws { // Enforces structural selection integrity without requiring transient discovery state.
        guard let target else { return } // Accepts nil as the documented legacy-compatible deterministic local default.
        let modelID = target.modelID.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes only for validation while preserving the provider identity verbatim.
        guard !modelID.isEmpty else { throw ConversationStoreError.invalidModelSelection("the model identifier is empty.") } // Rejects an unusable empty model identity.
        guard modelID.count <= 1_024 else { throw ConversationStoreError.invalidModelSelection("the model identifier exceeds 1024 characters.") } // Bounds corrupted or malicious persisted identities.
        switch (target.backendID, target.location) { // Validates the only implemented local and remote location combinations.
        case (.localMLX, .local): return // Accepts local MLX only on this Mac.
        case (.remoteOpenAICompatible, .remote), (.remoteOllama, .remote): return // Accepts remote adapters only with one explicit server UUID.
        default: throw ConversationStoreError.invalidModelSelection("the backend does not match its execution location.") // Rejects local-over-remote and remote-over-local ambiguity.
        } // Ends backend-location validation.
    } // Ends structural Chat target validation.

    private static func validatedTitle(_ value: String) throws -> String { // Normalizes and enforces the single shared editable-title contract.
        let normalized = Conversation.normalizedTitleText(value) // Collapses surrounding and repeated whitespace into one visible line.
        guard !normalized.isEmpty else { throw ConversationStoreError.invalidTitle("a title must contain visible text.") } // Rejects empty and whitespace-only titles.
        guard normalized.count <= Conversation.maximumTitleLength else { throw ConversationStoreError.invalidTitle("the \(normalized.count)-character title exceeds the \(Conversation.maximumTitleLength)-character limit.") } // Rejects overlong explicit edits instead of silently losing user text.
        return normalized // Returns exactly the durable normalized title.
    } // Ends title validation.

    private static func sortedForDisplay(_ conversations: [Conversation]) -> [Conversation] { // Produces deterministic newest-activity-first history ordering.
        conversations.sorted { lhs, rhs in // Compares activity, creation, and identity in descending user-facing order.
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt } // Places the most recently mutated chat first.
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt } // Uses creation time as the first stable tie-breaker.
            return lhs.id.uuidString < rhs.id.uuidString // Uses UUID text as a deterministic final tie-breaker.
        } // Ends stable history sorting.
    } // Ends display ordering.

    private static func bounded(_ value: String) -> String { // Produces privacy-safe compact error evidence from filesystem and decoder failures.
        String(value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(240)) // Flattens whitespace and limits all propagated details to 240 characters.
    } // Ends bounded diagnostic formatting.
} // Ends actor-isolated conversation persistence.
