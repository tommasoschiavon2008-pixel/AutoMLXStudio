import AppKit // Supplies the standard macOS multi-file open panel for user-selected local sources.
import SwiftUI // Supplies the native split view, lists, alerts, progress, and accessibility modifiers.
import UniformTypeIdentifiers // Supplies explicit allowlisted document content types for the open panel.

struct ProjectsView: View { // Bridges the application environment into the independently observable Projects workspace surface.
    @EnvironmentObject private var appState: AppState // Provides the shared workspace controller and root navigation selection.

    var body: some View { // Builds the Projects destination without owning project persistence locally.
        ProjectsWorkspaceView(workspace: appState.workspace) { appState.selection = .chat } // Observes workspace mutations directly and returns to Chat only after Project Chat creation succeeds.
    } // Ends the Projects destination body.
} // Ends the application-environment bridge.

private struct ProjectsWorkspaceView: View { // Presents restrained native project navigation and document management.
    @ObservedObject var workspace: WorkspaceController // Observes durable project, document, import, and storage-issue state directly.
    let openSelectedProjectChat: () -> Void // Performs only the parent-owned navigation mutation after chat persistence succeeds.
    @State private var isCreatingProject = false // Controls the inline New Project editor in the project list.
    @State private var newProjectName = "" // Stores the uncommitted project name until validation and persistence succeed.
    @State private var projectForRename: ProjectMemorySummary? // Identifies the exact project awaiting an explicit rename confirmation.
    @State private var renamedProjectName = "" // Stores the uncommitted replacement name for the rename alert.
    @State private var projectForDeletion: ProjectMemorySummary? // Identifies the exact project awaiting destructive confirmation.
    @State private var documentForRemoval: MemoryDocument? // Identifies the exact app-owned memory document awaiting removal confirmation.
    @State private var operationError: String? // Shows bounded failures from throwing workspace mutations that did not set controller error state.
    @State private var isPerformingProjectAction = false // Prevents duplicate create, rename, delete, or Project Chat requests.
    @State private var busyDocumentIDs: Set<UUID> = [] // Prevents duplicate reindex or removal operations for one document.
    @State private var documentSearchQuery = "" // Stores the visible manual lexical query for the selected project only.
    @State private var documentSearchResults: [MemorySearchResult] = [] // Stores bounded transparent lexical results for local RAG inspection.
    @State private var isSearchingDocuments = false // Reports the exact app-owned local search operation without inventing progress percentages.
    @State private var completedDocumentSearchQuery: String? // Distinguishes a real completed zero-result search from text that is merely being edited.
    @FocusState private var isNewProjectNameFocused: Bool // Moves keyboard focus into the inline creator when requested.

    var body: some View { // Builds one native horizontal project list and detail workspace.
        HSplitView { // Keeps project selection visible while the user manages the selected project's memory.
            projectSidebar // Shows projects, resilient storage issues, and inline creation.
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 320) // Retains a useful macOS source-list width without consuming the document workspace.
            projectDetail // Shows project metadata, import progress, and source-document actions.
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity) // Gives document metadata and actions enough readable space.
        } // Ends the Projects horizontal split.
        .navigationTitle("Projects") // Labels the current destination in the native window toolbar.
        .alert("Rename Project", isPresented: renameAlertPresented) { // Requests an explicit editable project name before mutating storage.
            TextField("Project name", text: $renamedProjectName) // Captures only the new local project title.
            Button("Cancel", role: .cancel) { projectForRename = nil } // Dismisses without changing project identity or storage.
            Button("Rename") { Task { await renamePendingProject() } } // Persists the validated name asynchronously.
                .disabled(!isValidProjectName(renamedProjectName) || isPerformingProjectAction) // Blocks empty, oversized, or duplicate in-flight requests.
        } message: { // Explains the scope of the rename operation.
            Text("Rename this local project. Documents and associated conversations keep their existing project identity.") // Clarifies that rename does not rebuild or duplicate memory.
        } // Ends rename confirmation content.
        .alert("Delete Project", isPresented: deleteProjectAlertPresented) { // Requires a destructive confirmation for the exact selected project.
            Button("Cancel", role: .cancel) { projectForDeletion = nil } // Preserves the project and every associated app-owned record.
            Button("Delete Project and Conversations", role: .destructive) { Task { await deletePendingProject() } } // Executes the documented project-owned-conversation policy.
                .disabled(isPerformingProjectAction) // Prevents a repeated deletion transaction.
        } message: { // States every destructive and non-destructive consequence before authorization.
            Text(deleteProjectPolicyText) // Explains that app-owned memory and associated conversations are deleted while original source files remain untouched.
        } // Ends project deletion confirmation content.
        .alert("Remove Document from Project Memory", isPresented: removeDocumentAlertPresented) { // Requires confirmation before removing an indexed document.
            Button("Cancel", role: .cancel) { documentForRemoval = nil } // Leaves both Project Memory and the original source unchanged.
            Button("Remove from Project Memory", role: .destructive) { Task { await removePendingDocument() } } // Removes only app-owned document, chunk, and vector records.
                .disabled(documentForRemoval.map { busyDocumentIDs.contains($0.id) } ?? false) // Prevents duplicate removal while the exact document is already busy.
        } message: { // Makes the source-preservation guarantee visible before removal.
            Text(removeDocumentPolicyText) // Explains that the original local source file is never deleted.
        } // Ends document removal confirmation content.
        .onChange(of: workspace.selectedProjectID) { // Prevents results from one isolated project appearing under another selection.
            documentSearchQuery = "" // Clears the prior project's visible query.
            documentSearchResults = [] // Clears every prior project result immediately on selection change.
            completedDocumentSearchQuery = nil // Clears completed-search evidence for the prior isolated project.
        } // Ends project-scoped search reset.
    } // Ends the Projects workspace body.

    private var projectSidebar: some View { // Builds the native source list and resilient catalog diagnostics.
        List(selection: projectSelection) { // Binds selection to the controller through its asynchronous validation API.
            if isCreatingProject { // Inserts project creation directly in the source list instead of opening a separate workflow.
                Section("New Project") { // Gives the inline editor an accessible native section label.
                    VStack(alignment: .leading, spacing: 8) { // Groups name validation and actions compactly.
                        TextField("Project name", text: $newProjectName) // Captures a bounded local project name.
                            .textFieldStyle(.roundedBorder) // Uses the standard macOS field appearance.
                            .focused($isNewProjectNameFocused) // Supports immediate keyboard entry after pressing New Project.
                            .onSubmit { if isValidProjectName(newProjectName) { Task { await createProject() } } } // Creates on Return only when the same visible validation passes.
                            .accessibilityLabel("New project name") // Gives VoiceOver an explicit field purpose.
                        if !newProjectName.isEmpty, !isValidProjectName(newProjectName) { // Shows actionable validation only after the user begins typing.
                            Text(projectNameValidationMessage(newProjectName)) // Explains the explicit 80-character non-empty constraint.
                                .font(.caption) // Keeps validation subordinate to the editable name.
                                .foregroundStyle(.red) // Uses the system semantic error color.
                        } // Ends conditional project-name validation.
                        HStack(spacing: 8) { // Places save and cancel beside one another without extra chrome.
                            Button("Create") { Task { await createProject() } } // Persists the new project through the workspace actor boundary.
                                .buttonStyle(.borderedProminent) // Makes the primary action clear inside the temporary editor.
                                .controlSize(.small) // Matches compact macOS source-list controls.
                                .disabled(!isValidProjectName(newProjectName) || isPerformingProjectAction) // Prevents invalid or repeated creation.
                                .accessibilityHint("Creates and opens this local project") // Describes the resulting selection change.
                            Button("Cancel") { cancelProjectCreation() } // Dismisses the inline editor without persistence.
                                .buttonStyle(.bordered) // Uses a native secondary action style.
                                .controlSize(.small) // Matches the adjacent create action.
                        } // Ends inline creation actions.
                    } // Ends inline creation content.
                    .padding(.vertical, 4) // Separates the temporary editor from project rows.
                } // Ends New Project section.
            } // Ends conditional inline project creation.

            Section("Projects") { // Labels durable project rows in the macOS source list.
                ForEach(workspace.projectSummaries) { summary in // Shows every healthy project returned by the resilient catalog.
                    projectSidebarRow(summary) // Presents name and honest memory-readiness metadata.
                        .tag(summary.id) // Associates the durable UUID with source-list selection.
                        .contextMenu { projectContextMenu(summary) } // Offers scoped secondary actions without cluttering every row.
                } // Ends durable project rows.
            } // Ends Projects section.

            if !workspace.storageIssues.isEmpty { // Keeps healthy projects usable while exposing isolated corrupt snapshots.
                Section("Storage Issues") { // Separates recoverable app-owned storage diagnostics from healthy projects.
                    ForEach(workspace.storageIssues) { issue in // Shows each bounded catalog problem independently.
                        VStack(alignment: .leading, spacing: 3) { // Groups the affected snapshot and controlled diagnostic.
                            Label(issue.filename, systemImage: "exclamationmark.triangle") // Identifies only the app-owned snapshot filename.
                                .foregroundStyle(.orange) // Uses a semantic warning treatment without claiming total failure.
                            Text(issue.detail) // Shows the bounded validation or decoding evidence.
                                .font(.caption) // Keeps diagnostic detail subordinate to the affected filename.
                                .foregroundStyle(.secondary) // Reduces hierarchy while retaining readability.
                                .lineLimit(3) // Prevents one corrupt record from overwhelming the source list.
                        } // Ends one storage issue row.
                        .accessibilityElement(children: .combine) // Reads filename and bounded issue as one coherent VoiceOver item.
                    } // Ends resilient storage issues.
                } // Ends Storage Issues section.
            } // Ends conditional storage diagnostics.
        } // Ends native project source list.
        .listStyle(.sidebar) // Uses the standard macOS sidebar material and selection treatment.
        .accessibilityLabel("Projects") // Names the source list independently from the window title.
        .overlay { if workspace.projectSummaries.isEmpty, workspace.storageIssues.isEmpty, !isCreatingProject, !workspace.isLoading { emptyProjectOverlay } } // Shows a useful first-run action only when no resilient storage diagnostics need to remain visible.
        .toolbar { // Adds one standard project-creation command to the destination toolbar.
            ToolbarItem { // Places the native creation control using toolbar conventions.
                Button { beginProjectCreation() } label: { Label("New Project", systemImage: "plus") } // Opens the inline source-list editor.
                    .disabled(isCreatingProject || isPerformingProjectAction) // Prevents duplicate inline editors or concurrent project mutations.
                    .accessibilityHint("Opens an inline project name field") // Explains the non-destructive first step.
            } // Ends New Project toolbar item.
        } // Ends Projects toolbar.
    } // Ends project sidebar construction.

    @ViewBuilder // Allows loading, selected, and empty detail branches to retain their native concrete view types.
    private var projectDetail: some View { // Selects loading, selected-project, and empty detail states explicitly.
        if workspace.isLoading { // Shows real workspace restoration activity.
            ProgressView("Loading projects…") // Uses native indeterminate progress while actor reads complete.
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Centers the loading state in the available detail area.
                .accessibilityLabel("Loading projects") // Announces the current workspace operation to assistive technology.
        } else if let summary = workspace.selectedProject { // Shows only metadata for a catalog-validated selected project.
            selectedProjectDetail(summary) // Builds header, activities, and document rows for that exact project.
        } else { // Handles an empty catalog or deliberately cleared selection.
            ContentUnavailableView("Select a Project", systemImage: "folder", description: Text("Choose a project from the list, or create one to add local documents.")) // Gives a concise native empty-state next action.
        } // Ends detail-state selection.
    } // Ends project detail selection.

    private func selectedProjectDetail(_ summary: ProjectMemorySummary) -> some View { // Builds one selected project's metadata and document workspace.
        VStack(spacing: 0) { // Keeps the project header fixed while the document list scrolls.
            projectHeader(summary) // Shows identity, truthful index readiness, counts, dates, and primary actions.
            Divider() // Separates project metadata from operational document content.
            if let visibleError = operationError ?? workspace.errorMessage { // Surfaces the latest controlled workspace mutation failure inline.
                errorBanner(visibleError) // Shows concise diagnostic text with a local dismiss action.
                Divider() // Separates diagnostics from import and document rows.
            } // Ends conditional error presentation.
            List { // Provides native scrolling, keyboard navigation, and section semantics for project memory content.
                if !workspace.ingestionActivities.isEmpty { // Makes every selected source pipeline state visible.
                    Section { // Groups sequential import activities and their cancellation control.
                        ForEach(workspace.ingestionActivities) { activity in // Shows each file in original selection order.
                            ingestionActivityRow(activity) // Shows filename, deterministic phase, progress, and bounded detail.
                        } // Ends import activity rows.
                    } header: { // Adds cancellation only while one or more activities remain active.
                        HStack { // Places the section title and cancellation action on one native header line.
                            Text("Document Import") // Labels the current or most recent local ingestion batch.
                            Spacer() // Pushes cancellation to the trailing edge.
                            if hasActiveIngestion { // Avoids presenting cancellation after every operation has settled.
                                Button("Cancel") { workspace.cancelDocumentImport() } // Cancels only the controller-owned import task.
                                    .controlSize(.small) // Matches compact section-header actions.
                                    .accessibilityLabel("Cancel document import") // Announces exact cancellation scope.
                            } // Ends active-import cancellation.
                        } // Ends import section header layout.
                    } // Ends import activities section.
                } // Ends conditional import activities.

                Section("Search Project Documents") { // Exposes deterministic lexical inspection without invoking any model.
                    HStack(spacing: 8) { // Aligns the bounded query field with its explicit search action.
                        TextField("Search imported text", text: $documentSearchQuery) // Captures only the visible user query for this selected project.
                            .textFieldStyle(.roundedBorder) // Uses the native macOS search-entry appearance.
                            .onSubmit { Task { await searchDocuments(projectID: summary.id) } } // Runs the same local search path on Return.
                            .accessibilityLabel("Search documents in \(summary.project.name)") // States the exact isolation scope for VoiceOver.
                        Button("Search") { Task { await searchDocuments(projectID: summary.id) } } // Executes bounded lexical ranking with no LLM or network access.
                            .disabled(documentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearchingDocuments) // Rejects empty or duplicate concurrent searches.
                        if isSearchingDocuments { ProgressView().controlSize(.small).accessibilityLabel("Searching project documents") } // Shows honest indeterminate local work.
                    } // Ends manual search controls.
                    if completedDocumentSearchQuery != nil, !isSearchingDocuments, documentSearchResults.isEmpty { // Explains only an actually completed zero-result query deterministically.
                        Text("No matching chunks in this project.") // Avoids suggesting general model knowledge came from Project Memory.
                            .font(.caption) // Keeps the empty result subordinate to the query controls.
                            .foregroundStyle(.secondary) // Uses native supporting hierarchy.
                    } // Ends zero-result feedback.
                    ForEach(documentSearchResults, id: \.chunk.id) { result in // Shows only bounded chunks returned from the selected project store.
                        VStack(alignment: .leading, spacing: 4) { // Groups known source identity, score, and exact excerpt.
                            HStack { // Aligns source metadata with transparent lexical score.
                                Text(result.document.title).font(.caption.weight(.semibold)).lineLimit(1) // Shows the actual persisted document title.
                                Text("Chunk \(result.chunk.index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) // Shows actual source order using a readable one-based label.
                                Spacer() // Pushes the diagnostic score to the trailing edge.
                                Text("Score \(result.score, format: .number.precision(.fractionLength(3)))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) // Shows the meaningful lexical score without presenting it as a probability.
                            } // Ends lexical result metadata.
                            Text(result.chunk.text).font(.caption).foregroundStyle(.secondary).lineLimit(5).textSelection(.enabled) // Shows the exact stored chunk used by search.
                        } // Ends one manual retrieval result.
                        .accessibilityElement(children: .combine) // Reads source, chunk, score, and excerpt coherently.
                    } // Ends bounded manual search results.
                } // Ends manual Project Memory search inspector.

                Section { // Groups every durable document owned by this selected project.
                    if workspace.selectedDocuments.isEmpty { // Explains a valid project with no indexed sources.
                        ContentUnavailableView("No Documents", systemImage: "doc.badge.plus", description: Text("Add text-based files to make lexical Project Memory available.")) // Provides truthful retrieval capability and next action.
                            .frame(maxWidth: .infinity, minHeight: 180) // Gives the in-list empty state sufficient breathing room.
                    } else { // Shows actual durable document metadata.
                        ForEach(workspace.selectedDocuments) { document in // Preserves the store's deterministic document order.
                            documentRow(document) // Shows status, counts, dates, and source-safe actions.
                        } // Ends project document rows.
                    } // Ends empty-versus-populated document state.
                } header: { // Adds a native section label and compact file-import action.
                    HStack { // Places the section title and source selection action together.
                        Text("Documents") // Labels app-owned Project Memory sources.
                        Spacer() // Pushes Add Documents to the standard trailing position.
                        Button { chooseDocuments(for: summary.id) } label: { Label("Add Documents", systemImage: "plus") } // Opens the allowlisted standard macOS file panel.
                            .controlSize(.small) // Matches a compact section-header action.
                            .accessibilityHint("Choose text files to import sequentially into this project") // Explains the bounded local ingestion behavior.
                    } // Ends Documents section header layout.
                } // Ends project documents section.
            } // Ends project memory list.
            .listStyle(.inset) // Uses restrained native inset grouping in the detail pane.
        } // Ends selected-project detail layout.
    } // Ends selected project detail construction.

    private func projectHeader(_ summary: ProjectMemorySummary) -> some View { // Builds stable project identity and primary actions without decorative cards.
        VStack(alignment: .leading, spacing: 12) { // Arranges project identity, metadata, and actions in a compact hierarchy.
            HStack(alignment: .firstTextBaseline, spacing: 10) { // Keeps project name and readiness state readable on one line when space permits.
                Text(summary.project.name) // Shows the exact persisted project name.
                    .font(.title2.weight(.semibold)) // Establishes the selected project as the page heading.
                    .lineLimit(1) // Prevents an oversized header from displacing document content.
                    .help(summary.project.name) // Preserves the full bounded name on hover.
                Spacer() // Pushes memory readiness to the trailing edge.
                Label(summary.indexStatus.displayName, systemImage: indexStatusSymbol(summary.indexStatus)) // Shows the actual empty, lexical, embedding, stale, or degraded state.
                    .foregroundStyle(indexStatusColor(summary.indexStatus)) // Uses semantic readiness color without fabricating success.
                    .accessibilityLabel("Project Memory status: \(summary.indexStatus.displayName)") // Reads the meaning instead of only the symbol.
            } // Ends project title line.
            HStack(spacing: 18) { // Presents actual bounded project counts as simple metadata rather than separate cards.
                Label("\(summary.documentCount) documents", systemImage: "doc.on.doc") // Shows the durable source count.
                Label("\(summary.chunkCount) chunks", systemImage: "text.quote") // Shows the current lexical retrieval window count.
                Label("\(summary.vectorCount) vectors", systemImage: "number.square") // Shows only physically persisted validated vectors.
            } // Ends project counts.
            .font(.callout) // Keeps counts subordinate to project identity.
            .foregroundStyle(.secondary) // Uses native secondary hierarchy.
            HStack(spacing: 16) { // Shows durable project dates without a separate inspection surface.
                Text("Created \(formattedDate(summary.project.createdAt))") // Shows actual project creation time.
                Text("Updated \(formattedDate(summary.project.updatedAt))") // Shows actual latest metadata or memory mutation time.
            } // Ends project dates.
            .font(.caption) // Uses compact metadata typography.
            .foregroundStyle(.secondary) // Keeps dates visually subordinate.
            HStack(spacing: 8) { // Groups the primary Project Chat action with scoped project management.
                Button { Task { await startProjectChat(summary.id) } } label: { Label("Start Project Chat", systemImage: "bubble.left.and.bubble.right") } // Creates a durable project-associated conversation before navigation.
                    .buttonStyle(.borderedProminent) // Marks the principal next step for a configured project.
                    .disabled(isPerformingProjectAction) // Prevents duplicate conversations from repeated clicks.
                    .accessibilityHint("Creates a new chat with this project's memory enabled, then opens Chat") // Explains persistence and navigation effects.
                Button("Rename") { beginRename(summary) } // Opens explicit rename confirmation for this exact project.
                    .buttonStyle(.bordered) // Uses native secondary action emphasis.
                    .disabled(isPerformingProjectAction) // Prevents overlapping project mutations.
                    .accessibilityLabel("Rename \(summary.project.name)") // Includes the target identity for VoiceOver.
                Button("Delete", role: .destructive) { projectForDeletion = summary } // Opens the documented deletion-policy confirmation.
                    .buttonStyle(.bordered) // Keeps destructive action visible but subordinate to Project Chat.
                    .disabled(isPerformingProjectAction) // Prevents overlapping project mutations.
                    .accessibilityLabel("Delete \(summary.project.name)") // Includes the exact destructive target.
            } // Ends project header actions.
        } // Ends project header hierarchy.
        .padding(20) // Provides standard macOS detail-pane spacing.
    } // Ends project header construction.

    private func projectSidebarRow(_ summary: ProjectMemorySummary) -> some View { // Builds one compact source-list project row.
        VStack(alignment: .leading, spacing: 3) { // Groups identity and truthful document/readiness metadata.
            Label(summary.project.name, systemImage: "folder") // Uses the standard folder symbol with the persisted project name.
                .lineLimit(1) // Keeps source-list rows compact.
            Text("\(summary.documentCount) documents · \(summary.indexStatus.displayName)") // Shows actual count and retrieval readiness.
                .font(.caption) // Uses standard secondary source-list typography.
                .foregroundStyle(.secondary) // Keeps metadata subordinate to the project name.
                .lineLimit(1) // Preserves compact source-list height.
        } // Ends one project row layout.
        .padding(.vertical, 2) // Adds subtle separation between selectable source-list rows.
        .accessibilityElement(children: .combine) // Reads project identity and state as one selection item.
        .accessibilityLabel("\(summary.project.name), \(summary.documentCount) documents, \(summary.indexStatus.displayName)") // Gives VoiceOver concise complete row meaning.
    } // Ends project sidebar row construction.

    @ViewBuilder // Combines the context menu's scoped actions without type erasure.
    private func projectContextMenu(_ summary: ProjectMemorySummary) -> some View { // Supplies secondary project actions scoped to the clicked row.
        Button { Task { await startProjectChat(summary.id) } } label: { Label("Start Project Chat", systemImage: "bubble.left.and.bubble.right") } // Creates and opens a durable project-associated conversation.
        Button { beginRename(summary) } label: { Label("Rename…", systemImage: "pencil") } // Opens rename confirmation for the clicked project.
        Divider() // Separates reversible actions from destructive deletion.
        Button(role: .destructive) { projectForDeletion = summary } label: { Label("Delete Project…", systemImage: "trash") } // Opens the full deletion-policy confirmation.
    } // Ends project context menu.

    private func documentRow(_ document: MemoryDocument) -> some View { // Builds one durable document row with source-safe progressive actions.
        let status = workspace.documentStatuses[document.id] // Resolves current source and index metadata by durable document identity.
        return VStack(alignment: .leading, spacing: 8) { // Groups document identity, metadata, warnings, and contextual controls.
            HStack(alignment: .firstTextBaseline, spacing: 10) { // Keeps title and source state visible at a glance.
                Label(document.title, systemImage: document.sourceURL == nil ? "doc.text" : "doc") // Distinguishes retained internal text from an external source reference.
                    .font(.body.weight(.medium)) // Gives the durable document identity modest emphasis.
                    .lineLimit(1) // Prevents long filenames from displacing status and actions.
                    .help(document.title) // Makes the complete normalized title available on hover.
                Spacer() // Pushes source state and actions to the trailing edge.
                sourceStatusLabel(status?.sourceStatus ?? .internalOnly) // Shows current, changed, unavailable, untracked, or internal state honestly.
                documentActionsMenu(document, status: status) // Keeps ordinary reindex, reveal, and removal actions available without permanent button clutter.
            } // Ends document identity line.
            HStack(spacing: 16) { // Shows actual retrieval counts and import date.
                Text("\(status?.chunkCount ?? 0) chunks") // Shows current lexical windows for this document.
                Text("\(status?.vectorCount ?? 0) vectors") // Shows only persisted vectors referencing this document.
                Text("Imported \(formattedDate(document.createdAt))") // Shows the durable ingestion date.
                if let sourceModificationDate = document.sourceModificationDate { Text("Source dated \(formattedDate(sourceModificationDate))") } // Shows measured source modification metadata only when recorded.
            } // Ends document metadata line.
            .font(.caption) // Uses compact metadata typography.
            .foregroundStyle(.secondary) // Keeps counts and dates subordinate to title.
            if let sourceName = document.sourceURL?.lastPathComponent, sourceName != document.title { // Shows a real retained filename when the visible title differs.
                Text(sourceName) // Displays only actual URL metadata.
                    .font(.caption) // Keeps path identity subordinate to the document title.
                    .foregroundStyle(.secondary) // Uses restrained metadata hierarchy.
                    .lineLimit(1) // Prevents a filename from expanding row height unexpectedly.
            } // Ends optional retained source filename.
            if let status, status.sourceStatus == .modifiedExternally || status.sourceStatus == .unavailable { // Brings required recovery action forward only when source attention is needed.
                HStack(spacing: 8) { // Pairs an honest source warning with explicit reindex or retry.
                    Text(status.sourceStatus == .modifiedExternally ? "The source changed after import." : "The original source is currently unavailable.") // Explains the computed filesystem state without claiming content changed when unavailable.
                        .font(.caption) // Keeps recovery copy concise.
                        .foregroundStyle(status.sourceStatus == .modifiedExternally ? .orange : .red) // Distinguishes a changed source from an unavailable source.
                    Button(status.sourceStatus == .modifiedExternally ? "Reindex" : "Retry Reindex") { Task { await reindex(document) } } // Explicitly attempts the retained source through the workspace validation pipeline.
                        .controlSize(.small) // Uses a compact inline recovery control.
                        .disabled(busyDocumentIDs.contains(document.id)) // Prevents duplicate reads or index transactions.
                        .accessibilityLabel("\(status.sourceStatus == .modifiedExternally ? "Reindex" : "Retry reindex") \(document.title)") // Includes both operation and target.
                } // Ends source-recovery line.
            } // Ends conditional source recovery.
        } // Ends durable document row layout.
        .padding(.vertical, 5) // Separates document rows without decorative containers.
        .accessibilityElement(children: .contain) // Preserves actionable child controls while grouping row metadata.
    } // Ends document row construction.

    private func ingestionActivityRow(_ activity: DocumentIngestionActivity) -> some View { // Builds one sequential document-pipeline progress row.
        HStack(spacing: 10) { // Places phase feedback beside the exact selected source filename.
            ingestionIndicator(activity.phase) // Shows indeterminate work, success, failure, or cancellation honestly.
            VStack(alignment: .leading, spacing: 2) { // Groups source identity with current deterministic phase and bounded detail.
                Text(activity.sourceURL.lastPathComponent) // Shows the exact user-selected filename.
                    .lineLimit(1) // Keeps import rows compact.
                    .help(activity.sourceURL.path) // Makes the full selected local path available on hover.
                Text(activity.detail.map { "\(activity.phase.rawValue) · \($0)" } ?? activity.phase.rawValue) // Shows current stage and optional bounded result evidence.
                    .font(.caption) // Uses compact progress metadata typography.
                    .foregroundStyle(activity.phase == .failed ? .red : .secondary) // Makes controlled failure visible without overstating normal progress.
                    .lineLimit(2) // Bounds activity detail row height.
            } // Ends activity text.
            Spacer() // Keeps the progress row aligned with available width.
        } // Ends import activity layout.
        .accessibilityElement(children: .combine) // Reads filename, phase, and detail as one progress item.
        .accessibilityLabel("\(activity.sourceURL.lastPathComponent), \(activity.phase.rawValue)\(activity.detail.map { ", \($0)" } ?? "")") // Announces exact current import state.
    } // Ends ingestion activity row construction.

    @ViewBuilder // Combines active and settled ingestion indicators without type erasure.
    private func ingestionIndicator(_ phase: DocumentIngestionPhase) -> some View { // Selects a truthful native indicator for one import phase.
        switch phase { // Distinguishes active work from settled outcomes.
        case .validating, .reading, .chunking, .indexing: // Handles every controller-owned active pipeline stage.
            ProgressView() // Shows indeterminate progress because the pipeline does not fabricate percentages.
                .controlSize(.small) // Fits native list-row proportions.
                .accessibilityHidden(true) // Avoids duplicating the phase already present in the combined row label.
        case .ready: // Handles successful durable lexical readiness.
            Image(systemName: "checkmark.circle.fill") // Shows a standard success glyph.
                .foregroundStyle(.green) // Uses the semantic success color.
                .accessibilityHidden(true) // Avoids duplicate outcome announcement.
        case .failed: // Handles controlled per-file failure.
            Image(systemName: "xmark.octagon.fill") // Shows a standard error glyph.
                .foregroundStyle(.red) // Uses semantic error color.
                .accessibilityHidden(true) // Avoids duplicate outcome announcement.
        case .cancelled: // Handles explicit cooperative cancellation.
            Image(systemName: "stop.circle") // Shows a standard stopped-state glyph.
                .foregroundStyle(.secondary) // Keeps cancellation neutral rather than presenting it as a failure.
                .accessibilityHidden(true) // Avoids duplicate outcome announcement.
        } // Ends phase-indicator selection.
    } // Ends import indicator construction.

    @ViewBuilder // Combines every source-status label branch without type erasure.
    private func sourceStatusLabel(_ status: MemorySourceStatus) -> some View { // Maps computed source state to concise native labels.
        switch status { // Selects exact source availability wording.
        case .current: // Handles a retained source whose known metadata still matches.
            Label("Current", systemImage: "checkmark.circle") // Shows a verified current source.
                .font(.caption) // Keeps source status compact.
                .foregroundStyle(.green) // Uses semantic ready color.
        case .modifiedExternally: // Handles changed size or modification time.
            Label("Changed", systemImage: "arrow.triangle.2.circlepath") // Shows explicit external-change state.
                .font(.caption) // Keeps source status compact.
                .foregroundStyle(.orange) // Uses warning color for needed reindex.
        case .unavailable: // Handles a retained URL that cannot currently be read.
            Label("Unavailable", systemImage: "exclamationmark.triangle") // Shows actual source unavailability.
                .font(.caption) // Keeps source status compact.
                .foregroundStyle(.red) // Uses semantic failure color for a missing source.
        case .untracked: // Handles migrated external sources without historical file metadata.
            Label("Unverified", systemImage: "questionmark.circle") // Avoids claiming the source is unchanged.
                .font(.caption) // Keeps source status compact.
                .foregroundStyle(.secondary) // Uses neutral metadata styling.
        case .internalOnly: // Handles durable normalized text without an external source URL.
            Label("Stored Text", systemImage: "internaldrive") // Describes app-owned text accurately.
                .font(.caption) // Keeps source status compact.
                .foregroundStyle(.secondary) // Uses neutral metadata styling.
        } // Ends source status selection.
    } // Ends source status label construction.

    @ViewBuilder // Combines the conditional source actions and removal action into one native menu.
    private func documentActionsMenu(_ document: MemoryDocument, status: MemoryDocumentStatus?) -> some View { // Provides source-safe actions for one durable document.
        Menu { // Uses progressive disclosure for ordinary document management.
            if document.sourceURL != nil { // Offers reindex and Finder reveal only when a real source reference exists.
                Button { Task { await reindex(document) } } label: { Label("Reindex from Source", systemImage: "arrow.clockwise") } // Revalidates, rereads, rechunks, and atomically replaces affected memory.
                    .disabled(busyDocumentIDs.contains(document.id)) // Prevents duplicate source reads and transactions.
                Button { workspace.revealSource(document) } label: { Label("Reveal in Finder", systemImage: "finder") } // Reveals the exact retained source when still available.
                    .disabled(status?.sourceStatus == .unavailable) // Avoids offering a known-impossible reveal action.
                Divider() // Separates source operations from app-owned memory removal.
            } // Ends actions requiring a retained source URL.
            Button(role: .destructive) { documentForRemoval = document } label: { Label("Remove from Project Memory…", systemImage: "trash") } // Opens the explicit source-preserving removal confirmation.
                .disabled(busyDocumentIDs.contains(document.id)) // Prevents removal during another operation on the same document.
        } label: { // Uses a compact standard overflow control.
            Image(systemName: "ellipsis.circle") // Signals additional document actions without visual clutter.
        } // Ends document action menu label.
        .menuStyle(.borderlessButton) // Matches native table and list overflow controls.
        .fixedSize() // Prevents the compact overflow affordance from expanding.
        .accessibilityLabel("Actions for \(document.title)") // Includes the exact document target for VoiceOver.
    } // Ends document actions menu construction.

    private func errorBanner(_ message: String) -> some View { // Builds a restrained inline error presentation that does not block unrelated projects.
        HStack(spacing: 8) { // Places diagnostic text beside a local dismiss control.
            Image(systemName: "exclamationmark.triangle.fill") // Identifies a controlled operation failure.
                .foregroundStyle(.orange) // Uses warning emphasis because the rest of the workspace remains usable.
                .accessibilityHidden(true) // Leaves the combined label to communicate meaning once.
            Text(message) // Shows bounded controller or operation error evidence.
                .font(.callout) // Keeps the diagnostic readable but subordinate to project identity.
                .lineLimit(3) // Prevents a diagnostic from consuming the whole detail pane.
            Spacer() // Pushes dismissal to the trailing edge.
            Button { operationError = nil; workspace.errorMessage = nil } label: { Image(systemName: "xmark") } // Clears only visible diagnostics and does not mutate durable storage.
                .buttonStyle(.plain) // Uses a lightweight native dismissal affordance.
                .accessibilityLabel("Dismiss error") // Announces the icon-only control's purpose.
        } // Ends error banner layout.
        .padding(.horizontal, 20) // Aligns diagnostic text with project header content.
        .padding(.vertical, 9) // Provides readable spacing without a decorative container.
        .accessibilityElement(children: .contain) // Preserves the dismiss action while grouping diagnostic content.
    } // Ends inline error banner construction.

    private var emptyProjectOverlay: some View { // Builds the first-run project state above an otherwise empty source list.
        ContentUnavailableView { // Uses the native macOS empty-state composition.
            Label("No Projects", systemImage: "folder.badge.plus") // States the empty durable catalog clearly.
        } description: { // Explains the local workspace purpose concisely.
            Text("Create a project to organize local documents and Project Chats.") // Gives one clear next step without claiming model availability.
        } actions: { // Offers the same inline creation path as the toolbar.
            Button("New Project") { beginProjectCreation() } // Opens the source-list name editor.
                .buttonStyle(.borderedProminent) // Makes the only first-run action visually clear.
        } // Ends first-run action.
        .padding() // Keeps the native empty state away from split-view edges.
    } // Ends empty project overlay construction.

    private var projectSelection: Binding<UUID?> { // Adapts the controller's private-set selection to SwiftUI List selection safely.
        Binding(get: { workspace.selectedProjectID }, set: { newValue in Task { await workspace.selectProject(newValue) } }) // Routes every selection through asynchronous document/status refresh.
    } // Ends source-list selection binding.

    private var renameAlertPresented: Binding<Bool> { // Adapts optional rename identity to explicit alert presentation.
        Binding(get: { projectForRename != nil }, set: { if !$0 { projectForRename = nil } }) // Clears pending identity only when the alert dismisses.
    } // Ends rename alert binding.

    private var deleteProjectAlertPresented: Binding<Bool> { // Adapts optional deletion identity to explicit destructive confirmation.
        Binding(get: { projectForDeletion != nil }, set: { if !$0 { projectForDeletion = nil } }) // Clears pending identity only when confirmation dismisses.
    } // Ends project deletion alert binding.

    private var removeDocumentAlertPresented: Binding<Bool> { // Adapts optional document identity to source-preserving removal confirmation.
        Binding(get: { documentForRemoval != nil }, set: { if !$0 { documentForRemoval = nil } }) // Clears pending identity only when confirmation dismisses.
    } // Ends document removal alert binding.

    private var deleteProjectPolicyText: String { // Produces explicit target-aware project deletion consequences.
        let name = projectForDeletion?.project.name ?? "this project" // Uses the exact bounded project name when available.
        return "Deleting “\(name)” permanently removes its app-owned Project Memory data and every conversation associated with it. Original source files are never deleted. This cannot be undone." // States app-owned deletion, conversation policy, source preservation, and irreversibility.
    } // Ends project deletion policy copy.

    private var removeDocumentPolicyText: String { // Produces explicit target-aware document removal consequences.
        let title = documentForRemoval?.title ?? "this document" // Uses the exact bounded document title when available.
        return "Removing “\(title)” deletes only its app-owned document record, chunks, and vectors from this project. The original source file is not deleted." // States exact Project Memory scope and source preservation.
    } // Ends document removal policy copy.

    private var hasActiveIngestion: Bool { // Reports whether the current batch contains unfinished controller-owned work.
        workspace.ingestionActivities.contains { activity in // Examines only visible activities from the current or latest batch.
            switch activity.phase { case .validating, .reading, .chunking, .indexing: return true; case .ready, .failed, .cancelled: return false } // Treats only actual pipeline work as cancellable.
        } // Ends visible activity scan.
    } // Ends active-ingestion derivation.

    private func beginProjectCreation() { // Opens and focuses the inline project editor without mutating storage.
        operationError = nil // Clears an earlier mutation error before a new explicit operation.
        newProjectName = "" // Starts from a clean uncommitted project name.
        isCreatingProject = true // Inserts the native editor in the source list.
        Task { @MainActor in isNewProjectNameFocused = true } // Moves keyboard focus after SwiftUI inserts the field.
    } // Ends inline project creation setup.

    private func cancelProjectCreation() { // Dismisses the inline project editor without persistence.
        newProjectName = "" // Discards uncommitted user input.
        isCreatingProject = false // Removes the editor from the source list.
    } // Ends inline project creation cancellation.

    @MainActor // Keeps project-creation UI state mutations on the SwiftUI actor across suspension.
    private func createProject() async { // Validates and persists one new local project exactly once.
        guard isValidProjectName(newProjectName) else { operationError = projectNameValidationMessage(newProjectName); return } // Refuses empty or oversized input before storage work.
        isPerformingProjectAction = true // Disables duplicate project mutations during the actor transaction.
        defer { isPerformingProjectAction = false } // Restores controls on every success or failure path.
        do { // Attempts the workspace's validated atomic creation path.
            _ = try await workspace.createProject(name: newProjectName) // Persists and selects the exact new project.
            cancelProjectCreation() // Removes the editor only after durable success.
            operationError = nil // Clears an earlier controlled failure after successful creation.
        } catch { // Preserves user input when persistence or validation fails.
            operationError = bounded(error.localizedDescription) // Shows concise actionable creation evidence.
        } // Ends creation recovery.
    } // Ends project creation operation.

    private func beginRename(_ summary: ProjectMemorySummary) { // Prepares exact project identity and existing name for explicit rename.
        operationError = nil // Clears unrelated prior failure before the new operation.
        renamedProjectName = summary.project.name // Seeds the editable field with the persisted project name.
        projectForRename = summary // Retains exact identity even if source-list selection later changes.
    } // Ends rename setup.

    @MainActor // Keeps project-rename UI state mutations on the SwiftUI actor across suspension.
    private func renamePendingProject() async { // Validates and persists the explicitly targeted project rename.
        guard let summary = projectForRename else { return } // Refuses a stale alert action with no durable target.
        guard isValidProjectName(renamedProjectName) else { operationError = projectNameValidationMessage(renamedProjectName); return } // Refuses empty or oversized input before storage work.
        isPerformingProjectAction = true // Disables overlapping project mutations.
        defer { isPerformingProjectAction = false } // Restores controls on every outcome.
        do { // Attempts the workspace's atomic rename path.
            try await workspace.renameProject(id: summary.id, name: renamedProjectName) // Changes metadata while preserving project identity and relationships.
            projectForRename = nil // Dismisses the alert after durable success.
            operationError = nil // Clears earlier rename failure after success.
        } catch { // Preserves the target and entered name for retry.
            operationError = bounded(error.localizedDescription) // Shows concise rename evidence.
            projectForRename = nil // Dismisses the system alert so inline error feedback remains accessible.
        } // Ends rename recovery.
    } // Ends project rename operation.

    @MainActor // Keeps project-deletion UI state mutations on the SwiftUI actor across suspension.
    private func deletePendingProject() async { // Executes the explicitly confirmed project and associated-conversation policy.
        guard let summary = projectForDeletion else { return } // Refuses a stale confirmation with no durable target.
        isPerformingProjectAction = true // Prevents repeated deletion transactions.
        defer { isPerformingProjectAction = false } // Restores controls on every outcome.
        do { // Attempts containment-safe app-owned deletion.
            try await workspace.deleteProject(id: summary.id) // Deletes the project snapshot and its associated app-owned conversations while never touching source files.
            projectForDeletion = nil // Clears the confirmed target after durable success.
            operationError = nil // Clears prior controlled failure after success.
        } catch { // Keeps the workspace usable when deletion cannot complete.
            operationError = bounded(error.localizedDescription) // Shows concise containment or persistence evidence.
            projectForDeletion = nil // Dismisses the system confirmation after the failed attempt.
        } // Ends project deletion recovery.
    } // Ends confirmed project deletion operation.

    @MainActor // Keeps Project Chat handoff state and navigation on the SwiftUI actor across suspension.
    private func startProjectChat(_ projectID: UUID) async { // Creates a durable project-associated conversation before changing destinations.
        isPerformingProjectAction = true // Prevents duplicate conversation creation.
        defer { isPerformingProjectAction = false } // Restores controls on every outcome.
        do { // Attempts conversation persistence with the Project Chat memory default.
            try await workspace.startProjectChat(projectID: projectID) // Creates and selects a project-owned conversation.
            operationError = nil // Clears prior mutation failure after durable success.
            openSelectedProjectChat() // Navigates only after the selected durable Project Chat exists.
        } catch { // Leaves the user in Projects when chat creation fails.
            operationError = bounded(error.localizedDescription) // Shows concise conversation persistence evidence.
        } // Ends Project Chat recovery.
    } // Ends Project Chat operation.

    private func chooseDocuments(for projectID: UUID) { // Opens the standard allowlisted macOS source picker for the exact project.
        let panel = NSOpenPanel() // Creates a user-controlled local file chooser.
        panel.title = "Add Documents to Project Memory" // States the destination and purpose in the native panel.
        panel.prompt = "Add Documents" // Labels the affirmative panel action clearly.
        panel.message = "Choose UTF-8 text files (txt, md, swift, json, csv, or log). Files are read locally and the originals are never modified." // Explains accepted formats, local processing, and source safety.
        panel.canChooseFiles = true // Allows only explicit local source-file selection.
        panel.canChooseDirectories = false // Prevents unbounded directory traversal or implicit bulk import.
        panel.allowsMultipleSelection = true // Supports the controller's visible sequential bounded batch pipeline.
        panel.resolvesAliases = true // Resolves user-selected Finder aliases through standard macOS behavior.
        panel.allowedContentTypes = allowedDocumentTypes // Enforces the same visible six-extension allowlist before ingestion validation.
        panel.begin { response in // Presents the native panel without blocking ongoing workspace rendering.
            guard response == .OK else { return } // Treats cancellation as a no-op without an error.
            let selectedURLs = panel.urls // Captures only the files explicitly selected by the user.
            guard !selectedURLs.isEmpty else { return } // Avoids starting an empty import batch.
            Task { @MainActor in workspace.importDocuments(selectedURLs, projectID: projectID) } // Starts cancellable sequential ingestion on the shared workspace controller.
        } // Ends asynchronous open-panel completion.
    } // Ends document source selection.

    @MainActor // Keeps visible query state isolated to the selected Projects surface across actor suspension.
    private func searchDocuments(projectID: UUID) async { // Runs transparent bounded lexical retrieval without model inference or network access.
        let query = documentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes only query edges for visible completion tracking.
        guard !query.isEmpty, workspace.selectedProjectID == projectID else { return } // Refuses empty input or a stale project target.
        isSearchingDocuments = true // Publishes actual local search activity.
        completedDocumentSearchQuery = nil // Hides prior zero-result feedback while a new search is running.
        defer { isSearchingDocuments = false } // Restores controls on every success, failure, or cancellation path.
        do { // Attempts project-isolated deterministic lexical ranking.
            let results = try await workspace.memoryStore.searchDocuments(projectID: projectID, query: query, limit: 20) // Searches only the selected project's persisted chunks under a fixed result bound.
            guard workspace.selectedProjectID == projectID else { return } // Discards results when selection changed during the actor read.
            documentSearchResults = results // Publishes exact stored chunks and meaningful lexical scores.
            completedDocumentSearchQuery = query // Records that zero results, if any, are a completed outcome for this query.
            operationError = nil // Clears an earlier search diagnostic after success.
        } catch is CancellationError { // Treats cancellation as a neutral aborted local operation.
            documentSearchResults = [] // Avoids presenting stale evidence after cancellation.
            completedDocumentSearchQuery = nil // Avoids claiming a completed zero-result search.
        } catch { // Handles missing project, corrupt snapshot, or persistence read failure.
            documentSearchResults = [] // Avoids retaining results whose current storage read failed.
            completedDocumentSearchQuery = nil // Avoids mislabeling failure as no matches.
            operationError = bounded(error.localizedDescription) // Shows a concise actionable local-storage diagnostic.
        } // Ends manual lexical search recovery.
    } // Ends project document search.

    @MainActor // Keeps per-document reindex controls and errors on the SwiftUI actor across suspension.
    private func reindex(_ document: MemoryDocument) async { // Revalidates and atomically replaces one changed or unavailable retained source.
        guard !busyDocumentIDs.contains(document.id) else { return } // Prevents duplicate source reads and snapshot mutations.
        busyDocumentIDs.insert(document.id) // Marks the exact document as busy for row controls.
        defer { busyDocumentIDs.remove(document.id) } // Restores controls on every success or failure path.
        do { // Attempts the workspace's source-scoped reindex path.
            try await workspace.reindexDocument(document) // Rereads the retained source and replaces only affected app-owned memory.
            operationError = nil // Clears prior reindex failure after success.
        } catch { // Preserves the existing durable document when source validation or persistence fails.
            operationError = bounded(error.localizedDescription) // Shows concise unavailable, unsupported, or persistence evidence.
        } // Ends reindex recovery.
    } // Ends document reindex operation.

    @MainActor // Keeps confirmed document-removal UI state on the SwiftUI actor across suspension.
    private func removePendingDocument() async { // Removes only the explicitly confirmed app-owned memory document.
        guard let document = documentForRemoval else { return } // Refuses a stale alert action with no durable target.
        guard !busyDocumentIDs.contains(document.id) else { return } // Prevents overlap with source reading or another removal.
        busyDocumentIDs.insert(document.id) // Disables this document's controls during the atomic transaction.
        defer { busyDocumentIDs.remove(document.id) } // Restores controls on every outcome.
        do { // Attempts exact project/document identity removal.
            try await workspace.removeDocument(document) // Deletes only app-owned document, chunks, and vectors and never the original source.
            documentForRemoval = nil // Clears the confirmed target after durable success.
            operationError = nil // Clears prior controlled failure after success.
        } catch { // Leaves the durable source record visible when removal fails.
            operationError = bounded(error.localizedDescription) // Shows concise persistence or identity evidence.
            documentForRemoval = nil // Dismisses the system confirmation after the failed attempt.
        } // Ends document removal recovery.
    } // Ends confirmed document removal.

    private var allowedDocumentTypes: [UTType] { // Resolves the explicit Project Memory extension allowlist into open-panel types.
        ["txt", "md", "swift", "json", "csv", "log"].compactMap { UTType(filenameExtension: $0) } // Accepts only the same bounded text formats documented by ingestion.
    } // Ends allowlisted content-type derivation.

    private func isValidProjectName(_ value: String) -> Bool { // Applies visible validation matching the persistence contract.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines) // Ignores surrounding whitespace for meaningful length validation.
        return !trimmed.isEmpty && trimmed.count <= 80 // Requires visible content within the explicit store limit.
    } // Ends project-name validation.

    private func projectNameValidationMessage(_ value: String) -> String { // Produces one actionable validation result for inline and mutation failures.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines) // Applies the same normalization used by validation.
        return trimmed.isEmpty ? "Enter a project name." : "Project names must be 80 characters or fewer." // Distinguishes missing content from the explicit size limit.
    } // Ends project-name validation copy.

    private func formattedDate(_ date: Date) -> String { // Produces a locale-aware compact project and document timestamp.
        date.formatted(date: .abbreviated, time: .shortened) // Uses the user's macOS locale and calendar conventions.
    } // Ends date formatting.

    private func indexStatusSymbol(_ status: MemoryIndexStatus) -> String { // Maps real retrieval readiness to standard semantic symbols.
        switch status { case .empty: return "tray"; case .lexicalReady: return "text.magnifyingglass"; case .embeddingReady: return "checkmark.circle"; case .stale: return "arrow.triangle.2.circlepath"; case .degraded: return "exclamationmark.triangle" } // Covers every persisted index state exhaustively.
    } // Ends index-status symbol mapping.

    private func indexStatusColor(_ status: MemoryIndexStatus) -> Color { // Maps real retrieval readiness to restrained semantic colors.
        switch status { case .empty: return .secondary; case .lexicalReady, .embeddingReady: return .green; case .stale, .degraded: return .orange } // Distinguishes ready, empty, and attention-needed states without fabricated precision.
    } // Ends index-status color mapping.

    private func bounded(_ value: String) -> String { // Keeps unexpected thrown diagnostics readable in the Projects surface.
        String(value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(240)) // Flattens whitespace and caps visible diagnostic length.
    } // Ends local error bounding.
} // Ends native Projects workspace view.
