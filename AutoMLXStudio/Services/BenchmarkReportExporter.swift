import Foundation // Supplies deterministic JSON and Markdown file export.

enum BenchmarkReportExporter { // Produces portable read-only result artifacts without changing run evidence.
    static let schemaVersion = 1 // Declares the result-export schema version.

    static func jsonData(for run: BenchmarkRun) throws -> Data { // Encodes one complete run as inspectable stable JSON.
        struct Export: Codable { let schemaVersion: Int; let run: BenchmarkRun } // Defines the explicit portable result envelope.
        let encoder = JSONEncoder() // Creates a thread-confined encoder.
        encoder.dateEncodingStrategy = .iso8601 // Uses stable visible timestamps.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] // Produces deterministic human-readable JSON.
        return try encoder.encode(Export(schemaVersion: schemaVersion, run: run)) // Encodes the immutable run snapshot.
    } // Ends JSON result export.

    static func markdown(for run: BenchmarkRun) -> String { // Builds a concise auditable Markdown report.
        var lines: [String] = [] // Collects deterministic report lines.
        lines.append("# Benchmark Result — \(escape(run.suiteName))") // Writes report title.
        lines.append("") // Separates title from metadata.
        lines.append("- Run ID: `\(run.id.uuidString)`") // Records stable run identity.
        lines.append("- State: **\(run.state.rawValue.uppercased())**") // Records terminal lifecycle.
        lines.append("- Model: `\(escape(run.modelConfiguration.target.modelID))`") // Records exact provider model identity.
        lines.append("- Backend: `\(run.modelConfiguration.target.backendID.rawValue)`") // Records exact backend identity.
        lines.append("- Suite version: \(run.suiteVersion)") // Records suite comparability version.
        lines.append("- Cases: \(run.caseIDs.count), repetitions: \(run.modelConfiguration.runsPerCase)") // Records selection size.
        lines.append("") // Separates summary.
        lines.append("## Scores") // Starts score section.
        lines.append("") // Separates heading and table.
        lines.append("| Dimension | Score |") // Writes table heading.
        lines.append("|---|---:|") // Writes table alignment.
        if let summary = run.summary { // Emits only calculated dimensions.
            lines.append("| Overall | \(format(summary.overallScore)) |") // Writes weighted overall.
            lines.append("| Quality | \(format(summary.qualityScore)) |") // Writes quality or N/A.
            lines.append("| Reliability | \(format(summary.reliabilityScore)) |") // Writes reliability or N/A.
            lines.append("| Tool Use | \(format(summary.toolUseScore)) |") // Writes tool score or N/A.
            lines.append("| Engineering | \(format(summary.engineeringScore)) |") // Writes engineering or N/A.
            lines.append("| Performance | \(format(summary.performanceScore)) |") // Writes modest performance score or N/A.
        } else { lines.append("| Overall | N/A |") } // Preserves absence of summary honestly.
        lines.append("") // Separates case details.
        lines.append("## Cases") // Starts case table.
        lines.append("") // Separates heading and table.
        lines.append("| Case | Category | Repetition | Status | Score | Latency (ms) | Error |") // Writes inspectable case columns.
        lines.append("|---|---|---:|---|---:|---:|---|") // Writes table alignment.
        for result in run.results { // Emits every completed repetition in order.
            lines.append("| \(escape(result.caseName)) | \(result.category.displayName) | \(result.repetition) | \(result.status.rawValue) | \(format(result.score)) | \(result.timing.totalDurationMilliseconds) | \(escape(result.errorKind?.rawValue ?? "—")) |") // Writes one bounded evidence row.
        } // Ends case table generation.
        lines.append("") // Ends the document cleanly.
        lines.append("> TTFT and token-derived metrics are reported only when the selected backend provides them. Tool calls are graded but never executed by the benchmark harness.") // Discloses truthful measurement and security boundary.
        lines.append("") // Supplies final newline.
        return lines.joined(separator: "\n") // Returns deterministic Markdown.
    } // Ends Markdown result export.

    static func write(run: BenchmarkRun, to directory: URL, fileManager: FileManager = .default) throws -> (json: URL, markdown: URL) { // Writes both requested result formats atomically.
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) // Creates only the caller-selected output directory.
        let stem = "benchmark-\(run.id.uuidString.lowercased())" // Builds a collision-safe stable filename.
        let jsonURL = directory.appendingPathComponent(stem).appendingPathExtension("json") // Resolves JSON artifact path.
        let markdownURL = directory.appendingPathComponent(stem).appendingPathExtension("md") // Resolves Markdown artifact path.
        try jsonData(for: run).write(to: jsonURL, options: [.atomic]) // Writes versioned JSON atomically.
        try Data(markdown(for: run).utf8).write(to: markdownURL, options: [.atomic]) // Writes Markdown atomically.
        return (jsonURL, markdownURL) // Returns both concrete artifact URLs.
    } // Ends dual-format result writing.

    private static func format(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "N/A" } // Formats optional scores honestly.
    private static func format(_ value: Double) -> String { String(format: "%.2f", value) } // Formats required scores consistently.
    private static func escape(_ value: String) -> String { value.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") } // Prevents response text from breaking Markdown tables.
} // Ends benchmark report exporter.
