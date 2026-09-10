import XCTest // Supplies asynchronous lifecycle and metric assertions.
@testable import AutoMLXStudio // Exposes internal V0.2.1 resource-management contracts.

final class OpenAIResponseSafetyTests: XCTestCase { // Verifies reasoning-capable server payloads never leak private reasoning as assistant content.
    func testReasoningOnlyResponseDecodesButHasNoUserFacingContent() throws { // Covers the exact DeepSeek hardware response shape found during validation.
        let data = Data(#"{"choices":[{"message":{"role":"assistant","reasoning":"private analysis"}}]}"#.utf8) // Creates a response with valid reasoning metadata and intentionally absent content.
        let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data) // Confirms optional content no longer causes an opaque key-not-found decoding failure.
        let message = try XCTUnwrap(response.choices.first?.message) // Resolves the single response choice.
        XCTAssertNil(message.userFacingContent) // Confirms private reasoning is never substituted for a user-facing answer.
        XCTAssertEqual(message.reasoning, "private analysis") // Confirms the field was understood only as diagnostic metadata.
    } // Ends reasoning-only response safety coverage.

    func testAssistantContentRemainsAvailableWhenPresent() throws { // Protects the existing successful response path.
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"  Ready answer  "}}]}"#.utf8) // Creates a normal response with surrounding whitespace.
        let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: data) // Decodes the existing server shape.
        XCTAssertEqual(response.choices.first?.message.userFacingContent, "Ready answer") // Confirms normalization returns only the intended assistant content.
    } // Ends normal response compatibility coverage.
} // Ends OpenAI response safety tests.

final class ModelInstallationValidationTests: XCTestCase { // Verifies structured local model completeness evidence.
    func testMissingIndexedShardMakesExistingDirectoryIncomplete() throws { // Ensures any missing index-declared shard blocks launch.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("InstallValidation-\(UUID().uuidString)", isDirectory: true) // Creates an isolated model directory.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) // Creates the exact fixture root.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only this UUID-scoped fixture.
        try Data("{}".utf8).write(to: root.appendingPathComponent("config.json")) // Creates required configuration metadata.
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer_config.json")) // Creates required tokenizer metadata.
        try validSafetensorsData().write(to: root.appendingPathComponent("model-00001-of-00002.safetensors")) // Creates only the first valid declared shard.
        let index = ["weight_map": ["a": "model-00001-of-00002.safetensors", "b": "model-00002-of-00002.safetensors"]] // Declares a second shard that is intentionally absent.
        try JSONSerialization.data(withJSONObject: index).write(to: root.appendingPathComponent("model.safetensors.index.json")) // Writes the authoritative shard index.
        let profile = ModelProfile(id: "indexed", displayName: "Indexed", repositoryID: "indexed", localPath: root.path, backend: .mlxLM, capabilities: [.general], approximateDiskGB: nil, approximateMemoryGB: nil, enabled: true, installationState: .installed, runtimeState: .unloaded, isLegacyFallback: false, statusDetail: nil) // Creates the profile under inspection.
        let validation = ModelInstallationInspector.validation(for: profile) // Runs the production read-only structured validator.
        XCTAssertTrue(validation.installed) // Confirms the directory itself exists.
        XCTAssertFalse(validation.completeEnoughToLaunch) // Confirms incomplete shards block launch eligibility.
        XCTAssertTrue(validation.missingRequiredFiles.contains { $0.contains("model-00002-of-00002.safetensors") }) // Confirms the exact missing indexed filename is reported.
        XCTAssertGreaterThan(validation.diskBytes, 0) // Confirms disk measurement is populated without reading tensors.
        XCTAssertEqual(ModelInstallationInspector.inspect(profile).installationState, .downloading) // Confirms an existing incomplete directory maps to the explicit downloading state.
    } // Ends indexed-shard completeness test.

    private func validSafetensorsData() -> Data { // Creates the smallest header-valid fixture accepted by the bounded inspector.
        var length = UInt64(2).littleEndian // Declares a two-byte JSON header.
        var data = Data(bytes: &length, count: MemoryLayout<UInt64>.size) // Writes the eight-byte little-endian prefix.
        data.append(Data("{}".utf8)) // Writes the declared header.
        data.append(0) // Adds one bounded payload byte after the header.
        return data // Returns the complete tiny fixture.
    } // Ends valid safetensors fixture creation.
} // Ends structured installation tests.

final class ModelInstallationAuditorTests: XCTestCase { // Verifies the reusable six-state model installation classification.
    func testIncompleteAndDownloadingAreDistinguishedByTransferEvidence() throws { // Separates a stable missing shard from a folder carrying an untouched lock.
        let root = try makeModelDirectory(weightData: validSafetensorsData()) // Creates a complete base model fixture.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only this test-owned fixture.
        try FileManager.default.removeItem(at: root.appendingPathComponent("model.safetensors")) // Makes the fixture incomplete without transfer evidence.
        let profile = profile(at: root) // Creates the filesystem-backed model profile.
        XCTAssertEqual(ModelInstallationAuditor.report(for: profile, runtimeAvailable: true).status, .incomplete) // Confirms missing stable artifacts do not automatically mean downloading.
        let lockDirectory = root.appendingPathComponent(".cache/huggingface/download", isDirectory: true) // Resolves a realistic nested download lock scope.
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true) // Creates only the fixture's nested cache directory.
        try Data().write(to: lockDirectory.appendingPathComponent("model.lock")) // Adds a lock that the auditor must never mutate.
        let report = ModelInstallationAuditor.report(for: profile, runtimeAvailable: true) // Re-audits with transfer evidence present.
        XCTAssertEqual(report.status, .downloading) // Confirms lock-plus-incomplete maps to downloading or incomplete.
        XCTAssertEqual(report.activeLocks.count, 1) // Confirms the exact lock reference is surfaced.
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.activeLocks[0].path)) // Confirms inspection left the lock untouched.
    } // Ends downloading classification test.

    func testCompleteFilesCanReportRuntimeUnavailableAndMalformedWeightsInvalid() throws { // Separates runtime dependency failure from invalid local content.
        let root = try makeModelDirectory(weightData: validSafetensorsData()) // Creates a complete launchable file fixture.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only this test-owned fixture.
        let profile = profile(at: root) // Creates the filesystem-backed model profile.
        XCTAssertEqual(ModelInstallationAuditor.report(for: profile, runtimeAvailable: false).status, .runtimeUnavailable) // Confirms complete files remain distinct from a missing runtime package.
        try Data("bad".utf8).write(to: root.appendingPathComponent("model.safetensors"), options: .atomic) // Replaces only the fixture weight with a malformed container.
        XCTAssertEqual(ModelInstallationAuditor.report(for: profile, runtimeAvailable: true).status, .invalid) // Confirms malformed safetensors metadata is invalid rather than downloading.
    } // Ends runtime and invalid classification test.

    private func makeModelDirectory(weightData: Data) throws -> URL { // Creates a minimal complete MLX LM fixture for reusable auditor tests.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Auditor-\(UUID().uuidString)", isDirectory: true) // Allocates one isolated model root.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) // Creates the exact fixture directory.
        try Data("{}".utf8).write(to: root.appendingPathComponent("config.json")) // Creates required model configuration.
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer_config.json")) // Creates required tokenizer metadata.
        try weightData.write(to: root.appendingPathComponent("model.safetensors")) // Creates the supplied bounded weight container.
        return root // Returns the exact fixture root.
    } // Ends complete model fixture creation.

    private func profile(at root: URL) -> ModelProfile { // Creates a launch-catalog profile for the fixture.
        ModelProfile(id: "auditor", displayName: "Auditor", repositoryID: "auditor", localPath: root.path, backend: .mlxLM, capabilities: [.general], approximateDiskGB: nil, approximateMemoryGB: 1, enabled: true, installationState: .installed, runtimeState: .unloaded, isLegacyFallback: false, statusDetail: nil) // Returns complete test metadata.
    } // Ends auditor profile construction.

    private func validSafetensorsData() -> Data { // Creates the smallest header-valid fixture accepted by the bounded inspector.
        var length = UInt64(2).littleEndian // Declares a two-byte JSON header.
        var data = Data(bytes: &length, count: MemoryLayout<UInt64>.size) // Writes the eight-byte prefix.
        data.append(Data("{}".utf8)) // Writes the declared JSON header.
        data.append(0) // Adds one payload byte after the header.
        return data // Returns the complete tiny container.
    } // Ends valid safetensors fixture creation.
} // Ends reusable installation-auditor tests.

final class ModelResidencyPolicyTests: XCTestCase { // Verifies host-independent pure reuse, load, switch, and reject policy outcomes.
    func testLargeTextToVisionRequiresSwitchAndSameModelReuses() { // Enforces mutual exclusion between large text and large Vision.
        let budget = ResourceBudget(physicalMemoryBytes: 16_000, reservedForSystemBytes: 4_000, usableForModelsBytes: 12_000) // Creates a deterministic synthetic host budget.
        let text = ResidentModelEstimate(modelID: "text", resourceClass: .largeText, estimatedBytes: 5_000) // Creates an active large text estimate.
        let vision = ResidentModelEstimate(modelID: "vision", resourceClass: .largeVision, estimatedBytes: 6_000) // Creates a different large Vision target.
        XCTAssertEqual(ModelResidencyPolicy.decide(target: text, activeLarge: text, activeSmall: [], budget: budget), .reuse) // Confirms identical physical residency reuses.
        XCTAssertEqual(ModelResidencyPolicy.decide(target: vision, activeLarge: text, activeSmall: [], budget: budget), .switchFrom("text")) // Confirms Vision cannot overlap large text.
    } // Ends large-runtime exclusivity test.

    func testSmallAudioCoexistsOnlyWithinBudgetAndOtherwiseReleasesLargeModel() { // Enforces estimated-memory coexistence rather than model count alone.
        let budget = ResourceBudget(physicalMemoryBytes: 16_000, reservedForSystemBytes: 4_000, usableForModelsBytes: 12_000) // Creates a deterministic usable budget.
        let text = ResidentModelEstimate(modelID: "text", resourceClass: .largeText, estimatedBytes: 10_000) // Creates a large resident text estimate.
        let smallASR = ResidentModelEstimate(modelID: "asr", resourceClass: .smallAudio, estimatedBytes: 1_000) // Creates a safe small audio target.
        let largerTTS = ResidentModelEstimate(modelID: "tts", resourceClass: .smallAudio, estimatedBytes: 3_000) // Creates an audio target that does not fit beside text.
        XCTAssertEqual(ModelResidencyPolicy.decide(target: smallASR, activeLarge: text, activeSmall: [], budget: budget), .load) // Confirms safe measured coexistence.
        XCTAssertEqual(ModelResidencyPolicy.decide(target: largerTTS, activeLarge: text, activeSmall: [], budget: budget), .switchFrom("text")) // Confirms text release when audio fits only alone.
        let impossible = ResidentModelEstimate(modelID: "impossible", resourceClass: .smallAudio, estimatedBytes: 13_000) // Creates a target larger than the entire usable budget.
        guard case .reject = ModelResidencyPolicy.decide(target: impossible, activeLarge: nil, activeSmall: [], budget: budget) else { return XCTFail("Expected a deterministic budget rejection.") } // Confirms unsafe work is refused.
    } // Ends small-runtime budget test.
} // Ends residency-policy tests.

final class ResourceReuseTests: XCTestCase { // Verifies warm reuse and measured physical transition evidence.
    func testWarmReuseSkipsSecondStartAndReportsReuseMetrics() async throws { // Exercises a cold load followed by a warm identical request.
        let environment = try ResourceTestEnvironment() // Creates a fake executable accepted by the text adapter.
        defer { environment.cleanup() } // Removes only the isolated environment.
        let controller = SafetyFakeController(stopResult: ManagedProcessStopResult(processID: 42, durationMilliseconds: 7, forcedTermination: false, exitConfirmed: true)) // Creates a verified fake lifecycle controller.
        let manager = ModelResourceManager(controller: controller) // Creates the production serialized manager.
        let model = environment.legacyProfile(id: "warm") // Creates a repository-backed validation-safe model.
        let cold = try await manager.prepare(model: model, configuration: environment.configuration) // Performs the first physical load.
        let warm = try await manager.prepare(model: model, configuration: environment.configuration) // Requests the already loaded model again.
        XCTAssertFalse(cold.reusedExistingLoad) // Confirms the first request was a cold load.
        XCTAssertTrue(warm.reusedExistingLoad) // Confirms the second request was warm reuse.
        XCTAssertEqual(warm.coldLoadDurationMilliseconds, 0) // Confirms reuse does not claim another cold load.
        XCTAssertEqual(warm.launchReference, model.launchReference) // Confirms the exact physical reference remains traceable.
        let startCount = await controller.startCount() // Reads actor-isolated physical start count before entering the XCTest autoclosure.
        XCTAssertEqual(startCount, 1) // Confirms only one process start occurred.
        await manager.stop() // Releases the fake active runtime.
    } // Ends warm reuse test.
} // Ends warm reuse tests.

final class StopTimeoutTests: XCTestCase { // Verifies replacement blocking and forced-stop trace propagation.
    func testUnconfirmedStopBlocksReplacementStart() async throws { // Ensures no second model starts after an unsafe shutdown result.
        let environment = try ResourceTestEnvironment() // Creates a fake text runtime environment.
        defer { environment.cleanup() } // Removes only the isolated environment.
        let controller = SafetyFakeController(stopResult: ManagedProcessStopResult(processID: 77, durationMilliseconds: 5, forcedTermination: true, exitConfirmed: false)) // Simulates a tracked process that did not confirm exit.
        let manager = ModelResourceManager(controller: controller) // Creates the production central resource manager.
        _ = try await manager.prepare(model: environment.legacyProfile(id: "first"), configuration: environment.configuration) // Loads the first fake physical model.
        do { // Attempts the unsafe replacement.
            _ = try await manager.prepare(model: environment.legacyProfile(id: "second"), configuration: environment.configuration) // Requests a second large model.
            XCTFail("Replacement should be blocked after unconfirmed exit.") // Fails if overlap protection regresses.
        } catch { // Accepts the required controlled lifecycle failure.
            XCTAssertTrue(error.localizedDescription.contains("did not confirm exit")) // Confirms the failure explains the exact safety reason.
        } // Ends replacement failure assertion.
        do { // Attempts a later third model to prove the unsafe-shutdown block is sticky.
            _ = try await manager.prepare(model: environment.legacyProfile(id: "third"), configuration: environment.configuration) // Requests another model after the first blocked replacement.
            XCTFail("Later startup should remain blocked after unconfirmed exit.") // Fails if actor state forgets the safety invariant.
        } catch { // Accepts the required persistent lifecycle block.
            XCTAssertTrue(error.localizedDescription.contains("did not confirm exit")) // Confirms later work receives the original actionable safety reason.
        } // Ends sticky-block assertion.
        let startCount = await controller.startCount() // Reads actor-isolated start count before synchronous assertions.
        let observedTimeout = await controller.lastTimeout() // Reads actor-isolated graceful deadline evidence.
        XCTAssertEqual(startCount, 1) // Confirms no second start occurred.
        XCTAssertEqual(observedTimeout, environment.configuration.transitionTimeoutMilliseconds) // Confirms the configured graceful deadline reached the controller.
    } // Ends unconfirmed-stop test.

    func testForcedTerminationIsPropagatedWhenExitIsConfirmed() async throws { // Verifies force use remains explicit hardware trace evidence.
        let environment = try ResourceTestEnvironment() // Creates a fake text runtime environment.
        defer { environment.cleanup() } // Removes only the isolated environment.
        let controller = SafetyFakeController(stopResult: ManagedProcessStopResult(processID: 88, durationMilliseconds: 9, forcedTermination: true, exitConfirmed: true)) // Simulates exact-PID force followed by confirmed exit.
        let manager = ModelResourceManager(controller: controller) // Creates the production serialized manager.
        _ = try await manager.prepare(model: environment.legacyProfile(id: "first"), configuration: environment.configuration) // Loads the outgoing model.
        let replacement = try await manager.prepare(model: environment.legacyProfile(id: "second"), configuration: environment.configuration) // Performs the verified replacement.
        XCTAssertTrue(replacement.forcedTermination) // Confirms force use is not hidden.
        XCTAssertEqual(replacement.stopDurationMilliseconds, 9) // Confirms verified shutdown time is preserved.
        XCTAssertEqual(replacement.memoryBeforeStop?.trackedProcessID, 4_242) // Confirms memory sampling uses only the controller-owned PID.
        let startCount = await controller.startCount() // Reads actor-isolated physical start count before asserting.
        XCTAssertEqual(startCount, 2) // Confirms replacement starts only after confirmed exit.
        await manager.stop() // Releases the fake final runtime.
    } // Ends confirmed forced-stop metric test.
} // Ends stop-timeout tests.

private struct ResourceTestEnvironment { // Owns one isolated fake MLX environment and validation-safe profiles.
    let root: URL // Stores the exact UUID-scoped root.
    let configuration: ModelRuntimeConfiguration // Stores fake executable, port, and timeout settings.

    init() throws { // Creates the isolated environment.
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ResourceSafety-\(UUID().uuidString)", isDirectory: true) // Allocates a unique cleanup root.
        let bin = root.appendingPathComponent("bin", isDirectory: true) // Resolves the fake environment executable folder.
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true) // Creates the fake environment directories.
        let executable = bin.appendingPathComponent("mlx_lm.server") // Resolves the expected text runtime executable.
        try Data("#!/bin/sh\n".utf8).write(to: executable) // Writes a harmless executable fixture.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path) // Makes the fixture executable for adapter discovery.
        configuration = ModelRuntimeConfiguration(executableDirectory: bin.path, repoPath: root.path, requestedPort: 22_000, autoSelectPort: true, transitionTimeoutMilliseconds: 123) // Creates explicit bounded transition settings.
    } // Ends environment construction.

    func legacyProfile(id: String) -> ModelProfile { // Creates a repository-backed validation-safe text model.
        ModelProfile(id: id, displayName: id, repositoryID: id, localPath: nil, backend: .mlxLM, capabilities: [.general, .reasoning, .coding, .swiftLanguage, .research], approximateDiskGB: nil, approximateMemoryGB: nil, enabled: true, installationState: .installed, runtimeState: .unloaded, isLegacyFallback: true, statusDetail: nil) // Returns the complete fake profile.
    } // Ends fake profile creation.

    func cleanup() { try? FileManager.default.removeItem(at: root) } // Removes only the exact UUID-scoped environment root.
} // Ends resource test environment.

private actor SafetyFakeController: ModelServerControlling { // Records exact lifecycle calls and returns configurable verified stop facts.
    private let configuredStopResult: ManagedProcessStopResult // Stores the requested shutdown behavior.
    private var starts = 0 // Counts physical start calls.
    private var observedTimeout: Int? // Stores the exact configured graceful deadline.

    init(stopResult: ManagedProcessStopResult) { configuredStopResult = stopResult } // Stores deterministic shutdown behavior.
    func start(modelReference: String, configuration: ModelRuntimeConfiguration, onOutput: @escaping (String) -> Void) async throws -> Int { starts += 1; return configuration.requestedPort + starts } // Records one ready fake physical start.
    func stop() async {} // Supplies compatibility stop behavior for the protocol.
    func stop(timeoutMilliseconds: Int) async throws -> ManagedProcessStopResult { observedTimeout = timeoutMilliseconds; return configuredStopResult } // Returns the configured exact-PID shutdown evidence.
    func managedProcessID() async -> Int32? { starts > 0 ? 4_242 : nil } // Exposes only the fake controller-owned PID after startup.
    func startCount() -> Int { starts } // Returns physical start count atomically.
    func lastTimeout() -> Int? { observedTimeout } // Returns the last observed graceful deadline atomically.
} // Ends safety fake controller.
