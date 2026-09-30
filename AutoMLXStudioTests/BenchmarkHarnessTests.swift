import Foundation // Supplies deterministic JSON, temporary directories, and environment variables.
import XCTest // Supplies the V0.6.1 deterministic verification framework.
@testable import AutoMLXStudio // Exposes internal benchmark architecture to the test target.

private struct BenchmarkTestClient: BenchmarkGenerationClient { // Implements an offline fake backend with no models, downloads, or network access.
    let handler: @Sendable (ModelGenerationRequest) async throws -> ModelGenerationResult // Stores one deterministic scripted response function.
    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult { try await handler(request) } // Returns the scripted normalized result.
} // Ends deterministic fake benchmark client.

private struct BenchmarkTestFailure: LocalizedError, Sendable { // Supplies a controlled fake backend failure.
    var errorDescription: String? { "Scripted benchmark backend failure." } // Returns bounded deterministic error text.
} // Ends fake failure.

private struct BenchmarkTestJudge: BenchmarkJudgeClient { // Supplies a deterministic optional judge without another model.
    func assess(case benchmarkCase: BenchmarkCase, result: ModelGenerationResult, target: ModelGenerationTarget) async throws -> BenchmarkJudgeAssessment { BenchmarkJudgeAssessment(judgeTarget: target, score: 77, rationale: "Simulated qualitative assessment.") } // Returns separated judge evidence.
} // Ends deterministic judge.

final class BenchmarkHarnessTests: XCTestCase { // Verifies graders, runner, persistence, scoring, comparison, export, and the full deterministic demo.
    private let target = ModelGenerationTarget(backendID: .localMLX, location: .local, modelID: "deterministic-v061-fake") // Uses a collision-safe fake target identity.

    func testBuiltInSuiteHasThirtyThreeStableCasesAcrossAllCategories() throws { // Verifies corpus size, uniqueness, validity, and requested taxonomy coverage.
        let suite = BuiltInBenchmarkSuite.standard // Reads the immutable original corpus.
        XCTAssertEqual(suite.cases.count, 33) // Requires the complete shipped case count.
        XCTAssertEqual(Set(suite.cases.map(\.id)).count, 33) // Requires collision-safe stable identities.
        XCTAssertEqual(BuiltInBenchmarkSuite.quickCases.count, 8) // Requires one Quick case per category.
        XCTAssertEqual(Dictionary(grouping: suite.cases, by: \.category).mapValues(\.count), [.general: 5, .reasoning: 5, .coding: 5, .structuredOutput: 5, .toolUse: 4, .engineering: 3, .reviewer: 3, .longContext: 3]) // Requires exact per-category coverage.
        XCTAssertNoThrow(try BenchmarkSuiteValidator.validate(suite)) // Requires all declarative configuration to validate.
        XCTAssertTrue(suite.isBuiltIn) // Requires visible immutability.
    } // Ends corpus verification.

    func testExactAndNormalizedGraders() { // Verifies literal and explicitly normalized matching remain distinct.
        XCTAssertTrue(grade(.exact(expected: "Alpha"), text: "Alpha").passed) // Accepts literal equality.
        XCTAssertFalse(grade(.exact(expected: "Alpha"), text: "alpha").passed) // Rejects implicit case folding.
        let normalized = BenchmarkNormalizationOptions(ignoresCase: true, collapsesWhitespace: true, trimsWhitespace: true) // Declares every permitted normalization.
        XCTAssertTrue(grade(.normalized(expected: "Alpha Beta", options: normalized), text: "  alpha\n beta  ").passed) // Accepts only the explicit transformations.
    } // Ends exact and normalized verification.

    func testContainsAndRegexGraders() { // Verifies phrase all-semantics and bounded pattern matching.
        XCTAssertTrue(grade(.contains(values: ["offline", "deterministic"], requiresAll: true, ignoresCase: true), text: "Deterministic and OFFLINE").passed) // Accepts both case-insensitive phrases.
        XCTAssertFalse(grade(.contains(values: ["offline", "deterministic"], requiresAll: true, ignoresCase: true), text: "offline").passed) // Rejects an omitted required phrase.
        XCTAssertTrue(grade(.regex(pattern: "^V061-[0-9]{3}$", ignoresCase: false), text: "V061-042").passed) // Accepts the declared whole-response pattern.
    } // Ends phrase and regex verification.

    func testNumericGraderRejectsProseAndHonorsTolerance() { // Verifies strict finite-number behavior.
        XCTAssertTrue(grade(.numeric(expected: 3.14, tolerance: 0.01), text: "3.145").passed) // Accepts a value inside absolute tolerance.
        let malformed = grade(.numeric(expected: 3.14, tolerance: 0.01), text: "about 3.14") // Grades prose-wrapped number.
        XCTAssertFalse(malformed.passed) // Rejects non-numeric full response.
        XCTAssertEqual(malformed.errorKind, .malformedResponse) // Classifies the contract failure accurately.
    } // Ends numeric verification.

    func testStrictJSONGraderValidatesNestedTypesAndValues() { // Verifies strict structured-output parsing and dot paths.
        let expectation = BenchmarkJSONExpectation(fields: [.init(path: "metrics", type: .object), .init(path: "metrics.score", type: .number, exactValue: .number(100)), .init(path: "enabled", type: .boolean, exactValue: .boolean(false))]) // Declares a nested typed schema subset.
        XCTAssertTrue(grade(.json(expectation: expectation), text: #"{"metrics":{"score":100},"enabled":false}"#).passed) // Accepts strict typed values.
        let invalid = grade(.json(expectation: expectation), text: #"{"metrics":{"score":"100"},"enabled":false}"#) // Supplies wrong nested type.
        XCTAssertEqual(invalid.errorKind, .invalidJSON) // Reports structured contract failure.
        XCTAssertFalse(grade(.json(expectation: expectation), text: "```json\n{}\n```").passed) // Rejects fences unless explicitly enabled.
    } // Ends JSON verification.

    func testToolGraderAcceptsNativeAndSimulatedCallsWithoutExecution() { // Verifies both backend representations as inert returned data.
        let expected = BenchmarkToolCallExpectation(calls: [.init(name: "lookup_weather", requiredArguments: ["city": .string("Rome")])]) // Declares one harmless expected call.
        let native = ModelToolCall(id: "native-1", name: "lookup_weather", arguments: ["city": .string("Rome")]) // Creates normalized provider-native data.
        XCTAssertTrue(BenchmarkGraderRegistry().grade(specification: .toolCalls(expectation: expected), input: BenchmarkGradingInput(text: nil, toolCalls: [native])).passed) // Accepts exact native data.
        let simulated = #"{"tool_calls":[{"name":"lookup_weather","arguments":{"city":"Rome"}}]}"# // Creates strict local JSON envelope.
        XCTAssertTrue(grade(.toolCalls(expectation: expected), text: simulated).passed) // Accepts exact simulated data without invoking it.
        XCTAssertFalse(grade(.toolCalls(expectation: expected), text: #"{"tool_calls":[{"name":"lookup_weather","arguments":{"city":"Milan"}}]}"#).passed) // Rejects wrong argument.
    } // Ends tool grader verification.

    func testProgrammaticRegistryRejectsUnknownIdentifiers() { // Verifies imports cannot select arbitrary executable code.
        let result = grade(.programmatic(identifier: "shell-script", expected: nil), text: "anything") // Attempts an unregistered identifier.
        XCTAssertEqual(result.errorKind, .gradingError) // Rejects it as configuration failure.
        let invalidCase = BenchmarkCase(name: "Unsafe", category: .engineering, prompt: "Do something", expectedDescription: "None", grading: .programmatic(identifier: "shell-script", expected: nil)) // Creates an unsafe declarative case.
        XCTAssertThrowsError(try BenchmarkSuiteValidator.validate(invalidCase)) // Rejects the suite before execution.
    } // Ends programmatic registry security verification.

    func testSequentialRunnerIsolatesOneFailureAndContinues() async throws { // Verifies no parallel scheduling and case-level failure isolation.
        actor State { var active = 0; var maximum = 0; var calls = 0; func begin() { active += 1; maximum = max(maximum, active); calls += 1 }; func end() { active -= 1 }; func snapshot() -> (Int, Int) { (maximum, calls) } } // Tracks concurrent fake calls safely.
        let state = State() // Creates isolated concurrency tracker.
        let client = BenchmarkTestClient { request in // Scripts success, failure, then success.
            await state.begin() // Records one active request.
            let prompt = request.messages.last?.content ?? "" // Reads deterministic case identity.
            if prompt == "fail" { await state.end(); throw BenchmarkTestFailure() } // Produces one isolated failure after releasing active count.
            let output = self.result(text: "ok") // Produces a passing normalized result.
            await state.end() // Releases active count before the next sequential call.
            return output // Returns the normalized pass.
        } // Ends scripted client.
        let suite = makeSuite(prompts: ["one", "fail", "three"], expected: "ok") // Creates three ordered cases.
        let run = try await BenchmarkEvaluationEngine().run(suite: suite, configuration: configuration(), environment: testEnvironment, client: client) // Executes the real engine.
        let snapshot = await state.snapshot() // Reads concurrency evidence.
        XCTAssertEqual(snapshot.0, 1) // Proves strictly sequential calls.
        XCTAssertEqual(snapshot.1, 3) // Proves execution continued after failure.
        XCTAssertEqual(run.results.map(\.status), [.passed, .error, .passed]) // Preserves every ordered terminal result.
        XCTAssertEqual(run.state, .completed) // Completes overall run despite isolated case failure.
    } // Ends sequential failure-isolation verification.

    func testPerCaseTimeoutIsIsolated() async throws { // Verifies timeout classification and continued scheduling.
        let client = BenchmarkTestClient { request in // Delays only the first case.
            if request.messages.last?.content == "slow" { try await Task.sleep(nanoseconds: 100_000_000) } // Exceeds the 10 ms case deadline cooperatively.
            return self.result(text: "ok") // Returns normal second result.
        } // Ends timeout client.
        var slow = BenchmarkCase(name: "Slow", category: .general, prompt: "slow", expectedDescription: "ok", grading: .exact(expected: "ok"), timeoutSeconds: 0.01) // Creates a short-deadline case.
        let fast = BenchmarkCase(name: "Fast", category: .general, prompt: "fast", expectedDescription: "ok", grading: .exact(expected: "ok"), timeoutSeconds: 1) // Creates a following normal case.
        slow.tags = [] // Keeps explicit test data simple.
        let suite = BenchmarkSuite(name: "Timeout", description: "Timeout isolation", cases: [slow, fast]) // Creates one valid custom suite.
        let run = try await BenchmarkEvaluationEngine().run(suite: suite, configuration: configuration(), environment: testEnvironment, client: client) // Executes timeout race.
        XCTAssertEqual(run.results.first?.errorKind, .timeout) // Classifies the first case accurately.
        XCTAssertEqual(run.results.last?.status, .passed) // Proves the following case still ran.
    } // Ends timeout verification.

    func testCancellationPreservesCompletedResults() async throws { // Verifies Stop semantics during a multi-case run.
        let client = BenchmarkTestClient { _ in try await Task.sleep(nanoseconds: 30_000_000); return self.result(text: "ok") } // Produces cooperative 30 ms responses.
        let suite = makeSuite(prompts: ["one", "two", "three", "four"], expected: "ok") // Creates enough work to cancel after one completion.
        let task = Task { try await BenchmarkEvaluationEngine().run(suite: suite, configuration: configuration(), environment: testEnvironment, client: client) } // Starts the real engine.
        try await Task.sleep(nanoseconds: 45_000_000) // Waits until at least the first result should complete.
        task.cancel() // Requests cooperative stop.
        let run = try await task.value // Receives durable cancelled evidence instead of losing it.
        XCTAssertEqual(run.state, .cancelled) // Records explicit cancellation.
        XCTAssertGreaterThanOrEqual(run.results.filter { $0.status == .passed }.count, 1) // Preserves completed successful results.
        XCTAssertLessThan(run.results.count, 4) // Stops scheduling remaining cases.
    } // Ends cancellation verification.

    func testSummaryUsesAvailableWeightsAndTruthfulMetrics() { // Verifies dimension scoring and optional usage behavior.
        let passed = caseResult(category: .general, status: .passed, score: 100, milliseconds: 100, usage: .init(inputTokens: 10, outputTokens: 5, totalTokens: 15)) // Creates one fully measured pass.
        let failed = caseResult(category: .toolUse, status: .failed, score: 0, milliseconds: 400, usage: nil, errorKind: .toolError) // Creates one missing-usage tool failure.
        let summary = BenchmarkSummaryCalculator.summarize(results: [passed, failed], weights: .default) // Calculates available dimensions.
        XCTAssertEqual(summary.qualityScore, 100) // Preserves quality evidence.
        XCTAssertEqual(summary.toolUseScore, 0) // Preserves tool failure.
        XCTAssertNotNil(summary.reliabilityScore) // Calculates response-contract reliability.
        XCTAssertNotNil(summary.performance.meanLatencyMilliseconds) // Calculates measured latency.
        XCTAssertEqual(summary.totalTokens, 15) // Sums only reported usage.
        XCTAssertNil(summary.performance.p95LatencyMilliseconds) // Omits p95 below twenty samples.
        XCTAssertEqual(summary.iterations, 2) // Counts actual evaluation iterations.
    } // Ends score and metric verification.

    func testOptionalJudgeStaysSeparatedFromDeterministicScore() async throws { // Verifies judge evidence never overwrites deterministic grading.
        let engine = BenchmarkEvaluationEngine(judgeClient: BenchmarkTestJudge()) // Injects one simulated judge.
        let suite = makeSuite(prompts: ["one"], expected: "ok") // Creates one exact deterministic task.
        var config = configuration() // Creates deterministic base configuration.
        config.judge = .init(isEnabled: true, target: target) // Enables judge explicitly.
        let run = try await engine.run(suite: suite, configuration: config, environment: testEnvironment, client: BenchmarkTestClient { _ in self.result(text: "ok") }) // Executes both isolated paths.
        XCTAssertEqual(run.results.first?.score, 100) // Preserves exact deterministic grade.
        XCTAssertEqual(run.results.first?.judge?.score, 77) // Stores separate simulated qualitative evidence.
        XCTAssertEqual(run.summary?.qualityScore, 100) // Keeps aggregate independent from judge score.
    } // Ends optional judge separation verification.

    func testVersionedPersistenceSkipsOnlyCorruptRecord() async throws { // Verifies schema persistence and corruption isolation.
        let root = temporaryDirectory("store") // Creates an isolated app-owned test root.
        let store = BenchmarkStore(rootURL: root) // Creates the real versioned actor store.
        let run = try await fullDemoRun() // Produces a valid complete run.
        try await store.save(run: run) // Persists canonical version-one JSON.
        let corruptDirectory = root.appendingPathComponent("runs", isDirectory: true) // Resolves only isolated test records.
        try Data("not-json".utf8).write(to: corruptDirectory.appendingPathComponent("corrupt.json"), options: [.atomic]) // Adds one intentionally corrupt independent record.
        let loaded = await store.loadRuns() // Loads all records independently.
        XCTAssertEqual(loaded.values.count, 1) // Preserves the valid run.
        XCTAssertEqual(loaded.issues.count, 1) // Reports only the corrupt record.
        XCTAssertEqual(BenchmarkStore.schemaVersion, 1) // Verifies explicit schema version.
    } // Ends persistence isolation verification.

    func testCustomSuiteImportPreviewAndExportRoundTrip() async throws { // Verifies safe declarative suite portability.
        let store = BenchmarkStore(rootURL: temporaryDirectory("suite")) // Creates isolated storage.
        let suite = makeSuite(prompts: ["question"], expected: "answer") // Creates one editable safe suite.
        let data = try await store.suiteExportData(suite) // Produces versioned deterministic JSON.
        let preview = try await store.importPreview(data: data) // Validates without persistence.
        XCTAssertEqual(preview.id, suite.id) // Preserves stable suite identity.
        XCTAssertEqual(preview.name, suite.name) // Preserves visible suite identity.
        XCTAssertEqual(preview.cases, suite.cases) // Preserves all executable declarative content exactly.
        XCTAssertEqual(preview.createdAt.timeIntervalSince1970, suite.createdAt.timeIntervalSince1970, accuracy: 1) // Allows ISO-8601's subsecond normalization only.
        try await store.save(suite: preview) // Persists only after explicit caller action.
        let loaded = await store.loadCustomSuites() // Restores persisted custom suites outside the assertion autoclosure.
        XCTAssertEqual(loaded.values.first?.id, suite.id) // Restores the exact saved suite record.
        XCTAssertEqual(loaded.values.first?.cases, suite.cases) // Restores declarative case content exactly.
        let oversized = Data(repeating: 0, count: BenchmarkStore.maximumImportBytes + 1) // Creates input beyond fixed bound.
        do { _ = try await store.importPreview(data: oversized); XCTFail("Oversized import should fail.") } catch let error as BenchmarkValidationError { XCTAssertEqual(error, .importTooLarge) } // Verifies the safety limit.
    } // Ends custom suite round-trip verification.

    func testComparisonAndBestModelByRole() async throws { // Verifies fairness checks and evidence-only role recommendation.
        let first = try await fullDemoRun() // Produces a complete all-category run.
        var second = first // Copies equivalent non-model conditions.
        second = BenchmarkRun(id: UUID(), suiteID: second.suiteID, suiteName: second.suiteName, suiteVersion: second.suiteVersion, caseIDs: second.caseIDs, mode: second.mode, selectedCategory: second.selectedCategory, modelConfiguration: modelConfiguration(target: ModelGenerationTarget(backendID: .localMLX, location: .local, modelID: "second-model")), environment: second.environment, scoreWeights: second.scoreWeights, startedAt: second.startedAt, completedAt: second.completedAt, state: second.state, results: second.results, summary: second.summary, isBaseline: false, issue: nil, isDeterministicDemo: true) // Changes only evaluated model identity.
        XCTAssertTrue(BenchmarkAnalysis.compare(first, second).comparability.isComparable) // Allows model identity to differ for fair comparison.
        let leaders = BenchmarkAnalysis.bestModelsByRole(from: [first, second]) // Derives category leaders only.
        XCTAssertEqual(leaders.count, BenchmarkRole.allCases.count) // Produces every supported role from full evidence.
        XCTAssertTrue(leaders.allSatisfy { $0.score == 100 }) // Preserves deterministic perfect category scores.
    } // Ends comparison and recommendation verification.

    func testDeterministicDemoCompletesAndExportsJSONAndMarkdown() async throws { // Runs every built-in case end to end with the offline fake backend.
        let run = try await fullDemoRun() // Executes suite, grading, metrics, and aggregation.
        XCTAssertEqual(run.state, .completed) // Requires terminal completion.
        XCTAssertEqual(run.results.count, 33) // Requires every built-in case.
        XCTAssertTrue(run.results.allSatisfy { $0.status == .passed }) // Requires deterministic expected responses.
        XCTAssertEqual(try XCTUnwrap(run.summary).overallScore, 100, accuracy: 0.0001) // Requires perfect weighted output.
        XCTAssertTrue(run.isDeterministicDemo) // Clearly distinguishes fake evidence from real model evidence.
        let requestedPath = ProcessInfo.processInfo.environment["V061_DEMO_OUTPUT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } // Reads an explicit validation artifact directory when supplied.
        let output = requestedPath ?? temporaryDirectory("demo-export-first") // Uses an explicit evidence path when requested or a disposable local destination for routine regression runs.
        let artifacts = try BenchmarkReportExporter.write(run: run, to: output) // Writes both requested result formats.
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.json.path)) // Verifies JSON artifact.
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.markdown.path)) // Verifies Markdown artifact.
        XCTAssertTrue(try String(contentsOf: artifacts.markdown, encoding: .utf8).contains("Tool calls are graded but never executed")) // Verifies security disclosure.
        let secondOutput = temporaryDirectory("demo-export-second") // Creates an independent destination for byte-level reproducibility.
        let secondArtifacts = try BenchmarkReportExporter.write(run: try await fullDemoRun(), to: secondOutput) // Repeats the entire deterministic demo and export.
        XCTAssertEqual(try Data(contentsOf: artifacts.json), try Data(contentsOf: secondArtifacts.json)) // Proves JSON output is byte-for-byte deterministic.
        XCTAssertEqual(try Data(contentsOf: artifacts.markdown), try Data(contentsOf: secondArtifacts.markdown)) // Proves Markdown output is byte-for-byte deterministic.
    } // Ends deterministic full-demo verification.

    private func grade(_ specification: BenchmarkGradingSpecification, text: String?) -> BenchmarkGrade { BenchmarkGraderRegistry().grade(specification: specification, input: BenchmarkGradingInput(text: text, toolCalls: [])) } // Grades one text response through the production registry.

    private func configuration(mode: BenchmarkRunMode = .standard) -> BenchmarkExecutionConfiguration { BenchmarkExecutionConfiguration(mode: mode, selectedCategory: nil, selectedCaseIDs: [], model: modelConfiguration(target: target), weights: .default, judge: .init(isEnabled: false, target: nil), isDeterministicDemo: false) } // Creates a valid deterministic execution configuration.

    private func modelConfiguration(target: ModelGenerationTarget) -> BenchmarkModelConfiguration { BenchmarkModelConfiguration(target: target, quantization: nil, localPathIdentity: nil, mlxConfiguration: "Fake", temperature: nil, maxOutputTokens: 512, contextLength: nil, seed: 61, streaming: false, qualityMode: "Deterministic Test", appVersion: "0.6.1-test", warmupEnabled: false, runsPerCase: 1) } // Creates truthful fake metadata.

    private var testEnvironment: BenchmarkEnvironment { BenchmarkEnvironment(macOSVersion: "Test", architecture: "arm64", hardwareClass: "Test Host", physicalMemoryGB: 1, appVersion: "0.6.1-test") } // Creates non-sensitive deterministic environment metadata.

    private func makeSuite(prompts: [String], expected: String) -> BenchmarkSuite { BenchmarkSuite(name: "Test Suite", description: "Deterministic isolated cases", cases: prompts.enumerated().map { index, prompt in BenchmarkCase(name: "Case \(index + 1)", category: .general, prompt: prompt, expectedDescription: expected, grading: .exact(expected: expected), timeoutSeconds: 1) }) } // Creates one safe custom exact suite.

    private func result(text: String?, toolCalls: [ModelToolCall] = []) -> ModelGenerationResult { ModelGenerationResult(text: text, toolCalls: toolCalls, usage: .init(inputTokens: 8, outputTokens: 2, totalTokens: 10), finishReason: toolCalls.isEmpty ? .stop : .toolCalls, modelID: target.modelID, backendID: target.backendID, durationMilliseconds: 10) } // Creates one normalized deterministic backend result.

    private func caseResult(category: BenchmarkCategory, status: BenchmarkCaseStatus, score: Double, milliseconds: Int, usage: ModelGenerationUsage?, errorKind: BenchmarkErrorKind? = nil) -> BenchmarkCaseResult { let date = Date(timeIntervalSince1970: 1_000); return BenchmarkCaseResult(id: UUID(), caseID: UUID(), caseName: "Case", category: category, repetition: 1, input: "input", output: "output", status: status, score: score, timing: .init(startedAt: date, firstTokenAt: nil, completedAt: date, totalDurationMilliseconds: milliseconds, timeToFirstTokenMilliseconds: nil, generationDurationMilliseconds: milliseconds), usage: usage, grader: "Test", gradingDetails: "Test result", errorKind: errorKind, errorMessage: nil, retryCount: 0, toolCallCount: category == .toolUse ? 1 : 0, iterations: 1, judge: nil, metadata: [:]) } // Creates one aggregate input result.

    private func fullDemoRun() async throws -> BenchmarkRun { // Executes the complete production-shaped corpus with generated expected responses.
        let suite = BuiltInBenchmarkSuite.standard // Captures immutable built-in case definitions.
        let answers = Dictionary(uniqueKeysWithValues: try suite.cases.map { item in (item.prompt, try expectedResult(for: item)) }) // Builds deterministic outputs from declarative expected values.
        let client = BenchmarkTestClient { request in guard let prompt = request.messages.last?.content, let answer = answers[prompt] else { throw BenchmarkTestFailure() }; return answer } // Returns no external or trained-model output.
        var config = configuration() // Creates standard full-suite configuration.
        config.isDeterministicDemo = true // Labels fake evidence explicitly.
        let fixedDate = Date(timeIntervalSince1970: 1_786_406_400) // Uses a stable visible timestamp.
        let runID = UUID(uuidString: "E0610000-0000-4000-8000-000000000001")! // Uses a stable explicit demo run identity.
        let engine = BenchmarkEvaluationEngine(dateProvider: { fixedDate }, runIDProvider: { runID }, resultIDProvider: { caseID, _ in UUID(uuidString: "E\(caseID.uuidString.dropFirst())")! }, elapsedOverride: { _, _ in 10 }) // Derives one stable collision-free demo result identity from every immutable case identity.
        return try await engine.run(suite: suite, configuration: config, environment: testEnvironment, client: client) // Runs real selection, timeout, grading, scoring, and result assembly.
    } // Ends deterministic full demo.

    private func expectedResult(for item: BenchmarkCase) throws -> ModelGenerationResult { // Derives one exact fake result from declarative grading configuration.
        switch item.grading { // Handles every strategy used by the built-in corpus.
        case .exact(let expected): return result(text: expected) // Returns literal expected text.
        case .normalized(let expected, _): return result(text: expected) // Returns normalized expected text directly.
        case .contains(let values, _, _): return result(text: values.joined(separator: " and ")) // Includes every declared phrase.
        case .regex: return result(text: "V061-042") // Returns the one built-in extraction pattern answer.
        case .numeric(let expected, _): return result(text: expected.rounded() == expected ? String(Int(expected)) : String(expected)) // Returns finite numeric text.
        case .json(let expectation): return result(text: try jsonAnswer(expectation)) // Builds strict schema-valid JSON.
        case .toolCalls(let expectation): // Returns native calls to exercise normalized tool grading.
            let calls = expectation.calls.enumerated().map { ModelToolCall(id: "demo-\($0.offset + 1)", name: $0.element.name, arguments: $0.element.requiredArguments) } // Converts declared harmless calls without execution.
            return result(text: nil, toolCalls: calls) // Returns tool-only normalized output.
        case .programmatic(let identifier, let expected): // Returns registered programmatic-pass content.
            if identifier == "ordered-plan" { return result(text: "Inspect, then Edit, then Test, then Verify.") } // Satisfies ordered phases.
            if identifier == "single-line" { return result(text: "macOS") } // Satisfies concise line shape.
            if identifier == "expected-string", case .string(let value) = expected { return result(text: value) } // Returns synthetic recall token.
            throw BenchmarkTestFailure() // Rejects unexpected programmatic configuration.
        } // Ends expected-result construction.
    } // Ends fake answer generation.

    private func jsonAnswer(_ expectation: BenchmarkJSONExpectation) throws -> String { // Builds strict JSON matching the declarative schema subset.
        if let rootField = expectation.fields.first(where: { $0.path.isEmpty }), let exact = rootField.exactValue { return try encode(exact) } // Returns exact root value when declared.
        var root: JSONValue = defaultJSONValue(expectation.rootType) // Starts with the requested root type.
        for field in expectation.fields where field.required { root = setting(field.exactValue ?? defaultJSONValue(field.type), at: field.path.split(separator: ".").map(String.init), in: root) } // Inserts every required typed value.
        return try encode(root) // Returns canonical strict JSON.
    } // Ends schema-valid JSON generation.

    private func setting(_ value: JSONValue, at components: [String], in root: JSONValue) -> JSONValue { // Inserts a typed value into object-only dot paths.
        guard let first = components.first else { return value } // Replaces root at the end of traversal.
        var object = root.objectValue ?? [:] // Creates an object when the declared path requires one.
        object[first] = setting(value, at: Array(components.dropFirst()), in: object[first] ?? .object([:])) // Recursively inserts the remaining path.
        return .object(object) // Returns the updated immutable JSON tree.
    } // Ends JSON path insertion.

    private func defaultJSONValue(_ type: BenchmarkJSONType) -> JSONValue { switch type { case .string: return .string(""); case .number: return .number(0); case .boolean: return .boolean(false); case .object: return .object([:]); case .array: return .array([]); case .null: return .null } } // Creates a strictly typed default value.

    private func encode(_ value: JSONValue) throws -> String { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return String(decoding: try encoder.encode(value), as: UTF8.self) } // Encodes provider-neutral JSON deterministically.

    private func temporaryDirectory(_ name: String) -> URL { // Creates a collision-safe isolated directory and registers cleanup.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AutoMLXStudio-V061-\(name)-\(UUID().uuidString)", isDirectory: true) // Resolves only a unique temporary target.
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) // Creates isolated test storage.
        addTeardownBlock { try? FileManager.default.removeItem(at: url) } // Removes only the exact generated temporary directory.
        return url // Returns isolated directory.
    } // Ends temporary-directory creation.
} // Ends V0.6.1 benchmark harness tests.
