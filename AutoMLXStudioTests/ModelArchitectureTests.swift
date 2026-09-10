import XCTest // Supplies unit assertions and structured asynchronous test support.
@testable import AutoMLXStudio // Exposes internal V0.2 registry, router, and resource-manager types.

final class ModelArchitectureTests: XCTestCase { // Verifies catalog mutation, deterministic selection, and serialized lifecycle behavior.
    private let agents = AgentRegistry() // Uses the same central agent requirements as production routing.

    func testDefaultCatalogAssignmentsAndLegacyMigration() throws { // Verifies the complete offline catalog, initial assignments, and V0.1 compatibility entry.
        let missingRoot = FileManager.default.temporaryDirectory.appendingPathComponent("Missing-Project5-Models-\(UUID().uuidString)", isDirectory: true).path // Uses a guaranteed absent root so optional installation states stay deterministic.
        let legacyIdentifier = "example/legacy-v01-model" // Supplies a repository-only V0.1 setting for migration.
        let registry = ModelRegistry.defaultRegistry(legacyIdentifier: legacyIdentifier, modelsRoot: missingRoot) // Builds the production first-launch V0.2 registry without downloading files.
        let expectedCatalogIDs: Set<String> = [Project5ModelCatalog.general, Project5ModelCatalog.coding, Project5ModelCatalog.reasoning, Project5ModelCatalog.translation, Project5ModelCatalog.vision, Project5ModelCatalog.speechToText, Project5ModelCatalog.textToSpeech, Project5ModelCatalog.embedding, Project5ModelCatalog.reranker] // Lists the nine required Project 5 catalog entries.
        XCTAssertEqual(Set(registry.models.filter { !$0.isLegacyFallback }.map(\.id)), expectedCatalogIDs) // Confirms every requested physical-model profile is registered exactly once.
        XCTAssertEqual(registry.models.count, expectedCatalogIDs.count + 1) // Confirms the migrated legacy fallback is retained alongside the catalog.
        let legacy = try XCTUnwrap(registry.model(id: legacyIdentifier)) // Resolves the migrated V0.1 profile.
        XCTAssertTrue(legacy.isLegacyFallback) // Confirms the migration marks the final compatibility fallback.
        XCTAssertEqual(legacy.installationState, .installed) // Confirms the previously working repository setting remains immediately routable.
        XCTAssertEqual(registry.assignments.count, 16) // Confirms assignments include legacy workflow agents, Vision, eight V0.5 specialists, and the V0.6 Engineering Agent without new local physical models.
        XCTAssertEqual(registry.assignment(for: AgentID.coding)?.preferredModelID, Project5ModelCatalog.coding) // Confirms coding begins on the dedicated physical coder.
        let engineeringAssignment = try XCTUnwrap(registry.assignment(for: AgentID.engineering)) // Resolves the new V0.6 assignment so its local-first safety contract is covered explicitly.
        XCTAssertEqual(engineeringAssignment.preferredModelID, Project5ModelCatalog.coding) // Confirms Engineering Agent starts on the compatible local coder until a remote model is configured deliberately.
        XCTAssertEqual(engineeringAssignment.preferredCapability, .coding) // Confirms remote or local replacements must satisfy the coding capability rather than silently selecting an unrelated model.
        XCTAssertEqual(engineeringAssignment.fallbackCapabilities, [.coding, .reasoning]) // Confirms deterministic compatible recovery remains available without weakening the preferred specialization.
        XCTAssertEqual(registry.assignment(for: AgentID.reviewer)?.preferredModelID, Project5ModelCatalog.reasoning) // Confirms review begins on the dedicated reasoning model.
        XCTAssertEqual(registry.assignment(for: AgentID.finalComposer)?.preferredModelID, Project5ModelCatalog.general) // Confirms final composition returns to the general model.
        XCTAssertTrue(try XCTUnwrap(registry.model(id: Project5ModelCatalog.vision)).enabled) // Confirms Vision is registered and enabled while installation and adapter validation still gate execution safely.
    } // Ends default catalog and migration validation.

    func testRegistryPersistenceRoundTripPreservesUserConfiguration() throws { // Verifies Codable persistence retains mutable catalog and assignment state exactly.
        var registry = makeRegistry(models: [profile(id: "general", capabilities: [.general]), profile(id: "legacy", capabilities: allTextCapabilities, legacy: true)], assignments: [ModelAssignment(agentID: AgentID.general, preferredModelID: "general", preferredCapability: .general, fallbackModelIDs: ["legacy"], fallbackCapabilities: [.general], allowsRuntimeReuse: true)]) // Creates an explicit registry containing user-visible configuration.
        registry.setEnabled(false, modelID: "general") // Applies a user model-toggle choice.
        registry.setPreferredModel("legacy", for: .general) // Applies a user capability preference.
        let encoded = try JSONEncoder().encode(registry) // Serializes the same representation AppState persists in UserDefaults.
        let decoded = try JSONDecoder().decode(ModelRegistry.self, from: encoded) // Restores the persisted V0.2 registry.
        XCTAssertEqual(decoded, registry) // Confirms all model, assignment, preference, fallback, and root fields survive exactly.
    } // Ends registry persistence validation.

    func testModelRegistrationUpdateAndRemoval() { // Verifies controlled registry mutation behavior.
        var registry = makeRegistry(models: [profile(id: "legacy", capabilities: allTextCapabilities, legacy: true)], assignments: []) // Creates a minimal registry with protected legacy fallback.
        var added = profile(id: "new-model", capabilities: [.general]) // Creates a user-registerable model profile.
        registry.register(added) // Registers the new model.
        XCTAssertEqual(registry.model(id: "new-model")?.displayName, "new-model") // Confirms lookup by stable ID.
        added.displayName = "Updated Model" // Changes mutable profile metadata.
        registry.update(added) // Updates the existing registry entry.
        XCTAssertEqual(registry.model(id: "new-model")?.displayName, "Updated Model") // Confirms deterministic upsert replacement.
        registry.remove(id: "new-model") // Removes the user model.
        XCTAssertNil(registry.model(id: "new-model")) // Confirms removal by ID.
        registry.remove(id: "legacy") // Attempts to remove the required final fallback.
        XCTAssertNotNil(registry.model(id: "legacy")) // Confirms legacy fallback protection.
    } // Ends model registration test.

    func testCapabilityMatchingRequiresEveryAgentCapability() throws { // Verifies typed capability intersection instead of loose single-tag matching.
        let coder = profile(id: "coder", capabilities: [.general, .reasoning, .coding, .swiftLanguage]) // Creates a complete Swift-compatible model.
        let partial = profile(id: "partial", capabilities: [.coding]) // Creates an incomplete model missing reasoning and Swift capability.
        let registry = makeRegistry(models: [coder, partial, profile(id: "legacy", capabilities: allTextCapabilities, legacy: true)], assignments: []) // Registers both candidates.
        let swiftAgent = try XCTUnwrap(agents.agent(id: AgentID.swift)) // Resolves production Swift Agent requirements.
        XCTAssertEqual(registry.models(supporting: swiftAgent.requiredCapabilities).map(\.id), ["coder", "legacy"]) // Confirms every required capability is enforced.
    } // Ends capability matching test.

    func testAssignmentLookupAndMutationRemainSeparateFromAgentDefinition() throws { // Verifies persisted assignments are independent values.
        let assignment = ModelAssignment(agentID: AgentID.general, preferredModelID: "general", preferredCapability: .general, fallbackModelIDs: ["backup"], fallbackCapabilities: [.general], allowsRuntimeReuse: true) // Creates an explicit general-agent assignment.
        var registry = makeRegistry(models: [profile(id: "legacy", capabilities: allTextCapabilities, legacy: true)], assignments: [assignment]) // Stores it outside AgentRegistry.
        XCTAssertEqual(registry.assignment(for: AgentID.general), assignment) // Confirms exact assignment lookup.
        registry.setPreferredModel("replacement", forAgent: AgentID.general) // Mutates only the preferred physical model.
        XCTAssertEqual(registry.assignment(for: AgentID.general)?.preferredModelID, "replacement") // Confirms persisted assignment mutation.
        XCTAssertEqual(try XCTUnwrap(agents.agent(id: AgentID.general)).requiredCapabilities, [.general]) // Confirms AgentDefinition responsibility remains unchanged.
    } // Ends assignment separation test.

    func testPreferredModelSelection() throws { // Verifies the primary deterministic ModelRouter path.
        let preferred = profile(id: "preferred", capabilities: [.general]) // Creates an installed compatible preferred model.
        let assignment = ModelAssignment(agentID: AgentID.general, preferredModelID: preferred.id, preferredCapability: .general, fallbackModelIDs: [], fallbackCapabilities: [.general], allowsRuntimeReuse: true) // Assigns it to General Agent.
        let registry = makeRegistry(models: [preferred, profile(id: "legacy", capabilities: allTextCapabilities, legacy: true)], assignments: [assignment]) // Registers preferred and legacy candidates.
        let selection = try ModelRouter().selectModel(for: XCTUnwrap(agents.agent(id: AgentID.general)), registry: registry, activeModelID: nil, policy: .balanced, excluding: []) // Resolves without an active model.
        XCTAssertEqual(selection.selectedModelID, preferred.id) // Confirms preferred physical model selection.
        XCTAssertEqual(selection.reason, .preferredModel) // Confirms trace reason metadata.
        XCTAssertFalse(selection.usedFallback) // Confirms no fallback was reported.
    } // Ends preferred model test.

    func testDeclaredFallbackSelectionWhenPreferredIsMissing() throws { // Verifies explicit ordered physical fallback behavior.
        var missing = profile(id: "missing", capabilities: [.general]) // Creates the configured but absent preferred model.
        missing.installationState = .notInstalled // Marks it absent from local storage.
        missing.runtimeState = .unavailable // Prevents runtime selection.
        let fallback = profile(id: "fallback", capabilities: [.general]) // Creates an installed declared fallback.
        let assignment = ModelAssignment(agentID: AgentID.general, preferredModelID: missing.id, preferredCapability: .general, fallbackModelIDs: [fallback.id], fallbackCapabilities: [.general], allowsRuntimeReuse: true) // Stores deterministic fallback order.
        let registry = makeRegistry(models: [missing, fallback, profile(id: "legacy", capabilities: allTextCapabilities, legacy: true)], assignments: [assignment]) // Registers all candidates.
        let selection = try ModelRouter().selectModel(for: XCTUnwrap(agents.agent(id: AgentID.general)), registry: registry, activeModelID: nil, policy: .balanced, excluding: []) // Resolves after preferred installation failure.
        XCTAssertEqual(selection.selectedModelID, fallback.id) // Confirms the declared fallback was used.
        XCTAssertEqual(selection.reason, .declaredFallback) // Confirms explicit recovery metadata.
        XCTAssertTrue(selection.usedFallback) // Confirms fallback use is recorded.
    } // Ends declared fallback test.

    func testDeclaredFallbackPrecedesCapabilityPreference() throws { // Verifies the brief's exact recovery order while retaining capability-level defaults.
        var missing = profile(id: "missing", capabilities: [.general]) // Creates an absent agent-preferred model.
        missing.installationState = .notInstalled // Marks the preferred model physically absent.
        missing.runtimeState = .unavailable // Prevents runtime selection of the missing model.
        let declared = profile(id: "declared", capabilities: [.general]) // Creates the agent's explicit first fallback.
        let capabilityPreferred = profile(id: "capability-preferred", capabilities: [.general]) // Creates a compatible global capability preference.
        let assignment = ModelAssignment(agentID: AgentID.general, preferredModelID: missing.id, preferredCapability: .general, fallbackModelIDs: [declared.id], fallbackCapabilities: [.general], allowsRuntimeReuse: true) // Stores the required agent-local recovery chain.
        var registry = makeRegistry(models: [missing, declared, capabilityPreferred, profile(id: "legacy", capabilities: allTextCapabilities, legacy: true)], assignments: [assignment]) // Registers every competing recovery candidate.
        registry.setPreferredModel(capabilityPreferred.id, for: .general) // Configures the Models-page capability preference.
        let declaredSelection = try ModelRouter().selectModel(for: XCTUnwrap(agents.agent(id: AgentID.general)), registry: registry, activeModelID: nil, policy: .balanced, excluding: []) // Resolves with both declared and capability-level alternatives available.
        XCTAssertEqual(declaredSelection.selectedModelID, declared.id) // Confirms declared fallback wins exactly as required.
        XCTAssertEqual(declaredSelection.reason, .declaredFallback) // Confirms trace metadata records the correct recovery tier.
        registry.setAssignment(ModelAssignment(agentID: AgentID.general, preferredModelID: missing.id, preferredCapability: .general, fallbackModelIDs: [], fallbackCapabilities: [.general], allowsRuntimeReuse: true)) // Removes declared fallbacks to expose the next deterministic tier.
        let capabilitySelection = try ModelRouter().selectModel(for: XCTUnwrap(agents.agent(id: AgentID.general)), registry: registry, activeModelID: nil, policy: .balanced, excluding: []) // Resolves again after declared fallback exhaustion.
        XCTAssertEqual(capabilitySelection.selectedModelID, capabilityPreferred.id) // Confirms the capability preference remains functional.
        XCTAssertEqual(capabilitySelection.reason, .capabilityPreference) // Confirms the capability preference has distinct trace metadata.
    } // Ends exact fallback-order validation.

    func testDisabledModelIsIgnored() throws { // Verifies user-disabled models never enter selection.
        var disabled = profile(id: "disabled", capabilities: [.general]) // Creates an otherwise usable preferred model.
        disabled.enabled = false // Applies the user-disabled state.
        let fallback = profile(id: "fallback", capabilities: [.general]) // Creates an enabled declared fallback.
        let assignment = ModelAssignment(agentID: AgentID.general, preferredModelID: disabled.id, preferredCapability: .general, fallbackModelIDs: [fallback.id], fallbackCapabilities: [.general], allowsRuntimeReuse: true) // Assigns both candidates.
        let registry = makeRegistry(models: [disabled, fallback, profile(id: "legacy", capabilities: allTextCapabilities, legacy: true)], assignments: [assignment]) // Registers disabled, fallback, and legacy models.
        let selection = try ModelRouter().selectModel(for: XCTUnwrap(agents.agent(id: AgentID.general)), registry: registry, activeModelID: nil, policy: .balanced, excluding: []) // Resolves deterministic alternatives.
        XCTAssertEqual(selection.selectedModelID, fallback.id) // Confirms the disabled model was ignored.
    } // Ends disabled model test.

    func testMissingLocalModelIsIgnoredAndLegacyFallbackWinsLast() throws { // Verifies absent catalog entries do not cause internet-dependent routing.
        var missing = profile(id: "missing", capabilities: [.general]) // Creates an absent preferred catalog model.
        missing.installationState = .notInstalled // Records missing physical storage.
        missing.runtimeState = .unavailable // Records runtime unavailability.
        let legacy = profile(id: "legacy", capabilities: allTextCapabilities, legacy: true) // Creates the migrated V0.1 final fallback.
        let assignment = ModelAssignment(agentID: AgentID.general, preferredModelID: missing.id, preferredCapability: .general, fallbackModelIDs: [], fallbackCapabilities: [.general], allowsRuntimeReuse: true) // Leaves no declared fallback.
        let registry = makeRegistry(models: [missing, legacy], assignments: [assignment]) // Registers only absent preferred and legacy fallback.
        let selection = try ModelRouter().selectModel(for: XCTUnwrap(agents.agent(id: AgentID.general)), registry: registry, activeModelID: nil, policy: .balanced, excluding: []) // Exhausts preferred and capability candidates.
        XCTAssertEqual(selection.selectedModelID, legacy.id) // Confirms backward-compatible final recovery.
        XCTAssertEqual(selection.reason, .legacyFallback) // Confirms trace metadata distinguishes legacy recovery.
    } // Ends missing local and legacy fallback test.

    func testSwitchPoliciesApplyExplicitReuseRules() throws { // Verifies quality, balanced, and minimize-switch behavior deterministically.
        let preferred = profile(id: "preferred", capabilities: [.general]) // Creates the assignment preference.
        let declared = profile(id: "declared", capabilities: [.general]) // Creates an explicit fallback currently active.
        let compatible = profile(id: "compatible", capabilities: [.general]) // Creates an undeclared compatible active model.
        let assignment = ModelAssignment(agentID: AgentID.general, preferredModelID: preferred.id, preferredCapability: .general, fallbackModelIDs: [declared.id], fallbackCapabilities: [.general], allowsRuntimeReuse: true) // Allows runtime reuse with a bounded fallback list.
        let registry = makeRegistry(models: [preferred, declared, compatible, profile(id: "legacy", capabilities: allTextCapabilities, legacy: true)], assignments: [assignment]) // Registers every policy candidate.
        let agent = try XCTUnwrap(agents.agent(id: AgentID.general)) // Resolves production General Agent requirements.
        let quality = try ModelRouter().selectModel(for: agent, registry: registry, activeModelID: declared.id, policy: .qualityPreferred, excluding: []) // Applies strict preferred quality selection.
        XCTAssertEqual(quality.selectedModelID, preferred.id) // Confirms quality mode chooses the preferred model and switches.
        let balanced = try ModelRouter().selectModel(for: agent, registry: registry, activeModelID: declared.id, policy: .balanced, excluding: []) // Applies bounded explicit reuse.
        XCTAssertEqual(balanced.selectedModelID, declared.id) // Confirms balanced mode reuses a declared fallback.
        XCTAssertEqual(balanced.reason, .activeModelReuse) // Confirms reuse appears in trace metadata.
        let minimized = try ModelRouter().selectModel(for: agent, registry: registry, activeModelID: compatible.id, policy: .minimizeSwitches, excluding: []) // Applies broad compatible reuse.
        XCTAssertEqual(minimized.selectedModelID, compatible.id) // Confirms minimize-switches reuses an undeclared compatible model.
    } // Ends switching policy test.

    func testResourceManagerStateTransitionsAndStop() async throws { // Verifies loaded, unloaded, and stopped lifecycle snapshots.
        let environment = try makeTestEnvironment() // Creates an isolated executable preflight environment.
        defer { try? FileManager.default.removeItem(at: environment.root) } // Removes only the UUID-scoped test directory.
        let controller = FakeModelServerController() // Creates a deterministic fake server process controller.
        let manager = ModelResourceManager(controller: controller) // Creates the real actor around the fake process boundary.
        let first = profile(id: "first", capabilities: [.general], legacy: true) // Creates a validation-safe first model.
        let second = profile(id: "second", capabilities: [.general], legacy: true) // Creates a validation-safe second model.
        _ = try await manager.prepare(model: first, configuration: environment.configuration) // Loads the first physical model.
        var snapshot = await manager.snapshot() // Reads authoritative lifecycle state.
        XCTAssertEqual(snapshot.activeModelID, first.id) // Confirms first model becomes active.
        XCTAssertEqual(snapshot.states[first.id], .loaded) // Confirms loaded state.
        _ = try await manager.prepare(model: second, configuration: environment.configuration) // Switches to the second physical model.
        snapshot = await manager.snapshot() // Reads post-switch state.
        XCTAssertEqual(snapshot.activeModelID, second.id) // Confirms second model becomes active.
        XCTAssertEqual(snapshot.states[first.id], .unloaded) // Confirms first model was released.
        XCTAssertEqual(snapshot.states[second.id], .loaded) // Confirms second model is loaded.
        await manager.stop() // Stops the managed server.
        snapshot = await manager.snapshot() // Reads final stopped state.
        XCTAssertNil(snapshot.activeModelID) // Confirms no model remains active.
        XCTAssertEqual(snapshot.states[second.id], .unloaded) // Confirms the final model is installed but no longer resident.
    } // Ends resource state transition test.

    func testConcurrentDuplicateLoadIsCoalesced() async throws { // Verifies simultaneous requests for one model create only one server start.
        let environment = try makeTestEnvironment() // Creates an isolated executable preflight environment.
        defer { try? FileManager.default.removeItem(at: environment.root) } // Removes only the UUID-scoped test directory.
        let controller = FakeModelServerController(startDelayMilliseconds: 80) // Keeps the transition open long enough for request overlap.
        let manager = ModelResourceManager(controller: controller) // Creates the production coalescing actor.
        let model = profile(id: "shared", capabilities: [.general], legacy: true) // Creates one validation-safe target.
        async let first = manager.prepare(model: model, configuration: environment.configuration) // Starts the first physical load request.
        async let second = manager.prepare(model: model, configuration: environment.configuration) // Starts an overlapping identical request.
        let preparations = try await [first, second] // Waits for both coalesced callers.
        let metrics = await controller.metrics() // Reads fake process invocation counts.
        XCTAssertEqual(metrics.startCount, 1) // Confirms only one physical model start occurred.
        XCTAssertEqual(Set(preparations.map(\.port)).count, 1) // Confirms both callers received the same ready endpoint.
        XCTAssertTrue(preparations.contains(where: \.reusedExistingLoad)) // Confirms the duplicate request is marked as shared reuse.
    } // Ends duplicate load coalescing test.

    func testConcurrentDifferentLoadsRemainSerialized() async throws { // Verifies competing model transitions never overlap physical start operations.
        let environment = try makeTestEnvironment() // Creates an isolated executable preflight environment.
        defer { try? FileManager.default.removeItem(at: environment.root) } // Removes only the UUID-scoped test directory.
        let controller = FakeModelServerController(startDelayMilliseconds: 60) // Creates observable process overlap if serialization fails.
        let manager = ModelResourceManager(controller: controller) // Creates the production serialization actor.
        let firstModel = profile(id: "first", capabilities: [.general], legacy: true) // Creates the first validation-safe target.
        let secondModel = profile(id: "second", capabilities: [.general], legacy: true) // Creates the competing validation-safe target.
        async let first = manager.prepare(model: firstModel, configuration: environment.configuration) // Starts the first transition.
        async let second = manager.prepare(model: secondModel, configuration: environment.configuration) // Starts a competing transition.
        _ = try await [first, second] // Waits for both serialized operations.
        let metrics = await controller.metrics() // Reads fake process concurrency metrics.
        XCTAssertEqual(metrics.startCount, 2) // Confirms both distinct targets were eventually loaded.
        XCTAssertEqual(metrics.maximumConcurrentStarts, 1) // Confirms physical starts never raced.
    } // Ends concurrent different-model serialization test.

    private var allTextCapabilities: Set<ModelCapability> { [.general, .reasoning, .coding, .swiftLanguage, .research] } // Supplies the migrated V0.1 compatibility capability set.

    private func profile(id: String, capabilities: Set<ModelCapability>, enabled: Bool = true, legacy: Bool = false) -> ModelProfile { // Creates concise installed text profiles for deterministic tests.
        ModelProfile(id: id, displayName: id, repositoryID: id, localPath: nil, backend: .mlxLM, capabilities: capabilities, approximateDiskGB: nil, approximateMemoryGB: nil, enabled: enabled, installationState: .installed, runtimeState: .unloaded, isLegacyFallback: legacy, statusDetail: nil) // Returns a complete profile without filesystem coupling for router tests.
    } // Ends test profile construction.

    private func makeRegistry(models: [ModelProfile], assignments: [ModelAssignment]) -> ModelRegistry { // Creates a minimal explicit registry for one test scenario.
        ModelRegistry(models: models, assignments: assignments, legacyFallbackModelID: "legacy", modelsRoot: "/tmp/AutoMLXStudioTests") // Avoids production catalog merging in focused unit tests.
    } // Ends test registry construction.

    private func makeTestEnvironment() throws -> TestEnvironment { // Creates an isolated executable path accepted by launch validation.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AutoMLXStudioTests-\(UUID().uuidString)", isDirectory: true) // Creates an exact UUID-scoped test root.
        let executableDirectory = root.appendingPathComponent("bin", isDirectory: true) // Creates a fake virtual-environment binary folder.
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true) // Creates the isolated directories.
        let executable = executableDirectory.appendingPathComponent("mlx_lm.server") // Creates the expected executable path.
        FileManager.default.createFile(atPath: executable.path, contents: Data("#!/bin/sh\n".utf8)) // Writes a harmless executable placeholder for preflight only.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path) // Marks the placeholder executable.
        let configuration = ModelRuntimeConfiguration(executableDirectory: executableDirectory.path, repoPath: root.path, requestedPort: 19_000, autoSelectPort: true) // Creates a deterministic fake runtime configuration.
        return TestEnvironment(root: root, configuration: configuration) // Returns both configuration and exact cleanup root.
    } // Ends test environment creation.
} // Ends V0.2 model architecture tests.

private struct TestEnvironment { // Groups isolated resource-manager test paths.
    let root: URL // Stores the exact UUID-scoped cleanup root.
    let configuration: ModelRuntimeConfiguration // Stores fake executable and port settings.
} // Ends test environment values.

private actor FakeModelServerController: ModelServerControlling { // Simulates server starts while measuring concurrency and duplicates.
    private let startDelayMilliseconds: Int // Stores deterministic fake model load time.
    private var startCount = 0 // Counts physical start requests.
    private var stopCount = 0 // Counts physical stop requests.
    private var concurrentStarts = 0 // Tracks currently running fake starts.
    private var maximumConcurrentStarts = 0 // Tracks the highest observed start overlap.
    private var nextPort = 19_100 // Supplies a distinct ready port for each physical load.

    init(startDelayMilliseconds: Int = 10) { // Creates a fake controller with configurable model load time.
        self.startDelayMilliseconds = startDelayMilliseconds // Stores the deterministic delay.
    } // Ends fake controller construction.

    func start(modelReference: String, configuration: ModelRuntimeConfiguration, onOutput: @escaping (String) -> Void) async throws -> Int { // Simulates one physical model start and readiness cycle.
        startCount += 1 // Records the physical load request.
        concurrentStarts += 1 // Records active fake start work.
        maximumConcurrentStarts = max(maximumConcurrentStarts, concurrentStarts) // Records any lifecycle race.
        defer { concurrentStarts -= 1 } // Guarantees active work count is restored after success or cancellation.
        onOutput("Loading \(modelReference)") // Exercises the production output callback path.
        try await Task.sleep(for: .milliseconds(startDelayMilliseconds)) // Keeps the asynchronous transition observable.
        nextPort += 1 // Allocates a deterministic distinct ready endpoint.
        return nextPort // Completes fake model readiness.
    } // Ends fake server start.

    func stop() async { // Simulates awaited release of the active model.
        stopCount += 1 // Records the physical stop request.
        try? await Task.sleep(for: .milliseconds(2)) // Preserves asynchronous stop semantics.
    } // Ends fake server stop.

    func metrics() -> FakeServerMetrics { // Returns immutable process lifecycle measurements to tests.
        FakeServerMetrics(startCount: startCount, stopCount: stopCount, maximumConcurrentStarts: maximumConcurrentStarts) // Returns counts atomically from the actor.
    } // Ends fake server metrics access.
} // Ends fake model server controller.

private struct FakeServerMetrics { // Stores immutable fake process lifecycle metrics.
    let startCount: Int // Stores total physical model starts.
    let stopCount: Int // Stores total physical model stops.
    let maximumConcurrentStarts: Int // Stores highest observed overlapping starts.
} // Ends fake server metrics.
