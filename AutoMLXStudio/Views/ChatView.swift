import SwiftUI
import AppKit // Supplies the native macOS image picker and local thumbnail decoding.
import UniformTypeIdentifiers // Supplies the PNG, JPEG, HEIC, and file-URL type identifiers.

struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @State private var prompt = ""
    @State private var sending = false
    @State private var expandedTraceID: UUID? // Tracks the one workflow disclosure expanded beneath an assistant message.
    @State private var attachments: [UserAttachment] = [] // Stores validated URL-backed attachments waiting in the composer.
    @State private var attachmentError: String? // Stores one controlled picker or drag-and-drop validation diagnostic.
    @State private var isDropTargeted = false // Gives drag-and-drop a clear native target state.
    @State private var expandedSourcesMessageID: UUID? // Tracks source disclosure independently from workflow diagnostics.
    @State private var conversationToDelete: Conversation? // Retains the exact app-owned conversation awaiting explicit deletion confirmation.
    @State private var conversationToRename: Conversation? // Retains the exact conversation whose visible title is being edited.
    @State private var editedConversationTitle = "" // Stores only the pending visible title text for the rename alert.

    var body: some View {
        HSplitView { // Gives durable conversation history a native resizable sidebar without changing the main Chat hierarchy.
            conversationSidebar // Shows normal and project-associated chats with stable persisted identities.
                .frame(minWidth: 190, idealWidth: 230, maxWidth: 300) // Keeps history useful while protecting the conversation reading width.
            VStack(spacing: 0) { // Preserves the established header, transcript, and composer layout.
                header // Shows actual conversation, project, quality, memory, and runtime state.
                Divider() // Separates persistent controls from the transcript.
                messageArea // Keeps conversation and multimodal controlled failures available even before a text server is loaded.
                Divider() // Separates the scrollable transcript from fixed composer controls.
                composer // Provides attachments, Voice draft, Send, and Stop behavior.
            } // Ends the main Chat surface.
        } // Ends conversation-history split view.
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { appState.voiceController.stopPlayback() } // Stops and cleans only app-owned generated audio when the Chat surface closes.
        .alert("Rename Conversation", isPresented: Binding(get: { conversationToRename != nil }, set: { if !$0 { conversationToRename = nil } })) { // Uses a native focused rename confirmation.
            TextField("Conversation title", text: $editedConversationTitle) // Edits only visible deterministic metadata and never invokes a model.
            Button("Cancel", role: .cancel) { conversationToRename = nil } // Leaves durable metadata untouched.
            Button("Rename") { renameSelectedConversation() } // Applies store validation and atomic persistence.
                .disabled(editedConversationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) // Prevents an invalid empty title before storage validation.
        } message: { // Explains the narrow rename effect.
            Text("This changes only the local conversation title.") // Avoids implying messages or project memory are modified.
        } // Ends rename alert.
        .alert("Delete Conversation?", isPresented: Binding(get: { conversationToDelete != nil }, set: { if !$0 { conversationToDelete = nil } })) { // Requires explicit confirmation for app-owned history deletion.
            Button("Cancel", role: .cancel) { conversationToDelete = nil } // Preserves the conversation.
            Button("Delete", role: .destructive) { deleteSelectedConversation() } // Deletes only the exact app-owned conversation record.
        } message: { // States the deletion boundary precisely.
            Text("Messages in this conversation will be removed. Project documents and Project Memory are not affected.") // Prevents ambiguity about external or project-owned sources.
        } // Ends delete confirmation.
    }

    private var conversationSidebar: some View { // Renders durable chat history with project association and bounded local actions.
        VStack(spacing: 0) { // Keeps the toolbar fixed above the scrollable conversation collection.
            HStack { // Aligns section identity and the primary new-chat action.
                Text("Conversations") // Names the persisted history surface.
                    .font(.headline) // Gives the sidebar one clear heading.
                Spacer() // Pushes the new-chat control to the trailing edge.
                Button { createNormalConversation() } label: { // Creates a normal chat without Project Memory association.
                    Image(systemName: "square.and.pencil") // Uses the standard native new-conversation symbol.
                } // Ends new-chat button label.
                .buttonStyle(.borderless) // Keeps the sidebar utility control visually restrained.
                .keyboardShortcut("n", modifiers: .command) // Supports the requested Command-N workflow globally while Chat is open.
                .help("New Conversation (⌘N)") // Exposes the shortcut and effect to pointer users.
                .disabled(appState.isGenerating) // Prevents changing durable destinations during an active workflow.
            } // Ends history toolbar.
            .padding(.horizontal, 12) // Aligns toolbar content with conversation rows.
            .frame(height: 44) // Uses a compact native sidebar toolbar height.
            Divider() // Separates the toolbar from history.
            if appState.workspace.conversations.isEmpty { // Shows a useful first-launch state while restoration or creation runs.
                ContentUnavailableView("No Conversations", systemImage: "bubble.left", description: Text("Create a local conversation to begin.")) // Uses the standard macOS empty-state component.
            } else { // Renders actual durable conversations.
                List { // Provides native selection, keyboard navigation, and contextual actions.
                    ForEach(appState.workspace.conversations) { conversation in // Preserves the store's recent-activity ordering.
                        Button { Task { await appState.workspace.selectConversation(conversation.id) } } label: { // Opens the exact persisted conversation asynchronously.
                            conversationLabel(conversation) // Shows title, project identity, and recent activity compactly.
                        } // Ends conversation row button label.
                        .buttonStyle(.plain) // Lets the List own row selection appearance.
                        .listRowBackground(appState.workspace.selectedConversationID == conversation.id ? Color.accentColor.opacity(0.14) : Color.clear) // Makes current durable selection visible without a second binding authority.
                        .contextMenu { // Exposes secondary history operations without permanent clutter.
                            Button("Rename…") { beginRename(conversation) } // Opens the native bounded title editor.
                            Button("Delete…", role: .destructive) { conversationToDelete = conversation } // Requires the outer explicit confirmation before deletion.
                        } // Ends conversation row actions.
                        .accessibilityLabel(conversationAccessibilityLabel(conversation)) // Combines title and project identity for VoiceOver.
                    } // Ends durable conversation iteration.
                } // Ends native history list.
                .listStyle(.sidebar) // Matches the containing navigation hierarchy without decorative cards.
            } // Ends history empty-versus-list selection.
        } // Ends conversation sidebar layout.
        .background(Color(nsColor: .underPageBackgroundColor)) // Uses a native subordinate sidebar surface.
    } // Ends durable conversation history.

    private func conversationLabel(_ conversation: Conversation) -> some View { // Builds a compact row from only persisted visible metadata.
        VStack(alignment: .leading, spacing: 4) { // Stacks title above subordinate project and date facts.
            Text(conversation.title) // Shows deterministic or explicitly renamed title.
                .font(.body.weight(appState.workspace.selectedConversationID == conversation.id ? .semibold : .regular)) // Gives current selection modest emphasis.
                .lineLimit(2) // Bounds long titles without changing persisted text.
            HStack(spacing: 5) { // Shows project identity and recency on one compact line.
                if let projectID = conversation.projectID { // Distinguishes Project Chat from a normal conversation.
                    Image(systemName: "folder") // Uses a semantic project marker.
                    Text(appState.workspace.projectSummaries.first(where: { $0.id == projectID })?.project.name ?? "Unavailable Project") // Shows real catalog metadata or an honest missing association.
                        .lineLimit(1) // Protects the date from a long project name.
                } else { // Labels ordinary chat explicitly.
                    Image(systemName: "bubble.left") // Uses the normal-conversation marker.
                    Text("Normal Chat") // Avoids implying global Project Memory access.
                } // Ends conversation association label.
                Spacer(minLength: 2) // Separates identity from activity time.
                Text(conversation.updatedAt, style: .relative) // Shows actual persisted last activity.
                    .monospacedDigit() // Keeps changing relative values visually stable.
            } // Ends subordinate metadata row.
            .font(.caption2) // Keeps metadata secondary to title.
            .foregroundStyle(.secondary) // Preserves native hierarchy.
        } // Ends conversation row label.
        .padding(.vertical, 4) // Gives each selectable row a comfortable target.
        .contentShape(Rectangle()) // Makes the complete label clickable and keyboard-selectable.
    } // Ends conversation row construction.

    private var header: some View { // Shows actual durable conversation association and active execution controls.
        HStack(spacing: 14) { // Keeps identity, preferences, and runtime actions on one restrained toolbar.
            VStack(alignment: .leading, spacing: 3) { // Gives the selected conversation clear primary identity.
                Text(appState.workspace.selectedConversation?.title ?? "Chat") // Shows real persisted title or a first-load fallback.
                    .font(.title2.bold()) // Preserves the established page-title hierarchy.
                    .lineLimit(1) // Prevents an edited title from crowding controls.
                HStack(spacing: 5) { // Combines project identity with current physical model status.
                    if let project = appState.workspace.conversationProject { // Labels only an actual Project Chat association.
                        Label(project.project.name, systemImage: "folder") // Shows the real selected project rather than a cosmetic toggle state.
                    } else { // Labels ordinary chat honestly.
                        Label("Normal Chat", systemImage: "bubble.left") // Makes Project Memory ineligibility understandable.
                    } // Ends association display.
                    Text("·") // Separates durable association from transient runtime status.
                    Text(chatModelStatus) // Shows current V0.2 runtime identity without implying one permanent model.
                        .truncationMode(.middle) // Preserves both ends of long model identifiers.
                } // Ends header metadata row.
                .font(.caption) // Keeps metadata subordinate to conversation title.
                .foregroundStyle(.secondary) // Uses native secondary hierarchy.
                .lineLimit(1) // Keeps the toolbar compact.
            } // Ends selected conversation identity.
            Spacer() // Pushes preference and runtime controls to the trailing edge.
            if let conversation = appState.workspace.selectedConversation { // Shows preferences only for a durable selected destination.
                Toggle("Use Project Memory", isOn: memoryPreferenceBinding) // Controls actual retrieval eligibility persisted on the conversation.
                    .toggleStyle(.switch) // Uses the native macOS compact switch.
                    .controlSize(.small) // Keeps the toolbar from becoming crowded.
                    .disabled(conversation.projectID == nil || appState.isGenerating) // Prevents a misleading global-memory toggle and mid-request policy changes.
                    .help(conversation.projectID == nil ? "Project Memory is available only in a Project Chat." : "Search only this project's imported documents for this conversation.") // Explains the exact isolation boundary.
                Picker("Quality", selection: qualityOverrideBinding) { // Exposes the optional per-conversation execution override compactly.
                    Text("Default · \(appState.defaultAgentQuality.rawValue)").tag(nil as AgentExecutionQuality?) // Inherits the persisted application default.
                    ForEach(AgentExecutionQuality.allCases) { quality in Text(quality.rawValue).tag(Optional(quality)) } // Lists the bounded Fast, Balanced, and Thorough policies.
                } // Ends per-conversation quality selection.
                .labelsHidden() // Keeps the compact toolbar label inside each menu choice.
                .frame(width: 126) // Prevents the picker from expanding with long metadata.
                .disabled(appState.isGenerating) // Freezes the plan policy for the active request.
                .help("Agent execution quality for this conversation") // Distinguishes this control from model-switching policy.
            } // Ends durable conversation preferences.
            statusPill // Shows actual managed server readiness and port.
            if appState.isGenerating { // Replaces server lifecycle controls with exact request cancellation while work is active.
                Button("Stop") { appState.cancelGeneration() } // Cancels only the current app-owned workflow task.
                    .buttonStyle(.borderedProminent) // Makes the time-sensitive action easy to find.
                    .tint(.red) // Uses semantic destructive color for stopping in-flight work.
                    .keyboardShortcut(.cancelAction) // Supports the requested Escape cancellation workflow.
                    .help("Stop the current workflow (Esc)") // States exact scope and shortcut.
            } else if appState.serverRunning { // Offers managed server release only when no workflow is using it.
                Button("Stop Server") { appState.stopServer() } // Stops only the exact MLX process retained by this application.
                    .buttonStyle(.bordered) // Keeps server lifecycle secondary to conversation work.
                    .disabled(appState.activeProcessDescription != nil) // Avoids racing another owned runtime operation.
            } else { // Offers explicit local server startup while offline.
                Button("Start Server") { appState.startServer() } // Starts the configured managed local fallback model.
                    .buttonStyle(.borderedProminent) // Preserves the existing primary offline recovery action.
                    .disabled(appState.activeProcessDescription != nil) // Avoids duplicate or racing starts.
            } // Ends runtime action selection.
        } // Ends Chat header row.
        .padding(.horizontal, 20) // Preserves established toolbar inset.
        .frame(minHeight: 74) // Preserves the prior height while permitting accessibility text expansion.
    } // Ends actual Chat header.

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.serverRunning ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)

            Text(appState.serverRunning ? "Running · \(appState.serverPort)" : "Offline")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.8))
        .clipShape(Capsule())
    }

    private var chatModelStatus: String { // Produces concise multi-model runtime copy for the Chat header.
        guard let activeModelID = appState.activeModelID else { return "Multi-model routing · \(appState.modelSwitchPolicy.displayName)" } // Shows policy while the managed server is offline.
        return appState.modelRegistry.model(id: activeModelID)?.displayName ?? activeModelID // Shows the exact physical model currently loaded.
    } // Ends Chat model status access.

    private var memoryPreferenceBinding: Binding<Bool> { // Bridges the persisted asynchronous conversation preference into a native Toggle.
        Binding(get: { appState.workspace.selectedConversation?.useProjectMemory ?? false }, set: { enabled in Task { do { try await appState.workspace.setUseProjectMemory(enabled) } catch { appState.workspace.errorMessage = error.localizedDescription } } }) // Reads the actual selected value and atomically persists every user change.
    } // Ends Project Memory preference binding.

    private var qualityOverrideBinding: Binding<AgentExecutionQuality?> { // Bridges the optional persisted quality override into a compact Picker.
        Binding(get: { appState.workspace.selectedConversation?.qualityOverride }, set: { quality in Task { do { try await appState.workspace.setQualityOverride(quality) } catch { appState.workspace.errorMessage = error.localizedDescription } } }) // Reads the actual override and atomically stores nil or one bounded policy.
    } // Ends quality-override binding.

    private var serverOfflineView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("MLX server is not running")
                    .font(.title3.weight(.semibold))

                Text(serverOfflineDescription)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            Button("Start Server") {
                appState.startServer()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appState.activeProcessDescription != nil)

            if appState.statusText.localizedCaseInsensitiveContains("port") {
                Text("You can change the port in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var serverOfflineDescription: String {
        if appState.statusText.localizedCaseInsensitiveContains("port") {
            return appState.statusText
        }
        return "Start the local MLX server before sending messages."
    }

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if appState.chatMessages.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 40, weight: .light))
                                .foregroundStyle(.secondary)

                            Text("Start a conversation")
                                .font(.title3.weight(.semibold))

                            Text("Everything is generated locally through MLX.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 110)
                    }

                    ForEach(appState.chatMessages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .onChange(of: appState.chatMessages.count) {
                if let id = appState.chatMessages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.role == "assistant" {
                assistantBadge
                VStack(alignment: .leading, spacing: 6) { // Keeps workflow metadata attached to its actual assistant response.
                    messageBubble(message, isUser: false) // Preserves the existing readable assistant bubble.
                    if !message.citations.isEmpty { sourcesDisclosure(for: message) } // Shows source inspection only for responses with exact injected Project Memory excerpts.
                    if let trace = appState.workflowTrace(id: message.workflowTraceID) { // Shows metadata only for real orchestrated messages.
                        workflowDisclosure(trace) // Adds a compact expandable workflow line without cluttering the conversation.
                    } // Ends trace metadata availability handling.
                } // Ends the assistant response and metadata grouping.
                .frame(maxWidth: 680, alignment: .leading) // Preserves the existing conversation reading width.
                Spacer(minLength: 120)
            } else {
                Spacer(minLength: 120)
                messageBubble(message, isUser: true)
            }
        }
    }

    private var assistantBadge: some View {
        Image(systemName: "cpu")
            .font(.caption.weight(.semibold))
            .frame(width: 28, height: 28)
            .background(.quaternary)
            .clipShape(Circle())
    }

    private func messageBubble(_ message: ChatMessage, isUser: Bool) -> some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) { // Keeps attachment previews visibly associated with their originating message.
            if !message.attachments.isEmpty { // Shows only stored URL-backed metadata and local thumbnails.
                attachmentPreviewRow(message.attachments, allowsRemoval: false) // Renders compact read-only message previews.
            } // Ends message attachment preview.
            Text(message.content) // Shows the visible user or assistant text.
                .textSelection(.enabled) // Preserves copy support.
                .font(.body) // Preserves the established chat typography.
        } // Ends message content stack.
        .padding(.horizontal, 14) // Preserves existing bubble inset.
        .padding(.vertical, 11) // Preserves existing bubble inset.
        .background(isUser ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor)) // Preserves native role distinction.
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)) // Preserves established restrained geometry.
        .frame(maxWidth: 680, alignment: isUser ? .trailing : .leading) // Preserves the existing reading width.
    }

    private func sourcesDisclosure(for message: ChatMessage) -> some View { // Shows only exact source chunks selected by bounded context assembly.
        VStack(alignment: .leading, spacing: 8) { // Groups the compact trigger and optional traceable source rows.
            Button { withAnimation(.easeOut(duration: 0.18)) { expandedSourcesMessageID = expandedSourcesMessageID == message.id ? nil : message.id } } label: { // Toggles only this response's source evidence.
                HStack(spacing: 6) { // Aligns disclosure affordance, semantic label, and exact count.
                    Image(systemName: "books.vertical") // Uses a native source-library symbol.
                    Text("Sources") // Names the user-facing grounding evidence.
                    Text("\(message.citations.count)") // Reports the exact number of injected citations.
                        .foregroundStyle(.secondary) // Keeps count subordinate.
                    Image(systemName: "chevron.right") // Uses the standard disclosure affordance.
                        .font(.caption2.weight(.semibold)) // Keeps the indicator compact.
                        .rotationEffect(.degrees(expandedSourcesMessageID == message.id ? 90 : 0)) // Communicates current expanded state.
                } // Ends source-disclosure label.
                .contentShape(Rectangle()) // Gives the complete label a reliable click target.
            } // Ends source-disclosure trigger.
            .buttonStyle(.plain) // Keeps evidence secondary to the answer.
            .font(.caption.weight(.medium)) // Uses compact but readable source typography.
            .help(expandedSourcesMessageID == message.id ? "Hide exact Project Memory sources" : "Inspect exact Project Memory sources") // States that evidence is local and traceable.
            if expandedSourcesMessageID == message.id { // Renders excerpts only on explicit request.
                VStack(alignment: .leading, spacing: 10) { // Keeps each source distinct without decorative cards.
                    ForEach(message.citations) { citation in // Preserves context-assembly selection order.
                        VStack(alignment: .leading, spacing: 4) { // Shows known metadata above the exact excerpt.
                            HStack(spacing: 6) { // Aligns document identity, chunk index, and optional source reveal.
                                Text(citation.documentTitle) // Shows the persisted document title.
                                    .font(.caption.weight(.semibold)) // Gives source identity modest emphasis.
                                Text("Chunk \(citation.chunkIndex + 1)") // Converts the actual zero-based index to a readable one-based label.
                                    .font(.caption2.monospacedDigit()) // Keeps chunk identity compact and stable.
                                    .foregroundStyle(.secondary) // Makes position subordinate to document title.
                                Spacer(minLength: 4) // Pushes optional reveal action to the trailing edge.
                                if let sourceURL = citation.sourceURL { // Offers source navigation only when a real retained URL exists.
                                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([sourceURL]) } // Reveals the exact local source without modifying it.
                                        .buttonStyle(.link) // Uses a lightweight native secondary action.
                                        .font(.caption) // Keeps reveal compact.
                                } // Ends optional source reveal.
                            } // Ends citation metadata row.
                            if let filename = citation.sourceFilename { Text(filename).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) } // Shows only the actual known filename.
                            Text(citation.excerpt) // Shows the exact excerpt injected into the workflow context.
                                .font(.caption) // Keeps source evidence readable but subordinate.
                                .foregroundStyle(.secondary) // Distinguishes quoted source data from the assistant answer.
                                .textSelection(.enabled) // Allows exact copying and verification.
                                .lineLimit(8) // Bounds transcript height while preserving access through text selection after expansion.
                        } // Ends one citation row.
                        .accessibilityElement(children: .combine) // Reads source identity, chunk, and excerpt coherently.
                        if citation.id != message.citations.last?.id { Divider() } // Separates adjacent sources with native structure only.
                    } // Ends exact citation iteration.
                } // Ends expanded source list.
                .padding(10) // Separates evidence from surrounding transcript metadata.
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6)) // Uses the same restrained secondary surface as workflow trace.
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)) // Matches established disclosure geometry.
                .transition(.opacity) // Avoids aggressive transcript movement.
            } // Ends expanded source rendering.
        } // Ends source disclosure stack.
    } // Ends exact citation UI.

    private func workflowDisclosure(_ trace: WorkflowTrace) -> some View { // Renders progressive workflow detail beneath one assistant response.
        VStack(alignment: .leading, spacing: 8) { // Groups the compact trigger and optional ordered stages.
            Button { // Uses a standard keyboard-accessible disclosure trigger.
                withAnimation(.easeOut(duration: 0.2)) { // Applies a brief state-driven transition consistent with product UI guidance.
                    expandedTraceID = expandedTraceID == trace.id ? nil : trace.id // Toggles only the selected response trace.
                } // Ends the disclosure state animation.
            } label: { // Defines the compact metadata button content.
                HStack(spacing: 6) { // Aligns workflow summary with its disclosure indicator.
                    WorkflowTraceSummaryView(trace: trace) // Shows actual specialist, model, and total duration.
                    Image(systemName: "chevron.right") // Uses the native disclosure affordance.
                        .font(.caption2.weight(.semibold)) // Keeps the indicator visually subordinate.
                        .rotationEffect(.degrees(expandedTraceID == trace.id ? 90 : 0)) // Communicates the current expanded state.
                        .foregroundStyle(.tertiary) // Prevents the affordance from competing with the message.
                } // Ends the compact disclosure label.
                .contentShape(Rectangle()) // Gives the full metadata line a reliable click target.
            } // Ends the disclosure button.
            .buttonStyle(.plain) // Keeps the metadata line unobtrusive in the chat transcript.
            .help(expandedTraceID == trace.id ? "Hide workflow" : "Show workflow") // Provides precise hover guidance.

            if expandedTraceID == trace.id { // Reveals operational stages only when the user requests detail.
                WorkflowStepListView(trace: trace, showsDetail: false) // Shows actual names, outcomes, skips, and durations compactly.
                    .padding(10) // Separates the trace from its disclosure line.
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6)) // Uses the existing native secondary surface.
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)) // Matches existing restrained component geometry.
                    .transition(.opacity) // Uses a simple state transition that does not move surrounding content aggressively.
            } // Ends expanded trace display.
        } // Ends the workflow disclosure stack.
    } // Ends workflow disclosure rendering.

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) { // Adds attachment and validation state without changing the established composer hierarchy.
            if !attachments.isEmpty { // Shows validated images before submission.
                attachmentPreviewRow(attachments, allowsRemoval: true) // Provides compact preview and removal controls.
            } // Ends pending attachment preview.
            if let attachmentError { // Displays content-validation failures inline rather than in a modal.
                Label(attachmentError, systemImage: "exclamationmark.triangle") // Communicates the controlled rejection visibly.
                    .font(.caption) // Keeps diagnostic subordinate to the composer.
                    .foregroundStyle(.orange) // Uses semantic warning color with a symbol and text.
            } // Ends attachment error display.
            HStack(alignment: .bottom, spacing: 10) { // Keeps picker, microphone, text, and send actions aligned.
            Button { chooseImages() } label: { // Opens the native multi-selection image picker.
                Image(systemName: "photo.badge.plus") // Uses a familiar native attachment affordance.
                    .frame(width: 28, height: 28) // Keeps a reliable desktop click target.
            } // Ends image-picker action.
            .buttonStyle(.borderless) // Keeps the utility action visually secondary.
            .help("Attach PNG, JPEG, or HEIC images") // States the exact supported formats.
            .disabled(sending) // Prevents composer mutation during submission.

            VoiceComposerControl(controller: appState.voiceController) { transcript in // Observes service state independently from AppState publication.
                let composerText = appState.consumeVoiceDraftForComposer() ?? transcript // Consumes trace evidence and resolves the actual composer transcript once.
                prompt = composerText // Places the transcript visibly in the editable composer before any optional send.
                if appState.sendAutomaticallyAfterTranscription { send() } // Sends only when the persisted opt-in preference is enabled.
            } // Ends Voice service control.

            TextField(
                attachments.isEmpty ? "Message your local models…" : "Ask about the attached image…",
                text: $prompt,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
            .disabled(sending)
            .onSubmit {
                send() // Lets the workflow load the selected text model or return a controlled backend error.
            }

            Button {
                send()
            } label: {
                ZStack {
                    Circle()
                        .fill(canSend ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(width: 38, height: 38)

                    if sending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(canSend ? Color.white : Color.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command) // Supports the requested Command-Return send workflow without removing pointer or Return submission.
            .help(appState.isGenerating ? "A workflow is already running" : "Send message (⌘↩)") // Communicates exact shortcut and current availability.
            } // Ends composer action row.
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay { // Shows a restrained native drag target without decorative redesign.
            RoundedRectangle(cornerRadius: 10, style: .continuous) // Matches the composer geometry.
                .stroke(isDropTargeted ? Color.accentColor : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [5])) // Highlights only during a supported drag.
                .padding(4) // Keeps the drop outline inside the bar bounds.
        } // Ends drag-target overlay.
        .dropDestination(for: URL.self) { urls, _ in // Accepts file URLs from Finder and other native macOS sources.
            addImages(from: urls) // Applies the exact same content validation as the picker.
            return !urls.isEmpty // Reports handled state only when URLs were supplied.
        } isTargeted: { targeted in // Observes drag targeting for the restrained outline.
            isDropTargeted = targeted // Publishes native drop-target state.
        } // Ends image drag-and-drop behavior.
    }

    private var canSend: Bool {
        !sending && !appState.isGenerating && (!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) // Allows image-only requests while preventing empty or overlapping workflows.
    }

    private func send() {
        guard canSend else { return }

        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestAttachments = attachments // Captures the validated list before clearing visible composer state.
        prompt = ""
        attachments = [] // Clears pending images only after capturing the typed request.
        attachmentError = nil // Clears stale validation feedback for the submitted request.
        sending = true

        Task {
            await appState.sendChat(UserRequest(text: text, attachments: requestAttachments)) // Sends one typed request without embedding image bytes.
            sending = false
        }
    }

    private func createNormalConversation() { // Creates one durable ordinary conversation from the sidebar or Command-N.
        Task { // Performs actor-isolated persistence without blocking the main run loop.
            do { _ = try await appState.workspace.createConversation(projectID: nil) } // Persists and selects a normal conversation with Project Memory OFF by default.
            catch { appState.workspace.errorMessage = error.localizedDescription } // Surfaces bounded storage failure through the shared inline workspace error.
        } // Ends asynchronous normal-chat creation.
    } // Ends new normal conversation action.

    private func beginRename(_ conversation: Conversation) { // Prepares the native rename alert with exact current visible metadata.
        editedConversationTitle = conversation.title // Starts from the persisted title rather than a stale row copy.
        conversationToRename = conversation // Retains the exact stable identity until confirmation or cancellation.
    } // Ends rename preparation.

    private func renameSelectedConversation() { // Applies one explicitly confirmed local title mutation.
        guard let conversation = conversationToRename else { return } // Ignores a stale alert action after dismissal.
        let title = editedConversationTitle // Captures visible text before clearing transient state.
        conversationToRename = nil // Dismisses the alert immediately while persistence completes.
        Task { // Performs actor-isolated atomic storage asynchronously.
            do { try await appState.workspace.renameConversation(id: conversation.id, title: title) } // Renames only the exact app-owned conversation.
            catch { appState.workspace.errorMessage = error.localizedDescription } // Reports validation or persistence failure without losing messages.
        } // Ends asynchronous rename.
    } // Ends confirmed conversation rename.

    private func deleteSelectedConversation() { // Applies one explicitly confirmed app-owned conversation deletion.
        guard let conversation = conversationToDelete else { return } // Ignores a stale confirmation after dismissal.
        conversationToDelete = nil // Dismisses the alert before the durable operation begins.
        Task { // Performs atomic deletion outside the synchronous button callback.
            do { try await appState.workspace.deleteConversation(id: conversation.id) } // Deletes only the exact conversation and selects or creates a safe successor.
            catch { appState.workspace.errorMessage = error.localizedDescription } // Reports bounded failure without affecting Project documents.
        } // Ends asynchronous deletion.
    } // Ends confirmed conversation deletion.

    private func conversationAccessibilityLabel(_ conversation: Conversation) -> String { // Produces a concise VoiceOver label from known persisted facts.
        let association: String // Declares normal or real project association.
        if let projectID = conversation.projectID { association = appState.workspace.projectSummaries.first(where: { $0.id == projectID })?.project.name ?? "Unavailable project" } // Resolves an actual project name without inventing one.
        else { association = "Normal Chat" } // Labels an ordinary conversation.
        return "\(conversation.title), \(association)" // Combines identity and scope for nonvisual selection.
    } // Ends conversation accessibility labeling.

    private func chooseImages() { // Presents the native macOS image picker with the exact supported allowlist.
        let panel = NSOpenPanel() // Creates a standard user-controlled file selection panel.
        panel.canChooseFiles = true // Allows local image files.
        panel.canChooseDirectories = false // Rejects folders before validation.
        panel.allowsMultipleSelection = true // Allows a request to carry more than one validated image.
        panel.allowedContentTypes = [.png, .jpeg, .heic] // Filters the picker while content validation remains authoritative.
        panel.prompt = "Attach" // Uses a clear picker confirmation verb.
        guard panel.runModal() == .OK else { return } // Leaves composer state untouched when the user cancels.
        addImages(from: panel.urls) // Applies content-based validation to every selected URL.
    } // Ends native image selection.

    private func addImages(from urls: [URL]) { // Validates picker and drop inputs through one deterministic service.
        attachmentError = nil // Clears an older error before validating the new batch.
        for url in urls { // Preserves user selection order.
            do { // Attempts bounded content-based PNG, JPEG, or HEIC validation.
                let result = try AttachmentValidationService.validateImage(at: url) // Reads metadata and a tiny decode without retaining full pixels.
                attachments.append(.image(result.attachment)) // Adds only the validated URL-backed value.
            } catch { // Keeps valid earlier selections while reporting the first current failure.
                attachmentError = error.localizedDescription // Shows a privacy-safe controlled diagnostic inline.
                break // Stops the current batch after the first rejected input.
            } // Ends image validation recovery.
        } // Ends selected URL iteration.
    } // Ends pending image addition.

    private func attachmentPreviewRow(_ values: [UserAttachment], allowsRemoval: Bool) -> some View { // Renders compact local image previews for composer and history.
        ScrollView(.horizontal, showsIndicators: false) { // Keeps multiple previews usable without increasing vertical height.
            HStack(spacing: 8) { // Arranges images in stable request order.
                ForEach(values) { attachment in // Renders only typed image cases in the current foundation.
                    if case let .image(image) = attachment { // Extracts validated image metadata.
                        ZStack(alignment: .topTrailing) { // Overlays an optional native removal action.
                            Group { // Builds a local thumbnail or a controlled placeholder.
                                if let thumbnail = NSImage(contentsOf: image.url) { Image(nsImage: thumbnail).resizable().scaledToFill() } // Decodes visible UI pixels only for an explicit preview.
                                else { Image(systemName: "photo").foregroundStyle(.secondary) } // Handles a file removed after validation.
                            } // Ends thumbnail content selection.
                            .frame(width: 72, height: 54) // Uses a compact readable thumbnail size.
                            .background(Color(nsColor: .controlBackgroundColor)) // Preserves native surface behavior.
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)) // Matches the restrained composer geometry.
                            .clipped() // Prevents scaled pixels from escaping preview bounds.
                            .help("\(image.originalFilename) · \(image.pixelWidth)×\(image.pixelHeight)") // Exposes visible filename and dimensions only in the local UI.
                            if allowsRemoval { // Adds removal only for pending composer state.
                                Button { attachments.removeAll { $0.id == attachment.id } } label: { // Removes exactly the selected attachment.
                                    Image(systemName: "xmark.circle.fill") // Uses the familiar native removal symbol.
                                        .symbolRenderingMode(.palette) // Keeps icon legible over light and dark thumbnails.
                                        .foregroundStyle(.white, .black.opacity(0.65)) // Supplies contrast without a custom color system.
                                } // Ends pending attachment removal.
                                .buttonStyle(.plain) // Keeps the overlay compact.
                                .padding(3) // Separates the action from thumbnail edges.
                                .help("Remove \(image.originalFilename)") // Gives the action a precise accessible label.
                            } // Ends optional removal action.
                        } // Ends preview overlay.
                    } // Ends image case rendering.
                } // Ends attachment iteration.
            } // Ends preview row.
        } // Ends horizontal preview scrolling.
    } // Ends attachment preview rendering.
}

private struct VoiceComposerControl: View { // Keeps the Chat microphone control subscribed directly to Voice service state.
    @ObservedObject var controller: VoiceConversationController // Observes permission, recording, transcribing, ready, and failed transitions.
    let onTranscript: (String) -> Void // Returns a ready transcript to the parent composer without sending it.

    var body: some View { // Defines the compact state-aware Voice control.
        VStack(alignment: .leading, spacing: 3) { // Keeps an optional controlled error adjacent to the microphone action.
            Button { handleAction() } label: { // Toggles start or stop based on actual service state.
                if controller.state == .requestingPermission || controller.state == .transcribing { ProgressView().controlSize(.small).frame(width: 28, height: 28) } // Shows real permission or ASR progress.
                else { Image(systemName: controller.state == .recording ? "stop.circle.fill" : "mic.circle").foregroundStyle(controller.state == .recording ? .red : .primary).frame(width: 28, height: 28) } // Uses explicit record/stop affordances.
            } // Ends state-aware Voice action.
            .buttonStyle(.borderless) // Keeps the utility action secondary to Send.
            .disabled(controller.state == .requestingPermission || controller.state == .transcribing) // Prevents invalid transitions while awaiting a service.
            .help(controller.state == .recording ? "Stop recording and transcribe" : "Record a voice draft") // Explains that Voice creates a draft rather than auto-sending.
            if let failure = controller.failureMessage { // Shows permission, ASR, or capture failures without crashing Chat.
                Text(failure) // Displays the controlled service diagnostic.
                    .font(.caption2) // Keeps error feedback compact.
                    .foregroundStyle(.red) // Uses semantic failure color with readable text.
                    .frame(maxWidth: 260, alignment: .leading) // Bounds composer expansion.
            } // Ends Voice failure display.
        } // Ends Voice control stack.
    } // Ends Voice control body.

    private func handleAction() { // Executes only user-triggered Voice state transitions.
        Task { @MainActor in // Keeps controller and composer updates on the main actor.
            if controller.state == .recording { // Stops an active press-record capture.
                if let draft = await controller.stopRecordingAndTranscribe() { onTranscript(draft.text) } // Places a successful transcript in the composer without sending.
            } else { // Starts permission and capture from idle, ready, or failed state.
                if controller.state == .failed { controller.resetFailure() } // Clears the prior controlled failure before retrying.
                await controller.startRecording() // Requests permission only because this explicit action occurred.
            } // Ends Voice action selection.
        } // Ends asynchronous Voice action.
    } // Ends Voice action handling.
} // Ends subscribed Voice composer control.
