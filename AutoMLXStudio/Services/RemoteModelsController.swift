import Combine // Supplies ObservableObject and published state for the native remote-models surface.
import Foundation // Supplies UUID, Date, and localized error support for controller state.

protocol RemoteServerManaging: RemoteServerProfileProviding { // Extends the read boundary with the exact mutations required by server management UI.
    func allProfiles() async throws -> [RemoteServerProfile] // Loads every configured non-secret server profile.
    func save(_ profile: RemoteServerProfile) async throws // Inserts or updates one validated non-secret profile.
    func remove(id: UUID) async throws // Removes one exact profile and its separate token.
    func setToken(_ token: String?, for id: UUID) async throws // Mutates one Keychain-backed credential without adding it to profile JSON.
} // Ends the remote server management boundary.

extension RemoteServerStore: RemoteServerManaging { // Exposes the existing actor through the focused management contract.
} // Ends production store conformance.

protocol RemoteModelsServicing: Sendable { // Isolates API health and discovery so controller tests remain deterministic and offline.
    func health(for target: ModelGenerationTarget) async -> ModelBackendHealth // Performs a usable inference API check for one remote target.
    func discoverModels(serverID: UUID, forceRefresh: Bool) async throws -> [RemoteDiscoveredModel] // Lists normalized models for one exact configured server.
} // Ends the remote model service boundary.

extension RemoteInferenceBackend: RemoteModelsServicing { // Exposes the production OpenAI-compatible backend through the UI service contract.
} // Ends production inference service conformance.

enum RemoteServerTokenUpdate: Equatable, Sendable { // Describes secret mutation without placing the token inside a server profile.
    case unchanged // Keeps an existing Keychain token without reading it into UI state.
    case replace(String) // Replaces the token through the vault boundary after explicit user input.
    case remove // Removes the exact server token from the vault.
} // Ends explicit token mutation choices.

enum RemoteModelsOperation: String, Equatable, Sendable { // Gives each profile one visible mutually exclusive network operation.
    case testingConnection // Indicates an explicit usable-API connection test.
    case refreshingModels // Indicates an explicit model discovery refresh.

    var displayName: String { // Produces concise operation text for native progress labels.
        switch self { // Selects the current user-visible activity.
        case .testingConnection: // Handles API health validation.
            return "Testing connection" // Describes the actual network work in progress.
        case .refreshingModels: // Handles model-list discovery.
            return "Refreshing models" // Describes the actual network work in progress.
        } // Ends operation-label selection.
    } // Ends operation display text.
} // Ends remote profile operation state.

enum RemoteModelsNoticeKind: Equatable, Sendable { // Distinguishes controller feedback semantically without relying on color.
    case success // Indicates a completed save, delete, test, or discovery action.
    case error // Indicates a bounded validation, persistence, Keychain, or network failure.
    case information // Indicates neutral operational guidance.
} // Ends notice severity choices.

struct RemoteModelsNotice: Identifiable, Equatable, Sendable { // Carries one concise accessible result to the remote-models view.
    let id: UUID // Gives repeated messages independent SwiftUI identity.
    let kind: RemoteModelsNoticeKind // Supplies semantic symbol and color selection.
    let message: String // Stores bounded user-facing feedback without secrets.

    init(kind: RemoteModelsNoticeKind, message: String) { // Creates one fresh controller notice.
        self.id = UUID() // Ensures repeated messages are announced as new state.
        self.kind = kind // Stores the semantic feedback category.
        self.message = message // Stores the concise already-sanitized text.
    } // Ends notice construction.
} // Ends controller notice state.

enum RemoteModelsControllerError: LocalizedError, Equatable, Sendable { // Defines UI-specific validation failures without duplicating backend errors.
    case profileNotFound // Indicates an action targeted a profile removed by another operation.
    case tokenRequired // Indicates a newly authenticated profile lacks an explicitly supplied token.
    case operationInProgress // Indicates another network operation already owns the profile.

    var errorDescription: String? { // Produces concise actionable UI copy.
        switch self { // Selects the matching controller validation message.
        case .profileNotFound: // Handles stale selection state.
            return "The selected remote server no longer exists." // Explains why the requested action cannot continue.
        case .tokenRequired: // Handles missing new bearer credentials.
            return "Enter a bearer token before saving this authenticated server." // Gives a direct corrective action.
        case .operationInProgress: // Handles overlapping profile operations.
            return "Wait for the current server operation to finish." // Preserves one coherent request per server.
        } // Ends controller error rendering.
    } // Ends localized controller error presentation.
} // Ends controller validation failures.

@MainActor // Keeps every published value and user-triggered transition serialized on the SwiftUI actor.
final class RemoteModelsController: ObservableObject { // Coordinates persisted profiles, Keychain token mutations, API health, and discovery for the UI.
    @Published private(set) var profiles: [RemoteServerProfile] = [] // Stores the stable non-secret multi-server list.
    @Published private(set) var healthByServerID: [UUID: ModelBackendHealth] = [:] // Stores the latest explicit API-level observation per server.
    @Published private(set) var modelsByServerID: [UUID: [RemoteDiscoveredModel]] = [:] // Stores normalized discovered models independently per server.
    @Published private(set) var operationByServerID: [UUID: RemoteModelsOperation] = [:] // Stores at most one visible operation for each profile.
    @Published private(set) var isLoading = false // Indicates initial durable profile loading.
    @Published private(set) var isSaving = false // Indicates one profile or token save is in progress.
    @Published private(set) var removingServerIDs: Set<UUID> = [] // Tracks exact profiles undergoing coordinated deletion.
    @Published var notice: RemoteModelsNotice? // Exposes one concise accessible action result.

    private let store: any RemoteServerManaging // Owns durable non-secret profile and secret-vault mutations behind an actor boundary.
    private let inferenceService: any RemoteModelsServicing // Owns network health and discovery away from the main actor.

    convenience init() { // Creates the production controller with the standard Application Support store and Keychain vault.
        let store = RemoteServerStore() // Creates one actor-isolated multi-profile persistence boundary.
        let service = RemoteInferenceBackend(profileProvider: store) // Creates one actor-isolated OpenAI-compatible network backend.
        self.init(store: store, inferenceService: service) // Delegates to the fully injectable designated initializer.
    } // Ends production controller construction.

    init(store: any RemoteServerManaging, inferenceService: any RemoteModelsServicing) { // Creates an injectable controller for deterministic tests and future composition.
        self.store = store // Stores the durable management boundary.
        self.inferenceService = inferenceService // Stores the remote API boundary.
    } // Ends injectable controller construction.

    func load() async { // Loads persisted profiles without blocking SwiftUI rendering.
        guard !isLoading else { // Prevents duplicate view-task loading from racing published state.
            return // Keeps the existing load as the single state owner.
        } // Ends duplicate-load protection.
        isLoading = true // Publishes the initial loading state.
        defer { isLoading = false } // Clears loading state on success or failure.
        do { // Converts durable store outcomes into concise UI state.
            profiles = try await store.allProfiles() // Loads the actor-owned stable multi-server list.
            pruneObservations() // Removes observations for profiles no longer present on disk.
            if profiles.isEmpty { // Handles first-run configuration explicitly.
                notice = RemoteModelsNotice(kind: .information, message: "Add a private OpenAI-compatible server to use remote inference.") // Teaches the empty state without claiming availability.
            } // Ends first-run guidance.
        } catch { // Handles bounded persistence or configuration failures.
            notice = RemoteModelsNotice(kind: .error, message: Self.safeMessage(for: error)) // Publishes safe actionable feedback.
        } // Ends durable profile loading.
    } // Ends initial profile loading.

    @discardableResult // Allows editor UI to dismiss only after confirmed persistence.
    func save(profile: RemoteServerProfile, tokenUpdate: RemoteServerTokenUpdate) async -> Bool { // Persists one profile and applies its separate explicit credential mutation.
        guard !isSaving else { // Prevents overlapping editor submissions.
            notice = RemoteModelsNotice(kind: .error, message: RemoteModelsControllerError.operationInProgress.localizedDescription) // Explains why a second save was ignored.
            return false // Keeps the editor open for a later retry.
        } // Ends duplicate-save protection.
        isSaving = true // Publishes the editor's saving state.
        defer { isSaving = false } // Clears saving state on every outcome.
        do { // Validates UI-specific auth transitions before durable mutation.
            let validated = try profile.validated() // Applies the production endpoint and timeout validation contract.
            let existing = profiles.first { $0.id == validated.id } // Resolves whether this is a new profile or an edit.
            let enablingBearer = validated.authenticationMode == .bearerToken && existing?.authenticationMode != .bearerToken // Detects a new authenticated boundary.
            if enablingBearer { // Requires explicit credential input when bearer authentication is newly enabled.
                guard case .replace(let token) = tokenUpdate, !token.isEmpty else { // Accepts only a non-empty SecureField replacement for the new auth boundary.
                    throw RemoteModelsControllerError.tokenRequired // Prevents saving a knowingly unusable newly authenticated profile.
                } // Ends newly enabled bearer token validation.
            } // Ends new bearer credential validation.
            try await store.save(validated) // Persists only the validated non-secret profile JSON.
            do { // Isolates credential mutation so a failed second persistence boundary can be compensated.
                try await applyTokenUpdate(tokenUpdate, to: validated) // Applies explicit token intent without ever reading an existing credential.
            } catch { // Handles a Keychain or token-boundary failure after profile persistence.
                let knownNewTokens: [String] // Holds only unsaved replacement text already present in the current editor action.
                if case .replace(let token) = tokenUpdate { // Detects a newly supplied credential that an injected boundary might echo unsafely.
                    knownNewTokens = [token] // Makes the exact transient value available only for immediate error redaction.
                } else { // Handles unchanged or removal instructions with no known token value.
                    knownNewTokens = [] // Avoids reading any existing Keychain secret.
                } // Ends transient token selection.
                let originalMessage = Self.safeMessage(for: error, knownSecrets: knownNewTokens) // Preserves the original bounded failure after removing any echoed replacement value.
                let rollbackSucceeded = await compensateProfileSave(previous: existing, attempted: validated) // Restores the prior profile or removes the newly inserted profile best-effort.
                profiles = (try? await store.allProfiles()) ?? profiles // Refreshes any durable state that can still be read after compensation.
                let suffix = rollbackSucceeded ? " Profile changes were rolled back." : " Profile rollback also failed; reload settings before retrying." // Reports compensation outcome without replacing the original cause.
                notice = RemoteModelsNotice(kind: .error, message: Self.bounded(originalMessage + suffix)) // Publishes one bounded combined diagnostic without secret values.
                return false // Keeps the editor open and prevents false success.
            } // Ends cross-boundary compensation handling.
            profiles = try await store.allProfiles() // Refreshes the stable durable list after all mutations succeed.
            healthByServerID[validated.id] = nil // Clears stale health because endpoint or authentication may have changed.
            modelsByServerID[validated.id] = nil // Clears stale discovery because endpoint or backend may have changed.
            notice = RemoteModelsNotice(kind: .success, message: "Saved remote server \(validated.displayName).") // Confirms the exact durable action without exposing endpoint or token.
            return true // Lets the editor dismiss after confirmed persistence.
        } catch { // Handles validation, filesystem, Keychain, or actor failures.
            notice = RemoteModelsNotice(kind: .error, message: Self.safeMessage(for: error)) // Publishes bounded safe feedback.
            return false // Keeps the editor available for correction or retry.
        } // Ends profile and credential persistence.
    } // Ends profile save coordination.

    func remove(serverID: UUID) async { // Removes one exact server after the view obtains user confirmation.
        guard operationByServerID[serverID] == nil, !removingServerIDs.contains(serverID) else { // Prevents removal while the profile owns network work or another delete.
            notice = RemoteModelsNotice(kind: .error, message: RemoteModelsControllerError.operationInProgress.localizedDescription) // Explains the safe serialization rule.
            return // Leaves durable state untouched.
        } // Ends removal serialization.
        guard let profile = profiles.first(where: { $0.id == serverID }) else { // Requires an exact current profile.
            notice = RemoteModelsNotice(kind: .error, message: RemoteModelsControllerError.profileNotFound.localizedDescription) // Explains stale selection state.
            return // Avoids ambiguous deletion.
        } // Ends removal target validation.
        removingServerIDs.insert(serverID) // Publishes the exact destructive operation in progress.
        defer { removingServerIDs.remove(serverID) } // Clears deletion state on every outcome.
        do { // Coordinates production store and Keychain removal.
            try await store.remove(id: serverID) // Removes only the exact profile and its separate vault entry.
            profiles = try await store.allProfiles() // Reloads durable multi-server state.
            healthByServerID[serverID] = nil // Removes stale health for the deleted server.
            modelsByServerID[serverID] = nil // Removes stale model discovery for the deleted server.
            operationByServerID[serverID] = nil // Removes any defensive stale operation entry.
            notice = RemoteModelsNotice(kind: .success, message: "Removed remote server \(profile.displayName).") // Confirms the exact destructive action without endpoint detail.
        } catch { // Handles bounded persistence or Keychain cleanup failures.
            notice = RemoteModelsNotice(kind: .error, message: Self.safeMessage(for: error)) // Publishes safe retry guidance.
        } // Ends coordinated server removal.
    } // Ends confirmed server removal.

    func setEnabled(_ enabled: Bool, serverID: UUID) async { // Updates one server's routing eligibility through the same validated persistence path.
        guard var profile = profiles.first(where: { $0.id == serverID }) else { // Requires an exact current profile.
            notice = RemoteModelsNotice(kind: .error, message: RemoteModelsControllerError.profileNotFound.localizedDescription) // Explains stale toggle state.
            return // Leaves durable state untouched.
        } // Ends toggle target validation.
        profile.isEnabled = enabled // Applies the explicit user choice.
        profile.updatedAt = Date() // Records the durable edit time.
        _ = await save(profile: profile, tokenUpdate: .unchanged) // Reuses validation and stale-observation clearing without touching the token.
    } // Ends enabled-state mutation.

    func testConnection(serverID: UUID) async { // Performs an explicit API-level health check and reuses its discovery cache.
        guard begin(.testingConnection, for: serverID) else { // Acquires exclusive network operation ownership for this profile.
            return // Leaves the existing operation in control.
        } // Ends operation acquisition.
        defer { operationByServerID[serverID] = nil } // Releases operation state on every outcome.
        guard let profile = profiles.first(where: { $0.id == serverID }) else { // Requires an exact configured target.
            notice = RemoteModelsNotice(kind: .error, message: RemoteModelsControllerError.profileNotFound.localizedDescription) // Explains stale selection state.
            return // Avoids a network request for removed configuration.
        } // Ends connection-test target validation.
        let knownModelID = modelsByServerID[serverID]?.first?.id // Uses a previously discovered exact model when available.
        let probeModelID = knownModelID ?? "automlx-api-compatibility-probe" // Supplies a non-empty sentinel used only to validate the models API on first contact.
        let target = ModelGenerationTarget(backendID: profile.backendID, location: .remote(serverID: profile.id), modelID: probeModelID) // Creates the typed transport target without a local path.
        var health = await inferenceService.health(for: target) // Performs the backend's real models-endpoint compatibility and latency check.
        if health.apiCompatible { // Discovers models only after a usable expected API response.
            do { // Reuses the backend's just-refreshed cache rather than issuing a second network request.
                let models = try await inferenceService.discoverModels(serverID: serverID, forceRefresh: false) // Loads normalized models from the fresh per-server observation.
                modelsByServerID[serverID] = models // Publishes actual remote identity and availability.
                if knownModelID == nil, !models.isEmpty, health.status == .degraded { // Recognizes a healthy API whose initial sentinel was naturally absent.
                    health = ModelBackendHealth(status: .healthy, latencyMilliseconds: health.latencyMilliseconds, checkedAt: health.checkedAt, serverKind: health.serverKind, apiCompatible: health.apiCompatible, discoveredModelCount: health.discoveredModelCount, conciseError: nil) // Promotes only evidence-backed API health after at least one real model is discovered.
                } // Ends first-contact health normalization.
            } catch { // Handles a rare cache invalidation or concurrent profile change.
                notice = RemoteModelsNotice(kind: .error, message: Self.safeMessage(for: error)) // Reports safe discovery failure while retaining the health observation.
            } // Ends post-health discovery retrieval.
        } // Ends compatible API model retrieval.
        healthByServerID[serverID] = health // Publishes the complete API-level observation.
        if health.status == .healthy { // Announces a fully usable selected or discovered model path.
            let count = health.discoveredModelCount ?? modelsByServerID[serverID]?.count ?? 0 // Uses only actually reported discovery evidence.
            notice = RemoteModelsNotice(kind: .success, message: "Connection succeeded. Discovered \(count) remote model\(count == 1 ? "" : "s").") // Confirms compatibility and exact model count.
        } else if let error = health.conciseError { // Handles degraded, unavailable, offline, and cancellation observations.
            notice = RemoteModelsNotice(kind: .error, message: error) // Displays the backend's bounded redacted diagnostic.
        } else { // Handles an unusual non-healthy observation without text.
            notice = RemoteModelsNotice(kind: .information, message: "Connection check finished with status \(health.status.rawValue).") // Reports explicit state without inventing a cause.
        } // Ends connection-test result feedback.
    } // Ends explicit API connection testing.

    func refreshModels(serverID: UUID) async { // Performs one explicit uncached model discovery for the selected server.
        guard begin(.refreshingModels, for: serverID) else { // Acquires exclusive network operation ownership for this profile.
            return // Leaves the existing operation in control.
        } // Ends operation acquisition.
        defer { operationByServerID[serverID] = nil } // Releases operation state on every outcome.
        do { // Converts discovery results into isolated published state.
            let models = try await inferenceService.discoverModels(serverID: serverID, forceRefresh: true) // Performs exactly one user-requested live model listing.
            modelsByServerID[serverID] = models // Publishes normalized model metadata for only this server.
            notice = RemoteModelsNotice(kind: .success, message: "Found \(models.count) remote model\(models.count == 1 ? "" : "s").") // Confirms the actual discovery count.
        } catch { // Handles disabled, offline, incompatible, auth, or persistence outcomes.
            notice = RemoteModelsNotice(kind: .error, message: Self.safeMessage(for: error)) // Publishes a bounded redacted failure.
        } // Ends explicit model refresh.
    } // Ends model discovery refresh.

    func operation(for serverID: UUID) -> RemoteModelsOperation? { // Resolves one profile's current visible network activity.
        operationByServerID[serverID] // Returns the exact published operation or nil.
    } // Ends operation lookup.

    func health(for serverID: UUID) -> ModelBackendHealth? { // Resolves one profile's latest explicit health observation.
        healthByServerID[serverID] // Returns actual observed state or nil rather than inventing availability.
    } // Ends health lookup.

    func models(for serverID: UUID) -> [RemoteDiscoveredModel] { // Resolves one profile's isolated normalized model list.
        modelsByServerID[serverID] ?? [] // Returns an empty collection when discovery has not run or found models.
    } // Ends model lookup.

    func canRemove(serverID: UUID) -> Bool { // Determines whether destructive profile removal can proceed safely.
        operationByServerID[serverID] == nil && !removingServerIDs.contains(serverID) && !isSaving // Prevents deletion during profile-owned network work or persistence.
    } // Ends safe removal eligibility.

    private func begin(_ operation: RemoteModelsOperation, for serverID: UUID) -> Bool { // Acquires one profile's exclusive network-operation slot.
        guard profiles.contains(where: { $0.id == serverID }) else { // Requires an exact current profile before publishing work.
            notice = RemoteModelsNotice(kind: .error, message: RemoteModelsControllerError.profileNotFound.localizedDescription) // Explains stale selection state.
            return false // Denies operation acquisition.
        } // Ends operation target validation.
        guard operationByServerID[serverID] == nil, !removingServerIDs.contains(serverID) else { // Prevents overlap with network or destructive work.
            notice = RemoteModelsNotice(kind: .error, message: RemoteModelsControllerError.operationInProgress.localizedDescription) // Explains safe serialization.
            return false // Leaves current ownership unchanged.
        } // Ends exclusive-operation validation.
        operationByServerID[serverID] = operation // Publishes the exact current activity.
        return true // Confirms operation ownership.
    } // Ends profile operation acquisition.

    private func applyTokenUpdate(_ tokenUpdate: RemoteServerTokenUpdate, to profile: RemoteServerProfile) async throws { // Applies one explicit credential instruction after profile persistence.
        if profile.authenticationMode == .none { // Ensures unauthenticated configuration never retains an obsolete credential.
            try await store.setToken(nil, for: profile.id) // Removes only this profile's Keychain entry.
            return // Completes without evaluating an irrelevant bearer update.
        } // Ends unauthenticated cleanup.
        switch tokenUpdate { // Handles an authenticated profile's explicit secret intent.
        case .unchanged: // Keeps an existing Keychain value without reading it into the controller.
            return // Performs no secret access or mutation.
        case .replace(let token): // Handles explicit SecureField input.
            guard !token.isEmpty else { // Rejects replacing a credential with an unusable empty value.
                throw RemoteModelsControllerError.tokenRequired // Keeps the editor open with a corrective message.
            } // Ends replacement token validation.
            try await store.setToken(token, for: profile.id) // Sends the credential directly to the vault boundary.
        case .remove: // Handles explicit credential removal while retaining bearer mode for later repair.
            try await store.setToken(nil, for: profile.id) // Removes the exact Keychain entry.
        } // Ends token mutation selection.
    } // Ends explicit credential application.

    private func compensateProfileSave(previous: RemoteServerProfile?, attempted: RemoteServerProfile) async -> Bool { // Repairs non-secret persistence after a failed token mutation without reading any credential.
        do { // Performs one best-effort exact profile compensation.
            if let previous { // Handles an edit to an existing server.
                try await store.save(previous) // Restores the complete prior non-secret profile snapshot.
            } else { // Handles a newly inserted server whose token could not be persisted.
                try await store.remove(id: attempted.id) // Removes the exact unusable new profile and any partial token entry.
            } // Ends insert-versus-update compensation selection.
            return true // Confirms the profile boundary returned to its prior state.
        } catch { // Handles a secondary persistence or vault failure during compensation.
            return false // Lets the primary caller report bounded rollback failure without masking the original cause.
        } // Ends profile compensation.
    } // Ends best-effort profile rollback.

    private func pruneObservations() { // Removes state that no longer corresponds to a persisted server profile.
        let validIDs = Set(profiles.map(\.id)) // Captures the exact currently configured identifiers.
        healthByServerID = healthByServerID.filter { validIDs.contains($0.key) } // Retains health only for current profiles.
        modelsByServerID = modelsByServerID.filter { validIDs.contains($0.key) } // Retains discovery only for current profiles.
        operationByServerID = operationByServerID.filter { validIDs.contains($0.key) } // Retains work only for current profiles.
        removingServerIDs = removingServerIDs.intersection(validIDs) // Retains destructive state only for current profiles.
    } // Ends stale observation cleanup.

    private static func safeMessage(for error: Error, knownSecrets: [String] = []) -> String { // Produces concise controller feedback without reflecting values or credentials.
        var message = error.localizedDescription // Starts from domain-localized bounded errors from store and backend boundaries.
        for secret in knownSecrets where !secret.isEmpty { // Removes every transient replacement credential known to this immediate action.
            message = message.replacingOccurrences(of: secret, with: "[REDACTED]") // Prevents an injected vault error from echoing new SecureField content.
        } // Ends exact transient-secret redaction.
        message = message.trimmingCharacters(in: .whitespacesAndNewlines) // Produces compact UI-ready feedback after redaction.
        guard !message.isEmpty else { // Handles unexpected errors without a localized description.
            return "The remote server operation failed." // Supplies stable non-sensitive fallback copy.
        } // Ends missing-description handling.
        return bounded(message) // Enforces the same concise UI bound as the remote backend.
    } // Ends safe controller error rendering.

    private static func bounded(_ message: String) -> String { // Enforces one consistent concise UI diagnostic limit.
        guard message.count > 512 else { // Accepts already bounded text unchanged.
            return message // Returns the concise domain diagnostic.
        } // Ends message-length validation.
        return String(message.prefix(509)) + "..." // Truncates excessive unexpected diagnostics without exposing additional content.
    } // Ends controller message bounding.
} // Ends the main-actor remote models controller.
