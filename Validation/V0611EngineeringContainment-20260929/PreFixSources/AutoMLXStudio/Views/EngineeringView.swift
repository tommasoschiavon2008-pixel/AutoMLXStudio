import SwiftUI // Supplies native macOS split views, forms, sheets, confirmation dialogs, and state observation.
import UniformTypeIdentifiers // Supplies the system folder content type for explicit workspace authorization.

@MainActor // Keeps view-owned controller access and file-picker state on the SwiftUI actor.
struct EngineeringView: View { // Presents a focused autonomous engineering surface without becoming a full source-code editor.
    @ObservedObject var controller: EngineeringController // Observes the application-owned Engineering session coordinator.
    @ObservedObject var remoteController: RemoteModelsController // Observes shared remote profiles and their explicitly discovered models.
    @EnvironmentObject private var appState: AppState // Reads the existing Project Memory catalog and sidebar navigation state.
    @State private var isChoosingWorkspace = false // Controls the native folder authorization picker.
    @State private var showsRollbackConfirmation = false // Requires explicit confirmation before conflict-safe transaction reversal.

    var body: some View { // Builds the complete state-driven Engineering destination.
        ScrollView { // Keeps every control reachable when the native detail pane is shorter than the full configuration and evidence surface.
        VStack(alignment: .leading, spacing: 16) { // Uses the same restrained page rhythm as the existing macOS destinations.
            header // Shows destination identity, execution boundary, and workspace action.
            if let notice = controller.notice { noticeView(notice) } // Presents the latest bounded operation result with text and symbol.
            workspaceAndExecutionBar // Makes the active filesystem authority and requested model location continuously visible.
            taskComposer // Collects the bounded task and explicit quality or Project Memory preferences.
            Divider() // Separates session configuration from observable execution evidence.
            executionDetail // Shows activity, app-owned changes, diff, and the terminal summary.
        } // Ends the primary page stack.
        .padding(24) // Matches the established desktop detail inset.
        .frame(maxWidth: .infinity, alignment: .topLeading) // Lets the scroll container own vertical sizing without clipping the page header.
        } // Ends the accessible vertically scrollable page.
        .background(Color(nsColor: .windowBackgroundColor)) // Preserves native light and dark appearances.
        .task { // Restores independent local authorization and remote profile state when the destination opens.
            await controller.loadWorkspaces() // Reopens only durable user-authorized workspace metadata.
            await remoteController.load() // Loads non-secret remote profiles without initiating discovery or inference.
            normalizeSelections() // Removes stale optional project, server, or model selections after restoration.
        } // Ends destination restoration.
        .onChange(of: remoteController.profiles) { _, _ in normalizeRemoteSelection() } // Keeps the selected server valid after profile edits or removal.
        .onChange(of: controller.selectedRemoteServerID) { _, _ in normalizeRemoteModelSelection() } // Keeps model identity scoped to the selected server.
        .onChange(of: appState.workspace.projectSummaries) { _, _ in normalizeProjectSelection() } // Keeps optional knowledge retrieval scoped to a readable project.
        .fileImporter(isPresented: $isChoosingWorkspace, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in // Requests explicit user authority for exactly one directory.
            handleWorkspaceSelection(result) // Hands the selected folder to the durable authorization boundary asynchronously.
        } // Ends native folder authorization.
        .sheet(isPresented: approvalSheetBinding) { // Presents the exact external-side-effect request without blocking the main thread.
            if let request = controller.pendingApproval { approvalSheet(request) } // Shows only the still-live typed approval evidence.
        } // Ends approval presentation.
        .confirmationDialog("Roll back this app-owned change?", isPresented: $showsRollbackConfirmation) { // Confirms the exact reversible transaction.
            Button("Roll back change", role: .destructive) { // Names the precise destructive scope.
                Task { await controller.rollbackSelectedChange() } // Uses workspace conflict detection before changing any bytes.
            } // Ends confirmed rollback action.
            Button("Cancel", role: .cancel) {} // Leaves workspace contents and transaction history untouched.
        } message: { // Explains why rollback can be safely refused.
            Text("Only the selected AutoMLX Studio transaction is reversed. Rollback stops if the file changed afterward.") // States the conflict-preserving behavior explicitly.
        } // Ends rollback confirmation.
    } // Ends the Engineering view body.

    private var header: some View { // Renders the page title and its single workspace-level primary action.
        HStack(alignment: .top, spacing: 18) { // Aligns concise trust-boundary copy with the action.
            VStack(alignment: .leading, spacing: 5) { // Groups title and execution explanation.
                Text("Engineering") // Names the autonomous coding destination.
                    .font(.title2.bold()) // Establishes clear hierarchy without an oversized marketing heading.
                Text("A bounded agent can inspect, edit, build, and test only inside an authorized Mac workspace.") // Summarizes actual authority.
                    .foregroundStyle(.secondary) // Keeps explanation subordinate to the page identity.
                Label("Remote models may reason about bounded results; every tool still runs locally on this Mac.", systemImage: "lock.mac") // Makes the distributed trust boundary explicit.
                    .font(.callout) // Keeps the security statement readable.
                    .foregroundStyle(.secondary) // Uses restrained native hierarchy.
            } // Ends page identity copy.
            Spacer(minLength: 18) // Pushes the primary workspace action to the trailing edge.
            Button("Open Workspace", systemImage: "folder.badge.plus") { isChoosingWorkspace = true } // Opens the native single-folder authorization flow.
                .buttonStyle(.borderedProminent) // Emphasizes the prerequisite action without decorating the whole page.
                .disabled(controller.isRunning) // Prevents authority switching during a live session.
                .keyboardShortcut("o", modifiers: [.command, .shift]) // Adds a desktop-appropriate explicit shortcut.
        } // Ends header layout.
    } // Ends Engineering header.

    private var workspaceAndExecutionBar: some View { // Shows the active filesystem authority and explicit inference location together.
        HStack(alignment: .center, spacing: 14) { // Keeps operational selection compact and scannable.
            Picker("Workspace", selection: workspaceSelectionBinding) { // Selects only previously authorized descriptors.
                Text("No workspace").tag(Optional<UUID>.none) // Represents the first-run state without fabricating authority.
                ForEach(controller.workspaces) { workspace in // Lists durable authorizations in store order.
                    Text(workspace.displayName).tag(Optional(workspace.id)) // Uses stable descriptor identity rather than a path string.
                } // Ends workspace choices.
            } // Ends workspace picker.
            .frame(minWidth: 220, idealWidth: 280, maxWidth: 360) // Leaves long folder names readable without dominating the page.
            .disabled(controller.isRunning || controller.isLoadingWorkspaces) // Prevents selection races during restoration or execution.
            if let selected = controller.selectedWorkspace { // Shows the exact authorized root for the active descriptor.
                Text(selected.rootPath) // Displays actual local filesystem scope.
                    .font(.caption.monospaced()) // Distinguishes machine path metadata from labels.
                    .foregroundStyle(.secondary) // Keeps path subordinate while remaining inspectable.
                    .lineLimit(1) // Retains compact bar height.
                    .truncationMode(.middle) // Preserves both volume and leaf folder in constrained width.
                    .help(selected.rootPath) // Makes the complete path available without expanding layout.
                Button("Forget Workspace", systemImage: "xmark.circle") { // Removes only the stored authorization record.
                    Task { await controller.removeWorkspaceAuthorization(id: selected.id) } // Leaves every external source file untouched.
                } // Ends authorization removal.
                .labelStyle(.iconOnly) // Keeps the operational bar compact.
                .buttonStyle(.borderless) // Uses the native secondary-action treatment.
                .help("Forget this authorization without deleting files") // States the non-destructive scope.
                .disabled(controller.isRunning) // Prevents removing the active boundary mid-session.
            } // Ends active-root metadata.
            Spacer(minLength: 10) // Separates workspace scope from execution identity.
            Label(controller.executionLocationLabel, systemImage: controller.prefersRemoteModel ? "network" : "desktopcomputer") // Shows Local — Mac or Remote — configured server in words.
                .font(.callout.weight(.medium)) // Gives execution location appropriate operational prominence.
                .accessibilityLabel("Inference location: \(controller.executionLocationLabel)") // Supplies standalone assistive context.
        } // Ends workspace and execution bar.
        .padding(.vertical, 2) // Keeps breathing room around standard controls.
    } // Ends active scope bar.

    private var taskComposer: some View { // Collects only explicit task and execution-policy inputs.
        VStack(alignment: .leading, spacing: 12) { // Uses one coherent configuration region rather than nested cards.
            TextEditor(text: $controller.taskText) // Accepts the visible engineering objective as user data.
                .font(.body) // Preserves native readable task typography.
                .frame(minHeight: 92, maxHeight: 150) // Allows useful multi-line tasks while preserving evidence space.
                .padding(6) // Separates text from its native border.
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7)) // Uses the standard editable surface color.
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor))) // Makes the editable boundary visible in both appearances.
                .overlay(alignment: .topLeading) { // Adds a prompt only while no real task text exists.
                    if controller.taskText.isEmpty { Text("Describe the change, constraints, and expected verification…").foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 14).allowsHitTesting(false) } // Provides useful input guidance without becoming persisted content.
                } // Ends task placeholder.
                .disabled(controller.isRunning) // Freezes the exact visible objective owned by a live run.
                .accessibilityLabel("Engineering task") // Gives the unlabeled editor a complete assistive name.
            HStack(alignment: .center, spacing: 14) { // Places deliberate execution policies beside the primary Run or Stop action.
                Picker("Quality", selection: $controller.quality) { // Selects the fixed bounded iteration and review plan.
                    ForEach(AgentExecutionQuality.allCases) { quality in // Lists Fast, Balanced, and Thorough exactly once.
                        Text("\(quality.rawValue) · \(quality.engineeringIterationLimit) turns").tag(quality) // Makes each hard ceiling visible before execution.
                    } // Ends quality choices.
                } // Ends quality picker.
                .frame(width: 210) // Keeps ceiling text readable.
                .disabled(controller.isRunning) // Prevents policy mutation after a run starts.
                Toggle("Project Memory", isOn: $controller.useProjectMemory) // Keeps RAG explicitly opt-in and distinct from workspace access.
                    .toggleStyle(.switch) // Uses the native binary-policy control.
                    .disabled(controller.isRunning || appState.workspace.projectSummaries.isEmpty) // Requires a readable project and stable run policy.
                if controller.useProjectMemory { // Progressively reveals only the options needed for enabled retrieval.
                    Picker("Knowledge", selection: $controller.selectedProjectID) { // Selects exactly one isolated Project Memory source.
                        ForEach(appState.workspace.projectSummaries) { summary in // Lists actual durable readable projects.
                            Text(summary.project.name).tag(Optional(summary.id)) // Uses stable project identity and visible name.
                        } // Ends project choices.
                    } // Ends Project Memory picker.
                    .frame(minWidth: 150, maxWidth: 230) // Keeps project names useful without crowding the primary action.
                    .disabled(controller.isRunning) // Freezes retrieval ownership during execution.
                    Picker("Context", selection: $controller.projectContextBudgetPreset) { // Selects one existing hard evidence budget.
                        Text("Efficient").tag(ProjectContextBudgetPreset.efficient) // Offers the compact three-chunk policy.
                        Text("Balanced").tag(ProjectContextBudgetPreset.balanced) // Offers the default six-chunk policy.
                        Text("Maximum quality").tag(ProjectContextBudgetPreset.maximumQuality) // Offers the bounded ten-chunk policy.
                    } // Ends context budget picker.
                    .frame(width: 175) // Keeps complete preset labels visible.
                    .disabled(controller.isRunning) // Freezes context policy for the active run.
                } // Ends Project Memory progressive options.
                Spacer(minLength: 8) // Keeps execution action at the trailing edge.
                if controller.isRunning { // Shows Stop only while this controller owns an exact session.
                    Button("Stop", systemImage: "stop.fill", role: .destructive) { controller.stop() } // Propagates cancellation without automatic rollback.
                        .buttonStyle(.borderedProminent) // Gives the live safety action immediate visibility.
                        .keyboardShortcut(".", modifiers: .command) // Matches the familiar macOS cancel shortcut.
                } else { // Shows Run for idle and fully configured state.
                    Button("Run", systemImage: "play.fill") { controller.run() } // Starts one bounded single-owner Engineering session.
                        .buttonStyle(.borderedProminent) // Emphasizes the primary execution action.
                        .disabled(!controller.canRun) // Requires workspace, task, and complete remote selection when applicable.
                        .keyboardShortcut(.return, modifiers: [.command]) // Provides a deliberate desktop launch shortcut.
                } // Ends Run versus Stop state.
            } // Ends primary policy row.
            modelSelection // Shows local or explicitly configured remote inference choices.
        } // Ends task configuration stack.
    } // Ends task composer.

    @ViewBuilder // Allows local and remote controls to use distinct layouts without type erasure.
    private var modelSelection: some View { // Makes requested backend preference explicit before any model attempt.
        VStack(alignment: .leading, spacing: 8) { // Fits transport selection into narrow native detail panes.
            Picker("Inference", selection: $controller.prefersRemoteModel) { // Chooses whether the primary model is local or an explicit server target.
                Text("Local — Mac").tag(false) // Selects the catalog-backed local MLX route.
                Text("Remote — configured server").tag(true) // Selects a manually configured private inference profile.
            } // Ends inference-location picker.
            .pickerStyle(.segmented) // Makes the two mutually exclusive locations immediately visible.
            .labelsHidden() // Avoids truncating the visible segments to reserve space for a redundant label.
            .accessibilityLabel("Inference location") // Preserves the hidden label for assistive technology.
            .frame(width: 310) // Preserves both literal labels without excess width.
            .disabled(controller.isRunning) // Freezes route preference for the active run.
            if controller.prefersRemoteModel { // Reveals server and model only for explicit remote-primary execution.
                Text("Remote inference receives selected context and tool results. Compatible local assignment fallback may run if remote inference fails; model capabilities remain unverified until observed.") // Discloses data sharing, fallback, and capability uncertainty before Run.
                    .font(.caption) // Keeps policy guidance subordinate to the task.
                    .fixedSize(horizontal: false, vertical: true) // Wraps the full data-sharing and fallback disclosure without truncation.
                Picker("Server", selection: $controller.selectedRemoteServerID) { // Selects one enabled manually configured endpoint.
                    ForEach(enabledRemoteProfiles) { profile in // Lists only profiles eligible for routing.
                        Text(profile.displayName).tag(Optional(profile.id)) // Stores exact server identity without a URL or secret.
                    } // Ends server choices.
                } // Ends remote server picker.
                .frame(minWidth: 150, maxWidth: 230) // Keeps server names readable.
                .disabled(controller.isRunning || enabledRemoteProfiles.isEmpty) // Prevents stale selection or route changes mid-run.
                Picker("Model", selection: $controller.selectedRemoteModelID) { // Selects only actually discovered identities for the chosen server.
                    ForEach(selectedRemoteModels) { model in // Lists provider-reported model identifiers.
                        Text(model.id).tag(Optional(model.id)) // Preserves the exact provider model identity.
                    } // Ends discovered model choices.
                } // Ends remote model picker.
                .frame(minWidth: 190, maxWidth: 320) // Supports longer provider identifiers.
                .disabled(controller.isRunning || selectedRemoteModels.isEmpty) // Requires explicit discovery before routing.
                if enabledRemoteProfiles.isEmpty || selectedRemoteModels.isEmpty { // Gives a concrete next step for incomplete remote configuration.
                    Button("Configure Remote Models") { appState.selection = .remoteModels } // Navigates to the dedicated profile and discovery destination.
                        .buttonStyle(.link) // Treats setup as navigation rather than an execution action.
                } // Ends missing-remote-configuration guidance.
            } else { // Describes the deterministic local model policy without exposing internal filesystem configuration here.
                Text("Engineering Agent uses the configured coding assignment. Edits and build scripts require approval.") // States routing and interactive mutation policy.
                    .font(.caption) // Keeps supporting policy subordinate.
                    .foregroundStyle(.secondary) // Preserves native hierarchy.
            } // Ends local versus remote model controls.
        } // Ends model selection row.
    } // Ends model selection surface.

    private var executionDetail: some View { // Shows live and terminal evidence in two desktop panes.
        HSplitView { // Lets users allocate space between activity/results and app-owned changes.
            activityPane // Shows status, actual backend/model, terminal summary, and operational events.
            changesPane // Shows reversible transactions and a bounded Git-independent diff.
        } // Ends evidence split view.
        .frame(minHeight: 330) // Keeps both evidence panes usable in the standard application window.
    } // Ends execution evidence surface.

    private var activityPane: some View { // Renders only trace-safe operational metadata and the best final candidate.
        VStack(alignment: .leading, spacing: 10) { // Groups status and activity without decorative nesting.
            HStack(spacing: 8) { // Aligns status with actual successful routing identity.
                Text(controller.statusText) // Shows the typed current or terminal state.
                    .font(.headline) // Makes session state the pane anchor.
                if controller.isRunning { ProgressView().controlSize(.small).accessibilityLabel("Engineering session running") } // Communicates live nonblocking work.
                Spacer() // Pushes actual model evidence to the trailing edge.
                if let backend = controller.activeBackendID { Text(backend).font(.caption.monospaced()).foregroundStyle(.secondary) } // Shows only an actually successful backend attempt.
                if let model = controller.activeModelID { Text(model).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(model) } // Shows only an actually successful model identity.
            } // Ends session status row.
            if let result = controller.result, !result.finalSummary.isEmpty { // Shows the best useful terminal candidate independently from verification state.
                VStack(alignment: .leading, spacing: 6) { // Groups summary label, verification truth, and selectable text.
                    HStack { // Aligns summary identity with evidence state.
                        Text("Result").font(.subheadline.weight(.semibold)) // Labels model-authored terminal content.
                        Spacer() // Pushes verification state to the trailing edge.
                        Label(result.verification.state == .verified ? "Verified" : "Unverified", systemImage: result.verification.state == .verified ? "checkmark.seal.fill" : "questionmark.diamond") // Distinguishes evidence from model assertion.
                            .font(.caption) // Keeps evidence compact.
                            .foregroundStyle(result.verification.state == .verified ? .green : .secondary) // Uses color only as secondary evidence beside literal text.
                    } // Ends result metadata row.
                    ScrollView { Text(result.finalSummary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } // Makes bounded result copy inspectable and selectable.
                        .frame(maxHeight: 115) // Preserves space for the operational event feed.
                } // Ends terminal result region.
            } // Ends optional result presentation.
            Divider() // Separates model-authored result from runtime-owned trace.
            Text("Tool activity").font(.subheadline.weight(.semibold)) // Labels the safe operational event feed.
            if controller.activity.isEmpty { // Handles an idle or newly selected workspace.
                ContentUnavailableView("No activity yet", systemImage: "list.bullet.rectangle", description: Text("Run a task to see model attempts, reads, searches, edits, commands, and verification.")) // Gives a concrete evidence-oriented empty state.
            } else { // Shows actual bounded runtime events.
                List(controller.activity) { event in // Uses native dense rows and keyboard scrolling.
                    activityRow(event) // Shows category, status, duration, and safe summary without arguments or private reasoning.
                } // Ends activity iteration.
                .listStyle(.inset) // Keeps evidence rows compact inside the detail destination.
            } // Ends activity state selection.
        } // Ends activity pane stack.
        .padding(.trailing, 12) // Separates evidence from the draggable split divider.
        .frame(minWidth: 360, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) // Gives the primary trace enough readable width.
    } // Ends activity pane.

    private func activityRow(_ event: EngineeringAgentEvent) -> some View { // Renders one trace-safe event without model prompts, tool arguments, or full output.
        HStack(alignment: .top, spacing: 9) { // Aligns semantic state icon with concise metadata.
            Image(systemName: eventSymbol(event)) // Uses a category and outcome-aware native symbol.
                .foregroundStyle(eventColor(event)) // Adds restrained status color as secondary evidence.
                .frame(width: 18) // Keeps row text aligned across symbols.
                .accessibilityHidden(true) // Leaves explicit textual summary for assistive technology.
            VStack(alignment: .leading, spacing: 3) { // Groups event type and bounded operational summary.
                HStack(spacing: 7) { // Shows compact type, tool, and timing metadata.
                    Text(eventTitle(event)).font(.callout.weight(.medium)) // Names the observable operation.
                    if let tool = event.toolName { Text(tool).font(.caption.monospaced()).foregroundStyle(.secondary) } // Shows only the registered tool name.
                    Spacer(minLength: 5) // Keeps duration and exit evidence at the trailing edge.
                    if let duration = event.durationMilliseconds { Text("\(duration) ms").font(.caption.monospaced()).foregroundStyle(.secondary) } // Shows measured runtime duration when available.
                    if let exitCode = event.exitCode { Text("exit \(exitCode)").font(.caption.monospaced()).foregroundStyle(.secondary) } // Shows actual child exit status when available.
                } // Ends event metadata row.
                Text(event.summary) // Shows the bounded secret-redacted runtime description.
                    .font(.caption) // Keeps operational detail dense.
                    .foregroundStyle(.secondary) // Preserves hierarchy beneath event identity.
                    .lineLimit(3) // Prevents a single event from consuming the whole feed.
            } // Ends event content.
        } // Ends one activity row.
        .padding(.vertical, 3) // Maintains a comfortable dense click and reading rhythm.
        .accessibilityElement(children: .combine) // Announces event identity, duration, exit status, and summary coherently.
    } // Ends activity row rendering.

    private var changesPane: some View { // Renders only app-owned reversible transactions and their bounded diffs.
        VStack(alignment: .leading, spacing: 10) { // Groups transaction list and selected diff.
            HStack { // Aligns section identity with manual refresh and rollback actions.
                Text("Changes").font(.headline) // Names the app-owned transaction surface.
                Text("\(controller.changes.count)").font(.caption.monospaced()).foregroundStyle(.secondary) // Shows exact transaction count.
                Spacer() // Pushes scoped actions to the trailing edge.
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await controller.refreshChanges() } } // Reloads durable transaction evidence only.
                    .labelStyle(.iconOnly) // Keeps the pane toolbar compact.
                    .help("Refresh app-owned changes") // Gives the icon a standalone accessible meaning.
                    .disabled(controller.isRunning) // Avoids redundant updates while run completion already refreshes state.
                Button("Rollback", systemImage: "arrow.uturn.backward") { showsRollbackConfirmation = true } // Opens exact transaction confirmation.
                    .disabled(controller.isRunning || controller.selectedChangeID == nil) // Requires idle state and one exact transaction.
            } // Ends changes toolbar.
            if controller.changes.isEmpty { // Handles a session or workspace with no app-authored transaction.
                ContentUnavailableView("No app-owned changes", systemImage: "doc.badge.ellipsis", description: Text("Edits made through Engineering Mode will appear here with conflict-safe rollback.")) // Explains scope and future behavior.
                    .frame(maxHeight: 120) // Preserves proportional space for the otherwise empty diff region.
            } else { // Shows actual durable transaction metadata.
                List(controller.changes, selection: changeSelectionBinding) { change in // Uses stable transaction identity for exact diff selection.
                    VStack(alignment: .leading, spacing: 3) { // Groups path and operation metadata.
                        Text(change.relativePath).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle).help(change.relativePath) // Shows the root-relative affected path.
                        Text("\(change.kind.rawValue.capitalized) · \(change.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) // Shows actual operation type and timestamp.
                    } // Ends transaction row.
                    .tag(change.id) // Binds selection to the exact app-owned change identity.
                } // Ends transaction list.
                .listStyle(.inset) // Uses a compact desktop evidence list.
                .frame(minHeight: 100, maxHeight: 155) // Reserves most pane height for selected diff inspection.
            } // Ends transaction list state.
            Text("Diff").font(.subheadline.weight(.semibold)) // Labels the Git-independent selected transaction diff.
            ScrollView([.horizontal, .vertical]) { // Supports bounded long lines and multi-file-style diff text without editing.
                Text(controller.selectedDiff.isEmpty ? "Select a change to inspect its before/after diff." : controller.selectedDiff) // Shows guidance or actual bounded diff.
                    .font(.system(.caption, design: .monospaced)) // Preserves diff alignment.
                    .foregroundStyle(controller.selectedDiff.isEmpty ? .secondary : .primary) // Distinguishes guidance from evidence.
                    .textSelection(.enabled) // Allows copying evidence without granting mutation authority.
                    .frame(maxWidth: .infinity, alignment: .topLeading) // Keeps short diffs anchored predictably.
                    .padding(8) // Separates text from the scroll boundary.
            } // Ends diff scrolling.
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6)) // Uses the native text inspection surface.
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor))) // Keeps the read-only boundary visible.
        } // Ends changes pane stack.
        .padding(.leading, 12) // Separates changes from the draggable split divider.
        .frame(minWidth: 330, idealWidth: 470, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) // Keeps paths and diff evidence readable.
    } // Ends changes pane.

    private func approvalSheet(_ request: EngineeringApprovalRequest) -> some View { // Shows all exact evidence required for one Allow Once decision.
        VStack(alignment: .leading, spacing: 16) { // Uses a focused nonblocking decision layout.
            Label("Approval required", systemImage: "exclamationmark.shield.fill") // Names the security boundary with symbol and text.
                .font(.title2.bold()) // Gives the decision appropriate prominence.
                .foregroundStyle(.orange) // Uses warning color only as secondary semantic evidence.
            Text("Engineering requests permission to change workspace files or execute a command. Nothing runs until you decide.") // Covers contained edits and process side effects without mislabeling risk.
                .foregroundStyle(.secondary) // Keeps guidance subordinate.
            approvalField("Action", value: request.tool.rawValue) // Shows the registered action name.
            approvalField("Risk", value: request.risk.rawValue) // Shows the runtime's typed classification.
            approvalField("Reason", value: request.reason) // Shows the bounded requested rationale.
            approvalField("Workspace", value: request.workspacePath) // Shows the exact local authorization root.
            VStack(alignment: .leading, spacing: 5) { // Gives the exact direct-process display extra room.
                Text("Proposed operation").font(.caption.weight(.semibold)).foregroundStyle(.secondary) // Labels exact command or bounded edit evidence.
                ScrollView([.horizontal, .vertical]) { Text(request.exactCommand).font(.body.monospaced()).textSelection(.enabled).padding(8) } // Makes large bounded edit previews inspectable in both directions.
                    .frame(height: 200) // Keeps Deny and Allow Once reachable even for long proposed content.
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6)) // Uses a standard inspectable text surface.
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor))) // Makes the exact-command boundary visible.
            } // Ends exact command field.
            HStack { // Places the safe default and one-shot grant in familiar order.
                Spacer() // Aligns decision actions to the trailing edge.
                Button("Deny", role: .cancel) { controller.resolveApproval(.deny) } // Refuses only this exact invocation.
                    .keyboardShortcut(.cancelAction) // Makes Escape select the safe decision.
                Button("Allow Once") { controller.resolveApproval(.allowOnce) } // Grants only this exact pending command once.
                    .buttonStyle(.borderedProminent) // Emphasizes the deliberate affirmative decision.
            } // Ends approval actions.
        } // Ends approval content.
        .padding(24) // Provides comfortable focus around a security-sensitive decision.
        .frame(width: 620) // Keeps exact command and workspace evidence readable.
        .interactiveDismissDisabled(true) // Prevents ambiguous dismissal while the runtime awaits a typed decision.
    } // Ends approval sheet.

    private func approvalField(_ title: String, value: String) -> some View { // Renders one labeled immutable approval fact consistently.
        VStack(alignment: .leading, spacing: 3) { // Groups label and selectable value.
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary) // Labels the evidence field.
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) // Shows exact bounded evidence without editing.
        } // Ends approval fact layout.
    } // Ends approval fact helper.

    private func noticeView(_ notice: EngineeringControllerNotice) -> some View { // Renders operation feedback without relying on color alone.
        Label(notice.message, systemImage: noticeSymbol(notice.kind)) // Combines semantic icon and bounded text.
            .font(.callout) // Keeps feedback readable but subordinate to page identity.
            .foregroundStyle(noticeColor(notice.kind)) // Adds restrained semantic color.
            .padding(.horizontal, 10) // Separates text from the notice boundary.
            .padding(.vertical, 8) // Gives feedback a comfortable target and reading height.
            .frame(maxWidth: .infinity, alignment: .leading) // Supports long actionable diagnostics.
            .background(noticeColor(notice.kind).opacity(0.08), in: RoundedRectangle(cornerRadius: 7)) // Uses one subtle state surface rather than decorative cards.
            .accessibilityElement(children: .combine) // Announces icon meaning through the adjacent literal message.
    } // Ends notice rendering.

    private var enabledRemoteProfiles: [RemoteServerProfile] { // Resolves profiles that may participate in explicit routing.
        remoteController.profiles.filter(\.isEnabled) // Excludes user-disabled endpoints without deleting their configuration.
    } // Ends enabled profile lookup.

    private var selectedRemoteModels: [RemoteDiscoveredModel] { // Resolves model discovery only for the exact selected server.
        guard let serverID = controller.selectedRemoteServerID else { return [] } // Requires one explicit server identity.
        return remoteController.models(for: serverID) // Returns only provider-reported isolated model records.
    } // Ends selected server model lookup.

    private var workspaceSelectionBinding: Binding<UUID?> { // Converts picker writes into actor-backed workspace reopening.
        Binding(get: { controller.selectedWorkspaceID }, set: { identifier in // Reads published selection and handles one explicit change.
            guard let identifier else { return } // Keeps authority removal as a separate explicit action.
            Task { await controller.selectWorkspace(id: identifier) } // Reopens the exact durable authorization asynchronously.
        }) // Ends workspace selection binding construction.
    } // Ends workspace picker binding.

    private var changeSelectionBinding: Binding<UUID?> { // Converts transaction selection into bounded diff loading.
        Binding(get: { controller.selectedChangeID }, set: { identifier in // Reads exact identity and handles one new selection.
            Task { await controller.showDiff(changeID: identifier) } // Computes the selected before/after diff away from the rendering pass.
        }) // Ends change selection binding construction.
    } // Ends transaction selection binding.

    private var approvalSheetBinding: Binding<Bool> { // Presents the live exact request and denies an external dismissal defensively.
        Binding(get: { controller.pendingApproval != nil }, set: { presented in // Reflects broker state and observes dismissal attempts.
            if !presented, controller.pendingApproval != nil { controller.resolveApproval(.deny) } // Converts any system dismissal into the safe typed decision.
        }) // Ends approval presentation binding.
    } // Ends approval sheet binding.

    private func handleWorkspaceSelection(_ result: Result<[URL], Error>) { // Normalizes one folder-picker outcome without blocking SwiftUI.
        switch result { // Separates user cancellation or picker failure from a selected folder.
        case .success(let urls): // Handles the system-returned selection list.
            guard let directoryURL = urls.first else { return } // Requires the exact one authorized folder requested by this view.
            Task { // Retains security scope for the complete asynchronous bookmark and workspace-open operation.
                let didStartScope = directoryURL.startAccessingSecurityScopedResource() // Activates macOS scope when the picker supplied one.
                defer { if didStartScope { directoryURL.stopAccessingSecurityScopedResource() } } // Releases only scope started by this operation.
                await controller.authorizeWorkspace(directoryURL: directoryURL, associatedProjectID: controller.useProjectMemory ? controller.selectedProjectID : nil) // Persists independent workspace authorization with an optional project link.
            } // Ends authorized workspace handoff.
        case .failure(let error): // Handles a picker or system authorization failure.
            controller.notice = EngineeringControllerNotice(kind: .error, message: error.localizedDescription) // Publishes bounded safe feedback through the existing notice surface.
        } // Ends folder-picker result handling.
    } // Ends workspace selection handling.

    private func normalizeSelections() { // Repairs optional selections after independent persistence restoration.
        normalizeProjectSelection() // Keeps optional Project Memory selection readable.
        normalizeRemoteSelection() // Keeps remote target identity scoped to enabled current profiles.
    } // Ends initial selection normalization.

    private func normalizeProjectSelection() { // Keeps knowledge retrieval disabled or scoped to one readable durable project.
        guard !controller.isRunning else { return } // Keeps submitted project selection stable when other pages refresh data.
        let projects = appState.workspace.projectSummaries // Captures the current isolated project catalog.
        if projects.isEmpty { controller.useProjectMemory = false; controller.selectedProjectID = nil; return } // Disables retrieval when no evidence source exists.
        if controller.selectedProjectID == nil || !projects.contains(where: { $0.id == controller.selectedProjectID }) { controller.selectedProjectID = projects.first?.id } // Selects the first readable project without importing workspace files.
    } // Ends Project Memory selection normalization.

    private func normalizeRemoteSelection() { // Keeps server selection within current enabled manually configured profiles.
        guard !controller.isRunning else { return } // Keeps active inference selection stable across configuration-page updates.
        if enabledRemoteProfiles.isEmpty { controller.selectedRemoteServerID = nil; controller.selectedRemoteModelID = nil; return } // Clears an unusable remote target honestly.
        if controller.selectedRemoteServerID == nil || !enabledRemoteProfiles.contains(where: { $0.id == controller.selectedRemoteServerID }) { controller.selectedRemoteServerID = enabledRemoteProfiles.first?.id } // Selects the first explicitly enabled profile.
        normalizeRemoteModelSelection() // Revalidates model identity under the selected server.
    } // Ends remote server selection normalization.

    private func normalizeRemoteModelSelection() { // Keeps provider model identity scoped to current discovery evidence.
        guard !controller.isRunning else { return } // Defers draft normalization until the running snapshot is released.
        let models = selectedRemoteModels // Captures the exact server's discovered records.
        if models.isEmpty { controller.selectedRemoteModelID = nil; return } // Requires explicit discovery rather than inventing a model name.
        if controller.selectedRemoteModelID == nil || !models.contains(where: { $0.id == controller.selectedRemoteModelID }) { controller.selectedRemoteModelID = models.first?.id } // Selects the first actual discovered identity when needed.
    } // Ends remote model selection normalization.

    private func eventTitle(_ event: EngineeringAgentEvent) -> String { // Maps typed trace categories to concise user-facing language.
        switch event.kind { // Selects a stable operational label.
        case .sessionStarted: return "Session started" // Labels ownership acquisition.
        case .modelAttempt: return "Model attempt" // Labels local or remote inference.
        case .modelFallback: return "Model fallback" // Labels explicit compatible recovery.
        case .toolRequested: return "Tool requested" // Labels a validated proposal.
        case .toolSucceeded: return "Tool completed" // Labels successful Mac execution.
        case .toolFailed: return "Tool failed" // Labels recoverable tool failure.
        case .toolDenied: return "Tool denied" // Labels policy or approval refusal.
        case .toolCancelled: return "Tool cancelled" // Labels exact-owner cancellation.
        case .argumentRepair: return "Argument repair" // Labels the sole structured repair allowance.
        case .loopWarning: return "Strategy warning" // Labels repeated-action guidance.
        case .loopDetected: return "Loop stopped" // Labels terminal loop protection.
        case .reviewerStarted: return "Reviewer started" // Labels optional bounded review.
        case .reviewerSucceeded: return "Reviewer completed" // Labels successful review.
        case .reviewerFailed: return "Reviewer unavailable" // Labels progressive review degradation.
        case .composerStarted: return "Composer started" // Labels optional final composition.
        case .composerSucceeded: return "Composer completed" // Labels successful composition.
        case .composerFailed: return "Composer unavailable" // Labels progressive composition degradation.
        case .sessionCompleted: return "Session completed" // Labels explicit normal termination.
        case .sessionFailed: return "Session failed" // Labels terminal failure.
        case .sessionCancelled: return "Session cancelled" // Labels user-owned cancellation.
        case .iterationLimit: return "Iteration limit" // Labels fixed-ceiling termination.
        case .sessionBusy: return "Session busy" // Labels single-owner rejection.
        } // Ends event-label mapping.
    } // Ends event title helper.

    private func eventSymbol(_ event: EngineeringAgentEvent) -> String { // Chooses one semantic native symbol per event outcome and category.
        if event.succeeded == false { return event.kind == .toolDenied ? "hand.raised.fill" : "exclamationmark.triangle.fill" } // Gives explicit failures and denials visible non-color shapes.
        switch event.kind { // Selects category symbolism for neutral or successful events.
        case .modelAttempt, .modelFallback: return "cpu" // Represents inference and backend routing.
        case .toolRequested, .toolSucceeded: return "wrench.and.screwdriver" // Represents concrete Mac tool operations.
        case .reviewerStarted, .reviewerSucceeded: return "checkmark.bubble" // Represents bounded review.
        case .composerStarted, .composerSucceeded: return "text.badge.checkmark" // Represents final composition.
        case .sessionCompleted: return "checkmark.circle.fill" // Represents normal completion.
        case .sessionCancelled: return "stop.circle" // Represents cooperative stop.
        default: return "circle.fill" // Provides a restrained stable marker for other trace events.
        } // Ends event-symbol mapping.
    } // Ends event symbol helper.

    private func eventColor(_ event: EngineeringAgentEvent) -> Color { // Adds semantic color only beside an explicit symbol and text state.
        if event.succeeded == false { return event.kind == .toolDenied ? .orange : .red } // Distinguishes refusals from failures without relying on color alone.
        if event.succeeded == true { return .green } // Marks concrete success evidence.
        return .secondary // Keeps lifecycle and request events neutral.
    } // Ends event color helper.

    private func noticeSymbol(_ kind: EngineeringControllerNoticeKind) -> String { // Maps notice semantics to native symbols.
        switch kind { // Selects a literal state shape.
        case .information: return "info.circle" // Represents neutral guidance.
        case .success: return "checkmark.circle.fill" // Represents a completed operation.
        case .error: return "exclamationmark.triangle.fill" // Represents a bounded failure.
        } // Ends notice-symbol mapping.
    } // Ends notice symbol helper.

    private func noticeColor(_ kind: EngineeringControllerNoticeKind) -> Color { // Maps notice semantics to restrained native colors.
        switch kind { // Selects a secondary visual cue.
        case .information: return .secondary // Keeps guidance neutral.
        case .success: return .green // Marks concrete success.
        case .error: return .red // Marks a bounded actionable failure.
        } // Ends notice-color mapping.
    } // Ends notice color helper.
} // Ends the focused Engineering destination.
