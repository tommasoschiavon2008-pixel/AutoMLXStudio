import XCTest // Supplies asynchronous integration-test assertions and expectations.
@testable import AutoMLXStudio // Exposes the real MLX service and workflow engine to the opt-in test.

final class MLXIntegrationTests: XCTestCase { // Verifies the existing local server and new orchestration together when explicitly enabled.
    func testRealServerAutoPortFullWorkflowAndStop() async throws { // Exercises start, automatic free port, three real inferences, trace, and stop.
        guard ProcessInfo.processInfo.environment["RUN_MLX_INTEGRATION_TESTS"] == "1" else { // Keeps normal unit-test runs fast and deterministic.
            throw XCTSkip("Set RUN_MLX_INTEGRATION_TESTS=1 to run the real local MLX integration test.") // Explains how to enable the hardware-backed test.
        } // Ends opt-in integration-test gating.

        let repositoryPath = "/Volumes/Crucial X9 Pro/app/MLX/mlx-lm-main" // Uses the working MLX repository supplied in the project brief.
        let executableDirectory = "\(repositoryPath)/.venv/bin" // Resolves the existing virtual-environment command directory.
        let modelIdentifier = "mlx-community/Llama-3.2-3B-Instruct-4bit" // Uses the currently configured V0.1 local model.
        let service = MLXService() // Creates the same concrete service owned by AppState.
        defer { service.stopServer() } // Guarantees the integration test never leaves its server process running.

        let startCompleted = expectation(description: "MLX server start completed") // Waits for either a ready port or a concrete startup failure.
        let startOutcome = LockedStartOutcome() // Stores callback state safely across the detached readiness task.
        service.startServer( // Starts the real server through the unchanged application service.
            executableDirectory: executableDirectory, // Uses the supplied working virtual environment.
            repoPath: repositoryPath, // Uses the supplied MLX repository as the process directory.
            model: modelIdentifier, // Loads the shared V0.1 model.
            requestedPort: 8080, // Intentionally requests the known occupied local port for auto-selection coverage.
            autoSelectPort: true, // Enables the existing next-free-port behavior.
            onOutput: { _ in }, // Keeps verbose model-load output out of the test report.
            onStarted: { actualPort in // Receives the ready port selected by MLXService.
                startOutcome.set(.started(actualPort)) // Stores the successful ready result.
                startCompleted.fulfill() // Releases the asynchronous test wait.
            }, // Ends successful-start handling.
            onFailure: { message in // Receives a concrete startup or readiness error.
                startOutcome.set(.failed(message)) // Stores the failure diagnostic for assertion output.
                startCompleted.fulfill() // Releases the asynchronous test wait.
            }, // Ends startup-failure handling.
            onExit: { _ in } // Leaves process-exit reporting to the explicit stop assertion below.
        ) // Ends real server startup.

        await fulfillment(of: [startCompleted], timeout: 240) // Allows model loading on Apple Silicon without an unbounded wait.
        let actualPort: Int // Declares the ready port required by the real workflow.
        switch startOutcome.get() { // Interprets the synchronized startup result.
        case let .started(port): actualPort = port // Preserves the actual automatically selected port.
        case let .failed(message): XCTFail("Real MLX server failed to start: \(message)"); return // Fails with the concrete service diagnostic.
        case nil: XCTFail("MLX service returned no startup outcome."); return // Fails if callback behavior is incomplete.
        } // Ends startup result interpretation.

        XCTAssertNotEqual(actualPort, 8080) // Confirms the occupied requested port was not reused.
        XCTAssertGreaterThan(actualPort, 8080) // Confirms the existing next-free-port policy selected a later port.

        let registry = AgentRegistry() // Creates the same centralized agent registry used by AppState.
        let engine = WorkflowEngine(client: MLXCompletionClient(service: service), registry: registry) // Connects real orchestration to the server process created above.
        let model = ModelRegistry().mainModel(identifier: modelIdentifier) // Resolves the configured model through the V0.1 abstraction.
        let result = await engine.execute( // Runs the full three-inference workflow end to end.
            userInput: "Write a Python function that returns the largest number in an array.", // Uses the required coding acceptance prompt.
            conversationHistory: [], // Starts with a clean bounded context for deterministic verification.
            model: model, // Assigns the real shared local model to all three LLM stages.
            serverPort: actualPort // Uses the actual automatically selected ready port.
        ) // Ends the real orchestrated completion request.

        XCTAssertFalse(result.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) // Confirms Chat can receive a real non-empty MLX response.
        XCTAssertEqual(result.trace.intent, .coding) // Confirms the required prompt routes to coding intent.
        XCTAssertEqual(result.trace.specialistID, AgentID.coding) // Confirms Director selected Coding Agent.
        XCTAssertEqual(result.trace.modelIdentifier, modelIdentifier) // Confirms the currently configured model executed.
        XCTAssertEqual(result.trace.status, .succeeded) // Confirms Specialist, Reviewer, and Final Composer all completed.
        XCTAssertEqual(result.trace.steps.map(\.stage), [.fastRouter, .director, .specialist, .reviewer, .finalComposer]) // Confirms the complete real stage order.
        XCTAssertTrue(result.trace.steps.allSatisfy { $0.status == .succeeded }) // Confirms AgentsView will receive a fully successful actual trace.

        service.stopServer() // Stops the exact process created by this integration test.
        try await Task.sleep(for: .seconds(2)) // Allows graceful termination before checking the endpoint.
        let stillResponding = await Self.isServerReady(port: actualPort) // Tests whether the stopped process still exposes the MLX endpoint.
        XCTAssertFalse(stillResponding) // Confirms stopServer removed the integration-test listener.
    } // Ends the real MLX integration test.

    private static func isServerReady(port: Int) async -> Bool { // Performs a bounded readiness probe for the stop assertion.
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/models") else { return false } // Builds the same readiness endpoint used by MLXService.
        var request = URLRequest(url: url) // Creates the local readiness request.
        request.timeoutInterval = 0.5 // Prevents a stopped or stuck endpoint from delaying the test.
        do { // Attempts the bounded readiness probe.
            let (_, response) = try await URLSession.shared.data(for: request) // Requests local model metadata.
            return (response as? HTTPURLResponse)?.statusCode == 200 // Treats only an MLX success response as still running.
        } catch { // Handles the expected connection failure after stop.
            return false // Reports that the local server is no longer ready.
        } // Ends readiness probe recovery.
    } // Ends the integration-test readiness helper.
} // Ends the opt-in MLX integration test suite.

private enum IntegrationStartOutcome { // Represents the two terminal MLX startup callback outcomes.
    case started(Int) // Stores the actual ready port.
    case failed(String) // Stores the concrete startup diagnostic.
} // Ends startup outcome definition.

private final class LockedStartOutcome: @unchecked Sendable { // Synchronizes callback data shared with the asynchronous XCTest task.
    private let lock = NSLock() // Protects the single startup outcome value.
    private var value: IntegrationStartOutcome? // Stores the first terminal startup result.

    func set(_ newValue: IntegrationStartOutcome) { // Stores a callback outcome safely.
        lock.lock() // Begins exclusive access to the outcome.
        defer { lock.unlock() } // Guarantees the lock is released on every return path.
        guard value == nil else { return } // Preserves the first terminal callback if a later process event arrives.
        value = newValue // Stores the startup result.
    } // Ends synchronized outcome storage.

    func get() -> IntegrationStartOutcome? { // Reads the callback outcome safely after expectation fulfillment.
        lock.lock() // Begins exclusive access to the outcome.
        defer { lock.unlock() } // Guarantees the lock is released after reading.
        return value // Returns the stored startup result.
    } // Ends synchronized outcome reading.
} // Ends the callback outcome container.
