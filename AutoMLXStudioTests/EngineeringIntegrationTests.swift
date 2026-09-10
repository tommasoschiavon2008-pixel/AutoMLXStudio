import CryptoKit // Fingerprints disposable fixture bytes for real optimistic edits.
import Foundation // Supplies isolated files, URLProtocol, and cancellable test tasks.
import XCTest // Asserts production builder, dispatcher, engine, and runtime behavior.
import AppKit // Renders only test-owned native views for visual layout inspection.
import SwiftUI // Hosts the production Engineering surface in an isolated native view.
@testable import AutoMLXStudio // Exposes the production integration graph to deterministic tests.

private actor IntegrationBackend: ModelInferenceBackend { // Supplies deterministic model output without MLX hardware or a network.
    nonisolated let id: ModelBackendID // Selects native remote or strict local normalization.
    private let replies: [ModelGenerationResult] // Stores the complete bounded script.
    private(set) var requests: [ModelGenerationRequest] = [] // Records actual multi-turn backend requests.
    init(id: ModelBackendID, replies: [ModelGenerationResult]) { self.id = id; self.replies = replies } // Stores immutable script configuration.
    func health(for target: ModelGenerationTarget) async -> ModelBackendHealth { ModelBackendHealth(status: .healthy, latencyMilliseconds: 0, checkedAt: Date(), serverKind: "Fixture", apiCompatible: true, discoveredModelCount: 1, conciseError: nil) } // Reports only injected deterministic availability.
    func generate(request: ModelGenerationRequest) async throws -> ModelGenerationResult { // Executes one exact scripted turn.
        try Task.checkCancellation() // Honors Stop before consuming another response.
        let index = requests.count // Captures the deterministic turn index.
        requests.append(request) // Retains the actual normalized request for correlation assertions.
        guard index < replies.count else { throw URLError(.badServerResponse) } // Fails unexpected extra turns instead of silently completing.
        return replies[index] // Returns only the scripted model result.
    } // Ends deterministic generation.
} // Ends the hardware-free inference fixture.

private actor IntegrationResources: ModelResourceManaging { // Replaces physical model loading while preserving LocalMLXBackend's production lifecycle calls.
    private(set) var prepareCount = 0 // Records exact resource-manager usage.
    func prepare(model: ModelProfile, configuration: ModelRuntimeConfiguration, onOutput: @escaping (String) -> Void) async throws -> ModelPreparation { // Simulates readiness without touching any physical model or process.
        prepareCount += 1 // Records each local preparation boundary.
        return ModelPreparation(modelID: model.id, previousModelID: nil, port: 12345, didSwitch: false, reusedExistingLoad: true, loadDurationMilliseconds: 0, launchReference: model.launchReference) // Returns deterministic existing-runtime evidence.
    } // Ends fake physical preparation.
    func markFailed(modelID: String, reason: String) async {} // Owns no physical model state to change.
    func stop() async {} // Owns no external process to terminate.
    func snapshot() async -> ModelResourceSnapshot { ModelResourceSnapshot(activeModelID: nil, activePort: nil, states: [:]) } // Returns isolated model state.
    func validateAvailability(model: ModelProfile, configuration: ModelRuntimeConfiguration) async throws {} // Declares only fixture availability.
    func dependencyStatuses(configuration: ModelRuntimeConfiguration) async -> [RuntimeDependencyStatus] { [] } // Performs no hardware or dependency probing.
} // Ends isolated resource-manager injection.

private actor IntegrationCompleter: LLMCompleting { // Replaces only the last local inference boundary with deterministic responses.
    private let replies: [String] // Stores strict model-response envelopes.
    private(set) var requests: [LLMCompletionRequest] = [] // Captures requests made by the actual LocalMLXBackend.
    init(replies: [String]) { self.replies = replies } // Stores immutable model behavior.
    func complete(_ request: LLMCompletionRequest) async throws -> String { // Executes one local text-model turn without hardware.
        let index = requests.count // Captures the actual local completion count.
        requests.append(request) // Records production local normalization.
        guard index < replies.count else { throw URLError(.badServerResponse) } // Rejects unintended extra inference calls.
        return replies[index] // Returns only deterministic model text.
    } // Ends fake local inference.
} // Ends hardware-free LocalMLXBackend completion injection.

private struct IntegrationProfileProvider: RemoteServerProfileProviding { // Supplies a credential-free profile without touching user settings or Keychain.
    let value: RemoteServerProfile // Stores one unique HTTP fixture identity.
    func profile(id: UUID) async throws -> RemoteServerProfile? { id == value.id ? value : nil } // Resolves only the fixture server.
    func token(for id: UUID) async throws -> String? { nil } // Never accesses real credentials.
} // Ends fixture profile isolation.

private final class IntegrationHTTP: URLProtocol, @unchecked Sendable { // Exercises the real HTTP backend without opening a network connection.
    private static let lock = NSLock() // Protects URLSession worker-thread access.
    private static var handlers: [String: (URLRequest) throws -> Data] = [:] // Isolates concurrently registered fixtures by unique host.
    static func install(host: String, handler: @escaping (URLRequest) throws -> Data) { lock.lock(); defer { lock.unlock() }; handlers[host] = handler } // Registers only one test-owned host.
    static func remove(host: String) { lock.lock(); defer { lock.unlock() }; handlers.removeValue(forKey: host) } // Releases only the completed fixture handler.
    override class func canInit(with request: URLRequest) -> Bool { true } // Intercepts every request in this private URLSession.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request } // Preserves exact request semantics.
    override func startLoading() { // Returns scripted HTTP bytes through the real URL loading callbacks.
        Self.lock.lock() // Resolves the host handler under the shared lock.
        let handler = Self.handlers[request.url?.host ?? ""] // Copies only this fixture's callback.
        Self.lock.unlock() // Releases shared state before running fixture assertions.
        do { // Reports deterministic HTTP success or a real URL loading failure.
            guard let handler, let url = request.url else { throw URLError(.badURL) } // Rejects requests outside the explicitly registered fixture.
            let data = try handler(request) // Lets the fixture inspect and respond to the actual request.
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])! // Supplies a valid OpenAI-compatible response envelope.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) // Delivers response metadata without cache side effects.
            client?.urlProtocol(self, didLoad: data) // Delivers only fixture-owned bytes.
            client?.urlProtocolDidFinishLoading(self) // Completes the exact intercepted request.
        } catch { client?.urlProtocol(self, didFailWithError: error) } // Preserves failures as transport evidence.
    } // Ends intercepted HTTP delivery.
    override func stopLoading() {} // Owns no socket or background worker that needs termination.
} // Ends the network-free HTTP boundary.

private final class IntegrationHTTPScript: @unchecked Sendable { // Serializes exact multi-turn HTTP fixtures and captured request bodies.
    private let lock = NSLock() // Protects script progress across URLSession callback threads.
    private let calls: [ModelToolCall?] // Stores tool proposals followed by explicit completion.
    private var bodies: [[String: Any]] = [] // Captures serialized native correlation fields.
    init(calls: [ModelToolCall?]) { self.calls = calls } // Stores the bounded reply sequence.
    func respond(_ request: URLRequest) throws -> Data { // Implements only discovery and chat-completion fixtures.
        lock.lock(); defer { lock.unlock() } // Keeps one ordered turn sequence per unique host.
        if request.url?.path == "/v1/models" { return Data(#"{"data":[{"id":"fixture-model"}]}"#.utf8) } // Proves identity without claiming unknown tool capabilities.
        var bytes = request.httpBody ?? Data() // Reads direct bodies when Foundation preserves them.
        if bytes.isEmpty, let stream = request.httpBodyStream { // Reads streamed bodies without changing application transport code.
            stream.open(); defer { stream.close() } // Owns only the provided request stream.
            var buffer = [UInt8](repeating: 0, count: 4096) // Bounds each read allocation.
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(buffer, count: count) } // Collects the already bounded request body.
        } // Ends Foundation body normalization.
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any]) // Requires actual serialized OpenAI request JSON.
        let index = bodies.count // Captures the ordered model turn.
        bodies.append(body) // Retains proof of multi-turn assistant and tool history.
        guard index < calls.count else { throw URLError(.badServerResponse) } // Rejects an unintended extra model turn.
        var message: [String: Any] = ["role": "assistant", "content": "Fixture fixed and verified."] // Supplies the explicit final candidate by default.
        if let call = calls[index] { // Encodes provider-native tool calls on scripted tool turns.
            let arguments = String(decoding: try JSONEncoder().encode(call.arguments), as: UTF8.self) // Preserves the exact JSON argument object as provider-native text.
            message = ["role": "assistant", "content": NSNull(), "tool_calls": [["id": call.id, "type": "function", "function": ["name": call.name, "arguments": arguments]]]] // Matches the OpenAI-compatible native call contract.
        } // Ends scripted native response selection.
        return try JSONSerialization.data(withJSONObject: ["model": "fixture-model", "choices": [["index": 0, "message": message, "finish_reason": calls[index] == nil ? "stop" : "tool_calls"]]]) // Returns real parseable transport bytes.
    } // Ends one scripted HTTP response.
    func capturedBodies() -> [[String: Any]] { lock.lock(); defer { lock.unlock() }; return bodies } // Returns a thread-safe request snapshot.
} // Ends the real-backend deterministic script.

@MainActor // Exercises the same main-actor composition used by AppState and SwiftUI.
final class EngineeringIntegrationTests: XCTestCase { // Runs production filesystem/process E2E in disposable directories only.
    private struct Fixture { // Owns every path created by one test.
        let container: URL // Defines the precise cleanup boundary.
        let root: URL // Defines the authorized engineering workspace.
        let workspace: EngineeringWorkspace // Runs production containment and transaction history.
        let workspaceID: UUID // Stores immutable authorization identity without an actor hop.
        let hash: String // Records the known buggy file's optimistic edit precondition.
    } // Ends disposable fixture ownership.

    func testRemoteHTTPInspectApproveEditTestVerifyThroughProductionBuilder() async throws { // Validates the entire remote protocol, builder, engine, approval, and local tool path.
        let fixture = try makeFixture() // Creates a known failing one-file project.
        defer { try? FileManager.default.removeItem(at: fixture.container) } // Removes only this test-owned fixture.
        let server = RemoteServerProfile(displayName: "Fixture Windows", host: "fixture-\(UUID().uuidString.lowercased()).test", port: 1234) // Uses an isolated host that cannot reach a physical server.
        let script = IntegrationHTTPScript(calls: normalCalls(hash: fixture.hash)) // Defines inspect, edit, test, verification read, and completion.
        IntegrationHTTP.install(host: server.host, handler: script.respond) // Installs the host-specific transport fixture.
        defer { IntegrationHTTP.remove(host: server.host) } // Releases only this fixture's handler.
        let configuration = URLSessionConfiguration.ephemeral // Avoids persisted cache and credential state.
        configuration.protocolClasses = [IntegrationHTTP.self] // Prevents real network access for all fixture requests.
        let session = URLSession(configuration: configuration) // Creates the exact test-owned URLSession.
        defer { session.invalidateAndCancel() } // Cancels only this fixture's networking owner.
        let remote = RemoteInferenceBackend(profileProvider: IntegrationProfileProvider(value: server), session: session) // Uses the production OpenAI-compatible backend.
        let discovered = try await remote.discoverModels(serverID: server.id, forceRefresh: true) // Exercises real discovery parsing before routing.
        XCTAssertEqual(discovered.first?.capabilities.support(for: .toolCalling), .unknown) // Ensures discovery does not fabricate native-tool support.
        let broker = EngineeringApprovalBroker() // Uses the production exact-ID approval mechanism.
        let builder = EngineeringSessionBuilder(backends: [remote], approvalBroker: broker, registryProvider: { self.emptyRegistry() }, remoteModelsProvider: { discovered }) // Builds the real remote graph with no local fallback candidate.
        let components = try builder.makeSession(workspace: fixture.workspace, preferredRemoteTarget: ModelGenerationTarget(backendID: .remoteOpenAICompatible, location: .remote(serverID: server.id), modelID: "fixture-model")) // Creates the same run components used by the UI.
        let running = Task { await components.engine.execute(EngineeringAgentInput(task: "Fix value.txt and prove the test passes."), plan: self.plan(fixture)) } // Starts the actual bounded multi-turn session.
        defer { running.cancel() } // Cancels only this fixture's run if an assertion helper throws.
        let editApproval = try await waitForApproval(broker) // Waits for the proposed file mutation before permitting any write.
        XCTAssertEqual(editApproval.tool, .writeFile) // Confirms inspect ran first and only the edit needs this decision.
        XCTAssertTrue(editApproval.exactCommand.contains("value.txt")) // Confirms the user can identify the exact file being changed.
        XCTAssertEqual(try String(contentsOf: fixture.root.appendingPathComponent("value.txt"), encoding: .utf8), "1\n") // Proves the file is unchanged while approval is pending.
        let allowedEdit = await broker.resolve(id: editApproval.id, decision: .allowOnce) // Grants exactly one proposed edit.
        XCTAssertTrue(allowedEdit) // Requires actual broker acceptance.
        let testApproval = try await waitForApproval(broker) // Waits for the build-script execution decision separately.
        XCTAssertEqual(testApproval.tool, .runTests) // Confirms file approval did not authorize arbitrary process execution.
        let allowedTest = await broker.resolve(id: testApproval.id, decision: .allowOnce) // Authorizes only the disposable project's make test invocation.
        XCTAssertTrue(allowedTest) // Requires exact process approval acceptance.
        let result = await running.value // Waits for the complete real runtime flow.
        try assertCompleted(result, fixture: fixture) // Verifies disk bytes, transactions, tool order, checks, and termination.
        let bodies = script.capturedBodies() // Reads evidence from actual serialized HTTP requests.
        XCTAssertEqual(bodies.count, 5) // Confirms five genuine model round trips.
        let lastMessages = try XCTUnwrap(bodies.last?["messages"] as? [[String: Any]]) // Reads the final native conversation.
        XCTAssertEqual(lastMessages.filter { $0["role"] as? String == "tool" }.compactMap { $0["tool_call_id"] as? String }, ["inspect", "edit", "test", "verify"]) // Proves exact tool-result correlation reached the remote model.
        XCTAssertEqual(lastMessages.filter { $0["tool_calls"] != nil }.count, 4) // Proves corresponding assistant tool calls were retained too.
        XCTAssertFalse(result.events.contains { $0.backendID == ModelBackendID.localMLX.rawValue }) // Proves the Mac did not become the inference backend during remote execution.
    } // Ends real-HTTP-backend deterministic Engineering E2E.

    func testLocalStrictJSONInspectEditTestVerify() async throws { // Verifies local-mode strict JSON through production routing and the real Mac tools.
        let fixture = try makeFixture() // Creates the same known buggy project used by the remote test.
        defer { try? FileManager.default.removeItem(at: fixture.container) } // Cleans only this test's isolated tree.
        let completer = IntegrationCompleter(replies: try normalCalls(hash: fixture.hash).map { try reply(call: $0, backend: .localMLX).text ?? "" }) // Replaces only the final physical model inference operation.
        let resources = IntegrationResources() // Replaces physical loading without bypassing the local backend.
        let profile = localRegistry().models[0] // Resolves the isolated compatible local fixture model.
        let configuration = ModelRuntimeConfiguration(executableDirectory: "/fixture/bin", repoPath: "/fixture/repo", requestedPort: 12345, autoSelectPort: false) // Uses inert runtime paths that the fake resource manager never opens.
        let backend = LocalMLXBackend(resourceManager: resources, completionClient: completer, modelProvider: { $0 == profile.id ? profile : nil }, configurationProvider: { configuration }) // Exercises the actual LocalMLXBackend in the complete Engineering flow.
        let broker = EngineeringApprovalBroker() // Uses real exact-command decisions.
        let builder = EngineeringSessionBuilder(backends: [backend], approvalBroker: broker, registryProvider: { self.localRegistry() }, remoteModelsProvider: { [] }) // Uses actual local assignment routing.
        let components = try builder.makeSession(workspace: fixture.workspace, preferredRemoteTarget: nil) // Builds the production local session.
        let running = Task { await components.engine.execute(EngineeringAgentInput(task: "Fix and test the fixture."), plan: self.plan(fixture)) } // Runs the bounded engine with strict JSON model replies.
        defer { running.cancel() } // Cancels only this fixture's run if an assertion helper throws.
        for _ in 0..<2 { let request = try await waitForApproval(broker); let accepted = await broker.resolve(id: request.id, decision: .allowOnce); XCTAssertTrue(accepted) } // Separately authorizes the edit and real test process.
        try assertCompleted(await running.value, fixture: fixture) // Checks the same full E2E contract as remote mode.
        let requests = await completer.requests // Reads actual LocalMLXBackend completion requests.
        XCTAssertEqual(requests.count, 5) // Confirms strict fallback remains multi-turn.
        XCTAssertTrue(requests.allSatisfy { $0.serverPort == 12345 && $0.model.id == "fixture-model" }) // Proves the exact prepared local target served every turn.
        let preparationCount = await resources.prepareCount // Resolves resource-manager evidence before XCTest's synchronous assertion.
        XCTAssertEqual(preparationCount, 5) // Proves every local turn passed through the shared lifecycle boundary.
    } // Ends deterministic local normalization E2E.

    func testDenyEditPreservesBytesAndStopsSession() async throws { // Verifies a real mutation cannot override the UI's denial.
        let fixture = try makeFixture() // Creates disposable buggy content.
        defer { try? FileManager.default.removeItem(at: fixture.container) } // Cleans only this fixture.
        let setup = try scriptedSession(fixture, calls: [normalCalls(hash: fixture.hash)[1]]) // Proposes one concrete write through the production builder.
        let running = Task { await setup.components.engine.execute(EngineeringAgentInput(task: "Propose a fix."), plan: self.plan(fixture)) } // Starts one approval-gated run.
        defer { running.cancel() } // Cancels only this fixture's run if an assertion helper throws.
        let request = try await waitForApproval(setup.broker) // Observes actual pending edit authority.
        let denied = await setup.broker.resolve(id: request.id, decision: .deny) // Denies that exact proposed edit.
        XCTAssertTrue(denied) // Confirms the decision was accepted rather than stale.
        let result = await running.value // Waits for policy termination.
        XCTAssertEqual(result.status, .permissionDenied) // Requires a distinct permission outcome.
        XCTAssertEqual(try String(contentsOf: fixture.root.appendingPathComponent("value.txt"), encoding: .utf8), "1\n") // Proves denied edits never reached disk.
        XCTAssertTrue(result.changedPaths.isEmpty) // Proves no mutation evidence was fabricated.
    } // Ends denied-edit E2E.

    func testCancellationWhileEditApprovalPendingPreservesBytes() async throws { // Verifies Stop invalidates pending edit authority.
        let fixture = try makeFixture() // Creates disposable buggy content.
        defer { try? FileManager.default.removeItem(at: fixture.container) } // Cleans only fixture-owned files.
        let setup = try scriptedSession(fixture, calls: [normalCalls(hash: fixture.hash)[1]]) // Proposes an approval-gated write.
        let running = Task { await setup.components.engine.execute(EngineeringAgentInput(task: "Wait before editing."), plan: self.plan(fixture)) } // Starts one exact run.
        defer { running.cancel() } // Cancels only this fixture's run if an assertion helper throws.
        let request = try await waitForApproval(setup.broker) // Ensures cancellation occurs at the authority boundary.
        let stoppedAt = Date() // Measures only the cancellation boundary.
        running.cancel() // Cancels only the test-owned session.
        let result = await running.value // Waits for cooperative cleanup.
        XCTAssertLessThan(Date().timeIntervalSince(stoppedAt), 2) // Prevents regression to waiting for the approval timeout.
        XCTAssertEqual(result.status, .cancelled) // Requires cancellation rather than model failure or success.
        let lateAllow = await setup.broker.resolve(id: request.id, decision: .allowOnce) // Attempts a stale decision after Stop.
        XCTAssertFalse(lateAllow) // Proves cancelled authority cannot be resurrected.
        XCTAssertEqual(try String(contentsOf: fixture.root.appendingPathComponent("value.txt"), encoding: .utf8), "1\n") // Proves cancellation did not apply the pending edit.
    } // Ends approval-boundary cancellation E2E.

    func testToolErrorCannotFabricateVerification() async throws { // Exercises real filesystem failure through the bounded loop.
        let fixture = try makeFixture() // Creates the contained workspace.
        defer { try? FileManager.default.removeItem(at: fixture.container) } // Removes only the disposable fixture.
        let missing = ModelToolCall(id: "missing", name: "read_file", arguments: ["path": .string("missing.txt")]) // Requests a nonexistent contained file.
        let setup = try scriptedSession(fixture, calls: [missing, nil]) // Lets the model finish after observing a real runtime error.
        let result = await setup.components.engine.execute(EngineeringAgentInput(task: "Inspect the missing file."), plan: plan(fixture)) // Executes the concrete failing tool.
        XCTAssertEqual(result.status, .completed) // Allows an explicit final explanation after a repairable tool error.
        XCTAssertEqual(result.verification.state, .unverified) // Prevents final model prose from inventing successful tests.
        XCTAssertTrue(result.events.contains { $0.kind == .toolFailed }) // Requires actual failure evidence.
        XCTAssertTrue(result.isPartial) // Reports missing required verification honestly.
    } // Ends real tool-error propagation.

    func testMalformedOutputFailsAfterOneRepair() async throws { // Exercises strict local parsing through the production bridge.
        let fixture = try makeFixture() // Creates a workspace even though malformed replies must never reach tools.
        defer { try? FileManager.default.removeItem(at: fixture.container) } // Cleans fixture files.
        let malformed = ModelGenerationResult(text: "not structured JSON", toolCalls: [], usage: nil, finishReason: .stop, modelID: "fixture-model", backendID: .localMLX, durationMilliseconds: 0) // Supplies an invalid strict-fallback response.
        let backend = IntegrationBackend(id: .localMLX, replies: [malformed, malformed]) // Supplies only the permitted initial and repair turns.
        let builder = EngineeringSessionBuilder(backends: [backend], approvalBroker: EngineeringApprovalBroker(), registryProvider: { self.localRegistry() }, remoteModelsProvider: { [] }) // Builds real routing and strict normalization.
        let components = try builder.makeSession(workspace: fixture.workspace, preferredRemoteTarget: nil) // Creates the concrete engine and runtime.
        let result = await components.engine.execute(EngineeringAgentInput(task: "Fix the fixture."), plan: plan(fixture)) // Executes bounded malformed-response handling.
        XCTAssertEqual(result.status, .failed) // Requires termination after the single repair allowance.
        XCTAssertEqual(result.events.filter { $0.kind == .argumentRepair }.count, 1) // Proves repair remains bounded.
        XCTAssertTrue(result.changedPaths.isEmpty) // Proves malformed output never mutated files.
    } // Ends malformed-output E2E.

    func testRepeatedRealReadTriggersLoopDetection() async throws { // Exercises repeated-action fingerprints with actual file output.
        let fixture = try makeFixture() // Creates deterministic readable content.
        defer { try? FileManager.default.removeItem(at: fixture.container) } // Cleans only this fixture.
        let calls = (0..<8).map { ModelToolCall(id: "repeat-\($0)", name: "read_file", arguments: ["path": .string("value.txt")]) } // Changes correlation IDs while preserving the repeated operation.
        let setup = try scriptedSession(fixture, calls: calls.map(Optional.some)) // Uses the production loop and real reads.
        let result = await setup.components.engine.execute(EngineeringAgentInput(task: "Inspect once."), plan: plan(fixture)) // Executes until repetition protection stops it.
        XCTAssertEqual(result.status, .loopDetected) // Requires deterministic loop termination before exhausting all turns.
        XCTAssertLessThan(result.iterationsUsed, 8) // Proves loop detection is independent from the hard ceiling.
    } // Ends real-runtime loop detection.

    func testDistinctRealToolFailuresReachExactFastIterationLimit() async throws { // Exercises the ceiling without accidentally triggering duplicate-call detection.
        let fixture = try makeFixture() // Creates contained filesystem authority.
        defer { try? FileManager.default.removeItem(at: fixture.container) } // Cleans only this fixture.
        let calls = (0..<8).map { ModelToolCall(id: "missing-\($0)", name: "read_file", arguments: ["path": .string("missing-\($0).txt")]) } // Produces distinct real filesystem failures.
        let setup = try scriptedSession(fixture, calls: calls.map(Optional.some)) // Supplies exactly the Fast model-turn budget.
        let result = await setup.components.engine.execute(EngineeringAgentInput(task: "Inspect bounded candidates."), plan: plan(fixture)) // Runs the real loop to its hard ceiling.
        XCTAssertEqual(result.status, .iterationLimit) // Requires explicit bounded termination.
        XCTAssertEqual(result.iterationsUsed, 8) // Verifies the exact Fast budget.
        XCTAssertEqual(result.verification.state, .unverified) // Prevents failed reads from becoming verification evidence.
    } // Ends exact-limit E2E.

    func testAppStateOwnsStableControllersAcrossNavigation() { // Verifies root ownership without launching model inference.
        let app = AppState(startsBackgroundTasks: false) // Skips asynchronous workspace and hardware bootstrap.
        let engineering = app.engineeringController // Resolves the app-owned Engineering controller once.
        let remote = app.remoteModelsController // Resolves the shared configuration controller once.
        app.selection = .engineering // Selects the real Engineering case.
        engineering.taskText = "Preserve this draft." // Stores input in its long-lived owner.
        app.selection = .remoteModels // Follows the configuration link's destination.
        app.selection = .engineering // Returns through normal root navigation.
        XCTAssertTrue(app.engineeringController === engineering) // Proves navigation does not duplicate session ownership.
        XCTAssertTrue(app.remoteModelsController === remote) // Proves configuration and Engineering share remote state.
        XCTAssertEqual(engineering.taskText, "Preserve this draft.") // Proves input survives navigation.
        XCTAssertTrue(SidebarItem.allCases.contains(.remoteModels)) // Proves Remote Models is in the sidebar.
        XCTAssertTrue(SidebarItem.allCases.contains(.engineering)) // Proves Engineering is in the sidebar.
    } // Ends app-state navigation ownership coverage.

    func testControllerPreservesActiveAndCompletedStateOnPageReload() async throws { // Verifies live progress and page re-entry with actual controller execution.
        let fixture = try makeFixture() // Creates a disposable project.
        defer { try? FileManager.default.removeItem(at: fixture.container) } // Cleans only this test's tree.
        let backend = IntegrationBackend(id: .localMLX, replies: try normalCalls(hash: fixture.hash).map { try reply(call: $0, backend: .localMLX) }) // Supplies fake model inference only.
        let broker = EngineeringApprovalBroker() // Uses real approval decisions.
        let builder = EngineeringSessionBuilder(backends: [backend], approvalBroker: broker, registryProvider: { self.localRegistry() }, remoteModelsProvider: { [] }) // Uses production routing and engine assembly.
        let controller = EngineeringController(workspaceStore: EngineeringWorkspaceStore(catalogURL: fixture.container.appendingPathComponent("workspaces.json")), memoryStore: ProjectMemoryStore(rootURL: fixture.container.appendingPathComponent("memory")), sessionBuilder: builder, approvalBroker: broker) // Isolates controller persistence from user settings.
        await controller.authorizeWorkspace(directoryURL: fixture.root) // Uses the folder picker's real authorization path.
        let workspaceID = controller.selectedWorkspaceID // Records submitted filesystem authority.
        controller.taskText = "Fix and verify the original task." // Sets the submitted objective.
        controller.quality = .fast // Excludes optional quality models from this deterministic fixture.
        controller.run() // Starts the controller-owned session.
        defer { controller.stop() } // Cancels only this fixture's controller on early failure.
        let edit = try await waitForApproval(broker) // Suspends at an actual proposed mutation.
        await controller.loadWorkspaces() // Simulates the page task while running.
        await controller.selectWorkspace(id: UUID()) // Attempts an invalid workspace switch while running.
        XCTAssertTrue(controller.isRunning) // Proves page entry did not destroy the run.
        XCTAssertEqual(controller.selectedWorkspaceID, workspaceID) // Proves authority stayed unchanged.
        for _ in 0..<100 { if controller.activity.contains(where: { $0.kind == .toolRequested }) { break }; try await Task.sleep(nanoseconds: 10_000_000) } // Waits for asynchronous main-actor progress delivery.
        XCTAssertTrue(controller.activity.contains { $0.kind == .toolRequested }) // Requires live tool progress before terminal completion.
        controller.quality = .thorough // Simulates another state writer changing the draft policy.
        controller.taskText = "A later draft must not replace the running objective." // Challenges input immutability.
        _ = await broker.resolve(id: edit.id, decision: .allowOnce) // Allows only the submitted edit.
        let test = try await waitForApproval(broker) // Observes separate process approval.
        _ = await broker.resolve(id: test.id, decision: .allowOnce) // Allows only the fixture test.
        for _ in 0..<500 { if !controller.isRunning { break }; try await Task.sleep(nanoseconds: 10_000_000) } // Bounds completion observation to five seconds.
        XCTAssertFalse(controller.isRunning) // Requires ownership release.
        let result = try XCTUnwrap(controller.result) // Requires a retained terminal result.
        XCTAssertEqual(result.status, .completed) // Requires successful real runtime completion.
        XCTAssertEqual(result.maximumIterations, 8) // Proves the submitted Fast ceiling survived draft mutation.
        XCTAssertFalse(result.events.contains { $0.kind == .reviewerStarted || $0.kind == .composerStarted }) // Proves the active session did not acquire later quality stages.
        await controller.loadWorkspaces() // Simulates returning to Engineering after completion.
        XCTAssertEqual(controller.result?.sessionID, result.sessionID) // Proves the completed result survives page entry.
        XCTAssertFalse(controller.changes.isEmpty) // Requires retained transaction history.
        let requests = await backend.requests // Reads actual normalized model requests.
        XCTAssertTrue(requests.first?.messages.contains { $0.content.contains("original task") } == true) // Proves inference received the submitted objective.
    } // Ends controller lifetime, snapshot, and live-progress coverage.

    func testNewMutationInvalidatesOlderVerification() async throws { // Prevents stale green checks from validating newer file bytes.
        let fixture = try makeFixture() // Creates disposable source files.
        defer { try? FileManager.default.removeItem(at: fixture.container) } // Cleans only this fixture.
        let calls: [ModelToolCall?] = [ModelToolCall(id: "early-test", name: "run_tests", arguments: ["executable": .string("true"), "arguments": .array([]), "workingDirectory": .string(""), "timeoutMilliseconds": .number(1000)]), normalCalls(hash: fixture.hash)[1], nil] // Runs a successful process before, but never after, the mutation.
        let setup = try scriptedSession(fixture, calls: calls) // Uses production verification bookkeeping.
        let running = Task { await setup.components.engine.execute(EngineeringAgentInput(task: "Edit after the earlier check."), plan: self.plan(fixture)) } // Starts the stale-evidence challenge.
        defer { running.cancel() } // Cleans exact test-owned work if a helper throws.
        let approval = try await waitForApproval(setup.broker) // Waits for the edit after the safe early process.
        _ = await setup.broker.resolve(id: approval.id, decision: .allowOnce) // Allows only the subsequent mutation.
        let result = await running.value // Waits for explicit completion.
        XCTAssertEqual(result.status, .completed) // Separates completion from verification.
        XCTAssertEqual(result.verification.state, .unverified) // Requires fresh checks after edits.
        XCTAssertTrue(result.isPartial) // Exposes missing current verification honestly.
    } // Ends verification freshness coverage.

    func testEngineeringNativeLayoutRendersAtMinimumDetailSize() async throws { // Produces a test-owned native view image without capturing the user's desktop.
        let fixture = try makeFixture() // Supplies isolated controller storage.
        defer { try? FileManager.default.removeItem(at: fixture.container) } // Cleans only the fixture project.
        let app = AppState(startsBackgroundTasks: false) // Supplies read-only environment state without background bootstrap.
        let broker = EngineeringApprovalBroker() // Supplies an idle approval source.
        let builder = EngineeringSessionBuilder(backends: [], approvalBroker: broker, registryProvider: { self.emptyRegistry() }, remoteModelsProvider: { [] }) // Avoids all inference during UI rendering.
        let controller = EngineeringController(workspaceStore: EngineeringWorkspaceStore(catalogURL: fixture.container.appendingPathComponent("catalog.json")), memoryStore: ProjectMemoryStore(rootURL: fixture.container.appendingPathComponent("memory")), sessionBuilder: builder, approvalBroker: broker) // Isolates UI persistence.
        controller.prefersRemoteModel = true // Exercises the larger empty remote configuration form.
        let store = RemoteServerStore(fileURL: fixture.container.appendingPathComponent("servers.json")) // Isolates server metadata from user configuration.
        let remote = RemoteModelsController(store: store, inferenceService: RemoteInferenceBackend(profileProvider: store)) // Supplies an empty real configuration controller without network requests.
        let view = NSHostingView(rootView: EngineeringView(controller: controller, remoteController: remote).environmentObject(app)) // Hosts only the app's Engineering surface.
        view.frame = NSRect(x: 0, y: 0, width: 850, height: 686) // Matches the minimum app window's approximate detail area.
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false) // Creates an offscreen test-owned native rendering context.
        window.isReleasedWhenClosed = false // Keeps native ownership explicit during teardown.
        window.contentView = view // Attaches the real SwiftUI hierarchy for native control rendering.
        defer { window.close() } // Releases only the test-owned offscreen window.
        await Task.yield() // Allows initial SwiftUI publication without waiting on external state.
        view.layoutSubtreeIfNeeded() // Resolves native layout at the fixed detail size.
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds)) // Requires a renderable native backing image.
        view.cacheDisplay(in: view.bounds, to: bitmap) // Captures only this test-owned view, not the desktop.
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:])) // Encodes the native layout for manual visual QA.
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("AutoMLXStudioV06EngineeringLayout.png")) // Writes a disposable validation artifact outside user documents.
        XCTAssertGreaterThan(bitmap.pixelsWide, 0) // Requires actual rendered pixels rather than a fabricated snapshot.
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0) // Requires actual rendered geometry.
    } // Ends native layout rendering smoke coverage.

    private func makeFixture() throws -> Fixture { // Creates every deterministic project dependency under one disposable root.
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("AutoMLXIntegration-\(UUID().uuidString)", isDirectory: true) // Allocates a unique test-owned cleanup boundary.
        let root = container.appendingPathComponent("workspace", isDirectory: true) // Separates authorized files from transaction history.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) // Creates only the disposable workspace.
        try "1\n".write(to: root.appendingPathComponent("value.txt"), atomically: true, encoding: .utf8) // Installs the intentional one-byte logic error.
        try "2\n".write(to: root.appendingPathComponent("expected.txt"), atomically: true, encoding: .utf8) // Installs the independent expected output.
        try "test:\n\t/usr/bin/cmp value.txt expected.txt\n".write(to: root.appendingPathComponent("Makefile"), atomically: true, encoding: .utf8) // Runs a real deterministic check without dependencies, downloads, or hardware.
        let workspaceID = UUID() // Allocates the exact fixture authorization identity.
        let workspace = try EngineeringWorkspace(rootURL: root, workspaceID: workspaceID, historyDirectoryURL: container.appendingPathComponent("history")) // Uses production canonical containment and transaction storage.
        let hash = SHA256.hash(data: Data("1\n".utf8)).map { String(format: "%02x", $0) }.joined() // Records the exact pre-edit bytes.
        return Fixture(container: container, root: root, workspace: workspace, workspaceID: workspaceID, hash: hash) // Returns only fixture-owned state.
    } // Ends fixture construction.

    private func normalCalls(hash: String) -> [ModelToolCall?] { // Defines the mandatory inspect, edit, test, verify, complete sequence.
        [ModelToolCall(id: "inspect", name: "read_file", arguments: ["path": .string("value.txt")]), ModelToolCall(id: "edit", name: "write_file", arguments: ["path": .string("value.txt"), "content": .string("2\n"), "expectedSHA256": .string(hash)]), ModelToolCall(id: "test", name: "run_tests", arguments: ["executable": .string("make"), "arguments": .array([.string("test")]), "workingDirectory": .string(""), "timeoutMilliseconds": .number(5_000), "reason": .string("Verify the fixture fix")]), ModelToolCall(id: "verify", name: "read_file", arguments: ["path": .string("value.txt")]), nil] // Uses exact production tool schemas and a real test process.
    } // Ends the deterministic engineering script.

    private func reply(call: ModelToolCall?, backend: ModelBackendID = .remoteOpenAICompatible) throws -> ModelGenerationResult { // Converts one script step into the selected model protocol.
        var text = "Fixture fixed and verified." // Supplies the explicit terminal candidate.
        if backend == .localMLX { // Encodes the real strict fallback envelope for local text-only models.
            let object: [String: Any] // Holds one complete strict JSON object.
            if let call { object = ["type": "tool_call", "id": call.id, "name": call.name, "arguments": try JSONSerialization.jsonObject(with: JSONEncoder().encode(call.arguments))] } else { object = ["type": "complete", "summary": text] } // Preserves exact tool and completion envelope schemas.
            text = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) // Produces standalone bounded JSON rather than Markdown.
        } // Ends local reply normalization.
        return ModelGenerationResult(text: call == nil || backend == .localMLX ? text : nil, toolCalls: backend == .localMLX ? [] : call.map { [$0] } ?? [], usage: nil, finishReason: .stop, modelID: "fixture-model", backendID: backend, durationMilliseconds: 0) // Supplies deterministic typed inference evidence.
    } // Ends fixture response generation.

    private func scriptedSession(_ fixture: Fixture, calls: [ModelToolCall?]) throws -> (components: EngineeringSessionComponents, broker: EngineeringApprovalBroker) { // Builds remote-mode production integration around fake inference only.
        let backend = IntegrationBackend(id: .remoteOpenAICompatible, replies: try calls.map { try reply(call: $0) }) // Supplies the bounded native tool script.
        let serverID = UUID() // Isolates target identity across tests.
        let model = RemoteDiscoveredModel(id: "fixture-model", serverID: serverID, backendID: .remoteOpenAICompatible, availability: .available, capabilities: ModelCapabilityProfile()) // Preserves discovery's unknown capabilities.
        let broker = EngineeringApprovalBroker() // Uses real allow-once and deny behavior.
        let builder = EngineeringSessionBuilder(backends: [backend], approvalBroker: broker, registryProvider: { self.emptyRegistry() }, remoteModelsProvider: { [model] }) // Uses the real builder and existing router.
        return (try builder.makeSession(workspace: fixture.workspace, preferredRemoteTarget: ModelGenerationTarget(backendID: .remoteOpenAICompatible, location: .remote(serverID: serverID), modelID: model.id)), broker) // Returns exact actors for execution and authority decisions.
    } // Ends deterministic production-graph assembly.

    private func waitForApproval(_ broker: EngineeringApprovalBroker) async throws -> EngineeringApprovalRequest { // Waits for state rather than assuming scheduler timing.
        for _ in 0..<500 { if let request = await broker.pendingRequest() { return request }; try await Task.sleep(nanoseconds: 10_000_000) } // Bounds approval observation to five seconds.
        XCTFail("Expected an exact pending approval within five seconds.") // Reports an actionable failure instead of hanging the suite.
        throw URLError(.timedOut) // Ends the failing fixture wait.
    } // Ends bounded approval observation.

    private func plan(_ fixture: Fixture) -> EngineeringExecutionPlan { EngineeringExecutionPlan(workspaceID: fixture.workspaceID, workspaceName: "Disposable fixture", quality: .fast, allowedToolNames: Set(EngineeringToolRuntime.definitions.map { $0.name.rawValue }), reviewerEnabled: false, composerEnabled: false, verificationExpected: true) } // Disables optional quality models while retaining exact tool and iteration policy.
    private func emptyRegistry() -> ModelRegistry { ModelRegistry(models: [], assignments: [], legacyFallbackModelID: "") } // Prevents accidental real local inference or filesystem model inspection.
    private func localRegistry() -> ModelRegistry { // Creates one explicit compatible installed logical fixture without inspecting real model folders.
        let profile = ModelProfile(id: "fixture-model", displayName: "Fixture", repositoryID: "fixture-model", localPath: nil, backend: .mlxLM, capabilities: [.general, .coding, .reasoning], approximateDiskGB: nil, approximateMemoryGB: nil, enabled: true, installationState: .installed, runtimeState: .unloaded, isLegacyFallback: false, statusDetail: nil) // Declares only the fake model's deterministic test capabilities.
        let assignment = ModelAssignment(agentID: AgentID.engineering, preferredModelID: profile.id, preferredCapability: .coding, fallbackModelIDs: [], fallbackCapabilities: [.coding], allowsRuntimeReuse: true) // Prevents undeclared fallback to any real model.
        return ModelRegistry(models: [profile], assignments: [assignment], legacyFallbackModelID: "") // Returns an isolated assignment snapshot.
    } // Ends local routing fixture construction.

    private func assertCompleted(_ result: EngineeringAgentSessionResult, fixture: Fixture) throws { // Applies the same required E2E assertions to both inference modes.
        XCTAssertEqual(result.status, .completed, result.failureSummary ?? "") // Requires actual explicit completion.
        XCTAssertEqual(result.iterationsUsed, 5) // Verifies inspect, edit, test, verify, and completion consumed five model turns.
        XCTAssertEqual(result.events.filter { $0.kind == .toolRequested }.compactMap(\.toolName), ["read_file", "write_file", "run_tests", "read_file"]) // Requires exact concrete tool order.
        XCTAssertEqual(result.changedPaths, ["value.txt"]) // Proves only the authorized bug file was changed.
        XCTAssertEqual(result.verification.state, .verified) // Requires real test-process evidence.
        XCTAssertTrue(result.events.contains { $0.toolName == "run_tests" && $0.exitCode == 0 && $0.succeeded == true }) // Requires an actual successful process exit.
        XCTAssertEqual(result.finalSummary, "Fixture fixed and verified.") // Requires the explicit final candidate.
        XCTAssertFalse(result.isPartial) // Requires verified, complete termination.
        XCTAssertEqual(try String(contentsOf: fixture.root.appendingPathComponent("value.txt"), encoding: .utf8), "2\n") // Verifies actual filesystem mutation independently from model and tool prose.
        XCTAssertEqual(try String(contentsOf: fixture.root.appendingPathComponent("expected.txt"), encoding: .utf8), "2\n") // Verifies the independent expected output was preserved.
    } // Ends complete-flow evidence assertions.
} // Ends deterministic V0.6 Engineering integration coverage.
