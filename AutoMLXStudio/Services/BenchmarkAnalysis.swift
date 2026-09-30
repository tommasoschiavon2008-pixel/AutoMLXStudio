import Foundation // Supplies stable model-target grouping for comparisons and recommendations.

enum BenchmarkAnalysis { // Centralizes comparison policy and evidence-derived role recommendations without routing models.
    static func compare(_ first: BenchmarkRun, _ second: BenchmarkRun) -> BenchmarkRunComparison { // Evaluates whether two model runs used equivalent non-model conditions.
        var differences: [String] = [] // Collects every fairness mismatch for user inspection.
        if first.suiteID != second.suiteID { differences.append("Suite identity differs.") } // Requires the same source suite.
        if first.suiteVersion != second.suiteVersion { differences.append("Suite version differs.") } // Requires the same suite revision.
        if first.caseIDs != second.caseIDs { differences.append("Selected case set or order differs.") } // Requires identical ordered cases.
        if first.mode != second.mode { differences.append("Run mode differs.") } // Requires the same selection policy.
        if first.selectedCategory != second.selectedCategory { differences.append("Selected category differs.") } // Requires the same category scope.
        if first.modelConfiguration.runsPerCase != second.modelConfiguration.runsPerCase { differences.append("Repetition count differs.") } // Requires equal statistical repetition.
        if first.modelConfiguration.temperature != second.modelConfiguration.temperature { differences.append("Temperature differs.") } // Requires equal sampling configuration.
        if first.modelConfiguration.maxOutputTokens != second.modelConfiguration.maxOutputTokens { differences.append("Maximum output tokens differ.") } // Requires equal output bounds.
        if first.modelConfiguration.contextLength != second.modelConfiguration.contextLength { differences.append("Declared context length differs.") } // Discloses a context-limit mismatch.
        if first.modelConfiguration.seed != second.modelConfiguration.seed { differences.append("Seed configuration differs.") } // Requires equal seed support and value.
        if first.modelConfiguration.streaming != second.modelConfiguration.streaming { differences.append("Streaming mode differs.") } // Prevents timing comparisons across delivery modes.
        if first.modelConfiguration.qualityMode != second.modelConfiguration.qualityMode { differences.append("Quality mode differs.") } // Requires equal user-visible run policy.
        if first.modelConfiguration.warmupEnabled != second.modelConfiguration.warmupEnabled { differences.append("Warmup policy differs.") } // Requires equal warmup conditions.
        if first.scoreWeights != second.scoreWeights { differences.append("Score weights differ.") } // Requires equal aggregate policy.
        if first.environment.architecture != second.environment.architecture { differences.append("Host architecture differs.") } // Discloses material performance environment mismatch.
        return BenchmarkRunComparison(first: first, second: second, comparability: BenchmarkComparability(isComparable: differences.isEmpty, differences: differences)) // Returns both evidence snapshots and complete verdict.
    } // Ends run comparability analysis.

    static func bestModelsByRole(from runs: [BenchmarkRun]) -> [BenchmarkRoleRecommendation] { // Selects category leaders from completed evidence without changing app routing.
        let eligible = runs.filter { $0.state == .completed && $0.summary != nil } // Uses only terminal runs with calculated summaries.
        return BenchmarkRole.allCases.compactMap { role in // Produces at most one evidence-backed recommendation per role.
            let scored = eligible.compactMap { run -> BenchmarkRoleRecommendation? in // Extracts the requested category score from each run.
                guard let score = run.summary?.categoryScores[role.category] else { return nil } // Omits runs that did not evaluate the category.
                return BenchmarkRoleRecommendation(role: role, target: run.modelConfiguration.target, score: score, runID: run.id) // Links the candidate to exact evidence.
            } // Ends role candidate extraction.
            return scored.sorted { lhs, rhs in lhs.score == rhs.score ? lhs.target.modelID < rhs.target.modelID : lhs.score > rhs.score }.first // Selects highest score with deterministic identity tie-break.
        } // Ends role recommendation generation.
    } // Ends evidence-derived recommendations.
} // Ends benchmark analysis.
