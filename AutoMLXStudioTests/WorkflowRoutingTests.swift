import XCTest // Supplies unit-test assertions and asynchronous test support.
@testable import AutoMLXStudio // Exposes internal V0.1 orchestration types to the test target.

final class WorkflowRoutingTests: XCTestCase { // Verifies the required deterministic routing and recovery behaviors.
    private let router = DeterministicFastRouter() // Uses the same zero-inference router configured in WorkflowEngine.

    func testRequiredGeneralRoutingCase() { // Verifies the required CPU definition prompt.
        let decision = router.route("What is a CPU?") // Routes the exact prompt from the V0.1 acceptance criteria.
        XCTAssertEqual(decision.intent, .general) // Confirms General Agent intent selection.
    } // Ends the required general routing test.

    func testRequiredCodingRoutingCase() { // Verifies the original Python array prompt now reaches the more specific V0.5 logical specialist.
        let decision = router.route("Write a Python function that returns the largest number in an array.") // Routes the exact original acceptance prompt through the expanded taxonomy.
        XCTAssertEqual(decision.intent, .python) // Confirms the intentional V0.5 Python Agent specialization supersedes only the former generic Coding route.
    } // Ends the required coding-prompt routing test.

    func testRequiredSwiftRoutingCase() { // Verifies the required Swift function prompt.
        let decision = router.route("Write a simple Swift function that adds two numbers.") // Routes the exact Swift acceptance prompt.
        XCTAssertEqual(decision.intent, .swift) // Confirms Swift Agent intent selection.
    } // Ends the required Swift routing test.

    func testRequiredResearchRoutingCase() { // Verifies the required MLX documentation prompt.
        let decision = router.route("Find documentation about MLX model quantization.") // Routes the exact research acceptance prompt.
        XCTAssertEqual(decision.intent, .research) // Confirms Research Agent intent selection.
    } // Ends the required research routing test.

    func testDirectorUsesCentralIntentMapping() throws { // Verifies every supported intent maps to the required specialist ID.
        let registry = AgentRegistry() // Creates the same central registry used by the application.
        let director = Director(registry: registry) // Creates the deterministic director from that registry.
        let expected: [UserIntent: String] = [.general: AgentID.general, .coding: AgentID.coding, .swift: AgentID.swift, .research: AgentID.research] // Declares the V0.1 acceptance mapping.
        for (intent, specialistID) in expected { // Checks each supported structured intent.
            let decision = RoutingDecision(intent: intent, confidence: 1, summary: "Test") // Creates deterministic structured input for Director.
            let plan = try director.makePlan(for: decision, request: "A non-trivial request with enough detail to use the complete workflow.") // Produces the centralized workflow plan.
            XCTAssertEqual(plan.specialistID, specialistID) // Confirms the selected registry destination.
        } // Ends intent mapping iteration.
    } // Ends the central Director mapping test.

    func testResearchAgentForbidsFabricatedSearchesAndCitations() { // Verifies the V0.1 research safety instruction remains centralized.
        let prompt = AgentRegistry().agent(id: AgentID.research)?.systemPrompt.lowercased() ?? "" // Reads the actual registered Research Agent prompt.
        XCTAssertTrue(prompt.contains("no external web-search tool")) // Confirms the prompt states the real tool limitation.
        XCTAssertTrue(prompt.contains("never fabricate")) // Confirms fabricated sources and citations are prohibited.
    } // Ends the Research Agent safety test.

    func testTrivialGeneralWorkflowRecordsSkippedQualityStages() async { // Verifies the explicit low-latency optimization and its trace.
        let engine = WorkflowEngine(client: ConstantCompletionClient(response: "A CPU executes instructions.")) // Uses a deterministic local test completion client.
        let result = await engine.execute(userInput: "What is a CPU?", conversationHistory: [], model: Self.testModel, serverPort: 8080) // Runs the exact trivial general workflow.
        XCTAssertEqual(result.trace.specialistID, AgentID.general) // Confirms General Agent execution.
        XCTAssertEqual(result.trace.steps.first(where: { $0.stage == .reviewer })?.status, .skipped) // Confirms Reviewer is visibly skipped.
        XCTAssertEqual(result.trace.steps.first(where: { $0.stage == .finalComposer })?.status, .skipped) // Confirms Final Composer is visibly skipped.
        XCTAssertEqual(result.trace.status, .succeeded) // Confirms the intentional fast path is not marked degraded.
    } // Ends the direct-workflow trace test.

    func testReviewerFailurePreservesSpecialistAndStillComposes() async { // Verifies graceful recovery from a later QA failure.
        let client = ScriptedCompletionClient(results: [.success("Specialist candidate"), .failure(TestCompletionError.expected), .success("Composed fallback")]) // Scripts specialist success, reviewer failure, and composer success.
        let engine = WorkflowEngine(client: client) // Injects the deterministic failure sequence.
        let result = await engine.execute(userInput: "Write a Python function for a maintainable parser.", conversationHistory: [], model: Self.testModel, serverPort: 8080) // Runs a full coding workflow.
        XCTAssertEqual(result.answer, "Composed fallback") // Confirms Final Composer receives the preserved specialist candidate.
        XCTAssertEqual(result.trace.status, .degraded) // Confirms the later failure is visible at workflow level.
        XCTAssertEqual(result.trace.steps.first(where: { $0.stage == .reviewer })?.status, .failed) // Confirms the Reviewer failure is retained in the trace.
        XCTAssertEqual(result.trace.steps.first(where: { $0.stage == .finalComposer })?.status, .succeeded) // Confirms later recovery execution continues.
    } // Ends reviewer-failure recovery testing.

    func testFinalComposerFailureReturnsReviewedCandidate() async { // Verifies the best intermediate answer survives output-stage failure.
        let client = ScriptedCompletionClient(results: [.success("Specialist candidate"), .success("Reviewed candidate"), .failure(TestCompletionError.expected)]) // Scripts a terminal composer failure after two valid candidates.
        let engine = WorkflowEngine(client: client) // Injects the deterministic failure sequence.
        let result = await engine.execute(userInput: "Write a Python function for a maintainable parser.", conversationHistory: [], model: Self.testModel, serverPort: 8080) // Runs the full coding workflow.
        XCTAssertEqual(result.answer, "Reviewed candidate") // Confirms the best valid intermediate answer is returned.
        XCTAssertEqual(result.trace.status, .degraded) // Confirms graceful recovery is visible.
        XCTAssertEqual(result.trace.steps.last?.status, .failed) // Confirms Final Composer failure remains in the operational trace.
    } // Ends final-composer fallback testing.

    private static let testModel = LLMModel( // Creates a deterministic capable model without contacting MLX.
        id: "test/local-model", // Supplies a non-empty OpenAI-compatible model identifier.
        name: "local-model", // Supplies a concise trace display name.
        repository: "test/local-model", // Supplies the model registry reference.
        capabilities: [.general, .reasoning, .coding, .research] // Satisfies all V0.1 agent capability declarations.
    ) // Ends the deterministic test model.
} // Ends the V0.1 workflow routing test suite.

private struct ConstantCompletionClient: LLMCompleting { // Provides one fixed model response for simple workflow tests.
    let response: String // Stores the deterministic response returned for every completion.

    func complete(_ request: LLMCompletionRequest) async throws -> String { // Satisfies the clean completion-client interface without network access.
        response // Returns the fixed response regardless of stage payload.
    } // Ends fixed completion execution.
} // Ends the constant test completion client.

private actor ScriptedCompletionClient: LLMCompleting { // Provides ordered success and failure results safely across async calls.
    private var results: [Result<String, Error>] // Stores the remaining scripted completion outcomes.

    init(results: [Result<String, Error>]) { // Accepts the exact sequence required by a recovery test.
        self.results = results // Stores the scripted sequence inside actor isolation.
    } // Ends scripted client construction.

    func complete(_ request: LLMCompletionRequest) async throws -> String { // Returns the next scripted model outcome.
        guard !results.isEmpty else { throw TestCompletionError.missingResult } // Fails clearly if the workflow performs an unexpected extra inference.
        let result = results.removeFirst() // Consumes exactly one stage outcome.
        return try result.get() // Returns or throws the scripted value.
    } // Ends scripted completion execution.
} // Ends the actor-isolated scripted completion client.

private enum TestCompletionError: LocalizedError { // Defines intentional deterministic completion failures.
    case expected // Represents a failure deliberately injected by a recovery test.
    case missingResult // Represents an unexpected extra workflow inference.

    var errorDescription: String? { // Supplies concise trace diagnostics during test execution.
        switch self { // Selects the diagnostic for the current test error.
        case .expected: return "Expected test completion failure." // Describes the deliberate failure.
        case .missingResult: return "No scripted completion result remained." // Describes an unexpected call count.
        } // Ends test error selection.
    } // Ends the localized test error accessor.
} // Ends deterministic test completion errors.
