import Foundation // Supplies URL loading stubs, temporary storage, JSON inspection, and synchronization primitives.
import XCTest // Supplies deterministic asynchronous assertions for the V0.6 remote inference foundation.
@testable import AutoMLXStudio // Exposes internal backend, profile, token, and response contracts to permanent tests.

private final class RecordingRemoteTokenVault: RemoteServerTokenVault, @unchecked Sendable { // Provides an in-memory secret boundary without touching the user's Keychain.
    private let lock = NSLock() // Serializes test credential access across URLSession and XCTest threads.
    private var values: [UUID: String] = [:] // Stores test-only token values by exact server identifier.

    func token(for serverID: UUID) throws -> String? { // Implements the injectable read boundary.
        lock.lock() // Begins exclusive access to test credential state.
        defer { lock.unlock() } // Releases the lock on every return path.
        return values[serverID] // Returns only the exact server's test token.
    } // Ends test token lookup.

    func setToken(_ token: String?, for serverID: UUID) throws { // Implements add, replacement, and removal for deterministic tests.
        lock.lock() // Begins exclusive access to test credential state.
        defer { lock.unlock() } // Releases the lock on every mutation path.
        values[serverID] = token // Stores a non-nil value or removes the key through dictionary nil assignment.
    } // Ends test token mutation.

    func storedToken(for serverID: UUID) -> String? { // Lets persistence tests verify cleanup without going through a removed profile.
        lock.lock() // Begins exclusive access to test credential state.
        defer { lock.unlock() } // Releases the lock on return.
        return values[serverID] // Returns the exact in-memory test value.
    } // Ends direct test-only token inspection.
} // Ends the injectable test token vault.

private final class RemoteURLProtocolStub: URLProtocol, @unchecked Sendable { // Provides deterministic offline HTTP responses for discovery and generation tests.
    struct StubResponse { // Describes one complete mock transport outcome.
        let statusCode: Int // Supplies the mock HTTP status.
        let headers: [String: String] // Supplies response headers used by compatibility and server-kind checks.
        let data: Data // Supplies the exact mock response bytes.
        let error: Error? // Supplies an optional URL loading failure instead of an HTTP response.

        init(statusCode: Int = 200, headers: [String: String] = ["Content-Type": "application/json"], data: Data = Data(), error: Error? = nil) { // Creates one concise deterministic transport outcome.
            self.statusCode = statusCode // Stores the mock HTTP status.
            self.headers = headers // Stores the mock response headers.
            self.data = data // Stores the mock body bytes.
            self.error = error // Stores the optional transport error.
        } // Ends mock response construction.
    } // Ends the mock response value.

    typealias Handler = (URLRequest) throws -> StubResponse // Defines a request-aware synchronous mock response factory.
    private static let stateLock = NSLock() // Serializes shared handler and request-log state.
    private static var handler: Handler? // Stores the current test's exact mock behavior.
    private static var capturedRequests: [URLRequest] = [] // Records requests for boundary and payload assertions.

    static func configure(_ handler: @escaping Handler) { // Installs one isolated handler and clears earlier request observations.
        stateLock.lock() // Begins exclusive shared-stub mutation.
        self.handler = handler // Stores the new deterministic response factory.
        capturedRequests = [] // Prevents request leakage across tests.
        stateLock.unlock() // Ends exclusive shared-stub mutation.
    } // Ends stub configuration.

    static func reset() { // Removes all test behavior and observations after each test.
        stateLock.lock() // Begins exclusive shared-stub mutation.
        handler = nil // Removes the prior response factory.
        capturedRequests = [] // Removes potentially sensitive test request data.
        stateLock.unlock() // Ends exclusive shared-stub mutation.
    } // Ends shared stub reset.

    static func requests() -> [URLRequest] { // Returns a stable copy of all observed requests.
        stateLock.lock() // Begins exclusive shared-stub access.
        defer { stateLock.unlock() } // Releases the shared lock on return.
        return capturedRequests // Returns value-semantic request snapshots.
    } // Ends request-log retrieval.

    private static func snapshotIncludingBody(_ request: URLRequest) -> URLRequest { // Preserves a provider payload even when URLSession presents it to URLProtocol as a body stream.
        guard request.httpBody == nil, let stream = request.httpBodyStream else { return request } // Reuses ordinary requests whose bytes are already directly available.
        stream.open() // Opens only the in-memory request stream supplied to this deterministic test protocol.
        defer { stream.close() } // Balances the exact stream open operation on every exit path.
        var bytes = Data() // Accumulates the bounded test request body for assertions after completion.
        var buffer = [UInt8](repeating: 0, count: 4_096) // Allocates one small reusable read buffer.
        while stream.hasBytesAvailable { // Reads until URLSession's finite request-body stream reaches its end.
            let count = stream.read(&buffer, maxLength: buffer.count) // Pulls one bounded chunk without interpreting provider JSON.
            guard count > 0 else { break } // Stops on EOF or an unavailable stream rather than spinning.
            bytes.append(buffer, count: count) // Appends exactly the bytes observed at the transport boundary.
        } // Ends complete request-stream capture.
        var snapshot = request // Copies URL, method, and headers without mutating the live loading request.
        snapshot.httpBodyStream = nil // Removes the consumed stream only from the retained assertion snapshot.
        snapshot.httpBody = bytes // Makes the exact captured provider payload available to the test assertions.
        return snapshot // Returns a stable request value whose secret-bearing header remains test-local.
    } // Ends deterministic request-body snapshotting.

    override class func canInit(with request: URLRequest) -> Bool { // Claims all requests in the injected ephemeral URLSession only.
        true // Routes every injected test request through this deterministic stub.
    } // Ends URL loading selection.

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { // Preserves the exact request for payload assertions.
        request // Returns the original value without normalization side effects.
    } // Ends request canonicalization.

    override func startLoading() { // Delivers one configured deterministic mock outcome.
        let selectedHandler: Handler? // Holds a synchronized snapshot of current test behavior.
        Self.stateLock.lock() // Begins exclusive shared-stub access.
        Self.capturedRequests.append(Self.snapshotIncludingBody(request)) // Records the complete request, including URLSession-streamed provider bytes, for post-generation assertions.
        selectedHandler = Self.handler // Copies the handler before releasing shared state.
        Self.stateLock.unlock() // Ends exclusive shared-stub access.
        guard let selectedHandler else { // Requires every test to install explicit behavior.
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)) // Fails deterministically instead of hanging.
            return // Stops without producing an HTTP response.
        } // Ends missing-handler protection.
        do { // Converts the configured outcome into URLProtocol callbacks.
            let stub = try selectedHandler(request) // Evaluates request-specific test behavior.
            if let error = stub.error { // Handles an injected transport failure.
                client?.urlProtocol(self, didFailWithError: error) // Delivers the stable error through URLSession.
                return // Stops without delivering response bytes.
            } // Ends injected transport-error handling.
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: stub.headers) else { // Constructs an actual HTTP response for production validation logic.
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)) // Fails if the test response itself is invalid.
                return // Stops without ambiguous callbacks.
            } // Ends mock HTTP response construction.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) // Delivers response metadata without caching.
            client?.urlProtocol(self, didLoad: stub.data) // Delivers the exact configured response bytes.
            client?.urlProtocolDidFinishLoading(self) // Completes the URL loading contract.
        } catch { // Handles a request-aware test handler error.
            client?.urlProtocol(self, didFailWithError: error) // Delivers the injected error through normal URLSession behavior.
        } // Ends mock outcome delivery.
    } // Ends deterministic loading.

    override func stopLoading() { // Supports URLSession cancellation without additional callbacks.
    } // Ends URL loading cancellation.
} // Ends deterministic HTTP protocol stub.

private final class NeverCompletingRemoteURLProtocol: URLProtocol, @unchecked Sendable { // Holds a request open so task cancellation can be tested without timing a real server.
    override class func canInit(with request: URLRequest) -> Bool { // Claims all requests in its dedicated ephemeral session.
        true // Routes the cancellation test through this never-completing protocol.
    } // Ends cancellation protocol selection.

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { // Preserves the request without changing cancellation behavior.
        request // Returns the original request.
    } // Ends cancellation request canonicalization.

    override func startLoading() { // Intentionally leaves loading pending until URLSession cancels it.
    } // Ends pending-load start.

    override func stopLoading() { // Lets URLSession finish its cancellation path without delivering data.
    } // Ends pending-load cancellation.
} // Ends the never-completing cancellation protocol.

final class RemoteInferenceBackendTests: XCTestCase { // Verifies multi-server persistence, discovery, generation, tool calls, redaction, and network failure semantics.
    override func tearDown() { // Clears process-wide URLProtocol state after every deterministic test.
        RemoteURLProtocolStub.reset() // Removes captured requests and handler closures.
        super.tearDown() // Preserves XCTest teardown behavior.
    } // Ends test cleanup.

    func testProfileBuildsCredentialFreeURLAndWarnsOnlyForRemoteCleartext() throws { // Verifies manual endpoint normalization and the explicit LAN HTTP warning.
        let profile = makeProfile(host: "192.168.1.50") // Creates a representative private-LAN OpenAI-compatible profile.
        XCTAssertEqual(try profile.validated().baseURL().absoluteString, "http://192.168.1.50:1234/v1") // Confirms deterministic credential-free URL construction.
        XCTAssertNotNil(profile.cleartextSecurityWarning) // Confirms unencrypted non-loopback traffic receives a visible warning.
        let loopback = makeProfile(host: "127.0.0.1") // Creates an explicit local-machine server profile.
        XCTAssertNil(loopback.cleartextSecurityWarning) // Confirms loopback HTTP is not mislabeled as crossing the machine boundary.
        var invalid = profile // Copies the valid value for isolated host validation.
        invalid.host = "http://user:secret@example.test/v1" // Supplies forbidden scheme, credentials, and path syntax.
        XCTAssertThrowsError(try invalid.validated()) { error in // Verifies malformed host configuration is rejected before networking.
            XCTAssertEqual(error as? RemoteServerConfigurationError, .invalidHost) // Confirms the bounded typed configuration failure.
        } // Ends invalid-host assertion.
    } // Ends profile URL and security warning testing.

    func testStorePersistsMultipleProfilesWithoutPersistingTokenAndRemovesKeychainEntry() async throws { // Verifies multi-profile JSON durability and secret separation.
        let environment = makeTemporaryEnvironment() // Creates one exact disposable persistence directory and in-memory vault.
        let first = makeProfile(id: UUID(), displayName: "Alpha Mac", host: "localhost") // Creates the first independent server profile.
        let second = makeProfile(id: UUID(), displayName: "Beta PC", host: "100.64.0.8", authenticationMode: .bearerToken) // Creates a second private-overlay profile requiring auth.
        let secret = "server-secret-value-123456" // Supplies a recognizable test credential for leakage detection.
        let store = RemoteServerStore(fileURL: environment.fileURL, tokenVault: environment.vault) // Creates the production actor against disposable boundaries.
        try await store.save(second) // Persists the second profile first to test stable sorting independently from insertion order.
        try await store.save(first) // Persists the first profile.
        try await store.setToken(secret, for: second.id) // Stores the credential through the injected secret boundary.
        let profiles = try await store.allProfiles() // Reads the stable multi-server view.
        XCTAssertEqual(profiles.map(\.displayName), ["Alpha Mac", "Beta PC"]) // Confirms deterministic display ordering without singleton assumptions.
        let persistedText = try String(contentsOf: environment.fileURL, encoding: .utf8) // Reads only the disposable non-secret JSON document.
        XCTAssertFalse(persistedText.contains(secret)) // Proves the bearer token never entered profile JSON.
        let reloaded = RemoteServerStore(fileURL: environment.fileURL, tokenVault: environment.vault) // Creates a fresh actor to exercise real decode rather than memory cache.
        let reloadedProfiles = try await reloaded.allProfiles() // Loads profiles from the durable JSON in the fresh actor.
        XCTAssertEqual(reloadedProfiles.count, 2) // Confirms both profiles survive durable reload.
        let reloadedToken = try await reloaded.token(for: second.id) // Reads the second profile's token through the network boundary.
        XCTAssertEqual(reloadedToken, secret) // Confirms the backend boundary can retrieve the injected vault token.
        try await reloaded.remove(id: second.id) // Removes one profile through the production coordinated cleanup path.
        XCTAssertNil(environment.vault.storedToken(for: second.id)) // Confirms profile removal also clears its exact Keychain-equivalent item.
        let remainingProfiles = try await reloaded.allProfiles() // Reads the store after exact removal.
        XCTAssertEqual(remainingProfiles.map(\.id), [first.id]) // Confirms the other configured server remains intact.
    } // Ends multi-server persistence and secret-isolation testing.

    func testDiscoveryMapsOnlyTrustworthyMetadataAndCachesPerServer() async throws { // Verifies OpenAI model discovery, unknown capabilities, and conservative cache reuse.
        let setup = try await makeBackend() // Creates one enabled unauthenticated server with an offline stub session.
        RemoteURLProtocolStub.configure { request in // Installs a deterministic model-list response.
            XCTAssertEqual(request.url?.path, "/v1/models") // Confirms endpoint composition from configured base path.
            return .init(headers: ["Content-Type": "application/json", "Server": "llama.cpp"], data: try Self.jsonData(["object": "list", "data": [["id": "qwen-coder"], ["id": "reviewer-model"], ["id": "qwen-coder"]]])) // Returns two unique models plus one duplicate.
        } // Ends discovery stub configuration.
        let first = try await setup.backend.discoverModels(serverID: setup.profile.id) // Performs the live API discovery.
        let second = try await setup.backend.discoverModels(serverID: setup.profile.id) // Reuses the fresh conservative cache.
        XCTAssertEqual(first.map(\.id), ["qwen-coder", "reviewer-model"]) // Confirms stable provider order and duplicate elimination.
        XCTAssertEqual(second, first) // Confirms cached normalization is value-stable.
        XCTAssertEqual(first.first?.serverID, setup.profile.id) // Confirms every model retains its owning server identity.
        XCTAssertEqual(first.first?.backendID, .remoteOpenAICompatible) // Confirms typed backend identity is retained.
        XCTAssertEqual(first.first?.capabilities.support(for: .toolCalling), .unknown) // Confirms discovery does not invent tool-calling support.
        XCTAssertEqual(RemoteURLProtocolStub.requests().count, 1) // Confirms a second normal lookup does not hammer the server.
        _ = try await setup.backend.discoverModels(serverID: setup.profile.id, forceRefresh: true) // Performs an explicit user-driven refresh.
        XCTAssertEqual(RemoteURLProtocolStub.requests().count, 2) // Confirms force refresh performs exactly one new request.
    } // Ends remote discovery and cache testing.

    func testHealthRequiresCompatibleModelsAPIAndReportsSelectedModelAbsenceAsDegraded() async throws { // Verifies connection testing is API-level rather than TCP-level.
        let setup = try await makeBackend() // Creates one deterministic server/backend pair.
        RemoteURLProtocolStub.configure { _ in // Installs a compatible discovery response missing the selected target model.
            .init(headers: ["Content-Type": "application/json", "x-lmstudio-version": "0.3"], data: try Self.jsonData(["data": [["id": "different-model"]]])) // Returns a valid LM Studio-style listing.
        } // Ends compatible health stub configuration.
        let health = await setup.backend.health(for: makeTarget(profile: setup.profile, modelID: "qwen-coder")) // Performs a live API health observation.
        XCTAssertEqual(health.status, .degraded) // Confirms a compatible server missing the selected model is not marked fully healthy.
        XCTAssertTrue(health.apiCompatible) // Confirms the models endpoint itself passed structural validation.
        XCTAssertEqual(health.discoveredModelCount, 1) // Confirms the actual discovered count is retained.
        XCTAssertEqual(health.serverKind, "LM Studio") // Confirms conservative header-based server-family detection.
        XCTAssertNotNil(health.latencyMilliseconds) // Confirms live API latency is measured.
    } // Ends API-level health testing.

    func testHealthRejectsUnrelatedHTMLServiceEvenWhenHTTPReturnsSuccess() async throws { // Proves an open socket or arbitrary web page never becomes a healthy inference server.
        let setup = try await makeBackend() // Creates one deterministic server/backend pair.
        RemoteURLProtocolStub.configure { _ in // Installs an unrelated successful HTML response.
            .init(headers: ["Content-Type": "text/html"], data: Data("<html>hello</html>".utf8)) // Simulates a reachable non-inference web server.
        } // Ends incompatible health stub configuration.
        let health = await setup.backend.health(for: makeTarget(profile: setup.profile)) // Performs the actual production compatibility check.
        XCTAssertEqual(health.status, .degraded) // Confirms reachability without API compatibility is degraded rather than healthy.
        XCTAssertFalse(health.apiCompatible) // Confirms usable inference compatibility remains false.
        XCTAssertNil(health.discoveredModelCount) // Confirms no model count is invented from unrelated HTML.
    } // Ends false-positive health prevention testing.

    func testTextGenerationBuildsAuthOnlyAtNetworkBoundaryAndNormalizesUsage() async throws { // Verifies request encoding, bearer isolation, response decoding, and duration metadata.
        let secret = "private-bearer-987654321" // Supplies a distinctive credential for leakage assertions.
        let setup = try await makeBackend(authenticationMode: .bearerToken, token: secret) // Creates an authenticated deterministic backend.
        RemoteURLProtocolStub.configure { request in // Installs a successful standard chat completion response.
            XCTAssertEqual(request.url?.path, "/v1/chat/completions") // Confirms exact generation endpoint construction.
            return .init(data: try Self.jsonData(["model": "qwen-coder-loaded", "choices": [["message": ["content": "Implemented safely."], "finish_reason": "stop"]], "usage": ["prompt_tokens": 12, "completion_tokens": 4, "total_tokens": 16]])) // Returns normalized text and usage metadata.
        } // Ends generation stub configuration.
        let request = ModelGenerationRequest(target: makeTarget(profile: setup.profile), systemInstructions: "You are the coding specialist.", messages: [ModelGenerationMessage(role: .user, content: "Inspect the workspace.")], temperature: 0.2, maxOutputTokens: 256, stopSequences: ["<END>"]) // Creates a backend-neutral request containing no credential field.
        XCTAssertFalse(request.debugDescription.contains(secret)) // Confirms safe request diagnostics cannot reveal a server token.
        let result = try await setup.backend.generate(request: request) // Executes the production OpenAI-compatible adapter against the stub.
        XCTAssertEqual(result.text, "Implemented safely.") // Confirms normalized assistant text.
        XCTAssertEqual(result.toolCalls, []) // Confirms absent native calls remain an empty collection.
        XCTAssertEqual(result.modelID, "qwen-coder-loaded") // Confirms actual provider model identity is retained when present.
        XCTAssertEqual(result.backendID, .remoteOpenAICompatible) // Confirms typed backend trace metadata.
        XCTAssertEqual(result.finishReason, .stop) // Confirms provider finish reason normalization.
        XCTAssertEqual(result.usage, ModelGenerationUsage(inputTokens: 12, outputTokens: 4, totalTokens: 16)) // Confirms token accounting is mapped without recomputation.
        XCTAssertGreaterThanOrEqual(result.durationMilliseconds, 0) // Confirms monotonic duration measurement is non-negative.
        let sent = try XCTUnwrap(RemoteURLProtocolStub.requests().last) // Reads the exact network-boundary request.
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer \(secret)") // Confirms Keychain material is applied only to the HTTP header.
        let body = try XCTUnwrap(sent.httpBody) // Reads the provider JSON payload for field-level validation.
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(secret)) // Confirms the token never enters provider request JSON.
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any]) // Decodes the captured provider payload for supported-option assertions.
        XCTAssertEqual(object["stream"] as? Bool, false) // Confirms this backend does not pretend to stream.
        XCTAssertEqual(object["max_tokens"] as? Int, 256) // Confirms the explicit output bound is forwarded.
        XCTAssertNil(object["api_key"]) // Confirms no credential-shaped provider field is serialized.
    } // Ends authenticated text generation testing.

    func testNativeToolCallIsStrictlyDecodedWithoutExecutingIt() async throws { // Verifies real OpenAI-compatible function calling normalizes only JSON-object arguments.
        let setup = try await makeBackend() // Creates one deterministic unauthenticated backend.
        RemoteURLProtocolStub.configure { _ in // Installs a native tool-call completion.
            let arguments = "{\"path\":\"Sources/AppState.swift\",\"line\":12}" // Creates the provider's JSON-encoded argument string.
            let function: [String: Any] = ["name": "read_file", "arguments": arguments] // Builds the provider function object explicitly.
            let call: [String: Any] = ["id": "call_1", "type": "function", "function": function] // Builds one provider-native call object.
            let message: [String: Any] = ["content": NSNull(), "tool_calls": [call]] // Builds an assistant message containing the native call.
            let choice: [String: Any] = ["message": message, "finish_reason": "tool_calls"] // Builds one complete tool-call choice.
            return .init(data: try Self.jsonData(["model": "qwen-coder", "choices": [choice]])) // Returns one valid native function request and no text.
        } // Ends native tool-call stub configuration.
        let schema = ModelToolSchema(name: "read_file", description: "Read a bounded UTF-8 workspace file.", parameters: .object(["type": .string("object"), "properties": .object(["path": .object(["type": .string("string")])])])) // Advertises one local tool schema without granting remote execution.
        let request = ModelGenerationRequest(target: makeTarget(profile: setup.profile), systemInstructions: "Use tools when needed.", messages: [ModelGenerationMessage(role: .user, content: "Read AppState.")], tools: [schema]) // Creates a normalized tool-capable request.
        let result = try await setup.backend.generate(request: request) // Decodes the native provider response through production validation.
        XCTAssertNil(result.text) // Confirms absent provider text remains absent.
        XCTAssertEqual(result.finishReason, .toolCalls) // Confirms native call completion metadata.
        XCTAssertEqual(result.toolCalls.count, 1) // Confirms exactly one local runtime request is produced.
        XCTAssertEqual(result.toolCalls[0].id, "call_1") // Confirms stable provider correlation.
        XCTAssertEqual(result.toolCalls[0].name, "read_file") // Confirms the requested local function name.
        XCTAssertEqual(result.toolCalls[0].arguments["path"], .string("Sources/AppState.swift")) // Confirms strict object argument decoding.
        XCTAssertEqual(result.toolCalls[0].arguments["line"], .number(12)) // Confirms numeric JSON arguments remain typed.
        } // Ends native tool-call normalization testing.

    func testPriorAssistantToolCallAndToolResultRoundTripAsNativeMessages() async throws { // Verifies multi-turn native context survives the normalized request boundary.
        let setup = try await makeBackend() // Creates one deterministic unauthenticated backend.
        RemoteURLProtocolStub.configure { _ in // Installs a successful response after the model receives prior prior tool context.
            .init(data: try Self.jsonData(["model": "qwen-coder", "choices": [["message": ["content": "The file was read."], "finish_reason": "stop"]]])) // Returns one ordinary continuation response.
        } // Ends multi-turn response stub configuration.
        let priorCall = ModelToolCall(id: "call_previous", name: "read_file", arguments: ["path": .string("Sources/App.swift")]) // Creates one previously validated assistant-native request.
        let schema = ModelToolSchema(name: "read_file", description: "Read a bounded workspace file.", parameters: .object(["type": .string("object")])) // Keeps the same local tool available for the continuation.
        let messages = [ // Builds the exact assistant call followed by its correlated local tool result.
            ModelGenerationMessage(role: .assistant, content: "", assistantToolCalls: [priorCall]), // Preserves the prior native call without flattening it into assistant text.
            ModelGenerationMessage(role: .tool, content: "file contents", toolCallID: "call_previous", name: "read_file") // Returns the local tool observation with exact provider correlation.
        ] // Ends normalized multi-turn message history.
        let request = ModelGenerationRequest(target: makeTarget(profile: setup.profile), systemInstructions: "Continue after tool results.", messages: messages, tools: [schema]) // Creates a complete native continuation request.
        let result = try await setup.backend.generate(request: request) // Executes provider encoding and normal response decoding.
        XCTAssertEqual(result.text, "The file was read.") // Confirms the continuation response remains normalized.
        let sent = try XCTUnwrap(RemoteURLProtocolStub.requests().last) // Reads the exact provider-bound request.
        let body = try XCTUnwrap(sent.httpBody) // Reads the captured JSON body.
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any]) // Decodes only the deterministic test payload.
        let providerMessages = try XCTUnwrap(object["messages"] as? [[String: Any]]) // Reads provider-native messages in order.
        let assistant = try XCTUnwrap(providerMessages.first { $0["role"] as? String == "assistant" }) // Resolves the prior assistant function-call message.
        let assistantCalls = try XCTUnwrap(assistant["tool_calls"] as? [[String: Any]]) // Reads re-encoded native calls rather than natural-language text.
        XCTAssertEqual(assistantCalls.first?["id"] as? String, "call_previous") // Confirms exact call correlation survives round-trip.
        let function = try XCTUnwrap(assistantCalls.first?["function"] as? [String: Any]) // Reads the provider function envelope.
        XCTAssertEqual(function["name"] as? String, "read_file") // Confirms exact local tool identity survives round-trip.
        let argumentsText = try XCTUnwrap(function["arguments"] as? String) // Reads the provider-required JSON argument string.
        let argumentsData = try XCTUnwrap(argumentsText.data(using: .utf8)) // Converts the strict argument string for structural assertion.
        let arguments = try XCTUnwrap(try JSONSerialization.jsonObject(with: argumentsData) as? [String: Any]) // Decodes the strict prior JSON object.
        XCTAssertEqual(arguments["path"] as? String, "Sources/App.swift") // Confirms typed arguments survive provider encoding.
        let tool = try XCTUnwrap(providerMessages.first { $0["role"] as? String == "tool" }) // Resolves the correlated tool result message.
        XCTAssertEqual(tool["tool_call_id"] as? String, "call_previous") // Confirms the local result references the same native call.
    } // Ends assistant call and tool result round-trip testing.

    func testMalformedToolArgumentsAreRejectedWithoutNaturalLanguageParsing() async throws { // Verifies an ambiguous provider call never reaches local runtime dispatch.
        let setup = try await makeBackend() // Creates one deterministic backend.
        RemoteURLProtocolStub.configure { _ in // Installs a malformed function argument string.
            let function: [String: Any] = ["name": "run_command", "arguments": "please run rm -rf something"] // Supplies ambiguous natural language instead of a JSON object string.
            let call: [String: Any] = ["id": "call_1", "type": "function", "function": function] // Builds the malformed provider-native call object.
            let message: [String: Any] = ["content": NSNull(), "tool_calls": [call]] // Builds an assistant message containing the malformed call.
            let choice: [String: Any] = ["message": message, "finish_reason": "tool_calls"] // Builds one structurally complete provider choice.
            return .init(data: try Self.jsonData(["model": "qwen-coder", "choices": [choice]])) // Simulates natural language where strict JSON is required.
        } // Ends malformed tool-call stub configuration.
        let request = ModelGenerationRequest(target: makeTarget(profile: setup.profile), systemInstructions: "Use strict calls.", messages: [ModelGenerationMessage(role: .user, content: "Run tests.")]) // Creates a valid normalized generation request.
        do { // Captures the exact typed rejection.
            _ = try await setup.backend.generate(request: request) // Attempts production response normalization.
            XCTFail("Expected malformed tool-call rejection.") // Fails if arbitrary natural language was accepted.
        } catch let error as RemoteInferenceError { // Reads the typed backend failure.
            guard case .malformedToolCall = error else { // Requires the strict tool-call error category.
                return XCTFail("Unexpected error: \(error)") // Reports a mismatched safe typed failure.
            } // Ends error-category validation.
            XCTAssertTrue(error.isFallbackEligible) // Confirms routing may use only its explicit compatible fallback after provider incompatibility.
        } // Ends malformed tool-call rejection assertion.
    } // Ends strict malformed tool-call testing.

    func testHTTPAuthenticationFailureRedactsExactAndCredentialShapedSecrets() async throws { // Verifies provider and Authorization echoes cannot leak into errors or traces.
        let secret = "sk-private-credential-123456789" // Supplies both an exact known token and a common credential shape.
        let setup = try await makeBackend(authenticationMode: .bearerToken, token: secret) // Creates an authenticated deterministic backend.
        RemoteURLProtocolStub.configure { _ in // Installs a provider failure that maliciously echoes authorization content.
            let echoed = "Authorization: Bearer \(secret) token=second-secret-value" // Simulates an unsafe server diagnostic.
            return .init(statusCode: 401, data: try Self.jsonData(["error": ["message": echoed]])) // Returns the echo inside the standard provider error envelope.
        } // Ends unsafe error stub configuration.
        let request = ModelGenerationRequest(target: makeTarget(profile: setup.profile), systemInstructions: "Respond.", messages: [ModelGenerationMessage(role: .user, content: "Hello")]) // Creates a normal backend-neutral request.
        do { // Captures the expected typed HTTP failure.
            _ = try await setup.backend.generate(request: request) // Executes the authenticated request.
            XCTFail("Expected HTTP authentication failure.") // Fails if a 401 response was accepted.
        } catch let error as RemoteInferenceError { // Reads the typed redacted failure.
            guard case .httpStatus(let code, let message) = error else { // Requires the provider HTTP error category.
                return XCTFail("Unexpected error: \(error)") // Reports a mismatched safe failure.
            } // Ends error-category validation.
            XCTAssertEqual(code, 401) // Confirms routing and UI retain the useful status code.
            XCTAssertFalse(message.contains(secret)) // Confirms exact token removal.
            XCTAssertFalse(message.contains("second-secret-value")) // Confirms labeled credential-shape removal.
            XCTAssertTrue(message.contains("[REDACTED]")) // Confirms the error remains intelligible without secrets.
            XCTAssertFalse(error.localizedDescription.contains(secret)) // Confirms final UI/debug rendering is also safe.
        } // Ends redacted HTTP failure assertion.
    } // Ends authentication error redaction testing.

    func testMalformedGenerationResponseIsBoundedAndFallbackReady() async throws { // Verifies provider-specific or broken JSON never escapes as dictionaries.
        let setup = try await makeBackend() // Creates one deterministic backend.
        RemoteURLProtocolStub.configure { _ in // Installs a structurally incompatible JSON response.
            .init(data: try Self.jsonData(["choices": []])) // Returns no usable completion choice.
        } // Ends malformed response stub configuration.
        let request = ModelGenerationRequest(target: makeTarget(profile: setup.profile), systemInstructions: "Respond.", messages: [ModelGenerationMessage(role: .user, content: "Hello")]) // Creates a valid normalized request.
        do { // Captures the expected normalization failure.
            _ = try await setup.backend.generate(request: request) // Attempts to normalize the malformed success envelope.
            XCTFail("Expected malformed response failure.") // Fails if an unusable response is accepted.
        } catch let error as RemoteInferenceError { // Reads the typed backend failure.
            guard case .malformedResponse(let message) = error else { // Requires the normalized response error category.
                return XCTFail("Unexpected error: \(error)") // Reports a mismatched safe failure.
            } // Ends error-category validation.
            XCTAssertLessThanOrEqual(message.count, 512) // Confirms concise bounded diagnostics.
            XCTAssertTrue(error.isFallbackEligible) // Confirms explicit compatible local fallback remains possible.
        } // Ends malformed response assertion.
    } // Ends malformed provider response testing.

    func testTimeoutAndConnectionLossMapToDistinctFallbackReadyErrors() async throws { // Verifies network failure semantics remain actionable to ModelRouter.
        let setup = try await makeBackend() // Creates one deterministic backend shared across two sequential outcomes.
        let request = ModelGenerationRequest(target: makeTarget(profile: setup.profile), systemInstructions: "Respond.", messages: [ModelGenerationMessage(role: .user, content: "Hello")]) // Creates one valid normalized request.
        RemoteURLProtocolStub.configure { _ in // Installs an explicit transport timeout.
            .init(error: URLError(.timedOut)) // Returns the stable Foundation timeout code.
        } // Ends timeout stub configuration.
        do { // Captures the first typed transport failure.
            _ = try await setup.backend.generate(request: request) // Attempts generation through the timed-out transport.
            XCTFail("Expected timeout.") // Fails if timeout is accepted as a response.
        } catch let error as RemoteInferenceError { // Reads the typed timeout.
            XCTAssertEqual(error, .timedOut) // Confirms exact timeout normalization.
            XCTAssertTrue(error.isFallbackEligible) // Confirms explicit compatible fallback may be selected.
        } // Ends timeout assertion.
        RemoteURLProtocolStub.configure { _ in // Reconfigures the same offline session for a dropped connection.
            .init(error: URLError(.networkConnectionLost)) // Returns the stable Foundation disconnect code.
        } // Ends disconnect stub configuration.
        do { // Captures the second typed transport failure.
            _ = try await setup.backend.generate(request: request) // Attempts generation through the disconnected transport.
            XCTFail("Expected connection loss.") // Fails if disconnect is accepted as a response.
        } catch let error as RemoteInferenceError { // Reads the typed disconnect.
            XCTAssertEqual(error, .connectionLost) // Confirms connection loss remains distinct from timeout.
            XCTAssertTrue(error.isFallbackEligible) // Confirms explicit compatible fallback may be selected.
        } // Ends disconnect assertion.
    } // Ends network loss mapping testing.

    func testTaskCancellationStopsPendingInferenceWithoutFallback() async throws { // Verifies cooperative cancellation independently from any physical server.
        let environment = makeTemporaryEnvironment() // Creates isolated production store boundaries.
        let profile = makeProfile() // Creates one enabled unauthenticated server profile.
        let store = RemoteServerStore(fileURL: environment.fileURL, tokenVault: environment.vault) // Creates the production multi-profile actor.
        try await store.save(profile) // Persists the profile before generation begins.
        let backend = RemoteInferenceBackend(profileProvider: store, session: makeSession(protocolClass: NeverCompletingRemoteURLProtocol.self), cacheTTL: 30) // Creates a backend whose HTTP request remains pending until cancellation.
        let request = ModelGenerationRequest(target: makeTarget(profile: profile), systemInstructions: "Respond.", messages: [ModelGenerationMessage(role: .user, content: "Wait")]) // Creates a valid normalized request.
        let task = Task { // Starts the pending production generation asynchronously.
            try await backend.generate(request: request) // Executes until URLSession receives cancellation.
        } // Ends pending generation task creation.
        try await Task.sleep(nanoseconds: 30_000_000) // Allows the injected URL load to enter its pending state without a blocking sleep.
        task.cancel() // Requests cooperative user-style cancellation.
        do { // Captures the expected typed cancellation.
            _ = try await task.value // Awaits termination of the cancelled URLSession request.
            XCTFail("Expected cancellation.") // Fails if pending inference returned a fabricated result.
        } catch let error as RemoteInferenceError { // Reads the typed cancellation outcome.
            XCTAssertEqual(error, .cancelled) // Confirms cancellation remains distinct from disconnect and timeout.
            XCTAssertFalse(error.isFallbackEligible) // Confirms user cancellation never silently starts another model.
        } // Ends cancellation assertion.
    } // Ends pending inference cancellation testing.

    private func makeTemporaryEnvironment() -> (fileURL: URL, vault: RecordingRemoteTokenVault) { // Creates exact disposable persistence and token boundaries for one test.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AutoMLXStudio-RemoteTests-\(UUID().uuidString)", isDirectory: true) // Creates a unique narrow test directory path.
        let fileURL = directory.appendingPathComponent("RemoteServers.json", isDirectory: false) // Selects the exact production-format document location.
        let vault = RecordingRemoteTokenVault() // Creates an isolated in-memory secret boundary.
        addTeardownBlock { // Registers recoverable test-artifact cleanup after assertions finish.
            try? FileManager.default.removeItem(at: directory) // Removes only the exact UUID-scoped temporary directory.
        } // Ends temporary artifact cleanup registration.
        return (fileURL, vault) // Returns the isolated test boundaries.
    } // Ends temporary environment creation.

    private func makeProfile(id: UUID = UUID(), displayName: String = "Remote Test Server", host: String = "remote.test", authenticationMode: RemoteAuthenticationMode = .none) -> RemoteServerProfile { // Creates a consistent bounded OpenAI-compatible profile for tests.
        RemoteServerProfile(id: id, displayName: displayName, backendID: .remoteOpenAICompatible, scheme: .http, host: host, port: 1_234, basePath: "/v1", authenticationMode: authenticationMode, connectionTimeoutSeconds: 2, inferenceTimeoutSeconds: 5, isEnabled: true, createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000)) // Returns deterministic non-secret configuration.
    } // Ends test profile construction.

    private func makeTarget(profile: RemoteServerProfile, modelID: String = "qwen-coder") -> ModelGenerationTarget { // Creates the exact remote target selected by routing.
        ModelGenerationTarget(backendID: .remoteOpenAICompatible, location: .remote(serverID: profile.id), modelID: modelID) // Binds backend, server, and provider model without a filesystem path.
    } // Ends test target construction.

    private func makeBackend(authenticationMode: RemoteAuthenticationMode = .none, token: String? = nil) async throws -> (backend: RemoteInferenceBackend, profile: RemoteServerProfile) { // Creates a production backend wired to disposable persistence and deterministic HTTP.
        let environment = makeTemporaryEnvironment() // Creates isolated persistence and token boundaries.
        let profile = makeProfile(authenticationMode: authenticationMode) // Creates one configured server profile.
        let store = RemoteServerStore(fileURL: environment.fileURL, tokenVault: environment.vault) // Creates the actor-isolated production profile store.
        try await store.save(profile) // Persists the exact profile used by the backend.
        if let token { // Handles authenticated test setup.
            try await store.setToken(token, for: profile.id) // Stores the token behind the injected vault boundary.
        } // Ends optional test token setup.
        let backend = RemoteInferenceBackend(profileProvider: store, session: makeSession(protocolClass: RemoteURLProtocolStub.self), cacheTTL: 60) // Creates the production adapter with a conservative cache and offline transport.
        return (backend, profile) // Returns the configured backend and exact target profile.
    } // Ends deterministic backend setup.

    private func makeSession(protocolClass: AnyClass) -> URLSession { // Creates an isolated non-caching URLSession using one exact test protocol.
        let configuration = URLSessionConfiguration.ephemeral // Avoids shared cookies, credentials, and disk cache state.
        configuration.protocolClasses = [protocolClass] // Routes requests only through the supplied deterministic URLProtocol.
        configuration.urlCache = nil // Disables response caching outside production actor cache behavior.
        return URLSession(configuration: configuration) // Returns the isolated cancellable test session.
    } // Ends test URLSession construction.

    private static func jsonData(_ object: Any) throws -> Data { // Encodes deterministic Foundation JSON fixtures without fragile manual escaping.
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) // Produces valid stable test JSON from literal fixtures without forced failure.
    } // Ends JSON fixture encoding.
} // Ends the permanent remote backend test suite.
