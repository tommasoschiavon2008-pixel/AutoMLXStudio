import Darwin // Supplies POSIX realpath for a genuine macOS `/var` canonicalization assertion.
import Foundation // Supplies isolated disposable paths, harmless marker bytes, and symlink fixtures.
import XCTest // Supplies production-boundary assertions without replacing the macOS sandbox with mocks.
@testable import AutoMLXStudio // Exposes the real Engineering workspace, approval, command, and process implementation.

final class EngineeringCommandContainmentTests: XCTestCase { // Exercises actual sandbox-exec inheritance on harmless temporary fixtures.
    func testDirectFileBoundaryAndCanonicalSymlinkHandling() async throws { // Covers valid reads, traversal, absolute paths, symlinks, and macOS temp aliases.
        let fixture = try Fixture() // Creates only this test's disposable workspace and sibling marker.
        defer { fixture.remove() } // Removes only the exact generated fixture after assertions.
        let workspace = try EngineeringWorkspace(rootURL: fixture.workspaceURL, historyDirectoryURL: fixture.historyURL) // Opens the same canonical authority as production.
        let valid = try await workspace.readFile(relativePath: "inside.txt") // Reads a normal contained text file through the real direct tool boundary.
        XCTAssertTrue(valid.text.contains("AUTOMLX_INSIDE_BOUNDARY_MARKER")) // Confirms legitimate workspace inspection still succeeds.
        await assertReadDenied(workspace, path: "../outside-marker.txt") // Requires lexical parent traversal to be rejected.
        await assertReadDenied(workspace, path: fixture.outsideURL.path) // Requires an absolute outside path to be rejected.
        await assertReadDenied(workspace, path: "outside-link.txt") // Requires a contained symlink pointing outside to be rejected.
        XCTAssertNotEqual(fixture.workspaceURL.path, fixture.workspaceURL.path.withCString { source in guard let result = realpath(source, nil) else { return fixture.workspaceURL.path }; defer { free(result) }; return String(cString: result) }) // Confirms this macOS temporary fixture exercises `/var` versus `/private/var` canonical spelling.
    } // Ends direct workspace security coverage.

    func testRealSandboxAllowsNormalCommandAndWorkspaceMake() async throws { // Proves OS confinement does not disable ordinary local commands or Makefiles.
        let fixture = try Fixture() // Creates an isolated Makefile and local marker.
        defer { fixture.remove() } // Removes only generated test state.
        let provider = ContainmentApprovalProvider(decision: .allowOnce) // Grants exact build invocations once for this test.
        let runtime = try fixture.runtime(provider: provider) // Creates the real production command path with mandatory approval.
        let pwd = await runtime.execute(.runCommand(EngineeringCommand(executable: "pwd", timeoutMilliseconds: 5_000, reason: "Inspect contained current directory"))) // Exercises a safe read command under sandbox-exec.
        XCTAssertTrue(pwd.succeeded, "Contained pwd: \(pwd)") // Requires ordinary child process launch to work.
        let make = await runtime.execute(.runCommand(EngineeringCommand(executable: "make", arguments: ["inside-probe"], timeoutMilliseconds: 10_000, reason: "Read only a local fixture"))) // Runs the actual Makefile recipe and shell child.
        XCTAssertTrue(make.succeeded, "Contained make: \(make)") // Requires workspace-local build execution to succeed.
        XCTAssertTrue(make.text?.contains("AUTOMLX_INSIDE_BOUNDARY_MARKER") == true) // Confirms the child reached the intended workspace file.
        let approvalCount = await provider.count() // Reads the actor-owned number of one-shot decisions.
        XCTAssertEqual(approvalCount, 1) // Confirms make received one exact approval request.
    } // Ends legitimate subprocess usability coverage.

    func testRealSandboxBlocksRelativeAbsoluteSymlinkScriptAndNestedEscapes() async throws { // Tests real OS file denial through five indirect process routes.
        let fixture = try Fixture() // Creates the outside-only marker, link, scripts, and Makefile.
        defer { fixture.remove() } // Removes only the generated fixture.
        let provider = ContainmentApprovalProvider(decision: .allowOnce) // Exercises real approved commands rather than pre-approval rejection.
        let runtime = try fixture.runtime(provider: provider) // Uses the production Engineering runtime and process runner.
        for target in ["boundary-probe", "absolute-probe", "symlink-probe", "script-probe", "nested-probe", "environment-probe", "data-volume-probe", "nested-sandbox-probe", "temp-probe", "hardlink-probe"] { // Covers traversal, descendants, link aliases, environment redirects, data-volume aliases, and attempted re-sandboxing.
            let result = await runtime.execute(.runCommand(EngineeringCommand(executable: "make", arguments: [target], timeoutMilliseconds: 10_000, reason: "Harmless containment test \(target)"))) // Invokes one actual sandboxed Makefile recipe.
            XCTAssertFalse(result.succeeded, "Escape target unexpectedly succeeded: \(target), \(result)") // Requires every attempt to fail at the kernel boundary.
            XCTAssertFalse(result.text?.contains("AUTOMLX_OUTSIDE_BOUNDARY_MARKER") == true, "Outside marker escaped through \(target)") // Requires outside-only bytes never to reach the agent.
            XCTAssertEqual(result.errorCode, "nonzero_exit", "Unexpected failure type for \(target): \(result)") // Confirms a process ran and the access itself was denied.
        } // Ends indirect access routes.
        let approvalCount = await provider.count() // Reads the actor-owned number of one-shot decisions.
        XCTAssertEqual(approvalCount, 10) // Confirms every harmless process was independently approved once.
    } // Ends actual subprocess escape regression coverage.

    func testRealSandboxBlocksOutsideWriteAndDenyNeverLaunches() async throws { // Distinguishes kernel filesystem denial from human approval denial.
        let fixture = try Fixture() // Creates isolated inside and outside write targets.
        defer { fixture.remove() } // Removes only generated test state.
        let allow = ContainmentApprovalProvider(decision: .allowOnce) // Grants one command without widening its workspace boundary.
        let allowedRuntime = try fixture.runtime(provider: allow) // Uses the production sandbox with one-shot approval.
        let outsideWrite = await allowedRuntime.execute(.runCommand(EngineeringCommand(executable: "make", arguments: ["outside-write"], timeoutMilliseconds: 10_000, reason: "Attempt harmless sibling write"))) // Exercises an approved shell child writing outside.
        XCTAssertFalse(outsideWrite.succeeded, "Outside write unexpectedly succeeded: \(outsideWrite)") // Requires filesystem containment after approval.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.outsideWriteURL.path)) // Requires no outside mutation.
        let deny = ContainmentApprovalProvider(decision: .deny) // Configures a separate explicit Deny choice.
        let deniedRuntime = try fixture.runtime(provider: deny) // Uses the same workspace with a different one-shot provider.
        let denied = await deniedRuntime.execute(.runCommand(EngineeringCommand(executable: "make", arguments: ["inside-write"], timeoutMilliseconds: 10_000, reason: "Confirm Deny prevents local write"))) // Requests a legitimate mutation that the human rejects.
        XCTAssertFalse(denied.succeeded) // Requires Deny to stop the operation.
        XCTAssertEqual(denied.errorCode, "approval_denied") // Distinguishes human refusal from kernel sandbox refusal.
        XCTAssertNil(denied.process) // Confirms no child process launched after Deny.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.insideWriteURL.path)) // Requires unchanged workspace contents.
    } // Ends outside-write and Deny coverage.

    func testAllowOnceRequiresFreshApprovalForNextCommand() async throws { // Prevents one approval from becoming a persistent command or filesystem grant.
        let fixture = try Fixture() // Creates two harmless independent local output targets.
        defer { fixture.remove() } // Removes only test-owned state.
        let provider = ContainmentApprovalProvider(decision: .allowOnce) // Records each exact approval request.
        let runtime = try fixture.runtime(provider: provider) // Uses production per-mutation approval behavior.
        let first = await runtime.execute(.runCommand(EngineeringCommand(executable: "make", arguments: ["inside-write"], timeoutMilliseconds: 10_000, reason: "First local write"))) // Authorizes one workspace-local output.
        XCTAssertTrue(first.succeeded, "First approved write: \(first)") // Requires the legitimate write to work.
        let second = await runtime.execute(.runCommand(EngineeringCommand(executable: "make", arguments: ["second-write"], timeoutMilliseconds: 10_000, reason: "Second local write"))) // Requests a separate action after first approval is consumed.
        XCTAssertTrue(second.succeeded, "Second approved write: \(second)") // Requires another legitimate operation to work after a new decision.
        let approvalCount = await provider.count() // Reads the actor-owned number of one-shot decisions.
        XCTAssertEqual(approvalCount, 2) // Requires two distinct approval requests, not sticky blanket authority.
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.insideWriteURL.path)) // Confirms first contained output exists.
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.secondWriteURL.path)) // Confirms second contained output exists.
    } // Ends one-shot approval regression coverage.

    func testSwiftPackageBuildAndTestsRemainUsableInsideWorkspace() async throws { // Exercises a real compiler and SwiftPM child graph under the OS sandbox.
        let fixture = try Fixture() // Creates an isolated development workspace.
        defer { fixture.remove() } // Removes only the exact test-owned project and output.
        let sourceDirectory = fixture.workspaceURL.appendingPathComponent("Sources/Tiny", isDirectory: true) // Names the contained source target.
        let testsDirectory = fixture.workspaceURL.appendingPathComponent("Tests/TinyTests", isDirectory: true) // Names the contained XCTest target.
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true) // Creates only workspace-local source directories.
        try FileManager.default.createDirectory(at: testsDirectory, withIntermediateDirectories: true) // Creates only workspace-local test directories.
        try Data("// swift-tools-version: 5.10\nimport PackageDescription // Describes the tiny isolated Swift package.\nlet package = Package(name: \"Tiny\", products: [.library(name: \"Tiny\", targets: [\"Tiny\"])], targets: [.target(name: \"Tiny\"), .testTarget(name: \"TinyTests\", dependencies: [\"Tiny\"])]) // Keeps all build artifacts in this workspace.\n".utf8).write(to: fixture.workspaceURL.appendingPathComponent("Package.swift")) // Publishes the tiny package manifest inside the authorization.
        try Data("public func answer() -> Int { 42 } // Returns one deterministic local build value.\n".utf8).write(to: sourceDirectory.appendingPathComponent("Tiny.swift")) // Publishes the contained library source.
        try Data("import XCTest // Supplies the standard test assertion.\nimport Tiny // Imports only the local package target.\nfinal class TinyTests: XCTestCase { func testAnswer() { XCTAssertEqual(answer(), 42) } } // Verifies the tiny local function.\n".utf8).write(to: testsDirectory.appendingPathComponent("TinyTests.swift")) // Publishes the contained XCTest source.
        let provider = ContainmentApprovalProvider(decision: .allowOnce) // Approves exactly this build-and-test invocation.
        let runtime = try fixture.runtime(provider: provider) // Uses the real product sandbox and timeout.
        let result = await runtime.execute(.runCommand(EngineeringCommand(executable: "swift", arguments: ["test"], timeoutMilliseconds: 180_000, reason: "Build and test the isolated Swift fixture"))) // Invokes actual SwiftPM and its compiler/test descendants.
        XCTAssertTrue(result.succeeded, "Sandboxed swift test: \(result)") // Requires a real compile and test pass without reading arbitrary user files.
        XCTAssertTrue(result.text?.contains("Executed 1 test") == true || result.text?.contains("1 test passed") == true, "Missing test execution evidence: \(result)") // Requires test execution evidence rather than command startup alone.
    } // Ends legitimate Swift build-and-test regression coverage.

    func testStopAndTimeoutTerminateChildAndGrandchildWithoutTouchingOtherProcesses() async throws { // Exercises real signal-resistant descendants under both terminal conditions.
        let unrelated = EngineeringOwnedProcess() // Creates a separately owned harmless control group without Foundation run-loop waits.
        unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep") // Uses a deterministic system process that is not part of Engineering.
        unrelated.currentDirectoryURL = FileManager.default.temporaryDirectory // Supplies a valid test-only cwd without workspace authority.
        unrelated.arguments = ["30"] // Keeps the control alive during the bounded test.
        try unrelated.run() // Starts the independent control group.
        defer { unrelated.forceTerminate() } // Cleans up only this test's exact control group without blocking the cooperative executor.
        for timedOut in [false, true] { // Separately verifies explicit Stop and automatic deadline cleanup.
            let fixture = try Fixture() // Creates a distinct workspace for each lifecycle case.
            defer { fixture.remove() } // Removes only the completed case's disposable files.
            let runtime = try fixture.runtime(provider: ContainmentApprovalProvider(decision: .allowOnce)) // Exercises real approval, sandbox, and process ownership.
            let task = Task { await runtime.execute(.runCommand(EngineeringCommand(executable: "make", arguments: ["process-tree"], timeoutMilliseconds: timedOut ? 1_500 : 10_000, reason: "Test bounded process-tree cleanup"))) } // Starts a shell child and signal-resistant grandchild.
            let child = try await awaitPID(in: fixture.workspaceURL.appendingPathComponent("child.pid")) // Waits for evidence that the child really launched.
            let grandchild = try await awaitPID(in: fixture.workspaceURL.appendingPathComponent("grandchild.pid")) // Waits for evidence that the nested child really launched.
            if !timedOut { await runtime.cancel() } // Exercises the product Stop path rather than terminating the fixture from XCTest.
            let result = await task.value // Requires command completion after owned-group cleanup.
            XCTAssertFalse(result.succeeded) // Neither cancellation nor timeout may be reported as success.
            XCTAssertEqual(result.errorCode, timedOut ? "process_timeout" : "process_cancelled") // Preserves the terminal cause through the runtime result.
            await assertProcessGone(child) // Requires the direct shell child to have stopped.
            await assertProcessGone(grandchild) // Requires the signal-resistant grandchild to have stopped.
            XCTAssertTrue(unrelated.isRunning) // Proves group signals never target a generic process name or the app's group.
        } // Ends both lifecycle scenarios.
    } // Ends actual process-tree Stop and timeout regression.

    func testSuccessfulLeaderExitCleansUpBackgroundChild() async throws { // Proves a completed make command cannot leave a same-group orphan running.
        let fixture = try Fixture() // Creates one disposable orphan-test workspace.
        defer { fixture.remove() } // Removes only test-owned files.
        let runtime = try fixture.runtime(provider: ContainmentApprovalProvider(decision: .allowOnce)) // Builds the actual contained process path.
        let result = await runtime.execute(.runCommand(EngineeringCommand(executable: "make", arguments: ["background-child"], timeoutMilliseconds: 5_000, reason: "Test normal-exit orphan cleanup"))) // Lets make return while a shell child still owns the pipe.
        XCTAssertTrue(result.succeeded, "Normal leader exit: \(result)") // Preserves the legitimate leader's successful result.
        let child = try await awaitPID(in: fixture.workspaceURL.appendingPathComponent("background.pid")) // Reads the actual launched background PID.
        await assertProcessGone(child) // Requires cleanup even though no user cancellation occurred.
        XCTAssertLessThan(result.durationMilliseconds, 4_000) // Detects the old unbounded readDataToEndOfFile hang.
    } // Ends normal-exit orphan cleanup regression.

    private func awaitPID(in url: URL) async throws -> Int32 { // Awaits a child-created PID file with a finite deadline.
        for _ in 0..<100 { // Bounds fixture startup observation to two seconds.
            if let text = try? String(contentsOf: url, encoding: .utf8), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 { return pid } // Returns only a valid recorded process identity.
            try await Task.sleep(nanoseconds: 20_000_000) // Allows the child to start without blocking the test executor.
        } // Ends bounded PID observation.
        throw NSError(domain: "ContainmentFixtureMissingPID", code: 1) // Fails explicitly rather than silently skipping physical process assertions.
    } // Ends PID evidence collection.

    private func assertProcessGone(_ pid: Int32) async { // Allows macOS a bounded interval to reap a killed reparented child.
        for _ in 0..<100 { // Bounds orphan-reaping observation to two seconds.
            if Darwin.kill(pid, 0) == -1 && errno == ESRCH { return } // Accepts only an absent process rather than an unverified signal request.
            try? await Task.sleep(nanoseconds: 20_000_000) // Yields while launchd reaps any terminated orphan.
        } // Ends bounded process-exit observation.
        XCTFail("Owned child still exists after cleanup: \(pid)") // Records a concrete lingering-process failure.
    } // Ends child cleanup assertion.

    func testDescriptorBoundaryRejectsParentReplacementAfterCanonicalization() throws { // Deterministically reproduces a symlink substitution between path validation and content access.
        let fixture = try Fixture() // Creates an isolated workspace with harmless outside data.
        defer { fixture.remove() } // Removes only this test-owned namespace.
        let directory = fixture.workspaceURL.appendingPathComponent("racing", isDirectory: true) // Names a previously legitimate contained parent.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) // Establishes an ordinary directory before the simulated validation.
        let validatedTarget = directory.appendingPathComponent("outside-marker.txt") // Captures the canonical target that a caller would retain after checking the parent.
        try FileManager.default.removeItem(at: directory) // Removes only the empty test-owned parent to simulate a concurrent command.
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: fixture.containerURL) // Replaces the validated parent with a sibling-pointing link before the actual content operation.
        let access = EngineeringSecureFileAccess(rootURL: fixture.workspaceURL) // Uses the production final content-access boundary independently of earlier canonicalization.
        XCTAssertThrowsError(try access.read(validatedTarget, maximumBytes: 1_024)) // Refuses outside reads even when the previously validated string still looks contained.
        XCTAssertThrowsError(try access.write(Data("BAD".utf8), to: validatedTarget, createOnly: false)) // Refuses outside atomic replacements through the racing parent.
        XCTAssertThrowsError(try access.remove(validatedTarget)) // Refuses outside rollback deletion through the racing parent.
        XCTAssertEqual(try String(contentsOf: fixture.outsideURL, encoding: .utf8), "AUTOMLX_OUTSIDE_BOUNDARY_MARKER\n") // Proves every rejected operation left outside bytes unchanged.
    } // Ends deterministic direct-tool race regression.

    func testDescriptorBoundaryRejectsConcurrentDirectorySymlinkSwaps() throws { // Exercises real simultaneous parent replacement during direct reads and writes.
        let fixture = try Fixture() // Owns every path used by the concurrent race fixture.
        defer { fixture.remove() } // Removes only the exact disposable fixture after both threads finish.
        let racing = fixture.workspaceURL.appendingPathComponent("racing", isDirectory: true) // Names the path repeatedly opened by the secure file helper.
        let alternate = fixture.workspaceURL.appendingPathComponent("alternate", isDirectory: true) // Holds the other directory entry during atomic exchanges.
        let outsideTarget = fixture.containerURL.appendingPathComponent("race-read.txt") // Places distinctive content outside the authorized workspace.
        let outsideWrite = fixture.containerURL.appendingPathComponent("race-write.txt") // Names an outside file that must never be replaced.
        try FileManager.default.createDirectory(at: racing, withIntermediateDirectories: false) // Establishes the legitimate contained directory.
        try Data("INSIDE_RACE_MARKER".utf8).write(to: racing.appendingPathComponent("race-read.txt")) // Provides a permitted read result.
        try FileManager.default.createSymbolicLink(at: alternate, withDestinationURL: fixture.containerURL) // Establishes an outside-pointing path component beside the real directory.
        try Data("OUTSIDE_RACE_MARKER".utf8).write(to: outsideTarget) // Provides bytes that must never be returned by Engineering.
        try Data("OUTSIDE_WRITE_UNCHANGED".utf8).write(to: outsideWrite) // Provides an outside destination whose original bytes must survive.
        XCTAssertEqual(renameatx_np(AT_FDCWD, racing.path, AT_FDCWD, alternate.path, UInt32(RENAME_SWAP)), 0) // Verifies this filesystem supports an actual atomic directory/symlink exchange.
        XCTAssertEqual(renameatx_np(AT_FDCWD, racing.path, AT_FDCWD, alternate.path, UInt32(RENAME_SWAP)), 0) // Restores the legitimate entry before concurrent work starts.
        let stop = DispatchSemaphore(value: 0) // Coordinates termination without a shared mutable Swift variable.
        let finished = DispatchGroup() // Ensures all swapping ends before fixture teardown.
        finished.enter() // Records the one concurrent path-replacement worker.
        DispatchQueue.global(qos: .userInitiated).async { // Races atomic name swaps against the direct filesystem operations below.
            defer { finished.leave() } // Guarantees teardown waits for the worker even after an error.
            while stop.wait(timeout: .now()) == .timedOut { // Continues swapping until the main test signals completion.
                _ = renameatx_np(AT_FDCWD, racing.path, AT_FDCWD, alternate.path, UInt32(RENAME_SWAP)) // Changes which actual object the lexical parent names atomically.
            } // Ends the live replacement window.
        } // Ends the competing filesystem worker.
        let access = EngineeringSecureFileAccess(rootURL: fixture.workspaceURL) // Exercises the exact descriptor-based production boundary.
        for _ in 0..<200 { // Samples both reads and writes repeatedly while the competing thread is active.
            if let bytes = try? access.read(racing.appendingPathComponent("race-read.txt"), maximumBytes: 1_024) { XCTAssertEqual(String(data: bytes, encoding: .utf8), "INSIDE_RACE_MARKER") } // Accepts only the actual contained file, never outside bytes.
            try? access.write(Data("INSIDE_WRITE".utf8), to: racing.appendingPathComponent("race-write.txt"), createOnly: false) // Permits a contained replacement or a safe race refusal, never an outside write.
        } // Ends bounded concurrent probes.
        stop.signal() // Tells the worker to stop changing path identities.
        finished.wait() // Prevents a worker from outliving its fixture or assertions.
        XCTAssertEqual(try String(contentsOf: outsideWrite, encoding: .utf8), "OUTSIDE_WRITE_UNCHANGED") // Proves every attempted write left outside data unchanged.
        XCTAssertEqual(try String(contentsOf: outsideTarget, encoding: .utf8), "OUTSIDE_RACE_MARKER") // Proves the outside source was not modified.
    } // Ends actual concurrent TOCTOU regression.

    func testMissingSandboxAuthorityFailsBeforeLaunching() throws { // Exercises fail-closed setup independently of tool approval.
        let fixture = try Fixture() // Creates only the harmless workspace fixture.
        defer { fixture.remove() } // Removes only test-owned files.
        XCTAssertThrowsError(try EngineeringCommandSandbox.prepare(executableURL: URL(fileURLWithPath: "/bin/echo"), arguments: ["must-not-run"], workspaceRootURL: fixture.workspaceURL, runtimeDirectoryURL: fixture.containerURL.appendingPathComponent("missing-runtime"), environment: [:])) // Refuses launch when the private runtime authority cannot be canonicalized.
        XCTAssertThrowsError(try EngineeringCommandSandbox.makeProfile(workspacePath: "/invalid\npath", runtimePath: "/tmp/private-runtime", developerPath: "/Applications/Xcode.app/Contents/Developer")) // Refuses profile injection through an unrepresentable authority path.
    } // Ends fail-closed setup regression.

    private func assertReadDenied(_ workspace: EngineeringWorkspace, path: String) async { // Reduces repeated direct-file rejection assertions.
        do { _ = try await workspace.readFile(relativePath: path); XCTFail("Outside direct read unexpectedly succeeded: \(path)") } // Fails if a direct tool returned outside content.
        catch { XCTAssertTrue(error is EngineeringRuntimeError, "Unexpected direct-file error: \(error)") } // Requires a typed workspace boundary refusal.
    } // Ends direct-file assertion helper.
} // Ends real Engineering command containment test class.

private actor ContainmentApprovalProvider: EngineeringApprovalProviding { // Records exact one-shot decisions without mocking process containment.
    private let decisionToReturn: EngineeringApprovalDecision // Stores only this fixture's deterministic human decision.
    private var requests = 0 // Counts separate approval prompts for scope assertions.
    init(decision: EngineeringApprovalDecision) { decisionToReturn = decision } // Creates one fixed test decision.
    func decision(for request: EngineeringApprovalRequest) async -> EngineeringApprovalDecision { requests += 1; return decisionToReturn } // Records every real runtime approval request.
    func count() -> Int { requests } // Returns the observed prompt count to XCTest.
} // Ends deterministic approval fixture.

private struct Fixture { // Owns one disposable workspace, harmless outside marker, and private runtime.
    let containerURL: URL // Names the exact removable test-owned parent.
    let workspaceURL: URL // Names the only directory authorized to Engineering.
    let historyURL: URL // Names isolated app-owned change history.
    let runtimeURL: URL // Names isolated sanitized HOME and TMPDIR storage.
    let outsideURL: URL // Names the harmless marker deliberately outside workspace.
    let outsideWriteURL: URL // Names a harmless outside write target that must remain absent.
    let insideWriteURL: URL // Names the first legitimate workspace-local output.
    let secondWriteURL: URL // Names the second legitimate workspace-local output.

    init() throws { // Constructs one collision-resistant fixture without touching unrelated files.
        let manager = FileManager.default // Uses the local filesystem only for test-owned paths.
        containerURL = manager.temporaryDirectory.appendingPathComponent("AutoMLXContainmentTests-\(UUID().uuidString)", isDirectory: true) // Creates one unique disposable namespace.
        workspaceURL = containerURL.appendingPathComponent("workspace", isDirectory: true) // Separates authorized work from sibling data.
        historyURL = containerURL.appendingPathComponent("history", isDirectory: true) // Separates direct-tool history from project files.
        runtimeURL = containerURL.appendingPathComponent("runtime", isDirectory: true) // Separates command HOME/TMPDIR from user data.
        outsideURL = containerURL.appendingPathComponent("outside-marker.txt") // Places the marker just outside W.
        outsideWriteURL = containerURL.appendingPathComponent("outside-write.txt") // Names a sibling write destination that must never be created.
        insideWriteURL = workspaceURL.appendingPathComponent("inside-output.txt") // Names one legitimate output target.
        secondWriteURL = workspaceURL.appendingPathComponent("second-output.txt") // Names another legitimate output target.
        try manager.createDirectory(at: workspaceURL, withIntermediateDirectories: true) // Creates only the selected workspace.
        try Data("AUTOMLX_OUTSIDE_BOUNDARY_MARKER\n".utf8).write(to: outsideURL) // Writes only an innocent unique outside marker.
        try Data("AUTOMLX_INSIDE_BOUNDARY_MARKER\n".utf8).write(to: workspaceURL.appendingPathComponent("inside.txt")) // Writes the legitimate local marker.
        try manager.createSymbolicLink(at: workspaceURL.appendingPathComponent("outside-link.txt"), withDestinationURL: outsideURL) // Creates an inside-to-outside symlink for escape testing.
        try Data("#!/bin/sh\n/bin/cat ../outside-marker.txt\n".utf8).write(to: workspaceURL.appendingPathComponent("script.sh")) // Creates a harmless script that tries relative escape.
        try Data("#!/bin/sh\n/bin/sh nested-inner.sh\n".utf8).write(to: workspaceURL.appendingPathComponent("nested.sh")) // Creates a parent shell that spawns another child.
        try Data("#!/bin/sh\n/bin/cat ../outside-marker.txt\n".utf8).write(to: workspaceURL.appendingPathComponent("nested-inner.sh")) // Creates the grandchild marker read.
        try Data("#!/bin/sh\ntrap '' TERM\n/bin/sh -c 'trap \"\" TERM; echo $$ > grandchild.pid; while :; do /bin/sleep 1; done' &\necho $$ > child.pid\nwait\n".utf8).write(to: workspaceURL.appendingPathComponent("process-tree.sh")) // Creates signal-resistant child/grandchild fixtures with recorded identities.
        let makefile = [ // Declares only harmless local and outside-marker probes.
            "inside-probe:\n\t@/bin/cat inside.txt", // Validates legitimate Makefile reads.
            "boundary-probe:\n\t@/bin/cat ../outside-marker.txt", // Reproduces the original relative escape class.
            "absolute-probe:\n\t@/bin/cat \(outsideURL.path)", // Tries an absolute outside path hidden in a Makefile recipe.
            "symlink-probe:\n\t@/bin/cat outside-link.txt", // Tries a workspace symlink that resolves outside.
            "script-probe:\n\t@/bin/sh script.sh", // Invokes a workspace-local script that attempts outside access.
            "nested-probe:\n\t@/bin/sh nested.sh", // Invokes a script whose child attempts outside access.
            "environment-probe:\n\t@OUTSIDE=\(outsideURL.path) /bin/sh -c '/bin/cat \"$$OUTSIDE\"'", // Attempts to smuggle an outside filename through a child environment variable.
            "data-volume-probe:\n\t@/bin/cat /System/Volumes/Data\(outsideURL.path)", // Tries the macOS writable-data-volume alias rather than the ordinary user path.
            "nested-sandbox-probe:\n\t@/usr/bin/sandbox-exec -p '(version 1)(allow default)' /bin/cat ../outside-marker.txt", // Proves a nested permissive profile cannot remove inherited containment.
            "temp-probe:\n\t@TMPDIR=.. /bin/sh -c '/bin/cat \"$$TMPDIR/outside-marker.txt\"'", // Proves changing TMPDIR cannot authorize another temporary directory.
            "hardlink-probe:\n\t@/bin/ln ../outside-marker.txt hard-link.txt && /bin/cat hard-link.txt", // Tests whether a process can re-export an outside inode through an inside hard link.
            "process-tree:\n\t@/bin/sh process-tree.sh", // Keeps nested descendants running until the product Stop or deadline fires.
            "background-child:\n\t@/bin/sh -c '/bin/sleep 20 & echo $$! > background.pid'", // Returns successfully while a background child still holds output descriptors.
            "outside-write:\n\t@/bin/sh -c 'printf OUTSIDE_WRITE > ../outside-write.txt'", // Tries a harmless sibling mutation.
            "inside-write:\n\t@/bin/sh -c 'printf INSIDE_WRITE > inside-output.txt'", // Performs one legitimate local mutation.
            "second-write:\n\t@/bin/sh -c 'printf SECOND_WRITE > second-output.txt'" // Performs a second independently approved local mutation.
        ].joined(separator: "\n\n") + "\n" // Builds a deterministic Makefile with separate targets.
        try Data(makefile.utf8).write(to: workspaceURL.appendingPathComponent("Makefile")) // Publishes only the test-owned Makefile.
    } // Ends isolated test fixture construction.

    func runtime(provider: any EngineeringApprovalProviding) throws -> EngineeringToolRuntime { // Builds production objects over this fixture.
        let workspace = try EngineeringWorkspace(rootURL: workspaceURL, historyDirectoryURL: historyURL) // Opens only the selected test workspace.
        return EngineeringToolRuntime(workspace: workspace, approvalProvider: provider, runtimeDirectoryURL: runtimeURL, requiresMutationApproval: true) // Requires one-shot approval and real process sandboxing.
    } // Ends production runtime construction.

    func remove() { try? FileManager.default.removeItem(at: containerURL) } // Removes only this UUID-qualified disposable fixture.
} // Ends test fixture ownership.
