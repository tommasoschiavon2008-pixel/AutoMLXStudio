import SwiftUI // Supplies native macOS list, form, split-view, sheet, confirmation, and accessibility controls.

@MainActor // Keeps StateObject construction and all controller interactions on the SwiftUI actor.
struct RemoteModelsView: View { // Presents multi-server private inference configuration without becoming a full infrastructure console.
    @StateObject private var controller: RemoteModelsController // Owns durable profile, health, discovery, and operation state for this surface.
    @State private var selectedServerID: UUID? // Tracks the exact profile shown in the detail pane.
    @State private var editorDraft: RemoteServerEditorDraft? // Presents one focused add or edit sheet without retaining saved tokens.
    @State private var pendingRemoval: RemoteServerProfile? // Holds the exact server awaiting destructive confirmation.

    init() { // Creates the production surface with Application Support and Keychain boundaries.
        _controller = StateObject(wrappedValue: RemoteModelsController()) // Installs the production main-actor controller once per view lifetime.
    } // Ends production view construction.

    init(controller: RemoteModelsController) { // Creates an injectable surface for previews, deterministic tests, and composition.
        _controller = StateObject(wrappedValue: controller) // Retains the supplied controller as this surface's state owner.
    } // Ends injectable view construction.

    var body: some View { // Defines the complete restrained remote-model management surface.
        VStack(alignment: .leading, spacing: 16) { // Uses the existing Models page rhythm without nested decorative cards.
            header // States scope and exposes the single primary add action.
            if let notice = controller.notice { // Presents the latest save, removal, health, or discovery outcome.
                noticeView(notice) // Uses symbol and text so feedback never relies on color alone.
            } // Ends optional feedback presentation.
            HSplitView { // Uses a familiar macOS source-list and detail relationship for multiple server profiles.
                serverSidebar // Provides dense selection and first-run guidance.
                selectedServerDetail // Shows configuration, health, and discovered remote models progressively.
            } // Ends native horizontal split navigation.
            .frame(minHeight: 480) // Keeps both panes usable in standard desktop windows.
        } // Ends the remote-models page stack.
        .padding(24) // Matches established detail-page insets.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) // Keeps operational content anchored predictably.
        .background(Color(nsColor: .windowBackgroundColor)) // Preserves native light and dark appearance contrast.
        .task { // Loads durable profiles when this destination becomes active.
            await controller.load() // Performs persistence work away from the rendering pass.
            normalizeSelection() // Selects the first durable profile without overriding an existing valid choice.
        } // Ends initial profile loading.
        .onChange(of: controller.profiles) { _, _ in // Keeps selection coherent after add, edit, or removal.
            normalizeSelection() // Resolves stale or absent selection against current durable profiles.
        } // Ends durable-profile selection synchronization.
        .sheet(item: $editorDraft) { draft in // Presents a focused native form for one add or edit operation.
            RemoteServerEditorView(controller: controller, initialDraft: draft) { // Isolates temporary form and SecureField state from the profile list.
                selectedServerID = draft.id // Selects the exact added or edited profile after confirmed persistence.
            } // Ends editor sheet construction.
        } // Ends add or edit sheet presentation.
        .confirmationDialog("Remove remote server?", isPresented: removalDialogBinding, presenting: pendingRemoval) { profile in // Requires explicit confirmation before destructive profile and token deletion.
            Button("Remove server", role: .destructive) { // Names the exact destructive result.
                Task { // Runs actor-backed persistence without blocking SwiftUI.
                    await controller.remove(serverID: profile.id) // Removes only the confirmed profile and its separate token.
                    pendingRemoval = nil // Clears confirmation state after the operation returns.
                } // Ends asynchronous removal task.
            } // Ends confirmed removal action.
            Button("Cancel", role: .cancel) { // Preserves the profile without mutation.
                pendingRemoval = nil // Clears only local confirmation state.
            } // Ends removal cancellation.
        } message: { profile in // Explains exact destructive scope before confirmation.
            Text("This removes \(profile.displayName) and its saved Keychain token. Other servers are unchanged.") // States recoverability and isolation clearly.
        } // Ends destructive confirmation dialog.
    } // Ends the remote-models view body.

    private var header: some View { // Renders page identity, execution boundary, and the primary creation action.
        HStack(alignment: .top, spacing: 18) { // Aligns concise explanatory copy with the primary action.
            VStack(alignment: .leading, spacing: 5) { // Groups destination title and literal execution behavior.
                Text("Remote models") // Names the private inference management destination.
                    .font(.title2.bold()) // Creates clear hierarchy without a marketing-scale heading.
                Text("Connect to user-managed OpenAI-compatible servers on loopback, LAN, or a private overlay network.") // Explains supported manually configured topology.
                    .foregroundStyle(.secondary) // Keeps supporting copy subordinate.
                    .frame(maxWidth: 680, alignment: .leading) // Maintains a readable line length in wide windows.
                Label("Inference can be remote. Files, commands, builds, and tests always run on this Mac.", systemImage: "macbook.and.iphone") // Makes the model versus tool execution boundary explicit.
                    .font(.callout) // Keeps the key trust statement readable.
                    .foregroundStyle(.secondary) // Uses restrained native hierarchy.
            } // Ends heading and execution-boundary copy.
            Spacer(minLength: 18) // Pushes the primary action to the trailing edge.
            Button("Add server", systemImage: "plus") { // Uses a direct verb-and-object primary action.
                editorDraft = RemoteServerEditorDraft() // Opens a blank non-secret manual endpoint form.
            } // Ends add-server action.
            .buttonStyle(.borderedProminent) // Gives the single creation action appropriate emphasis.
            .disabled(controller.isSaving) // Prevents overlapping profile submissions.
            .keyboardShortcut("n", modifiers: [.command, .shift]) // Provides an explicit discoverable desktop shortcut distinct from new chat.
            .help("Add a manually configured private inference server") // Clarifies that no LAN scan will occur.
        } // Ends header layout.
    } // Ends remote-models header.

    private var serverSidebar: some View { // Renders dense multi-profile navigation and first-run guidance.
        VStack(spacing: 0) { // Keeps the source list and its small action footer visually connected.
            if controller.isLoading { // Shows stable shape while durable profiles load.
                loadingServerRows // Uses redacted rows rather than an isolated center spinner.
            } else if controller.profiles.isEmpty { // Teaches first configuration without an empty blank pane.
                emptyServerState // Explains manual private endpoint setup and offers the primary action.
            } else { // Shows every configured server in deterministic store order.
                List(selection: $selectedServerID) { // Uses native macOS selection and keyboard behavior.
                    ForEach(controller.profiles) { profile in // Renders each non-secret profile exactly once.
                        serverRow(profile) // Shows identity, endpoint, enabled state, and last health observation.
                            .tag(profile.id) // Binds source-list selection to the stable profile UUID.
                    } // Ends profile iteration.
                } // Ends native server source list.
                .listStyle(.sidebar) // Uses the established macOS source-list vocabulary.
            } // Ends sidebar content selection.
            Divider() // Separates navigation from profile-level actions.
            HStack(spacing: 8) { // Provides compact native add and remove controls.
                Button("Add server", systemImage: "plus") { // Duplicates the primary action where source-list users expect it.
                    editorDraft = RemoteServerEditorDraft() // Opens a blank manual endpoint form.
                } // Ends sidebar add action.
                .labelStyle(.iconOnly) // Keeps the compact footer uncluttered.
                .help("Add server") // Preserves an explicit accessible hover label.
                Button("Remove server", systemImage: "minus") { // Starts confirmation for the selected exact profile.
                    pendingRemoval = selectedProfile // Captures immutable confirmation context.
                } // Ends sidebar remove action.
                .labelStyle(.iconOnly) // Matches the native source-list footer vocabulary.
                .help("Remove selected server") // Gives the icon a clear standalone meaning.
                .disabled(selectedProfile.map { !controller.canRemove(serverID: $0.id) } ?? true) // Prevents ambiguous or concurrent deletion.
                Spacer() // Keeps compact actions at the leading edge.
            } // Ends source-list action footer.
            .buttonStyle(.borderless) // Matches standard macOS source-list controls.
            .padding(.horizontal, 10) // Aligns controls with list content.
            .padding(.vertical, 7) // Keeps the footer comfortably clickable without excess height.
        } // Ends sidebar stack.
        .frame(minWidth: 230, idealWidth: 270, maxWidth: 330) // Keeps names and endpoints readable while preserving detail space.
        .background(Color(nsColor: .controlBackgroundColor)) // Creates a subtle native secondary surface for navigation.
    } // Ends server sidebar.

    private var loadingServerRows: some View { // Preserves sidebar shape during initial durable loading.
        VStack(alignment: .leading, spacing: 18) { // Mimics three compact source-list rows.
            ForEach(0..<3, id: \.self) { _ in // Produces a small stable skeleton rather than an indeterminate center spinner.
                VStack(alignment: .leading, spacing: 5) { // Matches visible server row structure.
                    Text("Private inference server") // Supplies placeholder name geometry.
                        .font(.headline) // Matches loaded row hierarchy.
                    Text("https://private-host:1234/v1") // Supplies placeholder endpoint geometry.
                        .font(.caption.monospaced()) // Matches loaded endpoint typography.
                } // Ends one skeleton row.
                .redacted(reason: .placeholder) // Communicates loading without decorative animation.
            } // Ends skeleton iteration.
            Spacer() // Keeps skeletons aligned to the top.
        } // Ends skeleton list.
        .padding(14) // Matches source-list inset.
        .accessibilityLabel("Loading remote servers") // Replaces meaningless redacted content for assistive technology.
    } // Ends initial loading state.

    private var emptyServerState: some View { // Teaches the manual first-run flow without claiming automatic discovery.
        VStack(spacing: 12) { // Centers concise guidance in the narrow navigation pane.
            Image(systemName: "network") // Uses a familiar semantic network symbol.
                .font(.title) // Gives the empty state a clear anchor without illustration.
                .foregroundStyle(.secondary) // Avoids decorative accent color.
                .accessibilityHidden(true) // Leaves adjacent text as the meaningful label.
            Text("No remote servers") // States the actual durable condition.
                .font(.headline) // Establishes compact empty-state hierarchy.
            Text("Add a host and port manually. AutoMLX Studio never scans your network.") // Teaches configuration and privacy behavior.
                .font(.callout) // Keeps guidance readable in the narrow pane.
                .foregroundStyle(.secondary) // Preserves hierarchy.
                .multilineTextAlignment(.center) // Supports narrow wrapping cleanly.
            Button("Add server") { // Offers the next concrete action.
                editorDraft = RemoteServerEditorDraft() // Opens the manual endpoint form.
            } // Ends empty-state creation action.
            .buttonStyle(.bordered) // Uses familiar secondary styling because the header already carries the primary action.
        } // Ends first-run guidance.
        .padding(22) // Gives the compact empty state sufficient breathing room.
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Centers guidance within the available sidebar.
    } // Ends empty server state.

    @ViewBuilder // Selects a concrete detail state while preserving SwiftUI type inference.
    private var selectedServerDetail: some View { // Renders either one server's operational detail or a selection prompt.
        if let profile = selectedProfile { // Handles an exact current profile selection.
            serverDetail(profile) // Shows endpoint, health, models, and controls.
        } else { // Handles no selection after load or removal.
            VStack(spacing: 10) { // Provides a concise native selection prompt.
                Image(systemName: "sidebar.left") // Indicates the source-list relationship.
                    .font(.title) // Gives the prompt a restrained visual anchor.
                    .foregroundStyle(.secondary) // Avoids decorative emphasis.
                    .accessibilityHidden(true) // Leaves text as the accessible instruction.
                Text("Select a remote server") // Gives the exact next action.
                    .font(.headline) // Establishes clear compact hierarchy.
                Text("Connection health and discovered models appear here after an explicit check.") // Explains progressive disclosure behavior.
                    .foregroundStyle(.secondary) // Keeps supporting copy subordinate.
            } // Ends selection guidance.
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Centers the prompt in the detail pane.
        } // Ends detail state selection.
    } // Ends selected-server detail switching.

    private func serverRow(_ profile: RemoteServerProfile) -> some View { // Renders one dense source-list profile row.
        VStack(alignment: .leading, spacing: 4) { // Groups name, endpoint, and explicit state.
            HStack(spacing: 7) { // Aligns server name with non-color health state.
                Text(profile.displayName) // Shows the user-defined server identity.
                    .font(.headline) // Makes the selected target scannable.
                    .lineLimit(1) // Preserves dense source-list rhythm.
                Spacer(minLength: 4) // Keeps status at the trailing edge.
                Image(systemName: healthSymbol(controller.health(for: profile.id)?.status)) // Communicates observed state with a semantic shape.
                    .foregroundStyle(healthColor(controller.health(for: profile.id)?.status)) // Adds restrained semantic color as secondary evidence.
                    .accessibilityHidden(true) // Leaves explicit state text in the accessibility label.
            } // Ends name and health row.
            Text(endpointText(profile)) // Shows the manually configured credential-free endpoint.
                .font(.caption.monospaced()) // Distinguishes machine identity from display copy.
                .foregroundStyle(.secondary) // Preserves native hierarchy.
                .lineLimit(1) // Keeps one compact row.
                .truncationMode(.middle) // Preserves both scheme and base path when narrow.
            Text("Remote, \(profile.isEnabled ? healthText(controller.health(for: profile.id)?.status) : "Disabled")") // Makes location and operational state explicit in words.
                .font(.caption) // Keeps status subordinate but readable.
                .foregroundStyle(.secondary) // Avoids heavy color on inactive state.
        } // Ends one source-list row.
        .padding(.vertical, 4) // Maintains a comfortable selection target.
        .opacity(profile.isEnabled ? 1 : 0.68) // Subordinates disabled entries while preserving contrast and text state.
        .accessibilityElement(children: .combine) // Presents name, endpoint, location, and state as one selectable item.
        .accessibilityLabel("\(profile.displayName), remote server, \(profile.isEnabled ? healthText(controller.health(for: profile.id)?.status) : "disabled")") // Provides standalone selection context.
    } // Ends source-list server row.

    private func serverDetail(_ profile: RemoteServerProfile) -> some View { // Renders one selected server's configuration and live observations.
        ScrollView { // Keeps details usable in shorter windows and with larger accessibility text.
            VStack(alignment: .leading, spacing: 18) { // Uses a restrained operational rhythm with progressive sections.
                serverIdentity(profile) // Shows remote identity, endpoint, enablement, and edit action.
                if let warning = profile.cleartextSecurityWarning { // Shows the backend's exact non-loopback HTTP warning.
                    Label(warning, systemImage: "exclamationmark.triangle.fill") // Communicates risk through symbol and explanatory text.
                        .font(.callout) // Keeps security guidance readable.
                        .foregroundStyle(.orange) // Uses semantic warning color only for the warning state.
                        .padding(10) // Separates warning text from surrounding controls.
                        .frame(maxWidth: .infinity, alignment: .leading) // Gives long guidance predictable wrapping.
                        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8)) // Uses one subtle state surface without decorative shadow or glass.
                } // Ends conditional cleartext warning.
                connectionSection(profile) // Shows API-level health evidence and explicit actions.
                modelSection(profile) // Shows discovered remote identities without invented metadata.
            } // Ends detail content stack.
            .padding(20) // Provides comfortable inset from the split divider and scroll edges.
            .frame(maxWidth: .infinity, alignment: .leading) // Keeps operational details aligned on wide surfaces.
        } // Ends selected-server detail scrolling.
        .background(Color(nsColor: .windowBackgroundColor)) // Preserves the primary native detail surface.
    } // Ends selected-server detail rendering.

    private func serverIdentity(_ profile: RemoteServerProfile) -> some View { // Shows literal server identity and Mac execution boundary.
        VStack(alignment: .leading, spacing: 12) { // Groups heading, endpoint, state, and controls.
            HStack(alignment: .top, spacing: 12) { // Aligns identity with the edit action.
                VStack(alignment: .leading, spacing: 4) { // Groups remote display name and protocol type.
                    Label(profile.displayName, systemImage: "network") // Gives server identity a semantic native symbol.
                        .font(.title3.bold()) // Establishes selected-detail hierarchy without oversized type.
                    Text(backendText(profile.backendID)) // States the actual configured protocol adapter.
                        .font(.callout) // Keeps protocol visible but subordinate.
                        .foregroundStyle(.secondary) // Preserves hierarchy.
                } // Ends selected identity copy.
                Spacer() // Pushes edit to the trailing edge.
                Button("Edit server", systemImage: "pencil") { // Uses a direct verb-and-object label.
                    editorDraft = RemoteServerEditorDraft(profile: profile) // Opens a temporary form without retrieving the saved token.
                } // Ends edit action.
                .disabled(controller.operation(for: profile.id) != nil || controller.removingServerIDs.contains(profile.id)) // Prevents endpoint mutation during live network or delete work.
            } // Ends identity header.
            Text(endpointText(profile)) // Shows the complete credential-free manually configured endpoint.
                .font(.callout.monospaced()) // Makes the technical value easy to scan and copy.
                .textSelection(.enabled) // Supports copy into server diagnostics.
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) { // Aligns concise execution and authentication facts without metric cards.
                GridRow { // Shows model execution location.
                    Text("Inference") // Labels the execution dimension.
                        .foregroundStyle(.secondary) // Keeps field labels subordinate.
                    Text("Remote, \(profile.displayName)") // States the actual remote model boundary.
                } // Ends inference location row.
                GridRow { // Shows tool execution location.
                    Text("Tools") // Labels the local execution dimension.
                        .foregroundStyle(.secondary) // Keeps field labels subordinate.
                    Text("Local, this Mac") // States that filesystem and commands never execute on the model server.
                } // Ends tool location row.
                GridRow { // Shows authentication behavior.
                    Text("Authentication") // Labels the credential dimension.
                        .foregroundStyle(.secondary) // Keeps field labels subordinate.
                    Text(profile.authenticationMode == .none ? "None" : "Bearer token in macOS Keychain") // States where credentials live without exposing them.
                } // Ends authentication row.
            } // Ends execution-boundary grid.
            Toggle("Enable this server for model routing", isOn: enabledBinding(profile)) // Provides the familiar native enablement affordance with explicit scope.
                .toggleStyle(.switch) // Uses standard macOS switch behavior.
                .disabled(controller.isSaving || controller.operation(for: profile.id) != nil) // Prevents overlapping persistence and network changes.
        } // Ends selected server identity content.
    } // Ends server identity rendering.

    private func connectionSection(_ profile: RemoteServerProfile) -> some View { // Shows real API health evidence and explicit management actions.
        GroupBox("Connection") { // Uses one native semantic group rather than nested status cards.
            VStack(alignment: .leading, spacing: 12) { // Arranges observed fields and actions compactly.
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) { // Aligns state labels and values for fast scanning.
                    GridRow { // Shows evidence-based health status.
                        Text("Status") // Labels the observed state.
                            .foregroundStyle(.secondary) // Keeps the field label subordinate.
                        Label(healthText(controller.health(for: profile.id)?.status), systemImage: healthSymbol(controller.health(for: profile.id)?.status)) // Uses text and symbol for accessible state.
                            .foregroundStyle(healthColor(controller.health(for: profile.id)?.status)) // Adds restrained semantic color.
                    } // Ends status row.
                    GridRow { // Shows measured API latency.
                        Text("API latency") // Labels the live measurement.
                            .foregroundStyle(.secondary) // Keeps the field label subordinate.
                        Text(latencyText(controller.health(for: profile.id))) // Shows milliseconds only when actually measured.
                    } // Ends latency row.
                    GridRow { // Shows detected server family.
                        Text("Server type") // Labels conservative server detection.
                            .foregroundStyle(.secondary) // Keeps the field label subordinate.
                        Text(controller.health(for: profile.id)?.serverKind ?? "Unknown") // Preserves unknown rather than guessing.
                    } // Ends server-kind row.
                    GridRow { // Shows usable API compatibility.
                        Text("API") // Labels protocol compatibility.
                            .foregroundStyle(.secondary) // Keeps the field label subordinate.
                        Text(apiCompatibilityText(controller.health(for: profile.id))) // States compatible, incompatible, or not tested.
                    } // Ends API compatibility row.
                } // Ends connection evidence grid.
                if let error = controller.health(for: profile.id)?.conciseError { // Shows the backend's bounded redacted diagnostic when present.
                    Text(error) // Presents concise actionable failure text.
                        .font(.callout) // Keeps the diagnostic readable.
                        .foregroundStyle(.secondary) // Avoids excessive error emphasis alongside explicit status.
                        .textSelection(.enabled) // Supports copying safe diagnostics.
                } // Ends optional health diagnostic.
                HStack(spacing: 10) { // Places explicit network actions and progress on one familiar row.
                    Button("Test connection", systemImage: "bolt.horizontal.circle") { // Runs a usable API compatibility check rather than a TCP probe.
                        Task { await controller.testConnection(serverID: profile.id) } // Delegates network work to the controller and backend actors.
                    } // Ends connection-test action.
                    .buttonStyle(.borderedProminent) // Gives the section's primary validation action clear emphasis.
                    Button("Refresh models", systemImage: "arrow.clockwise") { // Runs one explicit uncached model discovery.
                        Task { await controller.refreshModels(serverID: profile.id) } // Delegates bounded network work off the rendering path.
                    } // Ends model refresh action.
                    .buttonStyle(.bordered) // Keeps refresh secondary to connection validation.
                    if let operation = controller.operation(for: profile.id) { // Shows current real network activity inline.
                        ProgressView() // Uses the native compact progress affordance for a user-triggered operation.
                            .controlSize(.small) // Keeps progress proportional to action controls.
                            .accessibilityHidden(true) // Leaves adjacent activity text as the meaningful description.
                        Text(operation.displayName) // States the actual API work underway.
                            .font(.callout) // Keeps activity readable.
                            .foregroundStyle(.secondary) // Preserves hierarchy.
                    } // Ends inline operation progress.
                    Spacer() // Keeps controls and progress aligned to the leading edge.
                } // Ends connection action row.
                .disabled(controller.operation(for: profile.id) != nil || controller.removingServerIDs.contains(profile.id) || !profile.isEnabled) // Prevents overlap, removal race, and disabled-server traffic.
            } // Ends connection group content.
            .padding(8) // Matches existing Models GroupBox inset.
        } // Ends connection group.
    } // Ends connection section rendering.

    private func modelSection(_ profile: RemoteServerProfile) -> some View { // Shows only remote model metadata proven by discovery.
        let models = controller.models(for: profile.id) // Reads the selected server's isolated normalized model list.
        return GroupBox("Discovered models") { // Uses one native list container for arbitrary model count.
            VStack(alignment: .leading, spacing: 0) { // Builds a dense divider-separated list.
                if models.isEmpty { // Handles never-refreshed and valid zero-model states honestly.
                    VStack(alignment: .leading, spacing: 5) { // Groups concise empty state and next action guidance.
                        Text(controller.health(for: profile.id)?.apiCompatible == true ? "No models reported" : "Models not loaded") // Distinguishes an actual empty listing from missing observation.
                            .font(.headline) // Makes the current state scannable.
                        Text(controller.health(for: profile.id)?.apiCompatible == true ? "The server API responded but did not list a model." : "Test the connection or refresh models to query the configured server.") // Gives evidence-based explanation and next action.
                            .font(.callout) // Keeps guidance readable.
                            .foregroundStyle(.secondary) // Preserves hierarchy.
                    } // Ends model empty-state copy.
                    .padding(10) // Matches loaded row inset.
                } else { // Shows every actually discovered remote model.
                    ForEach(Array(models.enumerated()), id: \.element.id) { index, model in // Preserves provider order while supplying divider position.
                        if index > 0 { // Separates adjacent models without nested containers.
                            Divider() // Uses native list separation.
                        } // Ends divider condition.
                        HStack(alignment: .top, spacing: 10) { // Aligns semantic location icon with trustworthy metadata.
                            Image(systemName: "network") // Identifies remote execution without color dependence.
                                .foregroundStyle(.secondary) // Avoids decorative accent use.
                                .frame(width: 20) // Aligns every discovered model row.
                                .accessibilityHidden(true) // Leaves adjacent location text as the meaningful label.
                            VStack(alignment: .leading, spacing: 4) { // Groups exact provider ID and honest metadata state.
                                Text(model.id) // Shows the provider-facing remote model identifier.
                                    .font(.callout.monospaced().weight(.medium)) // Makes machine identity precise and scannable.
                                    .textSelection(.enabled) // Supports copying into assignment or diagnostics.
                                Text("Remote, available in last discovery") // States execution location and observed availability explicitly.
                                    .font(.caption) // Keeps evidence subordinate.
                                    .foregroundStyle(.secondary) // Preserves hierarchy.
                                Text("Capabilities: not reported") // Avoids inventing tool calling, context size, quantization, or modalities.
                                    .font(.caption) // Keeps uncertainty visible but compact.
                                    .foregroundStyle(.secondary) // Preserves hierarchy.
                            } // Ends discovered model metadata.
                            Spacer() // Keeps metadata aligned to the leading edge.
                        } // Ends one discovered model row.
                        .padding(10) // Provides a comfortable dense row target.
                        .accessibilityElement(children: .combine) // Presents identity, location, availability, and uncertainty together.
                    } // Ends discovered model iteration.
                } // Ends model list state selection.
            } // Ends discovered model stack.
        } // Ends discovered models group.
    } // Ends remote model list rendering.

    private func noticeView(_ notice: RemoteModelsNotice) -> some View { // Renders concise semantic controller feedback.
        HStack(alignment: .firstTextBaseline, spacing: 8) { // Aligns result symbol, text, and dismissal.
            Label(notice.message, systemImage: noticeSymbol(notice.kind)) // Communicates result through both words and shape.
                .font(.callout) // Keeps operational feedback readable.
                .foregroundStyle(noticeColor(notice.kind)) // Applies restrained semantic color.
                .textSelection(.enabled) // Supports copying safe diagnostics.
            Spacer(minLength: 8) // Pushes dismissal to the trailing edge.
            Button("Dismiss", systemImage: "xmark") { // Gives feedback dismissal a standalone accessible name.
                controller.notice = nil // Clears only transient presentation state.
            } // Ends notice dismissal.
            .labelStyle(.iconOnly) // Keeps the status row compact.
            .buttonStyle(.borderless) // Uses a familiar unobtrusive macOS dismissal affordance.
            .help("Dismiss message") // Clarifies the icon on hover.
        } // Ends notice row layout.
        .padding(10) // Separates feedback from surrounding content.
        .background(noticeColor(notice.kind).opacity(0.08), in: RoundedRectangle(cornerRadius: 8)) // Uses a subtle semantic state surface without shadow or glass.
        .accessibilityElement(children: .combine) // Announces the complete result coherently.
    } // Ends notice rendering.

    private var selectedProfile: RemoteServerProfile? { // Resolves selection against current durable state.
        guard let selectedServerID else { // Handles first run or cleared selection.
            return nil // Reports no selected profile.
        } // Ends absent selection handling.
        return controller.profiles.first { $0.id == selectedServerID } // Returns only an exact current profile.
    } // Ends selected-profile lookup.

    private var removalDialogBinding: Binding<Bool> { // Bridges optional confirmation context to SwiftUI's Boolean presentation API.
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }) // Clears exact context only when the dialog dismisses.
    } // Ends removal dialog binding.

    private func normalizeSelection() { // Keeps source-list selection valid after durable profile changes.
        if let selectedServerID, controller.profiles.contains(where: { $0.id == selectedServerID }) { // Preserves an existing valid user choice.
            return // Avoids surprising selection jumps.
        } // Ends valid-selection preservation.
        selectedServerID = controller.profiles.first?.id // Selects the first stable profile or clears selection when empty.
    } // Ends selection normalization.

    private func enabledBinding(_ profile: RemoteServerProfile) -> Binding<Bool> { // Creates a native toggle binding backed by validated async persistence.
        Binding(get: { profile.isEnabled }, set: { enabled in Task { await controller.setEnabled(enabled, serverID: profile.id) } }) // Applies the exact explicit choice without optimistic hidden state.
    } // Ends enabled toggle binding.

    private func endpointText(_ profile: RemoteServerProfile) -> String { // Produces a credential-free endpoint string for display and copy.
        (try? profile.baseURL().absoluteString) ?? "Invalid endpoint" // Uses production validation and never includes a token.
    } // Ends endpoint display text.

    private func backendText(_ backendID: ModelBackendID) -> String { // Produces honest protocol adapter labels.
        switch backendID { // Selects the stable backend identity.
        case .remoteOpenAICompatible: // Handles the implemented private HTTP adapter.
            return "OpenAI-compatible remote API" // Names protocol compatibility without implying OpenAI cloud use.
        case .remoteOllama: // Handles reserved optional adapter configuration.
            return "Ollama adapter unavailable in this version" // Avoids claiming unimplemented behavior.
        case .localMLX: // Handles defensive invalid persisted configuration.
            return "Invalid local backend for remote server" // Makes the location mismatch explicit.
        } // Ends backend label selection.
    } // Ends backend display text.

    private func healthText(_ status: ModelBackendHealthStatus?) -> String { // Produces explicit readable observed state.
        switch status { // Selects known observation or absence.
        case .healthy: return "Healthy" // Labels a compatible API and selected or discovered model.
        case .degraded: return "Degraded" // Labels a reachable but incomplete or incompatible observation.
        case .unavailable: return "Unavailable" // Labels configuration or backend unavailability.
        case .serverOffline: return "Server offline" // Labels private server reachability loss.
        case .unknown, .none: return "Not tested" // Preserves unknown before explicit validation or after cancellation.
        } // Ends health text selection.
    } // Ends health status text.

    private func healthSymbol(_ status: ModelBackendHealthStatus?) -> String { // Maps observed state to non-color SF Symbols.
        switch status { // Selects a semantic symbol.
        case .healthy: return "checkmark.circle.fill" // Indicates confirmed usable state.
        case .degraded: return "exclamationmark.triangle.fill" // Indicates compatibility or selected-model concern.
        case .unavailable, .serverOffline: return "xmark.circle.fill" // Indicates unusable current state.
        case .unknown, .none: return "questionmark.circle" // Indicates absence of reliable observation.
        } // Ends health symbol selection.
    } // Ends health symbol mapping.

    private func healthColor(_ status: ModelBackendHealthStatus?) -> Color { // Applies restrained semantic color as secondary state evidence.
        switch status { // Selects the native semantic color.
        case .healthy: return .green // Uses success color for confirmed API health.
        case .degraded: return .orange // Uses warning color for incomplete compatibility.
        case .unavailable, .serverOffline: return .red // Uses error color for current unusability.
        case .unknown, .none: return .secondary // Keeps unobserved state neutral.
        } // Ends health color selection.
    } // Ends health color mapping.

    private func latencyText(_ health: ModelBackendHealth?) -> String { // Formats only actually measured API latency.
        guard let milliseconds = health?.latencyMilliseconds else { // Handles absent or failed observations.
            return "Not measured" // Avoids inventing a zero-latency result.
        } // Ends absent latency handling.
        return "\(milliseconds) ms" // Presents exact whole milliseconds from the backend trace.
    } // Ends latency formatting.

    private func apiCompatibilityText(_ health: ModelBackendHealth?) -> String { // Presents usable API compatibility independently from reachability.
        guard let health else { // Handles no explicit check.
            return "Not tested" // Preserves unknown initial state.
        } // Ends absent health handling.
        return health.apiCompatible ? "OpenAI-compatible" : "Not compatible or unreachable" // States only evidence established by the models endpoint.
    } // Ends API compatibility text.

    private func noticeSymbol(_ kind: RemoteModelsNoticeKind) -> String { // Maps feedback severity to familiar native symbols.
        switch kind { // Selects the semantic symbol.
        case .success: return "checkmark.circle.fill" // Indicates confirmed completion.
        case .error: return "exclamationmark.circle.fill" // Indicates an actionable failure.
        case .information: return "info.circle" // Indicates neutral guidance.
        } // Ends notice symbol selection.
    } // Ends notice symbol mapping.

    private func noticeColor(_ kind: RemoteModelsNoticeKind) -> Color { // Maps feedback severity to restrained semantic color.
        switch kind { // Selects the semantic color.
        case .success: return .green // Uses success color only for confirmed completion.
        case .error: return .red // Uses error color only for failure feedback.
        case .information: return .secondary // Keeps neutral guidance understated.
        } // Ends notice color selection.
    } // Ends notice color mapping.
} // Ends the native remote-model management surface.

private struct RemoteServerEditorDraft: Identifiable { // Holds temporary non-secret profile fields plus unsaved SecureField input.
    let id: UUID // Preserves exact profile identity across sheet updates.
    let isNew: Bool // Distinguishes creation from edits for token validation and copy.
    let createdAt: Date // Preserves durable creation time during edits.
    var displayName: String // Holds temporary user-facing server identity.
    var backendID: ModelBackendID // Holds the selected typed protocol adapter.
    var scheme: RemoteServerScheme // Holds explicit HTTP or HTTPS transport.
    var host: String // Holds a manually entered host without auto-discovery.
    var port: Int // Holds the explicit server port.
    var basePath: String // Holds the optional API prefix.
    var authenticationMode: RemoteAuthenticationMode // Holds explicit no-auth or bearer configuration.
    var tokenInput: String // Holds only unsaved SecureField text for the current sheet lifetime.
    var removeExistingToken: Bool // Records an explicit request to clear a previously saved Keychain item.
    var connectionTimeoutSeconds: Double // Holds the bounded management request timeout.
    var inferenceTimeoutSeconds: Double // Holds the bounded generation request timeout.
    var isEnabled: Bool // Holds routing eligibility.

    init(profile: RemoteServerProfile? = nil) { // Creates a blank addition or a non-secret edit snapshot.
        self.id = profile?.id ?? UUID() // Reuses exact durable identity or creates a fresh opaque ID.
        self.isNew = profile == nil // Records whether the sheet represents insertion.
        self.createdAt = profile?.createdAt ?? Date() // Preserves or creates durable creation time.
        self.displayName = profile?.displayName ?? "" // Loads only the non-secret display name.
        self.backendID = profile?.backendID ?? .remoteOpenAICompatible // Defaults new profiles to the implemented adapter.
        self.scheme = profile?.scheme ?? .http // Defaults to common local/private server transport with warning support.
        self.host = profile?.host ?? "" // Requires manual host entry and performs no LAN scan.
        self.port = profile?.port ?? 1_234 // Uses a common local inference port only as editable form convenience.
        self.basePath = profile?.basePath ?? "/v1" // Defaults to the standard OpenAI-compatible prefix.
        self.authenticationMode = profile?.authenticationMode ?? .none // Makes no authentication the explicit initial choice.
        self.tokenInput = "" // Never reads or pre-fills an existing Keychain token.
        self.removeExistingToken = false // Preserves an existing token unless the user explicitly removes it.
        self.connectionTimeoutSeconds = profile?.connectionTimeoutSeconds ?? 10 // Uses the production management default.
        self.inferenceTimeoutSeconds = profile?.inferenceTimeoutSeconds ?? 120 // Uses the production inference default.
        self.isEnabled = profile?.isEnabled ?? true // Makes a newly saved server immediately eligible unless disabled explicitly.
    } // Ends editor draft construction.

    var profile: RemoteServerProfile { // Converts temporary non-secret fields into the production validation model.
        RemoteServerProfile(id: id, displayName: displayName, backendID: backendID, scheme: scheme, host: host, port: port, basePath: basePath, authenticationMode: authenticationMode, connectionTimeoutSeconds: connectionTimeoutSeconds, inferenceTimeoutSeconds: inferenceTimeoutSeconds, isEnabled: isEnabled, createdAt: createdAt, updatedAt: Date()) // Builds one complete non-secret profile without token data.
    } // Ends production profile conversion.

    var tokenUpdate: RemoteServerTokenUpdate { // Converts temporary secret intent into an explicit vault-only mutation.
        if authenticationMode == .none || removeExistingToken { // Handles unauthenticated mode or explicit credential deletion.
            return .remove // Removes only the exact profile's Keychain item.
        } // Ends token removal selection.
        if !tokenInput.isEmpty { // Handles new SecureField input.
            return .replace(tokenInput) // Sends the token only to the controller's vault boundary.
        } // Ends replacement selection.
        return .unchanged // Keeps an existing token without reading it into UI state.
    } // Ends explicit token mutation conversion.
} // Ends temporary server editor state.

@MainActor // Keeps SecureField state and save coordination on the SwiftUI actor.
private struct RemoteServerEditorView: View { // Presents one focused native add or edit form.
    @Environment(\.dismiss) private var dismiss // Uses native sheet dismissal for cancel and confirmed save only.
    @ObservedObject var controller: RemoteModelsController // Reads saving and notice state from the shared controller.
    @State private var draft: RemoteServerEditorDraft // Owns temporary non-secret fields and unsaved token input.
    let onSaved: () -> Void // Reports confirmed durable success to update source-list selection.

    init(controller: RemoteModelsController, initialDraft: RemoteServerEditorDraft, onSaved: @escaping () -> Void) { // Creates a focused editor from one immutable snapshot.
        self.controller = controller // Stores the shared controller reference.
        _draft = State(initialValue: initialDraft) // Installs isolated temporary form state.
        self.onSaved = onSaved // Stores the confirmed-save selection callback.
    } // Ends editor construction.

    var body: some View { // Defines the complete manual endpoint and token form.
        VStack(spacing: 0) { // Separates scrollable fields from stable trailing actions.
            HStack { // Aligns concise sheet identity.
                VStack(alignment: .leading, spacing: 4) { // Groups title and privacy guidance.
                    Text(draft.isNew ? "Add remote server" : "Edit remote server") // Names the exact profile operation.
                        .font(.title2.bold()) // Establishes focused sheet hierarchy.
                    Text("Enter the endpoint manually. No network scan is performed.") // States privacy behavior clearly.
                        .foregroundStyle(.secondary) // Keeps guidance subordinate.
                } // Ends editor heading copy.
                Spacer() // Keeps heading aligned to the leading edge.
            } // Ends editor heading layout.
            .padding(20) // Gives the native sheet header comfortable inset.
            Divider() // Separates heading from editable configuration.
            ScrollView { // Keeps the form usable at larger accessibility text sizes.
                Form { // Uses native macOS labels, focus behavior, and control geometry.
                    Section("Server") { // Groups identity and manual endpoint fields.
                        TextField("Display name", text: $draft.displayName) // Captures the concise user-facing profile name.
                        Picker("API type", selection: $draft.backendID) { // Uses typed backend values without raw strings.
                            Text("OpenAI-compatible").tag(ModelBackendID.remoteOpenAICompatible) // Offers the implemented private API adapter.
                            Text("Ollama, unavailable").tag(ModelBackendID.remoteOllama).disabled(true) // Shows reserved scope without pretending implementation.
                        } // Ends backend type selection.
                        Picker("Protocol", selection: $draft.scheme) { // Makes cleartext or encrypted transport explicit.
                            Text("HTTP").tag(RemoteServerScheme.http) // Supports loopback, LAN, and private overlay endpoints with warning.
                            Text("HTTPS").tag(RemoteServerScheme.https) // Supports encrypted endpoints.
                        } // Ends transport scheme selection.
                        TextField("Host", text: $draft.host, prompt: Text("192.168.1.50 or private-host")) // Captures a host or IP without scheme, path, or credentials.
                            .textContentType(.URL) // Gives macOS appropriate text services without auto-navigation.
                        TextField("Port", value: $draft.port, format: .number.grouping(.never)) // Captures the explicit TCP port as a numeric value.
                        TextField("Base path", text: $draft.basePath, prompt: Text("/v1")) // Captures the optional API prefix.
                        Toggle("Enabled for model routing", isOn: $draft.isEnabled) // Makes routing eligibility explicit at save time.
                    } // Ends server configuration section.
                    Section("Authentication") { // Groups explicit auth mode and ephemeral SecureField input.
                        Picker("Mode", selection: $draft.authenticationMode) { // Uses typed persisted authentication values.
                            Text("No authentication").tag(RemoteAuthenticationMode.none) // Makes an unauthenticated private server explicit.
                            Text("Bearer token").tag(RemoteAuthenticationMode.bearerToken) // Selects Keychain-backed Authorization behavior.
                        } // Ends authentication selection.
                        if draft.authenticationMode == .bearerToken { // Shows secret input only when the server requires it.
                            SecureField(draft.isNew ? "Bearer token" : "New bearer token", text: $draft.tokenInput) // Keeps unsaved credential text obscured and sheet-scoped.
                                .onChange(of: draft.tokenInput) { _, newValue in // Resolves conflicting replace and remove intent.
                                    if !newValue.isEmpty { draft.removeExistingToken = false } // Makes fresh explicit input take precedence over removal.
                                } // Ends token input intent synchronization.
                            Text(draft.isNew ? "Required for a new authenticated server. The token is stored in macOS Keychain." : "Leave empty to keep the saved Keychain token.") // Explains creation and edit behavior without revealing secret state.
                                .font(.caption) // Keeps security guidance subordinate but readable.
                                .foregroundStyle(.secondary) // Preserves hierarchy.
                            if !draft.isNew { // Offers explicit deletion only for a profile that may already own a saved token.
                                Toggle("Remove saved token", isOn: $draft.removeExistingToken) // Requires direct user intent for credential removal.
                            } // Ends existing token removal control.
                        } else { // Explains unauthenticated behavior explicitly.
                            Text("No Authorization header will be sent. Saving removes any token previously stored for this profile.") // States exact boundary behavior.
                                .font(.caption) // Keeps explanatory copy compact.
                                .foregroundStyle(.secondary) // Preserves hierarchy.
                        } // Ends authentication-specific controls.
                    } // Ends authentication section.
                    Section("Timeouts") { // Groups bounded connection and inference behavior.
                        Stepper("Connection: \(Int(draft.connectionTimeoutSeconds)) seconds", value: $draft.connectionTimeoutSeconds, in: 1...60, step: 1) // Controls API-check timeout within production bounds.
                        Stepper("Inference: \(Int(draft.inferenceTimeoutSeconds)) seconds", value: $draft.inferenceTimeoutSeconds, in: 1...3_600, step: 1) // Controls generation timeout within production bounds.
                    } // Ends timeout section.
                    if let warning = draft.profile.cleartextSecurityWarning { // Shows the live non-loopback HTTP warning before save.
                        Section("Network boundary") { // Gives security guidance a semantic form group.
                            Label(warning, systemImage: "exclamationmark.triangle.fill") // Uses text and symbol to communicate the actual risk.
                                .foregroundStyle(.orange) // Applies semantic warning color only to warning state.
                        } // Ends network boundary section.
                    } // Ends live cleartext warning.
                } // Ends native configuration form.
                .formStyle(.grouped) // Uses standard macOS grouped form rhythm.
                .padding(16) // Separates controls from sheet edges.
            } // Ends editor scrolling.
            Divider() // Separates editable fields from stable actions.
            HStack(spacing: 10) { // Places cancel and save in standard trailing order.
                Spacer() // Pushes sheet actions to the trailing edge.
                Button("Cancel") { // Closes without persistence or token mutation.
                    dismiss() // Dismisses the native sheet without changing durable state.
                } // Ends editor cancellation.
                .keyboardShortcut(.cancelAction) // Supports Escape through native sheet behavior.
                Button(controller.isSaving ? "Saving…" : "Save server") { // Uses verb-and-object copy and visible in-progress state.
                    Task { // Runs store and Keychain work without blocking the main thread.
                        let saved = await controller.save(profile: draft.profile, tokenUpdate: draft.tokenUpdate) // Applies validated non-secret and explicit secret intent.
                        if saved { // Dismisses only after both persistence boundaries confirm success.
                            onSaved() // Selects the exact durable profile in the owning source list.
                            dismiss() // Closes the sheet after confirmed complete persistence.
                        } // Ends confirmed-save dismissal.
                    } // Ends asynchronous save task.
                } // Ends server save action.
                .buttonStyle(.borderedProminent) // Gives the form's primary commit action appropriate emphasis.
                .keyboardShortcut(.defaultAction) // Supports Return through standard macOS form behavior.
                .disabled(controller.isSaving || draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) // Prevents duplicate or obviously incomplete submissions while preserving deeper validation feedback.
            } // Ends editor action row.
            .padding(16) // Provides standard sheet action inset.
        } // Ends editor sheet stack.
        .frame(minWidth: 520, idealWidth: 580, minHeight: 560, idealHeight: 650) // Keeps native form labels and security guidance readable.
    } // Ends editor view body.
} // Ends the focused remote server editor.
