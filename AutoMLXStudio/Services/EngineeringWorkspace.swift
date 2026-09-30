import CryptoKit // Supplies deterministic SHA-256 fingerprints for optimistic concurrency and rollback safety.
import Darwin // Supplies atomic hard-link publication for race-safe contained file creation.
import Foundation // Supplies bookmark persistence, canonical URLs, bounded file handles, JSON, and regular expressions.

actor EngineeringWorkspaceStore { // Persists only user-authorized workspace descriptors, separate from Project Memory.
    private let catalogURL: URL // Identifies the exact app-owned JSON catalog file.
    private let fileManager: FileManager // Supplies injectable filesystem behavior for deterministic tests.
    private var descriptors: [EngineeringWorkspaceDescriptor] // Caches the decoded durable catalog in actor isolation.

    init(catalogURL: URL? = nil, fileManager: FileManager = .default) { // Creates a descriptor store at an explicit or application-support location.
        self.fileManager = fileManager // Retains the filesystem dependency.
        if let catalogURL { // Uses an isolated location when a caller or test supplies one.
            self.catalogURL = catalogURL.standardizedFileURL // Normalizes the exact persistence target.
        } else { // Derives a stable application-support location for normal app launches.
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory // Falls back safely if application support discovery fails.
            self.catalogURL = support.appendingPathComponent("AutoMLXStudio/Engineering/workspaces.json", isDirectory: false) // Keeps Engineering Workspace metadata separate from memory snapshots.
        } // Ends catalog location selection.
        self.descriptors = Self.loadCatalog(at: self.catalogURL, fileManager: fileManager) // Isolates a missing or malformed catalog as an empty recoverable list.
    } // Ends workspace-store construction.

    func all() -> [EngineeringWorkspaceDescriptor] { // Returns deterministic most-recently-opened workspace descriptors.
        descriptors.sorted { lhs, rhs in // Sorts without mutating durable identity or authorization data.
            if lhs.lastOpenedAt != rhs.lastOpenedAt { return lhs.lastOpenedAt > rhs.lastOpenedAt } // Places the latest successful workspace first.
            return lhs.id.uuidString < rhs.id.uuidString // Stabilizes ties for repeatable UI and tests.
        } // Ends deterministic descriptor sorting.
    } // Ends catalog access.

    func authorize(directoryURL: URL, displayName: String? = nil, associatedProjectID: UUID? = nil, now: Date = Date()) throws -> EngineeringWorkspaceDescriptor { // Records an explicit folder-selection result.
        let canonicalURL = EngineeringPathCanonicalizer.existingURL(directoryURL) // Resolves filesystem aliases and symlinks before assigning the authority boundary.
        var isDirectory: ObjCBool = false // Receives filesystem directory metadata.
        guard fileManager.fileExists(atPath: canonicalURL.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw EngineeringRuntimeError.workspaceUnavailable(canonicalURL.path) } // Rejects missing or non-directory roots.
        let bookmark = try? canonicalURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) // Persists sandbox-compatible scope when macOS supplies one.
        let normalizedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes an optional user-entered display label.
        let descriptor = EngineeringWorkspaceDescriptor( // Creates one stable authorization record.
            id: UUID(), // Assigns a collision-resistant workspace identity.
            displayName: normalizedName?.isEmpty == false ? normalizedName! : canonicalURL.lastPathComponent, // Uses the selected folder name when no useful label was supplied.
            rootPath: canonicalURL.path, // Retains an unsandboxed-build fallback and user-visible root.
            securityScopedBookmark: bookmark, // Retains security scope without exposing it to model context.
            associatedProjectID: associatedProjectID, // Preserves only an optional conceptual link to Project Memory.
            createdAt: now, // Records authorization creation.
            lastOpenedAt: now // Records the initial successful access time.
        ) // Ends descriptor construction.
        descriptors.append(descriptor) // Adds the new authorization to the isolated catalog.
        try persist() // Durably commits the catalog before returning success.
        return descriptor // Returns the exact persisted descriptor.
    } // Ends explicit workspace authorization.

    func updateLastOpened(id: UUID, now: Date = Date()) throws -> EngineeringWorkspaceDescriptor { // Records successful reopening without broad catalog mutation.
        guard let index = descriptors.firstIndex(where: { $0.id == id }) else { throw EngineeringRuntimeError.workspaceUnavailable(id.uuidString) } // Requires an existing stable identity.
        descriptors[index].lastOpenedAt = now // Updates only recency metadata.
        try persist() // Atomically persists the new recency value.
        return descriptors[index] // Returns the exact updated descriptor.
    } // Ends workspace recency update.

    func remove(id: UUID) throws { // Removes only one descriptor and never deletes its external directory.
        descriptors.removeAll { $0.id == id } // Drops the exact catalog identity without following its root path.
        try persist() // Atomically persists descriptor removal.
    } // Ends non-destructive workspace catalog removal.

    static func resolveURL(for descriptor: EngineeringWorkspaceDescriptor) -> (url: URL, isStale: Bool, didStartSecurityScope: Bool) { // Resolves durable scope while retaining an unsandboxed fallback.
        if let bookmark = descriptor.securityScopedBookmark { // Prefers the persisted user authorization when available.
            var isStale = false // Receives macOS bookmark staleness information.
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) { // Resolves without inventing new authorization.
                let didStart = resolved.startAccessingSecurityScopedResource() // Activates scope for the workspace lifetime when sandboxing requires it.
                return (EngineeringPathCanonicalizer.existingURL(resolved), isStale, didStart) // Returns canonical authority and lifecycle evidence.
            } // Ends successful bookmark resolution handling.
        } // Ends bookmark-preferred path.
        return (EngineeringPathCanonicalizer.existingURL(URL(fileURLWithPath: descriptor.rootPath, isDirectory: true)), false, false) // Uses the persisted path only for the current unsandboxed configuration.
    } // Ends workspace authorization resolution.

    private func persist() throws { // Atomically writes the bounded descriptor catalog.
        let parentURL = catalogURL.deletingLastPathComponent() // Resolves the exact app-owned parent directory.
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true) // Creates only the catalog hierarchy.
        let encoder = JSONEncoder() // Creates a deterministic durable encoder.
        encoder.dateEncodingStrategy = .iso8601 // Uses a stable interoperable timestamp representation.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys] // Makes catalog changes reviewable and repeatable.
        let data = try encoder.encode(descriptors) // Encodes only typed descriptors and bookmark bytes.
        try data.write(to: catalogURL, options: .atomic) // Prevents a partial catalog replacement.
    } // Ends atomic catalog persistence.

    private static func loadCatalog(at url: URL, fileManager: FileManager) -> [EngineeringWorkspaceDescriptor] { // Loads a bounded typed catalog without crashing app startup.
        guard fileManager.fileExists(atPath: url.path), let attributes = try? fileManager.attributesOfItem(atPath: url.path), let byteCount = attributes[.size] as? NSNumber, byteCount.intValue <= 2_097_152 else { return [] } // Treats absent or unexpectedly large metadata as unavailable.
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder.engineeringISO8601.decode([EngineeringWorkspaceDescriptor].self, from: data) else { return [] } // Isolates malformed app-owned JSON safely.
        return decoded // Returns only fully decoded typed records.
    } // Ends resilient catalog loading.
} // Ends Engineering Workspace descriptor persistence.

actor EngineeringWorkspace { // Centralizes every live filesystem mutation and inspection within one canonical root.
    let descriptor: EngineeringWorkspaceDescriptor // Exposes stable user authorization metadata without mutable application objects.
    let rootURL: URL // Exposes the canonical root for UI labels and deterministic process working directories.
    let limits: EngineeringWorkspaceLimits // Exposes the active safety bounds for trace surfaces and tests.
    private let historyDirectoryURL: URL // Stores reversible app-owned transactions outside live source files.
    private let fileManager: FileManager // Supplies injectable filesystem behavior.
    private let securityScopedURL: URL? // Retains the exact URL whose security scope was activated.
    private var records: [UUID: EngineeringChangeRecord] // Caches bounded durable transactions by stable identity.

    init(descriptor: EngineeringWorkspaceDescriptor, historyDirectoryURL: URL? = nil, limits: EngineeringWorkspaceLimits = .standard, fileManager: FileManager = .default) throws { // Opens a persisted authorization as a contained live workspace.
        let resolution = EngineeringWorkspaceStore.resolveURL(for: descriptor) // Resolves security scope or the unsandboxed path fallback.
        var isDirectory: ObjCBool = false // Receives root filesystem metadata.
        guard fileManager.fileExists(atPath: resolution.url.path, isDirectory: &isDirectory), isDirectory.boolValue else { // Rejects stale roots before any tool can run.
            if resolution.didStartSecurityScope { resolution.url.stopAccessingSecurityScopedResource() } // Balances scope when validation fails.
            throw EngineeringRuntimeError.workspaceUnavailable(resolution.url.path) // Reports the exact unavailable root.
        } // Ends root availability validation.
        self.descriptor = descriptor // Retains stable authorization identity and metadata.
        self.rootURL = EngineeringPathCanonicalizer.existingURL(resolution.url) // Freezes the filesystem-canonical containment boundary.
        self.limits = limits // Retains normalized caller-provided bounds.
        self.fileManager = fileManager // Retains filesystem dependency.
        self.securityScopedURL = resolution.didStartSecurityScope ? resolution.url : nil // Retains only scope that this instance must later release.
        if let historyDirectoryURL { // Uses a caller-owned isolated history directory in tests or custom configurations.
            self.historyDirectoryURL = historyDirectoryURL.standardizedFileURL // Normalizes the exact app-owned transaction directory.
        } else { // Derives normal app-owned transaction persistence.
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory // Finds a durable host-local base.
            self.historyDirectoryURL = support.appendingPathComponent("AutoMLXStudio/Engineering/History/\(descriptor.id.uuidString)", isDirectory: true) // Separates each authorized workspace's transactions.
        } // Ends history-directory selection.
        try fileManager.createDirectory(at: self.historyDirectoryURL, withIntermediateDirectories: true) // Creates only app-owned history storage.
        self.records = Self.loadRecords(from: self.historyDirectoryURL, workspaceID: descriptor.id, fileManager: fileManager) // Loads only valid transactions for this exact workspace.
    } // Ends contained workspace construction.

    init(rootURL: URL, workspaceID: UUID = UUID(), displayName: String? = nil, historyDirectoryURL: URL, limits: EngineeringWorkspaceLimits = .standard, fileManager: FileManager = .default) throws { // Creates an explicitly authorized temporary or integration workspace without catalog persistence.
        let canonicalRoot = EngineeringPathCanonicalizer.existingURL(rootURL) // Normalizes filesystem aliases and symlinks for the explicit user/test-selected directory.
        let descriptor = EngineeringWorkspaceDescriptor(id: workspaceID, displayName: displayName ?? canonicalRoot.lastPathComponent, rootPath: canonicalRoot.path, securityScopedBookmark: nil, associatedProjectID: nil, createdAt: Date(), lastOpenedAt: Date()) // Represents the same authorization shape without requiring a bookmark fixture.
        try self.init(descriptor: descriptor, historyDirectoryURL: historyDirectoryURL, limits: limits, fileManager: fileManager) // Delegates all boundary validation and durable history setup.
    } // Ends explicit-root workspace construction.

    deinit { // Balances only the security-scoped resource started by this workspace instance.
        securityScopedURL?.stopAccessingSecurityScopedResource() // Releases sandbox authorization without touching the external directory.
    } // Ends workspace lifecycle cleanup.

    func listDirectory(relativePath: String = "") throws -> [EngineeringDirectoryEntry] { // Returns a bounded non-recursive view of one contained visible directory.
        let resolved = try resolve(relativePath, allowRoot: true, requiresExisting: true, enforceSensitivePolicy: true) // Canonicalizes and contains the requested directory.
        let values = try resolved.canonicalURL.resourceValues(forKeys: [.isDirectoryKey]) // Reads only required directory metadata.
        guard values.isDirectory == true else { throw EngineeringRuntimeError.notADirectory(resolved.relativePath) } // Refuses file targets.
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey] // Requests inexpensive metadata in one pass.
        let children = try fileManager.contentsOfDirectory(at: resolved.canonicalURL, includingPropertiesForKeys: Array(keys), options: []) // Enumerates only direct children.
        var entries: [EngineeringDirectoryEntry] = [] // Accumulates bounded visible results.
        for child in children.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) { // Produces deterministic human-friendly ordering.
            guard entries.count < limits.maximumDirectoryEntries else { break } // Stops before an oversized directory can flood context.
            guard !Self.isHiddenOrSensitive(component: child.lastPathComponent), !Self.isIgnoredSearchDirectory(child.lastPathComponent) else { continue } // Omits hidden, sensitive, and generated garbage by default.
            let childRelative = resolved.relativePath.isEmpty ? child.lastPathComponent : "\(resolved.relativePath)/\(child.lastPathComponent)" // Builds a normalized root-relative child identity.
            guard let childResolved = try? resolve(childRelative, allowRoot: false, requiresExisting: true, enforceSensitivePolicy: true) else { continue } // Omits an unsafe or racing child without making one symlink deny the complete safe directory listing.
            let childValues = try childResolved.lexicalURL.resourceValues(forKeys: keys) // Preserves lexical symlink metadata without following it for display.
            entries.append(EngineeringDirectoryEntry(relativePath: childRelative, isDirectory: childValues.isDirectory == true, isSymbolicLink: childValues.isSymbolicLink == true, byteCount: childValues.fileSize, modificationDate: childValues.contentModificationDate)) // Adds only safe bounded metadata.
        } // Ends direct child enumeration.
        return entries // Returns the bounded listing without recursive expansion.
    } // Ends list_directory behavior.

    func readFile(relativePath: String, startLine: Int? = nil, endLine: Int? = nil) throws -> EngineeringFileRead { // Reads one bounded regular UTF-8 file with optional line selection.
        let resolved = try resolve(relativePath, allowRoot: false, requiresExisting: true, enforceSensitivePolicy: true) // Canonicalizes and contains the target.
        let metadata = try regularFileMetadata(for: resolved) // Requires a safe regular file and retrieves its size.
        let read = try readBoundedText(from: resolved.canonicalURL, maximumBytes: limits.maximumReadBytes) // Reads only the configured byte window through anchored no-follow descriptors.
        let exactHash = try sha256(ofFileAt: resolved.canonicalURL) // Fingerprints source bytes without following racing path-component links.
        var selectedText = read.text // Starts with the decoded bounded file prefix.
        var lineWasTruncated = false // Tracks omission caused by an explicit line selection.
        if startLine != nil || endLine != nil { // Applies an inclusive one-based line range only when requested.
            let normalizedStart = max(1, startLine ?? 1) // Prevents non-positive line indices.
            let normalizedEnd = max(normalizedStart, endLine ?? Int.max) // Prevents an inverted range from broadening access.
            let lines = selectedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) // Preserves blank lines for deterministic editor coordinates.
            let lowerIndex = min(lines.count, normalizedStart - 1) // Clamps selection to the decoded text.
            let upperIndex = min(lines.count, normalizedEnd) // Converts the inclusive user index into a safe slice end.
            selectedText = lowerIndex < upperIndex ? lines[lowerIndex..<upperIndex].joined(separator: "\n") : "" // Returns exactly the requested available lines.
            lineWasTruncated = lowerIndex > 0 || upperIndex < lines.count // Reports content omitted by the selected range.
        } // Ends optional line slicing.
        let redacted = EngineeringSecretRedactor.redact(selectedText) // Removes conservative secret patterns before model transmission.
        return EngineeringFileRead(relativePath: resolved.relativePath, text: redacted, sha256: exactHash, totalByteCount: metadata.byteCount, wasTruncated: read.wasTruncated || lineWasTruncated) // Returns bounded text and exact concurrency evidence.
    } // Ends read_file behavior.

    func fileInfo(relativePath: String) throws -> EngineeringFileInfo { // Returns metadata without returning file contents.
        let resolved = try resolve(relativePath, allowRoot: true, requiresExisting: true, enforceSensitivePolicy: true) // Canonicalizes and contains the visible target.
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey] // Requests only safe inexpensive metadata.
        let lexicalValues = try resolved.lexicalURL.resourceValues(forKeys: keys) // Reads link identity at the lexical target.
        let canonicalValues = try resolved.canonicalURL.resourceValues(forKeys: keys) // Reads contained target type and size.
        var hash: String? // Holds a full content fingerprint only for bounded regular files.
        if canonicalValues.isRegularFile == true, (canonicalValues.fileSize ?? 0) <= limits.maximumWriteBytes { hash = try sha256(ofFileAt: resolved.canonicalURL) } // Opens bounded regular source through anchored no-follow descriptors.
        return EngineeringFileInfo(relativePath: resolved.relativePath, isDirectory: canonicalValues.isDirectory == true, isSymbolicLink: lexicalValues.isSymbolicLink == true, byteCount: canonicalValues.fileSize, modificationDate: canonicalValues.contentModificationDate, sha256: hash) // Returns contained metadata.
    } // Ends file_info behavior.

    func searchFiles(query: String, relativePath: String = "") throws -> [EngineeringTextMatch] { // Searches bounded visible filenames without a heavyweight index.
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines) // Normalizes provider input without interpreting it as code.
        guard !trimmedQuery.isEmpty else { return [] } // Avoids an empty query dumping the whole workspace.
        let candidates = try searchableFiles(relativePath: relativePath) // Enumerates bounded safe regular-file candidates.
        let needle = trimmedQuery.lowercased() // Uses deterministic case-insensitive literal matching.
        var matches: [EngineeringTextMatch] = [] // Accumulates bounded filename matches.
        for candidate in candidates where candidate.relativePath.lowercased().contains(needle) { // Treats punctuation and wildcard characters as ordinary data.
            matches.append(EngineeringTextMatch(relativePath: candidate.relativePath, line: nil, excerpt: candidate.relativePath)) // Reports only the contained visible path.
            if matches.count >= limits.maximumSearchMatches { break } // Stops before response context can grow without bound.
        } // Ends literal filename matching.
        return matches // Returns deterministic bounded results.
    } // Ends search_files behavior.

    func searchText(query: String, relativePath: String = "") throws -> [EngineeringTextMatch] { // Searches literal text across bounded visible UTF-8 file prefixes.
        guard !query.isEmpty else { return [] } // Prevents an empty literal from matching every line.
        let candidates = try searchableFiles(relativePath: relativePath) // Enumerates bounded contained candidates without following links.
        var matches: [EngineeringTextMatch] = [] // Accumulates bounded content evidence.
        for candidate in candidates { // Visits deterministic candidate order.
            guard matches.count < limits.maximumSearchMatches else { break } // Stops globally at the configured context bound.
            guard let read = try? readBoundedText(from: candidate.canonicalURL, maximumBytes: limits.maximumReadBytes) else { continue } // Skips binary, undecodable, racing, or transiently unreadable files.
            let lines = read.text.split(separator: "\n", omittingEmptySubsequences: false) // Preserves one-based line positions including blanks.
            for (index, line) in lines.enumerated() where line.localizedCaseInsensitiveContains(query) { // Performs literal case-insensitive matching with no command interpretation.
                let excerpt = EngineeringSecretRedactor.redact(String(line.prefix(500))) // Bounds and redacts every returned line independently.
                matches.append(EngineeringTextMatch(relativePath: candidate.relativePath, line: index + 1, excerpt: excerpt)) // Records exact contained source evidence.
                if matches.count >= limits.maximumSearchMatches { break } // Stops the inner scan at the global result bound.
            } // Ends one file's line scan.
        } // Ends bounded candidate scanning.
        return matches // Returns bounded secret-safe matches.
    } // Ends search_text behavior.

    func createFile(relativePath: String, content: String, createParentDirectories: Bool = false, now: Date = Date()) throws -> EngineeringChangeRecord { // Atomically creates one absent contained UTF-8 file.
        let data = Data(content.utf8) // Encodes the model-authored text deterministically.
        try validateMutationSize(data) // Refuses unexpectedly large authored state before touching disk.
        let resolved = try resolve(relativePath, allowRoot: false, requiresExisting: false, enforceSensitivePolicy: true) // Validates lexical and canonical authority for an absent target.
        guard !fileManager.fileExists(atPath: resolved.canonicalURL.path) else { throw EngineeringRuntimeError.fileAlreadyExists(resolved.relativePath) } // Never silently overwrites existing user data.
        let parentURL = resolved.canonicalURL.deletingLastPathComponent() // Identifies the exact contained parent directory.
        if createParentDirectories { // Creates missing parents only when the typed request explicitly permits it.
            _ = try resolveParentForCreation(relativePath: resolved.relativePath) // Proves every existing ancestor and symlink remains contained.
        } // Ends optional parent creation.
        var parentIsDirectory: ObjCBool = false // Receives parent availability metadata.
        guard createParentDirectories || (fileManager.fileExists(atPath: parentURL.path, isDirectory: &parentIsDirectory) && parentIsDirectory.boolValue) else { throw EngineeringRuntimeError.notADirectory(parentURL.path) } // Requires existing parents unless descriptor-relative creation was explicitly requested.
        let record = EngineeringChangeRecord(id: UUID(), workspaceID: descriptor.id, relativePath: resolved.relativePath, kind: .create, createdAt: now, beforeData: nil, afterData: data, beforeSHA256: nil, afterSHA256: Self.sha256(data), parentChangeID: nil) // Captures exact bounded before/after state before mutation.
        try persistAndApply(record: record) { try EngineeringSecureFileAccess(rootURL: rootURL).write(data, to: resolved.canonicalURL, createOnly: true, createParents: createParentDirectories) } // Publishes through an anchored parent and never overwrites a racing target.
        return record // Returns exact transaction evidence.
    } // Ends create_file behavior.

    func writeFile(relativePath: String, content: String, expectedSHA256: String, now: Date = Date()) throws -> EngineeringChangeRecord { // Atomically replaces one existing file from an explicitly observed state.
        let data = Data(content.utf8) // Encodes authored text deterministically.
        try validateMutationSize(data) // Bounds the new state before any filesystem mutation.
        let resolved = try resolve(relativePath, allowRoot: false, requiresExisting: true, enforceSensitivePolicy: true) // Canonicalizes and contains the existing target.
        let metadata = try regularFileMetadata(for: resolved) // Rejects directories, binaries, and oversized rollback states.
        guard metadata.byteCount <= limits.maximumWriteBytes else { throw EngineeringRuntimeError.outputLimitExceeded(limits.maximumWriteBytes) } // Requires exact bounded rollback bytes.
        let original = try EngineeringSecureFileAccess(rootURL: rootURL).read(resolved.canonicalURL, maximumBytes: limits.maximumWriteBytes) // Captures bounded bytes without following racing parent or file symlinks.
        try ensureTextData(original, relativePath: resolved.relativePath) // Refuses binary overwrite through text tools.
        let actualHash = Self.sha256(original) // Fingerprints the captured bytes rather than racing a second read.
        guard actualHash.caseInsensitiveCompare(expectedSHA256) == .orderedSame else { throw EngineeringRuntimeError.expectedHashConflict(expected: expectedSHA256, actual: actualHash) } // Preserves external edits made since read_file.
        let record = EngineeringChangeRecord(id: UUID(), workspaceID: descriptor.id, relativePath: resolved.relativePath, kind: .write, createdAt: now, beforeData: original, afterData: data, beforeSHA256: actualHash, afterSHA256: Self.sha256(data), parentChangeID: nil) // Captures exact reversible state.
        try persistAndApply(record: record) { try EngineeringSecureFileAccess(rootURL: rootURL).write(data, to: resolved.canonicalURL, createOnly: false) } // Atomically replaces only an entry in the descriptor-anchored workspace parent.
        return record // Returns transaction identity and hashes.
    } // Ends write_file behavior.

    func replaceInFile(relativePath: String, oldText: String, newText: String, expectedOccurrences: Int = 1, expectedSHA256: String, now: Date = Date()) throws -> EngineeringChangeRecord { // Performs deterministic exact replacement from an explicitly observed state.
        guard !oldText.isEmpty, expectedOccurrences > 0 else { throw EngineeringRuntimeError.replacementCountMismatch(expected: max(1, expectedOccurrences), actual: 0) } // Refuses ambiguous empty-pattern or non-positive expectations.
        let resolved = try resolve(relativePath, allowRoot: false, requiresExisting: true, enforceSensitivePolicy: true) // Canonicalizes and contains the existing target.
        let metadata = try regularFileMetadata(for: resolved) // Requires a bounded regular file.
        guard metadata.byteCount <= limits.maximumWriteBytes else { throw EngineeringRuntimeError.outputLimitExceeded(limits.maximumWriteBytes) } // Ensures exact rollback state fits the transaction budget.
        let originalData = try EngineeringSecureFileAccess(rootURL: rootURL).read(resolved.canonicalURL, maximumBytes: limits.maximumWriteBytes) // Captures bounded bytes without a mutable pathname read.
        try ensureTextData(originalData, relativePath: resolved.relativePath) // Refuses binary replacement through a text tool.
        let actualHash = Self.sha256(originalData) // Fingerprints the exact captured state.
        guard actualHash.caseInsensitiveCompare(expectedSHA256) == .orderedSame else { throw EngineeringRuntimeError.expectedHashConflict(expected: expectedSHA256, actual: actualHash) } // Preserves edits made after model inspection.
        guard let originalText = String(data: originalData, encoding: .utf8) else { throw EngineeringRuntimeError.unsupportedBinaryFile(resolved.relativePath) } // Requires lossless UTF-8 decoding.
        let actualOccurrences = Self.nonoverlappingOccurrenceCount(of: oldText, in: originalText) // Counts exact non-overlapping matches before mutation.
        guard actualOccurrences == expectedOccurrences else { throw EngineeringRuntimeError.replacementCountMismatch(expected: expectedOccurrences, actual: actualOccurrences) } // Fails instead of making an ambiguous edit.
        let replacementText = originalText.replacingOccurrences(of: oldText, with: newText) // Applies the exact validated replacement set.
        let replacementData = Data(replacementText.utf8) // Encodes the deterministic result.
        try validateMutationSize(replacementData) // Refuses replacement expansion beyond rollback bounds.
        let record = EngineeringChangeRecord(id: UUID(), workspaceID: descriptor.id, relativePath: resolved.relativePath, kind: .replace, createdAt: now, beforeData: originalData, afterData: replacementData, beforeSHA256: actualHash, afterSHA256: Self.sha256(replacementData), parentChangeID: nil) // Captures exact reversible before/after state.
        try persistAndApply(record: record) { try EngineeringSecureFileAccess(rootURL: rootURL).write(replacementData, to: resolved.canonicalURL, createOnly: false) } // Persists history before descriptor-relative atomic replacement.
        return record // Returns the exact transaction for diff or rollback.
    } // Ends replace_in_file behavior.

    func changes() -> [EngineeringChangeRecord] { // Returns this workspace's durable app-owned mutation history.
        records.values.sorted { lhs, rhs in // Sorts transaction history deterministically.
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt } // Preserves chronological operation order.
            return lhs.id.uuidString < rhs.id.uuidString // Stabilizes equal timestamps.
        } // Ends deterministic history sorting.
    } // Ends transaction-history access.

    func unifiedDiff(changeID: UUID) throws -> String { // Builds a bounded textual unified diff without requiring a Git repository.
        guard let record = records[changeID] else { throw EngineeringRuntimeError.changeNotFound(changeID) } // Requires an app-owned durable transaction.
        guard record.workspaceID == descriptor.id else { throw EngineeringRuntimeError.changeBelongsToAnotherWorkspace(changeID) } // Prevents cross-workspace state disclosure.
        let before = record.beforeData.flatMap { String(data: $0, encoding: .utf8) } ?? "" // Decodes the bounded original or the empty absent state.
        let after = record.afterData.flatMap { String(data: $0, encoding: .utf8) } ?? "" // Decodes the bounded authored or future deleted state.
        let diff = Self.makeUnifiedDiff(path: record.relativePath, before: before, after: after, beforeExists: record.beforeData != nil, afterExists: record.afterData != nil) // Creates deterministic standard headers and hunks.
        let bounded = String(decoding: Data(diff.utf8).prefix(limits.maximumDiffBytes), as: UTF8.self) // Bounds model-visible diff bytes safely.
        return EngineeringSecretRedactor.redact(bounded) // Prevents stored secrets from leaking through change inspection.
    } // Ends session unified-diff generation.

    func rollback(changeID: UUID, now: Date = Date()) throws -> EngineeringChangeRecord { // Reverses only one app-owned change when its authored state is still current.
        guard let originalRecord = records[changeID] else { throw EngineeringRuntimeError.changeNotFound(changeID) } // Requires exact durable transaction ownership.
        guard originalRecord.workspaceID == descriptor.id else { throw EngineeringRuntimeError.changeBelongsToAnotherWorkspace(changeID) } // Prevents cross-workspace rollback.
        let resolved = try resolve(originalRecord.relativePath, allowRoot: false, requiresExisting: originalRecord.afterData != nil, enforceSensitivePolicy: true) // Revalidates current containment instead of trusting stored paths.
        let currentData = fileManager.fileExists(atPath: resolved.canonicalURL.path) ? try EngineeringSecureFileAccess(rootURL: rootURL).read(resolved.canonicalURL, maximumBytes: limits.maximumWriteBytes) : nil // Captures bounded rollback state without following racing links.
        let currentHash = currentData.map(Self.sha256) // Fingerprints current bytes or represents absence.
        guard currentHash == originalRecord.afterSHA256 else { throw EngineeringRuntimeError.rollbackConflict(expected: originalRecord.afterSHA256, actual: currentHash) } // Preserves every unrelated external edit after the agent change.
        let rollbackRecord = EngineeringChangeRecord(id: UUID(), workspaceID: descriptor.id, relativePath: originalRecord.relativePath, kind: .rollback, createdAt: now, beforeData: currentData, afterData: originalRecord.beforeData, beforeSHA256: currentHash, afterSHA256: originalRecord.beforeSHA256, parentChangeID: originalRecord.id) // Records rollback itself as another exact auditable transaction.
        try persistAndApply(record: rollbackRecord) { // Persists rollback evidence before changing the target.
            if let restored = originalRecord.beforeData { // Restores an overwritten file exactly.
                try EngineeringSecureFileAccess(rootURL: rootURL).write(restored, to: resolved.canonicalURL, createOnly: false) // Restores bytes through an anchored parent without following a racing outside link.
            } else { // Reverses a file that this session originally created.
                guard self.fileManager.fileExists(atPath: resolved.canonicalURL.path) else { throw EngineeringRuntimeError.rollbackConflict(expected: originalRecord.afterSHA256, actual: nil) } // Rechecks exact target existence immediately before deletion.
                try EngineeringSecureFileAccess(rootURL: rootURL).remove(resolved.canonicalURL) // Unlinks only a single entry in the anchored contained parent.
            } // Ends rollback state selection.
        } // Ends persisted rollback application.
        return rollbackRecord // Returns exact audit evidence for the reversal.
    } // Ends conflict-aware rollback.

    func resolveWorkingDirectory(_ relativePath: String) throws -> URL { // Resolves a command cwd using the same canonical containment policy as file tools.
        let resolved = try resolve(relativePath, allowRoot: true, requiresExisting: true, enforceSensitivePolicy: true) // Validates lexical and symlink containment.
        let values = try resolved.canonicalURL.resourceValues(forKeys: [.isDirectoryKey]) // Reads only directory identity.
        guard values.isDirectory == true else { throw EngineeringRuntimeError.notADirectory(resolved.relativePath) } // Prevents a file from becoming Process.currentDirectoryURL.
        return resolved.canonicalURL // Returns only a canonical contained directory.
    } // Ends deterministic command cwd resolution.

    private func searchableFiles(relativePath: String) throws -> [ResolvedWorkspacePath] { // Enumerates bounded visible regular files without following symlinks.
        let base = try resolve(relativePath, allowRoot: true, requiresExisting: true, enforceSensitivePolicy: true) // Contains the requested search subtree.
        let baseValues = try base.canonicalURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) // Determines whether the request names one file or a directory.
        if baseValues.isRegularFile == true { return [base] } // Searches one explicitly selected safe regular file directly.
        guard baseValues.isDirectory == true else { throw EngineeringRuntimeError.notADirectory(base.relativePath) } // Rejects unsupported filesystem objects.
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey] // Requests traversal and size metadata efficiently.
        guard let enumerator = fileManager.enumerator(at: base.canonicalURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { return [] } // Treats an unavailable enumerator as no safe candidates.
        var candidates: [ResolvedWorkspacePath] = [] // Accumulates bounded regular files.
        while let url = enumerator.nextObject() as? URL, candidates.count < limits.maximumSearchFiles { // Stops traversal at the configured candidate bound.
            let values = try? url.resourceValues(forKeys: Set(keys)) // Reads cached traversal metadata without failing the whole search for one race.
            if values?.isDirectory == true, Self.isIgnoredSearchDirectory(url.lastPathComponent) { enumerator.skipDescendants(); continue } // Skips generated dependency trees by default.
            if values?.isSymbolicLink == true { if values?.isDirectory == true { enumerator.skipDescendants() }; continue } // Never follows links during recursive search.
            guard values?.isRegularFile == true else { continue } // Ignores directories and special filesystem objects.
            let relative = Self.relativePath(from: rootURL, to: url) // Derives the candidate's normalized root-relative identity.
            guard !relative.split(separator: "/").contains(where: { Self.isHiddenOrSensitive(component: String($0)) }) else { continue } // Excludes sensitive components even if enumerator behavior changes.
            guard (values?.fileSize ?? 0) <= max(limits.maximumReadBytes * 4, limits.maximumWriteBytes) else { continue } // Avoids opening unusually large generated or data files.
            if let resolved = try? resolve(relative, allowRoot: false, requiresExisting: true, enforceSensitivePolicy: true) { candidates.append(resolved) } // Revalidates canonical containment immediately before use.
        } // Ends bounded recursive traversal.
        return candidates.sorted { $0.relativePath < $1.relativePath } // Stabilizes search ordering across filesystems.
    } // Ends safe search candidate enumeration.

    private func resolveParentForCreation(relativePath: String) throws -> ResolvedWorkspacePath { // Validates an absent target's parent hierarchy against symlink escapes.
        let parent = (relativePath as NSString).deletingLastPathComponent // Extracts the normalized relative parent path.
        return try resolve(parent, allowRoot: true, requiresExisting: false, enforceSensitivePolicy: true) // Walks and contains every existing ancestor.
    } // Ends parent validation.

    private func resolve(_ suppliedPath: String, allowRoot: Bool, requiresExisting: Bool, enforceSensitivePolicy: Bool) throws -> ResolvedWorkspacePath { // Applies lexical, canonical, and policy validation to every filesystem request.
        let trimmed = suppliedPath.trimmingCharacters(in: .whitespacesAndNewlines) // Removes accidental surrounding whitespace without rewriting path components.
        if trimmed.isEmpty { // Handles the workspace root only for explicitly root-capable operations.
            guard allowRoot else { throw EngineeringRuntimeError.invalidRelativePath(suppliedPath) } // Prevents file mutations from targeting the authority root.
            return ResolvedWorkspacePath(relativePath: "", lexicalURL: rootURL, canonicalURL: rootURL) // Returns the frozen canonical authority boundary.
        } // Ends root request handling.
        guard !(trimmed as NSString).isAbsolutePath, !trimmed.hasPrefix("~"), !trimmed.contains("\0") else { throw EngineeringRuntimeError.invalidRelativePath(suppliedPath) } // Rejects absolute, home-relative, and NUL-bearing input.
        let rawComponents = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init) // Preserves empty and traversal components for explicit denial.
        guard !rawComponents.isEmpty, rawComponents.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw EngineeringRuntimeError.invalidRelativePath(suppliedPath) } // Rejects parent, dot, and repeated-separator normalization bypasses.
        if enforceSensitivePolicy, rawComponents.contains(where: Self.isHiddenOrSensitive(component:)) { throw EngineeringRuntimeError.hiddenOrSensitivePath(suppliedPath) } // Applies conservative hidden and secret-path denial before filesystem access.
        let normalizedRelative = rawComponents.joined(separator: "/") // Produces one stable persisted and reported path.
        let lexicalURL = rootURL.appendingPathComponent(normalizedRelative, isDirectory: false).standardizedFileURL // Constructs the lexical target beneath the frozen root.
        var currentURL = rootURL // Begins component-wise canonical traversal at the authorized boundary.
        for component in rawComponents { // Resolves each existing prefix so a symlink can never jump authority.
            let candidate = currentURL.appendingPathComponent(component, isDirectory: false).standardizedFileURL // Appends one previously validated literal component.
            if EngineeringPathCanonicalizer.entryExists(at: candidate) { // Resolves every lexical entry, including symlinks whose target may be unavailable.
                guard fileManager.fileExists(atPath: candidate.path) else { throw EngineeringRuntimeError.pathEscapesWorkspace(suppliedPath) } // Refuses dangling symlinks instead of treating them as safe absent creation targets.
                currentURL = EngineeringPathCanonicalizer.existingURL(candidate) // Resolves filesystem aliases and complete symlink chains through realpath.
            } else { // Preserves a normalized contained path for an actually absent component.
                currentURL = candidate // Continues validating any remaining absent descendants lexically.
            } // Ends one component's canonical resolution.
            guard Self.isContained(currentURL, by: rootURL) else { throw EngineeringRuntimeError.pathEscapesWorkspace(suppliedPath) } // Rejects symlink and normalization escapes immediately.
        } // Ends component-wise canonicalization.
        if requiresExisting, !fileManager.fileExists(atPath: currentURL.path) { throw EngineeringRuntimeError.fileNotFound(normalizedRelative) } // Requires target existence only for the selected operation.
        return ResolvedWorkspacePath(relativePath: normalizedRelative, lexicalURL: lexicalURL, canonicalURL: currentURL) // Returns both display and contained access identities.
    } // Ends universal workspace path resolution.

    private func regularFileMetadata(for resolved: ResolvedWorkspacePath) throws -> (byteCount: Int, modificationDate: Date?) { // Validates a regular file before text operations.
        let values = try resolved.canonicalURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) // Reads exact canonical target metadata.
        guard values.isRegularFile == true else { throw EngineeringRuntimeError.notAFile(resolved.relativePath) } // Rejects directories, sockets, devices, and other special objects.
        return (max(0, values.fileSize ?? 0), values.contentModificationDate) // Returns normalized inexpensive metadata.
    } // Ends regular-file validation.

    private func validateMutationSize(_ data: Data) throws { // Applies one consistent authored-state byte bound.
        guard data.count <= limits.maximumWriteBytes else { throw EngineeringRuntimeError.inputTooLarge(limits.maximumWriteBytes) } // Refuses oversized writes before history or source mutation.
    } // Ends mutation-size validation.

    private func ensureTextData(_ data: Data, relativePath: String) throws { // Requires lossless non-binary UTF-8 for text mutation tools.
        guard !data.prefix(8_192).contains(0), String(data: data, encoding: .utf8) != nil else { throw EngineeringRuntimeError.unsupportedBinaryFile(relativePath) } // Rejects NUL-bearing or undecodable content.
    } // Ends binary-file refusal.

    private func persistAndApply(record: EngineeringChangeRecord, mutation: () throws -> Void) throws { // Couples durable rollback evidence with one atomic source mutation.
        try persist(record) // Commits exact before/after history before touching live source state.
        do { // Attempts only the validated mutation supplied by the caller.
            try mutation() // Performs the atomic contained write or exact created-file rollback removal.
            records[record.id] = record // Publishes history in actor memory only after the source mutation succeeds.
        } catch { // Removes an unused history record when the source mutation fails synchronously.
            let recordURL = historyDirectoryURL.appendingPathComponent("\(record.id.uuidString).json", isDirectory: false) // Resolves only the exact just-created app-owned record.
            try? fileManager.removeItem(at: recordURL) // Best-effort removes false transaction evidence without broad deletion.
            throw error // Preserves the original filesystem failure.
        } // Ends transactional mutation recovery.
    } // Ends transaction coupling.

    private func persist(_ record: EngineeringChangeRecord) throws { // Atomically writes one bounded transaction record.
        let encoder = JSONEncoder() // Creates deterministic durable encoding.
        encoder.dateEncodingStrategy = .iso8601 // Uses stable timestamps.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys] // Makes app-owned history inspectable.
        let data = try encoder.encode(record) // Encodes exact bounded before/after bytes.
        let recordURL = historyDirectoryURL.appendingPathComponent("\(record.id.uuidString).json", isDirectory: false) // Uses an unguessable exact filename under the dedicated history directory.
        guard !fileManager.fileExists(atPath: recordURL.path) else { throw CocoaError(.fileWriteFileExists) } // Refuses the practically impossible UUID collision before persistence.
        try data.write(to: recordURL, options: .atomic) // Prevents a partial transaction record without Foundation's unsupported option combination.
    } // Ends transaction persistence.

    private static func loadRecords(from directoryURL: URL, workspaceID: UUID, fileManager: FileManager) -> [UUID: EngineeringChangeRecord] { // Loads valid bounded records independently so one corrupt file cannot hide others.
        guard let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return [:] } // Treats missing history as an empty session lineage.
        var loaded: [UUID: EngineeringChangeRecord] = [:] // Accumulates independently decoded records.
        for url in urls where url.pathExtension.lowercased() == "json" { // Considers only exact app-owned record format files.
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), (values.fileSize ?? Int.max) <= 3_000_000 else { continue } // Bounds app-owned metadata reads.
            guard let data = try? Data(contentsOf: url), let record = try? JSONDecoder.engineeringISO8601.decode(EngineeringChangeRecord.self, from: data), record.workspaceID == workspaceID else { continue } // Isolates corrupt or cross-workspace records.
            loaded[record.id] = record // Retains the valid stable transaction.
        } // Ends isolated record decoding.
        return loaded // Returns all healthy matching history.
    } // Ends durable transaction loading.

    private func readBoundedText(from url: URL, maximumBytes: Int) throws -> (text: String, wasTruncated: Bool) { // Reads a leading byte window without following racing outside symlinks.
        let handle = try EngineeringSecureFileAccess(rootURL: rootURL).openFile(url) // Pins every path component and the actual regular file before reading.
        defer { try? handle.close() } // Releases the exact descriptor after the bounded read.
        let data = try handle.read(upToCount: max(1, maximumBytes) + 4) ?? Data() // Reads a small UTF-8 boundary cushion beyond the returned limit.
        let wasTruncated = data.count > maximumBytes || ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? data.count) > maximumBytes // Reports omitted trailing source bytes.
        let bounded = Data(data.prefix(maximumBytes)) // Retains only the configured context budget.
        guard !bounded.prefix(8_192).contains(0) else { throw EngineeringRuntimeError.unsupportedBinaryFile(url.lastPathComponent) } // Rejects common binary content before decoding.
        if let exact = String(data: bounded, encoding: .utf8) { return (exact, wasTruncated) } // Returns lossless UTF-8 when the byte window ends on a scalar boundary.
        if wasTruncated { // Allows only an incomplete final multi-byte scalar caused by byte-bound truncation.
            for removalCount in 1...min(4, bounded.count) { // Tests the maximum UTF-8 scalar width conservatively.
                if let prefix = String(data: bounded.dropLast(removalCount), encoding: .utf8) { return (prefix, true) } // Returns a lossless prefix and marks omission.
            } // Ends UTF-8 boundary recovery.
        } // Ends truncated-scalar handling.
        throw EngineeringRuntimeError.unsupportedBinaryFile(url.lastPathComponent) // Refuses malformed or unsupported encoding without lossy model transmission.
    } // Ends bounded UTF-8 reading.

    private static func sha256(_ data: Data) -> String { // Fingerprints in-memory bounded transaction bytes.
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() // Returns canonical lowercase hexadecimal SHA-256.
    } // Ends in-memory hashing.

    private func sha256(ofFileAt url: URL) throws -> String { // Streams a complete fingerprint from an anchored contained file.
        let handle = try EngineeringSecureFileAccess(rootURL: rootURL).openFile(url) // Rejects a racing symlink in any path component.
        defer { try? handle.close() } // Releases the exact descriptor after hashing.
        var hasher = SHA256() // Creates incremental SHA-256 state.
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty { hasher.update(data: chunk) } // Processes bounded chunks until EOF.
        return hasher.finalize().map { String(format: "%02x", $0) }.joined() // Returns canonical lowercase hexadecimal evidence.
    } // Ends streaming file hashing.

    private static func nonoverlappingOccurrenceCount(of needle: String, in haystack: String) -> Int { // Counts the exact replacement semantics used by String replacement.
        var count = 0 // Accumulates non-overlapping matches.
        var searchRange = haystack.startIndex..<haystack.endIndex // Starts at the complete source range.
        while let range = haystack.range(of: needle, options: [], range: searchRange) { // Finds the next exact case-sensitive literal occurrence.
            count += 1 // Records one deterministic match.
            searchRange = range.upperBound..<haystack.endIndex // Advances past the match to avoid overlap ambiguity.
        } // Ends literal occurrence scanning.
        return count // Returns the exact replacement count.
    } // Ends occurrence counting.

    private static func makeUnifiedDiff(path: String, before: String, after: String, beforeExists: Bool, afterExists: Bool) -> String { // Produces a compact valid whole-file unified hunk.
        guard before != after || beforeExists != afterExists else { return "" } // Emits no hunk when state is identical.
        let beforeLines = beforeExists ? before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) : [] // Preserves exact original lines while representing absent files with zero lines.
        let afterLines = afterExists ? after.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) : [] // Preserves exact authored lines while representing deleted files with zero lines.
        let oldHeader = beforeExists ? "a/\(path)" : "/dev/null" // Uses conventional creation source identity.
        let newHeader = afterExists ? "b/\(path)" : "/dev/null" // Uses conventional deletion destination identity for future support.
        var lines = ["--- \(oldHeader)", "+++ \(newHeader)", "@@ -\(beforeExists ? 1 : 0),\(beforeLines.count) +\(afterExists ? 1 : 0),\(afterLines.count) @@"] // Creates standard unified headers and a whole-file hunk range.
        lines.append(contentsOf: beforeLines.map { "-\($0)" }) // Emits exact original lines as removals.
        lines.append(contentsOf: afterLines.map { "+\($0)" }) // Emits exact authored lines as additions.
        return lines.joined(separator: "\n") + "\n" // Terminates the textual diff predictably.
    } // Ends unified diff generation.

    private static func isContained(_ candidate: URL, by root: URL) -> Bool { // Compares canonical filesystem paths with a separator-aware boundary.
        let rootPath = EngineeringPathCanonicalizer.existingURL(root).path // Normalizes the frozen authority root through the filesystem.
        let candidatePath = EngineeringPathCanonicalizer.existingURL(candidate).path // Normalizes the current target or existing ancestor through the filesystem when possible.
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") // Rejects sibling-prefix confusion such as root versus root-secret.
    } // Ends canonical containment comparison.

    private static func relativePath(from root: URL, to child: URL) -> String { // Derives a normalized path only after containment has been established.
        let canonicalRootPath = EngineeringPathCanonicalizer.existingURL(root).path // Resolves filesystem aliases such as `/var` versus `/private/var` at the authority boundary.
        let canonicalChildPath = EngineeringPathCanonicalizer.existingURL(child).path // Resolves the enumerator's potentially differently aliased URL before prefix comparison.
        let rootPrefix = canonicalRootPath.hasSuffix("/") ? canonicalRootPath : canonicalRootPath + "/" // Creates a separator-aware canonical prefix.
        return canonicalChildPath.hasPrefix(rootPrefix) ? String(canonicalChildPath.dropFirst(rootPrefix.count)) : child.lastPathComponent // Uses a safe fallback that will still be revalidated by resolve.
    } // Ends root-relative path derivation.

    private static func isHiddenOrSensitive(component: String) -> Bool { // Applies conservative path-based secret policy before file contents are opened.
        let lower = component.lowercased() // Normalizes case for cross-project conventions.
        if lower.hasPrefix(".") { return true } // Denies all hidden files and directories by default, including .env and .ssh.
        let exactNames: Set<String> = ["credentials", "credentials.json", "secrets", "secrets.json", "id_rsa", "id_ed25519", "known_hosts", "authorized_keys", "keychain", "keychains"] // Lists common credential containers independent of extension.
        if exactNames.contains(lower) { return true } // Denies exact sensitive names.
        let sensitiveExtensions: Set<String> = ["pem", "key", "p12", "pfx", "mobileprovision"] // Lists private-key and credential bundle extensions.
        if sensitiveExtensions.contains((lower as NSString).pathExtension) { return true } // Denies likely credential material by extension.
        return lower.contains("private_key") || lower.contains("private-key") || lower.hasPrefix("token.") // Denies additional conservative secret naming patterns.
    } // Ends sensitive-path classification.

    private static func isIgnoredSearchDirectory(_ component: String) -> Bool { // Excludes high-volume generated dependency trees from default discovery.
        let lower = component.lowercased() // Normalizes common tool-specific capitalization.
        return lower == "node_modules" || lower == "deriveddata" || lower == "build" || lower == ".build" || lower == "vendor" || lower == "pods" // Applies a small explicit configurable-later default set.
    } // Ends generated-directory exclusion.
} // Ends centralized contained Engineering Workspace filesystem runtime.

private struct ResolvedWorkspacePath: Sendable { // Carries both user-visible lexical identity and canonical access target.
    let relativePath: String // Stores the normalized root-relative path.
    let lexicalURL: URL // Stores the non-resolved target for symlink metadata.
    let canonicalURL: URL // Stores the component-wise contained target used for access.
} // Ends resolved workspace path metadata.

enum EngineeringSecretRedactor { // Conservatively redacts likely credentials from model-visible text and process output.
    private static let patterns: [(String, String)] = [ // Declares bounded regular-expression replacements without claiming perfect detection.
        ("-----BEGIN [^-\\n]*PRIVATE KEY-----[\\s\\S]*?-----END [^-\\n]*PRIVATE KEY-----", "[REDACTED PRIVATE KEY]"), // Removes complete PEM private-key blocks.
        ("(?im)^\\s*(?:export\\s+)?(?:password|passwd|token|api[_-]?key|secret|client[_-]?secret)\\s*[:=]\\s*[^\\r\\n]+", "[REDACTED CREDENTIAL]"), // Removes password-like environment and configuration assignments.
        ("(?i)\\bBearer\\s+[A-Za-z0-9._~+/-]{8,}=*", "Bearer [REDACTED]"), // Removes bearer-token values while retaining authentication context.
        ("\\b(?:sk-[A-Za-z0-9_-]{12,}|ghp_[A-Za-z0-9]{12,}|github_pat_[A-Za-z0-9_]{12,}|xox[baprs]-[A-Za-z0-9-]{12,}|AKIA[0-9A-Z]{16})\\b", "[REDACTED TOKEN]") // Removes several conservative common token prefixes.
    ] // Ends secret-pattern declarations.

    static func redact(_ input: String) -> String { // Returns a same-purpose trace string with likely credentials removed.
        var output = input // Starts from the bounded caller-provided text.
        for (pattern, replacement) in patterns { // Applies each independently compiled conservative detector.
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue } // Skips an unavailable detector without crashing tool execution.
            let range = NSRange(output.startIndex..<output.endIndex, in: output) // Bridges the current Unicode string into Foundation ranges.
            output = expression.stringByReplacingMatches(in: output, range: range, withTemplate: replacement) // Replaces only detected credential spans.
        } // Ends ordered redaction passes.
        return output // Returns bounded redacted text without modifying source files.
    } // Ends secret redaction.
} // Ends conservative secret-output safety.

private enum EngineeringPathCanonicalizer { // Normalizes existing filesystem identities consistently across `/var`, `/private/var`, symlinks, and mounted volumes.
    static func existingURL(_ url: URL) -> URL { // Uses POSIX realpath when the target exists and a standardized fallback otherwise.
        let resolvedPath: String? = url.path.withCString { pathPointer in // Bridges the requested filesystem path into POSIX canonicalization.
            guard let resultPointer = Darwin.realpath(pathPointer, nil) else { return nil } // Leaves absent paths for lexical component validation.
            defer { Darwin.free(resultPointer) } // Releases only the buffer allocated by realpath.
            return String(cString: resultPointer) // Captures the complete filesystem-canonical absolute path.
        } // Ends POSIX realpath bridging.
        return URL(fileURLWithPath: resolvedPath ?? url.standardizedFileURL.path, isDirectory: url.hasDirectoryPath).standardizedFileURL // Returns a stable URL for containment comparison and access.
    } // Ends existing-path canonicalization.

    static func entryExists(at url: URL) -> Bool { // Detects lexical entries even when a symlink target is dangling.
        var metadata = stat() // Receives lstat metadata without following the final symlink.
        return url.path.withCString { Darwin.lstat($0, &metadata) == 0 } // Distinguishes an absent entry from an unsafe dangling link.
    } // Ends lexical-entry existence testing.
} // Ends filesystem identity canonicalization.

private extension JSONDecoder { // Supplies the shared durable timestamp decoder used by Engineering metadata.
    static var engineeringISO8601: JSONDecoder { // Creates a fresh decoder because JSONDecoder is mutable and not Sendable.
        let decoder = JSONDecoder() // Allocates isolated decoding state.
        decoder.dateDecodingStrategy = .iso8601 // Matches every Engineering JSON encoder.
        return decoder // Returns the configured decoder.
    } // Ends shared decoder construction.
} // Ends Engineering JSON decoding support.
