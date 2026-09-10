import XCTest // Supplies end-to-end deterministic workflow assertions.
@testable import AutoMLXStudio // Exposes internal V0.2 workflow and model architecture.

final class MultiModelWorkflowTests: XCTestCase { // Verifies one request selects and switches specialist, reviewer, and composer models.
    func testWorkflowUsesThreeAgentModelSelections() async throws { // Exercises the complete V0.2 deterministic pipeline without physical model weights.
        let environment = try makeWorkflowEnvironment() // Creates valid local folders and a fake executable preflight root.
        defer { try? FileManager.default.removeItem(at: environment.root) } // Removes only the UUID-scoped workflow test directory.
        let general = environment.profile(id: "general", capabilities: [.general, .reasoning, .research]) // Creates the Final Composer physical model.
        let coder = environment.profile(id: "coder", capabilities: [.general, .reasoning, .coding, .swiftLanguage]) // Creates the Coding Agent physical model.
        let reasoner = environment.profile(id: "reasoner", capabilities: [.general, .reasoning]) // Creates the Reviewer physical model.
        let legacy = environment.profile(id: "legacy", capabilities: [.general, .reasoning, .coding, .swiftLanguage, .research], legacy: true) // Creates the final compatibility fallback.
        let assignments = [ // Defines explicit per-agent physical model choices used by this coding workflow.
            ModelAssignment(agentID: AgentID.coding, preferredModelID: coder.id, preferredCapability: .coding, fallbackModelIDs: [], fallbackCapabilities: [.coding], allowsRuntimeReuse: true), // Assigns the specialist to Coder.
            ModelAssignment(agentID: AgentID.reviewer, preferredModelID: reasoner.id, preferredCapability: .reasoning, fallbackModelIDs: [], fallbackCapabilities: [.reasoning], allowsRuntimeReuse: true), // Assigns Reviewer to Reasoner.
            ModelAssignment(agentID: AgentID.finalComposer, preferredModelID: general.id, preferredCapability: .general, fallbackModelIDs: [], fallbackCapabilities: [.general], allowsRuntimeReuse: true) // Assigns Final Composer to General.
        ] // Ends workflow assignment definitions.
        let registry = ModelRegistry(models: [general, coder, reasoner, legacy], assignments: assignments, legacyFallbackModelID: legacy.id, modelsRoot: environment.root.path) // Creates one explicit installed multi-model registry.
        for profile in [general, coder, reasoner] { // Revalidates every local fixture through the production structured inspector.
            let validation = ModelInstallationInspector.validation(for: profile) // Captures exact completeness evidence for useful assertion failures.
            XCTAssertTrue(validation.completeEnoughToLaunch, "Fixture \(profile.id) invalid: \(validation.missingRequiredFiles) \(validation.warnings)") // Confirms workflow failures cannot be caused by a malformed test fixture.
        } // Ends workflow fixture validation.
        let controller = WorkflowFakeServerController() // Creates a deterministic single-server process boundary.
        let manager = ModelResourceManager(controller: controller) // Creates the production serialized resource actor.
        let client = WorkflowRecordingClient() // Creates a completion client that records actual model references.
        let engine = WorkflowEngine(client: client, registry: AgentRegistry(), resourceManager: manager) // Connects production routing, switching, and trace code to deterministic boundaries.
        let result = await engine.execute(userInput: "Write a function that returns the largest number in an array.", conversationHistory: [], modelRegistry: registry, runtimeConfiguration: environment.configuration, switchPolicy: .qualityPreferred) // Uses a deliberately language-neutral request so this V0.2 test continues to exercise the general Coding Agent after V0.5 added a dedicated Python specialist.
        XCTAssertEqual(result.trace.intent, .coding) // Confirms a language-neutral development request remains on the general Coding route.
        XCTAssertEqual(result.trace.specialistID, AgentID.coding) // Confirms Director selects Coding Agent when no V0.5 language specialist was requested.
        XCTAssertEqual(result.trace.modelIdentifier, coder.id) // Confirms compact Chat metadata uses the actual specialist model.
        XCTAssertEqual(result.trace.status, .succeeded) // Confirms all three model-backed stages completed.
        XCTAssertEqual(result.trace.modelExecutions.filter { $0.status == .succeeded }.map(\.selectedModelID), [coder.id, reasoner.id, general.id]) // Confirms specialist, reviewer, and composer physical selections in order.
        XCTAssertTrue(result.trace.steps.contains(where: { $0.stage == .modelRouter })) // Confirms expanded trace records model decisions.
        XCTAssertEqual(result.trace.steps.filter { $0.stage == .modelResource && $0.status == .succeeded }.count, 3) // Confirms three actual load or switch operations are represented.
        let metrics = await controller.metrics() // Reads physical transition counts.
        XCTAssertEqual(metrics.starts, 3) // Confirms three distinct physical models were started.
        XCTAssertEqual(metrics.maximumConcurrentStarts, 1) // Confirms the single-medium-model memory rule.
        let references = await client.modelReferences() // Reads actual completion model references.
        XCTAssertEqual(references, [coder.launchReference, reasoner.launchReference, general.launchReference]) // Confirms each agent call used its selected physical model.
        await manager.stop() // Releases the final fake active model and mirrors production cleanup.
    } // Ends multi-model workflow selection test.

    private func makeWorkflowEnvironment() throws -> WorkflowEnvironment { // Creates isolated local files accepted by production preflight validation.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AutoMLXStudioWorkflowTests-\(UUID().uuidString)", isDirectory: true) // Creates an exact UUID-scoped root.
        let executableDirectory = root.appendingPathComponent("bin", isDirectory: true) // Creates the fake executable folder.
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true) // Creates parent directories.
        let executable = executableDirectory.appendingPathComponent("mlx_lm.server") // Creates the expected server executable path.
        FileManager.default.createFile(atPath: executable.path, contents: Data("#!/bin/sh\n".utf8)) // Writes a harmless preflight placeholder.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path) // Marks the placeholder executable.
        let configuration = ModelRuntimeConfiguration(executableDirectory: executableDirectory.path, repoPath: root.path, requestedPort: 20_000, autoSelectPort: true) // Creates deterministic fake runtime settings.
        return WorkflowEnvironment(root: root, configuration: configuration) // Returns cleanup, file creation, and runtime context.
    } // Ends workflow environment creation.
} // Ends deterministic multi-model workflow tests.

private struct WorkflowEnvironment { // Creates valid local physical model folders for workflow tests.
    let root: URL // Stores the exact UUID-scoped root.
    let configuration: ModelRuntimeConfiguration // Stores fake executable and port settings.

    func profile(id: String, capabilities: Set<ModelCapability>, legacy: Bool = false) -> ModelProfile { // Creates one locally valid model profile.
        let folder = root.appendingPathComponent(id, isDirectory: true) // Creates a stable physical folder per test model.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) // Creates the local model folder.
        FileManager.default.createFile(atPath: folder.appendingPathComponent("config.json").path, contents: Data("{}".utf8)) // Creates the required model configuration file.
        FileManager.default.createFile(atPath: folder.appendingPathComponent("tokenizer_config.json").path, contents: Data("{}".utf8)) // Creates the required tokenizer metadata file.
        var headerLength = UInt64(2).littleEndian // Declares the two-byte minimal JSON header length in safetensors byte order.
        var weightData = Data(bytes: &headerLength, count: MemoryLayout<UInt64>.size) // Writes the required eight-byte safetensors length prefix.
        weightData.append(Data("{}".utf8)) // Writes the declared minimal JSON header.
        weightData.append(0) // Adds one payload byte so the declared header fits strictly inside the container.
        FileManager.default.createFile(atPath: folder.appendingPathComponent("model.safetensors").path, contents: weightData) // Creates a header-valid bounded test weight container without real tensors.
        return ModelProfile(id: id, displayName: id.capitalized, repositoryID: id, localPath: folder.path, backend: .mlxLM, capabilities: capabilities, approximateDiskGB: nil, approximateMemoryGB: nil, enabled: true, installationState: .installed, runtimeState: .unloaded, isLegacyFallback: legacy, statusDetail: nil) // Returns a complete installed text profile.
    } // Ends valid physical profile creation.
} // Ends workflow test environment.

private actor WorkflowFakeServerController: ModelServerControlling { // Measures physical multi-model switching under the real resource manager.
    private var starts = 0 // Counts fake physical model starts.
    private var concurrentStarts = 0 // Tracks active fake starts.
    private var maximumConcurrentStarts = 0 // Tracks any illegal start overlap.

    func start(modelReference: String, configuration: ModelRuntimeConfiguration, onOutput: @escaping (String) -> Void) async throws -> Int { // Simulates one ready model server.
        starts += 1 // Records the physical load.
        concurrentStarts += 1 // Records active fake start work.
        maximumConcurrentStarts = max(maximumConcurrentStarts, concurrentStarts) // Detects any overlap.
        defer { concurrentStarts -= 1 } // Restores the active count after completion.
        onOutput("Ready \(modelReference)") // Exercises process output forwarding.
        try await Task.sleep(for: .milliseconds(5)) // Preserves asynchronous readiness behavior.
        return configuration.requestedPort + starts // Supplies a distinct ready port for each physical model.
    } // Ends fake workflow server start.

    func stop() async { // Simulates full release of the current model.
        try? await Task.sleep(for: .milliseconds(1)) // Preserves awaited stop semantics.
    } // Ends fake workflow server stop.

    func metrics() -> WorkflowServerMetrics { // Returns immutable physical lifecycle metrics.
        WorkflowServerMetrics(starts: starts, maximumConcurrentStarts: maximumConcurrentStarts) // Returns counts atomically from the actor.
    } // Ends workflow server metrics access.
} // Ends workflow fake server controller.

private struct WorkflowServerMetrics { // Stores immutable fake workflow lifecycle metrics.
    let starts: Int // Stores total physical model starts.
    let maximumConcurrentStarts: Int // Stores highest start overlap.
} // Ends workflow lifecycle metrics.

private actor WorkflowRecordingClient: LLMCompleting { // Returns stage-specific valid answers and records actual selected model references.
    private var references: [String] = [] // Stores completion model references in execution order.

    func complete(_ request: LLMCompletionRequest) async throws -> String { // Simulates a valid local completion for every agent stage.
        references.append(request.model.id) // Records the exact model supplied by WorkflowEngine.
        if request.systemPrompt.contains("Reviewer Agent") { return "Reviewed candidate" } // Returns a valid reviewer output.
        if request.systemPrompt.contains("Final Composer") { return "Final answer" } // Returns a valid final output.
        return "Specialist candidate" // Returns a valid coding specialist output.
    } // Ends deterministic completion behavior.

    func modelReferences() -> [String] { // Returns recorded physical model references atomically.
        references // Returns completion order for assertions.
    } // Ends recorded model access.
} // Ends workflow recording completion client.
