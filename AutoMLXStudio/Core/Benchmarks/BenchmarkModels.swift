import Foundation // Supplies identifiers, dates, Codable persistence, and platform environment metadata.

enum BenchmarkCategory: String, Codable, CaseIterable, Identifiable, Sendable { // Defines the stable benchmark taxonomy used by suites, scores, filters, and recommendations.
    case general // Covers instruction following, extraction, classification, and deterministic transformations.
    case reasoning // Covers short original problems with independently verifiable answers.
    case coding // Covers small Swift, Python, and C++ comprehension or correction tasks.
    case structuredOutput = "structured-output" // Covers strict JSON and schema adherence.
    case toolUse = "tool-use" // Covers simulated or native tool selection and arguments without executing side effects.
    case engineering // Covers inspect, edit-intent, test-intent, and verification planning.
    case reviewer // Covers defect identification, severity, and corrective guidance.
    case longContext = "long-context" // Covers recall and instruction retention in locally generated synthetic context.

    var id: String { rawValue } // Exposes stable SwiftUI identity without another persistence key.

    var displayName: String { // Produces concise user-facing category names.
        switch self { // Maps every stable raw value to presentation copy.
        case .general: return "General" // Names broad instruction-following work.
        case .reasoning: return "Reasoning" // Names deterministic reasoning work.
        case .coding: return "Coding" // Names source-code tasks.
        case .structuredOutput: return "Structured Output" // Names strict machine-readable responses.
        case .toolUse: return "Tool Use" // Names simulated/native function selection.
        case .engineering: return "Engineering" // Names multi-step software change planning.
        case .reviewer: return "Reviewer" // Names defect-review work.
        case .longContext: return "Long Context" // Names synthetic context recall.
        } // Ends category presentation mapping.
    } // Ends category display name.

    var symbol: String { // Supplies native semantic symbols for compact UI labels.
        switch self { // Maps each category to one SF Symbol.
        case .general: return "text.bubble" // Represents general language work.
        case .reasoning: return "function" // Represents short computed reasoning.
        case .coding: return "chevron.left.forwardslash.chevron.right" // Represents source code.
        case .structuredOutput: return "curlybraces" // Represents structured JSON.
        case .toolUse: return "wrench.and.screwdriver" // Represents bounded tools.
        case .engineering: return "hammer" // Represents engineering workflow.
        case .reviewer: return "checkmark.seal" // Represents review and severity assessment.
        case .longContext: return "text.justify.left" // Represents larger synthetic input.
        } // Ends category symbol mapping.
    } // Ends category symbol.
} // Ends benchmark category taxonomy.

enum BenchmarkDifficulty: String, Codable, CaseIterable, Identifiable, Sendable { // Records transparent case difficulty without changing its score.
    case easy // Identifies one-step tasks.
    case medium // Identifies small multi-constraint tasks.
    case hard // Identifies the bounded most demanding built-in tasks.

    var id: String { rawValue } // Supplies stable picker identity.

    var displayName: String { rawValue.capitalized } // Produces native title-case UI text.
} // Ends difficulty values.

enum BenchmarkRunMode: String, Codable, CaseIterable, Identifiable, Sendable { // Defines the requested case-selection policy for one run.
    case quick // Selects a small tagged cross-category subset.
    case standard // Selects every case in the chosen suite.
    case category // Selects every case in one explicit category.
    case custom // Selects every case from a user-created suite.

    var id: String { rawValue } // Supplies stable picker identity.

    var displayName: String { // Produces concise run-mode labels.
        switch self { // Maps stable values to UI copy.
        case .quick: return "Quick" // Names the small subset.
        case .standard: return "Standard" // Names the complete built-in suite.
        case .category: return "Category" // Names one-category execution.
        case .custom: return "Custom Suite" // Names user-suite execution.
        } // Ends mode presentation mapping.
    } // Ends run-mode display name.
} // Ends benchmark run modes.

enum BenchmarkRunState: String, Codable, Equatable, Sendable { // Describes the durable lifecycle of a benchmark run.
    case queued // Indicates configuration is captured but execution has not begun.
    case running // Indicates sequential execution owns a current case.
    case completed // Indicates every selected repetition reached a terminal result.
    case cancelled // Indicates user cancellation stopped new case scheduling while preserving completed results.
    case failed // Indicates fatal suite or configuration failure prevented normal execution.
} // Ends durable run states.

enum BenchmarkCaseStatus: String, Codable, Equatable, Sendable { // Describes one case repetition outcome independently from the overall run.
    case passed // Indicates deterministic grading met the case threshold.
    case failed // Indicates a valid response did not meet deterministic expectations.
    case error // Indicates backend, protocol, timeout, or grading failure.
    case cancelled // Indicates user cancellation interrupted this repetition.
} // Ends case outcome states.

enum BenchmarkErrorKind: String, Codable, CaseIterable, Sendable { // Classifies failures for transparent reliability analysis.
    case timeout // Indicates the case-specific deadline expired.
    case cancelled // Indicates user cancellation.
    case backendUnavailable = "backend-unavailable" // Indicates the selected backend or model could not serve the request.
    case malformedResponse = "malformed-response" // Indicates no usable response contract was returned.
    case invalidJSON = "invalid-json" // Indicates structured output could not be decoded as strict JSON.
    case wrongAnswer = "wrong-answer" // Indicates a valid response failed deterministic correctness.
    case toolError = "tool-error" // Indicates incorrect, malformed, or unnecessary simulated/native tool calls.
    case protocolError = "protocol-error" // Indicates provider-neutral generation contract failure.
    case gradingError = "grading-error" // Indicates the configured grader itself could not evaluate safely.
} // Ends benchmark error taxonomy.

enum BenchmarkJSONType: String, Codable, CaseIterable, Sendable { // Defines declarative JSON types accepted by imported benchmark suites.
    case string // Requires a JSON string.
    case number // Requires a finite JSON number.
    case boolean // Requires a JSON Boolean.
    case object // Requires a JSON object.
    case array // Requires a JSON array.
    case null // Requires explicit JSON null.
} // Ends JSON type constraints.

struct BenchmarkNormalizationOptions: Codable, Equatable, Sendable { // Configures safe normalized exact-match behavior explicitly.
    var ignoresCase: Bool // Controls Unicode-aware lowercasing.
    var collapsesWhitespace: Bool // Controls repeated whitespace collapse.
    var trimsWhitespace: Bool // Controls leading, trailing, and newline trimming.

    init(ignoresCase: Bool = false, collapsesWhitespace: Bool = true, trimsWhitespace: Bool = true) { // Creates conservative normalization defaults.
        self.ignoresCase = ignoresCase // Stores case policy.
        self.collapsesWhitespace = collapsesWhitespace // Stores internal whitespace policy.
        self.trimsWhitespace = trimsWhitespace // Stores boundary whitespace policy.
    } // Ends normalization configuration.
} // Ends normalized-match options.

struct BenchmarkJSONFieldExpectation: Codable, Equatable, Sendable { // Declares one required or optional JSON path constraint.
    let path: String // Stores a dot-separated object path without executable expressions.
    let type: BenchmarkJSONType // Stores the required JSON value kind.
    let required: Bool // Distinguishes missing optional fields from failures.
    let exactValue: JSONValue? // Optionally requires one exact strictly typed value.

    init(path: String, type: BenchmarkJSONType, required: Bool = true, exactValue: JSONValue? = nil) { // Creates one declarative schema field.
        self.path = path // Stores the validated path.
        self.type = type // Stores the expected type.
        self.required = required // Stores presence policy.
        self.exactValue = exactValue // Stores optional exact-value policy.
    } // Ends JSON field expectation creation.
} // Ends one JSON schema constraint.

struct BenchmarkJSONExpectation: Codable, Equatable, Sendable { // Groups strict JSON response constraints without executing code.
    let rootType: BenchmarkJSONType // Requires the top-level response kind.
    let fields: [BenchmarkJSONFieldExpectation] // Requires bounded declarative nested fields.
    let allowsMarkdownFences: Bool // Makes fence tolerance explicit instead of silently stripping formatting.

    init(rootType: BenchmarkJSONType = .object, fields: [BenchmarkJSONFieldExpectation], allowsMarkdownFences: Bool = false) { // Creates one strict JSON grading contract.
        self.rootType = rootType // Stores root shape.
        self.fields = fields // Stores field constraints.
        self.allowsMarkdownFences = allowsMarkdownFences // Stores response-format policy.
    } // Ends JSON grading contract creation.
} // Ends JSON expectations.

struct BenchmarkExpectedToolCall: Codable, Equatable, Sendable { // Declares one expected simulated or native tool request.
    let name: String // Stores the exact harmless tool name.
    let requiredArguments: [String: JSONValue] // Stores exact required argument values.
    let allowsAdditionalArguments: Bool // Controls whether extra non-required arguments are accepted.

    init(name: String, requiredArguments: [String: JSONValue], allowsAdditionalArguments: Bool = false) { // Creates one tool-call expectation.
        self.name = name // Stores expected tool identity.
        self.requiredArguments = requiredArguments // Stores required arguments.
        self.allowsAdditionalArguments = allowsAdditionalArguments // Stores extra-argument policy.
    } // Ends expected tool creation.
} // Ends one tool-call expectation.

struct BenchmarkToolCallExpectation: Codable, Equatable, Sendable { // Describes an exact ordered harmless tool-call sequence.
    let calls: [BenchmarkExpectedToolCall] // Stores expected tool requests in required order.
    let allowsAdditionalCalls: Bool // Controls whether unnecessary calls are accepted.

    init(calls: [BenchmarkExpectedToolCall], allowsAdditionalCalls: Bool = false) { // Creates one ordered sequence contract.
        self.calls = calls // Stores ordered expectations.
        self.allowsAdditionalCalls = allowsAdditionalCalls // Stores unnecessary-call policy.
    } // Ends tool sequence creation.
} // Ends tool-call grading expectations.

enum BenchmarkGradingSpecification: Codable, Equatable, Sendable { // Stores only declarative, import-safe grading configuration.
    case exact(expected: String) // Requires byte-equivalent visible text after edge trimming.
    case normalized(expected: String, options: BenchmarkNormalizationOptions) // Requires safely normalized text equality.
    case contains(values: [String], requiresAll: Bool, ignoresCase: Bool) // Requires one or all bounded phrases.
    case regex(pattern: String, ignoresCase: Bool) // Requires a validated regular-expression match.
    case numeric(expected: Double, tolerance: Double) // Requires a finite numeric response within tolerance.
    case json(expectation: BenchmarkJSONExpectation) // Requires strict JSON shape and optional exact values.
    case toolCalls(expectation: BenchmarkToolCallExpectation) // Requires exact simulated/native tool identity, arguments, and order.
    case programmatic(identifier: String, expected: JSONValue?) // Selects one registered safe in-process grader by stable identifier.

    var displayName: String { // Produces user-facing grader identity without exposing implementation internals.
        switch self { // Maps each declarative strategy to a concise label.
        case .exact: return "Exact Match" // Names byte-equivalent text grading.
        case .normalized: return "Normalized Exact Match" // Names normalized equality.
        case .contains: return "Contains" // Names phrase inclusion.
        case .regex: return "Regular Expression" // Names pattern grading.
        case .numeric: return "Numeric" // Names tolerance grading.
        case .json: return "JSON Validation" // Names schema grading.
        case .toolCalls: return "Tool Call Validation" // Names ordered tool grading.
        case .programmatic: return "Programmatic" // Names registered custom grading.
        } // Ends grader label mapping.
    } // Ends grader display name.
} // Ends persistence-safe grading specifications.

struct BenchmarkCase: Identifiable, Codable, Equatable, Sendable { // Defines one bounded original benchmark task independently from execution state.
    let id: UUID // Supplies stable case identity across suite versions and comparisons.
    var name: String // Stores concise visible case name.
    var category: BenchmarkCategory // Stores scoring and filtering category.
    var prompt: String // Stores the complete user prompt or locally generated synthetic context.
    var systemPrompt: String? // Optionally overrides the benchmark-safe default system instruction.
    var expectedDescription: String // Stores a human-readable expected result for case inspection.
    var grading: BenchmarkGradingSpecification // Stores the deterministic grader configuration.
    var timeoutSeconds: TimeInterval // Stores the per-repetition deadline.
    var maxOutputTokens: Int // Stores the provider-neutral output bound.
    var tags: [String] // Stores bounded selection and discovery labels such as quick.
    var difficulty: BenchmarkDifficulty // Stores transparent case complexity.
    var isDeterministic: Bool // Distinguishes primary deterministic cases from optional qualitative judging.

    init(id: UUID = UUID(), name: String, category: BenchmarkCategory, prompt: String, systemPrompt: String? = nil, expectedDescription: String, grading: BenchmarkGradingSpecification, timeoutSeconds: TimeInterval = 60, maxOutputTokens: Int = 256, tags: [String] = [], difficulty: BenchmarkDifficulty = .easy, isDeterministic: Bool = true) { // Creates one source-compatible complete case.
        self.id = id // Stores stable identity.
        self.name = name // Stores case name.
        self.category = category // Stores category.
        self.prompt = prompt // Stores user input.
        self.systemPrompt = systemPrompt // Stores optional system instruction.
        self.expectedDescription = expectedDescription // Stores inspection-friendly expectation.
        self.grading = grading // Stores deterministic grader.
        self.timeoutSeconds = timeoutSeconds // Stores timeout.
        self.maxOutputTokens = maxOutputTokens // Stores output limit.
        self.tags = tags // Stores selection tags.
        self.difficulty = difficulty // Stores difficulty.
        self.isDeterministic = isDeterministic // Stores determinism policy.
    } // Ends benchmark case creation.
} // Ends benchmark case definition.

struct BenchmarkSuite: Identifiable, Codable, Equatable, Sendable { // Groups versioned benchmark cases and immutable built-in metadata.
    let id: UUID // Supplies stable suite identity across exports and runs.
    var name: String // Stores visible suite name.
    var description: String // Stores concise purpose and scope.
    var category: BenchmarkCategory? // Optionally restricts a custom suite to one category.
    var cases: [BenchmarkCase] // Stores ordered case definitions.
    var version: Int // Stores explicit suite revision for comparability.
    let isBuiltIn: Bool // Prevents mutation or persistence replacement of shipped suites.
    let createdAt: Date // Records suite creation time.
    var updatedAt: Date // Records last custom-suite edit time.

    init(id: UUID = UUID(), name: String, description: String, category: BenchmarkCategory? = nil, cases: [BenchmarkCase], version: Int = 1, isBuiltIn: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) { // Creates one complete suite snapshot.
        self.id = id // Stores stable identity.
        self.name = name // Stores name.
        self.description = description // Stores purpose.
        self.category = category // Stores optional category restriction.
        self.cases = cases // Stores ordered cases.
        self.version = version // Stores revision.
        self.isBuiltIn = isBuiltIn // Stores immutability policy.
        self.createdAt = createdAt // Stores creation time.
        self.updatedAt = updatedAt // Stores edit time.
    } // Ends suite creation.

    func duplicated(name: String? = nil, now: Date = Date()) -> BenchmarkSuite { // Creates an editable copy without mutating a built-in suite.
        let copiedCases = cases.map { item in BenchmarkCase(name: item.name, category: item.category, prompt: item.prompt, systemPrompt: item.systemPrompt, expectedDescription: item.expectedDescription, grading: item.grading, timeoutSeconds: item.timeoutSeconds, maxOutputTokens: item.maxOutputTokens, tags: item.tags, difficulty: item.difficulty, isDeterministic: item.isDeterministic) } // Gives every copied case a collision-safe new identity while preserving declarative content.
        return BenchmarkSuite(name: name ?? "\(self.name) Copy", description: description, category: category, cases: copiedCases, version: 1, isBuiltIn: false, createdAt: now, updatedAt: now) // Returns a new editable suite identity.
    } // Ends suite duplication.
} // Ends benchmark suite definition.

struct BenchmarkScoreWeights: Codable, Equatable, Sendable { // Stores configurable transparent score weights.
    var quality: Double // Weights deterministic correctness and task completion.
    var reliability: Double // Weights valid terminal responses and consistency.
    var toolUse: Double // Weights tool protocol correctness.
    var engineering: Double // Weights engineering workflow discipline.
    var performance: Double // Weights measured latency and throughput modestly.

    static let `default` = BenchmarkScoreWeights(quality: 0.35, reliability: 0.25, toolUse: 0.20, engineering: 0.15, performance: 0.05) // Implements the requested initial 35/25/20/15/5 weighting.

    var total: Double { quality + reliability + toolUse + engineering + performance } // Exposes validation-friendly total weight.
} // Ends score weights.

struct BenchmarkModelConfiguration: Codable, Equatable, Sendable { // Captures exact model identity and relevant generation configuration for reproducibility.
    let target: ModelGenerationTarget // Stores backend, server location, and exact model identifier.
    let quantization: String? // Stores known quantization only when catalog metadata provides it.
    let localPathIdentity: String? // Stores a privacy-safe final path component rather than an absolute user path.
    let mlxConfiguration: String? // Stores a concise non-secret local runtime descriptor when known.
    let temperature: Double? // Stores optional explicitly requested sampling temperature.
    let maxOutputTokens: Int // Stores the configured upper bound before case-specific minimum selection.
    let contextLength: Int? // Stores known model context length or nil when unavailable.
    let seed: Int? // Stores an optional seed only when the backend can honor it.
    let streaming: Bool // Records whether the execution contract measured streamed output.
    let qualityMode: String // Stores a concise user-visible run policy label.
    let appVersion: String // Stores application version/build identity.
    let warmupEnabled: Bool // Records whether a non-scored warmup was requested.
    let runsPerCase: Int // Stores repeated-run count for consistency analysis.
} // Ends benchmark model configuration.

struct BenchmarkJudgeConfiguration: Codable, Equatable, Sendable { // Keeps optional qualitative judging visibly separate from deterministic scoring.
    var isEnabled: Bool // Requires explicit opt-in and defaults to false in the controller.
    var target: ModelGenerationTarget? // Stores the separate judge model when enabled.
} // Ends optional judge configuration.

struct BenchmarkExecutionConfiguration: Codable, Equatable, Sendable { // Captures every user choice required to reproduce case selection and execution.
    var mode: BenchmarkRunMode // Stores Quick, Standard, Category, or Custom selection.
    var selectedCategory: BenchmarkCategory? // Stores the required category for Category mode.
    var selectedCaseIDs: Set<UUID> // Stores explicit Custom selection or an empty set for mode-derived selection.
    var model: BenchmarkModelConfiguration // Stores exact backend-qualified model settings.
    var weights: BenchmarkScoreWeights // Stores the scoring weights used by this run.
    var judge: BenchmarkJudgeConfiguration // Stores disabled-by-default qualitative judging independently.
    var isDeterministicDemo = false // Marks only explicit fake-backend validation runs and defaults to false for production UI execution.
} // Ends complete benchmark execution configuration.

struct BenchmarkEnvironment: Codable, Equatable, Sendable { // Stores useful non-sensitive host metadata for result interpretation.
    let macOSVersion: String // Stores operating-system version only.
    let architecture: String // Stores processor architecture without a device identifier.
    let hardwareClass: String // Stores chip family or generic hardware class.
    let physicalMemoryGB: Double // Stores total physical memory in gigabytes.
    let appVersion: String // Stores application version/build identity.
} // Ends privacy-bounded benchmark environment.

struct BenchmarkTiming: Codable, Equatable, Sendable { // Stores wall-clock anchors and monotonic-derived durations without inventing streaming data.
    let startedAt: Date // Records user-readable repetition start.
    let firstTokenAt: Date? // Records first streamed token only when genuinely observed.
    let completedAt: Date // Records user-readable terminal time.
    let totalDurationMilliseconds: Int // Stores monotonic end-to-end duration.
    let timeToFirstTokenMilliseconds: Int? // Stores monotonic TTFT only when available.
    let generationDurationMilliseconds: Int // Stores backend-reported generation duration.
} // Ends case timing metrics.

struct BenchmarkJudgeAssessment: Codable, Equatable, Sendable { // Stores optional qualitative judge evidence separately from deterministic scoring.
    let judgeTarget: ModelGenerationTarget? // Stores judge identity when enabled and known.
    let score: Double // Stores judge-only 0 to 100 assessment.
    let rationale: String // Stores concise visible rationale without chain-of-thought.
} // Ends optional judge assessment.

struct BenchmarkCaseResult: Identifiable, Codable, Equatable, Sendable { // Stores one bounded terminal case repetition.
    let id: UUID // Supplies stable history and case-detail identity.
    let caseID: UUID // Links to the immutable suite snapshot case.
    let caseName: String // Preserves visible case identity if a custom suite later changes.
    let category: BenchmarkCategory // Supports filtering and category aggregation without reopening a suite file.
    let repetition: Int // Records one-based repeated-run position.
    let input: String // Stores a bounded prompt snapshot for inspection.
    let output: String? // Stores bounded user-facing model output only.
    let status: BenchmarkCaseStatus // Stores pass, fail, error, or cancellation.
    let score: Double // Stores deterministic 0 to 100 score.
    let timing: BenchmarkTiming // Stores truthful timing values.
    let usage: ModelGenerationUsage? // Stores provider token usage only when reported.
    let grader: String // Stores deterministic grader identity.
    let gradingDetails: String // Stores concise transparent grading explanation.
    let errorKind: BenchmarkErrorKind? // Stores classified terminal failure when applicable.
    let errorMessage: String? // Stores bounded safe failure text.
    let retryCount: Int // Stores actual retries, initially zero because standard execution does not retry.
    let toolCallCount: Int // Stores returned simulated/native tool call count.
    let iterations: Int // Stores actual evaluation iterations, currently one per repetition.
    let judge: BenchmarkJudgeAssessment? // Stores optional judge evidence without changing deterministic score.
    let metadata: [String: String] // Stores bounded non-sensitive protocol details such as native versus simulated tools.
} // Ends case result persistence model.

struct BenchmarkPerformanceStatistics: Codable, Equatable, Sendable { // Aggregates measured performance without claiming unavailable values.
    let meanLatencyMilliseconds: Double? // Stores arithmetic mean when samples exist.
    let medianLatencyMilliseconds: Double? // Stores median when samples exist.
    let minimumLatencyMilliseconds: Int? // Stores fastest observed total latency.
    let maximumLatencyMilliseconds: Int? // Stores slowest observed total latency.
    let p95LatencyMilliseconds: Double? // Stores p95 only when at least twenty samples make it meaningful.
    let meanOutputTokensPerSecond: Double? // Stores throughput only from results with reported output tokens and positive duration.
} // Ends aggregate performance statistics.

struct ModelEvaluationSummary: Codable, Equatable, Sendable { // Stores transparent aggregate dimensions and weighted contributions.
    let overallScore: Double // Stores normalized weighted overall score from available dimensions.
    let qualityScore: Double? // Stores deterministic task-quality score when eligible cases exist.
    let reliabilityScore: Double? // Stores valid-response and consistency score.
    let toolUseScore: Double? // Stores tool protocol score only when tool cases exist.
    let engineeringScore: Double? // Stores engineering score only when engineering cases exist.
    let performanceScore: Double? // Stores relative per-run performance score only when latency exists.
    let categoryScores: [BenchmarkCategory: Double] // Stores per-category deterministic averages.
    let weightedContributions: [String: Double] // Stores each included normalized contribution for inspection.
    let performance: BenchmarkPerformanceStatistics // Stores raw aggregate latency and throughput.
    let totalTokens: Int? // Stores summed reported tokens only when at least one provider reports usage.
    let tokensPerCorrectAnswer: Double? // Stores efficiency only when reported tokens and correct answers exist.
    let tokensPerScorePoint: Double? // Stores efficiency only when reported tokens and positive aggregate score exist.
    let failures: Int // Stores failed or error result count.
    let malformedOutputs: Int // Stores malformed-response or invalid-JSON count.
    let toolCalls: Int // Stores total simulated/native tool calls returned.
    let iterations: Int // Stores total executed repetitions.

    init(overallScore: Double, qualityScore: Double?, reliabilityScore: Double?, toolUseScore: Double?, engineeringScore: Double?, performanceScore: Double?, categoryScores: [BenchmarkCategory: Double], weightedContributions: [String: Double], performance: BenchmarkPerformanceStatistics, totalTokens: Int?, tokensPerCorrectAnswer: Double?, tokensPerScorePoint: Double?, failures: Int, malformedOutputs: Int, toolCalls: Int, iterations: Int) { // Creates one complete aggregate summary.
        self.overallScore = overallScore // Stores weighted overall score.
        self.qualityScore = qualityScore // Stores optional quality evidence.
        self.reliabilityScore = reliabilityScore // Stores optional reliability evidence.
        self.toolUseScore = toolUseScore // Stores optional tool-use evidence.
        self.engineeringScore = engineeringScore // Stores optional engineering evidence.
        self.performanceScore = performanceScore // Stores optional bounded performance evidence.
        self.categoryScores = categoryScores // Stores typed category scores.
        self.weightedContributions = weightedContributions // Stores visible contribution values.
        self.performance = performance // Stores raw aggregate metrics.
        self.totalTokens = totalTokens // Stores optional truthful token total.
        self.tokensPerCorrectAnswer = tokensPerCorrectAnswer // Stores optional answer efficiency.
        self.tokensPerScorePoint = tokensPerScorePoint // Stores optional score efficiency.
        self.failures = failures // Stores terminal failure count.
        self.malformedOutputs = malformedOutputs // Stores malformed output count.
        self.toolCalls = toolCalls // Stores returned tool-call count.
        self.iterations = iterations // Stores evaluation iteration count.
    } // Ends aggregate summary construction.

    private enum CodingKeys: String, CodingKey { // Defines stable persistence field names.
        case overallScore // Stores weighted overall.
        case qualityScore // Stores quality.
        case reliabilityScore // Stores reliability.
        case toolUseScore // Stores tool use.
        case engineeringScore // Stores engineering.
        case performanceScore // Stores performance score.
        case categoryScores // Stores raw-string category map.
        case weightedContributions // Stores dimension contribution map.
        case performance // Stores raw performance aggregate.
        case totalTokens // Stores tokens.
        case tokensPerCorrectAnswer // Stores answer efficiency.
        case tokensPerScorePoint // Stores score efficiency.
        case failures // Stores failures.
        case malformedOutputs // Stores malformed outputs.
        case toolCalls // Stores tool calls.
        case iterations // Stores iterations.
    } // Ends summary coding keys.

    init(from decoder: Decoder) throws { // Decodes canonical string-keyed category scores deterministically.
        let container = try decoder.container(keyedBy: CodingKeys.self) // Opens the summary object.
        overallScore = try container.decode(Double.self, forKey: .overallScore) // Decodes weighted overall.
        qualityScore = try container.decodeIfPresent(Double.self, forKey: .qualityScore) // Decodes optional quality.
        reliabilityScore = try container.decodeIfPresent(Double.self, forKey: .reliabilityScore) // Decodes optional reliability.
        toolUseScore = try container.decodeIfPresent(Double.self, forKey: .toolUseScore) // Decodes optional tool score.
        engineeringScore = try container.decodeIfPresent(Double.self, forKey: .engineeringScore) // Decodes optional engineering score.
        performanceScore = try container.decodeIfPresent(Double.self, forKey: .performanceScore) // Decodes optional performance score.
        let storedCategories = try container.decode([String: Double].self, forKey: .categoryScores) // Decodes a canonical JSON object instead of a non-string dictionary array.
        categoryScores = Dictionary(uniqueKeysWithValues: storedCategories.compactMap { key, value in BenchmarkCategory(rawValue: key).map { ($0, value) } }) // Restores only known stable category keys.
        weightedContributions = try container.decode([String: Double].self, forKey: .weightedContributions) // Decodes visible contributions.
        performance = try container.decode(BenchmarkPerformanceStatistics.self, forKey: .performance) // Decodes raw performance aggregate.
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens) // Decodes optional token total.
        tokensPerCorrectAnswer = try container.decodeIfPresent(Double.self, forKey: .tokensPerCorrectAnswer) // Decodes optional answer efficiency.
        tokensPerScorePoint = try container.decodeIfPresent(Double.self, forKey: .tokensPerScorePoint) // Decodes optional score efficiency.
        failures = try container.decode(Int.self, forKey: .failures) // Decodes failures.
        malformedOutputs = try container.decode(Int.self, forKey: .malformedOutputs) // Decodes malformed output count.
        toolCalls = try container.decode(Int.self, forKey: .toolCalls) // Decodes tool-call count.
        iterations = try container.decode(Int.self, forKey: .iterations) // Decodes iterations.
    } // Ends summary decoding.

    func encode(to encoder: Encoder) throws { // Encodes category scores as sorted-key-compatible JSON object data.
        var container = encoder.container(keyedBy: CodingKeys.self) // Opens the summary object.
        try container.encode(overallScore, forKey: .overallScore) // Encodes weighted overall.
        try container.encodeIfPresent(qualityScore, forKey: .qualityScore) // Encodes optional quality.
        try container.encodeIfPresent(reliabilityScore, forKey: .reliabilityScore) // Encodes optional reliability.
        try container.encodeIfPresent(toolUseScore, forKey: .toolUseScore) // Encodes optional tool score.
        try container.encodeIfPresent(engineeringScore, forKey: .engineeringScore) // Encodes optional engineering score.
        try container.encodeIfPresent(performanceScore, forKey: .performanceScore) // Encodes optional performance score.
        try container.encode(Dictionary(uniqueKeysWithValues: categoryScores.map { ($0.key.rawValue, $0.value) }), forKey: .categoryScores) // Encodes stable raw category keys that sortedKeys can canonicalize.
        try container.encode(weightedContributions, forKey: .weightedContributions) // Encodes dimension contributions.
        try container.encode(performance, forKey: .performance) // Encodes raw performance aggregate.
        try container.encodeIfPresent(totalTokens, forKey: .totalTokens) // Encodes optional tokens.
        try container.encodeIfPresent(tokensPerCorrectAnswer, forKey: .tokensPerCorrectAnswer) // Encodes optional answer efficiency.
        try container.encodeIfPresent(tokensPerScorePoint, forKey: .tokensPerScorePoint) // Encodes optional score efficiency.
        try container.encode(failures, forKey: .failures) // Encodes failure count.
        try container.encode(malformedOutputs, forKey: .malformedOutputs) // Encodes malformed count.
        try container.encode(toolCalls, forKey: .toolCalls) // Encodes tool-call count.
        try container.encode(iterations, forKey: .iterations) // Encodes iteration count.
    } // Ends summary encoding.
} // Ends aggregate evaluation summary.

struct BenchmarkRun: Identifiable, Codable, Equatable, Sendable { // Stores one durable run with immutable suite/configuration snapshots and bounded results.
    let id: UUID // Supplies stable run history identity.
    let suiteID: UUID // Stores suite identity for comparability.
    let suiteName: String // Stores visible suite name independently from later custom edits.
    let suiteVersion: Int // Stores exact suite revision.
    let caseIDs: [UUID] // Stores selected ordered case set for strict comparability.
    let mode: BenchmarkRunMode // Stores quick, standard, category, or custom selection policy.
    let selectedCategory: BenchmarkCategory? // Stores one-category selection when applicable.
    let modelConfiguration: BenchmarkModelConfiguration // Stores exact target and generation settings.
    let environment: BenchmarkEnvironment // Stores non-sensitive host metadata.
    let scoreWeights: BenchmarkScoreWeights // Stores the exact weighting used for aggregation.
    let startedAt: Date // Stores run start.
    var completedAt: Date? // Stores terminal time after completion or cancellation.
    var state: BenchmarkRunState // Stores durable lifecycle.
    var results: [BenchmarkCaseResult] // Stores completed repetition results in execution order.
    var summary: ModelEvaluationSummary? // Stores aggregate scores after each progress checkpoint.
    var isBaseline: Bool // Stores optional user baseline designation.
    var issue: String? // Stores one bounded fatal or persistence-facing issue.
    let isDeterministicDemo: Bool // Distinguishes sample harness validation from real model evidence.
} // Ends benchmark run model.

struct BenchmarkProgress: Equatable, Sendable { // Publishes efficient per-repetition progress without token-level updates.
    let completed: Int // Stores completed terminal repetitions.
    let total: Int // Stores planned repetitions.
    let currentCaseName: String? // Stores current visible case name.
    let failures: Int // Stores current failure/error count.
    let elapsedMilliseconds: Int // Stores monotonic run elapsed time.
} // Ends benchmark progress value.

struct BenchmarkComparability: Equatable, Sendable { // Explains whether two run snapshots may be compared fairly.
    let isComparable: Bool // Indicates all required suite, case-set, and generation-setting checks passed.
    let differences: [String] // Lists every visible mismatch instead of hiding it.
} // Ends comparability result.

struct BenchmarkRunComparison: Equatable, Sendable { // Combines two runs with comparability and inspectable metrics.
    let first: BenchmarkRun // Stores first selected run.
    let second: BenchmarkRun // Stores second selected run.
    let comparability: BenchmarkComparability // Stores compatibility verdict and warnings.
} // Ends two-run comparison.

enum BenchmarkRole: String, Codable, CaseIterable, Identifiable, Sendable { // Defines benchmark-derived roles without enabling automatic routing.
    case general // Represents broad conversational tasks.
    case coding // Represents code generation and comprehension.
    case engineering // Represents inspect/edit/test/verify workflows.
    case reviewer // Represents code-review workflows.
    case structuredOutput = "structured-output" // Represents strict JSON output.
    case toolUse = "tool-use" // Represents tool selection and argument reliability.

    var id: String { rawValue } // Supplies stable SwiftUI identity.

    var displayName: String { // Produces concise recommendation labels.
        switch self { // Maps stable role values to presentation names.
        case .general: return "General" // Names broad role.
        case .coding: return "Coding" // Names coding role.
        case .engineering: return "Engineering" // Names engineering role.
        case .reviewer: return "Reviewer" // Names review role.
        case .structuredOutput: return "Structured Output" // Names structured-output role.
        case .toolUse: return "Tool Use" // Names tool role.
        } // Ends role display mapping.
    } // Ends role display name.

    var category: BenchmarkCategory { // Maps each recommendation to its transparent benchmark category.
        switch self { // Selects the corresponding category.
        case .general: return .general // Uses general score.
        case .coding: return .coding // Uses coding score.
        case .engineering: return .engineering // Uses engineering score.
        case .reviewer: return .reviewer // Uses reviewer score.
        case .structuredOutput: return .structuredOutput // Uses structured-output score.
        case .toolUse: return .toolUse // Uses tool-use score.
        } // Ends role-category mapping.
    } // Ends role category.
} // Ends recommendation roles.

struct BenchmarkRoleRecommendation: Identifiable, Equatable, Sendable { // Stores one deterministic best-model recommendation derived from comparable data.
    var id: BenchmarkRole { role } // Uses stable role identity.
    let role: BenchmarkRole // Stores recommended role.
    let target: ModelGenerationTarget // Stores winning exact model identity.
    let score: Double // Stores winning category score.
    let runID: UUID // Links recommendation to evidence.
} // Ends role recommendation.

enum BenchmarkValidationError: LocalizedError, Equatable, Sendable { // Defines bounded suite, case, configuration, and storage validation failures.
    case emptySuiteName // Indicates missing suite identity.
    case emptySuite // Indicates a suite has no cases.
    case invalidSuiteVersion // Indicates version is below one.
    case duplicateCaseID // Indicates ambiguous case identity.
    case emptyCaseName // Indicates missing case identity.
    case emptyPrompt // Indicates no model input.
    case invalidTimeout // Indicates non-positive or excessive timeout.
    case invalidOutputLimit // Indicates unsafe output-token bound.
    case invalidRegex // Indicates a declarative pattern cannot compile.
    case invalidNumericExpectation // Indicates non-finite numeric grading configuration.
    case invalidScoreWeights // Indicates negative, non-finite, or zero-total weights.
    case invalidRunsPerCase // Indicates repeated-run count is not 1, 3, or 5.
    case builtInMutation // Indicates an attempt to persist over an immutable shipped suite.
    case importTooLarge // Indicates imported JSON exceeds the fixed safe size.
    case unsupportedSchemaVersion(Int) // Indicates persisted data requires an unknown migration.
    case corruptRecord // Indicates a record could not be decoded safely.

    var errorDescription: String? { // Produces concise user-facing validation copy.
        switch self { // Maps each validation failure to corrective text.
        case .emptySuiteName: return "Benchmark suite name cannot be empty." // Explains missing name.
        case .emptySuite: return "A benchmark suite must contain at least one case." // Explains empty suite.
        case .invalidSuiteVersion: return "Benchmark suite version must be at least 1." // Explains version bound.
        case .duplicateCaseID: return "Benchmark case identifiers must be unique within a suite." // Explains identity collision.
        case .emptyCaseName: return "Benchmark case name cannot be empty." // Explains missing case name.
        case .emptyPrompt: return "Benchmark case prompt cannot be empty." // Explains missing prompt.
        case .invalidTimeout: return "Benchmark case timeout must be greater than zero and no more than 600 seconds." // Explains timeout bound.
        case .invalidOutputLimit: return "Benchmark case output limit must be between 1 and 8192 tokens." // Explains output bound.
        case .invalidRegex: return "Benchmark regular expression is invalid." // Explains pattern failure without echoing input.
        case .invalidNumericExpectation: return "Benchmark numeric expectation and tolerance must be finite and tolerance cannot be negative." // Explains numeric constraints.
        case .invalidScoreWeights: return "Benchmark score weights must be finite, non-negative, and have a positive total." // Explains weight constraints.
        case .invalidRunsPerCase: return "Runs per case must be 1, 3, or 5." // Explains repetition choices.
        case .builtInMutation: return "Built-in benchmark suites are read-only. Duplicate the suite to edit it." // Explains immutable built-in policy.
        case .importTooLarge: return "The imported benchmark suite exceeds the 2 MB safety limit." // Explains import bound.
        case .unsupportedSchemaVersion(let version): return "Benchmark schema version \(version) is not supported by this app version." // Explains migration requirement.
        case .corruptRecord: return "A benchmark record is corrupt and was skipped." // Explains isolated corruption recovery.
        } // Ends validation error mapping.
    } // Ends localized validation copy.
} // Ends benchmark validation errors.
