import AppKit // Supplies Finder reveal for an explicitly retained and currently available source URL.
import Foundation // Supplies observable state, dates, URLs, and structured concurrency.

enum DocumentIngestionPhase: String, Equatable, Sendable { // Describes visible non-blocking document pipeline progress.
    case validating = "Validating" // Indicates extension, regular-file, size, and security-scope checks.
    case reading = "Reading" // Indicates bounded local UTF-8 source extraction.
    case chunking = "Chunking" // Indicates deterministic normalized text segmentation.
    case indexing = "Indexing" // Indicates atomic Project Memory persistence and optional index invalidation.
    case ready = "Ready" // Indicates durable lexical memory is available.
    case failed = "Failed" // Indicates a controlled pipeline error with no partial snapshot write.
    case cancelled = "Cancelled" // Indicates user-requested cancellation before completion.
} // Ends ingestion progress states.

struct DocumentIngestionActivity: Identifiable, Equatable, Sendable { // Reports one selected source operation without retaining file contents.
    let id: UUID // Gives SwiftUI stable identity for concurrent imports.
    let sourceURL: URL // Stores the explicitly selected source needed for visible filename and retry.
    var phase: DocumentIngestionPhase // Stores current deterministic pipeline stage.
    var detail: String? // Stores a bounded success, duplicate, cancellation, or failure description.

    init(id: UUID = UUID(), sourceURL: URL, phase: DocumentIngestionPhase, detail: String? = nil) { // Creates one complete visible activity record.
        self.id = id // Stores stable operation identity.
        self.sourceURL = sourceURL // Stores the user-selected source reference.
        self.phase = phase // Stores current pipeline stage.
        self.detail = detail // Stores optional bounded progress evidence.
    } // Ends activity construction.
} // Ends document ingestion activity metadata.

@MainActor
final class WorkspaceController: ObservableObject { // Coordinates project and conversation persistence while leaving model/runtime ownership in AppState.
    @Published private(set) var projectSummaries: [ProjectMemorySummary] = [] // Stores readable projects ordered by recent activity.
    @Published private(set) var storageIssues: [ProjectStorageIssue] = [] // Stores isolated corrupt-snapshot diagnostics without hiding healthy projects.
    @Published private(set) var conversations: [Conversation] = [] // Stores all durable visible conversations ordered by recent activity.
    @Published private(set) var selectedProjectID: UUID? // Stores current Projects selection independently from Chat association.
    @Published private(set) var selectedConversationID: UUID? // Stores current durable Chat selection.
    @Published private(set) var messages: [ChatMessage] = [] // Mirrors only the selected conversation's visible history.
    @Published private(set) var selectedDocuments: [MemoryDocument] = [] // Stores documents for the selected Projects detail surface.
    @Published private(set) var documentStatuses: [UUID: MemoryDocumentStatus] = [:] // Stores source and index state keyed by durable document identity.
    @Published private(set) var ingestionActivities: [DocumentIngestionActivity] = [] // Stores current and recent bounded import progress.
    @Published private(set) var isLoading = false // Reports initial or explicit workspace refresh activity.
    @Published var errorMessage: String? // Stores one concise user-facing workspace failure for inline presentation.

    let memoryStore: ProjectMemoryStore // Owns project-scoped source, chunk, and vector snapshots.
    let conversationStore: ConversationStore // Owns visible conversation history and preferences.
    private var importTask: Task<Void, Never>? // Owns only the current app-started import batch for explicit cancellation.

    init(memoryStore: ProjectMemoryStore = ProjectMemoryStore(), conversationStore: ConversationStore = ConversationStore()) { // Creates a production or injectable test workspace coordinator.
        self.memoryStore = memoryStore // Stores the actor-isolated Project Memory authority.
        self.conversationStore = conversationStore // Stores the actor-isolated conversation authority.
    } // Ends workspace-controller construction.

    var selectedProject: ProjectMemorySummary? { // Resolves current Projects selection from validated catalog summaries.
        guard let selectedProjectID else { return nil } // Returns no project when selection is empty.
        return projectSummaries.first { $0.id == selectedProjectID } // Returns the exact selected project summary.
    } // Ends selected project lookup.

    var selectedConversation: Conversation? { // Resolves current Chat selection from durable visible conversations.
        guard let selectedConversationID else { return nil } // Returns no chat when selection is empty.
        return conversations.first { $0.id == selectedConversationID } // Returns the exact selected conversation.
    } // Ends selected conversation lookup.

    var conversationProject: ProjectMemorySummary? { // Resolves the project visibly associated with the selected conversation.
        guard let projectID = selectedConversation?.projectID else { return nil } // Distinguishes normal chat from Project Chat.
        return projectSummaries.first { $0.id == projectID } // Returns actual readable project metadata when available.
    } // Ends conversation-project lookup.

    func load() async { // Restores project catalog and conversations without blocking the main thread on filesystem work.
        isLoading = true // Shows initial workspace loading state.
        defer { isLoading = false } // Clears loading state on every success or controlled failure path.
        do { // Attempts independent actor-isolated storage reads.
            let catalog = try await memoryStore.catalog() // Loads healthy project summaries and isolated snapshot issues.
            let restoredConversations = try await conversationStore.listConversations() // Loads visible conversation history with schema validation.
            projectSummaries = catalog.projects // Publishes readable projects atomically.
            storageIssues = catalog.issues // Publishes recoverable storage diagnostics independently.
            conversations = restoredConversations // Publishes all durable conversations.
            if let currentID = selectedConversationID, restoredConversations.contains(where: { $0.id == currentID }) { await selectConversation(currentID) } // Preserves a valid in-session selection across refresh.
            else if let first = restoredConversations.first { await selectConversation(first.id) } // Opens the most recently active durable chat.
            else { _ = try await createConversation(projectID: nil) } // Creates one persisted normal conversation for a first launch.
            if let selectedProjectID, catalog.projects.contains(where: { $0.id == selectedProjectID }) { await selectProject(selectedProjectID) } // Refreshes current project detail when still available.
            else { selectedProjectID = catalog.projects.first?.id; await refreshSelectedProjectDetails() } // Selects the most recently active project without creating one implicitly.
            errorMessage = nil // Clears an earlier workspace error after a complete refresh.
        } catch { // Keeps the application usable when one root persistence operation fails.
            errorMessage = Self.bounded(error.localizedDescription) // Shows concise actionable persistence evidence.
        } // Ends workspace restoration recovery.
    } // Ends workspace loading.

    @discardableResult
    func createProject(name: String) async throws -> Project { // Creates and immediately publishes one durable project.
        let project = try await memoryStore.createProject(name: name) // Applies storage validation and atomic persistence first.
        await refreshProjects() // Reloads actual summary counts and ordering after commit.
        await selectProject(project.id) // Opens the newly created project detail.
        return project // Returns exact persisted project metadata.
    } // Ends project creation.

    func renameProject(id: UUID, name: String) async throws { // Renames project metadata without changing any ownership identity.
        _ = try await memoryStore.renameProject(id: id, name: name) // Applies validation and atomic update.
        await refreshProjects() // Publishes actual renamed metadata and stable relationships.
    } // Ends project rename.

    func deleteProject(id: UUID) async throws { // Applies the explicit policy that project-owned conversations are deleted with app-owned project memory.
        try await memoryStore.deleteProject(id: id) // Deletes only the containment-proven UUID snapshot and never any source URL.
        _ = try await conversationStore.deleteConversations(projectID: id) // Deletes only app-owned conversations associated with the removed project.
        if selectedProjectID == id { selectedProjectID = nil; selectedDocuments = []; documentStatuses = [:] } // Clears stale project-detail state.
        if selectedConversation?.projectID == id { selectedConversationID = nil; messages = [] } // Clears stale Project Chat selection when its explicit deletion policy ran.
        await load() // Reloads both stores and creates a normal conversation only if no chat remains.
    } // Ends explicit project deletion policy.

    func selectProject(_ id: UUID?) async { // Opens one project summary and its document detail without changing Chat.
        selectedProjectID = id // Publishes the requested Projects selection.
        await refreshSelectedProjectDetails() // Loads only the selected project's source and status metadata.
    } // Ends project selection.

    @discardableResult
    func createConversation(projectID: UUID?) async throws -> Conversation { // Creates a normal or Project Chat with documented memory defaults.
        let conversation = try await conversationStore.createConversation(projectID: projectID) // Persists stable identity and preference before UI selection.
        await refreshConversations() // Publishes actual durable ordering.
        await selectConversation(conversation.id) // Opens the new empty conversation.
        return conversation // Returns exact persisted conversation metadata.
    } // Ends conversation creation.

    func selectConversation(_ id: UUID) async { // Opens an existing durable conversation by stable identity.
        do { // Attempts exact actor-isolated lookup.
            let conversation = try await conversationStore.conversation(id: id) // Loads the authoritative durable value.
            selectedConversationID = id // Publishes stable Chat selection.
            messages = conversation.messages // Publishes only visible history.
            if let projectID = conversation.projectID, projectSummaries.contains(where: { $0.id == projectID }) { selectedProjectID = projectID } // Keeps Projects selection aligned when entering Project Chat.
            errorMessage = nil // Clears an earlier selection error.
        } catch { // Reports a stale or corrupt conversation selection without crashing Chat.
            errorMessage = Self.bounded(error.localizedDescription) // Publishes concise lookup evidence.
        } // Ends conversation selection recovery.
    } // Ends conversation selection.

    func appendMessage(_ message: ChatMessage) async throws { // Atomically persists a visible message before publishing it in selected Chat history.
        let conversationID = try requireSelectedConversationID() // Requires a durable destination rather than an in-memory orphan.
        let updated = try await conversationStore.append(message, to: conversationID) // Applies visible-role validation, title derivation, and atomic save.
        messages = updated.messages // Publishes exactly the committed visible history.
        await refreshConversations(preservingMessages: true) // Updates title and activity ordering without replacing current messages again.
    } // Ends visible message append.

    func setUseProjectMemory(_ enabled: Bool) async throws { // Persists the selected conversation's actual retrieval eligibility control.
        let conversationID = try requireSelectedConversationID() // Requires a durable selected chat.
        let updated = try await conversationStore.setUseProjectMemory(enabled, conversationID: conversationID) // Atomically updates one conversation preference.
        replaceConversation(updated) // Publishes the exact persisted preference without reloading every record.
    } // Ends Project Memory preference update.

    func setQualityOverride(_ quality: AgentExecutionQuality?) async throws { // Persists an optional per-conversation agent execution policy.
        let conversationID = try requireSelectedConversationID() // Requires a durable selected chat.
        let updated = try await conversationStore.setQualityOverride(quality, conversationID: conversationID) // Atomically stores Fast, Balanced, Thorough, or inheritance.
        replaceConversation(updated) // Publishes exact persisted policy.
    } // Ends per-conversation quality update.

    func renameConversation(id: UUID, title: String) async throws { // Renames one visible chat without invoking an LLM.
        let updated = try await conversationStore.renameConversation(id: id, title: title) // Applies normalized bounded title validation atomically.
        replaceConversation(updated) // Publishes exact persisted title and activity.
        await refreshConversations(preservingMessages: true) // Restores display ordering after the mutation.
    } // Ends conversation rename.

    func deleteConversation(id: UUID) async throws { // Deletes only one app-owned visible conversation transaction entry.
        try await conversationStore.deleteConversation(id: id) // Removes the exact stable identity atomically.
        if selectedConversationID == id { selectedConversationID = nil; messages = [] } // Clears stale visible selection.
        await load() // Opens the next recent conversation or creates one normal empty chat.
    } // Ends conversation deletion.

    func startProjectChat(projectID: UUID) async throws { // Creates a new project-associated chat and navigationally prepares it for opening.
        _ = try await createConversation(projectID: projectID) // Persists default memory ON and selects the new chat.
    } // Ends Project Chat creation.

    func importDocuments(_ urls: [URL], projectID: UUID) { // Starts one cancellable sequential import batch outside the main actor's heavy work.
        importTask?.cancel() // Cancels only the prior batch task owned by this controller.
        ingestionActivities = urls.map { DocumentIngestionActivity(sourceURL: $0, phase: .validating) } // Publishes one visible operation per selected source.
        let activities = ingestionActivities // Captures stable operation identities and source order for the task.
        importTask = Task { [weak self] in // Owns the complete batch and allows explicit cancellation.
            guard let self else { return } // Stops when the workspace controller no longer exists.
            for activity in activities { // Processes files sequentially to bound memory and disk pressure.
                if Task.isCancelled { self.updateActivity(activity.id, phase: .cancelled, detail: "Import cancelled."); continue } // Marks remaining work honestly after cancellation.
                do { // Attempts validate, read, chunk, and atomic index stages.
                    self.updateActivity(activity.id, phase: .reading, detail: nil) // Reports bounded file reading before leaving the main actor.
                    let sourceURL = activity.sourceURL // Captures one Sendable Foundation value for detached extraction.
                    let extracted = try await Task.detached(priority: .utility) { try MemoryDocumentIngestor().extract(from: sourceURL) }.value // Performs metadata, security scope, read, normalization, and hashing away from SwiftUI.
                    try Task.checkCancellation() // Stops before project mutation when cancellation arrived after reading.
                    self.updateActivity(activity.id, phase: .chunking, detail: nil) // Reports deterministic segmentation stage.
                    self.updateActivity(activity.id, phase: .indexing, detail: nil) // Reports the imminent atomic snapshot transaction.
                    _ = try await self.memoryStore.addExtractedDocument(projectID: projectID, extracted: extracted) // Commits source metadata and chunks without any embedding claim.
                    self.updateActivity(activity.id, phase: .ready, detail: "Lexical memory ready.") // Reports actual immediately available retrieval capability.
                } catch is CancellationError { // Handles cooperative cancellation without an error traceback.
                    self.updateActivity(activity.id, phase: .cancelled, detail: "Import cancelled.") // Reports explicit user cancellation.
                } catch { // Handles unsupported, duplicate, read, or persistence failure independently per file.
                    self.updateActivity(activity.id, phase: .failed, detail: Self.bounded(error.localizedDescription)) // Shows a concise controlled diagnostic while continuing the batch.
                } // Ends one import recovery boundary.
            } // Ends sequential source processing.
            await self.refreshProjects() // Publishes final counts and last-activity ordering.
            if self.selectedProjectID == projectID { await self.refreshSelectedProjectDetails() } // Refreshes visible document rows for the open project.
        } // Ends owned import task.
    } // Ends document batch import.

    func cancelDocumentImport() { // Cancels only the current controller-owned import task.
        importTask?.cancel() // Propagates cooperative cancellation into extraction and between files.
        importTask = nil // Releases the completed or cancelling task handle.
    } // Ends document import cancellation.

    func reindexDocument(_ document: MemoryDocument) async throws { // Replaces one externally changed source only after explicit user action.
        guard let sourceURL = document.sourceURL else { throw ProjectMemoryError.fileUnavailable("this document has no retained external source.") } // Refuses to invent an original source for internal text.
        let extracted = try await Task.detached(priority: .utility) { try MemoryDocumentIngestor().extract(from: sourceURL) }.value // Performs security-scoped read, normalization, and hashing away from SwiftUI.
        _ = try await memoryStore.reindexDocument(projectID: document.projectID, documentID: document.id, extracted: extracted) // Atomically replaces only affected chunks and proven-compatible vectors.
        await refreshProjects() // Publishes updated activity and index counts.
        await refreshSelectedProjectDetails() // Publishes updated document and source state.
    } // Ends explicit document reindex.

    func removeDocument(_ document: MemoryDocument) async throws { // Removes only app-owned memory records and never the retained original source.
        try await memoryStore.removeDocument(projectID: document.projectID, documentID: document.id) // Atomically removes document, chunks, and referenced vectors.
        await refreshProjects() // Publishes updated project counts.
        await refreshSelectedProjectDetails() // Removes the row from visible detail.
    } // Ends contained document removal.

    func revealSource(_ document: MemoryDocument) { // Reveals a retained source only when it still exists locally.
        guard let sourceURL = document.sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) else { errorMessage = "The original source is not currently available."; return } // Avoids claiming a missing file can be revealed.
        NSWorkspace.shared.activateFileViewerSelecting([sourceURL]) // Uses the standard Finder reveal action for the exact retained URL.
    } // Ends source reveal.

    private func refreshProjects() async { // Reloads project summaries and isolated issues after a durable mutation.
        do { let catalog = try await memoryStore.catalog(); projectSummaries = catalog.projects; storageIssues = catalog.issues } // Publishes one consistent resilient catalog.
        catch { errorMessage = Self.bounded(error.localizedDescription) } // Preserves current UI and reports bounded root failure.
    } // Ends project catalog refresh.

    private func refreshConversations(preservingMessages: Bool = false) async { // Reloads durable conversation ordering after a mutation.
        do { conversations = try await conversationStore.listConversations(); if !preservingMessages, let selectedConversationID { messages = try await conversationStore.conversation(id: selectedConversationID).messages } } // Publishes current records and optionally selected history.
        catch { errorMessage = Self.bounded(error.localizedDescription) } // Reports bounded persistence failure without clearing visible history.
    } // Ends conversation refresh.

    private func refreshSelectedProjectDetails() async { // Loads only the selected project's documents and status metadata.
        guard let selectedProjectID else { selectedDocuments = []; documentStatuses = [:]; return } // Clears detail for no selection.
        do { // Attempts consistent actor-isolated document and status reads.
            let documents = try await memoryStore.documents(projectID: selectedProjectID) // Loads durable internal source records.
            let statuses = try await memoryStore.documentStatuses(projectID: selectedProjectID) // Computes current source and index state.
            selectedDocuments = documents // Publishes actual document order.
            documentStatuses = Dictionary(uniqueKeysWithValues: statuses.map { ($0.documentID, $0) }) // Publishes stable identity-based status lookups.
            errorMessage = nil // Clears an earlier detail error after successful refresh.
        } catch { // Handles a project deleted or corrupted between catalog and detail reads.
            selectedDocuments = [] // Avoids showing stale document contents.
            documentStatuses = [:] // Avoids showing stale status values.
            errorMessage = Self.bounded(error.localizedDescription) // Reports concise detail failure.
        } // Ends selected-project detail recovery.
    } // Ends project-detail refresh.

    private func replaceConversation(_ updated: Conversation) { // Publishes one exact persisted conversation mutation in memory.
        if let index = conversations.firstIndex(where: { $0.id == updated.id }) { conversations[index] = updated } // Replaces an existing visible record by stable identity.
        else { conversations.append(updated) } // Handles a concurrently restored record defensively.
        if selectedConversationID == updated.id { messages = updated.messages } // Keeps selected visible history synchronized.
    } // Ends in-memory conversation replacement.

    private func requireSelectedConversationID() throws -> UUID { // Prevents visible messages or preferences from becoming unpersisted global state.
        guard let selectedConversationID else { throw ConversationStoreError.corruptedStore("no conversation is selected.") } // Produces a typed bounded failure for an impossible send state.
        return selectedConversationID // Returns the durable destination identity.
    } // Ends selected-conversation validation.

    private func updateActivity(_ id: UUID, phase: DocumentIngestionPhase, detail: String?) { // Updates one visible operation without replacing unrelated progress.
        guard let index = ingestionActivities.firstIndex(where: { $0.id == id }) else { return } // Ignores a stale operation after UI cleanup.
        ingestionActivities[index].phase = phase // Publishes current deterministic stage.
        ingestionActivities[index].detail = detail // Publishes optional bounded evidence.
    } // Ends ingestion activity mutation.

    private static func bounded(_ value: String) -> String { // Produces concise user-facing workspace diagnostics.
        String(value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(240)) // Flattens repeated whitespace and bounds output length.
    } // Ends workspace diagnostic bounding.
} // Ends local workspace controller.
