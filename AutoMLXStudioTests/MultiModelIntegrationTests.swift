import XCTest // Supplies skip-capable hardware integration assertions.
@testable import AutoMLXStudio // Exposes the real V0.2 registry, resource manager, and workflow engine.

final class MultiModelIntegrationTests: XCTestCase { // Runs real three-model switching only when the optional local catalog is installed and explicitly enabled.
    func testInstalledGeneralCodingAndReasoningModelsSwitchPhysically() async throws { // Validates the requested General, Coding, Reviewer, and Final model chain on local hardware.
        guard ProcessInfo.processInfo.environment["RUN_MLX_MULTI_MODEL_TESTS"] == "1" else { throw XCTSkip("Set RUN_MLX_MULTI_MODEL_TESTS=1 to run physical multi-model MLX switching.") } // Keeps normal test runs deterministic and inexpensive.
        let legacyIdentifier = "mlx-community/Llama-3.2-3B-Instruct-4bit" // Preserves the verified V0.1 final fallback.
        let registry = ModelRegistry.defaultRegistry(legacyIdentifier: legacyIdentifier) // Detects installed Project 5 folders offline.
        let requiredIDs = [Project5ModelCatalog.general, Project5ModelCatalog.coding, Project5ModelCatalog.reasoning] // Lists the three physical models required for the acceptance flow.
        guard requiredIDs.allSatisfy({ registry.model(id: $0)?.installationState == .installed }) else { throw XCTSkip("General, Coding, and Reasoning catalog models are not all installed under \(registry.modelsRoot).") } // Skips rather than failing when optional downloads are absent.
        let service = MLXService() // Creates the existing working MLX server and completion service.
        let manager = ModelResourceManager(service: service) // Creates the one-server serialized physical resource manager.
        let engine = WorkflowEngine(client: MLXCompletionClient(service: service), registry: AgentRegistry(), resourceManager: manager) // Connects the real V0.2 orchestration pipeline.
        let configuration = ModelRuntimeConfiguration(executableDirectory: "/Volumes/Crucial X9 Pro/app/MLX/mlx-lm-main/.venv/bin", repoPath: "/Volumes/Crucial X9 Pro/app/MLX/mlx-lm-main", requestedPort: 8082, autoSelectPort: true) // Uses the provided verified MLX environment.
        let result = await engine.execute(userInput: "Write a Python function that returns the largest number in an array.", conversationHistory: [], modelRegistry: registry, runtimeConfiguration: configuration, switchPolicy: .qualityPreferred, onOutput: { print("MLX_HARDWARE_OUTPUT|\($0)") }) // Runs Coding → Reviewer → Final Composer with physical switching and captures owned-server diagnostics.
        XCTAssertEqual(result.trace.status, .succeeded) // Confirms every real model-backed stage completed.
        for execution in result.trace.modelExecutions where execution.status == .failed { // Emits every failed preferred attempt before evaluating the accepted sequence.
            print("HARDWARE_FAILURE|agent=\(execution.agentID)|model=\(execution.selectedModelID)|reason=\(execution.selectionReason.rawValue)|load_ms=\(execution.modelLoadingMilliseconds)|inference_ms=\(execution.inferenceMilliseconds)|detail=\(execution.detail.replacingOccurrences(of: "\n", with: " "))") // Preserves actionable runtime evidence without prompts or generated answers.
        } // Ends failed-attempt diagnostics.
        let successfulExecutions = result.trace.modelExecutions.filter { $0.status == .succeeded } // Retains only completed physical inference stages for acceptance evidence.
        XCTAssertEqual(successfulExecutions.map(\.selectedModelID), [Project5ModelCatalog.coding, Project5ModelCatalog.reasoning, Project5ModelCatalog.general]) // Confirms the exact physical model sequence.
        for execution in successfulExecutions { // Verifies and emits complete per-stage hardware evidence.
            let expectedReference = try XCTUnwrap(registry.model(id: execution.selectedModelID)?.launchReference) // Resolves the read-only catalog path for the actual model.
            XCTAssertEqual(execution.launchReference, expectedReference) // Confirms the runtime trace contains the exact selected on-disk path.
            print("HARDWARE_EXECUTION|agent=\(execution.agentID)|model=\(execution.selectedModelID)|path=\(execution.launchReference ?? "nil")|stop_ms=\(execution.stopMilliseconds ?? -1)|cold_load_ms=\(execution.coldLoadMilliseconds ?? -1)|reuse_ms=\(execution.reuseMilliseconds ?? -1)|overhead_ms=\(execution.switchingOverheadMilliseconds ?? -1)|inference_ms=\(execution.inferenceMilliseconds)|stage_total_ms=\(execution.totalStageMilliseconds)|forced=\(execution.forcedTermination ?? false)|rss_before_bytes=\(execution.memoryBeforeStop?.trackedProcessResidentBytes.map(String.init) ?? "nil")|rss_after_load_bytes=\(execution.memoryAfterLoad?.trackedProcessResidentBytes.map(String.init) ?? "nil")|pid_after_load=\(execution.memoryAfterLoad?.trackedProcessID.map(String.init) ?? "nil")") // Prints exact machine-readable transition evidence without model output or private prompt content.
        } // Ends per-stage hardware evidence verification.
        XCTAssertFalse(result.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) // Confirms Chat receives a real final answer.
        let generalProfile = try XCTUnwrap(registry.model(id: Project5ModelCatalog.general)) // Resolves the model intentionally left warm by the workflow.
        let warmReuse = try await manager.prepare(model: generalProfile, configuration: configuration) // Requests the same General model to verify no restart occurs.
        XCTAssertTrue(warmReuse.reusedExistingLoad) // Confirms the final model was reused in memory.
        XCTAssertFalse(warmReuse.didSwitch) // Confirms warm reuse did not claim a physical transition.
        print("HARDWARE_SUMMARY|status=\(result.trace.status.rawValue)|port=\(result.activeServerPort ?? -1)|workflow_total_ms=\(result.trace.totalDurationMilliseconds)|answer_characters=\(result.answer.count)|warm_reuse=true|warm_reuse_ms=\(warmReuse.reuseDurationMilliseconds)|forced_count=\(successfulExecutions.filter { $0.forcedTermination == true }.count)") // Prints exact aggregate acceptance evidence while excluding answer contents.
        await manager.stop() // Releases the final physical model and local server process.
        let stoppedSnapshot = await manager.snapshot() // Reads actor state after the verified explicit release.
        XCTAssertNil(stoppedSnapshot.activeModelID) // Confirms no V0.3 model remains logically active.
        XCTAssertNil(stoppedSnapshot.activePort) // Confirms no managed endpoint remains published.
        XCTAssertNil(service.managedServerProcessID()) // Confirms the exact MLXService-owned process reference was released.
        print("HARDWARE_CLEANUP|active_model=nil|active_port=nil|managed_pid=nil") // Emits deterministic orphan-cleanup evidence for the test log.
    } // Ends real installed multi-model integration test.
} // Ends skip-capable multi-model hardware integration tests.
