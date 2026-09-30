import Darwin // Supplies exact-PID liveness checks for cancellation isolation.
import Foundation // Supplies disposable directories, direct Process fixtures, and asynchronous delays.
import XCTest // Supplies deterministic assertions for tool policy and owned-process behavior.
@testable import AutoMLXStudio // Exposes internal V0.6 Engineering Tool Runtime types to the test bundle.

final class EngineeringToolRuntimeTests: XCTestCase { // Groups process and policy tests that never operate on the real repository.
    func testToolRegistryIsStableUniqueAndRiskAnnotated() { // Verifies model backends receive a compact non-overlapping typed tool surface.
        let definitions = EngineeringToolRuntime.definitions // Reads the production provider-independent registry.
        XCTAssertEqual(definitions.count, EngineeringToolName.allCases.count) // Confirms every stable tool name is registered exactly once.
        XCTAssertEqual(Set(definitions.map(\.name)).count, definitions.count) // Confirms no duplicate or overlapping registration exists.
        XCTAssertEqual(definitions.first(where: { $0.name == .readFile })?.defaultRisk, .safeReadOnly) // Confirms ordinary bounded reads require no approval.
        XCTAssertEqual(definitions.first(where: { $0.name == .writeFile })?.defaultRisk, .workspaceMutation) // Confirms contained tracked writes are classified explicitly.
        XCTAssertEqual(definitions.first(where: { $0.name == .runCommand })?.requiredArguments.contains("arguments"), true) // Confirms command calls require structured argument arrays rather than natural-language shell parsing.
    } // Ends typed registry coverage.

    func testDirectCommandTreatsShellMetacharactersAsInertData() async throws { // Verifies Process argument boundaries prevent command injection.
        let fixture = try makeFixture(prefix: "ArgumentInjection") // Creates an isolated authorized workspace and runtime storage.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only test-owned state.
        let runtime = try makeRuntime(fixture: fixture) // Creates the production runtime with default-deny approval.
        let payload = "hello; /usr/bin/touch SHOULD_NOT_EXIST && echo injected" // Defines shell-looking text that must remain one ordinary argument.
        let command = EngineeringCommand(executable: "echo", arguments: [payload], timeoutMilliseconds: 2_000, reason: "Verify direct argument handling") // Requests the fixed direct echo executable.
        let result = await runtime.execute(.runCommand(command)) // Runs without `/bin/sh -c`.
        XCTAssertTrue(result.succeeded) // Confirms the allowed diagnostic command completed.
        XCTAssertEqual(result.risk, .safeReadOnly) // Confirms punctuation did not alter structural classification.
        XCTAssertTrue(result.text?.contains(payload) == true) // Confirms the exact punctuation was passed as inert data.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.rootURL.appendingPathComponent("SHOULD_NOT_EXIST").path)) // Confirms no embedded command executed.
    } // Ends shell-injection-as-data coverage.

    func testPolicyBlocksShellDestructionTraversalAndHistoryRewriteBeforeApproval() throws { // Verifies structural denial cannot be promoted through an approval provider.
        let blockedCommands = [ // Builds a deterministic matrix of unconditional safety refusals.
            EngineeringCommand(executable: "sudo", arguments: ["true"]), // Requests privileged execution.
            EngineeringCommand(executable: "/bin/sh", arguments: ["-c", "echo unsafe"]), // Requests explicit shell interpretation.
            EngineeringCommand(executable: "git", arguments: ["reset", "--hard"]), // Requests destructive worktree/history mutation.
            EngineeringCommand(executable: "git", arguments: ["commit", "--amend", "-m", "rewrite"]), // Requests forbidden history rewriting.
            EngineeringCommand(executable: "git", arguments: ["push", "--force", "origin", "main"]), // Requests destructive remote history replacement.
            EngineeringCommand(executable: "xcodebuild", arguments: ["-derivedDataPath", "../../outside"]) // Requests a process output path outside workspace authority.
        ] // Ends blocked command fixtures.
        for command in blockedCommands { // Assesses each command without launching any process.
            XCTAssertThrowsError(try EngineeringCommandPolicy.assess(command)) { error in // Requires deterministic pre-execution refusal.
                XCTAssertTrue(error is EngineeringRuntimeError) // Confirms every refusal uses the stable runtime error domain.
            } // Ends one policy assertion.
        } // Ends blocked-command matrix.
        XCTAssertEqual(try EngineeringCommandPolicy.assess(EngineeringCommand(executable: "git", arguments: ["status", "--short"])).risk, .safeReadOnly) // Confirms read-only Git remains available.
        XCTAssertEqual(try EngineeringCommandPolicy.assess(EngineeringCommand(executable: "git", arguments: ["commit", "-m", "bounded"])).risk, .externalSideEffect) // Confirms commit always requires explicit approval.
        XCTAssertEqual(try EngineeringCommandPolicy.assess(EngineeringCommand(executable: "git", arguments: ["push", "origin", "main"])).risk, .externalSideEffect) // Confirms push always requires explicit approval.
        XCTAssertEqual(try EngineeringCommandPolicy.assess(EngineeringCommand(executable: "npm", arguments: ["install"])).risk, .externalSideEffect) // Confirms package installation requires explicit approval even when the executable is absent.
    } // Ends destructive and external command classification coverage.

    func testDefaultApprovalProviderDeniesExternalCommandWithoutLaunchingProcess() async throws { // Verifies missing UI never becomes implicit authorization.
        let fixture = try makeFixture(prefix: "DefaultDeny") // Creates an isolated non-Git workspace.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only test-owned state.
        let runtime = try makeRuntime(fixture: fixture) // Uses the production default-deny provider.
        let command = EngineeringCommand(executable: "git", arguments: ["commit", "-m", "must not launch"], timeoutMilliseconds: 2_000, reason: "Attempt an external-side-effect fixture") // Requests an approval-required command.
        let result = await runtime.execute(.runCommand(command)) // Executes centralized classification and approval handling.
        XCTAssertFalse(result.succeeded) // Confirms the operation was refused.
        XCTAssertEqual(result.risk, .externalSideEffect) // Confirms refusal retains the reason approval was required.
        XCTAssertEqual(result.errorCode, "approval_denied") // Confirms stable structured denial.
        XCTAssertNil(result.process) // Confirms no child PID was launched before authorization.
        let activePID = await runtime.activeProcessID() // Reads exact process ownership outside XCTest's autoclosure.
        XCTAssertNil(activePID) // Confirms the runtime owns no child after denial.
    } // Ends default-deny approval coverage.

    func testAllowOnceRunsOnlyTheExactApprovedExternalInvocation() async throws { // Verifies explicit approval permits one structurally safe command and returns real exit evidence.
        let fixture = try makeFixture(prefix: "AllowOnce") // Creates an isolated non-Git workspace so commit cannot mutate a real repository.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only test-owned state.
        let provider = RecordingApprovalProvider(decision: .allowOnce) // Creates an injected deterministic allow-once source.
        let runtime = try makeRuntime(fixture: fixture, approvalProvider: provider) // Connects the provider to the production runtime.
        let command = EngineeringCommand(executable: "git", arguments: ["commit", "-m", "temporary fixture"], timeoutMilliseconds: 2_000, reason: "Exercise one approved commit attempt") // Requests a commit only in the disposable non-repository.
        let result = await runtime.execute(.runCommand(command)) // Runs after the explicit allow-once decision.
        XCTAssertEqual(result.risk, .externalSideEffect) // Confirms the command remained approval-required.
        XCTAssertNotNil(result.process) // Confirms an exact child process was launched only after approval.
        XCTAssertEqual(result.errorCode, "nonzero_exit") // Confirms expected non-repository Git failure is normalized rather than hidden.
        let requests = await provider.requests() // Reads recorded approval prompts before XCTest assertions.
        XCTAssertEqual(requests.count, 1) // Confirms allow-once was requested exactly once.
        XCTAssertTrue(requests[0].exactCommand.contains("git commit")) // Confirms UI received the exact command structure.
        XCTAssertEqual(requests[0].workspacePath, fixture.rootURL.path) // Confirms UI received the exact authorized workspace.
        XCTAssertEqual(requests[0].reason, "Exercise one approved commit attempt") // Confirms UI received the bounded caller rationale.
    } // Ends allow-once approval coverage.

    func testApprovalTimeoutDeniesAndNeverLaunchesLateAllowDecision() async throws { // Verifies dismissed or slow approval cannot execute after its deadline.
        let fixture = try makeFixture(prefix: "ApprovalTimeout") // Creates an isolated non-Git workspace.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only test-owned state.
        let provider = DelayedAllowApprovalProvider(delayMilliseconds: 250) // Creates a provider slower than the configured deadline.
        let runtime = try makeRuntime(fixture: fixture, approvalProvider: provider, approvalTimeoutMilliseconds: 15) // Uses a short deterministic timeout.
        let command = EngineeringCommand(executable: "git", arguments: ["commit", "-m", "too late"], timeoutMilliseconds: 2_000, reason: "Verify timeout deny") // Requests approval-required work.
        let result = await runtime.execute(.runCommand(command)) // Races the provider against the safe deadline.
        XCTAssertFalse(result.succeeded) // Confirms timeout did not authorize execution.
        XCTAssertEqual(result.errorCode, "approval_timeout") // Confirms bounded timeout is distinct from an explicit denial.
        XCTAssertNil(result.process) // Confirms no child was launched.
        try await Task.sleep(nanoseconds: 300_000_000) // Allows the deliberately late provider answer to arrive.
        let activePID = await runtime.activeProcessID() // Checks process ownership after the late allow response.
        XCTAssertNil(activePID) // Confirms a late allow decision cannot launch stale work.
    } // Ends approval timeout coverage.

    func testCommandTimeoutTerminatesOnlyTheOwnedChild() async throws { // Verifies every command has a finite cleanup path and structured timeout result.
        let fixture = try makeFixture(prefix: "CommandTimeout") // Creates an isolated workspace and runtime directory.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only test-owned state.
        let runtime = try makeRuntime(fixture: fixture) // Creates the production runtime.
        let command = EngineeringCommand(executable: "sleep", arguments: ["5"], timeoutMilliseconds: 25, reason: "Exercise exact child timeout") // Requests a long diagnostic child with a short deadline.
        let started = DispatchTime.now().uptimeNanoseconds // Starts monotonic test timing.
        let result = await runtime.execute(.runCommand(command)) // Waits for timeout and exact child cleanup.
        let elapsedMilliseconds = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000) // Measures end-to-end timeout behavior.
        XCTAssertFalse(result.succeeded) // Confirms the command did not report normal completion.
        XCTAssertEqual(result.errorCode, "process_timeout") // Confirms structured timeout identity.
        XCTAssertLessThan(elapsedMilliseconds, 2_000) // Confirms the five-second child was stopped promptly.
        let activePID = await runtime.activeProcessID() // Reads ownership after the result.
        XCTAssertNil(activePID) // Confirms the runner released exact process ownership after cleanup.
    } // Ends command-timeout coverage.

    func testCancellationStopsOwnedChildAndPreservesUnrelatedProcess() async throws { // Verifies cancellation never uses generic process-name termination.
        let fixture = try makeFixture(prefix: "CommandCancellation") // Creates an isolated workspace and runtime directory.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only test-owned filesystem state.
        let unrelated = Process() // Creates a separate test-owned child outside EngineeringToolRuntime ownership.
        unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep") // Uses the same executable name to detect forbidden generic killing.
        unrelated.arguments = ["5"] // Keeps the unrelated fixture alive through runtime cancellation.
        try unrelated.run() // Starts the exact unrelated fixture directly.
        defer { // Guarantees cleanup of only the test-owned unrelated process.
            if unrelated.isRunning { unrelated.terminate() } // Stops the exact fixture if it remains active.
            unrelated.waitUntilExit() // Reaps the exact fixture without affecting other processes.
        } // Ends unrelated fixture cleanup.
        let runtime = try makeRuntime(fixture: fixture) // Creates the production runtime with separate exact ownership.
        let command = EngineeringCommand(executable: "sleep", arguments: ["5"], timeoutMilliseconds: 10_000, reason: "Exercise cooperative cancellation") // Requests a second same-name child owned by the runtime.
        let task = Task { await runtime.execute(.runCommand(command)) } // Starts execution asynchronously so the test can cancel it.
        var ownedPID: Int32? // Stores the exact runtime-owned child identity once launched.
        for _ in 0..<100 where ownedPID == nil { // Polls for at most one second without blocking a thread.
            ownedPID = await runtime.activeProcessID() // Reads only the exact runtime ownership state.
            if ownedPID == nil { try await Task.sleep(nanoseconds: 10_000_000) } // Briefly yields until Process.run publishes ownership.
        } // Ends bounded launch observation.
        XCTAssertNotNil(ownedPID) // Confirms the runtime child started before cancellation.
        task.cancel() // Cancels the owning Swift task.
        let result = await task.value // Awaits structured cancellation only after exact child exit.
        XCTAssertFalse(result.succeeded) // Confirms cancellation is not reported as normal completion.
        XCTAssertEqual(result.errorCode, "process_cancelled") // Confirms stable cooperative cancellation identity.
        if let ownedPID { XCTAssertEqual(Darwin.kill(ownedPID, 0), -1) } // Confirms the exact owned PID no longer exists after result delivery.
        XCTAssertTrue(unrelated.isRunning) // Confirms a same-name unrelated process remains alive.
        XCTAssertEqual(Darwin.kill(unrelated.processIdentifier, 0), 0) // Confirms the unrelated exact PID is still signalable.
    } // Ends exact-process cancellation isolation coverage.

    func testProcessOutputIsBoundedMalformedUTF8SafeAndSecretRedacted() async throws { // Verifies arbitrary command bytes cannot crash or flood model context.
        let fixture = try makeFixture(prefix: "OutputSafety") // Creates an isolated workspace and runtime directory.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only test-owned state.
        var limits = EngineeringWorkspaceLimits.standard // Starts from production defaults.
        limits.maximumProcessOutputBytes = 24 // Forces deterministic head/tail truncation.
        let runtime = try makeRuntime(fixture: fixture, limits: limits) // Creates the bounded production runtime.
        let longPayload = String(repeating: "A", count: 80) + " sk-abcdefghijklmnopqrstuvwxyz123456 " + String(repeating: "Z", count: 80) // Creates oversized output containing a deterministic fake token.
        let longResult = await runtime.execute(.runCommand(EngineeringCommand(executable: "printf", arguments: ["%s", longPayload], timeoutMilliseconds: 2_000, reason: "Exercise bounded output"))) // Emits exact bytes without a shell.
        XCTAssertTrue(longResult.succeeded) // Confirms the diagnostic process completed.
        XCTAssertTrue(longResult.process?.outputWasTruncated == true) // Confirms the bounded buffer reports omitted middle bytes.
        XCTAssertTrue(longResult.text?.contains("output truncated") == true) // Confirms model-visible output announces truncation.
        XCTAssertFalse(longResult.text?.contains("sk-abcdefghijklmnopqrstuvwxyz123456") == true) // Confirms retained fake tokens are conservatively redacted when present.
        let malformedResult = await runtime.execute(.runCommand(EngineeringCommand(executable: "printf", arguments: ["%b", "\\377invalid"], timeoutMilliseconds: 2_000, reason: "Exercise malformed UTF-8"))) // Emits one invalid UTF-8 byte followed by text.
        XCTAssertTrue(malformedResult.succeeded) // Confirms malformed output never crashes process collection.
        XCTAssertTrue(malformedResult.text?.contains("invalid") == true) // Confirms decodable trailing diagnostics remain usable.
        XCTAssertTrue(malformedResult.text?.contains("�") == true) // Confirms undecodable bytes are represented safely.
    } // Ends bounded malformed-output and redaction coverage.

    func testSanitizedEnvironmentContainsNoInheritedCredentials() { // Verifies command processes receive an explicit allowlist instead of the app environment.
        let runtimeURL = FileManager.default.temporaryDirectory.appendingPathComponent("AutoMLXStudioTests-Environment-\(UUID().uuidString)", isDirectory: true) // Creates a unique app-owned path identity without touching the real workspace.
        let environment = EngineeringSanitizedEnvironment.make(runtimeDirectoryURL: runtimeURL) // Builds the exact production child environment.
        XCTAssertEqual(environment["HOME"], runtimeURL.appendingPathComponent("home", isDirectory: true).path) // Confirms children cannot read the user's real HOME by default.
        XCTAssertEqual(environment["TMPDIR"], runtimeURL.appendingPathComponent("tmp", isDirectory: true).path) // Confirms temporary paths are app-owned.
        XCTAssertEqual(environment["GIT_TERMINAL_PROMPT"], "0") // Confirms commands cannot hang on credential prompts.
        XCTAssertNil(environment["SSH_AUTH_SOCK"]) // Confirms SSH agent credentials are not inherited.
        XCTAssertNil(environment["OPENAI_API_KEY"]) // Confirms common API keys are not inherited.
        XCTAssertNil(environment["AWS_SECRET_ACCESS_KEY"]) // Confirms cloud credentials are not inherited.
        XCTAssertLessThanOrEqual(environment.count, 10) // Confirms the allowlist remains intentionally small and reviewable.
    } // Ends sanitized environment coverage.

    func testRuntimeRejectsEscapingWorkingDirectoryBeforeProcessLaunch() async throws { // Verifies command cwd uses the same canonical boundary as file tools.
        let fixture = try makeFixture(prefix: "CommandCWDContainment") // Creates an isolated workspace and outside sibling.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only test-owned state.
        let runtime = try makeRuntime(fixture: fixture) // Creates the production runtime.
        let command = EngineeringCommand(executable: "pwd", workingDirectory: "../", timeoutMilliseconds: 2_000, reason: "Attempt cwd escape") // Requests a parent traversal cwd.
        let result = await runtime.execute(.runCommand(command)) // Executes centralized validation.
        XCTAssertFalse(result.succeeded) // Confirms no command ran outside authority.
        XCTAssertEqual(result.errorCode, "invalid_relative_path") // Confirms workspace containment rejected cwd before launch.
        XCTAssertNil(result.process) // Confirms no child PID was created.
    } // Ends command cwd containment coverage.

    func testTypedGitStatusRunsOnlyInsideTemporaryRepository() async throws { // Verifies the read-only Git convenience tool uses the authorized Mac workspace.
        let fixture = try makeFixture(prefix: "GitStatus") // Creates an isolated temporary workspace.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only the test-owned repository.
        try runFixtureProcess(executable: "/usr/bin/git", arguments: ["init", "--quiet"], workingDirectoryURL: fixture.rootURL) // Initializes Git directly only inside the disposable fixture.
        try Data("untracked".utf8).write(to: fixture.rootURL.appendingPathComponent("Visible.txt")) // Creates one deterministic untracked file.
        let runtime = try makeRuntime(fixture: fixture) // Creates the production runtime.
        let result = await runtime.execute(.gitStatus) // Invokes the typed read-only Git tool.
        XCTAssertTrue(result.succeeded) // Confirms Git status completed normally.
        XCTAssertEqual(result.risk, .safeReadOnly) // Confirms no approval was required.
        XCTAssertTrue(result.text?.contains("Visible.txt") == true) // Confirms output came from the authorized temporary workspace.
        XCTAssertNotNil(result.process?.processID) // Confirms exact child identity is retained in structured evidence.
    } // Ends typed Git status coverage.

    private func makeFixture(prefix: String) throws -> (containerURL: URL, rootURL: URL, historyURL: URL, runtimeURL: URL) { // Creates one exact test-owned workspace, history, and process cache tree.
        let containerURL = FileManager.default.temporaryDirectory.appendingPathComponent("AutoMLXStudioTests-\(prefix)-\(UUID().uuidString)", isDirectory: true) // Uses a collision-resistant disposable container.
        let rootURL = containerURL.appendingPathComponent("workspace", isDirectory: true) // Separates live user-like files from app metadata.
        let historyURL = containerURL.appendingPathComponent("history", isDirectory: true) // Stores only this fixture's app-owned changes.
        let runtimeURL = containerURL.appendingPathComponent("runtime", isDirectory: true) // Stores only this fixture's sanitized HOME and TMPDIR.
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true) // Creates the explicitly authorized temporary root.
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true) // Creates isolated transaction storage.
        return (containerURL, rootURL, historyURL, runtimeURL) // Returns exact construction and cleanup identities.
    } // Ends runtime fixture creation.

    private func makeRuntime(fixture: (containerURL: URL, rootURL: URL, historyURL: URL, runtimeURL: URL), limits: EngineeringWorkspaceLimits = .standard, approvalProvider: any EngineeringApprovalProviding = DenyEngineeringApprovalProvider(), approvalTimeoutMilliseconds: Int = 1_000) throws -> EngineeringToolRuntime { // Builds production actors over one disposable fixture.
        let workspace = try EngineeringWorkspace(rootURL: fixture.rootURL, historyDirectoryURL: fixture.historyURL, limits: limits) // Opens only the explicit temporary authorization.
        return EngineeringToolRuntime(workspace: workspace, approvalProvider: approvalProvider, approvalTimeoutMilliseconds: approvalTimeoutMilliseconds, runtimeDirectoryURL: fixture.runtimeURL) // Connects isolated workspace, approval, and process storage.
    } // Ends production runtime fixture construction.

    private func runFixtureProcess(executable: String, arguments: [String], workingDirectoryURL: URL) throws { // Runs one direct synchronous setup command only inside a disposable fixture.
        let process = Process() // Creates the exact test-owned child.
        process.executableURL = URL(fileURLWithPath: executable) // Uses a fixed executable path without a shell.
        process.arguments = arguments // Preserves deterministic setup argument boundaries.
        process.currentDirectoryURL = workingDirectoryURL // Constrains setup effects to the disposable workspace.
        process.standardOutput = FileHandle.nullDevice // Discards bounded known fixture output.
        process.standardError = FileHandle.nullDevice // Discards bounded known fixture diagnostics.
        try process.run() // Starts the direct setup command.
        process.waitUntilExit() // Reaps the exact child before the test continues.
        XCTAssertEqual(process.terminationStatus, 0) // Requires deterministic fixture setup success.
    } // Ends direct fixture-process setup.
} // Ends Engineering Tool Runtime coverage.

private actor RecordingApprovalProvider: EngineeringApprovalProviding { // Records prompts and returns one deterministic test decision.
    private let configuredDecision: EngineeringApprovalDecision // Stores the exact decision applied to every request.
    private var recordedRequests: [EngineeringApprovalRequest] = [] // Stores bounded typed prompt evidence in actor isolation.

    init(decision: EngineeringApprovalDecision) { // Creates one deterministic approval source.
        self.configuredDecision = decision // Retains the explicit test choice.
    } // Ends provider construction.

    func decision(for request: EngineeringApprovalRequest) async -> EngineeringApprovalDecision { // Records and answers one nonblocking request.
        recordedRequests.append(request) // Retains exact UI metadata for assertions.
        return configuredDecision // Returns only the configured allow-once or deny choice.
    } // Ends approval response.

    func requests() -> [EngineeringApprovalRequest] { // Returns an immutable prompt snapshot.
        recordedRequests // Exposes recorded requests safely through actor isolation.
    } // Ends prompt inspection.
} // Ends recording approval fixture.

private struct DelayedAllowApprovalProvider: EngineeringApprovalProviding { // Simulates a UI response arriving after the runtime deadline.
    let delayMilliseconds: Int // Stores a deterministic delay longer than the tested timeout.

    func decision(for request: EngineeringApprovalRequest) async -> EngineeringApprovalDecision { // Waits cooperatively before returning allow-once.
        try? await Task.sleep(nanoseconds: UInt64(max(1, delayMilliseconds)) * 1_000_000) // Delays without blocking a host thread.
        return .allowOnce // Returns a late authorization that the single-resolution gate must ignore.
    } // Ends delayed approval response.
} // Ends delayed approval fixture.
