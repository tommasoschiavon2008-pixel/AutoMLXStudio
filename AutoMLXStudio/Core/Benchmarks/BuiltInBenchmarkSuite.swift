import Foundation // Supplies stable UUIDs, finite-number checks, and regular-expression validation.

enum BuiltInBenchmarkSuite { // Defines the original offline benchmark corpus shipped with V0.6.1.
    static let suiteID = UUID(uuidString: "D0610000-0000-4000-8000-000000000001")! // Keeps built-in suite identity stable across launches and exports.

    static let standard = BenchmarkSuite( // Publishes the immutable standard suite snapshot.
        id: suiteID, // Uses the stable V0.6.1 suite identity.
        name: "AutoMLXStudio Core Evaluation", // Names the app-owned original corpus.
        description: "Deterministic offline evaluation for general, reasoning, coding, structured output, tool use, engineering, review, and synthetic long-context behavior.", // Explains scope without claiming external benchmark compatibility.
        cases: generalCases + reasoningCases + codingCases + structuredCases + toolCases + engineeringCases + reviewerCases + longContextCases, // Preserves deterministic category order.
        version: 1, // Starts the explicit built-in schema revision.
        isBuiltIn: true, // Prevents edits to shipped evidence.
        createdAt: Date(timeIntervalSince1970: 1_786_406_400), // Uses a stable V0.6.1 release-era timestamp for deterministic exports.
        updatedAt: Date(timeIntervalSince1970: 1_786_406_400) // Keeps the initial built-in revision stable.
    ) // Ends standard suite construction.

    static var quickCases: [BenchmarkCase] { // Selects one representative task from every category.
        standard.cases.filter { $0.tags.contains("quick") } // Uses explicit tags so quick selection remains inspectable.
    } // Ends quick case selection.

    private static let generalCases: [BenchmarkCase] = [ // Defines five broad deterministic language tasks.
        textCase(1, "Follow two transformations", .general, "Return the word studio in uppercase, followed by a colon and the number 61. Return only the result.", "STUDIO:61", .exact(expected: "STUDIO:61"), ["quick", "instruction-following"]), // Tests multi-constraint instruction following.
        textCase(2, "Classify message intent", .general, "Classify this message as QUESTION, COMMAND, or STATEMENT. Return one label only: 'Please archive the completed run.'", "COMMAND", .normalized(expected: "COMMAND", options: .init(ignoresCase: true)), ["classification"]), // Tests simple classification.
        textCase(3, "Extract stable identifier", .general, "Extract only the run identifier from: 'Result run_id=V061-042 is ready.'", "V061-042", .regex(pattern: "^V061-042$", ignoresCase: false), ["extraction"]), // Tests constrained extraction.
        textCase(4, "Retain required terms", .general, "Write one short sentence containing both 'offline' and 'deterministic'.", "A sentence containing offline and deterministic.", .contains(values: ["offline", "deterministic"], requiresAll: true, ignoresCase: true), ["constraints"]), // Tests inclusion constraints.
        textCase(5, "Concise one-line response", .general, "Answer on exactly one non-empty line: What platform does AutoMLXStudio target?", "A one-line answer naming macOS.", .programmatic(identifier: "single-line", expected: nil), ["format"]), // Tests concise response shape.
    ] // Ends general cases.

    private static let reasoningCases: [BenchmarkCase] = [ // Defines five original short reasoning tasks.
        textCase(6, "Inventory remainder", .reasoning, "A lab has 17 adapters. It assigns 4 adapters to each of 3 benches. How many remain? Return only the number.", "5", .numeric(expected: 5, tolerance: 0), ["quick", "arithmetic"]), // Tests bounded arithmetic.
        textCase(7, "Sequence continuation", .reasoning, "Continue the sequence 3, 6, 12, 24. Return only the next number.", "48", .numeric(expected: 48, tolerance: 0), ["sequence"]), // Tests geometric sequence recognition.
        textCase(8, "Constraint intersection", .reasoning, "A run must be after Tuesday, before Friday, and not Thursday. Return only the weekday.", "Wednesday", .normalized(expected: "Wednesday", options: .init(ignoresCase: true)), ["logic"]), // Tests simple constraint intersection.
        textCase(9, "Weighted total", .reasoning, "Quality is 80 with weight 0.35 and Reliability is 60 with weight 0.25. Ignore all other dimensions. Return only their unnormalized weighted sum.", "43", .numeric(expected: 43, tolerance: 0.0001), ["weights"]), // Tests transparent weighted calculation.
        textCase(10, "Ordering deduction", .reasoning, "Mira finishes before Niko. Niko finishes before Oren. Return the three names from first to last separated by commas.", "Mira,Niko,Oren", .normalized(expected: "Mira,Niko,Oren", options: .init(ignoresCase: false, collapsesWhitespace: true)), ["ordering"]), // Tests transitive ordering.
    ] // Ends reasoning cases.

    private static let codingCases: [BenchmarkCase] = [ // Defines five small language-diverse code comprehension tasks.
        textCase(11, "Swift array result", .coding, "In Swift, what does `[1, 2, 3].map { $0 * 2 }` produce? Return exactly `[2, 4, 6]`.", "[2, 4, 6]", .exact(expected: "[2, 4, 6]"), ["quick", "swift"]), // Tests Swift expression comprehension.
        textCase(12, "Python loop output", .coding, "What single integer is printed by `total = 0\nfor n in [2, 5, 1]: total += n\nprint(total)`? Return only the integer.", "8", .numeric(expected: 8, tolerance: 0), ["python"]), // Tests Python loop comprehension.
        textCase(13, "C++ boundary correction", .coding, "A C++ loop over a vector uses `i <= values.size()` and reads `values[i]`. Return only the corrected loop condition.", "i < values.size()", .normalized(expected: "i < values.size()", options: .init()), ["cpp", "bug-fix"]), // Tests off-by-one correction.
        textCase(14, "Swift optional safeguard", .coding, "Return the Swift keyword pair used to unwrap an optional and exit when it is nil. Return only two words.", "guard let", .normalized(expected: "guard let", options: .init(ignoresCase: false)), ["swift", "safety"]), // Tests language syntax knowledge.
        textCase(15, "Complexity classification", .coding, "A loop visits every element once and does constant work. Return only the Big-O time complexity.", "O(n)", .normalized(expected: "O(n)", options: .init(ignoresCase: true)), ["complexity"]), // Tests basic complexity reasoning.
    ] // Ends coding cases.

    private static let structuredCases: [BenchmarkCase] = [ // Defines five strict machine-readable output tasks.
        jsonCase(16, "Run state object", "Return strict JSON only with keys status and version. status must be \"ready\" and version must be 61.", [.init(path: "status", type: .string, exactValue: .string("ready")), .init(path: "version", type: .number, exactValue: .number(61))], ["quick", "json"]), // Tests exact scalar fields.
        jsonCase(17, "Nested score object", "Return strict JSON only: an object containing metrics.score equal to 100.", [.init(path: "metrics", type: .object), .init(path: "metrics.score", type: .number, exactValue: .number(100))], ["nested"]), // Tests nested object paths.
        jsonCase(18, "Boolean policy object", "Return strict JSON only with enabled set to false and mode set to \"sequential\".", [.init(path: "enabled", type: .boolean, exactValue: .boolean(false)), .init(path: "mode", type: .string, exactValue: .string("sequential"))], ["schema"]), // Tests Boolean and string types.
        BenchmarkCase(id: identifier(19), name: "String array root", category: .structuredOutput, prompt: "Return strict JSON only: an array containing the strings alpha and beta in that order.", expectedDescription: "[\"alpha\",\"beta\"]", grading: .json(expectation: .init(rootType: .array, fields: [.init(path: "", type: .array, exactValue: .array([.string("alpha"), .string("beta")]))], allowsMarkdownFences: false)), tags: ["array"], difficulty: .easy), // Tests an exact array root without accepting Markdown fences.
        jsonCase(20, "Optional field schema", "Return strict JSON only with id equal to \"case-20\". An optional note string may be included.", [.init(path: "id", type: .string, exactValue: .string("case-20")), .init(path: "note", type: .string, required: false)], ["optional"]), // Tests optional fields.
    ] // Ends structured-output cases.

    private static let toolCases: [BenchmarkCase] = [ // Defines four harmless tool-selection tasks with no execution authority.
        toolCase(21, "Select weather lookup", "Use the provided harmless tool representation to look up weather for Rome. Do not answer with prose.", "lookup_weather(city: Rome)", "lookup_weather", ["city": .string("Rome")], ["quick", "single-tool"]), // Tests exact single tool and argument.
        toolCase(22, "Select calculator", "Use the provided harmless tool representation to calculate 7 multiplied by 9. Do not answer with prose.", "calculate(expression: 7*9)", "calculate", ["expression": .string("7*9")], ["calculation"]), // Tests expression argument preservation.
        toolCase(23, "Select project search", "Use the provided harmless tool representation to search project text for BenchmarkRun. Do not answer with prose.", "search_project(query: BenchmarkRun)", "search_project", ["query": .string("BenchmarkRun")], ["engineering-tool"]), // Tests bounded search intent.
        BenchmarkCase(id: identifier(24), name: "Ordered two-tool plan", category: .toolUse, prompt: "Return two harmless tool calls in order: search_project for AppState, then open_file for AppState.swift. Do not answer with prose.", expectedDescription: "search_project then open_file", grading: .toolCalls(expectation: .init(calls: [.init(name: "search_project", requiredArguments: ["query": .string("AppState")]), .init(name: "open_file", requiredArguments: ["path": .string("AppState.swift")])])), timeoutSeconds: 60, maxOutputTokens: 256, tags: ["ordered-tools"], difficulty: .medium), // Tests strict call order and exact arguments.
    ] // Ends tool-use cases.

    private static let engineeringCases: [BenchmarkCase] = [ // Defines three safe engineering workflow tasks against synthetic fixtures.
        textCase(25, "Four-phase change plan", .engineering, "For a safe code change, give a concise plan whose phase labels appear in this exact order: Inspect, Edit, Test, Verify.", "Inspect, Edit, Test, Verify in order.", .programmatic(identifier: "ordered-plan", expected: nil), ["quick", "workflow"]), // Tests complete workflow sequencing.
        textCase(26, "Isolated fixture repair", .engineering, "A fixture function returns `a - b` but its contract says sum. Name the exact replacement expression only.", "a + b", .normalized(expected: "a + b", options: .init()), ["fixture", "edit-intent"]), // Tests bounded edit intent without modifying files.
        textCase(27, "Verification command intent", .engineering, "A Swift package change needs its unit suite run. Return only the conventional SwiftPM test command.", "swift test", .normalized(expected: "swift test", options: .init()), ["test-intent"]), // Tests verification-tool intent without shell execution.
    ] // Ends engineering cases.

    private static let reviewerCases: [BenchmarkCase] = [ // Defines three deterministic review tasks.
        textCase(28, "Detect force unwrap", .reviewer, "Review `let value = input!` where input may be nil. Return only the defect label `unsafe force unwrap`.", "unsafe force unwrap", .normalized(expected: "unsafe force unwrap", options: .init(ignoresCase: true)), ["quick", "safety"]), // Tests clear defect identification.
        textCase(29, "Assign blocking severity", .reviewer, "A change deletes all user projects on app launch. Return only the severity: BLOCKER, HIGH, MEDIUM, or LOW.", "BLOCKER", .normalized(expected: "BLOCKER", options: .init(ignoresCase: true)), ["severity"]), // Tests high-impact severity judgment.
        textCase(30, "Identify missing assertion", .reviewer, "A test calls a function but checks no output or state. Return only `missing assertion`.", "missing assertion", .normalized(expected: "missing assertion", options: .init(ignoresCase: true)), ["test-review"]), // Tests verification-quality review.
    ] // Ends reviewer cases.

    private static let longContextCases: [BenchmarkCase] = [ // Defines three locally generated synthetic context tasks.
        longCase(31, token: "ORCHID-731", slot: 73, tag: "quick"), // Tests recall from an early-middle synthetic record.
        longCase(32, token: "EMBER-942", slot: 142, tag: "recall"), // Tests recall from a later synthetic record.
        longCase(33, token: "COBALT-518", slot: 219, tag: "instruction-retention"), // Tests retention near the end of larger input.
    ] // Ends long-context cases.

    private static func textCase(_ number: Int, _ name: String, _ category: BenchmarkCategory, _ prompt: String, _ expectedDescription: String, _ grading: BenchmarkGradingSpecification, _ tags: [String]) -> BenchmarkCase { // Reduces repeated safe defaults without hiding case semantics.
        BenchmarkCase(id: identifier(number), name: name, category: category, prompt: prompt, expectedDescription: expectedDescription, grading: grading, timeoutSeconds: 60, maxOutputTokens: 256, tags: tags, difficulty: number % 5 == 0 ? .medium : .easy) // Creates one deterministic text case.
    } // Ends text-case helper.

    private static func jsonCase(_ number: Int, _ name: String, _ prompt: String, _ fields: [BenchmarkJSONFieldExpectation], _ tags: [String]) -> BenchmarkCase { // Creates one strict object-root JSON case.
        BenchmarkCase(id: identifier(number), name: name, category: .structuredOutput, prompt: prompt, expectedDescription: "Strict JSON matching the declared schema.", grading: .json(expectation: .init(fields: fields)), timeoutSeconds: 60, maxOutputTokens: 256, tags: tags, difficulty: .easy) // Returns the declarative structured-output task.
    } // Ends JSON-case helper.

    private static func toolCase(_ number: Int, _ name: String, _ prompt: String, _ expectedDescription: String, _ toolName: String, _ arguments: [String: JSONValue], _ tags: [String]) -> BenchmarkCase { // Creates one harmless exact tool-call case.
        BenchmarkCase(id: identifier(number), name: name, category: .toolUse, prompt: prompt, expectedDescription: expectedDescription, grading: .toolCalls(expectation: .init(calls: [.init(name: toolName, requiredArguments: arguments)])), timeoutSeconds: 60, maxOutputTokens: 256, tags: tags, difficulty: .medium) // Returns a call-selection task with no execution path.
    } // Ends tool-case helper.

    private static func longCase(_ number: Int, token: String, slot: Int, tag: String) -> BenchmarkCase { // Generates an original synthetic context locally and deterministically.
        let records = (1...240).map { index in index == slot ? "Record \(index): verification token \(token)." : "Record \(index): synthetic benchmark filler value \(index * 17)." }.joined(separator: "\n") // Builds predictable non-user context with one target token.
        let prompt = "Read the synthetic records below. Return only the verification token in Record \(slot).\n\n\(records)" // Appends one precise recall instruction after identifying the target slot.
        return BenchmarkCase(id: identifier(number), name: "Synthetic recall slot \(slot)", category: .longContext, prompt: prompt, expectedDescription: token, grading: .programmatic(identifier: "expected-string", expected: .string(token)), timeoutSeconds: 120, maxOutputTokens: 64, tags: [tag, "synthetic", "context-warning"], difficulty: .medium) // Returns the fully local long-context case.
    } // Ends synthetic context generation.

    private static func identifier(_ number: Int) -> UUID { // Builds stable case UUIDs from the one-based corpus index.
        UUID(uuidString: String(format: "D0610000-0000-4000-8000-%012d", number))! // Produces a valid deterministic identifier for every shipped case.
    } // Ends stable identifier creation.
} // Ends built-in benchmark corpus.

enum BenchmarkSuiteValidator { // Enforces bounded declarative imports and run configurations before execution.
    static let maximumImportBytes = 2 * 1_024 * 1_024 // Caps imported suite JSON at two mebibytes.

    static func validate(_ suite: BenchmarkSuite, permitsBuiltIn: Bool = true) throws { // Validates a complete suite snapshot without modifying it.
        guard !suite.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BenchmarkValidationError.emptySuiteName } // Requires visible identity.
        guard !suite.cases.isEmpty else { throw BenchmarkValidationError.emptySuite } // Requires executable content.
        guard suite.version >= 1 else { throw BenchmarkValidationError.invalidSuiteVersion } // Requires a supported positive revision.
        guard permitsBuiltIn || !suite.isBuiltIn else { throw BenchmarkValidationError.builtInMutation } // Protects shipped suite persistence.
        guard Set(suite.cases.map(\.id)).count == suite.cases.count else { throw BenchmarkValidationError.duplicateCaseID } // Prevents ambiguous case results.
        for item in suite.cases { try validate(item) } // Validates every case independently.
    } // Ends suite validation.

    static func validate(_ item: BenchmarkCase) throws { // Validates one imported or created case.
        guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BenchmarkValidationError.emptyCaseName } // Requires visible case identity.
        guard !item.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BenchmarkValidationError.emptyPrompt } // Requires model input.
        guard item.timeoutSeconds > 0, item.timeoutSeconds <= 600 else { throw BenchmarkValidationError.invalidTimeout } // Bounds resource occupancy.
        guard (1...8_192).contains(item.maxOutputTokens) else { throw BenchmarkValidationError.invalidOutputLimit } // Bounds generated output.
        switch item.grading { // Validates strategy-specific declarative configuration.
        case .regex(let pattern, let ignoresCase): // Checks regular-expression compilation.
            let options: NSRegularExpression.Options = ignoresCase ? [.caseInsensitive] : [] // Builds declared pattern options.
            guard (try? NSRegularExpression(pattern: pattern, options: options)) != nil else { throw BenchmarkValidationError.invalidRegex } // Rejects invalid patterns.
        case .numeric(let expected, let tolerance): guard expected.isFinite, tolerance.isFinite, tolerance >= 0 else { throw BenchmarkValidationError.invalidNumericExpectation } // Requires finite numeric bounds.
        case .contains(let values, _, _): guard !values.isEmpty else { throw BenchmarkValidationError.corruptRecord } // Requires at least one phrase.
        case .programmatic(let identifier, _): guard ["ordered-plan", "single-line", "expected-string"].contains(identifier) else { throw BenchmarkValidationError.corruptRecord } // Allows only registered non-executable identifiers.
        case .exact, .normalized, .json, .toolCalls: break // Requires no additional executable validation.
        } // Ends strategy validation.
    } // Ends case validation.

    static func validate(weights: BenchmarkScoreWeights, runsPerCase: Int) throws { // Validates scoring and repetition configuration.
        let values = [weights.quality, weights.reliability, weights.toolUse, weights.engineering, weights.performance] // Collects every score dimension.
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }), weights.total > 0 else { throw BenchmarkValidationError.invalidScoreWeights } // Rejects invalid or zero-total weights.
        guard [1, 3, 5].contains(runsPerCase) else { throw BenchmarkValidationError.invalidRunsPerCase } // Restricts repeated evaluation to visible options.
    } // Ends run configuration validation.
} // Ends benchmark validation.
