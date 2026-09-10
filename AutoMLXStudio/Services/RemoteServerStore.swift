import Foundation // Supplies actor-safe persistence primitives, URL construction, UUID, and Codable support.

enum RemoteServerScheme: String, Codable, CaseIterable, Equatable, Sendable { // Restricts configured inference transport schemes to explicit HTTP choices.
    case http // Supports user-owned loopback, LAN, and private-overlay servers with a visible warning when appropriate.
    case https // Supports encrypted private inference endpoints.
} // Ends remote server scheme choices.

enum RemoteAuthenticationMode: String, Codable, CaseIterable, Equatable, Sendable { // Records whether the configured server expects a bearer token.
    case none // Makes unauthenticated private-server operation explicit.
    case bearerToken = "bearer-token" // Retrieves a bearer credential from Keychain only at request construction.
} // Ends remote authentication choices.

struct RemoteServerProfile: Identifiable, Codable, Equatable, Sendable { // Stores non-secret configuration for one user-authorized inference server.
    let id: UUID // Supplies a stable profile identity and Keychain account key.
    var displayName: String // Stores the user-facing server name.
    var backendID: ModelBackendID // Selects the typed remote protocol adapter.
    var scheme: RemoteServerScheme // Selects explicit cleartext or encrypted HTTP transport.
    var host: String // Stores the user-entered host without discovering or scanning the LAN.
    var port: Int // Stores the explicit server port.
    var basePath: String // Stores an optional API prefix such as /v1.
    var authenticationMode: RemoteAuthenticationMode // Records whether a Keychain token is required.
    var connectionTimeoutSeconds: TimeInterval // Bounds discovery and health requests.
    var inferenceTimeoutSeconds: TimeInterval // Bounds model generation independently from connection checks.
    var isEnabled: Bool // Allows the user to disable a profile without deleting it.
    let createdAt: Date // Records durable creation time for deterministic management.
    var updatedAt: Date // Records the latest durable profile edit time.

    init(id: UUID = UUID(), displayName: String, backendID: ModelBackendID = .remoteOpenAICompatible, scheme: RemoteServerScheme = .http, host: String, port: Int, basePath: String = "/v1", authenticationMode: RemoteAuthenticationMode = .none, connectionTimeoutSeconds: TimeInterval = 10, inferenceTimeoutSeconds: TimeInterval = 120, isEnabled: Bool = true, createdAt: Date = Date(), updatedAt: Date = Date()) { // Creates one complete non-secret server profile.
        self.id = id // Stores the stable server identity.
        self.displayName = displayName // Stores the user-facing name.
        self.backendID = backendID // Stores the typed protocol adapter selection.
        self.scheme = scheme // Stores the explicit transport scheme.
        self.host = host // Stores the manually configured host.
        self.port = port // Stores the manually configured port.
        self.basePath = basePath // Stores the optional API path prefix.
        self.authenticationMode = authenticationMode // Stores the explicit authentication mode.
        self.connectionTimeoutSeconds = connectionTimeoutSeconds // Stores the bounded API-check timeout.
        self.inferenceTimeoutSeconds = inferenceTimeoutSeconds // Stores the bounded generation timeout.
        self.isEnabled = isEnabled // Stores whether routing may use this profile.
        self.createdAt = createdAt // Stores the durable creation time.
        self.updatedAt = updatedAt // Stores the durable update time.
    } // Ends server profile construction.

    func validated() throws -> RemoteServerProfile { // Returns a normalized profile only when every persisted field is safe and meaningful.
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines) // Removes accidental surrounding whitespace from the display name.
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines) // Removes accidental surrounding whitespace from the host.
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else { // Requires a concise visible server identity.
            throw RemoteServerConfigurationError.invalidDisplayName // Rejects empty or unbounded names.
        } // Ends display-name validation.
        guard !trimmedHost.isEmpty, trimmedHost.count <= 253, !trimmedHost.contains("://"), !trimmedHost.contains("/"), !trimmedHost.contains("@"), trimmedHost.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { // Requires a host rather than a URL, path, user-info value, or whitespace-bearing string.
            throw RemoteServerConfigurationError.invalidHost // Rejects an ambiguous or unsafe host representation.
        } // Ends host validation.
        guard (1...65_535).contains(port) else { // Restricts ports to the valid TCP range.
            throw RemoteServerConfigurationError.invalidPort // Rejects impossible or sentinel ports.
        } // Ends port validation.
        guard backendID == .remoteOpenAICompatible || backendID == .remoteOllama else { // Prevents a remote profile from masquerading as the local MLX backend.
            throw RemoteServerConfigurationError.invalidBackend // Rejects a location/backend mismatch.
        } // Ends backend validation.
        guard connectionTimeoutSeconds.isFinite, (1...60).contains(connectionTimeoutSeconds) else { // Bounds connection checks to a responsive management interval.
            throw RemoteServerConfigurationError.invalidConnectionTimeout // Rejects non-finite, zero, negative, or excessive checks.
        } // Ends connection-timeout validation.
        guard inferenceTimeoutSeconds.isFinite, (1...3_600).contains(inferenceTimeoutSeconds) else { // Bounds inference while allowing deliberate long local generations.
            throw RemoteServerConfigurationError.invalidInferenceTimeout // Rejects non-finite, zero, negative, or unbounded inference waits.
        } // Ends inference-timeout validation.
        let normalizedPath = try Self.normalizeBasePath(basePath) // Validates and normalizes the optional API prefix.
        var normalized = self // Copies the value before applying harmless normalization.
        normalized.displayName = trimmedName // Persists the trimmed user-facing name.
        normalized.host = trimmedHost // Persists the trimmed explicit host.
        normalized.basePath = normalizedPath // Persists the canonical path prefix.
        _ = try normalized.baseURL() // Proves Foundation can form a complete absolute URL from the normalized fields.
        return normalized // Returns the validated non-secret profile.
    } // Ends profile validation and normalization.

    func baseURL() throws -> URL { // Constructs the API base URL without token, query, fragment, or user-info data.
        var components = URLComponents() // Starts a structured URL to avoid unsafe string concatenation.
        components.scheme = scheme.rawValue // Applies the explicit allowed HTTP scheme.
        components.host = Self.unbracketedHost(host) // Lets URLComponents correctly encode IPv4, DNS, and IPv6 hosts.
        components.port = port // Applies the validated explicit port.
        components.path = try Self.normalizeBasePath(basePath) // Applies only the normalized API prefix.
        guard let url = components.url, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { // Requires an absolute credential-free endpoint.
            throw RemoteServerConfigurationError.invalidURL // Rejects any configuration Foundation cannot represent safely.
        } // Ends URL construction validation.
        return url // Returns the credential-free API base URL.
    } // Ends base URL construction.

    var cleartextSecurityWarning: String? { // Produces an actionable warning for non-loopback cleartext servers without prohibiting LAN use.
        guard scheme == .http, !Self.isLoopback(host: host) else { // Exempts HTTPS and local-only cleartext endpoints.
            return nil // Reports no cleartext boundary warning.
        } // Ends warning applicability validation.
        return "This HTTP server is outside loopback; prompts and code cross the Mac process boundary without transport encryption." // Explains the concrete private-network risk without claiming public exposure.
    } // Ends cleartext warning generation.

    private static func normalizeBasePath(_ path: String) throws -> String { // Canonicalizes the optional API prefix without accepting query or traversal syntax.
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines) // Removes accidental surrounding whitespace.
        if trimmed.isEmpty || trimmed == "/" { // Treats empty and root prefixes equivalently.
            return "" // Uses no prefix before endpoint components.
        } // Ends root-path normalization.
        guard !trimmed.contains("?"), !trimmed.contains("#"), !trimmed.contains("\\"), !trimmed.split(separator: "/", omittingEmptySubsequences: true).contains("..") else { // Rejects query, fragment, alternate separators, and traversal segments.
            throw RemoteServerConfigurationError.invalidBasePath // Prevents ambiguous endpoint construction.
        } // Ends unsafe-path validation.
        let withLeadingSlash = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)" // Ensures an absolute path component.
        return withLeadingSlash.hasSuffix("/") ? String(withLeadingSlash.dropLast()) : withLeadingSlash // Removes one trailing slash for deterministic endpoint appending.
    } // Ends base-path normalization.

    private static func unbracketedHost(_ host: String) -> String { // Normalizes user-friendly bracketed IPv6 input for URLComponents.
        guard host.hasPrefix("["), host.hasSuffix("]"), host.count > 2 else { // Detects a complete bracketed IPv6-style host.
            return host // Leaves DNS, IPv4, and unbracketed IPv6 values unchanged.
        } // Ends bracketed-host detection.
        return String(host.dropFirst().dropLast()) // Removes only the surrounding brackets.
    } // Ends host normalization.

    private static func isLoopback(host: String) -> Bool { // Identifies only explicit local-machine host forms.
        let normalized = unbracketedHost(host).lowercased() // Normalizes case and optional IPv6 brackets.
        return normalized == "localhost" || normalized == "::1" || normalized == "0:0:0:0:0:0:0:1" || normalized.hasPrefix("127.") // Accepts standard DNS, IPv6, expanded IPv6, and IPv4 loopback forms.
    } // Ends loopback detection.
} // Ends persisted non-secret server configuration.

enum RemoteServerConfigurationError: LocalizedError, Equatable, Sendable { // Defines bounded validation and persistence failures for remote configuration.
    case invalidDisplayName // Indicates a missing or excessive display name.
    case invalidHost // Indicates the host contains a URL, path, credentials, whitespace, or no value.
    case invalidPort // Indicates a port outside the valid TCP range.
    case invalidBasePath // Indicates ambiguous endpoint path syntax.
    case invalidBackend // Indicates a local backend was assigned to a remote server profile.
    case invalidConnectionTimeout // Indicates an unsafe management timeout.
    case invalidInferenceTimeout // Indicates an unsafe generation timeout.
    case invalidURL // Indicates Foundation could not create the configured endpoint.
    case profileNotFound // Indicates an operation targeted an unknown profile.
    case persistence(String) // Stores one bounded non-secret persistence diagnostic.

    var errorDescription: String? { // Produces concise actionable descriptions for settings UI and tests.
        switch self { // Selects the matching safe configuration message.
        case .invalidDisplayName: // Handles invalid visible names.
            return "Enter a server name between 1 and 100 characters." // Explains the accepted display-name range.
        case .invalidHost: // Handles malformed hosts.
            return "Enter only a host name or IP address, without a scheme, path, credentials, or spaces." // Explains the host-only contract.
        case .invalidPort: // Handles invalid ports.
            return "Enter a port between 1 and 65535." // Explains the valid TCP range.
        case .invalidBasePath: // Handles malformed API prefixes.
            return "The base path cannot contain traversal, query, fragment, or backslash syntax." // Explains rejected path forms.
        case .invalidBackend: // Handles transport/location mismatch.
            return "A remote server profile requires a remote backend type." // Explains the typed configuration constraint.
        case .invalidConnectionTimeout: // Handles invalid connection bounds.
            return "Connection timeout must be between 1 and 60 seconds." // Explains the management bound.
        case .invalidInferenceTimeout: // Handles invalid inference bounds.
            return "Inference timeout must be between 1 and 3600 seconds." // Explains the generation bound.
        case .invalidURL: // Handles URL construction failure.
            return "The server URL could not be constructed from this configuration." // Avoids echoing potentially sensitive input.
        case .profileNotFound: // Handles unknown profile operations.
            return "The remote server profile no longer exists." // Explains possible concurrent removal safely.
        case .persistence(let message): // Handles bounded persistence failures.
            return message // Returns the already bounded non-secret message.
        } // Ends configuration error rendering.
    } // Ends localized error presentation.
} // Ends remote server configuration errors.

protocol RemoteServerProfileProviding: Sendable { // Supplies immutable profile snapshots and boundary-only tokens to remote backends.
    func profile(id: UUID) async throws -> RemoteServerProfile? // Reads one current non-secret profile snapshot.
    func token(for id: UUID) async throws -> String? // Reads one token only when a network request requires it.
} // Ends the remote profile provider boundary.

actor RemoteServerStore: RemoteServerProfileProviding { // Serializes multi-server persistence and Keychain coordination without assuming a global singleton.
    private struct Document: Codable { // Wraps persisted profiles in an explicitly versioned non-secret document.
        let schemaVersion: Int // Records the durable schema version.
        var profiles: [RemoteServerProfile] // Stores all configured non-secret server profiles.
    } // Ends the persisted document shape.

    private let fileURL: URL // Identifies the exact application-support JSON document.
    private let tokenVault: any RemoteServerTokenVault // Keeps credentials outside the JSON document behind an injectable boundary.
    private let fileManager: FileManager // Owns filesystem access within this actor.
    private var cachedDocument: Document? // Caches one actor-isolated decoded document after first access.

    init(fileURL: URL = RemoteServerStore.defaultFileURL(), tokenVault: any RemoteServerTokenVault = KeychainRemoteServerTokenVault(), fileManager: FileManager = .default) { // Creates a multi-profile store with injectable durable boundaries.
        self.fileURL = fileURL // Stores the exact non-secret document location.
        self.tokenVault = tokenVault // Stores the secret boundary implementation.
        self.fileManager = fileManager // Stores the filesystem boundary used by this actor only.
    } // Ends remote server store construction.

    static func defaultFileURL(fileManager: FileManager = .default) -> URL { // Resolves the standard per-user Application Support location without touching disk.
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory // Falls back safely only when the system directory cannot be resolved.
        return root.appendingPathComponent("AutoMLXStudio", isDirectory: true).appendingPathComponent("RemoteServers.json", isDirectory: false) // Returns the exact versioned store file path.
    } // Ends default store-path resolution.

    func allProfiles() async throws -> [RemoteServerProfile] { // Returns every configured profile in stable display order.
        let document = try loadDocumentIfNeeded() // Loads and validates the durable document once per actor lifetime.
        return document.profiles.sorted { lhs, rhs in // Produces deterministic UI and test ordering.
            if lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedSame { // Resolves duplicate visible names deterministically.
                return lhs.id.uuidString < rhs.id.uuidString // Uses the stable opaque identity as a tie-breaker.
            } // Ends duplicate-name tie breaking.
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending // Sorts names without changing persisted values.
        } // Ends stable profile ordering.
    } // Ends all-profile retrieval.

    func profile(id: UUID) async throws -> RemoteServerProfile? { // Returns one immutable profile snapshot for routing or network use.
        try loadDocumentIfNeeded().profiles.first { $0.id == id } // Looks up only the exact stable identifier.
    } // Ends profile lookup.

    func save(_ profile: RemoteServerProfile) async throws { // Inserts or replaces one validated non-secret profile atomically.
        let validated = try profile.validated() // Rejects malformed configuration before changing durable state.
        var document = try loadDocumentIfNeeded() // Starts from the latest actor-isolated snapshot.
        if let index = document.profiles.firstIndex(where: { $0.id == validated.id }) { // Detects an edit to an existing profile.
            document.profiles[index] = validated // Replaces only the exact matching profile.
        } else { // Handles a new independently configured server.
            document.profiles.append(validated) // Adds the profile without imposing a singleton assumption.
        } // Ends insert-or-replace selection.
        try persist(document) // Atomically writes the complete non-secret document.
        cachedDocument = document // Publishes the new actor-local snapshot only after a successful write.
    } // Ends profile persistence.

    func remove(id: UUID) async throws { // Removes one exact profile and its Keychain token without affecting other servers.
        var document = try loadDocumentIfNeeded() // Starts from the current actor-local snapshot.
        guard let index = document.profiles.firstIndex(where: { $0.id == id }) else { // Requires an existing exact target.
            throw RemoteServerConfigurationError.profileNotFound // Avoids treating an ambiguous removal as success.
        } // Ends removal-target validation.
        let previousToken = try tokenVault.token(for: id) // Reads the current secret only to support rollback if the document write fails.
        try tokenVault.setToken(nil, for: id) // Removes the token before making the profile unreachable.
        document.profiles.remove(at: index) // Removes only the exact matching non-secret profile.
        do { // Protects cross-boundary consistency during atomic document persistence.
            try persist(document) // Writes the profile removal atomically.
            cachedDocument = document // Publishes the new snapshot only after persistence succeeds.
        } catch { // Handles a rare filesystem failure after Keychain deletion.
            try? tokenVault.setToken(previousToken, for: id) // Best-effort restores the prior credential without masking the original error.
            throw error // Returns the bounded persistence failure to the caller.
        } // Ends removal rollback handling.
    } // Ends profile removal.

    func token(for id: UUID) async throws -> String? { // Retrieves a token only for an existing profile and only through the vault boundary.
        guard try loadDocumentIfNeeded().profiles.contains(where: { $0.id == id }) else { // Prevents orphan account access through arbitrary UUIDs.
            throw RemoteServerConfigurationError.profileNotFound // Reports that the requested configuration no longer exists.
        } // Ends profile existence validation.
        return try tokenVault.token(for: id) // Returns the Keychain value without copying it into cached profile state.
    } // Ends boundary-only token retrieval.

    func setToken(_ token: String?, for id: UUID) async throws { // Mutates one credential independently from the non-secret profile document.
        guard try loadDocumentIfNeeded().profiles.contains(where: { $0.id == id }) else { // Requires an existing exact server identity.
            throw RemoteServerConfigurationError.profileNotFound // Prevents creation of orphan Keychain entries.
        } // Ends token-target validation.
        try tokenVault.setToken(token, for: id) // Delegates secret persistence directly to the injected vault.
    } // Ends token mutation.

    private func loadDocumentIfNeeded() throws -> Document { // Loads the durable non-secret document exactly once per actor lifetime.
        if let cachedDocument { // Reuses the actor-isolated snapshot after successful initial loading.
            return cachedDocument // Avoids repeated disk reads and decode races.
        } // Ends cache-hit handling.
        guard fileManager.fileExists(atPath: fileURL.path) else { // Treats a never-configured application as an empty multi-server store.
            let empty = Document(schemaVersion: 1, profiles: []) // Creates the current empty document in memory without touching disk.
            cachedDocument = empty // Caches the empty state for subsequent operations.
            return empty // Returns the empty profile collection.
        } // Ends missing-file handling.
        do { // Bounds filesystem and decode failures behind a safe configuration error.
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe]) // Reads only the exact configured JSON document.
            let decoder = JSONDecoder() // Creates a deterministic decoder for the versioned document.
            decoder.dateDecodingStrategy = .iso8601 // Restores stable human-inspectable timestamps.
            let document = try decoder.decode(Document.self, from: data) // Decodes only declared non-secret profile fields.
            guard document.schemaVersion == 1 else { // Rejects unknown future schemas instead of overwriting them.
                throw RemoteServerConfigurationError.persistence("Remote server settings use an unsupported schema version.") // Reports a bounded migration requirement.
            } // Ends schema-version validation.
            let validatedProfiles = try document.profiles.map { try $0.validated() } // Revalidates persisted configuration before network use.
            let validated = Document(schemaVersion: document.schemaVersion, profiles: validatedProfiles) // Builds a normalized actor-local snapshot.
            cachedDocument = validated // Caches only successfully validated durable state.
            return validated // Returns the validated document.
        } catch let error as RemoteServerConfigurationError { // Preserves already bounded configuration errors.
            throw error // Returns the safe domain error unchanged.
        } catch { // Handles raw filesystem or decoding failures.
            throw RemoteServerConfigurationError.persistence("Remote server settings could not be loaded safely.") // Avoids leaking paths, JSON contents, or credentials.
        } // Ends durable document loading.
    } // Ends lazy document loading.

    private func persist(_ document: Document) throws { // Writes the complete non-secret document atomically.
        do { // Bounds filesystem and encoding details behind a safe configuration error.
            let directory = fileURL.deletingLastPathComponent() // Identifies only the exact parent directory for this store.
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) // Creates missing application-support parents without broad filesystem mutation.
            let encoder = JSONEncoder() // Creates a deterministic non-secret JSON encoder.
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys] // Produces stable inspectable persistence for diagnostics and tests.
            encoder.dateEncodingStrategy = .iso8601 // Stores timestamps in a stable portable representation.
            let data = try encoder.encode(document) // Encodes only schema version and profile fields.
            try data.write(to: fileURL, options: [.atomic]) // Atomically replaces only the exact store document.
        } catch { // Handles raw encoding and filesystem failures.
            throw RemoteServerConfigurationError.persistence("Remote server settings could not be saved safely.") // Avoids leaking paths or underlying payload content.
        } // Ends atomic persistence.
    } // Ends durable document writing.
} // Ends the actor-isolated remote server store.
