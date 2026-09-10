import Foundation // Supplies UUID and fixed Date values for deterministic controller tests.
import XCTest // Supplies asynchronous main-actor assertions for profile, token, health, and discovery state.
@testable import AutoMLXStudio // Exposes internal remote models controller contracts to the permanent suite.

private enum RemoteModelsControllerMockError: LocalizedError { // Defines one safe injected persistence or discovery failure.
    case tokenWrite // Simulates a Keychain mutation failure after profile persistence.
    case discovery // Simulates a bounded model-list failure.

    var errorDescription: String? { // Produces stable assertions without credential content.
        switch self { // Selects the injected diagnostic.
        case .tokenWrite: return "Injected Keychain token write failure." // Identifies the exact compensation trigger.
        case .discovery: return "Injected remote model discovery failure." // Identifies the exact network failure.
        } // Ends mock error rendering.
    } // Ends mock localized descriptions.
} // Ends deterministic controller mock errors.

private actor RemoteServerManagerMock: RemoteServerManaging { // Provides deterministic multi-profile and failure-injection behavior without disk or Keychain access.
    private var profiles: [RemoteServerProfile] // Stores non-secret test profiles by value.
    private var tokens: [UUID: String] = [:] // Stores test-only credential state separately from profiles.
    private var tokenReadCountValue = 0 // Records any prohibited controller secret read.
    private var saveCountValue = 0 // Records durable profile save attempts.
    private var failNextTokenMutation = false // Injects one second-boundary failure for compensation testing.

    init(profiles: [RemoteServerProfile] = []) { // Creates an actor with optional preexisting durable state.
        self.profiles = profiles // Stores the supplied non-secret profiles.
    } // Ends mock manager construction.

    func allProfiles() async throws -> [RemoteServerProfile] { // Returns stable display-name order like the production store.
        profiles.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending } // Produces deterministic UI ordering.
    } // Ends mock profile-list retrieval.

    func profile(id: UUID) async throws -> RemoteServerProfile? { // Resolves one exact current profile.
        profiles.first { $0.id == id } // Returns the matching value or nil.
    } // Ends mock profile lookup.

    func token(for id: UUID) async throws -> String? { // Implements the provider token boundary for protocol completeness.
        tokenReadCountValue += 1 // Records every secret read for negative controller assertions.
        return tokens[id] // Returns only the exact test credential.
    } // Ends mock token lookup.

    func save(_ profile: RemoteServerProfile) async throws { // Inserts or replaces one non-secret profile deterministically.
        saveCountValue += 1 // Records the profile persistence attempt.
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { // Detects an existing exact identity.
            profiles[index] = profile // Replaces only the matching profile.
        } else { // Handles a new server.
            profiles.append(profile) // Adds one independent profile.
        } // Ends mock insert-or-replace selection.
    } // Ends mock profile persistence.

    func remove(id: UUID) async throws { // Removes one exact profile and its separate test token.
        profiles.removeAll { $0.id == id } // Removes only matching non-secret state.
        tokens[id] = nil // Removes only the matching test credential.
    } // Ends mock removal.

    func setToken(_ token: String?, for id: UUID) async throws { // Mutates the separate test credential boundary.
        if failNextTokenMutation { // Handles one explicit failure injection.
            failNextTokenMutation = false // Makes compensation behavior deterministic and allows its cleanup to proceed.
            throw RemoteModelsControllerMockError.tokenWrite // Fails after profile persistence without changing secret state.
        } // Ends injected token failure.
        tokens[id] = token // Applies normal add, replace, or removal semantics.
    } // Ends mock token mutation.

    func injectNextTokenFailure() { // Arms one exact credential-boundary failure.
        failNextTokenMutation = true // Causes the next mutation to fail before changing token state.
    } // Ends token failure injection.

    func snapshotProfiles() -> [RemoteServerProfile] { // Exposes durable non-secret state for assertions.
        profiles // Returns value-semantic profile snapshots.
    } // Ends profile snapshot retrieval.

    func savedToken(for id: UUID) -> String? { // Exposes test-only separate credential state.
        tokens[id] // Returns the exact test token without affecting read-count assertions.
    } // Ends direct test token inspection.

    func tokenReadCount() -> Int { // Exposes controller secret-read attempts.
        tokenReadCountValue // Returns the deterministic read counter.
    } // Ends token-read count retrieval.

    func saveCount() -> Int { // Exposes profile persistence attempts.
        saveCountValue // Returns the deterministic save counter.
    } // Ends save-count retrieval.
} // Ends deterministic remote server manager mock.

private actor RemoteModelsServiceMock: RemoteModelsServicing { // Provides deterministic API health and discovery without network access.
    private let healthValue: ModelBackendHealth // Stores the exact API-level observation returned to the controller.
    private let modelsValue: [RemoteDiscoveredModel] // Stores the exact normalized discovery result.
    private var discoveryError: Error? // Stores an optional injected discovery failure.
    private var targets: [ModelGenerationTarget] = [] // Records every typed health target.
    private var forceRefreshValues: [Bool] = [] // Records cache policy chosen by controller actions.

    init(health: ModelBackendHealth, models: [RemoteDiscoveredModel]) { // Creates a service with fixed evidence.
        self.healthValue = health // Stores the fixed health observation.
        self.modelsValue = models // Stores the fixed model list.
    } // Ends mock service construction.

    func health(for target: ModelGenerationTarget) async -> ModelBackendHealth { // Returns the fixed observation and records typed routing context.
        targets.append(target) // Records backend, server, and model target for assertions.
        return healthValue // Returns the exact configured evidence.
    } // Ends mock health observation.

    func discoverModels(serverID: UUID, forceRefresh: Bool) async throws -> [RemoteDiscoveredModel] { // Returns fixed discovery or one injected safe failure.
        forceRefreshValues.append(forceRefresh) // Records whether the controller requested live refresh or cache reuse.
        if let discoveryError { // Handles explicit failure injection.
            throw discoveryError // Returns the bounded mock failure.
        } // Ends injected discovery failure.
        return modelsValue.filter { $0.serverID == serverID } // Preserves exact per-server isolation.
    } // Ends mock model discovery.

    func recordedTargets() -> [ModelGenerationTarget] { // Exposes typed health targets for assertions.
        targets // Returns value-semantic target snapshots.
    } // Ends target log retrieval.

    func recordedForceRefreshValues() -> [Bool] { // Exposes controller discovery cache intent.
        forceRefreshValues // Returns value-semantic Boolean snapshots.
    } // Ends force-refresh log retrieval.
} // Ends deterministic remote model service mock.

@MainActor // Runs published controller state assertions on the same actor as production SwiftUI behavior.
final class RemoteModelsControllerTests: XCTestCase { // Verifies durable state, secret separation, compensation, and API observation coordination.
    func testLoadPublishesStableMultipleProfiles() async { // Verifies initial loading uses the durable manager and preserves multi-server architecture.
        let beta = makeProfile(displayName: "Beta Server") // Creates the later alphabetical profile first.
        let alpha = makeProfile(displayName: "Alpha Server") // Creates the earlier alphabetical profile second.
        let manager = RemoteServerManagerMock(profiles: [beta, alpha]) // Seeds durable state in insertion order.
        let service = makeService() // Creates an unused deterministic network boundary.
        let controller = RemoteModelsController(store: manager, inferenceService: service) // Creates the production controller against mocks.
        await controller.load() // Loads durable profile state.
        XCTAssertEqual(controller.profiles.map(\.displayName), ["Alpha Server", "Beta Server"]) // Confirms stable multi-profile display order.
        XCTAssertFalse(controller.isLoading) // Confirms loading state always clears.
        XCTAssertNil(controller.notice) // Confirms a non-empty successful load does not add redundant feedback.
    } // Ends initial multi-profile loading testing.

    func testNewBearerProfileRequiresExplicitTokenBeforePersistence() async { // Verifies authenticated creation cannot knowingly save an unusable profile.
        let manager = RemoteServerManagerMock() // Starts with no durable profiles or tokens.
        let profile = makeProfile(authenticationMode: .bearerToken) // Creates a new profile requiring bearer auth.
        let controller = RemoteModelsController(store: manager, inferenceService: makeService()) // Creates the production controller against mocks.
        await controller.load() // Establishes the empty durable state.
        let saved = await controller.save(profile: profile, tokenUpdate: .unchanged) // Attempts creation without SecureField input.
        XCTAssertFalse(saved) // Confirms the editor must remain open.
        let saveCount = await manager.saveCount() // Reads the actor-owned persistence counter before entering the XCTest autoclosure.
        XCTAssertEqual(saveCount, 0) // Confirms validation happens before profile persistence.
        XCTAssertTrue(controller.notice?.message.contains("bearer token") == true) // Confirms actionable non-secret feedback.
    } // Ends new bearer credential validation testing.

    func testTokenFailureRestoresPreviousProfileWithoutReadingExistingSecret() async { // Verifies cross-boundary compensation after profile persistence succeeds and token mutation fails.
        let original = makeProfile(displayName: "Original Server", host: "old.private") // Creates preexisting durable non-secret state.
        let manager = RemoteServerManagerMock(profiles: [original]) // Seeds the exact original profile.
        let controller = RemoteModelsController(store: manager, inferenceService: makeService()) // Creates the production controller against mocks.
        await controller.load() // Loads original state for edit comparison.
        await manager.injectNextTokenFailure() // Arms one Keychain-equivalent failure after profile save.
        var edited = original // Copies the original profile for a visible endpoint edit.
        edited.displayName = "Edited Server" // Changes non-secret display identity.
        edited.host = "new.private" // Changes the non-secret endpoint host.
        edited.authenticationMode = .bearerToken // Enables authentication and requires explicit token input.
        edited.updatedAt = Date(timeIntervalSince1970: 1_800_000_000) // Records a deterministic edit time.
        let saved = await controller.save(profile: edited, tokenUpdate: .replace("new-secret-never-logged")) // Triggers profile persistence then injected credential failure.
        XCTAssertFalse(saved) // Confirms no partial operation is reported as success.
        let durable = await manager.snapshotProfiles() // Reads the compensated non-secret durable state.
        XCTAssertEqual(durable, [original]) // Confirms the prior profile is restored exactly.
        let tokenReadCount = await manager.tokenReadCount() // Reads actor-owned secret-access evidence before entering the XCTest autoclosure.
        XCTAssertEqual(tokenReadCount, 0) // Confirms compensation never reads or exposes an existing token.
        XCTAssertTrue(controller.notice?.message.contains("Injected Keychain token write failure") == true) // Confirms the original failure remains primary.
        XCTAssertTrue(controller.notice?.message.contains("rolled back") == true) // Confirms successful compensation is reported explicitly.
    } // Ends profile compensation and secret non-read testing.

    func testConnectionPublishesRemoteHealthModelsAndUsesFreshCacheWithoutSecondLiveRefresh() async { // Verifies API checking, target location, and discovery state coordination.
        let profile = makeProfile() // Creates one configured private remote server.
        let manager = RemoteServerManagerMock(profiles: [profile]) // Seeds durable profile state.
        let observedHealth = ModelBackendHealth(status: .degraded, latencyMilliseconds: 21, checkedAt: Date(timeIntervalSince1970: 1_700_000_000), serverKind: "LM Studio", apiCompatible: true, discoveredModelCount: 1, conciseError: "Probe model was not discovered.") // Simulates first-contact sentinel absence on a compatible API.
        let model = RemoteDiscoveredModel(id: "qwen-coder", serverID: profile.id, backendID: .remoteOpenAICompatible, availability: .available, capabilities: ModelCapabilityProfile()) // Supplies one actually discovered remote model.
        let service = RemoteModelsServiceMock(health: observedHealth, models: [model]) // Creates fixed network evidence.
        let controller = RemoteModelsController(store: manager, inferenceService: service) // Creates the production controller against deterministic boundaries.
        await controller.load() // Loads the configured server.
        await controller.testConnection(serverID: profile.id) // Performs the explicit API-level connection workflow.
        XCTAssertEqual(controller.health(for: profile.id)?.status, .healthy) // Confirms compatible first contact is normalized only after a real model is found.
        XCTAssertEqual(controller.models(for: profile.id), [model]) // Confirms normalized discovery is isolated to the selected server.
        XCTAssertEqual(controller.operation(for: profile.id), nil) // Confirms operation ownership releases on completion.
        let targets = await service.recordedTargets() // Reads typed health targets.
        XCTAssertEqual(targets.first?.backendID, .remoteOpenAICompatible) // Confirms no raw transport string is used.
        XCTAssertEqual(targets.first?.location, .remote(serverID: profile.id)) // Confirms the exact server identity is retained.
        let forceRefreshValues = await service.recordedForceRefreshValues() // Reads actor-owned cache intent before entering the XCTest autoclosure.
        XCTAssertEqual(forceRefreshValues, [false]) // Confirms discovery reuses the backend health check's fresh cache rather than issuing a second live refresh.
        XCTAssertTrue(controller.notice?.message.contains("Discovered 1 remote model") == true) // Confirms exact successful model count feedback.
    } // Ends connection and discovery coordination testing.

    private func makeProfile(displayName: String = "Remote Test Server", host: String = "private.test", authenticationMode: RemoteAuthenticationMode = .none) -> RemoteServerProfile { // Creates deterministic valid non-secret profile state.
        RemoteServerProfile(id: UUID(), displayName: displayName, backendID: .remoteOpenAICompatible, scheme: .https, host: host, port: 1_234, basePath: "/v1", authenticationMode: authenticationMode, connectionTimeoutSeconds: 5, inferenceTimeoutSeconds: 60, isEnabled: true, createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000)) // Returns a complete production-valid profile.
    } // Ends deterministic profile construction.

    private func makeService() -> RemoteModelsServiceMock { // Creates an inert healthy service for tests not focused on networking.
        let health = ModelBackendHealth(status: .healthy, latencyMilliseconds: 1, checkedAt: Date(timeIntervalSince1970: 1_700_000_000), serverKind: nil, apiCompatible: true, discoveredModelCount: 0, conciseError: nil) // Supplies fixed usable API evidence.
        return RemoteModelsServiceMock(health: health, models: []) // Returns the deterministic actor boundary.
    } // Ends inert service construction.
} // Ends permanent remote models controller tests.
