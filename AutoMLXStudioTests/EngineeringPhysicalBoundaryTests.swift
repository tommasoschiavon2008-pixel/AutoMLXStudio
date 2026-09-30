import Foundation // Supplies exact source-workspace fixture paths and immutable marker bytes.
import XCTest // Supplies opt-in physical acceptance assertions on the real signed app host.
@testable import AutoMLXStudio // Runs the production workspace, approval, runtime, and macOS sandbox path.

final class EngineeringPhysicalBoundaryTests: XCTestCase { // Replays the original visible make escape against the preserved physical fixture.
    func testOriginalMakeBoundaryProbeAfterFix() async throws { // Executes the same Makefile target that disclosed the sibling marker before the fix.
        guard ProcessInfo.processInfo.environment["RUN_AUTOMLX_PHYSICAL_BOUNDARY"] == "1" else { throw XCTSkip("Opt in to the preserved physical make boundary fixture.") } // Keeps the normal suite independent of a workstation-specific validation path.
        let fixture = URL(fileURLWithPath: "/Volumes/AutoMLXShrd/AutoMLXStudioV1_3/Validation/V0611EngineeringContainment-20260929/EngineeringContainmentTest", isDirectory: true) // Selects only the already recorded pre-fix experiment directory.
        let workspaceURL = fixture.appendingPathComponent("workspace", isDirectory: true) // Selects the same authorized W as the successful pre-fix escape.
        let markerURL = fixture.appendingPathComponent("outside-marker.txt") // Names only the harmless sibling marker observed before the fix.
        let marker = try String(contentsOf: markerURL, encoding: .utf8) // Captures the pre-existing outside-only validation bytes without changing them.
        XCTAssertEqual(marker, "AUTOMLX_OUTSIDE_BOUNDARY_MARKER_20260929\n") // Verifies this is exactly the recorded harmless fixture.
        let historyURL = fixture.appendingPathComponent("PhysicalPostFixHistory", isDirectory: true) // Isolates app-owned test history beside the preserved fixture.
        let runtimeURL = fixture.appendingPathComponent("PhysicalPostFixRuntime", isDirectory: true) // Gives commands a private temporary namespace within the validation directory.
        let workspace = try EngineeringWorkspace(rootURL: workspaceURL, historyDirectoryURL: historyURL) // Opens exactly the user-authorized canonical workspace through the production object.
        let provider = PhysicalOnceApprovalProvider() // Gives an explicit one-shot test approval without changing persistent UI preferences.
        let runtime = EngineeringToolRuntime(workspace: workspace, approvalProvider: provider, runtimeDirectoryURL: runtimeURL, requiresMutationApproval: true) // Uses the real approval and sandbox-enforced execution path.
        let inside = await runtime.execute(.runCommand(EngineeringCommand(executable: "make", arguments: ["inside-probe"], timeoutMilliseconds: 10_000, reason: "Verify ordinary workspace-local make recipe"))) // Confirms the build tool still works after containment.
        XCTAssertTrue(inside.succeeded, "Legitimate make failed: \(inside)") // Requires a real child shell execution with zero exit.
        XCTAssertTrue(inside.text?.contains("AUTOMLX_INSIDE_BOUNDARY_MARKER") == true) // Requires the local file contents to reach the tool result.
        let outside = await runtime.execute(.runCommand(EngineeringCommand(executable: "make", arguments: ["boundary-probe"], timeoutMilliseconds: 10_000, reason: "Replay the original approved make outside-marker probe"))) // Repeats the exact original target under Allow Once.
        XCTAssertFalse(outside.succeeded, "Outside-marker recipe unexpectedly succeeded: \(outside)") // Requires the OS to deny access after the command was actually approved.
        XCTAssertEqual(outside.errorCode, "nonzero_exit") // Distinguishes kernel denial from prelaunch command-policy refusal.
        XCTAssertFalse(outside.text?.contains("AUTOMLX_OUTSIDE_BOUNDARY_MARKER_20260929") == true) // Requires outside-only bytes never to reach the agent output.
        XCTAssertEqual(try String(contentsOf: markerURL, encoding: .utf8), marker) // Confirms that the physical fixture was not modified.
        let requests = await provider.count() // Reads the exact number of independent approvals.
        XCTAssertEqual(requests, 2) // Requires Allow Once for each separate make invocation.
    } // Ends physical pre-fix/post-fix boundary comparison.
} // Ends physical containment acceptance coverage.

private actor PhysicalOnceApprovalProvider: EngineeringApprovalProviding { // Grants only the exact opt-in physical validation requests.
    private var requests = 0 // Counts each separately considered command.
    func decision(for request: EngineeringApprovalRequest) async -> EngineeringApprovalDecision { requests += 1; return .allowOnce } // Returns one-time approval without granting lasting filesystem authority.
    func count() -> Int { requests } // Returns the actor-isolated approval count for verification.
} // Ends physical fixture approval provider.
