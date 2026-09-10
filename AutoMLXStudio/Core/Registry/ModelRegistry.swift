import Foundation // Supplies Codable persistence and deterministic collection support.

struct ModelRegistry: Codable, Equatable { // Owns the persisted V0.2 catalog, assignments, preferences, and legacy migration.
    private(set) var models: [ModelProfile] // Preserves stable catalog order while allowing controlled mutation.
    private(set) var assignments: [ModelAssignment] // Stores all agent-to-model choices outside AgentDefinition.
    private(set) var capabilityPreferences: [ModelCapabilityPreference] // Stores optional user defaults per capability.
    private(set) var legacyFallbackModelID: String // Identifies the migrated V0.1 compatibility model.
    var modelsRoot: String // Stores the offline folder used for deterministic installation detection.

    init() { // Preserves the V0.1 source-compatible registry constructor used by existing integration tests.
        self = Self.defaultRegistry(legacyIdentifier: "mlx-community/Llama-3.2-3B-Instruct-4bit") // Builds the complete V0.2 catalog around the prior default fallback.
    } // Ends the V0.1 compatibility constructor.

    init( // Creates an explicit registry value for application bootstrap and tests.
        models: [ModelProfile], // Accepts registered physical model profiles.
        assignments: [ModelAssignment], // Accepts persisted agent assignments.
        capabilityPreferences: [ModelCapabilityPreference] = [], // Accepts optional capability defaults.
        legacyFallbackModelID: String, // Accepts the final V0.1 fallback identifier.
        modelsRoot: String = Project5ModelCatalog.defaultRoot // Uses the requested Project 5 folder by default.
    ) { // Starts registry construction.
        self.models = models // Stores registered models in stable display order.
        self.assignments = assignments // Stores agent assignments separately from agent definitions.
        self.capabilityPreferences = capabilityPreferences // Stores user capability preferences.
        self.legacyFallbackModelID = legacyFallbackModelID // Stores the V0.1 compatibility key.
        self.modelsRoot = modelsRoot // Stores the offline detection root.
    } // Ends registry construction.

    static func defaultRegistry(legacyIdentifier: String, modelsRoot: String = Project5ModelCatalog.defaultRoot) -> ModelRegistry { // Builds the complete V0.2 catalog without downloads.
        let normalizedLegacy = normalized(identifier: legacyIdentifier) // Removes accidental whitespace from the persisted V0.1 setting.
        var registry = ModelRegistry( // Creates the base registry before legacy migration and filesystem inspection.
            models: defaultCatalog(modelsRoot: modelsRoot), // Registers all V0.2, V0.3, and V0.4 catalog entries.
            assignments: defaultAssignments(), // Registers the recommended per-agent mapping and legacy fallbacks.
            capabilityPreferences: [], // Leaves user capability preferences unset initially.
            legacyFallbackModelID: normalizedLegacy, // Preserves the exact working V0.1 identifier.
            modelsRoot: modelsRoot // Stores the configured offline catalog root.
        ) // Ends base registry creation.
        registry.ensureLegacyFallback(identifier: normalizedLegacy) // Adds or marks the working V0.1 model without losing catalog entries.
        registry.refreshInstallationStates() // Detects installed folders without requiring internet access.
        return registry // Returns the complete first-launch V0.2 registry.
    } // Ends default-registry creation.

    static func migrated(_ persisted: ModelRegistry?, legacyIdentifier: String, modelsRoot: String = Project5ModelCatalog.defaultRoot) -> ModelRegistry { // Merges persisted user choices with newly introduced catalog entries.
        guard var registry = persisted else { return defaultRegistry(legacyIdentifier: legacyIdentifier, modelsRoot: modelsRoot) } // Uses first-launch defaults when no V0.2 state exists.
        registry.modelsRoot = registry.modelsRoot.isEmpty ? modelsRoot : registry.modelsRoot // Repairs older or manually edited state without a model root.
        registry.migrateDeprecatedCatalogEntries() // Replaces obsolete V0.2 Vision and TTS placeholders without touching physical model folders.
        for profile in defaultCatalog(modelsRoot: registry.modelsRoot) where registry.model(id: profile.id) == nil { registry.register(profile) } // Adds future catalog entries without overwriting user edits.
        for assignment in defaultAssignments() where registry.assignment(for: assignment.agentID) == nil { registry.setAssignment(assignment) } // Adds missing assignments without overwriting user choices.
        registry.ensureLegacyFallback(identifier: legacyIdentifier) // Updates the compatibility fallback to the current legacy setting.
        registry.refreshInstallationStates() // Resets stale loaded states and inspects local folders on launch.
        return registry // Returns the reconciled persisted registry.
    } // Ends persisted-registry migration.

    mutating func register(_ profile: ModelProfile) { // Registers a new physical model or replaces a profile with the same stable ID.
        if let index = models.firstIndex(where: { $0.id == profile.id }) { models[index] = profile } else { models.append(profile) } // Performs deterministic upsert behavior.
    } // Ends model registration.

    mutating func update(_ profile: ModelProfile) { // Updates an existing registered model without exposing array mutation.
        register(profile) // Reuses the single stable upsert rule.
    } // Ends model update.

    mutating func remove(id: String) { // Removes a user-removable profile and dependent direct preferences.
        guard id != legacyFallbackModelID else { return } // Protects the required V0.1 compatibility fallback from accidental deletion.
        models.removeAll { $0.id == id } // Removes the matching physical model profile.
        capabilityPreferences.removeAll { $0.modelID == id } // Removes capability preferences that would otherwise reference a missing model.
        for index in assignments.indices { // Visits each assignment to remove stale references.
            if assignments[index].preferredModelID == id { assignments[index].preferredModelID = nil } // Clears a removed preferred model.
            assignments[index].fallbackModelIDs.removeAll { $0 == id } // Clears removed fallback references.
        } // Ends dependent assignment cleanup.
    } // Ends model removal.

    func model(id: String) -> ModelProfile? { // Looks up one registered model by stable identifier.
        models.first { $0.id == id } // Returns the first exact registry match.
    } // Ends model lookup.

    func models(supporting capabilities: Set<ModelCapability>, backends: Set<ModelBackend> = [.mlxLM], enabledOnly: Bool = true, installedOnly: Bool = true) -> [ModelProfile] { // Finds compatible models within explicitly permitted runtime backends.
        models.filter { profile in // Evaluates every registered profile in stable order.
            let enabledMatch = !enabledOnly || profile.enabled // Applies optional enabled-state filtering.
            let installedMatch = !installedOnly || profile.installationState == .installed // Applies optional installation filtering.
            return enabledMatch && installedMatch && backends.contains(profile.backend) && capabilities.isSubset(of: profile.capabilities) // Requires an allowed backend and every declared capability.
        } // Ends compatible model filtering.
    } // Ends capability lookup.

    func assignment(for agentID: String) -> ModelAssignment? { // Looks up one agent's persisted model assignment.
        assignments.first { $0.agentID == agentID } // Returns the first exact agent-key match.
    } // Ends assignment lookup.

    mutating func setAssignment(_ assignment: ModelAssignment) { // Persists an assignment without embedding it in AgentDefinition.
        if let index = assignments.firstIndex(where: { $0.agentID == assignment.agentID }) { assignments[index] = assignment } else { assignments.append(assignment) } // Performs deterministic assignment upsert.
    } // Ends assignment update.

    mutating func setPreferredModel(_ modelID: String?, forAgent agentID: String) { // Updates only one agent's preferred physical model.
        guard let index = assignments.firstIndex(where: { $0.agentID == agentID }) else { return } // Ignores unknown agent identifiers safely.
        assignments[index].preferredModelID = modelID // Stores the optional compatible preference.
    } // Ends agent preference update.

    func preferredModelID(for capability: ModelCapability) -> String? { // Looks up the user's preferred model for a capability.
        capabilityPreferences.first { $0.capability == capability }?.modelID // Returns the exact configured preference when present.
    } // Ends capability preference lookup.

    mutating func setPreferredModel(_ modelID: String, for capability: ModelCapability) { // Updates a capability-level default independently from agents.
        let preference = ModelCapabilityPreference(capability: capability, modelID: modelID) // Creates the complete persisted preference value.
        if let index = capabilityPreferences.firstIndex(where: { $0.capability == capability }) { capabilityPreferences[index] = preference } else { capabilityPreferences.append(preference) } // Performs deterministic preference upsert.
    } // Ends capability preference update.

    mutating func setEnabled(_ enabled: Bool, modelID: String) { // Changes whether deterministic routing may select a model.
        guard let index = models.firstIndex(where: { $0.id == modelID }) else { return } // Ignores stale UI identifiers safely.
        models[index].enabled = enabled // Stores the user-selected routing availability.
    } // Ends enabled-state update.

    mutating func setLocalPath(_ path: String?, modelID: String) { // Stores a manually selected offline model folder.
        guard let index = models.firstIndex(where: { $0.id == modelID }) else { return } // Ignores unknown model identifiers safely.
        models[index].localPath = path // Stores or clears the explicit local path.
        refreshInstallationState(at: index) // Immediately validates the selected folder for clear UI feedback.
    } // Ends local-path update.

    mutating func updateRuntimeState(modelID: String, state: ModelRuntimeState, detail: String? = nil) { // Mirrors resource-manager lifecycle state into observable application state.
        guard let index = models.firstIndex(where: { $0.id == modelID }) else { return } // Ignores runtime updates for removed models safely.
        models[index].runtimeState = state // Stores the latest lifecycle state.
        models[index].statusDetail = detail // Stores an optional bounded runtime diagnostic.
    } // Ends runtime-state update.

    mutating func applyRuntimeSnapshot(_ snapshot: ModelResourceSnapshot) { // Reconciles all model badges with the actor's authoritative lifecycle snapshot.
        for index in models.indices { // Visits every registered profile exactly once.
            if let state = snapshot.states[models[index].id] { models[index].runtimeState = state } // Applies actor state when it exists.
            else if models[index].installationState == .installed { models[index].runtimeState = .unloaded } // Resets usable non-active models deterministically.
            else { models[index].runtimeState = .unavailable } // Keeps absent models visibly unavailable.
        } // Ends snapshot state reconciliation.
        if let activeModelID = snapshot.activeModelID, let index = models.firstIndex(where: { $0.id == activeModelID }) { models[index].runtimeState = .loaded } // Guarantees exactly one loaded badge when the actor reports an active model.
    } // Ends runtime snapshot application.

    mutating func refreshInstallationStates() { // Re-inspects every expected local folder without network access.
        for index in models.indices { refreshInstallationState(at: index) } // Applies the same deterministic validation to each catalog entry.
    } // Ends registry-wide installation refresh.

    mutating func ensureLegacyFallback(identifier: String) { // Migrates or updates the current V0.1 model as the final compatibility fallback.
        let normalized = Self.normalized(identifier: identifier) // Removes setting whitespace before identity comparison.
        guard !normalized.isEmpty else { return } // Preserves the prior valid fallback when the text field is temporarily empty.
        if legacyFallbackModelID != normalized, let oldIndex = models.firstIndex(where: { $0.id == legacyFallbackModelID && $0.isLegacyFallback }) { models[oldIndex].isLegacyFallback = false } // Unmarks a previous migrated fallback without deleting a catalog profile.
        legacyFallbackModelID = normalized // Stores the current persisted V0.1 identifier.
        if let index = models.firstIndex(where: { $0.id == normalized }) { // Reuses a matching catalog profile when possible.
            models[index].isLegacyFallback = true // Marks the matching profile as the final compatibility fallback.
            models[index].enabled = true // Ensures backward compatibility cannot be disabled by first-launch defaults.
            if models[index].installationState != .installed { models[index].installationState = .installed } // Trusts the previously working V0.1 repository/cache path for migration.
            if models[index].runtimeState == .unavailable { models[index].runtimeState = .unloaded } // Makes the migrated working model routable.
        } else { // Adds a dedicated profile for a legacy identifier outside the catalog.
            let displayName = normalized.split(separator: "/").last.map(String.init) ?? normalized // Derives a concise label without losing the repository identity.
            models.append(ModelProfile( // Registers the migrated V0.1 model after the catalog entries.
                id: normalized, // Uses the exact legacy identifier as the stable key.
                displayName: displayName.isEmpty ? "Legacy MLX Model" : displayName, // Supplies a safe label for unusual local references.
                repositoryID: normalized, // Preserves the working repository or path setting.
                localPath: normalized.hasPrefix("/") ? normalized : nil, // Treats an absolute legacy value as a local folder.
                backend: .mlxLM, // Preserves the existing text-server backend.
                capabilities: [.general, .reasoning, .coding, .swiftLanguage, .research], // Preserves all V0.1 agent compatibility.
                approximateDiskGB: nil, // Leaves disk size unknown until a local folder can be inspected.
                approximateMemoryGB: nil, // Leaves memory size unknown for user-provided legacy models.
                enabled: true, // Keeps the proven V0.1 fallback selectable.
                installationState: .installed, // Trusts the current working configuration during migration.
                runtimeState: .unloaded, // Starts without assuming a server process survived relaunch.
                isLegacyFallback: true, // Marks this profile as final routing recovery.
                statusDetail: "Migrated from the V0.1 model setting." // Explains why a repository-only model is considered available.
            )) // Ends migrated legacy profile creation.
        } // Ends catalog reuse or legacy-profile creation.
    } // Ends V0.1 fallback migration.

    func mainModel(identifier: String) -> LLMModel { // Preserves the V0.1 source-compatible single-model adapter used by existing tests and tools.
        let normalizedIdentifier = Self.normalized(identifier: identifier) // Removes accidental setting whitespace.
        if let profile = model(id: normalizedIdentifier) { return profile.completionModel } // Reuses a registered profile when available.
        let displayName = normalizedIdentifier.split(separator: "/").last.map(String.init) ?? normalizedIdentifier // Derives a concise compatibility label.
        return LLMModel(id: normalizedIdentifier, name: displayName.isEmpty ? "Configured MLX Model" : displayName, repository: normalizedIdentifier, capabilities: [.general, .reasoning, .coding, .swiftLanguage, .research]) // Preserves every V0.1 agent capability.
    } // Ends V0.1 model adaptation.

    private mutating func refreshInstallationState(at index: Int) { // Applies offline validation to one mutable model profile.
        let inspected = ModelInstallationInspector.inspect(models[index]) // Delegates filesystem details to a deterministic service.
        models[index] = inspected // Stores installation, disk, runtime, and diagnostic results atomically.
    } // Ends single-profile installation refresh.

    private static func normalized(identifier: String) -> String { // Normalizes persisted model settings consistently.
        identifier.trimmingCharacters(in: .whitespacesAndNewlines) // Removes leading and trailing whitespace only.
    } // Ends identifier normalization.

    private mutating func migrateDeprecatedCatalogEntries() { // Reconciles corrected V0.3 repository identities in persisted V0.2 state.
        let replacements: [(oldID: String, newID: String)] = [(Project5ModelCatalog.deprecatedVision, Project5ModelCatalog.vision), (Project5ModelCatalog.deprecatedTextToSpeech, Project5ModelCatalog.textToSpeech)] // Declares the two exact catalog identity migrations.
        let currentDefaults = Self.defaultCatalog(modelsRoot: modelsRoot) // Builds corrected profiles using the persisted model root.
        for replacement in replacements { // Migrates each obsolete catalog entry independently.
            guard let oldProfile = model(id: replacement.oldID), !oldProfile.isLegacyFallback else { continue } // Leaves absent entries and an explicitly chosen legacy fallback untouched.
            if model(id: replacement.newID) == nil, var newProfile = currentDefaults.first(where: { $0.id == replacement.newID }) { // Creates the corrected profile only when not already present.
                newProfile.enabled = oldProfile.enabled // Preserves the user's prior enable or disable choice.
                register(newProfile) // Adds the corrected repository and expected physical folder.
            } // Ends corrected-profile creation.
            for index in assignments.indices { // Repairs any manually persisted agent references to the obsolete identifier.
                if assignments[index].preferredModelID == replacement.oldID { assignments[index].preferredModelID = replacement.newID } // Migrates a direct preferred-model reference.
                assignments[index].fallbackModelIDs = assignments[index].fallbackModelIDs.map { $0 == replacement.oldID ? replacement.newID : $0 } // Migrates declared fallback references while preserving order.
            } // Ends assignment migration.
            for index in capabilityPreferences.indices where capabilityPreferences[index].modelID == replacement.oldID { capabilityPreferences[index].modelID = replacement.newID } // Migrates capability-level preferences.
            models.removeAll { $0.id == replacement.oldID } // Removes only the obsolete registry profile, never its external folder.
        } // Ends catalog identity migration.
    } // Ends deprecated-catalog migration.

    private static func localPath(repositoryID: String, root: String) -> String { // Maps a repository to the requested deterministic offline folder.
        let lastComponent = repositoryID.split(separator: "/").last.map(String.init) ?? repositoryID // Uses the repository name as the human-readable folder base.
        let sanitized = lastComponent.map { character -> Character in // Replaces filesystem-unfriendly characters deterministically.
            character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." ? character : "-" // Preserves safe characters and replaces every other character.
        } // Ends folder-name sanitization.
        return URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(String(sanitized), isDirectory: true).path // Produces an absolute expected local folder.
    } // Ends repository-to-folder mapping.

    private static func defaultCatalog(modelsRoot: String) -> [ModelProfile] { // Defines every requested physical model without downloading it.
        [ // Starts the stable catalog displayed in Models UI.
            catalogProfile(id: Project5ModelCatalog.general, name: "Qwen3 8B 4-bit", backend: .mlxLM, capabilities: [.general, .reasoning, .research], memoryGB: 5.5, enabled: true, root: modelsRoot), // Registers general and composition text work.
            catalogProfile(id: Project5ModelCatalog.coding, name: "Qwen2.5 Coder 7B 4-bit", backend: .mlxLM, capabilities: [.general, .reasoning, .coding, .swiftLanguage], memoryGB: 5.0, enabled: true, root: modelsRoot), // Registers coding and Swift work.
            catalogProfile(id: Project5ModelCatalog.reasoning, name: "DeepSeek R1 Qwen3 8B 4-bit", backend: .mlxLM, capabilities: [.general, .reasoning], memoryGB: 5.5, enabled: true, root: modelsRoot), // Registers review and difficult reasoning work.
            catalogProfile(id: Project5ModelCatalog.translation, name: "TranslateGemma 4B 4-bit", backend: .mlxLM, capabilities: [.general, .translation], memoryGB: 3.0, enabled: true, root: modelsRoot), // Registers future translation work without adding an agent yet.
            catalogProfile(id: Project5ModelCatalog.vision, name: "Qwen3 VL 8B Instruct 4-bit", backend: .mlxVLM, capabilities: [.general, .reasoning, .vision], memoryGB: 6.5, enabled: true, root: modelsRoot), // Registers the V0.3 Vision model while adapter availability still gates execution.
            catalogProfile(id: Project5ModelCatalog.speechToText, name: "Qwen3 ASR 0.6B", backend: .mlxAudio, capabilities: [.speechToText, .audioAnalysis], memoryGB: 0.8, enabled: true, root: modelsRoot), // Registers the V0.3 speech-recognition model while adapter availability gates execution.
            catalogProfile(id: Project5ModelCatalog.textToSpeech, name: "Qwen3 TTS 1.7B 6-bit", backend: .mlxAudio, capabilities: [.textToSpeech, .audioAnalysis], memoryGB: 2.8, enabled: true, root: modelsRoot), // Registers the downloaded six-bit V0.3 speech-synthesis model.
            catalogProfile(id: Project5ModelCatalog.embedding, name: "Qwen3 Embedding 0.6B", backend: .embedding, capabilities: [.embedding], memoryGB: 0.6, enabled: false, root: modelsRoot), // Registers but disables future V0.4 embeddings.
            catalogProfile(id: Project5ModelCatalog.reranker, name: "Qwen3 Reranker 0.6B", backend: .reranker, capabilities: [.reranking], memoryGB: 0.6, enabled: false, root: modelsRoot) // Registers but disables future V0.4 reranking.
        ] // Ends the stable default model catalog.
    } // Ends default-catalog creation.

    private static func catalogProfile(id: String, name: String, backend: ModelBackend, capabilities: Set<ModelCapability>, memoryGB: Double?, enabled: Bool, root: String) -> ModelProfile { // Creates consistent not-yet-downloaded catalog entries.
        ModelProfile(id: id, displayName: name, repositoryID: id, localPath: localPath(repositoryID: id, root: root), backend: backend, capabilities: capabilities, approximateDiskGB: nil, approximateMemoryGB: memoryGB, enabled: enabled, installationState: .notInstalled, runtimeState: .unavailable, isLegacyFallback: false, statusDetail: "Expected local folder not found.") // Returns the complete offline-first profile.
    } // Ends catalog-profile construction.

    private static func defaultAssignments() -> [ModelAssignment] { // Defines the requested initial model-per-agent mapping.
        [ // Starts stable agent assignment order matching AgentRegistry.
            ModelAssignment(agentID: AgentID.general, preferredModelID: Project5ModelCatalog.general, preferredCapability: .general, fallbackModelIDs: [Project5ModelCatalog.reasoning], fallbackCapabilities: [.general], allowsRuntimeReuse: true), // Assigns General Agent to Qwen3 with the reasoning model as an explicit alternative.
            ModelAssignment(agentID: AgentID.coding, preferredModelID: Project5ModelCatalog.coding, preferredCapability: .coding, fallbackModelIDs: [], fallbackCapabilities: [.coding], allowsRuntimeReuse: true), // Assigns Coding Agent to Qwen Coder before compatible or legacy recovery.
            ModelAssignment(agentID: AgentID.engineering, preferredModelID: Project5ModelCatalog.coding, preferredCapability: .coding, fallbackModelIDs: [], fallbackCapabilities: [.coding, .reasoning], allowsRuntimeReuse: true), // Keeps V0.6 engineering local-first until the user explicitly assigns a compatible configured remote model.
            ModelAssignment(agentID: AgentID.swift, preferredModelID: Project5ModelCatalog.coding, preferredCapability: .swiftLanguage, fallbackModelIDs: [], fallbackCapabilities: [.swiftLanguage, .coding], allowsRuntimeReuse: true), // Assigns Swift Agent to the same Qwen Coder model.
            ModelAssignment(agentID: AgentID.research, preferredModelID: Project5ModelCatalog.general, preferredCapability: .research, fallbackModelIDs: [], fallbackCapabilities: [.research, .general], allowsRuntimeReuse: true), // Assigns Research Agent to Qwen3 before compatible or legacy recovery.
            ModelAssignment(agentID: AgentID.python, preferredModelID: Project5ModelCatalog.coding, preferredCapability: .coding, fallbackModelIDs: [], fallbackCapabilities: [.coding], allowsRuntimeReuse: true), // Shares the installed coding model with the logical Python specialist.
            ModelAssignment(agentID: AgentID.cAndCpp, preferredModelID: Project5ModelCatalog.coding, preferredCapability: .coding, fallbackModelIDs: [], fallbackCapabilities: [.coding], allowsRuntimeReuse: true), // Shares the installed coding model with the logical C/C++ specialist.
            ModelAssignment(agentID: AgentID.cSharp, preferredModelID: Project5ModelCatalog.coding, preferredCapability: .coding, fallbackModelIDs: [], fallbackCapabilities: [.coding], allowsRuntimeReuse: true), // Shares the installed coding model with the logical C# specialist.
            ModelAssignment(agentID: AgentID.web, preferredModelID: Project5ModelCatalog.coding, preferredCapability: .coding, fallbackModelIDs: [], fallbackCapabilities: [.coding], allowsRuntimeReuse: true), // Shares the installed coding model with the logical Web specialist without adding network access.
            ModelAssignment(agentID: AgentID.database, preferredModelID: Project5ModelCatalog.coding, preferredCapability: .coding, fallbackModelIDs: [], fallbackCapabilities: [.coding], allowsRuntimeReuse: true), // Shares the installed coding model with the logical Database specialist without adding database execution.
            ModelAssignment(agentID: AgentID.math, preferredModelID: Project5ModelCatalog.reasoning, preferredCapability: .reasoning, fallbackModelIDs: [Project5ModelCatalog.general], fallbackCapabilities: [.reasoning], allowsRuntimeReuse: true), // Shares the installed reasoning model with the logical Math specialist.
            ModelAssignment(agentID: AgentID.data, preferredModelID: Project5ModelCatalog.reasoning, preferredCapability: .reasoning, fallbackModelIDs: [Project5ModelCatalog.general], fallbackCapabilities: [.reasoning], allowsRuntimeReuse: true), // Shares the installed reasoning model with the logical Data specialist.
            ModelAssignment(agentID: AgentID.document, preferredModelID: Project5ModelCatalog.general, preferredCapability: .general, fallbackModelIDs: [Project5ModelCatalog.reasoning], fallbackCapabilities: [.general], allowsRuntimeReuse: true), // Shares the installed general model with the logical Document specialist.
            ModelAssignment(agentID: AgentID.reviewer, preferredModelID: Project5ModelCatalog.reasoning, preferredCapability: .reasoning, fallbackModelIDs: [Project5ModelCatalog.general], fallbackCapabilities: [.reasoning], allowsRuntimeReuse: true), // Assigns Reviewer Agent to DeepSeek with Qwen3 as a declared alternative.
            ModelAssignment(agentID: AgentID.finalComposer, preferredModelID: Project5ModelCatalog.general, preferredCapability: .general, fallbackModelIDs: [Project5ModelCatalog.reasoning], fallbackCapabilities: [.general, .reasoning], allowsRuntimeReuse: true), // Assigns Final Composer to Qwen3 with the reasoning model as an explicit alternative.
            ModelAssignment(agentID: AgentID.vision, preferredModelID: Project5ModelCatalog.vision, preferredCapability: .vision, fallbackModelIDs: [], fallbackCapabilities: [.vision], allowsRuntimeReuse: true) // Assigns the single V0.3 Vision Agent independently from text specialists.
        ] // Ends default assignment definitions.
    } // Ends default-assignment creation.
} // Ends the V0.2 model registry.
