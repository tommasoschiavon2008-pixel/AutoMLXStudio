import XCTest // Imports deterministic assertions without starting any external process.
@testable import AutoMLXStudio // Exposes the internal offline-environment helper owned by MLXService.

final class MLXServiceOfflineEnvironmentTests: XCTestCase { // Groups process-free coverage for every MLX text-runtime environment.
    func testOfflineRuntimeEnvironmentForcesAllOfflineFlagsAndPreservesInheritedValues() { // Verifies required overrides and unrelated inherited variables together.
        let inheritedEnvironment = [ // Builds a deterministic environment containing both ordinary values and conflicting online settings.
            "PATH": "/usr/bin:/bin", // Represents the host PATH that must remain after the MLX executable prefix.
            "HOME": "/Users/tester", // Represents an unrelated inherited variable that must not be removed.
            "PROJECT5_SENTINEL": "preserve-me", // Provides an app-specific value that detects accidental environment replacement.
            "HF_HUB_OFFLINE": "0", // Simulates a conflicting parent value that must be forced offline.
            "TRANSFORMERS_OFFLINE": "false", // Simulates a second conflicting parent value that must be forced offline.
            "HF_DATASETS_OFFLINE": "no", // Simulates a third conflicting parent value that must be forced offline.
            "PYTHONUNBUFFERED": "0" // Simulates a buffered parent runtime that must retain existing app log behavior.
        ] // Finishes the deterministic inherited environment fixture.

        let environment = MLXService.offlineRuntimeEnvironment( // Calls only the pure helper and never constructs or launches MLX.
            inheriting: inheritedEnvironment, // Supplies the controlled inherited values.
            executableDirectory: "/opt/project5/venv/bin" // Supplies the directory used to verify preserved PATH precedence.
        ) // Finishes offline environment construction.

        XCTAssertEqual(environment["HF_HUB_OFFLINE"], "1") // Proves Hugging Face Hub is forced into offline mode.
        XCTAssertEqual(environment["TRANSFORMERS_OFFLINE"], "1") // Proves Transformers is forced into offline mode.
        XCTAssertEqual(environment["HF_DATASETS_OFFLINE"], "1") // Proves Hugging Face Datasets is forced into offline mode.
        XCTAssertEqual(environment["PYTHONUNBUFFERED"], "1") // Proves the existing unbuffered-output behavior remains enabled.
        XCTAssertEqual(environment["PATH"], "/opt/project5/venv/bin:/usr/bin:/bin") // Proves the executable directory still precedes the inherited PATH exactly.
        XCTAssertEqual(environment["HOME"], "/Users/tester") // Proves an unrelated standard inherited value survives unchanged.
        XCTAssertEqual(environment["PROJECT5_SENTINEL"], "preserve-me") // Proves arbitrary inherited values survive unchanged.
    } // Ends required-offline-flags and inherited-environment coverage.

    func testOfflineRuntimeEnvironmentPreservesLegacyEmptyPathBehavior() { // Locks the pre-existing direct Process behavior when the parent has no PATH.
        let inheritedEnvironment = ["LANG": "en_IE.UTF-8"] // Creates an inherited environment with no PATH entry.
        let environment = MLXService.offlineRuntimeEnvironment( // Builds the process-free runtime environment for the no-PATH edge case.
            inheriting: inheritedEnvironment, // Supplies the single inherited locale value.
            executableDirectory: "/venv/bin" // Supplies the executable directory that must still be prepended.
        ) // Finishes no-PATH environment construction.

        XCTAssertEqual(environment["PATH"], "/venv/bin:") // Proves the helper preserves the exact legacy interpolation result for a missing PATH.
        XCTAssertEqual(environment["LANG"], "en_IE.UTF-8") // Proves inherited locale configuration is retained.
        XCTAssertEqual(environment["HF_HUB_OFFLINE"], "1") // Proves Hub offline mode is present even without an inherited PATH.
        XCTAssertEqual(environment["TRANSFORMERS_OFFLINE"], "1") // Proves Transformers offline mode is present even without an inherited PATH.
        XCTAssertEqual(environment["HF_DATASETS_OFFLINE"], "1") // Proves Datasets offline mode is present even without an inherited PATH.
    } // Ends missing-PATH compatibility coverage.
} // Ends MLXService offline-environment tests.
