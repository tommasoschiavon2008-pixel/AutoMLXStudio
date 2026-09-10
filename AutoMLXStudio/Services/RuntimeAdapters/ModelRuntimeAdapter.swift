import Foundation // Supplies filesystem URLs, localized errors, and value semantics for runtime discovery.

enum ModelResourceClass: String, Codable, CaseIterable, Sendable { // Groups backends by the unified-memory ownership policy enforced by ModelResourceManager.
    case largeText // Identifies a medium or large text model that must remain the only resident large text runtime.
    case largeVision // Identifies a vision-language model that requires centrally coordinated large-model ownership.
    case smallAudio // Identifies ASR or TTS resources that still require central ownership despite their smaller footprint.
    case embedding // Reserves a centrally managed class for a later embedding milestone.
    case reranker // Reserves a centrally managed class for a later reranking milestone.
} // Ends the model resource-class definition.

struct RuntimeDependencyStatus: Equatable, Sendable { // Describes read-only runtime discovery without changing the Python environment.
    let backend: ModelBackend // Identifies the backend whose dependency was inspected.
    let isAvailable: Bool // Indicates whether a usable executable or importable module location was discovered.
    let executablePaths: [String] // Records matching executable entrypoints found under the configured environment bin directory.
    let modulePaths: [String] // Records matching Python package directories found under the configured environment library directory.
    let detail: String // Supplies a bounded user-facing explanation of availability or the exact missing dependency.
} // Ends runtime dependency-status metadata.

enum ModelRuntimeAdapterError: LocalizedError, Equatable, Sendable { // Defines validation failures shared by backend-specific adapters.
    case backendMismatch(expected: ModelBackend, actual: ModelBackend) // Rejects dispatching a model through an adapter for another backend.
    case disabledModel(String) // Rejects a model that the user disabled in the central registry.
    case incompleteInstallation(String, String) // Rejects a model that failed the existing read-only installation inspection.
    case missingDependency(ModelBackend, String) // Rejects a backend whose optional runtime dependency is not discoverable.

    var errorDescription: String? { // Produces concise diagnostics suitable for Models UI and workflow traces.
        switch self { // Selects the stable diagnostic for the current validation failure.
        case let .backendMismatch(expected, actual): return "Runtime adapter expected \(expected.displayName), but the model requires \(actual.displayName)." // Explains incorrect adapter dispatch.
        case let .disabledModel(name): return "\(name) is disabled." // Explains an explicit user configuration block.
        case let .incompleteInstallation(name, detail): return "\(name) is unavailable: \(detail)" // Preserves the existing installation diagnostic.
        case let .missingDependency(backend, detail): return "\(backend.displayName) runtime unavailable: \(detail)" // Explains an optional environment dependency gap.
        } // Ends runtime-adapter error selection.
    } // Ends localized runtime-adapter error access.
} // Ends runtime-adapter validation errors.

protocol ModelRuntimeAdapter: Sendable { // Defines dependency and validation boundaries while leaving all load ownership with ModelResourceManager.
    var backend: ModelBackend { get } // Identifies the single backend implemented by this adapter.
    var resourceClass: ModelResourceClass { get } // Identifies the central unified-memory policy class for this backend.
    func dependencyStatus(configuration: ModelRuntimeConfiguration) -> RuntimeDependencyStatus // Discovers optional runtime support through read-only filesystem inspection.
    func validate(model: ModelProfile, configuration: ModelRuntimeConfiguration) async throws // Validates backend, installation, enablement, and dependency readiness without starting a process.
} // Ends the backend-specific runtime adapter contract.

struct MLXLMRuntimeAdapter: ModelRuntimeAdapter { // Describes the existing text runtime without duplicating its proven process implementation.
    let backend: ModelBackend = .mlxLM // Binds this adapter to the existing MLX LM backend.
    let resourceClass: ModelResourceClass = .largeText // Keeps medium and large text models under the one-at-a-time policy.

    func dependencyStatus(configuration: ModelRuntimeConfiguration) -> RuntimeDependencyStatus { // Checks the exact executable already used by MLXService.
        let executable = URL(fileURLWithPath: configuration.executableDirectory, isDirectory: true).appendingPathComponent("mlx_lm.server").path // Resolves the configured MLX LM server entrypoint.
        let available = FileManager.default.isExecutableFile(atPath: executable) // Requires an executable file rather than merely an existing path.
        let detail = available ? "mlx_lm.server is available." : "Expected executable not found: \(executable)" // Reports the exact read-only discovery result.
        return RuntimeDependencyStatus(backend: backend, isAvailable: available, executablePaths: available ? [executable] : [], modulePaths: [], detail: detail) // Returns immutable dependency metadata.
    } // Ends MLX LM dependency discovery.

    func validate(model: ModelProfile, configuration: ModelRuntimeConfiguration) async throws { // Validates a text model without loading or starting it.
        try RuntimeAdapterValidation.validate(model: model, expectedBackend: backend, dependency: dependencyStatus(configuration: configuration)) // Reuses the shared non-mutating validation boundary.
    } // Ends MLX LM model validation.
} // Ends the existing text runtime adapter.

struct MLXVLMRuntimeAdapter: ModelRuntimeAdapter { // Describes optional vision runtime availability without assuming a command-line API.
    let backend: ModelBackend = .mlxVLM // Binds this adapter to MLX vision-language models.
    let resourceClass: ModelResourceClass = .largeVision // Gives vision models their own centrally coordinated large-resource class.

    func dependencyStatus(configuration: ModelRuntimeConfiguration) -> RuntimeDependencyStatus { // Searches for an installed mlx-vlm module or entrypoint without launching Python.
        RuntimeDependencyDiscovery.status(backend: backend, moduleName: "mlx_vlm", configuration: configuration) // Delegates bounded environment layout discovery.
    } // Ends MLX VLM dependency discovery.

    func validate(model: ModelProfile, configuration: ModelRuntimeConfiguration) async throws { // Validates a vision model without inventing CLI arguments or starting inference.
        try RuntimeAdapterValidation.validate(model: model, expectedBackend: backend, dependency: dependencyStatus(configuration: configuration)) // Reuses the shared non-mutating validation boundary.
    } // Ends MLX VLM model validation.
} // Ends the optional vision runtime adapter.

struct MLXAudioRuntimeAdapter: ModelRuntimeAdapter { // Describes optional ASR and TTS runtime availability without coupling audio to the text server.
    let backend: ModelBackend = .mlxAudio // Binds this adapter to MLX audio models.
    let resourceClass: ModelResourceClass = .smallAudio // Keeps audio resources visible to the same central ownership authority.

    func dependencyStatus(configuration: ModelRuntimeConfiguration) -> RuntimeDependencyStatus { // Searches for an installed mlx-audio module or entrypoint without launching Python.
        RuntimeDependencyDiscovery.status(backend: backend, moduleName: "mlx_audio", configuration: configuration) // Delegates bounded environment layout discovery.
    } // Ends MLX Audio dependency discovery.

    func validate(model: ModelProfile, configuration: ModelRuntimeConfiguration) async throws { // Validates an audio model without inventing CLI arguments or starting inference.
        try RuntimeAdapterValidation.validate(model: model, expectedBackend: backend, dependency: dependencyStatus(configuration: configuration)) // Reuses the shared non-mutating validation boundary.
    } // Ends MLX Audio model validation.
} // Ends the optional audio runtime adapter.

struct ModelRuntimeAdapterRegistry: Sendable { // Centralizes backend adapter lookup for the sole owning ModelResourceManager.
    private let adapters: [ModelBackend: any ModelRuntimeAdapter] // Stores one immutable Sendable adapter per supported runtime backend.

    init(adapters: [any ModelRuntimeAdapter] = [MLXLMRuntimeAdapter(), MLXVLMRuntimeAdapter(), MLXAudioRuntimeAdapter()]) { // Registers the current text, vision, and audio runtime boundaries by default.
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.backend, $0) }) // Builds deterministic backend lookup and rejects duplicate registrations during development.
    } // Ends runtime-adapter registry construction.

    func adapter(for backend: ModelBackend) -> (any ModelRuntimeAdapter)? { // Resolves the adapter owned by the central resource manager.
        adapters[backend] // Returns nil for deliberately unimplemented embedding and reranking backends.
    } // Ends backend adapter lookup.

    func dependencyStatuses(configuration: ModelRuntimeConfiguration) -> [RuntimeDependencyStatus] { // Produces stable Models UI dependency diagnostics for every registered backend.
        [ModelBackend.mlxLM, .mlxVLM, .mlxAudio].compactMap { adapters[$0]?.dependencyStatus(configuration: configuration) } // Preserves a predictable text, vision, then audio order.
    } // Ends registry-wide dependency discovery.
} // Ends the central runtime-adapter registry.

private enum RuntimeAdapterValidation { // Shares side-effect-free adapter checks without exposing another ownership surface.
    static func validate(model: ModelProfile, expectedBackend: ModelBackend, dependency: RuntimeDependencyStatus) throws { // Validates one model at the adapter boundary.
        guard model.backend == expectedBackend else { throw ModelRuntimeAdapterError.backendMismatch(expected: expectedBackend, actual: model.backend) } // Prevents cross-backend execution.
        guard model.enabled else { throw ModelRuntimeAdapterError.disabledModel(model.displayName) } // Honors the central registry enablement choice.
        let inspected = ModelInstallationInspector.inspect(model) // Reuses the current read-only installation inspection until structured validation replaces it.
        guard inspected.installationState == .installed else { throw ModelRuntimeAdapterError.incompleteInstallation(model.displayName, inspected.statusDetail ?? "Local installation validation failed.") } // Rejects absent or incomplete local resources.
        guard dependency.isAvailable else { throw ModelRuntimeAdapterError.missingDependency(expectedBackend, dependency.detail) } // Rejects an optional backend that is not installed in the configured environment.
    } // Ends shared adapter validation.
} // Ends shared runtime-adapter validation helpers.

private enum RuntimeDependencyDiscovery { // Performs bounded read-only discovery of optional Python modules and entrypoints.
    static func status(backend: ModelBackend, moduleName: String, configuration: ModelRuntimeConfiguration) -> RuntimeDependencyStatus { // Inspects one configured virtual environment without executing Python.
        let fileManager = FileManager.default // Uses the system file manager only for metadata and directory reads.
        let binURL = URL(fileURLWithPath: configuration.executableDirectory, isDirectory: true) // Resolves the configured virtual-environment executable directory.
        let executablePaths = discoverEntrypoints(moduleName: moduleName, binURL: binURL, fileManager: fileManager) // Finds matching executable wrappers without assuming their arguments.
        let environmentRoot = binURL.deletingLastPathComponent() // Resolves the virtual-environment root from its conventional bin directory.
        let modulePaths = discoverModules(moduleName: moduleName, environmentRoot: environmentRoot, fileManager: fileManager) // Finds import package directories under conventional site-packages layouts.
        let available = !executablePaths.isEmpty || !modulePaths.isEmpty // Accepts either discoverable package form as requested.
        let packageName = moduleName.replacingOccurrences(of: "_", with: "-") // Produces the standard distribution spelling for diagnostics.
        let detail = available ? "\(packageName) was discovered in the configured environment." : "Install \(packageName) in the configured MLX environment; no module or entrypoint was found." // Reports availability without modifying the environment.
        return RuntimeDependencyStatus(backend: backend, isAvailable: available, executablePaths: executablePaths, modulePaths: modulePaths, detail: detail) // Returns immutable discovery evidence.
    } // Ends optional runtime dependency discovery.

    private static func discoverEntrypoints(moduleName: String, binURL: URL, fileManager: FileManager) -> [String] { // Finds executable wrappers whose names belong to the optional package.
        let names = (try? fileManager.contentsOfDirectory(atPath: binURL.path)) ?? [] // Reads only direct bin-directory entries and treats an absent directory as empty.
        return names.filter { $0 == moduleName || $0.hasPrefix("\(moduleName).") || $0.hasPrefix("\(moduleName)-") }.map { binURL.appendingPathComponent($0).path }.filter { fileManager.isExecutableFile(atPath: $0) }.sorted() // Returns only executable matching entrypoints in stable order.
    } // Ends optional entrypoint discovery.

    private static func discoverModules(moduleName: String, environmentRoot: URL, fileManager: FileManager) -> [String] { // Finds conventional Python package directories without importing them.
        let libURL = environmentRoot.appendingPathComponent("lib", isDirectory: true) // Resolves the virtual environment's library directory.
        let pythonDirectories = ((try? fileManager.contentsOfDirectory(at: libURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []).filter { $0.lastPathComponent.hasPrefix("python") } // Finds versioned Python library directories read-only.
        return pythonDirectories.map { $0.appendingPathComponent("site-packages", isDirectory: true).appendingPathComponent(moduleName, isDirectory: true) }.filter { fileManager.fileExists(atPath: $0.path) }.map(\.path).sorted() // Returns existing module directories in stable order.
    } // Ends optional Python module discovery.
} // Ends read-only runtime dependency discovery.
