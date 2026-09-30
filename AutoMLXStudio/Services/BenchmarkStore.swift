import Foundation // Supplies versioned JSON persistence, safe atomic writes, and local file URLs.

struct BenchmarkStoreLoad<Value: Sendable>: Sendable { // Returns valid records together with isolated corruption diagnostics.
    let values: [Value] // Stores every independently decoded valid record.
    let issues: [String] // Stores bounded filenames and reasons for skipped records.
} // Ends storage load result.

private struct BenchmarkStoreEnvelope<Value: Codable & Sendable>: Codable, Sendable { // Wraps each independent record with an explicit migration boundary.
    let schemaVersion: Int // Stores persistence schema independently from suite revision.
    let payload: Value // Stores one run or custom suite snapshot.
} // Ends versioned storage envelope.

actor BenchmarkStore { // Serializes benchmark persistence and prevents one corrupt record from blocking history.
    static let schemaVersion = 1 // Declares the only V0.6.1 persistence schema.
    static let maximumImportBytes = BenchmarkSuiteValidator.maximumImportBytes // Reuses the fixed two-mebibyte import limit.
    let rootURL: URL // Stores an injectable local root for production and isolated tests.
    private let fileManager: FileManager // Stores an injectable filesystem authority.

    init(rootURL: URL? = nil, fileManager: FileManager = .default) { // Creates production Application Support storage or an isolated test store.
        self.fileManager = fileManager // Stores filesystem dependency.
        if let rootURL { self.rootURL = rootURL } // Uses an explicitly isolated directory when supplied.
        else { // Resolves the app-owned production directory.
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] // Finds the current user's Application Support directory.
            self.rootURL = support.appendingPathComponent("AutoMLXStudio/Benchmarks/v1", isDirectory: true) // Names the versioned benchmark namespace.
        } // Ends storage-root selection.
    } // Ends benchmark store construction.

    func loadRuns() -> BenchmarkStoreLoad<BenchmarkRun> { // Loads each run independently in newest-first order.
        load(BenchmarkRun.self, from: runsURL) // Delegates isolated record decoding.
    } // Ends run loading.

    func loadCustomSuites() -> BenchmarkStoreLoad<BenchmarkSuite> { // Loads independently persisted editable suites.
        let loaded = load(BenchmarkSuite.self, from: suitesURL) // Decodes every versioned suite record independently.
        let valid = loaded.values.filter { !$0.isBuiltIn } // Rejects a crafted stored suite that attempts built-in authority.
        let rejected = loaded.values.count - valid.count // Counts invalid built-in claims.
        let issues = rejected > 0 ? loaded.issues + ["Skipped \(rejected) stored suite record(s) that claimed built-in identity."] : loaded.issues // Reports the bounded rejection.
        return BenchmarkStoreLoad(values: valid.sorted { $0.updatedAt > $1.updatedAt }, issues: issues) // Returns editable suites newest first.
    } // Ends custom-suite loading.

    func save(run: BenchmarkRun) throws { // Atomically persists one complete or in-progress run record.
        try save(run, id: run.id, in: runsURL) // Uses stable identity for overwrite-safe progress checkpoints.
    } // Ends run persistence.

    func save(suite: BenchmarkSuite) throws { // Atomically persists one validated editable suite.
        try BenchmarkSuiteValidator.validate(suite, permitsBuiltIn: false) // Protects built-in immutability and rejects malformed imports.
        try save(suite, id: suite.id, in: suitesURL) // Writes one independent suite record.
    } // Ends custom-suite persistence.

    func deleteRun(id: UUID) throws { // Deletes exactly one selected history record.
        let url = recordURL(id: id, directory: runsURL) // Resolves a literal app-owned target.
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) } // Removes only the exact selected file.
    } // Ends run deletion.

    func deleteSuite(id: UUID) throws { // Deletes exactly one selected editable suite.
        let url = recordURL(id: id, directory: suitesURL) // Resolves a literal app-owned target.
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) } // Removes only the exact selected file.
    } // Ends custom-suite deletion.

    func importPreview(data: Data) throws -> BenchmarkSuite { // Decodes and validates untrusted declarative JSON without persisting it.
        guard data.count <= Self.maximumImportBytes else { throw BenchmarkValidationError.importTooLarge } // Bounds memory and disk inputs.
        let decoder = configuredDecoder() // Uses the canonical timestamp strategy.
        let decoded: BenchmarkSuite // Holds either an exported envelope payload or raw suite JSON.
        if let envelope = try? decoder.decode(BenchmarkStoreEnvelope<BenchmarkSuite>.self, from: data) { // Accepts the canonical versioned export.
            guard envelope.schemaVersion == Self.schemaVersion else { throw BenchmarkValidationError.unsupportedSchemaVersion(envelope.schemaVersion) } // Rejects unknown migrations explicitly.
            decoded = envelope.payload // Extracts declarative payload.
        } else { decoded = try decoder.decode(BenchmarkSuite.self, from: data) } // Supports a plain suite document for interoperability.
        guard !decoded.isBuiltIn else { throw BenchmarkValidationError.builtInMutation } // Prevents imported data from claiming shipped immutability.
        try BenchmarkSuiteValidator.validate(decoded, permitsBuiltIn: false) // Rejects invalid graders, timeouts, identifiers, and empty cases.
        return decoded // Returns preview only; caller must explicitly save.
    } // Ends safe import preview.

    func suiteExportData(_ suite: BenchmarkSuite) throws -> Data { // Produces deterministic versioned JSON for built-in copies or custom suites.
        try BenchmarkSuiteValidator.validate(suite) // Validates the complete outgoing snapshot.
        return try configuredEncoder().encode(BenchmarkStoreEnvelope(schemaVersion: Self.schemaVersion, payload: suite)) // Encodes sorted pretty JSON with explicit schema.
    } // Ends suite export.

    private var runsURL: URL { rootURL.appendingPathComponent("runs", isDirectory: true) } // Names independent run records.
    private var suitesURL: URL { rootURL.appendingPathComponent("suites", isDirectory: true) } // Names independent custom-suite records.

    private func save<Value: Codable & Sendable>(_ value: Value, id: UUID, in directory: URL) throws { // Writes one versioned record atomically.
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) // Creates only the app-owned versioned namespace.
        let data = try configuredEncoder().encode(BenchmarkStoreEnvelope(schemaVersion: Self.schemaVersion, payload: value)) // Encodes canonical versioned JSON.
        try data.write(to: recordURL(id: id, directory: directory), options: [.atomic]) // Replaces one record through an atomic temporary file.
    } // Ends generic atomic save.

    private func load<Value: Codable & Sendable>(_ type: Value.Type, from directory: URL) -> BenchmarkStoreLoad<Value> { // Isolates decode failure per file.
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return BenchmarkStoreLoad(values: [], issues: []) } // Treats missing first-launch directories as empty.
        var values: [Value] = [] // Collects valid records.
        var issues: [String] = [] // Collects bounded corruption reports.
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) { // Reads only JSON records in stable order.
            do { // Decodes one record independently.
                let data = try Data(contentsOf: file, options: [.mappedIfSafe]) // Reads the selected record without scanning other content.
                let envelope = try configuredDecoder().decode(BenchmarkStoreEnvelope<Value>.self, from: data) // Decodes the versioned envelope.
                guard envelope.schemaVersion == Self.schemaVersion else { throw BenchmarkValidationError.unsupportedSchemaVersion(envelope.schemaVersion) } // Rejects unknown schema locally.
                values.append(envelope.payload) // Preserves the valid payload.
            } catch { issues.append("\(file.lastPathComponent): \(String(error.localizedDescription.prefix(256)))") } // Skips only the corrupt record and reports a bounded reason.
        } // Ends independent record loading.
        return BenchmarkStoreLoad(values: values, issues: issues) // Returns valid values even when issues exist.
    } // Ends generic isolated loading.

    private func recordURL(id: UUID, directory: URL) -> URL { directory.appendingPathComponent(id.uuidString.lowercased()).appendingPathExtension("json") } // Resolves one literal identity-based filename.

    private func configuredEncoder() -> JSONEncoder { // Creates canonical deterministic JSON output.
        let encoder = JSONEncoder() // Allocates a fresh thread-confined encoder.
        encoder.dateEncodingStrategy = .iso8601 // Uses human-readable stable timestamps.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] // Makes exports inspectable and stable.
        return encoder // Returns configured encoder.
    } // Ends encoder construction.

    private func configuredDecoder() -> JSONDecoder { // Creates the matching versioned JSON decoder.
        let decoder = JSONDecoder() // Allocates a fresh thread-confined decoder.
        decoder.dateDecodingStrategy = .iso8601 // Matches canonical persisted timestamps.
        return decoder // Returns configured decoder.
    } // Ends decoder construction.
} // Ends versioned benchmark store.
