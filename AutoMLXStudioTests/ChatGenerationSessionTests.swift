import Foundation // Supplies deterministic URLs, dates, UUIDs, and task cancellation for Chat integration tests.
import AppKit // Supplies test-owned native windows and bitmap rendering for Chat layout validation.
import SwiftUI // Supplies NSHostingView composition for the real Chat surface.
import XCTest // Supplies the permanent deterministic macOS test harness.
@testable import AutoMLXStudio // Exposes internal Chat session, persistence, and catalog contracts.

private enum ChatSessionBackendBehavior: Sendable { // Scripts one deterministic backend outcome without model, network, or package dependencies.
    case success(text: String?, toolCalls: [ModelToolCall], usage: ModelGenerationUsage?, duration: Int) // Returns one normalized successful transport response.
    case failure // Throws one adapter-classified operational failure.
    case waitForCancellation // Suspends until the owning Chat task is cancelled.
} // Ends scripted Chat backend behavior.

private struct ChatSessionMockFailure: Error, ModelBackendFailureClassifying, Sendable { // Supplies a safe fixed error for dispatcher normalization tests.
    let modelBackendFailureDisposition: ModelBackendFailureDisposition = .terminal // Prevents any silent fallback from the exact Chat target.
    let modelBackendSafeSummary = "Scripted remote HTTP 500 failure." // Supplies bounded redacted operational evidence.
} // Ends classified Chat test failure.

private actor ChatSessionBackend: ModelInferenceBackend { // Records normalized requests and returns one deterministic scripted outcome.
    nonisolated let id: ModelBackendID // Exposes the exact adapter identity without an actor hop.
    private let behavior: ChatSessionBackendBehavior // Stores immutable behavior for every invocation.
    private var requests: [ModelGenerationRequest] = [] // Records exact request order and contents for assertions.

    init(id: ModelBackendID, behavior: ChatSessionBackendBehavior) { // Creates one local or remote fake adapter.
        self.id = id // Stores the backend identity used by dispatcher lookup.
        self.behavior = behavior // Stores the selected deterministic outcome.
    } // Ends fake backend construction.

    func health(for target: ModelGenerationTarget) async -> ModelBackendHealth { // Satisfies the backend contract without network work.
        ModelBackendHealth(status: .healthy, latencyMilliseconds: 1, checkedAt: Date(timeIntervalSince1970: 0), serverKind: "Chat Test", apiCompatible: true, discoveredModelCount: 1, conciseError: nil) // Returns fixed evidence.
    } // Ends fake health observation.

    func generate(request: ModelGenerationRequest) async throws -> ModelGenerationResult { // Records and executes the scripted behavior.
        requests.append(request) // Proves the shared dispatcher reached the exact registered adapter.
        switch behavior { // Selects the deterministic result.
        case .success(let text, let toolCalls, let usage, let duration): return ModelGenerationResult(text: text, toolCalls: toolCalls, usage: usage, finishReason: toolCalls.isEmpty ? .stop : .toolCalls, modelID: request.target.modelID, backendID: id, durationMilliseconds: duration) // Returns provider-neutral success with exact provenance.
        case .failure: throw ChatSessionMockFailure() // Returns the fixed classified safe failure.
        case .waitForCancellation: try await Task.sleep(for: .seconds(30)); throw ChatSessionMockFailure() // Lets cancellation interrupt the suspension before any artificial completion.
        } // Ends behavior selection.
    } // Ends scripted generation.

    func capturedRequests() -> [ModelGenerationRequest] { requests } // Returns an immutable actor-isolated request snapshot.
} // Ends recording Chat backend.

private struct ChatRemoteModelsService: RemoteModelsServicing { // Supplies deterministic remote catalog and health observations for native Chat rendering.
    let model: RemoteDiscoveredModel // Stores the exact collision-safe model returned by discovery.

    func health(for target: ModelGenerationTarget) async -> ModelBackendHealth { // Returns an explicit usable observation without contacting a server.
        ModelBackendHealth(status: .healthy, latencyMilliseconds: 7, checkedAt: Date(timeIntervalSince1970: 0), serverKind: "UI Fixture", apiCompatible: true, discoveredModelCount: 1, conciseError: nil) // Supplies honest simulated-software evidence only.
    } // Ends deterministic health observation.

    func discoverModels(serverID: UUID, forceRefresh: Bool) async throws -> [RemoteDiscoveredModel] { // Returns one known model for the requested fixture server.
        model.serverID == serverID ? [model] : [] // Prevents a fixture model from appearing under any other server identity.
    } // Ends deterministic catalog discovery.
} // Ends isolated remote-models UI service.

final class ChatGenerationSessionTests: XCTestCase { // Verifies local/remote routing, selection, persistence, history, cancellation, and safe failures.
    private let serverA = UUID(uuidString: "10000000-0000-0000-0000-000000000001")! // Supplies one stable remote server identity.
    private let serverB = UUID(uuidString: "20000000-0000-0000-0000-000000000002")! // Supplies a second stable collision test identity.

    func testEngineeringPromptRequiresSmallestObservableVerifiedChange() throws { // Locks the generalized physical-fixture lesson without naming one harness or expected expression.
        let prompt = try XCTUnwrap(AgentRegistry().agent(id: AgentID.engineering)?.systemPrompt.lowercased()) // Reads the centralized production Engineering instruction.
        XCTAssertTrue(prompt.contains("smallest correct change")) // Requires minimal-change guidance.
        XCTAssertTrue(prompt.contains("observable requested behavior")) // Requires behavior rather than cosmetic equivalence.
        XCTAssertTrue(prompt.contains("do not substitute")) // Requires exact expected-result discipline.
        XCTAssertTrue(prompt.contains("verify after edits")) // Requires post-edit operational verification.
        XCTAssertTrue(prompt.contains("inspect failures")) // Requires evidence inspection before changing course.
        XCTAssertTrue(prompt.contains("avoid unnecessary changes")) // Requires bounded scope discipline.
    } // Ends Engineering prompt regression test.

    func testRemoteTextUsesDispatcherAndPreservesExactMultiTurnOrderAndMetadata() async throws { // Proves system plus user/assistant/user structure with no duplicated current turn.
        let usage = ModelGenerationUsage(inputTokens: 12, outputTokens: 5, totalTokens: 17) // Supplies exact provider-reported accounting.
        let backend = ChatSessionBackend(id: .remoteOpenAICompatible, behavior: .success(text: "second answer", toolCalls: [], usage: usage, duration: 43)) // Creates one successful remote adapter.
        let session = try makeSession(backend) // Builds the production dispatcher path around the fake adapter.
        let target = remoteTarget(serverID: serverA, modelID: "shared-name") // Selects one exact backend, server, and model tuple.
        let prior = [ChatMessage(role: "user", content: "first question"), ChatMessage(role: "assistant", content: "first answer")] // Supplies two visible prior turns.
        let output = try await session.generate(target: target, priorMessages: prior, currentUserText: "second question", projectID: nil, usesProjectMemory: false, contextLimits: .balanced) // Executes ordinary remote Chat.
        let requests = await backend.capturedRequests() // Reads the exact backend input.
        XCTAssertEqual(requests.count, 1) // Confirms one dispatcher attempt and no fallback.
        XCTAssertEqual(requests[0].messages.map(\.role), [.user, .assistant, .user]) // Confirms exact multi-turn role order.
        XCTAssertEqual(requests[0].messages.map(\.content), ["first question", "first answer", "second question"]) // Confirms the current user request appears once.
        XCTAssertTrue(requests[0].tools.isEmpty) // Confirms normal Chat advertises no Engineering tools.
        XCTAssertEqual(output.text, "second answer") // Confirms visible content propagation.
        XCTAssertEqual(output.metadata.target, target) // Confirms backend-qualified target identity survives execution.
        XCTAssertEqual(output.metadata.usage, usage) // Confirms provider usage preservation.
        XCTAssertEqual(output.metadata.durationMilliseconds, 43) // Confirms backend duration preservation.
        XCTAssertNil(output.metadata.timeToFirstTokenMilliseconds) // Confirms non-streaming Chat does not invent TTFT.
    } // Ends remote multi-turn integration test.

    func testLocalTextUsesSameDispatcherContract() async throws { // Proves local text no longer bypasses the backend-neutral Chat session.
        let backend = ChatSessionBackend(id: .localMLX, behavior: .success(text: "local answer", toolCalls: [], usage: nil, duration: 9)) // Creates one successful local adapter.
        let session = try makeSession(backend) // Builds the same session used by the remote test.
        let target = ModelGenerationTarget(backendID: .localMLX, location: .local, modelID: "local-model") // Selects one exact local target.
        let output = try await session.generate(target: target, priorMessages: [], currentUserText: "hello", projectID: nil, usesProjectMemory: false, contextLimits: .balanced) // Executes local text through the dispatcher.
        let capturedTarget = await backend.capturedRequests().first?.target // Reads actor-isolated evidence before entering XCTest's synchronous autoclosure.
        XCTAssertEqual(capturedTarget, target) // Confirms exact local dispatch.
        XCTAssertEqual(output.text, "local answer") // Confirms normalized local text propagation.
    } // Ends local shared-dispatcher test.

    func testSwitchingLocalRemoteAndBackRoutesEveryNewTurnWithoutLosingHistory() async throws { // Proves both backend-switch directions use the newly selected exact target while retaining prior turns.
        let local = ChatSessionBackend(id: .localMLX, behavior: .success(text: "local response", toolCalls: [], usage: nil, duration: 3)) // Records both local generations.
        let remote = ChatSessionBackend(id: .remoteOpenAICompatible, behavior: .success(text: "remote response", toolCalls: [], usage: nil, duration: 4)) // Records the middle remote generation.
        let registry = try ModelBackendRegistry(backends: [local, remote]) // Registers both production-shaped adapter identities once.
        let root = temporaryDirectory("switching") // Creates an isolated unused Project Memory root.
        defer { try? FileManager.default.removeItem(at: root) } // Cleans only the exact test-owned root.
        let session = ChatGenerationSession(dispatcher: ModelBackendDispatcher(registry: registry), memoryStore: ProjectMemoryStore(rootURL: root), systemInstructions: "System instruction") // Builds the real shared Chat routing layer.
        let localTarget = ModelGenerationTarget(backendID: .localMLX, location: .local, modelID: "shared-model-name") // Uses a model ID that deliberately collides with the remote provider ID.
        let remoteTarget = remoteTarget(serverID: serverA, modelID: "shared-model-name") // Qualifies the same model ID by remote server.
        let history = [ChatMessage(role: "user", content: "remember cedar"), ChatMessage(role: "assistant", content: "I will remember cedar")] // Supplies the same durable conversation history to every newly selected backend.
        _ = try await session.generate(target: localTarget, priorMessages: history, currentUserText: "first local turn", projectID: nil, usesProjectMemory: false, contextLimits: .balanced) // Routes Local before switching.
        _ = try await session.generate(target: remoteTarget, priorMessages: history, currentUserText: "remote turn", projectID: nil, usesProjectMemory: false, contextLimits: .balanced) // Routes Local → Remote.
        _ = try await session.generate(target: localTarget, priorMessages: history, currentUserText: "second local turn", projectID: nil, usesProjectMemory: false, contextLimits: .balanced) // Routes Remote → Local.
        let localRequests = await local.capturedRequests() // Reads both exact local dispatcher inputs.
        let remoteRequests = await remote.capturedRequests() // Reads the exact remote dispatcher input.
        XCTAssertEqual(localRequests.map(\.target), [localTarget, localTarget]) // Confirms no stale remote adapter remains pinned after switching back.
        XCTAssertEqual(remoteRequests.map(\.target), [remoteTarget]) // Confirms the middle generation uses only the selected remote server/model tuple.
        XCTAssertTrue((localRequests + remoteRequests).allSatisfy { Array($0.messages.prefix(2)).map(\.content) == history.map(\.content) }) // Confirms switching never clears or rewrites prior conversation history.
        XCTAssertEqual(localRequests.map { $0.messages.last?.content }, ["first local turn", "second local turn"]) // Confirms each local current turn appears once.
        XCTAssertEqual(remoteRequests.first?.messages.last?.content, "remote turn") // Confirms the remote current turn appears once.
    } // Ends bidirectional backend-switching test.

    func testNormalChatRejectsToolCallsWithoutExecution() async throws { // Proves unexpected remote native tools cannot cross into Engineering runtime.
        let call = ModelToolCall(id: "call-1", name: "write_file", arguments: ["path": .string("unsafe")]) // Supplies one normalized provider tool request.
        let backend = ChatSessionBackend(id: .remoteOpenAICompatible, behavior: .success(text: nil, toolCalls: [call], usage: nil, duration: 4)) // Returns the tool call from a remote adapter.
        let session = try makeSession(backend) // Builds ordinary Chat with no tool runtime dependency.
        do { _ = try await session.generate(target: remoteTarget(serverID: serverA, modelID: "tools"), priorMessages: [], currentUserText: "change a file", projectID: nil, usesProjectMemory: false, contextLimits: .balanced); XCTFail("Tool calls must not be accepted by normal Chat.") } // Executes the boundary and fails if it returns success.
        catch let error as ChatGenerationSessionError { XCTAssertEqual(error, .toolCallsUnsupported(1)) } // Confirms explicit no-execution handling.
    } // Ends normal Chat tool-call safety test.

    func testClassifiedBackendFailureKeepsSafeOperationalSummary() async throws { // Proves an HTTP-like backend failure remains actionable without response content.
        let backend = ChatSessionBackend(id: .remoteOpenAICompatible, behavior: .failure) // Creates one classified remote failure.
        let session = try makeSession(backend) // Builds the real dispatcher failure path.
        do { _ = try await session.generate(target: remoteTarget(serverID: serverA, modelID: "broken"), priorMessages: [], currentUserText: "hello", projectID: nil, usesProjectMemory: false, contextLimits: .balanced); XCTFail("The scripted failure must propagate.") } // Executes the failure path.
        catch let error as ChatGenerationSessionError { XCTAssertEqual(error, .backendFailure("Scripted remote HTTP 500 failure.")) } // Confirms safe adapter evidence reaches Chat.
    } // Ends safe failure normalization test.

    func testCancellationStopsRemoteSession() async throws { // Proves Stop cancels an in-flight remote adapter and does not wait for fallback.
        let backend = ChatSessionBackend(id: .remoteOpenAICompatible, behavior: .waitForCancellation) // Creates one long-running cancellable adapter.
        let session = try makeSession(backend) // Builds the exact remote dispatcher path.
        let task = Task { try await session.generate(target: remoteTarget(serverID: serverA, modelID: "slow"), priorMessages: [], currentUserText: "wait", projectID: nil, usesProjectMemory: false, contextLimits: .balanced) } // Starts one owned generation.
        while await backend.capturedRequests().isEmpty { await Task.yield() } // Waits only until the fake backend proves execution began.
        task.cancel() // Applies the same cooperative cancellation used by AppState Stop.
        do { _ = try await task.value; XCTFail("Cancelled generation must not return a response.") } // Awaits terminal cancellation.
        catch is CancellationError { } // Confirms cancellation remains distinct from offline or failed state.
    } // Ends remote cancellation test.

    func testCatalogKeepsCollidingRemoteModelNamesDistinctAndPreservesSavedUnknownTarget() { // Proves picker identity includes backend, server, and model.
        let profileA = remoteProfile(id: serverA, name: "Windows A", enabled: true) // Creates the first configured server.
        let profileB = remoteProfile(id: serverB, name: "Windows B", enabled: true) // Creates the second configured server.
        let capabilities = ModelCapabilityProfile(values: [.text: .supported]) // Supplies discovered text capability evidence.
        let modelA = RemoteDiscoveredModel(id: "same-model", serverID: serverA, backendID: .remoteOpenAICompatible, availability: .available, capabilities: capabilities) // Discovers the same provider name on server A.
        let modelB = RemoteDiscoveredModel(id: "same-model", serverID: serverB, backendID: .remoteOpenAICompatible, availability: .available, capabilities: capabilities) // Discovers the same provider name on server B.
        let choices = ChatModelCatalog.choices(localModels: [], remoteProfiles: [profileA, profileB], remoteModelsByServerID: [serverA: [modelA], serverB: [modelB]], preserving: nil) // Builds grouped remote choices.
        XCTAssertEqual(Set(choices.map(\.id)).count, 2) // Confirms equal model strings remain distinct target identities.
        let saved = remoteTarget(serverID: serverA, modelID: "saved-before-discovery") // Creates an exact persisted selection restored at launch.
        let restored = ChatModelCatalog.choices(localModels: [], remoteProfiles: [profileA], remoteModelsByServerID: [:], preserving: saved) // Builds catalog before any live network discovery.
        XCTAssertEqual(restored.first?.target, saved) // Confirms restart does not lose the exact saved target.
        XCTAssertEqual(restored.first?.state, .unknown) // Confirms missing discovery remains honest unknown, not false availability.
    } // Ends catalog identity and restart preservation test.

    func testCatalogRetainsDisabledSelectionButRejectsRemovedOrMissingDiscoveredModel() { // Covers disabled server, removal, and successful-discovery omission states.
        let saved = remoteTarget(serverID: serverA, modelID: "saved") // Creates one persisted remote selection.
        let disabled = ChatModelCatalog.choices(localModels: [], remoteProfiles: [remoteProfile(id: serverA, name: "Disabled", enabled: false)], remoteModelsByServerID: [:], preserving: saved) // Restores it against disabled configuration.
        XCTAssertFalse(disabled[0].isSelectable) // Confirms the selection remains visible but cannot generate.
        let missing = ChatModelCatalog.choices(localModels: [], remoteProfiles: [remoteProfile(id: serverA, name: "Enabled", enabled: true)], remoteModelsByServerID: [serverA: []], preserving: saved) // Represents a completed discovery that omitted the model.
        XCTAssertFalse(missing[0].isSelectable) // Confirms missing-model evidence blocks generation.
        XCTAssertTrue(ChatModelCatalog.choices(localModels: [], remoteProfiles: [], remoteModelsByServerID: [:], preserving: saved).isEmpty) // Confirms a removed server cannot be resolved or silently replaced.
    } // Ends invalid remote selection tests.

    func testSelectionPersistsAcrossStoreRestartAndIdentitySafeAppendDoesNotChangeVisibleConversation() async throws { // Covers restart persistence and stale-response destination safety together.
        let root = temporaryDirectory("conversation") // Creates one isolated app-owned persistence root.
        let memoryRoot = temporaryDirectory("memory") // Creates an independent Project Memory root.
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: memoryRoot) } // Cleans only exact test-owned directories.
        let target = remoteTarget(serverID: serverA, modelID: "persisted") // Creates the selection expected after restart.
        let store = ConversationStore(rootURL: root) // Creates the first persistence actor.
        let first = try await store.createConversation(id: UUID(), title: "First", selectedModelTarget: target, now: Date(timeIntervalSince1970: 1)) // Persists selection on the originating conversation.
        let second = try await store.createConversation(id: UUID(), title: "Second", now: Date(timeIntervalSince1970: 2)) // Persists a newer visible destination.
        let restarted = ConversationStore(rootURL: root) // Simulates application restart with a fresh actor instance.
        let restoredTarget = try await restarted.conversation(id: first.id).selectedModelTarget // Reads actor-isolated persistence before XCTest comparison.
        XCTAssertEqual(restoredTarget, target) // Confirms exact backend/server/model persistence.
        let workspace = await MainActor.run { WorkspaceController(memoryStore: ProjectMemoryStore(rootURL: memoryRoot), conversationStore: restarted) } // Builds UI coordination on the restarted stores.
        await workspace.load() // Selects the newest second conversation.
        let visibleConversationID = await MainActor.run { workspace.selectedConversationID } // Reads the main-actor selection before XCTest comparison.
        XCTAssertEqual(visibleConversationID, second.id) // Confirms the second conversation is visible.
        try await workspace.appendMessage(ChatMessage(role: "assistant", content: "late first response"), to: first.id) // Simulates a response arriving after navigation.
        let visibleMessagesAreEmpty = await MainActor.run { workspace.messages.isEmpty } // Reads visible transcript state outside XCTest's autoclosure.
        XCTAssertTrue(visibleMessagesAreEmpty) // Confirms the late response never appears in the wrong visible transcript.
        let persistedLateResponse = try await restarted.conversation(id: first.id).messages.last?.content // Reads the exact durable origin conversation.
        XCTAssertEqual(persistedLateResponse, "late first response") // Confirms it was durably committed to the originating identity.
    } // Ends persistence and stale destination test.

    @MainActor
    func testChatNativeLayoutRendersAtNormalAndMinimumDetailSizesWithLongState() async throws { // Validates real Chat hierarchy, long names, error state, metadata, and conversation depth without desktop capture.
        let root = temporaryDirectory("layout") // Creates one isolated root for both app-owned test stores.
        defer { try? FileManager.default.removeItem(at: root) } // Cleans only the exact test-owned persistence root.
        let target = ModelGenerationTarget(backendID: .localMLX, location: .local, modelID: "fixture/very-long-local-model-identifier-for-clipping-validation") // Supplies a deliberately long exact local target.
        let usage = ModelGenerationUsage(inputTokens: 1_234, outputTokens: 567, totalTokens: 1_801) // Supplies visible truthful numeric metadata.
        let metadata = ChatGenerationMetadata(target: target, usage: usage, durationMilliseconds: 98_765, finishReason: .stop, toolCallCount: 0, timeToFirstTokenMilliseconds: nil) // Exercises non-streaming duration and usage presentation.
        let messages = [ // Builds a long conversation with complete and failed terminal states.
            ChatMessage(role: "user", content: String(repeating: "A long user request for wrapping and transcript scrolling. ", count: 10)), // Exercises long selectable user content.
            ChatMessage(role: "assistant", content: String(repeating: "A long completed response for readable wrapping and scrolling. ", count: 12), modelID: target.modelID, generationMetadata: metadata), // Exercises complete metadata and long assistant content.
            ChatMessage(role: "user", content: "Trigger the controlled error presentation."), // Adds another multi-turn user row.
            ChatMessage(role: "assistant", content: "The selected remote-style fixture response is intentionally unavailable for this visual state.", generationStatus: .failed) // Exercises explicit failed labeling without starting inference.
        ] // Ends visible layout fixture messages.
        let conversationStore = ConversationStore(rootURL: root.appendingPathComponent("conversations", isDirectory: true)) // Isolates durable Chat state from the user's Application Support data.
        _ = try await conversationStore.createConversation(title: "A deliberately long conversation title that verifies minimum-width truncation", messages: messages, selectedModelTarget: target) // Persists a complete selected layout fixture.
        let workspace = WorkspaceController(memoryStore: ProjectMemoryStore(rootURL: root.appendingPathComponent("memory", isDirectory: true)), conversationStore: conversationStore) // Builds isolated UI coordination.
        await workspace.load() // Publishes the exact fixture conversation for ChatView.
        let app = AppState(startsBackgroundTasks: false, workspace: workspace) // Prevents hardware, network, and default workspace bootstrap during rendering.
        let profile = ModelProfile(id: target.modelID, displayName: "Very Long Local Model Display Name for Clipping and Accessibility Validation", repositoryID: target.modelID, localPath: nil, backend: .mlxLM, capabilities: [.general, .reasoning], approximateDiskGB: nil, approximateMemoryGB: nil, enabled: true, installationState: .installed, runtimeState: .unloaded, isLegacyFallback: true, statusDetail: nil) // Supplies one deterministic usable local choice without filesystem inspection.
        let assignment = ModelAssignment(agentID: AgentID.general, preferredModelID: profile.id, preferredCapability: .general, fallbackModelIDs: [], fallbackCapabilities: [.general], allowsRuntimeReuse: true) // Makes the exact fixture model the deterministic Chat migration default.
        app.modelRegistry = ModelRegistry(models: [profile], assignments: [assignment], legacyFallbackModelID: profile.id) // Replaces user-derived registry state only in this isolated AppState instance.
        try renderChat(app: app, size: NSSize(width: 1_180, height: 760), outputName: "AutoMLXStudioV0601ChatNormal.png") // Validates normal detail geometry.
        try renderChat(app: app, size: NSSize(width: 850, height: 686), outputName: "AutoMLXStudioV0601ChatMinimum.png") // Validates the established minimum app detail geometry.
    } // Ends native Chat layout rendering test.

    @MainActor
    func testChatNativeLayoutRendersRemoteEmptyErrorAndGeneratingStates() async throws { // Validates the remote selector, server identity, failure state, disabled controls, and visible Stop action without network access.
        let root = temporaryDirectory("remote-layout") // Creates one isolated root for conversation, remote profile, and session state.
        defer { try? FileManager.default.removeItem(at: root) } // Cleans only the exact test-owned root.
        let profile = remoteProfile(id: serverA, name: "Windows Engineering Server with a Deliberately Long Display Name", enabled: true) // Supplies a long configured server label without assuming LM Studio.
        let target = remoteTarget(serverID: serverA, modelID: "provider/very-long-remote-model-name-for-chat-validation") // Supplies the exact backend, server, and provider model identity.
        let discovered = RemoteDiscoveredModel(id: target.modelID, serverID: serverA, backendID: .remoteOpenAICompatible, availability: .available, capabilities: ModelCapabilityProfile(values: [.text: .supported])) // Marks only text support as explicitly discovered.
        let conversationStore = ConversationStore(rootURL: root.appendingPathComponent("conversations", isDirectory: true)) // Isolates durable Chat state.
        _ = try await conversationStore.createConversation(title: "Remote Chat UI validation", selectedModelTarget: target) // Starts with an empty remote-selected conversation.
        let workspace = WorkspaceController(memoryStore: ProjectMemoryStore(rootURL: root.appendingPathComponent("memory", isDirectory: true)), conversationStore: conversationStore) // Builds isolated UI coordination.
        await workspace.load() // Publishes the empty selected conversation.
        let remoteStore = RemoteServerStore(fileURL: root.appendingPathComponent("RemoteServers.json", isDirectory: false)) // Prevents reads or writes to the user's configured server store.
        try await remoteStore.save(profile) // Persists only the non-secret fixture profile in the isolated root.
        let remoteController = RemoteModelsController(store: remoteStore, inferenceService: ChatRemoteModelsService(model: discovered)) // Uses deterministic health and discovery with no URLSession request.
        await remoteController.load() // Publishes the configured server.
        await remoteController.refreshModels(serverID: serverA) // Publishes the exact selectable remote model.
        let app = AppState(startsBackgroundTasks: false, workspace: workspace) // Prevents production background startup.
        app.remoteModelsController = remoteController // Replaces the lazy production controller before ChatView reads the remote catalog.
        try renderChat(app: app, size: NSSize(width: 1_180, height: 760), outputName: "AutoMLXStudioV0601ChatRemoteEmpty.png") // Captures empty Chat with server-grouped remote selection.

        app.chatGenerationSession = try makeSession(ChatSessionBackend(id: .remoteOpenAICompatible, behavior: .failure)) // Routes one request through a deterministic classified remote error.
        await app.sendChat("Trigger a controlled remote HTTP failure.") // Produces the real failed terminal message and restores composer availability.
        try renderChat(app: app, size: NSSize(width: 1_180, height: 760), outputName: "AutoMLXStudioV0601ChatRemoteError.png") // Captures bounded failure presentation with the remote target retained.

        let waitingBackend = ChatSessionBackend(id: .remoteOpenAICompatible, behavior: .waitForCancellation) // Creates one cooperative in-flight remote generation.
        app.chatGenerationSession = try makeSession(waitingBackend) // Installs the waiting backend behind the real dispatcher session.
        let generation = Task { await app.sendChat("Keep this remote response in progress until Stop is exercised.") } // Starts the actual AppState ownership and cancellation path.
        while await waitingBackend.capturedRequests().isEmpty { await Task.yield() } // Waits only for proof that dispatcher routing began.
        XCTAssertTrue(app.isGenerating) // Confirms the view must display generating controls.
        try renderChat(app: app, size: NSSize(width: 1_180, height: 760), outputName: "AutoMLXStudioV0601ChatRemoteGenerating.png") // Captures Stop, disabled selector, and in-progress remote status.
        app.cancelGeneration() // Exercises the exact UI action's underlying ownership boundary.
        await generation.value // Waits for cooperative cancellation and state cleanup.
        XCTAssertFalse(app.isGenerating) // Confirms the composer is unlocked after Stop.
        app.chatGenerationSession = try makeSession(ChatSessionBackend(id: .remoteOpenAICompatible, behavior: .success(text: "Remote recovery succeeded.", toolCalls: [], usage: nil, duration: 5))) // Supplies one clean request after cancellation.
        await app.sendChat("Verify remote recovery after Stop.") // Reuses the same persisted remote selection and conversation history.
        XCTAssertEqual(app.chatMessages.last?.content, "Remote recovery succeeded.") // Confirms the next remote request completes normally.
        XCTAssertEqual(app.chatMessages.last?.generationStatus, .complete) // Confirms cancellation left no corrupt terminal state.
        XCTAssertEqual(app.chatMessages.last?.generationMetadata?.target, target) // Confirms recovery did not silently substitute another backend or model.
    } // Ends remote native Chat state rendering test.

    private func makeSession(_ backend: any ModelInferenceBackend) throws -> ChatGenerationSession { // Builds a production-shaped session around one deterministic adapter.
        let root = temporaryDirectory("session") // Creates an isolated unused Project Memory root.
        addTeardownBlock { try? FileManager.default.removeItem(at: root) } // Cleans only the exact test-owned directory after each test.
        let registry = try ModelBackendRegistry(backends: [backend]) // Registers the exact fake backend under production validation.
        return ChatGenerationSession(dispatcher: ModelBackendDispatcher(registry: registry), memoryStore: ProjectMemoryStore(rootURL: root), systemInstructions: "System instruction") // Returns the real session with no external dependencies.
    } // Ends session fixture construction.

    private func remoteTarget(serverID: UUID, modelID: String) -> ModelGenerationTarget { // Creates one exact OpenAI-compatible remote target.
        ModelGenerationTarget(backendID: .remoteOpenAICompatible, location: .remote(serverID: serverID), modelID: modelID) // Preserves all three collision-prevention identity fields.
    } // Ends remote target fixture.

    private func remoteProfile(id: UUID, name: String, enabled: Bool) -> RemoteServerProfile { // Creates one valid non-secret server configuration without network use.
        RemoteServerProfile(id: id, displayName: name, backendID: .remoteOpenAICompatible, scheme: .http, host: "192.0.2.10", port: 1234, basePath: "/v1", authenticationMode: .none, isEnabled: enabled) // Uses the documentation-only TEST-NET address and no token.
    } // Ends remote profile fixture.

    private func temporaryDirectory(_ component: String) -> URL { // Creates a unique test-owned filesystem location.
        FileManager.default.temporaryDirectory.appendingPathComponent("AutoMLXStudio-Chat-\(component)-\(UUID().uuidString)", isDirectory: true) // Avoids shared state and broad cleanup paths.
    } // Ends isolated temporary root construction.

    @MainActor
    private func renderChat(app: AppState, size: NSSize, outputName: String) throws { // Renders only a test-owned Chat view into deterministic evidence pixels.
        let view = NSHostingView(rootView: ChatView().environmentObject(app)) // Hosts the real production Chat surface with isolated application state.
        view.frame = NSRect(origin: .zero, size: size) // Applies the exact normal or minimum validation size.
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false) // Creates an offscreen native rendering context without desktop capture.
        window.isReleasedWhenClosed = false // Keeps ownership explicit through bitmap encoding.
        window.contentView = view // Attaches the complete SwiftUI hierarchy to native layout.
        defer { window.close() } // Releases only this test-owned offscreen window.
        view.layoutSubtreeIfNeeded() // Resolves two-row header, transcript, sidebar, metadata, and composer geometry.
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds)) // Requires a real renderable backing image.
        view.cacheDisplay(in: view.bounds, to: bitmap) // Captures only the test view pixels.
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:])) // Encodes lossless layout evidence.
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent(outputName), options: .atomic) // Writes a disposable artifact for the validation evidence copy.
        let scale = window.backingScaleFactor // Preserves the distinction between logical layout points and Retina backing pixels.
        XCTAssertEqual(bitmap.pixelsWide, Int(size.width * scale)) // Confirms the requested logical width rendered without an empty fallback.
        XCTAssertEqual(bitmap.pixelsHigh, Int(size.height * scale)) // Confirms the requested logical height rendered without an empty fallback.
    } // Ends test-owned Chat rendering helper.
} // Ends Chat generation session integration tests.
