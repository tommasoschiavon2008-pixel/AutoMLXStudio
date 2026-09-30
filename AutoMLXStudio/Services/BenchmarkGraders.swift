import Foundation // Supplies strict JSON decoding, regular expressions, and text normalization.

struct BenchmarkGradingInput: Sendable { // Carries the bounded response fields available to every deterministic grader.
    let text: String? // Stores visible model text when returned.
    let toolCalls: [ModelToolCall] // Stores validated provider-native calls when returned.
} // Ends deterministic grading input.

struct BenchmarkGrade: Equatable, Sendable { // Returns a transparent deterministic grade independently from run aggregation.
    let score: Double // Stores a bounded 0-to-100 correctness score.
    let passed: Bool // Records whether the response met the strategy contract.
    let details: String // Explains the result without hidden reasoning.
    let errorKind: BenchmarkErrorKind? // Classifies malformed output separately from a valid wrong answer.
} // Ends one deterministic grade.

protocol BenchmarkGradingStrategy: Sendable { // Defines the small replaceable strategy boundary used by the registry.
    func grade(_ input: BenchmarkGradingInput) -> BenchmarkGrade // Grades one already returned model response without side effects.
} // Ends the grading strategy protocol.

struct BenchmarkGraderRegistry: Sendable { // Resolves declarative suite specifications to isolated deterministic strategies.
    func grade(specification: BenchmarkGradingSpecification, input: BenchmarkGradingInput) -> BenchmarkGrade { // Evaluates one safe grading specification.
        switch specification { // Selects one purpose-built strategy without executing imported code.
        case .exact(let expected): return ExactBenchmarkGrader(expected: expected).grade(input) // Uses literal text equality.
        case .normalized(let expected, let options): return NormalizedBenchmarkGrader(expected: expected, options: options).grade(input) // Uses explicit normalization only.
        case .contains(let values, let requiresAll, let ignoresCase): return ContainsBenchmarkGrader(values: values, requiresAll: requiresAll, ignoresCase: ignoresCase).grade(input) // Uses bounded phrase checks.
        case .regex(let pattern, let ignoresCase): return RegexBenchmarkGrader(pattern: pattern, ignoresCase: ignoresCase).grade(input) // Uses a prevalidated regular expression.
        case .numeric(let expected, let tolerance): return NumericBenchmarkGrader(expected: expected, tolerance: tolerance).grade(input) // Uses finite numeric tolerance.
        case .json(let expectation): return JSONBenchmarkGrader(expectation: expectation).grade(input) // Uses strict JSON structure checks.
        case .toolCalls(let expectation): return ToolCallBenchmarkGrader(expectation: expectation).grade(input) // Uses native or simulated tool-call checks.
        case .programmatic(let identifier, let expected): return ProgrammaticBenchmarkGrader(identifier: identifier, expected: expected).grade(input) // Uses only a closed registry of harmless functions.
        } // Ends strategy selection.
    } // Ends deterministic grading.
} // Ends grader registry.

private struct ExactBenchmarkGrader: BenchmarkGradingStrategy { // Implements strict visible-text grading.
    let expected: String // Stores the exact expected text.

    func grade(_ input: BenchmarkGradingInput) -> BenchmarkGrade { // Compares the response after boundary newline removal only.
        guard let text = input.text else { return .malformed("No text response was returned.") } // Rejects absent text explicitly.
        let actual = text.trimmingCharacters(in: .newlines) // Ignores transport-added boundary newlines but no content characters.
        return actual == expected ? .pass("Exact text matched.") : .fail("Exact text did not match.") // Reports literal equality.
    } // Ends exact grading.
} // Ends exact grader.

private struct NormalizedBenchmarkGrader: BenchmarkGradingStrategy { // Implements only explicitly configured safe text normalization.
    let expected: String // Stores expected visible text.
    let options: BenchmarkNormalizationOptions // Stores normalization policy.

    func grade(_ input: BenchmarkGradingInput) -> BenchmarkGrade { // Normalizes both values symmetrically before equality.
        guard let text = input.text else { return .malformed("No text response was returned.") } // Rejects absent text explicitly.
        let actualValue = normalize(text) // Normalizes returned text.
        let expectedValue = normalize(expected) // Normalizes expected text identically.
        return actualValue == expectedValue ? .pass("Normalized text matched.") : .fail("Normalized text did not match.") // Reports normalized equality.
    } // Ends normalized grading.

    private func normalize(_ value: String) -> String { // Applies the configured transformations in a stable order.
        var result = value // Starts from the original Unicode string.
        if options.trimsWhitespace { result = result.trimmingCharacters(in: .whitespacesAndNewlines) } // Removes boundaries only when configured.
        if options.collapsesWhitespace { result = result.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") } // Collapses all internal whitespace runs.
        if options.ignoresCase { result = result.lowercased(with: Locale(identifier: "en_US_POSIX")) } // Uses a stable locale for case folding.
        return result // Returns the fully normalized value.
    } // Ends text normalization.
} // Ends normalized grader.

private struct ContainsBenchmarkGrader: BenchmarkGradingStrategy { // Implements explicit phrase-presence grading.
    let values: [String] // Stores bounded required phrases.
    let requiresAll: Bool // Chooses all-versus-any semantics.
    let ignoresCase: Bool // Chooses case comparison policy.

    func grade(_ input: BenchmarkGradingInput) -> BenchmarkGrade { // Checks every declared phrase without fuzzy matching.
        guard let text = input.text else { return .malformed("No text response was returned.") } // Rejects absent text explicitly.
        guard !values.isEmpty else { return .gradingError("Contains grader has no expected phrases.") } // Rejects invalid configuration safely.
        let options: String.CompareOptions = ignoresCase ? [.caseInsensitive] : [] // Builds the exact comparison policy.
        let checks = values.map { text.range(of: $0, options: options) != nil } // Evaluates each declared phrase once.
        let passed = requiresAll ? checks.allSatisfy { $0 } : checks.contains(true) // Applies explicit all-or-any semantics.
        return passed ? .pass("Required phrase condition matched.") : .fail("Required phrase condition did not match.") // Reports phrase outcome.
    } // Ends phrase grading.
} // Ends contains grader.

private struct RegexBenchmarkGrader: BenchmarkGradingStrategy { // Implements bounded regular-expression grading.
    let pattern: String // Stores the validated ICU-compatible pattern.
    let ignoresCase: Bool // Stores the case policy.

    func grade(_ input: BenchmarkGradingInput) -> BenchmarkGrade { // Searches the complete returned text once.
        guard let text = input.text else { return .malformed("No text response was returned.") } // Rejects absent text explicitly.
        let options: NSRegularExpression.Options = ignoresCase ? [.caseInsensitive] : [] // Builds regex options.
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return .gradingError("Regular expression configuration is invalid.") } // Rejects malformed imported patterns.
        let range = NSRange(text.startIndex..<text.endIndex, in: text) // Builds a Unicode-safe full-text range.
        let passed = expression.firstMatch(in: text, range: range) != nil // Requires at least one declared match.
        return passed ? .pass("Regular expression matched.") : .fail("Regular expression did not match.") // Reports pattern outcome.
    } // Ends regex grading.
} // Ends regex grader.

private struct NumericBenchmarkGrader: BenchmarkGradingStrategy { // Implements strict finite-number grading.
    let expected: Double // Stores expected finite value.
    let tolerance: Double // Stores non-negative absolute tolerance.

    func grade(_ input: BenchmarkGradingInput) -> BenchmarkGrade { // Decodes the entire visible response as one number.
        guard let text = input.text else { return .malformed("No text response was returned.") } // Rejects absent text explicitly.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines) // Removes presentation whitespace only.
        guard let actual = Double(trimmed), actual.isFinite else { return .malformed("Response was not one finite number.") } // Rejects prose, NaN, and infinity.
        let passed = abs(actual - expected) <= tolerance // Applies exact absolute-tolerance semantics.
        return passed ? .pass("Numeric value was within tolerance.") : .fail("Numeric value was outside tolerance.") // Reports numeric outcome.
    } // Ends numeric grading.
} // Ends numeric grader.

private struct JSONBenchmarkGrader: BenchmarkGradingStrategy { // Implements strict JSON root, path, type, and exact-value grading.
    let expectation: BenchmarkJSONExpectation // Stores the declarative schema subset.

    func grade(_ input: BenchmarkGradingInput) -> BenchmarkGrade { // Parses and validates one response without coercion.
        guard let text = input.text else { return .malformed("No text response was returned.") } // Rejects absent text explicitly.
        let candidate = expectation.allowsMarkdownFences ? stripFences(text) : text.trimmingCharacters(in: .whitespacesAndNewlines) // Applies only explicitly allowed fence tolerance.
        guard let data = candidate.data(using: .utf8), let root = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .invalidJSON("Response was not strict JSON.") } // Rejects malformed or non-JSON content.
        guard root.matches(type: expectation.rootType) else { return .invalidJSON("JSON root type did not match.") } // Validates top-level kind.
        for field in expectation.fields { // Evaluates every bounded declarative path.
            let value = root.value(at: field.path) // Resolves object-only dot paths.
            if value == nil, !field.required { continue } // Accepts an omitted optional field.
            guard let value else { return .invalidJSON("Required JSON field \(field.path) was missing.") } // Reports missing required field.
            guard value.matches(type: field.type) else { return .invalidJSON("JSON field \(field.path) had the wrong type.") } // Rejects type coercion.
            if let exact = field.exactValue, value != exact { return .fail("JSON field \(field.path) had the wrong value.") } // Applies strictly typed exact values.
        } // Ends field validation.
        return .pass("JSON structure and declared values matched.") // Accepts the complete declared contract.
    } // Ends JSON grading.

    private func stripFences(_ value: String) -> String { // Removes one optional outer Markdown fence when the suite explicitly allows it.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines) // Removes boundary whitespace.
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else { return trimmed } // Leaves ordinary JSON unchanged.
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false) // Preserves internal JSON newlines.
        guard lines.count >= 3 else { return trimmed } // Rejects incomplete fences.
        return lines.dropFirst().dropLast().joined(separator: "\n") // Removes only the opening and closing fence lines.
    } // Ends explicit fence removal.
} // Ends JSON grader.

private struct ToolCallBenchmarkGrader: BenchmarkGradingStrategy { // Implements exact ordered harmless tool-call grading.
    let expectation: BenchmarkToolCallExpectation // Stores declared call sequence.

    func grade(_ input: BenchmarkGradingInput) -> BenchmarkGrade { // Validates native calls or one strict simulated JSON envelope.
        let calls: [ModelToolCall] // Holds the normalized calls selected for grading.
        if !input.toolCalls.isEmpty { calls = input.toolCalls } // Prefers provider-native validated calls.
        else if let text = input.text, let simulated = Self.decodeSimulatedCalls(text) { calls = simulated } // Accepts strict local JSON simulation without executing it.
        else { return .toolError("No valid native or simulated tool calls were returned.") } // Rejects missing or malformed tool output.
        if expectation.allowsAdditionalCalls { // Applies prefix semantics only when explicitly allowed.
            guard calls.count >= expectation.calls.count else { return .toolError("Too few tool calls were returned.") } // Requires all expected calls.
        } else if calls.count != expectation.calls.count { return .toolError("Tool-call count did not match.") } // Requires exact count by default.
        for (index, expectedCall) in expectation.calls.enumerated() { // Validates expected order and arguments.
            guard calls.indices.contains(index) else { return .toolError("Expected tool call was missing.") } // Protects array access.
            let actual = calls[index] // Reads one normalized call.
            guard actual.name == expectedCall.name else { return .toolError("Tool name or order did not match.") } // Requires exact stable tool identity.
            for (key, value) in expectedCall.requiredArguments { // Validates every required argument.
                guard actual.arguments[key] == value else { return .toolError("Required tool argument \(key) did not match.") } // Requires strictly typed equality.
            } // Ends required argument checks.
            if !expectedCall.allowsAdditionalArguments, Set(actual.arguments.keys) != Set(expectedCall.requiredArguments.keys) { return .toolError("Unexpected tool arguments were returned.") } // Rejects unnecessary arguments.
        } // Ends ordered call validation.
        return .pass("Tool names, order, and arguments matched.") // Accepts the declared harmless call sequence.
    } // Ends tool-call grading.

    private static func decodeSimulatedCalls(_ text: String) -> [ModelToolCall]? { // Decodes the local-backend strict JSON envelope without execution authority.
        struct Envelope: Decodable { let toolCalls: [Call]; enum CodingKeys: String, CodingKey { case toolCalls = "tool_calls" } } // Defines the exact accepted envelope key.
        struct Call: Decodable { let name: String; let arguments: [String: JSONValue] } // Defines one simulated call without executable fields.
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8), let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil } // Rejects prose and malformed envelopes.
        return envelope.toolCalls.enumerated().map { ModelToolCall(id: "simulated-\($0.offset + 1)", name: $0.element.name, arguments: $0.element.arguments) } // Normalizes safe data and never invokes it.
    } // Ends simulated-call decoding.
} // Ends tool-call grader.

private struct ProgrammaticBenchmarkGrader: BenchmarkGradingStrategy { // Provides a closed non-extensible-by-import registry of harmless deterministic checks.
    let identifier: String // Stores one built-in registered check identifier.
    let expected: JSONValue? // Stores optional declarative expected data.

    func grade(_ input: BenchmarkGradingInput) -> BenchmarkGrade { // Invokes only known in-process text predicates.
        guard let text = input.text else { return .malformed("No text response was returned.") } // Rejects absent text explicitly.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes only response boundaries.
        switch identifier { // Resolves a fixed registry and never loads executable suite content.
        case "ordered-plan": // Checks exact inspect-edit-test-verify ordering for engineering tasks.
            let labels = ["inspect", "edit", "test", "verify"] // Defines the safe expected phase order.
            let positions = labels.compactMap { trimmed.lowercased().range(of: $0)?.lowerBound } // Finds every required phase once.
            guard positions.count == labels.count else { return .fail("Engineering plan omitted a required phase.") } // Requires complete workflow intent.
            let ordered = zip(positions, positions.dropFirst()).allSatisfy { $0 < $1 } // Requires strict phase order.
            return ordered ? .pass("Engineering phases were complete and ordered.") : .fail("Engineering phases were out of order.") // Reports ordering outcome.
        case "single-line": // Checks that a concise answer contains exactly one non-empty line.
            let lines = trimmed.split(whereSeparator: { $0.isNewline }) // Finds visible response lines.
            return lines.count == 1 ? .pass("Response contained one line.") : .fail("Response did not contain exactly one line.") // Reports line-count outcome.
        case "expected-string": // Provides a registered exact string check for generated synthetic cases.
            guard case .string(let expectedText) = expected else { return .gradingError("Programmatic expected-string configuration is invalid.") } // Requires a typed expected string.
            return trimmed == expectedText ? .pass("Registered expected string matched.") : .fail("Registered expected string did not match.") // Reports generated-value equality.
        default: return .gradingError("Programmatic grader identifier is not registered.") // Rejects arbitrary imported identifiers safely.
        } // Ends programmatic registry resolution.
    } // Ends programmatic grading.
} // Ends registered programmatic grader.

private extension BenchmarkGrade { // Centralizes consistent bounded outcomes across all strategies.
    static func pass(_ details: String) -> BenchmarkGrade { BenchmarkGrade(score: 100, passed: true, details: details, errorKind: nil) } // Creates a full deterministic pass.
    static func fail(_ details: String) -> BenchmarkGrade { BenchmarkGrade(score: 0, passed: false, details: details, errorKind: .wrongAnswer) } // Creates a valid wrong-answer outcome.
    static func malformed(_ details: String) -> BenchmarkGrade { BenchmarkGrade(score: 0, passed: false, details: details, errorKind: .malformedResponse) } // Creates a missing-text outcome.
    static func invalidJSON(_ details: String) -> BenchmarkGrade { BenchmarkGrade(score: 0, passed: false, details: details, errorKind: .invalidJSON) } // Creates a structured-output failure.
    static func toolError(_ details: String) -> BenchmarkGrade { BenchmarkGrade(score: 0, passed: false, details: details, errorKind: .toolError) } // Creates a tool-protocol failure.
    static func gradingError(_ details: String) -> BenchmarkGrade { BenchmarkGrade(score: 0, passed: false, details: details, errorKind: .gradingError) } // Creates a grader-configuration failure.
} // Ends shared grade constructors.

private extension JSONValue { // Adds strict introspection used only by declarative benchmark validation.
    func matches(type: BenchmarkJSONType) -> Bool { // Checks JSON shape without coercion.
        switch (self, type) { // Matches each enum case exactly.
        case (.string, .string), (.number, .number), (.boolean, .boolean), (.object, .object), (.array, .array), (.null, .null): return true // Accepts identical JSON kinds.
        default: return false // Rejects every cross-kind comparison.
        } // Ends strict type check.
    } // Ends JSON type matching.

    func value(at path: String) -> JSONValue? { // Resolves a dot-separated object path without expressions or array indexing.
        if path.isEmpty { return self } // Allows a caller to refer to the root explicitly.
        var current = self // Starts traversal at the decoded root.
        for component in path.split(separator: ".").map(String.init) { // Traverses every literal object key.
            guard case .object(let object) = current, let next = object[component] else { return nil } // Stops on missing or non-object segments.
            current = next // Advances to the strictly typed child.
        } // Ends path traversal.
        return current // Returns the resolved JSON value.
    } // Ends strict JSON path lookup.
} // Ends JSON benchmark helpers.
