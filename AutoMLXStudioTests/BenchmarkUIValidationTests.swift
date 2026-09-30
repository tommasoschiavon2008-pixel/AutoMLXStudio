import AppKit // Supplies test-owned native windows and lossless bitmap rendering for Benchmark UI evidence.
import SwiftUI // Supplies NSHostingView composition around the real production Benchmark surface.
import XCTest // Supplies deterministic assertions for controller lifecycle and rendered geometry.
@testable import AutoMLXStudio // Exposes internal Benchmark pages and dependencies to the test target only.

private struct BenchmarkUILayoutFailure: LocalizedError, Sendable { // Supplies one controlled visible backend error without network or model inference.
    var errorDescription: String? { "Deterministic UI validation backend failure." } // Returns bounded non-sensitive error copy for the result detail.
} // Ends controlled layout failure.

private struct BenchmarkUILayoutClient: BenchmarkGenerationClient { // Supplies success, failure, or cancellable waiting behavior through the production engine protocol.
    enum Behavior: Sendable { // Defines the only three offline UI fixture outcomes.
        case success // Returns a deterministic exact-match response with large truthful usage values.
        case failure // Throws a bounded deterministic backend-style error.
        case waitForCancellation // Suspends cooperatively until the controller Stop action cancels generation.
    } // Ends fixture behaviors.

    let behavior: Behavior // Stores the selected deterministic behavior.
    let target: ModelGenerationTarget // Stores the exact backend-qualified fixture target.

    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult { // Produces one normalized result through the real engine boundary.
        switch behavior { // Selects the requested isolated fixture behavior.
        case .success: // Produces a complete exact response.
            return ModelGenerationResult(text: "ok", toolCalls: [], usage: .init(inputTokens: 123_456, outputTokens: 98_765, totalTokens: 222_221), finishReason: .stop, modelID: target.modelID, backendID: target.backendID, durationMilliseconds: 123_456) // Exercises large metrics and long model identity without inventing production evidence.
        case .failure: // Produces one visible isolated error result.
            throw BenchmarkUILayoutFailure() // Lets the production evaluator classify and retain the error.
        case .waitForCancellation: // Produces a real cooperative running state.
            try await Task.sleep(nanoseconds: 60_000_000_000) // Waits without blocking a thread and exits immediately on Stop cancellation.
            return ModelGenerationResult(text: "ok", toolCalls: [], usage: nil, finishReason: .stop, modelID: target.modelID, backendID: target.backendID, durationMilliseconds: 60_000) // Supplies a structurally valid unreachable fallback if no cancellation occurs.
        } // Ends fixture behavior selection.
    } // Ends deterministic generation.
} // Ends offline Benchmark UI client.

private actor BenchmarkUILayoutSequenceClient: BenchmarkGenerationClient { // Produces one completed case followed by one cancellable in-flight case for controller Stop validation.
    let target: ModelGenerationTarget // Stores the exact fixture target for normalized result metadata.
    private var calls = 0 // Counts strictly sequential evaluator requests inside actor isolation.

    init(target: ModelGenerationTarget) { // Creates the deterministic two-stage client.
        self.target = target // Stores exact backend-qualified identity.
    } // Ends sequence-client construction.

    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult { // Responds successfully once and then waits cooperatively.
        calls += 1 // Records the current sequential request safely.
        if calls == 1 { return ModelGenerationResult(text: "ok", toolCalls: [], usage: .init(inputTokens: 10, outputTokens: 2, totalTokens: 12), finishReason: .stop, modelID: target.modelID, backendID: target.backendID, durationMilliseconds: 10) } // Completes the first case so Stop must preserve real evidence.
        try await Task.sleep(nanoseconds: 60_000_000_000) // Keeps the second case in progress until controller cancellation.
        return ModelGenerationResult(text: "ok", toolCalls: [], usage: nil, finishReason: .stop, modelID: target.modelID, backendID: target.backendID, durationMilliseconds: 60_000) // Supplies an unreachable valid fallback if cancellation is never requested.
    } // Ends staged generation.
} // Ends sequential cancellation client.

@MainActor
final class BenchmarkUIValidationTests: XCTestCase { // Validates native Benchmark layouts and app-owned controller states without desktop or external-system access.
    private let longTarget = ModelGenerationTarget(backendID: .localMLX, location: .local, modelID: "fixture/extremely-long-model-identifier-for-benchmark-clipping-truncation-and-accessibility-validation-4bit") // Exercises model-name truncation while preserving exact identity.

    func testBenchmarkIdlePagesRenderAtNormalAndMinimumSizes() async throws { // Renders empty Dashboard, New Run, History, Comparison, and Custom Suite destinations at required sizes.
        let root = temporaryDirectory("idle-pages") // Creates one isolated persistence and workspace root.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only the exact test-owned fixture after rendering.
        let controller = BenchmarkController(store: BenchmarkStore(rootURL: root.appendingPathComponent("benchmarks", isDirectory: true)), client: BenchmarkUILayoutClient(behavior: .success, target: longTarget)) // Creates an empty app-owned-style controller with no network dependency.
        await controller.load() // Publishes the intentional first-use history state.
        let app = makeApp(root: root) // Creates an isolated environment object without background discovery.
        for page in BenchmarkPage.allCases { // Renders every idle destination from the production view router.
            try render(controller: controller, app: app, page: page, caseResultID: nil, size: NSSize(width: 1_180, height: 760), outputName: "Benchmark-\(page.rawValue.replacingOccurrences(of: " ", with: ""))-Normal.png") // Captures normal-size layout evidence for the selected destination.
        } // Ends normal idle destination rendering.
        try render(controller: controller, app: app, page: .overview, caseResultID: nil, size: NSSize(width: 850, height: 686), outputName: "Benchmark-Overview-Minimum.png") // Captures the supported minimum empty Dashboard geometry.
        try render(controller: controller, app: app, page: .newRun, caseResultID: nil, size: NSSize(width: 850, height: 686), outputName: "Benchmark-NewRun-Minimum.png") // Captures scrollable minimum New Run geometry.
    } // Ends idle native layout coverage.

    func testBenchmarkRunningResultsComparisonHistoryCaseErrorAndCancelledStatesRender() async throws { // Renders all data-bearing and lifecycle states using the real evaluator, store, controller, and view.
        let root = temporaryDirectory("state-pages") // Creates an isolated root for durable completed and error runs.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only this exact test-owned root.
        let store = BenchmarkStore(rootURL: root.appendingPathComponent("benchmarks", isDirectory: true)) // Creates the real versioned persistence actor in isolation.
        let engine = BenchmarkEvaluationEngine(elapsedOverride: { _, _ in 123_456 }) // Supplies a deterministic large elapsed metric solely for layout stress evidence.
        let suite = fixtureSuite() // Creates two safe declarative exact-match cases.
        let completed = try await engine.run(suite: suite, configuration: configuration(target: longTarget), environment: fixtureEnvironment, client: BenchmarkUILayoutClient(behavior: .success, target: longTarget)) // Produces complete production-shaped result evidence offline.
        try await store.save(run: completed) // Persists the first complete run through schema-versioned storage.
        let peerTarget = ModelGenerationTarget(backendID: .remoteOpenAICompatible, location: .remote(serverID: UUID(uuidString: "E0610000-0000-4000-8000-000000000099")!), modelID: "fixture/second-comparable-remote-model-with-a-very-long-provider-qualified-name") // Supplies a distinct backend/server/model identity without making a remote request.
        let peerConfiguration = configuration(target: peerTarget).model // Captures otherwise comparable generation settings for the second model.
        let peer = BenchmarkRun(id: UUID(), suiteID: completed.suiteID, suiteName: completed.suiteName, suiteVersion: completed.suiteVersion, caseIDs: completed.caseIDs, mode: completed.mode, selectedCategory: completed.selectedCategory, modelConfiguration: peerConfiguration, environment: completed.environment, scoreWeights: completed.scoreWeights, startedAt: completed.startedAt.addingTimeInterval(-60), completedAt: completed.completedAt, state: .completed, results: completed.results, summary: completed.summary, isBaseline: true, issue: nil, isDeterministicDemo: true) // Creates a second fair comparison snapshot while clearly marking fixture evidence.
        try await store.save(run: peer) // Persists the comparable peer independently.
        let errorTarget = ModelGenerationTarget(backendID: .localMLX, location: .local, modelID: "fixture/error-state-model") // Supplies one exact target for visible error-state evidence.
        let errorRun = try await engine.run(suite: suite, configuration: configuration(target: errorTarget), environment: fixtureEnvironment, client: BenchmarkUILayoutClient(behavior: .failure, target: errorTarget)) // Produces isolated error cases while completing the suite.
        try await store.save(run: errorRun) // Persists the error-bearing run without converting failure to skip.
        let controller = BenchmarkController(store: store, engine: engine, client: BenchmarkUILayoutClient(behavior: .success, target: longTarget)) // Creates the real controller over the populated isolated store.
        await controller.load() // Restores history and the newest selection.
        let app = makeApp(root: root) // Creates an isolated environment object without hardware or remote background tasks.
        controller.selectedRunID = completed.id // Selects the complete run for Results and case inspection.
        try render(controller: controller, app: app, page: .overview, caseResultID: completed.results.first?.id, size: NSSize(width: 1_180, height: 760), outputName: "Benchmark-Results-CaseDetail-Normal.png") // Captures scores, large metrics, table, and the selected case detail.
        try render(controller: controller, app: app, page: .overview, caseResultID: completed.results.first?.id, size: NSSize(width: 850, height: 686), outputName: "Benchmark-Results-CaseDetail-Minimum.png") // Captures minimum-size scrolling and split-view behavior.
        try render(controller: controller, app: app, page: .history, caseResultID: nil, size: NSSize(width: 1_180, height: 760), outputName: "Benchmark-History-Populated.png") // Captures populated history, filters, large model names, status, and actions.
        controller.setComparisonSelection(completed, selected: true) // Selects the first exact run through production controller logic.
        controller.setComparisonSelection(peer, selected: true) // Selects the second exact run through production controller logic.
        XCTAssertTrue(try XCTUnwrap(controller.comparison).comparability.isComparable) // Requires the rendered comparison to represent fair evidence.
        try render(controller: controller, app: app, page: .comparison, caseResultID: nil, size: NSSize(width: 1_180, height: 760), outputName: "Benchmark-Comparison-Populated.png") // Captures the two-model aggregate and category comparison state.
        controller.selectedRunID = errorRun.id // Selects visible terminal error results.
        try render(controller: controller, app: app, page: .overview, caseResultID: errorRun.results.first?.id, size: NSSize(width: 1_180, height: 760), outputName: "Benchmark-Error-State.png") // Captures explicit error classification and bounded diagnostic copy.
        let runningRoot = root.appendingPathComponent("running", isDirectory: true) // Separates cancellable progress persistence from completed fixtures.
        let runningController = BenchmarkController(store: BenchmarkStore(rootURL: runningRoot), engine: BenchmarkEvaluationEngine(elapsedOverride: { _, _ in 50_000 }), client: BenchmarkUILayoutSequenceClient(target: longTarget)) // Creates a real controller that completes one case before waiting cooperatively on the next.
        await runningController.load() // Initializes empty durable state before start.
        runningController.start(suite: suite, configuration: configuration(target: longTarget)) // Starts the real async sequential controller path.
        try await waitUntil { runningController.isRunning && runningController.progress.completed == 1 } // Waits for one durable completion and the following in-flight request.
        XCTAssertEqual(runningController.progress.total, 2) // Requires exact progress denominator before rendering.
        try render(controller: runningController, app: app, page: .overview, caseResultID: nil, size: NSSize(width: 1_180, height: 760), outputName: "Benchmark-Running.png") // Captures model-independent running progress, failures, elapsed, and Stop controls.
        runningController.stop() // Exercises the exact controller action used by both visible Stop buttons.
        try await waitUntil { !runningController.isRunning } // Waits for cooperative cancellation and persistence completion.
        let cancelled = try XCTUnwrap(runningController.runs.first) // Requires the cancelled durable history record.
        XCTAssertEqual(cancelled.state, .cancelled) // Requires explicit cancelled lifecycle rather than failure or skip.
        XCTAssertFalse(cancelled.results.isEmpty) // Requires preservation of the in-flight terminal cancellation evidence.
        runningController.selectedRunID = cancelled.id // Selects the newly persisted cancelled result.
        try render(controller: runningController, app: app, page: .overview, caseResultID: cancelled.results.first?.id, size: NSSize(width: 1_180, height: 760), outputName: "Benchmark-Cancelled-State.png") // Captures cancelled state and retained completed evidence.
    } // Ends native lifecycle and result layout coverage.

    private func configuration(target: ModelGenerationTarget) -> BenchmarkExecutionConfiguration { // Builds one complete reproducible fixture configuration.
        let model = BenchmarkModelConfiguration(target: target, quantization: "4-bit fixture", localPathIdentity: nil, mlxConfiguration: target.backendID == .localMLX ? "MLX fixture" : nil, temperature: 0, maxOutputTokens: 512, contextLength: nil, seed: 61, streaming: false, qualityMode: "Deterministic UI Validation", appVersion: "0.6.1-test", warmupEnabled: false, runsPerCase: 1) // Captures known values and leaves unknown context explicitly nil.
        return BenchmarkExecutionConfiguration(mode: .standard, selectedCategory: nil, selectedCaseIDs: [], model: model, weights: .default, judge: .init(isEnabled: false, target: nil), isDeterministicDemo: true) // Keeps judge and external inference disabled while labeling fixture evidence.
    } // Ends fixture configuration creation.

    private func fixtureSuite() -> BenchmarkSuite { // Creates a small safe suite for native state rendering.
        let first = BenchmarkCase(id: UUID(uuidString: "D0610000-0000-4000-8000-000000000091")!, name: "A deliberately long case name for result table truncation and split-view validation", category: .general, prompt: String(repeating: "Synthetic prompt content for scrolling. ", count: 30), expectedDescription: "ok", grading: .exact(expected: "ok"), timeoutSeconds: 120, maxOutputTokens: 512, tags: ["ui-fixture"], difficulty: .easy) // Exercises long prompt, case name, and selected detail scrolling without user files.
        let second = BenchmarkCase(id: UUID(uuidString: "D0610000-0000-4000-8000-000000000092")!, name: "Second deterministic layout case", category: .structuredOutput, prompt: "Return ok.", expectedDescription: "ok", grading: .exact(expected: "ok"), timeoutSeconds: 120, maxOutputTokens: 512, tags: ["ui-fixture"], difficulty: .medium) // Supplies a second row and category score.
        return BenchmarkSuite(id: UUID(uuidString: "D0610000-0000-4000-8000-000000000090")!, name: "V0.6.1 Native UI Validation Suite with a Deliberately Long Name", description: "Isolated deterministic rendering fixture.", cases: [first, second], version: 1, isBuiltIn: false, createdAt: Date(timeIntervalSince1970: 1_786_406_400), updatedAt: Date(timeIntervalSince1970: 1_786_406_400)) // Returns immutable fixture identity and stable timestamps.
    } // Ends fixture suite creation.

    private var fixtureEnvironment: BenchmarkEnvironment { // Supplies non-sensitive stable environment metadata.
        BenchmarkEnvironment(macOSVersion: "UI Test", architecture: "arm64", hardwareClass: "Test Host", physicalMemoryGB: 128, appVersion: "0.6.1-test") // Avoids username, paths, serial numbers, IP addresses, and credentials.
    } // Ends fixture environment metadata.

    private func makeApp(root: URL) -> AppState { // Creates the production environment object with isolated workspace persistence and no startup tasks.
        let memory = ProjectMemoryStore(rootURL: root.appendingPathComponent("memory", isDirectory: true)) // Isolates Project Memory reads and writes from user state.
        let conversations = ConversationStore(rootURL: root.appendingPathComponent("conversations", isDirectory: true)) // Isolates Chat persistence from user state.
        let workspace = WorkspaceController(memoryStore: memory, conversationStore: conversations) // Composes only test-owned stores.
        return AppState(startsBackgroundTasks: false, workspace: workspace, loadsPersistentState: false, inspectsModelFiles: false) // Prevents user-state reads, model-folder inspection, hardware discovery, model loading, and remote activity.
    } // Ends isolated application state creation.

    private func temporaryDirectory(_ name: String) -> URL { // Resolves one unique test-owned filesystem root.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AutoMLXStudio-V061-UI-\(name)-\(UUID().uuidString)", isDirectory: true) // Prevents collision with user or parallel test data.
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) // Creates only the exact isolated root.
        return root // Returns the isolated directory for explicit ownership and cleanup.
    } // Ends temporary root creation.

    private func evidenceDirectory() throws -> URL { // Resolves fast test-local UI evidence before the validation harness copies it into the repository.
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("AutoMLXStudio-V061-UIEvidence", isDirectory: true) // Avoids blocking XCTest on removable-volume atomic replacement while keeping a stable handoff directory.
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) // Creates only the bounded test-local evidence directory.
        return output // Returns the inspectable temporary evidence directory for explicit post-test collection.
    } // Ends evidence path resolution.

    private func render(controller: BenchmarkController, app: AppState, page: BenchmarkPage, caseResultID: UUID?, size: NSSize, outputName: String) throws { // Renders a production Benchmark destination inside a test-owned native window.
        let view = NSHostingView(rootView: BenchmarkView(controller: controller, initialPage: page, initialCaseResultID: caseResultID).environmentObject(app)) // Hosts the real Benchmark hierarchy and exact isolated state.
        view.frame = NSRect(origin: .zero, size: size) // Applies the requested normal or minimum logical geometry.
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false) // Creates a native offscreen rendering context without desktop capture.
        window.isReleasedWhenClosed = false // Keeps ownership explicit until PNG encoding completes.
        window.contentView = view // Attaches the complete production SwiftUI hierarchy.
        defer { window.close() } // Releases only the exact test-owned offscreen window.
        view.layoutSubtreeIfNeeded() // Resolves forms, tables, split views, scroll views, long names, and semantic controls.
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds)) // Requires an actual native pixel backing rather than a fabricated snapshot.
        view.cacheDisplay(in: view.bounds, to: bitmap) // Captures only the test-owned Benchmark view pixels.
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:])) // Encodes lossless inspectable UI evidence.
        let output = try evidenceDirectory().appendingPathComponent(outputName, isDirectory: false) // Resolves one explicit evidence filename.
        try png.write(to: output, options: .atomic) // Writes only the requested validation artifact atomically.
        let scale = window.backingScaleFactor // Reads actual Retina backing scale for geometry assertions.
        XCTAssertEqual(bitmap.pixelsWide, Int(size.width * scale)) // Requires exact requested logical width without empty fallback.
        XCTAssertEqual(bitmap.pixelsHigh, Int(size.height * scale)) // Requires exact requested logical height without empty fallback.
        XCTAssertGreaterThan(png.count, 10_000) // Requires meaningful rendered content rather than a transparent or empty image.
    } // Ends native Benchmark rendering helper.

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws { // Waits boundedly for one controller state transition.
        for _ in 0..<1_000 { // Bounds the asynchronous wait to approximately two seconds.
            if predicate() { return } // Completes immediately after the expected state is visible.
            try await Task.sleep(nanoseconds: 2_000_000) // Yields cooperatively between observable-state checks.
        } // Ends bounded polling.
        XCTFail("Timed out waiting for Benchmark controller state.") // Records a deterministic failure instead of hanging the suite.
    } // Ends bounded state wait.
} // Ends V0.6.1 native Benchmark UI validation tests.
