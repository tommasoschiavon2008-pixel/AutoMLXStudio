import Foundation // Supplies local filesystem persistence, Codable JSON, deterministic text processing, and cancellation checks.

private enum MemoryStableIdentifier { // Produces deterministic UUIDs for chunks and recoverable catalog issues.
    static func uuid(seed: String) -> UUID { // Derives one stable UUID-shaped value from a SHA-256 digest.
        let digest = MemoryFingerprint.sha256(seed) // Computes a stable lowercase hexadecimal digest.
        let value = "\(digest.prefix(8))-\(digest.dropFirst(8).prefix(4))-\(digest.dropFirst(12).prefix(4))-\(digest.dropFirst(16).prefix(4))-\(digest.dropFirst(20).prefix(12))" // Formats the first 128 digest bits as a UUID string.
        return UUID(uuidString: value) ?? UUID() // Uses the deterministic value and retains a defensive fallback for impossible formatting failure.
    } // Ends stable UUID derivation.
} // Ends deterministic identifier support.

struct MemoryChunker: Sendable { // Splits normalized text into stable character windows with explicit overlap and source offsets.
    let maximumCharacters: Int // Stores the largest approximate token-independent chunk width.
    let overlapCharacters: Int // Stores the repeated source context between adjacent chunks.

    init(maximumCharacters: Int = 1_600, overlapCharacters: Int = 200) { // Creates a conservative default suitable for source code and prose.
        self.maximumCharacters = max(16, maximumCharacters) // Prevents unusably tiny or non-positive chunks.
        self.overlapCharacters = max(0, min(overlapCharacters, max(16, maximumCharacters) - 1)) // Guarantees forward progress while retaining requested context.
    } // Ends chunker configuration.

    func chunks(documentID: UUID, projectID: UUID, text: String) -> [MemoryChunk] { // Produces deterministic boundaries and identities for normalized document text.
        let characters = Array(text) // Uses character offsets so stored ranges match user-visible text rather than UTF-8 bytes.
        guard !characters.isEmpty else { return [] } // Returns no artificial chunks for empty text.
        var results: [MemoryChunk] = [] // Accumulates windows in stable source order.
        var start = 0 // Tracks the inclusive start of the next source window.
        while start < characters.count { // Continues until every source character has been covered.
            let hardEnd = min(start + maximumCharacters, characters.count) // Applies the configured hard upper bound.
            let end = preferredBoundary(in: characters, start: start, hardEnd: hardEnd) // Prefers a nearby line or word boundary without exceeding the limit.
            let raw = String(characters[start..<end]) // Extracts the exact normalized source window.
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines) // Removes only boundary whitespace from stored retrieval text.
            if !value.isEmpty { // Avoids creating meaningless whitespace-only chunks.
                let index = results.count // Captures stable source order for identity and retrieval metadata.
                let identitySeed = "\(documentID.uuidString)|\(index)|\(start)|\(end)|\(MemoryFingerprint.sha256(value))" // Includes ownership, position, and exact contents in the stable identity.
                results.append(MemoryChunk(id: MemoryStableIdentifier.uuid(seed: identitySeed), documentID: documentID, projectID: projectID, text: value, index: index, characterStart: start, characterEnd: end)) // Stores text, order, exact source offsets, and deterministic identity together.
            } // Ends non-empty chunk creation.
            guard end < characters.count else { break } // Stops after the terminal source window.
            start = max(start + 1, end - overlapCharacters) // Repeats bounded context while guaranteeing forward progress.
        } // Ends deterministic source-window iteration.
        return results // Returns chunks in original document order.
    } // Ends deterministic document chunking.

    private func preferredBoundary(in characters: [Character], start: Int, hardEnd: Int) -> Int { // Selects a stable natural boundary near the maximum size.
        guard hardEnd < characters.count else { return hardEnd } // Uses the document end for the final chunk.
        let minimumUsefulEnd = start + max(8, maximumCharacters / 2) // Avoids excessively short chunks caused by an early newline.
        guard minimumUsefulEnd < hardEnd else { return hardEnd } // Uses the hard bound when no useful search window exists.
        if let newline = stride(from: hardEnd - 1, through: minimumUsefulEnd, by: -1).first(where: { characters[$0].isNewline }) { return newline + 1 } // Prefers the last line boundary in the useful range.
        if let whitespace = stride(from: hardEnd - 1, through: minimumUsefulEnd, by: -1).first(where: { characters[$0].isWhitespace }) { return whitespace + 1 } // Falls back to the last word boundary.
        return hardEnd // Splits a long uninterrupted token only at the configured hard limit.
    } // Ends preferred-boundary selection.
} // Ends deterministic character chunking.

struct ExtractedMemoryDocument: Equatable, Sendable { // Carries validated local file text and real source metadata into durable storage.
    let title: String // Stores the filename-derived visible title.
    let sourceURL: URL // Stores the actual selected local source reference.
    let normalizedText: String // Stores decoded and normalized UTF-8 text.
    let contentFingerprint: String // Stores the normalized-content SHA-256 digest.
    let sourceByteCount: UInt64 // Stores the actual validated regular-file size.
    let sourceModificationDate: Date? // Stores actual modification time when available.
    let sourceFileExtension: String // Stores the validated lowercase extension.
} // Ends validated ingestion output.

struct MemoryDocumentIngestor: Sendable { // Validates and extracts a deliberately bounded set of local text and source-code formats.
    static let supportedExtensions: Set<String> = ["txt", "md", "swift", "py", "js", "ts", "cs", "cpp", "c", "h", "hpp", "java", "json", "yaml", "yml", "xml", "html", "css"] // Defines the explicit offline ingestion allowlist.
    let maximumBytes: UInt64 // Stores the maximum file size read into memory in one operation.

    init(maximumBytes: UInt64 = 8 * 1_024 * 1_024) { // Creates a bounded default appropriate for local memory.
        self.maximumBytes = maximumBytes // Stores the explicit ingestion limit.
    } // Ends ingestor configuration.

    func extract(from url: URL) throws -> ExtractedMemoryDocument { // Validates one selected file and decodes UTF-8 text without OCR or network access.
        try Task.checkCancellation() // Stops before filesystem work when the importing task was cancelled.
        let source = url.standardizedFileURL // Normalizes the local reference before validation and persistence.
        let fileExtension = source.pathExtension.lowercased() // Resolves a case-insensitive allowlist key.
        guard Self.supportedExtensions.contains(fileExtension) else { throw ProjectMemoryError.unsupportedFileType(fileExtension.isEmpty ? "no extension" : ".\(fileExtension)") } // Rejects unsupported and PDF/OCR inputs explicitly.
        let didAccessSecurityScope = source.startAccessingSecurityScopedResource() // Opens user-granted sandbox scope when required and harmlessly returns false in ordinary non-sandbox builds.
        defer { if didAccessSecurityScope { source.stopAccessingSecurityScopedResource() } } // Releases only scope opened for this bounded import operation.
        let values: URLResourceValues // Declares regular-file, size, and modification evidence.
        do { values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) } // Reads actual metadata before allocating source contents.
        catch { throw ProjectMemoryError.fileUnavailable(Self.bounded(error.localizedDescription)) } // Converts metadata failure into a bounded domain error.
        guard values.isRegularFile == true else { throw ProjectMemoryError.fileUnavailable("the selected path is not a regular file.") } // Rejects directories and special files.
        let byteCount = UInt64(max(0, values.fileSize ?? 0)) // Converts actual filesystem size safely.
        guard byteCount > 0 else { throw ProjectMemoryError.emptyDocument } // Rejects empty files before allocation.
        guard byteCount <= maximumBytes else { throw ProjectMemoryError.fileUnavailable("file size \(byteCount) bytes exceeds the \(maximumBytes)-byte limit.") } // Bounds memory use deterministically.
        try Task.checkCancellation() // Allows cancellation after validation and before reading source bytes.
        let data: Data // Declares the local source bytes.
        do { data = try Data(contentsOf: source, options: [.mappedIfSafe]) } // Reads only the explicitly selected bounded local file.
        catch { throw ProjectMemoryError.fileUnavailable(Self.bounded(error.localizedDescription)) } // Reports read failure without exposing unrelated contents.
        try Task.checkCancellation() // Allows cancellation before UTF-8 decoding, normalization, and hashing.
        guard let decoded = String(data: data, encoding: .utf8) else { throw ProjectMemoryError.fileUnavailable("the file is not valid UTF-8 text.") } // Keeps initial extraction reliable and debuggable.
        let normalized = Self.normalize(decoded) // Normalizes line endings and excessive blank space without altering code indentation.
        guard !normalized.isEmpty else { throw ProjectMemoryError.emptyDocument } // Rejects whitespace-only decoded documents.
        let fingerprint = MemoryFingerprint.sha256(normalized) // Computes deterministic duplicate identity after normalization.
        return ExtractedMemoryDocument(title: source.deletingPathExtension().lastPathComponent, sourceURL: source, normalizedText: normalized, contentFingerprint: fingerprint, sourceByteCount: byteCount, sourceModificationDate: values.contentModificationDate, sourceFileExtension: fileExtension) // Returns only actual validated source metadata and text.
    } // Ends local text extraction.

    static func normalize(_ text: String) -> String { // Produces stable text for chunking while preserving meaningful indentation and line structure.
        let lineNormalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") // Converts platform line endings deterministically.
        let boundedBlankLines = lineNormalized.replacingOccurrences(of: "\n{4,}", with: "\n\n\n", options: .regularExpression) // Bounds empty vertical runs without collapsing normal paragraphs.
        return boundedBlankLines.trimmingCharacters(in: .whitespacesAndNewlines) // Removes only document-edge whitespace.
    } // Ends ingestion text normalization.

    private static func bounded(_ value: String) -> String { // Produces concise filesystem diagnostics safe for normal UI.
        String(value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(240)) // Flattens repeated whitespace and bounds output length.
    } // Ends bounded diagnostic formatting.
} // Ends deterministic local document ingestion.

private struct ProjectMemorySnapshot: Codable, Equatable, Sendable { // Stores one complete project and its isolated durable memory records.
    var schemaVersion: Int // Identifies the persistence schema decoded or written for this snapshot.
    var project: Project // Stores project metadata in the same atomic snapshot.
    var documents: [MemoryDocument] // Stores normalized project-owned documents in insertion order.
    var chunks: [MemoryChunk] // Stores deterministic project-owned chunks in document order.
    var vectors: [MemoryVectorRecord] // Stores optional actual embedding records for installed runtimes.
    var indexIssue: String? // Stores recoverable vector-index validation state without invalidating readable source memory.

    init(project: Project, documents: [MemoryDocument], chunks: [MemoryChunk], vectors: [MemoryVectorRecord], indexIssue: String? = nil) { // Creates a current-version complete snapshot.
        self.schemaVersion = ProjectMemorySchema.currentVersion // Writes the current explicit schema version.
        self.project = project // Stores durable project metadata.
        self.documents = documents // Stores project-owned documents.
        self.chunks = chunks // Stores deterministic project-owned chunks.
        self.vectors = vectors // Stores validated vector records.
        self.indexIssue = indexIssue // Stores an optional recoverable index diagnostic.
    } // Ends current snapshot construction.

    private enum CodingKeys: String, CodingKey { // Defines current keys and migration support for unversioned V0.4 snapshots.
        case schemaVersion // Persists the explicit schema number.
        case project // Persists project metadata.
        case documents // Persists normalized sources.
        case chunks // Persists deterministic windows.
        case vectors // Persists actual vectors.
        case indexIssue // Persists recoverable index state.
    } // Ends snapshot coding keys.

    init(from decoder: Decoder) throws { // Decodes current snapshots and migrates the unversioned V0.4 Foundation format.
        let container = try decoder.container(keyedBy: CodingKeys.self) // Opens the keyed snapshot payload.
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1 // Treats the original unversioned foundation snapshot as schema 1.
        project = try container.decode(Project.self, forKey: .project) // Restores durable project metadata.
        documents = try container.decode([MemoryDocument].self, forKey: .documents) // Restores documents using their own migration decoder.
        chunks = try container.decode([MemoryChunk].self, forKey: .chunks) // Restores original or deterministic chunks.
        vectors = try container.decode([MemoryVectorRecord].self, forKey: .vectors) // Restores optional actual vectors.
        indexIssue = try container.decodeIfPresent(String.self, forKey: .indexIssue) // Restores optional recoverable index state.
    } // Ends snapshot migration decoding.
} // Ends one-project persistence snapshot.

actor ProjectMemoryStore { // Owns atomic project-scoped JSON persistence independently from chat history and model processes.
    static let maximumProjectNameCharacters = 80 // Defines a concise visible name limit shared by storage and UI validation.
    private let rootURL: URL // Stores the exact app-owned persistence directory.
    private let encoder: JSONEncoder // Stores one consistently configured atomic snapshot encoder.
    private let decoder: JSONDecoder // Stores one consistently configured snapshot decoder.

    init(rootURL: URL? = nil) { // Creates a store at an injectable test root or the app's Application Support directory.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] // Resolves the user-scoped durable application root.
        self.rootURL = (rootURL ?? base.appendingPathComponent("AutoMLXStudio/ProjectMemory", isDirectory: true)).standardizedFileURL // Uses a dedicated normalized app-owned subdirectory.
        self.encoder = JSONEncoder() // Creates the durable JSON encoder.
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys] // Keeps snapshots deterministic and easy to inspect.
        self.encoder.dateEncodingStrategy = .iso8601 // Stores stable human-readable timestamps.
        self.decoder = JSONDecoder() // Creates the matching durable decoder.
        self.decoder.dateDecodingStrategy = .iso8601 // Restores the exact timestamp strategy.
    } // Ends store construction.

    func createProject(name: String, now: Date = Date()) throws -> Project { // Creates and atomically persists one empty local project.
        let normalizedName = try validatedProjectName(name) // Applies visible non-empty and length validation consistently.
        let project = Project(name: normalizedName, createdAt: now) // Creates durable project metadata with stable identity.
        try save(ProjectMemorySnapshot(project: project, documents: [], chunks: [], vectors: [])) // Persists the empty isolated snapshot before returning success.
        return project // Returns the exact persisted project.
    } // Ends project creation.

    func catalog() throws -> ProjectMemoryCatalog { // Lists readable projects while isolating corrupt app-owned snapshots.
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return ProjectMemoryCatalog(projects: [], issues: []) } // Treats a never-used store as an empty healthy catalog.
        let files: [URL] // Declares direct project snapshot files.
        do { files = try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) } // Reads only the dedicated app-owned directory.
        catch { throw ProjectMemoryError.persistenceFailed(Self.bounded(error.localizedDescription)) } // Reports bounded root-directory failure.
        var summaries: [ProjectMemorySummary] = [] // Collects independently validated readable projects.
        var issues: [ProjectStorageIssue] = [] // Collects corrupt files without aborting healthy project discovery.
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) { // Processes explicit snapshot files deterministically.
            do { summaries.append(summary(for: try load(from: file))) } // Decodes, validates, and summarizes one project independently.
            catch { issues.append(ProjectStorageIssue(id: MemoryStableIdentifier.uuid(seed: file.lastPathComponent), filename: file.lastPathComponent, detail: Self.bounded(error.localizedDescription))) } // Retains a bounded recoverable catalog diagnostic.
        } // Ends independent snapshot discovery.
        summaries.sort { lhs, rhs in lhs.project.updatedAt == rhs.project.updatedAt ? lhs.project.name.localizedCaseInsensitiveCompare(rhs.project.name) == .orderedAscending : lhs.project.updatedAt > rhs.project.updatedAt } // Orders recent activity first with stable name ties.
        return ProjectMemoryCatalog(projects: summaries, issues: issues) // Returns healthy projects and isolated issues together.
    } // Ends resilient project catalog discovery.

    func projects() throws -> [Project] { // Preserves the V0.4 list API while no longer allowing one corrupt snapshot to hide healthy projects.
        try catalog().projects.map(\.project) // Returns only validated readable projects in catalog order.
    } // Ends project listing.

    func summary(projectID: UUID) throws -> ProjectMemorySummary { // Returns current counts and index state for one exact project.
        summary(for: try snapshot(projectID: projectID)) // Loads and summarizes only the requested isolated snapshot.
    } // Ends individual project summary lookup.

    func renameProject(id: UUID, name: String, now: Date = Date()) throws -> Project { // Updates only project metadata inside its isolated snapshot.
        let normalizedName = try validatedProjectName(name) // Applies the same creation and rename rules.
        var snapshot = try snapshot(projectID: id) // Loads the exact project-owned state.
        snapshot.project.name = normalizedName // Stores the new visible name without changing UUID or memory relationships.
        snapshot.project.updatedAt = now // Records the actual metadata mutation time.
        try save(snapshot) // Atomically replaces only this project's app-owned snapshot.
        return snapshot.project // Returns persisted metadata.
    } // Ends project rename.

    func deleteProject(id: UUID) throws { // Deletes only the UUID-named app-owned snapshot and never follows source URLs.
        let target = try containedSnapshotURL(projectID: id) // Proves the exact target remains inside the configured app-owned root.
        guard FileManager.default.fileExists(atPath: target.path) else { throw ProjectMemoryError.projectNotFound(id) } // Distinguishes a missing project from successful deletion.
        do { try FileManager.default.removeItem(at: target) } // Removes only the exact project snapshot file.
        catch { throw ProjectMemoryError.persistenceFailed(Self.bounded(error.localizedDescription)) } // Reports bounded deletion failure.
    } // Ends contained project deletion.

    func addDocument(projectID: UUID, title: String, sourceURL: URL?, text: String, chunker: MemoryChunker = MemoryChunker(), now: Date = Date()) throws -> MemoryDocument { // Normalizes, fingerprints, chunks, and atomically stores direct text.
        let normalizedText = MemoryDocumentIngestor.normalize(text) // Applies the same deterministic normalization used by file imports.
        guard !normalizedText.isEmpty else { throw ProjectMemoryError.emptyDocument } // Rejects empty durable memory.
        let extractedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes visible source title.
        return try addPreparedDocument(projectID: projectID, title: extractedTitle.isEmpty ? "Untitled document" : extractedTitle, sourceURL: sourceURL?.standardizedFileURL, normalizedText: normalizedText, contentFingerprint: MemoryFingerprint.sha256(normalizedText), sourceByteCount: nil, sourceModificationDate: nil, sourceFileExtension: sourceURL?.pathExtension.lowercased(), chunker: chunker, now: now) // Commits direct text through the duplicate-safe shared path.
    } // Ends direct document storage.

    func addExtractedDocument(projectID: UUID, extracted: ExtractedMemoryDocument, chunker: MemoryChunker = MemoryChunker(), now: Date = Date()) throws -> MemoryDocument { // Stores already validated off-main-actor extraction results.
        try addPreparedDocument(projectID: projectID, title: extracted.title, sourceURL: extracted.sourceURL, normalizedText: extracted.normalizedText, contentFingerprint: extracted.contentFingerprint, sourceByteCount: extracted.sourceByteCount, sourceModificationDate: extracted.sourceModificationDate, sourceFileExtension: extracted.sourceFileExtension, chunker: chunker, now: now) // Commits actual source metadata and chunks atomically.
    } // Ends prepared file ingestion.

    func ingestFile(projectID: UUID, url: URL, ingestor: MemoryDocumentIngestor = MemoryDocumentIngestor(), chunker: MemoryChunker = MemoryChunker(), now: Date = Date()) throws -> MemoryDocument { // Preserves the V0.4 convenience ingestion API.
        let extracted = try ingestor.extract(from: url) // Validates, scopes, reads, normalizes, and fingerprints the selected source.
        return try addExtractedDocument(projectID: projectID, extracted: extracted, chunker: chunker, now: now) // Commits actual extracted source through the shared atomic path.
    } // Ends local file ingestion.

    func reindexDocument(projectID: UUID, documentID: UUID, extracted: ExtractedMemoryDocument, chunker: MemoryChunker = MemoryChunker(), now: Date = Date()) throws -> MemoryDocument { // Replaces one changed source without rebuilding unrelated project memory.
        var snapshot = try snapshot(projectID: projectID) // Loads only the destination project snapshot.
        guard let documentIndex = snapshot.documents.firstIndex(where: { $0.id == documentID }) else { throw ProjectMemoryError.documentNotFound(documentID) } // Requires exact project-owned document identity.
        if let duplicate = snapshot.documents.first(where: { $0.id != documentID && $0.contentFingerprint == extracted.contentFingerprint }) { throw ProjectMemoryError.duplicateDocument(duplicate.id, duplicate.title) } // Prevents reindex from duplicating another document.
        let previous = snapshot.documents[documentIndex] // Captures stable identity, title, and creation time.
        if previous.contentFingerprint == extracted.contentFingerprint { return previous } // Avoids chunk or vector churn when normalized contents are unchanged.
        let replacement = MemoryDocument(id: previous.id, title: previous.title, sourceURL: extracted.sourceURL, text: extracted.normalizedText, createdAt: previous.createdAt, updatedAt: now, projectID: projectID, contentFingerprint: extracted.contentFingerprint, sourceByteCount: extracted.sourceByteCount, sourceModificationDate: extracted.sourceModificationDate, sourceFileExtension: extracted.sourceFileExtension) // Preserves document identity and user-visible title while updating actual source facts.
        let replacementChunks = chunker.chunks(documentID: documentID, projectID: projectID, text: extracted.normalizedText) // Produces deterministic new windows for only the affected document.
        guard !replacementChunks.isEmpty else { throw ProjectMemoryError.emptyDocument } // Prevents a document without retrievable context.
        let replacementMap = Dictionary(uniqueKeysWithValues: replacementChunks.map { ($0.id, $0.contentFingerprint) }) // Builds exact new chunk compatibility metadata.
        snapshot.documents[documentIndex] = replacement // Replaces only the affected document metadata.
        snapshot.chunks.removeAll { $0.documentID == documentID } // Removes only old chunks for the affected document.
        snapshot.chunks.append(contentsOf: replacementChunks) // Adds replacement chunks without touching other documents.
        snapshot.vectors.removeAll { record in guard let fingerprint = record.chunkFingerprint, let replacementFingerprint = replacementMap[record.chunkID] else { return snapshot.chunks.first(where: { $0.id == record.chunkID }) == nil }; return fingerprint != replacementFingerprint } // Retains only vectors still proven to match an unchanged deterministic chunk.
        snapshot.indexIssue = nil // Clears an older vector issue because incompatible affected records were removed.
        snapshot.project.updatedAt = now // Records the memory mutation time.
        try save(snapshot) // Atomically persists document, chunks, retained vectors, and metadata together.
        return replacement // Returns the exact persisted replacement document.
    } // Ends incremental document reindexing.

    func removeDocument(projectID: UUID, documentID: UUID, now: Date = Date()) throws { // Deletes only app-owned normalized memory, chunks, and vectors for one document.
        var snapshot = try snapshot(projectID: projectID) // Loads the exact isolated project state.
        guard snapshot.documents.contains(where: { $0.id == documentID }) else { throw ProjectMemoryError.documentNotFound(documentID) } // Rejects stale cross-project or unknown identities.
        let removedChunkIDs = Set(snapshot.chunks.filter { $0.documentID == documentID }.map(\.id)) // Captures exact vector references owned by the removed document.
        snapshot.documents.removeAll { $0.id == documentID } // Removes only the durable internal document copy.
        snapshot.chunks.removeAll { $0.documentID == documentID } // Removes only its deterministic chunks.
        snapshot.vectors.removeAll { removedChunkIDs.contains($0.chunkID) } // Removes only its vector sidecars.
        snapshot.project.updatedAt = now // Records the memory mutation time.
        snapshot.indexIssue = nil // Clears stale index diagnostics after referenced records are removed.
        try save(snapshot) // Atomically commits contained deletion without touching the original source URL.
    } // Ends document removal.

    func documents(projectID: UUID) throws -> [MemoryDocument] { // Returns only documents owned by the requested project.
        try snapshot(projectID: projectID).documents // Loads the isolated snapshot and returns its source records.
    } // Ends project document lookup.

    func chunks(projectID: UUID) throws -> [MemoryChunk] { // Returns only chunks owned by the requested project.
        try snapshot(projectID: projectID).chunks // Loads the isolated snapshot and returns its chunk records.
    } // Ends project chunk lookup.

    func vectors(projectID: UUID) throws -> [MemoryVectorRecord] { // Returns only validated vector records owned by the requested project.
        try snapshot(projectID: projectID).vectors // Loads the isolated snapshot and returns optional actual embeddings.
    } // Ends project vector lookup.

    func documentStatuses(projectID: UUID) throws -> [MemoryDocumentStatus] { // Computes source-change and index counts without reading complete external file contents.
        let snapshot = try snapshot(projectID: projectID) // Loads one consistent project transaction.
        return snapshot.documents.map { document in // Computes bounded status independently for each durable document.
            let sourceStatus = Self.sourceStatus(document) // Compares retained real metadata with current filesystem facts.
            let documentChunkIDs = Set(snapshot.chunks.filter { $0.documentID == document.id }.map(\.id)) // Resolves exact current chunk ownership.
            let vectorCount = snapshot.vectors.filter { documentChunkIDs.contains($0.chunkID) }.count // Counts only current references for this document.
            return MemoryDocumentStatus(documentID: document.id, sourceStatus: sourceStatus, chunkCount: documentChunkIDs.count, vectorCount: vectorCount) // Returns truthful per-document operational state.
        } // Ends status computation.
    } // Ends document status lookup.

    func replaceVectors(projectID: UUID, records: [MemoryVectorRecord], now: Date = Date()) throws { // Atomically replaces one project's vector sidecar after strict validation.
        var snapshot = try snapshot(projectID: projectID) // Loads the exact destination project.
        try validateVectorBatch(records, projectID: projectID, chunks: snapshot.chunks) // Rejects cross-project, orphan, non-finite, mixed, or stale records.
        snapshot.vectors = records // Stores only the validated actual vector batch.
        snapshot.indexIssue = nil // Clears a recoverable index issue after a successful explicit replacement.
        snapshot.project.updatedAt = now // Records the index mutation time.
        try save(snapshot) // Atomically persists the new sidecar with source memory.
    } // Ends vector sidecar replacement.

    func upsertVectors(projectID: UUID, records: [MemoryVectorRecord], now: Date = Date()) throws { // Adds or replaces only supplied current chunk vectors for incremental indexing.
        var snapshot = try snapshot(projectID: projectID) // Loads the exact destination project.
        try validateVectorBatch(records, projectID: projectID, chunks: snapshot.chunks) // Validates every new physical runtime result before mutation.
        if let modelID = records.first?.modelID, snapshot.vectors.contains(where: { $0.modelID != modelID }) { snapshot.vectors.removeAll() } // Marks a model change by removing incompatible prior-model vectors.
        let replacementIDs = Set(records.map(\.chunkID)) // Builds exact chunk identities supplied by the incremental batch.
        snapshot.vectors.removeAll { replacementIDs.contains($0.chunkID) } // Removes only records superseded by this batch.
        snapshot.vectors.append(contentsOf: records) // Adds validated actual vectors for new or changed chunks.
        snapshot.indexIssue = nil // Clears prior recoverable vector diagnostics.
        snapshot.project.updatedAt = now // Records the incremental index mutation.
        try save(snapshot) // Atomically persists the updated sidecar.
    } // Ends incremental vector upsert.

    func clearVectors(projectID: UUID, now: Date = Date()) throws { // Removes rebuildable vector state while preserving documents and lexical memory.
        var snapshot = try snapshot(projectID: projectID) // Loads the exact isolated project.
        snapshot.vectors = [] // Removes only app-owned rebuildable vector records.
        snapshot.indexIssue = nil // Clears degraded index state after explicit rebuild preparation.
        snapshot.project.updatedAt = now // Records the index mutation time.
        try save(snapshot) // Atomically commits the lexical-ready state.
    } // Ends vector-index clearing.

    func searchDocuments(projectID: UUID, query: String, limit: Int = 20) throws -> [MemorySearchResult] { // Supports manual lexical inspection without an LLM or embedding model.
        let snapshot = try snapshot(projectID: projectID) // Loads only the selected project's durable memory.
        return ProjectMemoryLexicalSearch.rank(query: query, chunks: snapshot.chunks, documents: snapshot.documents, limit: max(0, limit)) // Reuses deterministic project-isolated lexical ranking.
    } // Ends manual document search.

    private func addPreparedDocument(projectID: UUID, title: String, sourceURL: URL?, normalizedText: String, contentFingerprint: String, sourceByteCount: UInt64?, sourceModificationDate: Date?, sourceFileExtension: String?, chunker: MemoryChunker, now: Date) throws -> MemoryDocument { // Applies duplicate detection and one atomic source-plus-chunk transaction.
        var snapshot = try snapshot(projectID: projectID) // Loads only the destination project snapshot.
        if let duplicate = snapshot.documents.first(where: { $0.contentFingerprint == contentFingerprint }) { throw ProjectMemoryError.duplicateDocument(duplicate.id, duplicate.title) } // Prevents same normalized contents under another filename.
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes visible title edges.
        let document = MemoryDocument(title: normalizedTitle.isEmpty ? "Untitled document" : String(normalizedTitle.prefix(160)), sourceURL: sourceURL?.standardizedFileURL, text: normalizedText, createdAt: now, projectID: projectID, contentFingerprint: contentFingerprint, sourceByteCount: sourceByteCount, sourceModificationDate: sourceModificationDate, sourceFileExtension: sourceFileExtension) // Creates complete durable source metadata.
        let documentChunks = chunker.chunks(documentID: document.id, projectID: projectID, text: normalizedText) // Produces stable overlapped chunks before committing anything.
        guard !documentChunks.isEmpty else { throw ProjectMemoryError.emptyDocument } // Prevents a document without retrievable context.
        snapshot.documents.append(document) // Adds the new source in insertion order.
        snapshot.chunks.append(contentsOf: documentChunks) // Adds source-ordered chunks to the same transaction.
        snapshot.project.updatedAt = now // Records the memory mutation time.
        try save(snapshot) // Atomically persists document and chunks together.
        return document // Returns exact persisted document metadata.
    } // Ends prepared document storage.

    private func snapshot(projectID: UUID) throws -> ProjectMemorySnapshot { // Loads one exact isolated project snapshot.
        let url = try containedSnapshotURL(projectID: projectID) // Resolves and validates a UUID-only app-owned filename.
        guard FileManager.default.fileExists(atPath: url.path) else { throw ProjectMemoryError.projectNotFound(projectID) } // Distinguishes unknown project from corruption.
        return try load(from: url) // Decodes and validates the complete project transaction.
    } // Ends project snapshot lookup.

    private func load(from url: URL) throws -> ProjectMemorySnapshot { // Decodes one app-owned JSON snapshot with migration and isolation validation.
        let decoded: ProjectMemorySnapshot // Declares the decoded but not yet trusted snapshot.
        do { decoded = try decoder.decode(ProjectMemorySnapshot.self, from: Data(contentsOf: url)) } // Reads and decodes the exact snapshot.
        catch { throw ProjectMemoryError.persistenceFailed(Self.bounded(error.localizedDescription)) } // Reports JSON or filesystem failure honestly.
        guard decoded.schemaVersion <= ProjectMemorySchema.currentVersion else { throw ProjectMemoryError.unsupportedSchema(decoded.schemaVersion) } // Refuses to reinterpret a future incompatible schema.
        guard decoded.schemaVersion > 0 else { throw ProjectMemoryError.indexCorrupt("snapshot schema version must be positive.") } // Rejects invalid version metadata.
        guard decoded.documents.allSatisfy({ $0.projectID == decoded.project.id }) else { throw ProjectMemoryError.indexCorrupt("a document references a different project.") } // Enforces source isolation before exposing text.
        let documentIDs = Set(decoded.documents.map(\.id)) // Builds the only valid source reference set.
        guard documentIDs.count == decoded.documents.count else { throw ProjectMemoryError.indexCorrupt("duplicate document identifiers were found.") } // Rejects ambiguous source ownership.
        guard decoded.chunks.allSatisfy({ $0.projectID == decoded.project.id && documentIDs.contains($0.documentID) && !$0.text.isEmpty && $0.characterStart >= 0 && $0.characterEnd > $0.characterStart }) else { throw ProjectMemoryError.indexCorrupt("a chunk has invalid ownership, source, text, or offsets.") } // Enforces chunk isolation and shape.
        var migrated = decoded // Creates an in-memory migrated and recoverable copy.
        migrated.schemaVersion = ProjectMemorySchema.currentVersion // Marks the decoded representation as current for its next atomic save.
        do { try validateVectorBatch(migrated.vectors, projectID: migrated.project.id, chunks: migrated.chunks) } // Validates actual vectors separately from durable source memory.
        catch { migrated.vectors = []; migrated.indexIssue = Self.bounded(error.localizedDescription) } // Degrades safely to lexical memory when the rebuildable index is invalid.
        return migrated // Returns trusted source memory and only validated vector state.
    } // Ends snapshot decoding and migration.

    private func save(_ snapshot: ProjectMemorySnapshot) throws { // Atomically persists one complete isolated project snapshot.
        do { // Performs directory creation, encoding, and atomic replacement as one controlled operation.
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true) // Creates only the dedicated app-owned persistence root.
            var current = snapshot // Creates a mutable encoding value without changing caller state.
            current.schemaVersion = ProjectMemorySchema.currentVersion // Writes only the current explicit schema version.
            let data = try encoder.encode(current) // Encodes the complete transaction before writing.
            try data.write(to: containedSnapshotURL(projectID: snapshot.project.id), options: .atomic) // Replaces only the exact validated project file atomically.
        } catch let error as ProjectMemoryError { throw error } // Preserves typed store validation failures.
        catch { throw ProjectMemoryError.persistenceFailed(Self.bounded(error.localizedDescription)) } // Converts encoding and filesystem errors into bounded domain failures.
    } // Ends atomic snapshot persistence.

    private func containedSnapshotURL(projectID: UUID) throws -> URL { // Resolves a UUID-only filename and proves it remains inside the configured root.
        let candidate = rootURL.appendingPathComponent(projectID.uuidString.lowercased(), isDirectory: false).appendingPathExtension("json").standardizedFileURL // Uses no user-controlled path component.
        guard candidate.deletingLastPathComponent().standardizedFileURL == rootURL else { throw ProjectMemoryError.unsafeStorageTarget(candidate.path) } // Prevents accidental traversal or broad deletion.
        return candidate // Returns the exact containment-proven snapshot URL.
    } // Ends safe snapshot URL construction.

    private func validatedProjectName(_ value: String) throws -> String { // Applies one creation and rename validation policy.
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines) // Removes only surrounding whitespace.
        guard !normalized.isEmpty else { throw ProjectMemoryError.emptyProjectName } // Rejects invisible names.
        guard normalized.count <= Self.maximumProjectNameCharacters else { throw ProjectMemoryError.projectNameTooLong(Self.maximumProjectNameCharacters) } // Bounds sidebar and header copy.
        return normalized // Returns the exact persisted visible name.
    } // Ends project-name validation.

    private func validateVectorBatch(_ records: [MemoryVectorRecord], projectID: UUID, chunks: [MemoryChunk]) throws { // Validates one complete or incremental physical vector batch.
        let chunkMap = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) }) // Builds exact current chunk ownership and fingerprint data.
        let dimensions = Set(records.map(\.dimensions)) // Collects actual vector widths for consistency validation.
        let modelIDs = Set(records.map(\.modelID)) // Collects producing model identities for consistency validation.
        guard records.allSatisfy({ $0.projectID == projectID && chunkMap[$0.chunkID] != nil }) else { throw ProjectMemoryError.invalidVector("record references a different project or unknown chunk.") } // Rejects cross-project and orphan vectors.
        guard records.allSatisfy({ !$0.vector.isEmpty && $0.dimensions == $0.vector.count && $0.vector.allSatisfy(\.isFinite) }) else { throw ProjectMemoryError.invalidVector("vectors must be non-empty, finite, and dimensionally consistent.") } // Rejects empty, non-finite, or contradictory data.
        guard records.isEmpty || (dimensions.count == 1 && modelIDs.count == 1) else { throw ProjectMemoryError.invalidVector("one sidecar batch must use one dimension and one model ID.") } // Prevents incomparable vectors in one index.
        guard records.allSatisfy({ record in guard let fingerprint = record.chunkFingerprint else { return true }; return chunkMap[record.chunkID]?.contentFingerprint == fingerprint }) else { throw ProjectMemoryError.invalidVector("a vector fingerprint no longer matches its chunk.") } // Rejects explicitly stale records while allowing migration of legacy tests and snapshots.
    } // Ends vector validation.

    private func summary(for snapshot: ProjectMemorySnapshot) -> ProjectMemorySummary { // Produces truthful bounded catalog metadata from one validated snapshot.
        let status: MemoryIndexStatus // Declares actual retrieval readiness.
        if snapshot.indexIssue != nil { status = .degraded } // Preserves recoverable invalid-vector evidence.
        else if snapshot.chunks.isEmpty { status = .empty } // Reports no retrievable memory.
        else if snapshot.vectors.isEmpty { status = .lexicalReady } // Reports useful zero-model lexical retrieval.
        else { // Determines whether every current chunk has one compatible physical vector.
            let vectorMap = Dictionary(grouping: snapshot.vectors, by: \.chunkID) // Groups vector records by current chunk identity.
            let complete = snapshot.chunks.allSatisfy { chunk in vectorMap[chunk.id]?.contains(where: { $0.chunkFingerprint == chunk.contentFingerprint }) == true } // Requires an explicit fingerprint match for current-version embedding readiness.
            status = complete ? .embeddingReady : .stale // Distinguishes complete physical index from rebuild-needed state.
        } // Ends vector readiness selection.
        return ProjectMemorySummary(project: snapshot.project, documentCount: snapshot.documents.count, chunkCount: snapshot.chunks.count, vectorCount: snapshot.vectors.count, indexStatus: status) // Returns compact project metrics.
    } // Ends project summary construction.

    private static func sourceStatus(_ document: MemoryDocument) -> MemorySourceStatus { // Compares retained source facts without overwriting durable memory automatically.
        guard let source = document.sourceURL else { return .internalOnly } // Distinguishes direct/internal text from an unavailable external file.
        let values: URLResourceValues // Declares current regular-file metadata.
        do { values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) } // Reads bounded metadata only.
        catch { return .unavailable } // Reports inaccessible retained sources without deleting their internal text.
        guard values.isRegularFile == true else { return .unavailable } // Rejects removed, replaced-by-directory, or special paths.
        guard document.sourceByteCount != nil || document.sourceModificationDate != nil else { return .untracked } // Avoids claiming migrated sources are current without a historical baseline.
        if let expectedSize = document.sourceByteCount, UInt64(max(0, values.fileSize ?? 0)) != expectedSize { return .modifiedExternally } // Detects actual source-size changes.
        if let expectedDate = document.sourceModificationDate, let currentDate = values.contentModificationDate, abs(currentDate.timeIntervalSince(expectedDate)) > 0.5 { return .modifiedExternally } // Detects meaningful source timestamp changes.
        return .current // Reports current only when all retained comparison facts still match.
    } // Ends source-change detection.

    private static func bounded(_ value: String) -> String { // Produces compact persistence diagnostics.
        String(value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(240)) // Flattens repeated whitespace and bounds output.
    } // Ends persistence error bounding.
} // Ends durable project-scoped memory store.

enum ProjectMemoryLexicalSearch { // Provides deterministic project-isolated lexical ranking for retrieval and manual inspection.
    static func rank(query: String, chunks: [MemoryChunk], documents: [MemoryDocument], limit: Int) -> [MemorySearchResult] { // Scores bounded candidates without any model runtime.
        guard limit > 0 else { return [] } // Returns no work for an explicit zero result limit.
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes only visible query edges.
        let queryTerms = terms(normalizedQuery) // Tokenizes the current user query deterministically.
        guard !queryTerms.isEmpty else { return [] } // Avoids meaningless matches for punctuation or empty input.
        let documentMap = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) }) // Builds exact source metadata joins.
        return chunks.compactMap { chunk -> MemorySearchResult? in // Scores every supplied project-owned chunk exactly once.
            guard let document = documentMap[chunk.documentID] else { return nil } // Ignores impossible stale joins without crossing projects.
            let chunkTerms = terms(chunk.text) // Tokenizes normalized chunk contents.
            let overlap = queryTerms.intersection(chunkTerms).count // Counts unique actual query-term matches.
            guard overlap > 0 else { return nil } // Excludes chunks with no lexical evidence.
            let phraseBonus: Float = chunk.text.localizedCaseInsensitiveContains(normalizedQuery) ? 0.25 : 0 // Rewards an actual complete query phrase conservatively.
            let score = Float(overlap) / Float(max(1, queryTerms.count)) + phraseBonus // Produces a simple debuggable relevance score.
            return MemorySearchResult(chunk: chunk, document: document, score: score) // Returns real source metadata with lexical score.
        }.sorted { lhs, rhs in // Applies deterministic descending relevance and stable cross-document ties.
            if lhs.score != rhs.score { return lhs.score > rhs.score } // Ranks stronger lexical evidence first.
            if lhs.document.id != rhs.document.id { return lhs.document.id.uuidString < rhs.document.id.uuidString } // Stabilizes equal scores across documents.
            return lhs.chunk.index < rhs.chunk.index // Preserves source order within one document.
        }.prefix(limit).map { $0 } // Returns the requested bounded result set.
    } // Ends lexical ranking.

    static func terms(_ value: String) -> Set<String> { // Tokenizes prose and source code into stable lowercase alphanumeric terms.
        Set(value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 1 }) // Removes one-character noise while preserving identifiers and numbers.
    } // Ends deterministic lexical tokenization.
} // Ends reusable lexical search.
