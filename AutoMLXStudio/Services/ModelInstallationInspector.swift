import Foundation // Supplies offline filesystem inspection, JSON parsing, URLs, and file metadata.

struct ModelInstallationValidation: Codable, Equatable, Sendable { // Describes read-only installation facts without mutating a model directory.
    let modelID: String // Identifies the registry profile that was inspected.
    let installed: Bool // Records whether the configured directory or legacy reference exists conceptually.
    let completeEnoughToLaunch: Bool // Records whether all required launch artifacts are currently present.
    let diskBytes: UInt64 // Records the logical size of readable regular files.
    let missingRequiredFiles: [String] // Lists required artifact categories or indexed shards that were not found.
    let warnings: [String] // Lists non-fatal or download-in-progress observations.
    let detectedFiles: Int // Records the number of regular files observed.

    var diskGB: Double? { // Converts a positive byte measurement into binary gigabytes.
        diskBytes > 0 ? Double(diskBytes) / 1_073_741_824 : nil // Leaves size absent for a missing or unreadable directory.
    } // Ends computed disk-size access.
} // Ends structured model installation validation.

enum ModelInstallationStatus: String, Codable, CaseIterable, Sendable { // Defines the reusable installation states required by every backend-aware UI and launch gate.
    case notInstalled // Indicates that no configured local model directory exists.
    case downloading // Indicates that an incomplete directory also contains explicit partial-transfer or lock evidence.
    case incomplete // Indicates that a directory exists but required launch artifacts are absent.
    case complete // Indicates that all required local artifacts and the selected runtime dependency are available.
    case invalid // Indicates malformed indexes or weight containers rather than a merely unfinished transfer.
    case runtimeUnavailable // Indicates complete local artifacts whose backend package is not available in the configured environment.

    var displayName: String { // Converts the stable persisted value into concise Models UI copy.
        switch self { // Selects the human-readable label for the current installation state.
        case .notInstalled: return "Not installed" // Labels an absent model directory.
        case .downloading: return "Downloading / incomplete" // Labels incomplete content with transfer evidence conservatively.
        case .incomplete: return "Incomplete" // Labels missing launch artifacts without claiming an active transfer.
        case .complete: return "Complete" // Labels a launch-ready local model and runtime.
        case .invalid: return "Invalid" // Labels malformed local artifacts.
        case .runtimeUnavailable: return "Runtime unavailable" // Labels a missing backend package independently from model files.
        } // Ends installation-status label selection.
    } // Ends installation-status display-name access.
} // Ends reusable installation status definitions.

struct ModelInstallationReport: Sendable { // Carries complete read-only installation and runtime evidence to launch gates and Models UI.
    let modelID: String // Identifies the inspected registry model.
    let status: ModelInstallationStatus // Stores the deterministic classification derived from files and runtime availability.
    let diskBytes: UInt64 // Stores total logical bytes discovered below the configured model root.
    let missingFiles: [String] // Stores missing required artifacts and index-declared shards.
    let activeLocks: [URL] // Stores exact read-only lock references without deleting, renaming, or opening them for writing.
    let warnings: [String] // Stores bounded non-fatal observations such as stale-lock ambiguity.
} // Ends reusable installation report metadata.

enum ModelInstallationAuditor { // Produces one reusable backend-aware report without changing model folders or downloads.
    static func report(for profile: ModelProfile, runtimeAvailable: Bool? = nil, fileManager: FileManager = .default) -> ModelInstallationReport { // Audits one model and optionally includes its configured runtime dependency.
        let validation = ModelInstallationInspector.validation(for: profile, fileManager: fileManager) // Reuses the canonical config, tokenizer, weight, shard-index, header, and disk inspection.
        let evidence = transferEvidence(for: profile, fileManager: fileManager) // Collects exact recursive lock and partial-transfer references read-only.
        let malformed = validation.missingRequiredFiles.contains { requirement in // Distinguishes malformed content from artifacts that may simply be unfinished.
            requirement.hasPrefix("valid safetensors header:") || requirement.hasPrefix("readable shard index:") // Treats a corrupt header or unreadable declared index as invalid.
        } // Ends malformed-artifact classification.
        let status: ModelInstallationStatus // Declares the final deterministic status.
        if !validation.installed { // Handles an absent configured directory first.
            status = .notInstalled // Reports the model as not installed.
        } else if malformed { // Handles provably malformed local content before download evidence.
            status = .invalid // Reports invalid artifacts without pretending they are merely missing.
        } else if !validation.completeEnoughToLaunch, !evidence.partialFiles.isEmpty || !evidence.lockFiles.isEmpty { // Handles an incomplete folder with explicit transfer evidence.
            status = .downloading // Conservatively reports downloading or incomplete without touching an active transfer.
        } else if !validation.completeEnoughToLaunch { // Handles an existing directory with unexplained missing launch requirements.
            status = .incomplete // Reports a stable incomplete installation.
        } else if runtimeAvailable == false { // Handles complete model artifacts whose optional package is unavailable.
            status = .runtimeUnavailable // Keeps model completeness distinct from environment readiness.
        } else { // Handles complete artifacts with an available or not-yet-supplied runtime check.
            status = .complete // Reports the installation as complete.
        } // Ends final status classification.
        var warnings = validation.warnings // Starts with canonical inspection observations.
        if !evidence.lockFiles.isEmpty { warnings.append("Lock files are present; a lock may be active or stale and was left untouched.") } // Explains why read-only inspection cannot assert lock liveness.
        return ModelInstallationReport(modelID: profile.id, status: status, diskBytes: validation.diskBytes, missingFiles: validation.missingRequiredFiles, activeLocks: evidence.lockFiles, warnings: Array(Set(warnings)).sorted()) // Returns stable deduplicated evidence.
    } // Ends reusable model audit.

    private static func transferEvidence(for profile: ModelProfile, fileManager: FileManager) -> (lockFiles: [URL], partialFiles: [URL]) { // Finds transfer markers recursively without reading file contents.
        guard let localPath = profile.localPath else { return ([], []) } // Returns no filesystem evidence for repository-only legacy profiles.
        let rootURL = URL(fileURLWithPath: localPath, isDirectory: true).standardizedFileURL // Resolves a normalized configured model root.
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsPackageDescendants]) else { return ([], []) } // Treats a missing or unreadable root as no transfer-marker evidence.
        var locks: [URL] = [] // Collects exact lock URLs below the validated root.
        var partials: [URL] = [] // Collects exact partial-transfer URLs below the validated root.
        while let url = enumerator.nextObject() as? URL { // Visits every descendant returned by FileManager.
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue } // Ignores directories and unreadable entries.
            let canonicalURL = url.standardizedFileURL // Normalizes the candidate before containment validation.
            guard canonicalURL.path.hasPrefix(rootURL.path + "/") else { continue } // Rejects any enumerator result outside the configured root.
            let lowercasedName = canonicalURL.lastPathComponent.lowercased() // Normalizes only the basename used for extension matching.
            if lowercasedName.hasSuffix(".lock") { locks.append(canonicalURL) } // Records a lock reference without mutating it.
            if lowercasedName.hasSuffix(".incomplete") || lowercasedName.hasSuffix(".part") || lowercasedName.hasSuffix(".download") { partials.append(canonicalURL) } // Records explicit partial-transfer markers.
        } // Ends recursive transfer-marker inspection.
        return (locks.sorted { $0.path < $1.path }, partials.sorted { $0.path < $1.path }) // Returns deterministic exact filesystem references.
    } // Ends transfer-evidence collection.
} // Ends the reusable installation auditor.

enum ModelInstallationInspector { // Validates model folders without network access, downloads, or file writes.
    static func validation(for profile: ModelProfile, fileManager: FileManager = .default) -> ModelInstallationValidation { // Returns structured read-only facts for one model profile.
        if profile.isLegacyFallback, profile.localPath == nil { // Preserves the repository-backed V0.1 compatibility exception.
            let identifierPresent = !profile.repositoryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty // Verifies that the existing runtime has a usable legacy reference.
            return ModelInstallationValidation(modelID: profile.id, installed: identifierPresent, completeEnoughToLaunch: identifierPresent, diskBytes: 0, missingRequiredFiles: identifierPresent ? [] : ["repository identifier"], warnings: ["Repository-backed legacy model; local cache contents are managed by the existing MLX environment."], detectedFiles: 0) // Reports the exception without pretending a local-folder size.
        } // Ends legacy validation handling.

        guard let localPath = profile.localPath, !localPath.isEmpty else { // Requires a configured path for every catalog model.
            return ModelInstallationValidation(modelID: profile.id, installed: false, completeEnoughToLaunch: false, diskBytes: 0, missingRequiredFiles: ["model directory", "config.json", "model weights"], warnings: ["No local model folder is configured."], detectedFiles: 0) // Reports missing configuration without touching the filesystem.
        } // Ends missing-path validation.

        var isDirectory: ObjCBool = false // Receives the filesystem directory flag from FileManager.
        guard fileManager.fileExists(atPath: localPath, isDirectory: &isDirectory), isDirectory.boolValue else { // Requires an existing directory.
            return ModelInstallationValidation(modelID: profile.id, installed: false, completeEnoughToLaunch: false, diskBytes: 0, missingRequiredFiles: ["model directory", "config.json", "model weights"], warnings: ["Expected local folder not found: \(localPath)"], detectedFiles: 0) // Reports the exact absent path.
        } // Ends absent-directory validation.

        let rootURL = URL(fileURLWithPath: localPath, isDirectory: true) // Creates one canonical directory URL for inspection.
        let manifest = collectManifest(rootURL: rootURL, fileManager: fileManager) // Reads only filenames and filesystem metadata.
        let lowercasedNames = manifest.files.map { $0.lowercased() } // Normalizes comparisons without changing files.
        let hasConfig = lowercasedNames.contains("config.json") // Requires the standard root transformer configuration.
        let weightNames = manifest.files.filter { $0.lowercased().hasSuffix(".safetensors") || $0.lowercased().hasSuffix(".npz") } // Accepts monolithic and sharded MLX containers.
        let hasWeights = !weightNames.isEmpty // Records whether at least one supported weight container exists.
        let hasTokenizer = lowercasedNames.contains { name in // Detects common tokenizer layouts without requiring one repository-specific name.
            let baseName = URL(fileURLWithPath: name).lastPathComponent // Restricts matching to the artifact filename.
            return baseName == "tokenizer.json" || baseName == "tokenizer.model" || baseName == "tokenizer_config.json" || baseName == "vocab.json" // Accepts JSON, SentencePiece, config-only, and vocabulary layouts.
        } // Ends tokenizer detection.
        let hasProcessor = lowercasedNames.contains { name in // Detects processor metadata required by vision-language preprocessing.
            let baseName = URL(fileURLWithPath: name).lastPathComponent // Restricts the check to the repository artifact filename.
            return baseName.contains("processor") || baseName.contains("preprocessor") // Accepts standard processor and preprocessor configuration names.
        } // Ends processor metadata detection.
        let partialFiles = lowercasedNames.filter { $0.hasSuffix(".incomplete") || $0.hasSuffix(".part") || $0.hasSuffix(".download") } // Detects explicit external partial-download markers.
        let lockFiles = lowercasedNames.filter { $0.hasSuffix(".lock") } // Detects locks as warnings only because stale Hugging Face locks can remain after completion.
        let shardProblems = indexedShardProblems(rootURL: rootURL, relativeFileNames: manifest.files, fileManager: fileManager) // Validates every filename referenced by any safetensors index.
        let invalidWeightHeaders = weightNames.filter { name in // Performs a small header-only sanity check without reading model tensors.
            let url = rootURL.appendingPathComponent(name) // Resolves the current relative weight filename.
            return name.lowercased().hasSuffix(".safetensors") && !safetensorsHeaderLooksValid(at: url) // Rejects truncated or non-safetensors files.
        } // Ends header-only validation.
        var missing: [String] = [] // Collects required artifact categories in deterministic order.
        if !hasConfig { missing.append("config.json") } // Records a missing root configuration.
        if !hasWeights { missing.append("model weights (.safetensors or .npz)") } // Records missing weights without assuming a shard filename.
        if [.mlxLM, .mlxVLM, .mlxAudio].contains(profile.backend), !hasTokenizer { missing.append("tokenizer files") } // Requires tokenizer metadata for text, VLM, and speech repositories where applicable.
        if profile.backend == .mlxVLM, !hasProcessor { missing.append("processor or preprocessor configuration") } // Requires real image preprocessing metadata before Vision launch.
        missing.append(contentsOf: shardProblems) // Records every missing or unreadable indexed shard requirement.
        missing.append(contentsOf: invalidWeightHeaders.map { "valid safetensors header: \($0)" }) // Records header-invalid containers as incomplete.
        var warnings: [String] = [] // Collects non-fatal completeness observations.
        if !partialFiles.isEmpty { warnings.append("External download markers are present: \(partialFiles.prefix(3).joined(separator: ", ")).") } // Reports bounded partial-file evidence.
        if !lockFiles.isEmpty { warnings.append("Download lock files were detected; locks alone do not prove an active transfer.") } // Avoids falsely declaring stale locks corrupt.
        if profile.backend == .mlxVLM, !hasProcessor { warnings.append("No processor or preprocessor configuration was detected.") } // Reports the same VLM-specific requirement concern in diagnostics.
        if manifest.files.isEmpty { warnings.append("The model directory exists but is empty; it may still be downloading.") } // Explains an empty externally managed folder.
        let completeEnoughToLaunch = missing.isEmpty && partialFiles.isEmpty // Requires all artifacts, indexed shards, valid headers, and no explicit partial files.
        return ModelInstallationValidation(modelID: profile.id, installed: true, completeEnoughToLaunch: completeEnoughToLaunch, diskBytes: manifest.diskBytes, missingRequiredFiles: missing, warnings: warnings, detectedFiles: manifest.files.count) // Returns immutable validation facts.
    } // Ends structured installation validation.

    static func inspect(_ profile: ModelProfile, fileManager: FileManager = .default) -> ModelProfile { // Returns a profile updated from structured facts.
        var inspected = profile // Creates a mutable value-semantic copy for registry storage.
        let result = validation(for: profile, fileManager: fileManager) // Performs the canonical read-only inspection.
        inspected.approximateDiskGB = result.diskGB // Stores measured logical folder size when available.
        if result.completeEnoughToLaunch { // Handles a complete local installation or explicit legacy exception.
            inspected.installationState = .installed // Makes the model eligible for its backend adapter.
            inspected.runtimeState = profile.runtimeState == .loaded ? .loaded : .unloaded // Preserves only an actual loaded state across refresh.
            inspected.statusDetail = result.warnings.first // Surfaces one bounded non-fatal observation when present.
        } else if !result.installed { // Handles an absent path or legacy identifier.
            inspected.installationState = .notInstalled // Distinguishes absence from a partial external download.
            inspected.runtimeState = .unavailable // Prevents routing to a missing model.
            inspected.statusDetail = (result.missingRequiredFiles + result.warnings).joined(separator: ". ") // Produces an actionable UI detail.
        } else { // Handles an existing directory not complete enough to launch.
            inspected.installationState = .downloading // Classifies the externally managed folder as downloading or incomplete.
            inspected.runtimeState = .unavailable // Prevents launch until a later refresh validates completeness.
            let missingText = result.missingRequiredFiles.isEmpty ? "" : "Missing: \(result.missingRequiredFiles.joined(separator: ", "))." // Formats required artifact gaps.
            inspected.statusDetail = ([missingText] + result.warnings).filter { !$0.isEmpty }.joined(separator: " ") // Surfaces exact incomplete-download evidence.
        } // Ends state mapping.
        return inspected // Returns the inspected model profile.
    } // Ends profile inspection.

    static func validateForLaunch(_ profile: ModelProfile, executableDirectory: String, fileManager: FileManager = .default) throws { // Revalidates mlxLM requirements immediately before a text transition.
        guard profile.enabled else { throw ModelResourceError.disabledModel(profile.displayName) } // Rejects user-disabled models.
        guard profile.backend == .mlxLM else { throw ModelResourceError.unsupportedBackend(profile.backend) } // Leaves non-text validation to backend adapters.
        let executable = URL(fileURLWithPath: executableDirectory, isDirectory: true).appendingPathComponent("mlx_lm.server").path // Builds the existing text-server executable path.
        guard fileManager.isExecutableFile(atPath: executable) else { throw ModelResourceError.executableMissing(executable) } // Rejects a missing MLX environment before stopping a working model.
        let result = validation(for: profile, fileManager: fileManager) // Rechecks local artifacts at the last responsible moment.
        guard result.completeEnoughToLaunch else { // Rejects absent or partial downloads without starting a process.
            let detail = (result.missingRequiredFiles + result.warnings).joined(separator: ". ") // Creates a bounded structured reason.
            throw ModelResourceError.invalidModel(profile.displayName, detail.isEmpty ? "Local model validation failed." : detail) // Converts validation into a fallback-compatible resource error.
        } // Ends launch completeness validation.
    } // Ends mlxLM launch validation.

    private static func collectManifest(rootURL: URL, fileManager: FileManager) -> (files: [String], diskBytes: UInt64) { // Collects only read-only manifest metadata.
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey] // Requests only attributes needed for validation and disk size.
        let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]) // Creates a recursive metadata enumerator.
        let canonicalRootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path // Normalizes macOS /var and /private/var aliases before deriving relative names.
        var files: [String] = [] // Stores directory-relative regular-file names.
        var diskBytes: UInt64 = 0 // Accumulates readable logical sizes.
        while let fileURL = enumerator?.nextObject() as? URL { // Visits each enumerated entry.
            guard let values = try? fileURL.resourceValues(forKeys: keys), values.isRegularFile == true else { continue } // Ignores directories and unreadable metadata safely.
            let canonicalFilePath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path // Applies the same canonicalization used for the model root.
            guard canonicalFilePath == canonicalRootPath || canonicalFilePath.hasPrefix(canonicalRootPath + "/") else { continue } // Rejects any enumerator result that cannot be proven inside the inspected model directory.
            let relativeName = String(canonicalFilePath.dropFirst(canonicalRootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) // Removes the canonical private absolute root from stored metadata.
            files.append(relativeName) // Records the relative name for artifact checks.
            diskBytes += UInt64(max(0, values.fileSize ?? 0)) // Adds the non-negative logical size.
        } // Ends manifest enumeration.
        return (files.sorted(), diskBytes) // Returns deterministic filenames and their total size.
    } // Ends manifest collection.

    private static func indexedShardProblems(rootURL: URL, relativeFileNames: [String], fileManager: FileManager) -> [String] { // Verifies sharded repositories using their own index declarations.
        let available = Set(relativeFileNames) // Creates constant-time exact relative-name lookup.
        var problems: [String] = [] // Collects missing shard and parse requirements.
        for indexName in relativeFileNames where indexName.lowercased().hasSuffix(".safetensors.index.json") { // Visits every safetensors index regardless of model-specific shard count.
            let indexURL = rootURL.appendingPathComponent(indexName) // Resolves the small JSON index file.
            guard let data = try? Data(contentsOf: indexURL), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let weightMap = object["weight_map"] as? [String: String] else { // Parses only the declared weight map.
                problems.append("readable shard index: \(indexName)") // Prevents launch when an index cannot be interpreted safely.
                continue // Continues checking other independent index files.
            } // Ends shard-index parsing.
            let indexDirectory = (indexName as NSString).deletingLastPathComponent // Preserves a relative nested component folder without converting a root-level index into an absolute slash.
            for shardName in Set(weightMap.values).sorted() { // Validates each referenced shard exactly once.
                let relativeShard = indexDirectory == "." || indexDirectory.isEmpty ? shardName : "\(indexDirectory)/\(shardName)" // Reconstructs the repository-relative shard path.
                if !available.contains(relativeShard) { problems.append("indexed weight shard: \(relativeShard)") } // Records each declared but absent physical shard.
            } // Ends referenced-shard validation.
        } // Ends index iteration.
        return problems // Returns deterministic indexed-shard requirements.
    } // Ends sharded-weight validation.

    private static func safetensorsHeaderLooksValid(at url: URL) -> Bool { // Performs a bounded header sanity check without reading tensor data.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path), let number = attributes[.size] as? NSNumber else { return false } // Requires readable size metadata.
        let fileSize = number.uint64Value // Stores the physical container size.
        guard fileSize > 8, let handle = try? FileHandle(forReadingFrom: url) else { return false } // Requires the eight-byte header-length prefix and readable file.
        defer { try? handle.close() } // Closes the read-only handle deterministically.
        let prefix = handle.readData(ofLength: 8) // Reads only the safetensors header-length prefix.
        guard prefix.count == 8 else { return false } // Rejects a truncated prefix.
        let headerLength = prefix.withUnsafeBytes { rawBuffer -> UInt64 in rawBuffer.loadUnaligned(as: UInt64.self).littleEndian } // Decodes the format's little-endian header length safely.
        return headerLength > 1 && headerLength < fileSize - 8 // Requires the declared JSON header to fit within the existing container.
    } // Ends bounded safetensors header validation.
} // Ends deterministic installation inspection.
