import AppKit // Renders only validation-owned native views.
import Foundation // Uses real networking, persistence, and bounded asynchronous waits.
import SwiftUI // Hosts the unchanged production SwiftUI surfaces.
@testable import AutoMLXStudio // Links the exact prechecked application object files, not copied implementations.

final class Evidence: @unchecked Sendable { // Serializes sanitized observations from real production calls.
    let root: URL // Identifies the user-requested evidence directory.
    private let lock = NSLock() // Protects writes across actors.
    init(root: URL) { self.root = root } // Retains the explicit destination.
    func record(_ name: String, _ value: Any) { // Writes one independently inspectable JSON observation.
        lock.lock(); defer { lock.unlock() } // Keeps concurrent observations coherent.
        do { // Reports evidence failures rather than silently dropping them.
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) // Encodes only explicit non-secret fields.
            try data.write(to: root.appendingPathComponent(name + ".json"), options: .atomic) // Saves generated evidence without touching application sources.
            print("EVIDENCE \(name)"); fflush(stdout) // Makes long-running progress observable.
        } catch { print("EVIDENCE ERROR \(name): \(error)"); fflush(stdout) } // Exposes failed evidence persistence.
    } // Ends evidence writing.
} // Ends the evidence sink.

actor ObservedRemote: ModelInferenceBackend { // Observes real requests without intercepting or fabricating HTTP.
    nonisolated let id: ModelBackendID = .remoteOpenAICompatible // Preserves production backend identity.
    let real: RemoteInferenceBackend // Owns the unmodified real URLSession transport.
    let evidence: Evidence // Persists bounded protocol metadata.
    private var serial = 0 // Assigns unique request identities.
    private(set) var completed = 0 // Counts actual successful remote responses.
    private(set) var toolRoundTrips = 0 // Counts responses to requests carrying actual tool results.
    private(set) var active = 0 // Identifies an in-flight production generation.
    init(real: RemoteInferenceBackend, evidence: Evidence) { self.real = real; self.evidence = evidence } // Adds observation only.
    func health(for target: ModelGenerationTarget) async -> ModelBackendHealth { await real.health(for: target) } // Delegates health to the real server.
    func generate(request: ModelGenerationRequest) async throws -> ModelGenerationResult { // Preserves the complete original request.
        serial += 1; let number = serial; active += 1 // Records this live generation before transport starts.
        defer { active -= 1 } // Clears activity on success, cancellation, and failure.
        let tools = request.messages.filter { $0.role == .tool } // Extracts only actual Mac tool results.
        let calls = request.messages.flatMap(\.assistantToolCalls) // Obtains provider-generated correlation identities.
        let correlation = tools.allSatisfy { result in calls.contains { $0.id == result.toolCallID && $0.name == result.name } } // Checks the complete outgoing native history.
        evidence.record("request-\(number)", ["model": request.target.modelID, "backend": request.target.backendID.rawValue, "messageCount": request.messages.count, "tools": request.tools.map(\.name), "toolResultCount": tools.count, "correlationValid": correlation, "toolResults": tools.map { ["id": $0.toolCallID ?? "", "name": $0.name ?? "", "content": String($0.content.prefix(12000))] }]) // Records fixture-only results, never headers or credentials.
        do { // Distinguishes genuine transport outcomes.
            let result = try await real.generate(request: request) // Performs actual Mac-to-Windows inference.
            completed += 1; if !tools.isEmpty && correlation { toolRoundTrips += 1 } // Counts only successful real round-trips.
            evidence.record("response-\(number)", ["model": result.modelID, "durationMS": result.durationMilliseconds, "text": result.text ?? "", "toolCalls": result.toolCalls.map { ["id": $0.id, "name": $0.name] }, "finishReason": result.finishReason?.rawValue ?? ""]) // Records normalized application output.
            return result // Returns the untouched provider response to the dispatcher.
        } catch { // Retains typed safe failures for diagnosis.
            evidence.record("error-\(number)", ["type": String(describing: type(of: error)), "message": error.localizedDescription, "cancelled": Task.isCancelled]) // Excludes raw requests and secrets.
            throw error // Preserves production failure classification.
        } // Ends real transport observation.
    } // Ends observed generation.
} // Ends the transparent observer.

@main // Provides a validation-only entry point; the shipping app entry point is not linked.
struct PhysicalWindowsHarness { // Exercises unchanged app types with a physical Windows server.
    @MainActor static func main() async { // Uses the same actor isolation as SwiftUI actions.
        let env = ProcessInfo.processInfo.environment // Reads only explicitly supplied validation configuration.
        guard let output = env["PHYSICAL_EVIDENCE"], let host = env["PHYSICAL_HOST"], let portText = env["PHYSICAL_PORT"], let port = Int(portText), let model = env["PHYSICAL_MODEL"], let fixturePath = env["PHYSICAL_FIXTURE"] else { fatalError("Explicit physical validation environment required") } // Refuses implicit or hardcoded remote targets.
        let evidence = Evidence(root: URL(fileURLWithPath: output, isDirectory: true)) // Uses the requested repository evidence folder.
        do { try await run(evidence: evidence, host: host, port: port, model: model, fixture: URL(fileURLWithPath: fixturePath, isDirectory: true)) } catch { evidence.record("fatal", ["type": String(describing: type(of: error)), "message": error.localizedDescription]); exit(1) } // Reports real failures without inventing a pass.
    } // Ends the isolated entry point.

    @MainActor static func run(evidence: Evidence, host: String, port: Int, model: String, fixture: URL) async throws { // Runs physical checks in dependency order.
        _ = NSApplication.shared // Enables native rendering without inspecting another app or the desktop.
        let state = AppState(startsBackgroundTasks: false) // Loads the production object graph without starting local model or voice processes.
        let remote = state.remoteModelsController // Uses the app-owned normal Remote Models controller.
        await remote.load() // Loads the real app persistence path before any mutation.
        let existing = remote.profiles.first { $0.host == host && $0.port == port && $0.basePath == "/v1" } // Avoids duplicate endpoint profiles.
        let profile = existing ?? RemoteServerProfile(displayName: "Windows LM Studio", host: host, port: port) // Creates only the user-requested endpoint with no API key.
        if existing == nil { // Creates only an absent profile without an asynchronous boolean autoclosure.
            guard await remote.save(profile: profile, tokenUpdate: .unchanged) else { throw validationError("Remote profile save failed: \(remote.notice?.message ?? "unknown")") } // Uses normal validated persistence without touching Keychain secrets.
        } // Ends conditional profile creation.
        let persisted = try await RemoteServerStore().allProfiles() // Reopens the actual durable file through a fresh production store.
        guard persisted.contains(where: { $0.id == profile.id && $0.host == profile.host && $0.port == profile.port && $0.basePath == profile.basePath && $0.authenticationMode == profile.authenticationMode && $0.displayName == profile.displayName }) else { throw validationError("Remote profile did not survive fresh store reload") } // Checks durable configuration independently of ISO8601 subsecond normalization.
        evidence.record("persistence", ["status": "PASS", "file": RemoteServerStore.defaultFileURL().path, "serverID": profile.id.uuidString, "created": existing == nil, "authentication": profile.authenticationMode.rawValue]) // Records non-secret durable identity.
        await remote.testConnection(serverID: profile.id) // Executes the real UI health-check action.
        let health = remote.healthByServerID[profile.id] // Reads exactly the state displayed by Remote Models.
        evidence.record("health", ["status": health?.status.rawValue ?? "missing", "apiCompatible": health?.apiCompatible ?? false, "latencyMS": health?.latencyMilliseconds ?? -1, "error": health?.conciseError ?? ""]) // Retains real health evidence.
        await remote.refreshModels(serverID: profile.id) // Executes the normal explicit discovery action.
        let models = remote.modelsByServerID[profile.id] ?? [] // Reads the controller's actual discovered records.
        evidence.record("discovery", ["models": models.map(\.id), "selectedModel": model, "selectedModelPresent": models.contains { $0.id == model }]) // Does not load any other discovered model.
        guard health?.status == .healthy, models.contains(where: { $0.id == model }) else { throw validationError("Physical health or requested-model discovery failed") } // Prevents generation against an unverified target.
        let observed = ObservedRemote(real: state.remoteInferenceBackend, evidence: evidence) // Wraps the exact app-owned transport with non-mutating observation.
        let registry = ModelRegistry(models: [], assignments: [], legacyFallbackModelID: "") // Disables local fallbacks so every physical result must come from Windows.
        let target = ModelGenerationTarget(backendID: .remoteOpenAICompatible, location: .remote(serverID: profile.id), modelID: model) // Selects the discovered model explicitly.
        let route = try EngineeringSessionBuilder.route(phase: .primary, registry: registry, remoteTarget: target, remoteModels: models) // Uses the production route constructor.
        let dispatcher = ModelBackendDispatcher(registry: try ModelBackendRegistry(backends: [observed])) // Uses the actual production dispatcher.
        func request(_ messages: [ModelGenerationMessage], tokens: Int = 64) -> ModelGenerationRequest { ModelGenerationRequest(target: target, systemInstructions: "Follow the user's instructions exactly. Do not add explanations.", messages: messages, temperature: 0, maxOutputTokens: tokens) } // Builds plain normalized chat input, not a fake response.
        let chat = try await dispatcher.generate(request: request([ModelGenerationMessage(role: .user, content: "Reply with exactly: AUTOMLX_WINDOWS_OK")]), using: route) // Traverses the real backend and physical LAN.
        evidence.record("chat-backend", ["pass": chat.result.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "AUTOMLX_WINDOWS_OK", "response": chat.result.text ?? "", "fallback": chat.trace.usedFallback, "scope": "Production dispatcher/backend harness; ordinary Chat UI is local-only"]) // Does not mislabel backend coverage as Chat UI coverage.
        let first = ModelGenerationMessage(role: .user, content: "Remember the number 7319.") // Starts a synthetic validation-only conversation.
        let remembered = try await dispatcher.generate(request: request([first]), using: route) // Obtains the actual first response from Windows.
        let history = [first, ModelGenerationMessage(role: .assistant, content: remembered.result.text ?? ""), ModelGenerationMessage(role: .user, content: "What number did I give you? Reply with only the number.")] // Carries actual prior output in normalized history.
        let recalled = try await dispatcher.generate(request: request(history), using: route) // Sends real multi-turn history over the LAN.
        evidence.record("multi-turn-backend", ["pass": recalled.result.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "7319", "response": recalled.result.text ?? "", "scope": "Production backend history; not ordinary Chat UI history"]) // Distinguishes the absent UI integration.
        let longRequest = request([ModelGenerationMessage(role: .user, content: "Write a detailed 2000-word tutorial about prime numbers. Start immediately with the tutorial.")], tokens: 4096) // Requests a feasible long answer after the first model declined an excessive line count.
        let longTask = Task { try await dispatcher.generate(request: longRequest, using: route) } // Starts a cancellable real production request.
        try await Task.sleep(for: .milliseconds(500)) // Gives the physical request time to enter transport while avoiding a completed short refusal.
        let wasActive = await observed.active > 0 // Checks that cancellation is not applied after completion.
        let cancelStart = Date(); longTask.cancel() // Cancels only this validation-owned request, never LM Studio.
        var cancelled = false // Requires a typed cancellation rather than assuming success.
        do { _ = try await longTask.value } catch let error as ModelBackendDispatchError { cancelled = error.trace.terminalState == .cancelled } catch { cancelled = error is CancellationError } // Checks the propagated production outcome.
        let recovered = try await dispatcher.generate(request: request([ModelGenerationMessage(role: .user, content: "Reply with exactly: AUTOMLX_WINDOWS_OK")]), using: route) // Verifies immediate reuse after cancellation.
        evidence.record("cancellation-backend", ["wasActive": wasActive, "cancelled": cancelled, "recoveryResponse": recovered.result.text ?? "", "cancelAndRecoveryMS": Int(Date().timeIntervalSince(cancelStart) * 1000), "scope": "Production request cancellation; Engineering Stop checked separately"]) // Preserves the exact scope and recovery result.
        let broker = EngineeringApprovalBroker() // Keeps the production broker's default-deny behavior.
        let builder = EngineeringSessionBuilder(backends: [observed], approvalBroker: broker, registryProvider: { registry }, remoteModelsProvider: { models }) // Uses unchanged production session construction with no local fallback.
        let controller = EngineeringController(workspaceStore: EngineeringWorkspaceStore(catalogURL: fixture.appendingPathComponent("catalog.json")), memoryStore: ProjectMemoryStore(rootURL: fixture.appendingPathComponent("memory")), sessionBuilder: builder, approvalBroker: broker) // Isolates catalog/memory from existing user workspaces.
        controller.quality = .fast; controller.prefersRemoteModel = true; controller.selectedRemoteServerID = profile.id; controller.selectedRemoteModelID = model // Uses the same selections as the Engineering UI.
        await controller.authorizeWorkspace(directoryURL: fixture.appendingPathComponent("allow")) // Authorizes only the disposable faulty project.
        controller.taskText = "Inspect the project, identify the failing behavior, make the smallest correct edit, run the tests, and verify the final result. Start by calling read_file with path README.md and read_file with path calculator.txt. For all tools paths must be workspace-relative; the root path and workingDirectory are the empty string, never a dot. Use the SHA-256 returned by read_file for edits. Read README.md for the local test command. Do not alter the tests or Makefile. Stop after successful verification." // Clarifies the existing path contract after the first live model supplied an invalid dot path.
        controller.run() // Executes the same action as the native Run button.
        try await observe(controller, evidence: evidence, name: "engineering-allow", approve: true, timeout: 600) // Reviews each actual proposal before allowing it once.
        evidence.record("protocol-summary", ["realResponses": await observed.completed, "toolResultRoundTrips": await observed.toolRoundTrips]) // Records completed real native-tool history round-trips.
        await controller.authorizeWorkspace(directoryURL: fixture.appendingPathComponent("deny")) // Selects a second independent fixture for denial.
        controller.taskText = "Call read_file with path calculator.txt, then call write_file to change its value to 2 followed by a newline, using the SHA-256 returned by the read. Root paths must be the empty string, never a dot. Stop if a tool reports permission denied." // Requests a genuine write without telling the model in advance that approval will be denied.
        controller.run() // Starts a second real Engineering session.
        try await observe(controller, evidence: evidence, name: "engineering-deny", approve: false, timeout: 180) // Uses the normal Deny action without relaxing policy.
        let denyBytes = try String(contentsOf: fixture.appendingPathComponent("deny/calculator.txt"), encoding: .utf8) // Reads only the disposable deny fixture.
        evidence.record("deny-file", ["unchanged": denyBytes == "1\n", "content": denyBytes]) // Verifies denial did not mutate bytes.
        controller.taskText = "Do not use tools. Write 8000 numbered lines explaining prime numbers, without summarizing." // Creates long real model work through the UI controller.
        controller.run() // Starts the normal Engineering Run action.
        let waiting = Date() // Bounds time waiting for the actual request to start.
        while await observed.active == 0 && controller.isRunning && Date().timeIntervalSince(waiting) < 10 { try await Task.sleep(for: .milliseconds(50)) } // Waits for observable production transport activity.
        try await Task.sleep(for: .seconds(1)) // Cancels during generation rather than during workspace preparation.
        let controllerWasActive = await observed.active > 0; let stoppedAt = Date(); controller.stop() // Executes exactly the native Stop button action.
        while controller.isRunning && Date().timeIntervalSince(stoppedAt) < 10 { try await Task.sleep(for: .milliseconds(50)) } // Checks bounded controller recovery without blocking the main actor.
        evidence.record("cancellation-controller", ["wasActive": controllerWasActive, "isRunning": controller.isRunning, "canRun": controller.canRun, "pendingApproval": controller.pendingApproval != nil, "elapsedMS": Int(Date().timeIntervalSince(stoppedAt) * 1000), "status": controller.statusText]) // Records actual published UI state after Stop.
        controller.taskText = "Do not use tools. Reply with exactly: AUTOMLX_WINDOWS_OK" // Requests a new generation through the same recovered controller.
        controller.run() // Verifies controller reuse, not only transport reuse.
        try await observe(controller, evidence: evidence, name: "engineering-after-stop", approve: false, timeout: 120) // Records the actual post-cancellation response.
        let view = NSHostingView(rootView: EngineeringView(controller: controller, remoteController: remote).environmentObject(state)) // Hosts the unchanged real Engineering surface with its physical-run state.
        view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800); view.layoutSubtreeIfNeeded() // Gives the native view a deterministic own-view viewport.
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: bitmap); if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: evidence.root.appendingPathComponent("EngineeringPhysical.png")) } } // Captures only the validation-owned native view, not the user's desktop.
        evidence.record("complete", ["scope": "Live production-object harness, real LAN and Mac tools; ordinary Chat UI unavailable", "finishedAt": ISO8601DateFormatter().string(from: Date()), "fixture": fixture.path]) // Marks harness completion without claiming all acceptance criteria passed.
    } // Ends sequential physical checks.

    @MainActor static func observe(_ controller: EngineeringController, evidence: Evidence, name: String, approve: Bool, timeout: TimeInterval) async throws { // Observes the exact live UI controller until bounded completion.
        let started = Date(); var seen = Set<UUID>(); var decisions = [[String: Any]]() // Tracks only new actual approval requests.
        while controller.isRunning && Date().timeIntervalSince(started) < timeout { // Bounds each physical session.
            if let approval = controller.pendingApproval, seen.insert(approval.id).inserted { // Handles each exact decision once.
                let root = URL(fileURLWithPath: approval.workspacePath) // Resolves the actual proposal's authorized workspace.
                let file = root.appendingPathComponent("calculator.txt") // Identifies the fixture file for pre-decision evidence.
                let before = (try? String(contentsOf: file, encoding: .utf8)) ?? "missing" // Observes bytes before deciding.
                let isEdit = approval.tool == .writeFile || approval.tool == .replaceInFile // Limits approval to the intended deterministic edit tools.
                let isTest = approval.tool == .runTests && ["/usr/bin/make test", "make test"].contains(approval.exactCommand) // Accepts only the two equivalent spellings that production policy resolves to /usr/bin/make, without extra flags.
                let safeEdit = isEdit && (approval.exactCommand.hasPrefix("write_file calculator.txt\n") || approval.exactCommand.hasPrefix("replace_in_file calculator.txt\n")) // Refuses unrelated file mutations and ambiguous target names.
                let allow = approve && (safeEdit || isTest) // Never globally enables approval or arbitrary process execution.
                try await Task.sleep(for: .seconds(1)) // Leaves the real approval pending to test that no mutation happens early.
                let afterPending = (try? String(contentsOf: file, encoding: .utf8)) ?? "missing" // Rechecks bytes before granting or denying authority.
                decisions.append(["id": approval.id.uuidString, "tool": approval.tool.rawValue, "command": approval.exactCommand, "before": before, "unchangedWhilePending": before == afterPending, "decision": allow ? "allowOnce" : "deny"]) // Records exact proposal and both pre-decision byte observations.
                evidence.record(name + "-approvals", decisions) // Saves evidence before resolving the proposal.
                controller.resolveApproval(allow ? .allowOnce : .deny) // Uses the exact production Allow Once or Deny action.
            } // Ends one real approval decision.
            try await Task.sleep(for: .milliseconds(100)) // Keeps the UI actor responsive between observations.
        } // Ends bounded live observation.
        if controller.isRunning { controller.stop(); try await Task.sleep(for: .seconds(2)) } // Cancels only the validation-owned session at its deadline.
        let result = controller.result // Reads the actual terminal engine result published by the app.
        evidence.record(name, ["status": result?.status.rawValue ?? controller.statusText, "summary": result?.finalSummary ?? "", "verification": result?.verification.state.rawValue ?? "missing", "verificationDetail": result?.verification.detail ?? "", "changedPaths": result?.changedPaths ?? [], "iterations": result?.iterationsUsed ?? 0, "failure": result?.failureSummary ?? "", "stillRunning": controller.isRunning, "events": controller.activity.map { ["kind": $0.kind.rawValue, "tool": $0.toolName ?? "", "summary": $0.summary, "exitCode": $0.exitCode.map(String.init) ?? "", "backend": $0.backendID ?? "", "model": $0.modelID ?? ""] }]) // Retains actual operational evidence and final response, not invented verification.
    } // Ends live Engineering observation.
    static func validationError(_ message: String) -> NSError { NSError(domain: "PhysicalWindowsValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) } // Produces explicit harness failures.
} // Ends the validation-only harness.
