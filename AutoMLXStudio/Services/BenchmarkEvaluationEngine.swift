import Darwin // Supplies processor architecture discovery without device identifiers.
import Foundation // Supplies dates, task groups, ProcessInfo, and bounded error descriptions.

protocol BenchmarkGenerationClient: Sendable { // Isolates the provider-neutral dispatcher so deterministic tests never need a real model.
    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult // Executes one exact target request.
} // Ends benchmark generation client boundary.

protocol BenchmarkJudgeClient: Sendable { // Isolates optional qualitative assessment from every deterministic grader.
    func assess(case benchmarkCase: BenchmarkCase, result: ModelGenerationResult, target: ModelGenerationTarget) async throws -> BenchmarkJudgeAssessment // Produces one visible assessment that cannot modify deterministic scores.
} // Ends optional judge boundary.

struct DispatcherBenchmarkGenerationClient: BenchmarkGenerationClient { // Adapts the existing shared backend dispatcher to exact no-fallback benchmark execution.
    let dispatcher: ModelBackendDispatcher // Stores the backend-neutral production dispatcher.

    func generate(_ request: ModelGenerationRequest) async throws -> ModelGenerationResult { // Executes only the exact backend-qualified target captured by the run.
        let capabilities = ModelCapabilityProfile(values: [.text: .supported, .toolCalling: request.tools.isEmpty ? .unknown : .supported]) // Describes only capabilities the benchmark request actually relies on.
        let model = RoutableGenerationModel(id: "benchmark-target", logicalModelID: request.target.modelID, target: request.target, capabilities: capabilities, availability: .unknown) // Creates one run-scoped exact catalog record.
        let routingRequest = ModelGenerationRoutingRequest(agentID: "benchmark-harness", preferredModelID: model.id, orderedFallbackModelIDs: [], requiredCapabilities: request.tools.isEmpty ? [.text] : [.text, .toolCalling], fallbackPolicy: .disabled, allowsUnknownCapabilities: true, allowsUnknownAvailability: true) // Disables fallback so model identity never changes mid-run.
        let route = try ModelRouter().makeGenerationRoute(for: routingRequest, models: [model]) // Uses the production typed router for collision-safe target validation.
        return try await dispatcher.generate(request: request, using: route).result // Returns only the normalized provider-neutral result to the evaluator.
    } // Ends dispatcher-backed generation.
} // Ends production benchmark generation adapter.

enum BenchmarkExecutionError: LocalizedError, Equatable, Sendable { // Defines fatal harness-level failures separately from isolated case failures.
    case noCasesSelected // Indicates the selected mode produced no cases.
    case missingCategory // Indicates Category mode omitted its category.
    case timedOut // Indicates one case-specific deadline elapsed.

    var errorDescription: String? { // Produces concise safe diagnostics.
        switch self { // Maps each harness error to corrective copy.
        case .noCasesSelected: return "No benchmark cases were selected." // Explains empty selection.
        case .missingCategory: return "Choose a category before starting a category benchmark." // Explains missing mode input.
        case .timedOut: return "The benchmark case exceeded its configured timeout." // Explains isolated deadline failure.
        } // Ends harness error mapping.
    } // Ends localized benchmark execution diagnostics.
} // Ends benchmark execution errors.

struct BenchmarkEvaluationEngine: Sendable { // Executes validated cases sequentially and preserves every completed result.
    let graderRegistry: BenchmarkGraderRegistry // Owns deterministic strategy resolution.
    let judgeClient: (any BenchmarkJudgeClient)? // Owns an optional separately injected qualitative judge.
    let dateProvider: @Sendable () -> Date // Supplies deterministic dates to tests and demos.
    let runIDProvider: @Sendable () -> UUID // Supplies random production or stable demo run identity.
    let resultIDProvider: @Sendable (UUID, Int) -> UUID // Supplies random production or stable demo repetition identity.
    let elapsedOverride: (@Sendable (UUID, Int) -> Int)? // Supplies fixed test/demo elapsed values while remaining nil for truthful production timing.

    init(graderRegistry: BenchmarkGraderRegistry = BenchmarkGraderRegistry(), judgeClient: (any BenchmarkJudgeClient)? = nil, dateProvider: @escaping @Sendable () -> Date = { Date() }, runIDProvider: @escaping @Sendable () -> UUID = { UUID() }, resultIDProvider: @escaping @Sendable (UUID, Int) -> UUID = { _, _ in UUID() }, elapsedOverride: (@Sendable (UUID, Int) -> Int)? = nil) { // Creates the production or deterministic evaluator.
        self.graderRegistry = graderRegistry // Stores deterministic graders.
        self.judgeClient = judgeClient // Stores optional judge independently.
        self.dateProvider = dateProvider // Stores wall-clock provider.
        self.runIDProvider = runIDProvider // Stores run identity provider.
        self.resultIDProvider = resultIDProvider // Stores result identity provider.
        self.elapsedOverride = elapsedOverride // Stores optional test-only elapsed override.
    } // Ends evaluator construction.

    func selectedCases(in suite: BenchmarkSuite, configuration: BenchmarkExecutionConfiguration) throws -> [BenchmarkCase] { // Resolves the visible run mode deterministically.
        let selected: [BenchmarkCase] // Holds the ordered immutable case snapshot.
        switch configuration.mode { // Applies exactly one selection policy.
        case .quick: selected = suite.cases.filter { $0.tags.contains("quick") }.prefix(10).map { $0 } // Selects five to ten explicitly tagged cases.
        case .standard: selected = suite.cases // Selects the complete suite in authored order.
        case .category: // Selects every case in one required category.
            guard let category = configuration.selectedCategory else { throw BenchmarkExecutionError.missingCategory } // Requires the visible category choice.
            selected = suite.cases.filter { $0.category == category } // Preserves authored order within the category.
        case .custom: selected = configuration.selectedCaseIDs.isEmpty ? suite.cases : suite.cases.filter { configuration.selectedCaseIDs.contains($0.id) } // Supports a full custom suite or explicit subset.
        } // Ends mode selection.
        guard !selected.isEmpty else { throw BenchmarkExecutionError.noCasesSelected } // Prevents an apparently running empty benchmark.
        return selected // Returns the stable case snapshot.
    } // Ends case selection.

    func run( // Executes one complete benchmark and reports durable checkpoints.
        suite: BenchmarkSuite, // Supplies the immutable suite snapshot.
        configuration: BenchmarkExecutionConfiguration, // Supplies exact model, selection, repetition, and scoring choices.
        environment: BenchmarkEnvironment = .current(), // Captures non-sensitive host metadata by default.
        client: any BenchmarkGenerationClient, // Supplies production dispatcher or deterministic fake execution.
        progress: (@Sendable (BenchmarkProgress, BenchmarkRun) async -> Void)? = nil // Receives low-frequency per-repetition checkpoints for UI and persistence.
    ) async throws -> BenchmarkRun { // Returns completed, cancelled, or configuration-valid durable evidence.
        try BenchmarkSuiteValidator.validate(suite) // Rejects malformed suites before any model request.
        try BenchmarkSuiteValidator.validate(weights: configuration.weights, runsPerCase: configuration.model.runsPerCase) // Rejects invalid score and repetition settings.
        let cases = try selectedCases(in: suite, configuration: configuration) // Resolves an ordered immutable case set.
        let startedAt = dateProvider() // Captures visible run start once.
        let runStart = ContinuousClock.now // Starts monotonic total timing.
        var run = BenchmarkRun(id: runIDProvider(), suiteID: suite.id, suiteName: suite.name, suiteVersion: suite.version, caseIDs: cases.map(\.id), mode: configuration.mode, selectedCategory: configuration.selectedCategory, modelConfiguration: configuration.model, environment: environment, scoreWeights: configuration.weights, startedAt: startedAt, completedAt: nil, state: .running, results: [], summary: nil, isBaseline: false, issue: nil, isDeterministicDemo: configuration.isDeterministicDemo) // Creates the durable running snapshot.
        let total = cases.count * configuration.model.runsPerCase // Calculates exact progress denominator.
        if configuration.model.warmupEnabled, let first = cases.first, !Task.isCancelled { // Runs one deliberately unscored warmup when requested.
            _ = try? await execute(case: first, repetition: 0, configuration: configuration, client: client) // Ignores warmup success or failure while preserving no invented score.
        } // Ends optional warmup.
        executionLoop: for item in cases { // Schedules cases strictly sequentially.
            for repetition in 1...configuration.model.runsPerCase { // Schedules requested repetitions strictly sequentially.
                if Task.isCancelled { break executionLoop } // Stops scheduling while preserving completed results.
                let result = await isolatedResult(for: item, repetition: repetition, configuration: configuration, client: client) // Converts every per-case failure into one durable result.
                run.results.append(result) // Preserves terminal evidence immediately.
                run.summary = BenchmarkSummaryCalculator.summarize(results: run.results, weights: configuration.weights) // Recomputes a transparent partial summary.
                let currentProgress = BenchmarkProgress(completed: run.results.count, total: total, currentCaseName: item.name, failures: run.results.filter { $0.status != .passed }.count, elapsedMilliseconds: Self.milliseconds(since: runStart)) // Builds one efficient per-repetition progress event.
                if let progress { await progress(currentProgress, run) } // Lets the controller persist and publish without token-level churn.
            } // Ends repetitions for one case.
        } // Ends sequential case scheduling.
        run.completedAt = dateProvider() // Captures visible terminal time.
        run.state = Task.isCancelled ? .cancelled : .completed // Distinguishes cooperative stop from complete scheduling.
        run.summary = BenchmarkSummaryCalculator.summarize(results: run.results, weights: configuration.weights) // Finalizes aggregates from completed evidence only.
        let finalProgress = BenchmarkProgress(completed: run.results.count, total: total, currentCaseName: nil, failures: run.results.filter { $0.status != .passed }.count, elapsedMilliseconds: Self.milliseconds(since: runStart)) // Builds final terminal progress.
        if let progress { await progress(finalProgress, run) } // Publishes the final durable snapshot.
        return run // Returns completed or cancelled evidence without discarding results.
    } // Ends benchmark run.

    private func isolatedResult(for item: BenchmarkCase, repetition: Int, configuration: BenchmarkExecutionConfiguration, client: any BenchmarkGenerationClient) async -> BenchmarkCaseResult { // Converts one repetition into a result even when generation fails.
        let startedAt = dateProvider() // Captures the real visible attempt start even when generation throws before producing a result.
        let monotonicStart = ContinuousClock.now // Measures truthful elapsed failure and timeout duration without relying on wall-clock adjustments.
        do { // Attempts one bounded request and deterministic grade.
            return try await execute(case: item, repetition: repetition, configuration: configuration, client: client) // Returns a normal pass or valid wrong answer.
        } catch is CancellationError { // Handles cooperative cancellation from engine or backend.
            return failureResult(case: item, repetition: repetition, kind: .cancelled, status: .cancelled, message: "Case execution was cancelled.", startedAt: startedAt, durationMilliseconds: Self.milliseconds(since: monotonicStart)) // Preserves an in-flight cancellation result with measured elapsed time.
        } catch let error as BenchmarkExecutionError where error == .timedOut { // Handles the per-case deadline independently.
            return failureResult(case: item, repetition: repetition, kind: .timeout, status: .error, message: error.localizedDescription, startedAt: startedAt, durationMilliseconds: Self.milliseconds(since: monotonicStart)) // Records timeout duration and allows the next case.
        } catch let error as ModelBackendRegistryError { // Classifies unavailable exact backend resolution.
            return failureResult(case: item, repetition: repetition, kind: .backendUnavailable, status: .error, message: Self.safeMessage(error), startedAt: startedAt, durationMilliseconds: Self.milliseconds(since: monotonicStart)) // Keeps target/configuration failure bounded with real elapsed time.
        } catch let error as ModelBackendDispatchError { // Classifies normalized dispatcher terminal failures.
            let kind: BenchmarkErrorKind = error.trace.terminalState == .cancelled ? .cancelled : .backendUnavailable // Preserves cancellation separately from target failure.
            let status: BenchmarkCaseStatus = kind == .cancelled ? .cancelled : .error // Maps classified error to case status.
            return failureResult(case: item, repetition: repetition, kind: kind, status: status, message: Self.safeMessage(error), startedAt: startedAt, durationMilliseconds: Self.milliseconds(since: monotonicStart)) // Stores no prompt, credential, or raw provider body while retaining measured duration.
        } catch { // Isolates all remaining protocol and backend errors.
            return failureResult(case: item, repetition: repetition, kind: .protocolError, status: .error, message: Self.safeMessage(error), startedAt: startedAt, durationMilliseconds: Self.milliseconds(since: monotonicStart)) // Continues the overall run after a bounded measured failure.
        } // Ends per-case failure isolation.
    } // Ends isolated result creation.

    private func execute(case item: BenchmarkCase, repetition: Int, configuration: BenchmarkExecutionConfiguration, client: any BenchmarkGenerationClient) async throws -> BenchmarkCaseResult { // Generates and grades one case repetition.
        let startedAt = dateProvider() // Captures visible case start.
        let monotonicStart = ContinuousClock.now // Starts truthful elapsed timing.
        let request = request(for: item, configuration: configuration) // Builds one exact provider-neutral request.
        let generated = try await withTimeout(seconds: item.timeoutSeconds) { try await client.generate(request) } // Enforces the case-specific deadline.
        try Task.checkCancellation() // Honors cancellation even if a client returns late.
        let completedAt = dateProvider() // Captures visible case completion.
        let elapsed = elapsedOverride?(item.id, repetition) ?? Self.milliseconds(since: monotonicStart) // Measures production latency or uses an explicit deterministic test/demo value.
        let grade = graderRegistry.grade(specification: item.grading, input: BenchmarkGradingInput(text: generated.text, toolCalls: generated.toolCalls)) // Applies the declared deterministic strategy.
        let judge = await optionalJudge(case: item, generated: generated, configuration: configuration) // Runs optional qualitative judging separately and never changes grade.
        let timing = BenchmarkTiming(startedAt: startedAt, firstTokenAt: nil, completedAt: completedAt, totalDurationMilliseconds: elapsed, timeToFirstTokenMilliseconds: nil, generationDurationMilliseconds: max(0, generated.durationMilliseconds)) // Records TTFT as unavailable because dispatcher generation is not streamed.
        let status: BenchmarkCaseStatus = grade.passed ? .passed : .failed // Maps deterministic grade to terminal correctness.
        return BenchmarkCaseResult(id: resultIDProvider(item.id, repetition), caseID: item.id, caseName: item.name, category: item.category, repetition: repetition, input: Self.bounded(item.prompt, limit: 65_536), output: generated.text.map { Self.bounded($0, limit: 65_536) }, status: status, score: min(100, max(0, grade.score)), timing: timing, usage: generated.usage, grader: item.grading.displayName, gradingDetails: grade.details, errorKind: grade.errorKind, errorMessage: nil, retryCount: 0, toolCallCount: generated.toolCalls.isEmpty ? Self.simulatedToolCallCount(generated.text) : generated.toolCalls.count, iterations: 1, judge: judge, metadata: ["backend": generated.backendID.rawValue, "model": Self.bounded(generated.modelID, limit: 256), "tool-mode": generated.toolCalls.isEmpty ? "simulated-or-none" : "native"]) // Persists bounded truthful evidence.
    } // Ends one case execution.

    private func request(for item: BenchmarkCase, configuration: BenchmarkExecutionConfiguration) -> ModelGenerationRequest { // Builds a safe request without adaptive routing or tool execution.
        let isToolCase = item.category == .toolUse // Detects tool-protocol evaluation.
        let nativeTools = isToolCase && configuration.model.target.backendID != .localMLX ? toolSchemas(for: item) : [] // Advertises native harmless schemas only to non-local adapters that can encode them.
        let localToolInstruction = isToolCase && configuration.model.target.backendID == .localMLX ? " Return strict JSON only using {\"tool_calls\":[{\"name\":\"tool_name\",\"arguments\":{...}}]}. This is simulated data; do not execute anything." : "" // Gives local MLX a non-executable JSON representation because that adapter rejects native tools.
        let contextWarning = item.category == .longContext ? " The input is synthetic and may approach the configured context limit; do not infer a larger supported context." : "" // Makes long-context uncertainty explicit.
        let system = (item.systemPrompt ?? "Follow the benchmark prompt exactly. Return only the requested answer. Do not reveal hidden reasoning.") + localToolInstruction + contextWarning // Combines only benchmark-safe instructions.
        return ModelGenerationRequest(target: configuration.model.target, systemInstructions: system, messages: [ModelGenerationMessage(role: .user, content: item.prompt)], tools: nativeTools, temperature: configuration.model.temperature, maxOutputTokens: min(configuration.model.maxOutputTokens, item.maxOutputTokens), stopSequences: [], attachments: []) // Produces one text-only provider-neutral request.
    } // Ends request construction.

    private func toolSchemas(for item: BenchmarkCase) -> [ModelToolSchema] { // Derives only the exact harmless schemas declared by the case.
        guard case .toolCalls(let expectation) = item.grading else { return [] } // Rejects non-tool graders.
        var names = Set<String>() // Prevents duplicate schema declarations for repeated expected calls.
        return expectation.calls.compactMap { call in // Builds one generic object-argument schema per unique tool.
            guard names.insert(call.name).inserted else { return nil } // Emits each tool exactly once.
            let properties = Dictionary(uniqueKeysWithValues: call.requiredArguments.map { key, value in (key, Self.schema(for: value)) }) // Derives simple JSON types from expected values.
            let parameters: JSONValue = .object(["type": .string("object"), "properties": .object(properties), "required": .array(call.requiredArguments.keys.sorted().map { .string($0) }), "additionalProperties": .boolean(call.allowsAdditionalArguments)]) // Creates a strict provider-neutral JSON Schema subset.
            return ModelToolSchema(name: call.name, description: "Return this harmless simulated benchmark request; AutoMLXStudio will not execute it.", parameters: parameters) // Advertises selection-only semantics.
        } // Ends schema derivation.
    } // Ends tool schema construction.

    private func optionalJudge(case item: BenchmarkCase, generated: ModelGenerationResult, configuration: BenchmarkExecutionConfiguration) async -> BenchmarkJudgeAssessment? { // Runs only explicitly enabled and injected qualitative judging.
        guard configuration.judge.isEnabled, let target = configuration.judge.target, let judgeClient else { return nil } // Keeps judge disabled by default and absent from deterministic-only runs.
        return try? await judgeClient.assess(case: item, result: generated, target: target) // Isolates judge failure from deterministic evidence.
    } // Ends optional judge execution.

    private func failureResult(case item: BenchmarkCase, repetition: Int, kind: BenchmarkErrorKind, status: BenchmarkCaseStatus, message: String, startedAt: Date, durationMilliseconds: Int) -> BenchmarkCaseResult { // Creates one bounded terminal failure record from the actual attempt interval.
        let completedAt = dateProvider() // Captures the real visible failure completion timestamp.
        let timing = BenchmarkTiming(startedAt: startedAt, firstTokenAt: nil, completedAt: completedAt, totalDurationMilliseconds: max(0, durationMilliseconds), timeToFirstTokenMilliseconds: nil, generationDurationMilliseconds: 0) // Retains measured total latency while leaving unavailable generation and TTFT metrics explicit.
        return BenchmarkCaseResult(id: resultIDProvider(item.id, repetition), caseID: item.id, caseName: item.name, category: item.category, repetition: repetition, input: Self.bounded(item.prompt, limit: 65_536), output: nil, status: status, score: 0, timing: timing, usage: nil, grader: item.grading.displayName, gradingDetails: "Generation did not produce a grade.", errorKind: kind, errorMessage: Self.bounded(message, limit: 512), retryCount: 0, toolCallCount: 0, iterations: 1, judge: nil, metadata: [:]) // Preserves completed failure evidence without sensitive raw data.
    } // Ends failure result creation.

    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T { // Races one operation against its case-specific deadline.
        try await withThrowingTaskGroup(of: T.self) { group in // Creates structured child tasks that are cancelled together.
            group.addTask { try await operation() } // Starts the exact generation request.
            group.addTask { // Starts the deadline task.
                let nanoseconds = UInt64(seconds * 1_000_000_000) // Converts the already validated positive timeout safely.
                try await Task.sleep(nanoseconds: nanoseconds) // Waits cooperatively without blocking a thread.
                throw BenchmarkExecutionError.timedOut // Reports an isolated timeout when generation did not finish first.
            } // Ends deadline task.
            guard let first = try await group.next() else { throw BenchmarkExecutionError.timedOut } // Requires one race result.
            group.cancelAll() // Cancels the losing deadline or generation task.
            return first // Returns the successful first result.
        } // Ends structured timeout race.
    } // Ends timeout enforcement.

    private static func schema(for value: JSONValue) -> JSONValue { // Converts an expected argument into a minimal strict JSON Schema type.
        let type: String // Holds the exact JSON Schema type name.
        switch value { // Maps every provider-neutral JSON kind.
        case .string: type = "string" // Maps text.
        case .number: type = "number" // Maps finite numbers.
        case .boolean: type = "boolean" // Maps Booleans.
        case .object: type = "object" // Maps objects.
        case .array: type = "array" // Maps arrays.
        case .null: type = "null" // Maps null.
        } // Ends JSON type mapping.
        return .object(["type": .string(type)]) // Returns a bounded type-only schema.
    } // Ends schema type conversion.

    private static func simulatedToolCallCount(_ text: String?) -> Int { // Counts only valid strict simulated envelopes for truthful metrics.
        guard let text, let data = text.data(using: .utf8), let root = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let object) = root, case .array(let calls)? = object["tool_calls"] else { return 0 } // Requires the exact JSON envelope.
        return calls.count // Returns declared simulated call count without execution.
    } // Ends simulated tool-call counting.

    private static func safeMessage(_ error: Error) -> String { // Produces bounded diagnostics without raw provider bodies.
        if let classified = error as? any ModelBackendFailureClassifying { return bounded(classified.modelBackendSafeSummary, limit: 512) } // Uses only an adapter-declared safe summary.
        if error is CancellationError { return "Case execution was cancelled." } // Uses stable cancellation copy.
        return bounded(error.localizedDescription, limit: 512) // Bounds typed localized errors from harness and dispatcher layers.
    } // Ends safe error rendering.

    private static func bounded(_ value: String, limit: Int) -> String { String(value.prefix(limit)) } // Applies fixed persistence and UI bounds.
    private static func milliseconds(since start: ContinuousClock.Instant) -> Int { let components = start.duration(to: ContinuousClock.now).components; return max(0, Int(components.seconds * 1_000) + Int(components.attoseconds / 1_000_000_000_000_000)) } // Converts monotonic elapsed duration to non-negative milliseconds.
} // Ends benchmark evaluation engine.

enum BenchmarkSummaryCalculator { // Aggregates correctness, reliability, engineering, tool, and measured performance transparently.
    static func summarize(results: [BenchmarkCaseResult], weights: BenchmarkScoreWeights) -> ModelEvaluationSummary { // Calculates a snapshot from completed repetitions only.
        let categoryGroups = Dictionary(grouping: results, by: \.category) // Groups all repetitions by stable category.
        let categoryScores = categoryGroups.mapValues { average($0.map(\.score)) ?? 0 } // Calculates deterministic category means.
        let qualityCategories: Set<BenchmarkCategory> = [.general, .reasoning, .coding, .structuredOutput, .reviewer, .longContext] // Defines quality dimensions separately from specialized tool and engineering dimensions.
        let qualityResults = results.filter { qualityCategories.contains($0.category) } // Selects eligible general correctness evidence.
        let quality = average(qualityResults.map(\.score)) // Calculates quality only when evidence exists.
        let validResponseCount = results.filter { $0.errorKind == nil || $0.errorKind == .wrongAnswer }.count // Counts valid responses independently from correctness.
        let responseReliability = results.isEmpty ? nil : Double(validResponseCount) / Double(results.count) * 100 // Calculates successful response-contract rate.
        let repetitionConsistency = consistency(results) // Calculates within-case score consistency when repeated runs exist.
        let reliability = responseReliability.map { base in repetitionConsistency.map { base * 0.75 + $0 * 0.25 } ?? base } // Adds consistency only when repeated evidence exists.
        let toolUse = average(categoryGroups[.toolUse]?.map(\.score) ?? []) // Calculates tool score only when tool cases ran.
        let engineering = average(categoryGroups[.engineering]?.map(\.score) ?? []) // Calculates engineering score only when engineering cases ran.
        let latencies = results.filter { $0.status != .cancelled }.map { $0.timing.totalDurationMilliseconds } // Uses terminal measured results only.
        let performance = performanceStatistics(results: results, latencies: latencies) // Preserves raw metrics separately.
        let performanceScore = performance.meanLatencyMilliseconds.map(performanceGrade) // Converts latency to a modest transparent bounded contribution.
        let dimensions: [(String, Double, Double?)] = [("Quality", weights.quality, quality), ("Reliability", weights.reliability, reliability), ("Tool Use", weights.toolUse, toolUse), ("Engineering", weights.engineering, engineering), ("Performance", weights.performance, performanceScore)] // Pairs configured weights with available evidence.
        let availableWeight = dimensions.compactMap { $0.2 == nil ? nil : $0.1 }.reduce(0, +) // Normalizes only across dimensions actually evaluated.
        let contributionPairs: [(String, Double)] = dimensions.compactMap { dimension in let (name, weight, score) = dimension; guard let score, availableWeight > 0 else { return nil }; return (name, score * weight / availableWeight) } // Calculates only evidence-backed normalized contributions.
        let contributions = Dictionary(uniqueKeysWithValues: contributionPairs) // Exposes each normalized weighted contribution.
        let overall = contributions.values.reduce(0, +) // Sums transparent available contributions.
        let totals = results.compactMap(totalTokens) // Collects only truthful provider usage values.
        let totalTokensValue = totals.isEmpty ? nil : totals.reduce(0, +) // Avoids reporting zero when providers omitted usage.
        let correct = results.filter { $0.status == .passed }.count // Counts full deterministic passes.
        let scorePoints = results.map(\.score).reduce(0, +) // Sums all 0-to-100 score points.
        let tokensPerCorrect = totalTokensValue.flatMap { correct > 0 ? Double($0) / Double(correct) : nil } // Calculates token efficiency only with a correct answer.
        let tokensPerPoint = totalTokensValue.flatMap { scorePoints > 0 ? Double($0) / scorePoints : nil } // Calculates token efficiency only with positive score.
        return ModelEvaluationSummary(overallScore: overall, qualityScore: quality, reliabilityScore: reliability, toolUseScore: toolUse, engineeringScore: engineering, performanceScore: performanceScore, categoryScores: categoryScores, weightedContributions: contributions, performance: performance, totalTokens: totalTokensValue, tokensPerCorrectAnswer: tokensPerCorrect, tokensPerScorePoint: tokensPerPoint, failures: results.filter { $0.status == .failed || $0.status == .error }.count, malformedOutputs: results.filter { $0.errorKind == .malformedResponse || $0.errorKind == .invalidJSON }.count, toolCalls: results.map(\.toolCallCount).reduce(0, +), iterations: results.map(\.iterations).reduce(0, +)) // Returns the complete transparent summary.
    } // Ends summary calculation.

    private static func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) } // Calculates arithmetic mean only with evidence.

    private static func consistency(_ results: [BenchmarkCaseResult]) -> Double? { // Measures score stability only for cases with multiple repetitions.
        let repeated = Dictionary(grouping: results, by: \.caseID).values.filter { $0.count > 1 } // Selects actually repeated cases.
        guard !repeated.isEmpty else { return nil } // Omits consistency for one-shot runs.
        let values = repeated.map { group -> Double in // Converts each case score range into 0-to-100 stability.
            let scores = group.map(\.score) // Collects repetition scores.
            guard let minimum = scores.min(), let maximum = scores.max() else { return 0 } // Protects malformed empty groups.
            return max(0, 100 - (maximum - minimum)) // Awards full stability for identical outcomes.
        } // Ends per-case stability conversion.
        return average(values) // Returns mean stability across repeated cases.
    } // Ends repetition consistency calculation.

    private static func performanceStatistics(results: [BenchmarkCaseResult], latencies: [Int]) -> BenchmarkPerformanceStatistics { // Aggregates measured latency and optional throughput.
        let sorted = latencies.sorted() // Sorts samples for median and percentile calculations.
        let mean = sorted.isEmpty ? nil : Double(sorted.reduce(0, +)) / Double(sorted.count) // Calculates mean latency.
        let median: Double? = sorted.isEmpty ? nil : sorted.count.isMultiple(of: 2) ? Double(sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 : Double(sorted[sorted.count / 2]) // Calculates conventional median.
        let p95: Double? = sorted.count >= 20 ? Double(sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]) : nil // Reports p95 only with at least twenty samples.
        let rates = results.compactMap { result -> Double? in guard let tokens = result.usage?.outputTokens, tokens >= 0, result.timing.generationDurationMilliseconds > 0 else { return nil }; return Double(tokens) / (Double(result.timing.generationDurationMilliseconds) / 1_000) } // Uses only provider-reported output tokens and positive generation duration.
        return BenchmarkPerformanceStatistics(meanLatencyMilliseconds: mean, medianLatencyMilliseconds: median, minimumLatencyMilliseconds: sorted.first, maximumLatencyMilliseconds: sorted.last, p95LatencyMilliseconds: p95, meanOutputTokensPerSecond: average(rates)) // Returns every truthful aggregate.
    } // Ends performance aggregation.

    private static func performanceGrade(_ milliseconds: Double) -> Double { // Maps absolute latency to a transparent low-weight 0-to-100 grade.
        guard milliseconds > 250 else { return 100 } // Awards full performance score at or below 250 ms.
        let logarithmicPenalty = log10(milliseconds / 250) * 50 // Applies a gradual platform-neutral logarithmic penalty.
        return min(100, max(0, 100 - logarithmicPenalty)) // Bounds the grade and reaches zero at 25 seconds.
    } // Ends performance score mapping.

    private static func totalTokens(_ result: BenchmarkCaseResult) -> Int? { // Resolves reported total usage without inventing partial values.
        if let total = result.usage?.totalTokens { return total } // Prefers provider-reported total.
        if let input = result.usage?.inputTokens, let output = result.usage?.outputTokens { return input + output } // Sums only when both parts are known.
        return nil // Preserves unavailable usage honestly.
    } // Ends usage resolution.
} // Ends benchmark summary calculator.

extension BenchmarkEnvironment { // Builds privacy-bounded host metadata for production runs.
    static func current(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> BenchmarkEnvironment { // Reads only OS, architecture, hardware class, memory, and app version.
        var system = utsname() // Allocates the POSIX system-information structure.
        uname(&system) // Populates architecture fields locally.
        let machine = withUnsafePointer(to: &system.machine) { pointer in pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } } // Converts the architecture tuple without a hardware serial number.
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development" // Reads app semantic version when packaged.
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String // Reads optional build number.
        let appVersion = build.map { "\(version) (\($0))" } ?? version // Combines non-sensitive application identity.
        let memory = Double(processInfo.physicalMemory) / 1_073_741_824 // Converts total memory to gibibytes.
        return BenchmarkEnvironment(macOSVersion: processInfo.operatingSystemVersionString, architecture: machine, hardwareClass: machine.contains("arm64") ? "Apple Silicon" : "Mac", physicalMemoryGB: memory, appVersion: appVersion) // Returns no username, hostname, serial, endpoint, or path.
    } // Ends current environment capture.
} // Ends benchmark environment production helper.
