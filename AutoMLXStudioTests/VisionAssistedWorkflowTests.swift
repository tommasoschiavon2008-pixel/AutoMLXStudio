import Foundation // Supplies temporary URLs and deterministic fixture values.
import XCTest // Supplies asynchronous workflow assertions.
@testable import AutoMLXStudio // Exposes internal routing, registry, Vision, and workflow types.

final class VisionAssistedWorkflowTests: XCTestCase { // Verifies deterministic screenshot-to-Swift orchestration without hardware or text fallback.
    func testScreenshotWithSwiftQuestionRunsVisionThenSwiftReviewerAndComposer() async throws { // Covers the required cross-agent handoff order.
        let environment = try VisionWorkflowEnvironment() // Creates an isolated executable and registry fixture.
        defer { environment.cleanup() } // Removes only the UUID-scoped test environment.
        let controller = VisionWorkflowController() // Creates a deterministic text server lifecycle fake.
        let manager = ModelResourceManager(controller: controller) // Creates the production central resource manager around the fake process boundary.
        let client = VisionWorkflowCompletionClient(responses: ["Swift fix", "Reviewed fix", "Final fix"]) // Scripts Swift, Reviewer, and Composer text outputs only.
        let vision = VisionWorkflowService() // Supplies actual-typed structured Vision output without invoking hardware.
        let engine = WorkflowEngine(client: client, resourceManager: manager, visionService: vision) // Connects the production router and workflow with injected inference boundaries.
        let request = UserRequest(text: "Why is this SwiftUI code failing?", attachments: [.image(environment.image)]) // Creates the required screenshot-plus-Swift request shape.
        let result = await engine.execute(request: request, conversationHistory: [], modelRegistry: environment.registry, runtimeConfiguration: environment.configuration, switchPolicy: .qualityPreferred) // Runs the full Vision-assisted multi-model workflow.
        XCTAssertEqual(result.trace.intent, .swift) // Confirms the image did not force a pure Vision response.
        XCTAssertEqual(result.trace.specialistID, AgentID.swift) // Confirms Swift Agent owns the technical response.
        XCTAssertEqual(result.answer, "Final fix") // Confirms the complete quality pipeline reached Final Composer.
        XCTAssertEqual(result.trace.status, .succeeded) // Confirms all required and optional stages succeeded.
        let inferenceNames = result.trace.steps.filter { [.specialist, .reviewer, .finalComposer].contains($0.stage) && $0.status == .succeeded }.map(\.name) // Extracts actual successful inference order.
        XCTAssertEqual(inferenceNames, ["Vision Agent", "Swift Agent", "Reviewer Agent", "Final Composer"]) // Confirms the required non-recursive stage sequence.
        XCTAssertEqual(result.trace.modelExecutions.first?.selectedModelID, "vision") // Confirms the first physical execution is the VLM.
        XCTAssertEqual(result.trace.modelExecutions.first?.launchReference, environment.visionPath.path) // Confirms the exact Vision path is retained.
        let prompts = await client.receivedPrompts() // Reads actor-isolated text prompts after workflow completion.
        XCTAssertTrue(prompts.first?.contains("Visible text: Cannot convert value") == true) // Confirms structured visual evidence reached Swift Agent.
        XCTAssertFalse(prompts.contains { $0.contains("fake text-only vision") }) // Confirms no text completion substituted for Vision.
        await manager.stop() // Releases the final fake text runtime.
    } // Ends screenshot-to-Swift workflow test.

    func testImageRoutingRulesDistinguishPureVisionFromVisionAssistedCoding() { // Verifies deterministic multimodal routing quality directly.
        let image = ImageAttachment(url: URL(fileURLWithPath: "/tmp/routing.png"), originalFilename: "routing.png", contentTypeIdentifier: "public.png", byteCount: 1, pixelWidth: 1, pixelHeight: 1) // Creates URL-backed routing metadata without image decoding.
        let router = DeterministicFastRouter() // Uses the production ordered router.
        let pure = router.route(UserRequest(text: "What is in this image?", attachments: [.image(image)])) // Creates a photo-description request.
        let swift = router.route(UserRequest(text: "Why is this SwiftUI code failing?", attachments: [.image(image)])) // Creates an image-assisted Swift request.
        let python = router.route(UserRequest(text: "Debug this Python exception", attachments: [.image(image)])) // Creates an image-assisted request for the dedicated V0.5 Python specialist.
        XCTAssertEqual(pure.intent, .vision) // Confirms descriptive image work remains pure Vision.
        XCTAssertEqual(swift.intent, .swift) // Confirms Swift signals retain their specialist.
        XCTAssertEqual(python.intent, .python) // Confirms explicit Python signals retain their dedicated logical specialist.
        XCTAssertTrue(pure.requiresVisionAnalysis && swift.requiresVisionAnalysis && python.requiresVisionAnalysis) // Confirms every image-bearing path still requires real visual analysis.
    } // Ends multimodal routing rule test.
} // Ends Vision-assisted workflow tests.

private struct VisionWorkflowEnvironment { // Owns one isolated fake MLX environment, image reference, and complete registry.
    let root: URL // Stores the UUID-scoped test root.
    let visionPath: URL // Stores the exact fake physical Vision path retained in trace metadata.
    let image: ImageAttachment // Stores the typed image used by routing and the fake Vision service.
    let registry: ModelRegistry // Stores explicit Vision, Swift, Reviewer, and Composer assignments.
    let configuration: ModelRuntimeConfiguration // Stores the fake text executable and working directory.

    init() throws { // Creates all deterministic workflow fixtures.
        root = FileManager.default.temporaryDirectory.appendingPathComponent("VisionWorkflow-\(UUID().uuidString)", isDirectory: true) // Allocates one isolated root.
        let bin = root.appendingPathComponent("bin", isDirectory: true) // Resolves the fake virtual-environment executable folder.
        visionPath = root.appendingPathComponent("vision-model", isDirectory: true) // Resolves the fake physical VLM folder used only by the injected service.
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true) // Creates the test directories.
        try FileManager.default.createDirectory(at: visionPath, withIntermediateDirectories: true) // Creates the exact fake Vision path.
        let executable = bin.appendingPathComponent("mlx_lm.server", isDirectory: false) // Resolves the executable required by text adapter validation.
        try Data("#!/bin/sh\n".utf8).write(to: executable) // Writes a harmless test-owned executable fixture.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path) // Makes the fake entrypoint executable.
        let imageURL = root.appendingPathComponent("screenshot.png", isDirectory: false) // Resolves the fake screenshot reference.
        try Data([0]).write(to: imageURL) // Creates a regular file because the injected Vision service does not decode it.
        image = ImageAttachment(url: imageURL, originalFilename: "screenshot.png", contentTypeIdentifier: "public.png", byteCount: 1, pixelWidth: 1, pixelHeight: 1) // Creates complete validated-style attachment metadata.
        let visionModel = ModelProfile(id: "vision", displayName: "Vision", repositoryID: "vision", localPath: visionPath.path, backend: .mlxVLM, capabilities: [.vision], approximateDiskGB: 1, approximateMemoryGB: 1, enabled: true, installationState: .installed, runtimeState: .unloaded, isLegacyFallback: false, statusDetail: nil) // Creates the selected VLM profile.
        let coder = Self.textProfile(id: "coder", capabilities: [.general, .reasoning, .coding, .swiftLanguage]) // Creates the Swift-specialist text model.
        let reviewer = Self.textProfile(id: "reviewer", capabilities: [.general, .reasoning]) // Creates the reviewer text model.
        let general = Self.textProfile(id: "general", capabilities: [.general, .reasoning]) // Creates the composer text model.
        let assignments = [ // Defines explicit deterministic agent-to-model mappings.
            ModelAssignment(agentID: AgentID.vision, preferredModelID: visionModel.id, preferredCapability: .vision, fallbackModelIDs: [], fallbackCapabilities: [.vision], allowsRuntimeReuse: false), // Assigns only the real VLM to Vision.
            ModelAssignment(agentID: AgentID.swift, preferredModelID: coder.id, preferredCapability: .swiftLanguage, fallbackModelIDs: [], fallbackCapabilities: [.coding], allowsRuntimeReuse: false), // Assigns Swift Agent to coder.
            ModelAssignment(agentID: AgentID.reviewer, preferredModelID: reviewer.id, preferredCapability: .reasoning, fallbackModelIDs: [], fallbackCapabilities: [.reasoning], allowsRuntimeReuse: false), // Assigns Reviewer to reasoning.
            ModelAssignment(agentID: AgentID.finalComposer, preferredModelID: general.id, preferredCapability: .general, fallbackModelIDs: [], fallbackCapabilities: [.general], allowsRuntimeReuse: false) // Assigns Final Composer to general.
        ] // Ends explicit assignments.
        registry = ModelRegistry(models: [visionModel, coder, reviewer, general], assignments: assignments, legacyFallbackModelID: general.id, modelsRoot: root.path) // Creates the complete isolated registry.
        configuration = ModelRuntimeConfiguration(executableDirectory: bin.path, repoPath: root.path, requestedPort: 23_000, autoSelectPort: true) // Creates fake runtime configuration accepted by text validation.
    } // Ends workflow environment construction.

    private static func textProfile(id: String, capabilities: Set<ModelCapability>) -> ModelProfile { // Creates a repository-backed validation-safe text profile.
        ModelProfile(id: id, displayName: id.capitalized, repositoryID: id, localPath: nil, backend: .mlxLM, capabilities: capabilities, approximateDiskGB: nil, approximateMemoryGB: 1, enabled: true, installationState: .installed, runtimeState: .unloaded, isLegacyFallback: true, statusDetail: nil) // Returns a fake model that preserves existing legacy validation behavior.
    } // Ends fake text-profile construction.

    func cleanup() { try? FileManager.default.removeItem(at: root) } // Removes only this exact UUID-scoped root.
} // Ends Vision workflow test environment.

private actor VisionWorkflowController: ModelServerControlling { // Supplies deterministic ready ports for text stages without starting processes.
    private var starts = 0 // Counts physical text load attempts.
    func start(modelReference: String, configuration: ModelRuntimeConfiguration, onOutput: @escaping (String) -> Void) async throws -> Int { starts += 1; return configuration.requestedPort + starts } // Returns a distinct ready port per text model.
    func stop() async {} // Implements verified compatibility shutdown without owning a real process.
} // Ends fake text server controller.

private actor VisionWorkflowCompletionClient: LLMCompleting { // Supplies ordered text outputs and records the Vision-assisted prompt.
    private var responses: [String] // Stores Swift, Reviewer, and Composer outputs in order.
    private var prompts: [String] = [] // Stores only received user prompts for assertions.
    init(responses: [String]) { self.responses = responses } // Stores the deterministic response sequence.
    func complete(_ request: LLMCompletionRequest) async throws -> String { // Returns one output per expected text stage.
        prompts.append(request.userPrompt) // Records the exact handoff prompt.
        guard !responses.isEmpty else { throw VisionWorkflowTestError.unexpectedCompletion } // Fails if Vision incorrectly calls the text client or the workflow adds a stage.
        return responses.removeFirst() // Returns the next deterministic candidate.
    } // Ends fake text completion.
    func receivedPrompts() -> [String] { prompts } // Returns actor-isolated prompt evidence.
} // Ends recording completion client.

private struct VisionWorkflowService: VisionInferencing { // Supplies actual-typed Vision output and structured evidence without hardware.
    func analyze(images: [ImageAttachment], userPrompt: String, model: ModelProfile, configuration: ModelRuntimeConfiguration) async throws -> VisionResult { // Returns deterministic fake VLM output for orchestration testing.
        let analysis = VisualAnalysis(summary: "Xcode shows a SwiftUI type error.", visibleText: ["Cannot convert value"], likelyContext: "SwiftUI compiler diagnostic") // Creates structured visual evidence.
        return VisionResult(output: "SUMMARY: Xcode shows a SwiftUI type error.\nVISIBLE_TEXT: Cannot convert value\nLIKELY_CONTEXT: SwiftUI compiler diagnostic", analysis: analysis, modelID: model.id, modelPath: model.launchReference, loadDurationMilliseconds: nil, inferenceDurationMilliseconds: 5, residencyDecision: .load) // Returns physical and timing metadata with no text fallback.
    } // Ends fake Vision inference.
} // Ends fake Vision service.

private enum VisionWorkflowTestError: LocalizedError { // Defines an unexpected text-inference call count.
    case unexpectedCompletion // Indicates the workflow invoked more text stages than expected.
    var errorDescription: String? { "Unexpected text completion call." } // Supplies a concise failure diagnostic.
} // Ends Vision workflow test errors.
