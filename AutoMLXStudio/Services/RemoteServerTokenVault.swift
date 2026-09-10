import Foundation // Supplies UUID, Data, and localized error support for the token boundary.
import Security // Supplies the macOS Keychain APIs used for durable secret storage.

protocol RemoteServerTokenVault: Sendable { // Isolates authentication persistence so tests never need the real user Keychain.
    func token(for serverID: UUID) throws -> String? // Reads one server token without exposing it through profile persistence.
    func setToken(_ token: String?, for serverID: UUID) throws // Adds, replaces, or removes one server token at the secret boundary.
} // Ends the injectable token-vault contract.

enum RemoteServerTokenVaultError: LocalizedError, Equatable, Sendable { // Reports bounded Keychain failures without including credential material.
    case keychain(operation: String, status: OSStatus) // Stores only the failed operation and system status code.
    case invalidEncoding // Indicates Keychain bytes were not valid UTF-8 token data.

    var errorDescription: String? { // Produces a concise secret-free diagnostic for UI and tests.
        switch self { // Selects the bounded error presentation.
        case .keychain(let operation, let status): // Handles a Security framework failure.
            return "Keychain \(operation) failed (status \(status))." // Omits query values, account names, and token contents.
        case .invalidEncoding: // Handles corrupted Keychain token bytes.
            return "The saved server token could not be decoded." // Reports corruption without exposing stored bytes.
        } // Ends token-vault error rendering.
    } // Ends the localized error description.
} // Ends token-vault error definitions.

final class KeychainRemoteServerTokenVault: RemoteServerTokenVault, @unchecked Sendable { // Persists remote tokens in the user Keychain behind a stateless thread-safe API.
    private let service: String // Names the application-specific generic-password service.

    init(service: String = "com.tommaso.AutoMLXStudio.remote-server-token") { // Creates the production vault with a stable isolated service name.
        self.service = service // Stores only the non-secret Keychain namespace.
    } // Ends production vault construction.

    func token(for serverID: UUID) throws -> String? { // Reads a token for one configured server identifier.
        var query = baseQuery(for: serverID) // Starts from the stable class, service, and account key.
        query[kSecReturnData as String] = true // Requests secret bytes only at this boundary.
        query[kSecMatchLimit as String] = kSecMatchLimitOne // Bounds lookup to one exact account.
        var result: CFTypeRef? // Receives the Security framework result without logging it.
        let status = SecItemCopyMatching(query as CFDictionary, &result) // Performs the exact Keychain lookup.
        if status == errSecItemNotFound { // Treats an absent token as an explicit unauthenticated configuration.
            return nil // Returns no credential without raising an operational error.
        } // Ends missing-item handling.
        guard status == errSecSuccess else { // Rejects all other Security framework failures.
            throw RemoteServerTokenVaultError.keychain(operation: "read", status: status) // Reports only the safe operation and numeric status.
        } // Ends read-status validation.
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else { // Validates the stored representation without printing bytes.
            throw RemoteServerTokenVaultError.invalidEncoding // Rejects corrupted non-text token data safely.
        } // Ends token decoding validation.
        return token // Returns the credential only to the authorized caller at the network boundary.
    } // Ends token lookup.

    func setToken(_ token: String?, for serverID: UUID) throws { // Adds, replaces, or deletes the credential for one exact profile.
        guard let token, !token.isEmpty else { // Treats nil or empty input as an explicit credential removal.
            let status = SecItemDelete(baseQuery(for: serverID) as CFDictionary) // Deletes only the matching service/account item.
            guard status == errSecSuccess || status == errSecItemNotFound else { // Accepts deletion and already-absent states.
                throw RemoteServerTokenVaultError.keychain(operation: "delete", status: status) // Reports a secret-free deletion failure.
            } // Ends delete-status validation.
            return // Completes the removal without performing an add or update.
        } // Ends token-removal handling.
        let encodedToken = Data(token.utf8) // Encodes the credential only inside the Keychain boundary.
        let updateAttributes = [kSecValueData as String: encodedToken] as CFDictionary // Builds a replacement payload containing no loggable description.
        let updateStatus = SecItemUpdate(baseQuery(for: serverID) as CFDictionary, updateAttributes) // Attempts an in-place replacement first.
        if updateStatus == errSecSuccess { // Handles an existing credential successfully.
            return // Completes after the atomic Keychain update.
        } // Ends successful replacement handling.
        guard updateStatus == errSecItemNotFound else { // Rejects unexpected update failures before attempting an add.
            throw RemoteServerTokenVaultError.keychain(operation: "update", status: updateStatus) // Reports only safe failure metadata.
        } // Ends update-status validation.
        var insertion = baseQuery(for: serverID) // Starts a new exact generic-password record.
        insertion[kSecValueData as String] = encodedToken // Adds the secret bytes only to the Security framework query.
        let addStatus = SecItemAdd(insertion as CFDictionary, nil) // Persists the new Keychain item.
        guard addStatus == errSecSuccess else { // Rejects any failed insertion.
            throw RemoteServerTokenVaultError.keychain(operation: "write", status: addStatus) // Reports no query or credential details.
        } // Ends insertion-status validation.
    } // Ends token mutation.

    private func baseQuery(for serverID: UUID) -> [String: Any] { // Builds the non-secret exact-match Keychain identity.
        [ // Starts the Security framework query dictionary.
            kSecClass as String: kSecClassGenericPassword, // Stores tokens as generic passwords rather than files or certificates.
            kSecAttrService as String: service, // Isolates values under the application service namespace.
            kSecAttrAccount as String: serverID.uuidString // Uses only the opaque server UUID as the account key.
        ] // Ends the exact-match Keychain identity.
    } // Ends base query construction.
} // Ends the production Keychain token vault.
