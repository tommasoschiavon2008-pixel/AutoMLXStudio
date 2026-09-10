import Foundation // Supplies isolated temporary directories, deterministic dates, and raw JSON fixtures.
import XCTest // Supplies asynchronous actor-aware persistence assertions.
@testable import AutoMLXStudio // Exposes internal conversation models and the actor store to the permanent suite.

final class ConversationStorePersistenceTests: XCTestCase { // Verifies durable restart behavior, schema output, defaults, and legacy migration.
    func testConversationAndPreferencesSurviveFreshStoreRestart() async throws { // Proves all required fields survive a new actor instance reading the atomic snapshot.
        let root = Self.temporaryRoot(named: "Restart") // Allocates one exact test-owned persistence directory.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only the isolated fixture after the assertion run.
        let projectID = UUID() // Creates one stable project association.
        let conversationID = UUID() // Creates one stable identity whose restart preservation is asserted.
        let createdAt = Date(timeIntervalSince1970: 1_787_000_000) // Uses a whole-second timestamp compatible with ISO-8601 round trips.
        let userMessage = ChatMessage(id: UUID(), role: "user", content: "What did we decide about the offline API?") // Supplies the visible first user message used for deterministic title derivation.
        let assistantMessage = ChatMessage(id: UUID(), role: "assistant", content: "The project selected a local API.") // Supplies one visible assistant response without hidden runtime fields.
        let firstStore = ConversationStore(rootURL: root) // Creates the initial actor instance.
        let created = try await firstStore.createConversation(id: conversationID, projectID: projectID, messages: [userMessage], qualityOverride: .thorough, now: createdAt) // Atomically creates the project chat with its preferences.
        _ = try await firstStore.append(assistantMessage, to: conversationID, now: createdAt.addingTimeInterval(10)) // Atomically appends the visible response.
        let restartedStore = ConversationStore(rootURL: root) // Creates a fresh actor with no shared in-memory state.
        let restored = try await restartedStore.conversation(id: conversationID) // Loads the exact stable UUID from disk.
        XCTAssertEqual(restored.id, created.id) // Confirms stable conversation identity across restart.
        XCTAssertEqual(restored.projectID, projectID) // Confirms project association across restart.
        XCTAssertEqual(restored.title, "What did we decide about the offline API?") // Confirms deterministic visible title persistence.
        XCTAssertEqual(restored.messages, [userMessage, assistantMessage]) // Confirms exact visible history persistence.
        XCTAssertEqual(restored.createdAt, createdAt) // Confirms immutable creation time persistence.
        XCTAssertEqual(restored.updatedAt, createdAt.addingTimeInterval(10)) // Confirms latest activity persistence.
        XCTAssertTrue(restored.useProjectMemory) // Confirms the project-aware memory preference persists.
        XCTAssertEqual(restored.qualityOverride, .thorough) // Confirms the optional quality override persists.
        let snapshotData = try Data(contentsOf: root.appendingPathComponent(ConversationStore.snapshotFilename)) // Reads the isolated app-owned test transaction for schema verification.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any]) // Parses only top-level schema metadata for an implementation-independent assertion.
        XCTAssertEqual(json["schemaVersion"] as? Int, ConversationPersistenceSchema.currentVersion) // Confirms every mutation writes the current explicit schema version.
    } // Ends restart durability test.

    func testMemoryAndQualityDefaultsDependOnlyOnProjectAssociation() async throws { // Verifies documented defaults without any model or global application state.
        let root = Self.temporaryRoot(named: "Defaults") // Allocates one exact isolated persistence root.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only this test-owned root.
        let store = ConversationStore(rootURL: root) // Creates the actor under test.
        let ordinary = try await store.createConversation(now: Date(timeIntervalSince1970: 1_787_000_100)) // Creates an ordinary chat with no explicit preference values.
        let project = try await store.createConversation(projectID: UUID(), now: Date(timeIntervalSince1970: 1_787_000_101)) // Creates a project chat with no explicit preference values.
        XCTAssertFalse(ordinary.useProjectMemory) // Confirms ordinary conversations default Project Memory OFF.
        XCTAssertTrue(project.useProjectMemory) // Confirms project conversations default Project Memory ON.
        XCTAssertNil(ordinary.qualityOverride) // Confirms ordinary conversations inherit the application quality policy.
        XCTAssertNil(project.qualityOverride) // Confirms project conversations also inherit policy until explicitly overridden.
        XCTAssertEqual(ordinary.title, Conversation.defaultTitle) // Confirms empty conversations use the deterministic placeholder title.
        XCTAssertEqual(project.title, Conversation.defaultTitle) // Confirms project association does not alter title behavior.
    } // Ends preference-default test.

    func testLegacyUnwrappedRecordMigratesMissingPreferencesSafely() async throws { // Proves backward compatibility for schema-zero JSON without new preference fields.
        let root = Self.temporaryRoot(named: "Legacy") // Allocates one exact legacy fixture root.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only the isolated fixture.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) // Creates the exact destination directory for the legacy snapshot.
        let conversationID = UUID() // Creates the stable legacy conversation identity.
        let projectID = UUID() // Creates the legacy project association used to infer memory ON.
        let messageID = UUID() // Creates the stable visible legacy message identity.
        let legacyJSON = [ // Defines a schema-zero unwrapped array with fields that predate memory and quality preferences.
            "[", // Opens the legacy conversation array.
            "  {", // Opens the single legacy conversation object.
            "    \"id\": \"\(conversationID.uuidString)\",", // Stores the stable conversation identity.
            "    \"projectID\": \"\(projectID.uuidString)\",", // Stores the project association.
            "    \"messages\": [", // Opens the visible legacy message array.
            "      {", // Opens the single visible user message.
            "        \"id\": \"\(messageID.uuidString)\",", // Stores the stable message identity.
            "        \"role\": \"user\",", // Stores the public user role.
            "        \"content\": \"Recall the project decision\"", // Stores the visible message content.
            "      }", // Closes the visible user message.
            "    ],", // Closes the visible message array.
            "    \"createdAt\": \"2026-08-19T12:00:00Z\",", // Stores a deterministic legacy creation time.
            "    \"updatedAt\": \"2026-08-19T12:00:00Z\"", // Stores a deterministic legacy activity time.
            "  }", // Closes the legacy conversation object.
            "]" // Closes the legacy conversation array.
        ].joined(separator: "\n") // Produces valid bounded legacy JSON deterministically.
        try Data(legacyJSON.utf8).write(to: root.appendingPathComponent(ConversationStore.snapshotFilename), options: .atomic) // Writes only the isolated legacy fixture atomically.
        let store = ConversationStore(rootURL: root) // Creates a fresh actor over the legacy snapshot.
        let restored = try await store.conversation(id: conversationID) // Runs array migration and field-level defaults.
        XCTAssertEqual(restored.title, "Recall the project decision") // Confirms a missing title derives from the first visible user message.
        XCTAssertTrue(restored.useProjectMemory) // Confirms a missing preference defaults ON for an associated project.
        XCTAssertNil(restored.qualityOverride) // Confirms a missing quality field continues to inherit global policy.
        XCTAssertFalse(restored.titleWasEdited) // Confirms the derived title remains eligible for deterministic first-message behavior.
        _ = try await store.renameConversation(id: conversationID, title: "Migrated conversation") // Forces one current-schema atomic mutation.
        let migratedData = try Data(contentsOf: root.appendingPathComponent(ConversationStore.snapshotFilename)) // Reads the rewritten isolated transaction.
        let migratedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: migratedData) as? [String: Any]) // Parses the rewritten schema envelope.
        XCTAssertEqual(migratedJSON["schemaVersion"] as? Int, ConversationPersistenceSchema.currentVersion) // Confirms a legacy mutation upgrades persistence to the current schema.
    } // Ends legacy migration test.

    private static func temporaryRoot(named name: String) -> URL { // Creates a unique path without mutating the filesystem until the store writes.
        FileManager.default.temporaryDirectory.appendingPathComponent("ConversationStore-\(name)-\(UUID().uuidString)", isDirectory: true) // Returns one exact test-owned containment root.
    } // Ends temporary-root construction.
} // Ends durable persistence and compatibility tests.

final class ConversationStoreMutationTests: XCTestCase { // Verifies deterministic title behavior, identity-preserving edits, isolation, and deletion policy.
    func testTitleDerivationIsBoundedEditableAndValidated() async throws { // Exercises automatic first-user derivation and explicit title validation without an LLM call.
        let root = Self.temporaryRoot(named: "Titles") // Allocates one exact isolated persistence root.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only this test-owned fixture.
        let store = ConversationStore(rootURL: root) // Creates the actor under test.
        let created = try await store.createConversation(now: Date(timeIntervalSince1970: 1_787_000_200)) // Creates an untitled empty chat.
        let firstText = "   Explain\n  the   deterministic\ttitle behavior for this project   " // Supplies irregular visible whitespace for normalization.
        let afterFirstMessage = try await store.append(ChatMessage(role: "user", content: firstText), to: created.id, now: Date(timeIntervalSince1970: 1_787_000_201)) // Appends the first visible user request.
        XCTAssertEqual(afterFirstMessage.title, "Explain the deterministic title behavior for this project") // Confirms deterministic one-line derivation.
        let afterSecondMessage = try await store.append(ChatMessage(role: "user", content: "A different later request"), to: created.id, now: Date(timeIntervalSince1970: 1_787_000_202)) // Appends a later user request.
        XCTAssertEqual(afterSecondMessage.title, afterFirstMessage.title) // Confirms only the first visible user request determines the automatic title.
        let longText = Array(repeating: "bounded title words", count: 10).joined(separator: " ") // Creates a visible request longer than the title contract.
        let derived = Conversation.derivedTitle(from: [ChatMessage(role: "user", content: longText)]) // Runs pure deterministic derivation directly.
        XCTAssertLessThanOrEqual(derived.count, Conversation.maximumTitleLength) // Confirms derived titles never exceed the editable title limit.
        XCTAssertTrue(derived.hasSuffix("…")) // Confirms truncation remains visible rather than silently clipping content.
        do { // Attempts a whitespace-only explicit rename.
            _ = try await store.renameConversation(id: created.id, title: " \n\t ") // Exercises empty-title validation through the public mutation API.
            XCTFail("Whitespace-only titles must be rejected.") // Fails if an invisible sidebar title reaches persistence.
        } catch let error as ConversationStoreError { // Captures the expected typed title failure.
            guard case .invalidTitle = error else { return XCTFail("Expected invalidTitle, received \(error).") } // Confirms the exact validation category.
        } // Ends empty-title rejection.
        do { // Attempts an explicit title beyond the reasonable length contract.
            _ = try await store.renameConversation(id: created.id, title: String(repeating: "x", count: Conversation.maximumTitleLength + 1)) // Exercises overlong-title validation.
            XCTFail("Overlong explicit titles must be rejected.") // Fails if user text would be silently truncated during rename.
        } catch let error as ConversationStoreError { // Captures the expected typed title failure.
            guard case .invalidTitle = error else { return XCTFail("Expected invalidTitle, received \(error).") } // Confirms the same shared title contract.
        } // Ends overlong-title rejection.
    } // Ends deterministic title and validation test.

    func testRenameAndFullUpdatePreserveStableIdentityAndCreationMetadata() async throws { // Verifies selection-independent edits cannot replace durable identity fields.
        let root = Self.temporaryRoot(named: "Rename") // Allocates one exact isolated persistence root.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only this test-owned root.
        let store = ConversationStore(rootURL: root) // Creates the actor under test.
        let projectID = UUID() // Creates one stable project owner.
        let createdAt = Date(timeIntervalSince1970: 1_787_000_300) // Uses a deterministic whole-second creation time.
        let originalMessage = ChatMessage(role: "user", content: "Original request") // Creates one visible message whose retention is asserted.
        let created = try await store.createConversation(projectID: projectID, messages: [originalMessage], now: createdAt) // Persists the original chat.
        let renamed = try await store.renameConversation(id: created.id, title: "  Durable   name  ", now: createdAt.addingTimeInterval(5)) // Renames with whitespace normalization.
        XCTAssertEqual(renamed.id, created.id) // Confirms rename preserves the stable UUID.
        XCTAssertEqual(renamed.projectID, projectID) // Confirms rename preserves project ownership.
        XCTAssertEqual(renamed.messages, [originalMessage]) // Confirms rename preserves visible history.
        XCTAssertEqual(renamed.createdAt, createdAt) // Confirms rename preserves immutable creation time.
        XCTAssertEqual(renamed.title, "Durable name") // Confirms safe visible normalization.
        var candidate = renamed // Copies the durable value for a selection-independent full update.
        candidate.useProjectMemory = false // Applies an explicit retrieval preference change.
        candidate.qualityOverride = .balanced // Applies an explicit quality override.
        let updated = try await store.updateConversation(candidate, now: createdAt.addingTimeInterval(10)) // Atomically updates only editable fields by UUID.
        XCTAssertEqual(updated.id, created.id) // Confirms full update preserves stable identity.
        XCTAssertEqual(updated.createdAt, createdAt) // Confirms full update preserves creation metadata.
        XCTAssertFalse(updated.useProjectMemory) // Confirms the preference mutation persists.
        XCTAssertEqual(updated.qualityOverride, .balanced) // Confirms the quality mutation persists.
    } // Ends identity-preserving rename and update test.

    func testProjectFilteringAndDeletionRemainStrictlyIsolated() async throws { // Verifies exact ownership filtering and the explicit delete-project-conversations policy.
        let root = Self.temporaryRoot(named: "Isolation") // Allocates one test containment root.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only the isolated test fixture.
        let storeRoot = root.appendingPathComponent("store", isDirectory: true) // Separates app-owned conversation persistence from an external-source sentinel.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) // Creates the sentinel's parent directory.
        let sourceSentinel = root.appendingPathComponent("source-document.md") // Resolves a file that conversation deletion must never touch.
        try Data("User-owned source".utf8).write(to: sourceSentinel, options: .atomic) // Writes the isolated stand-in for a user's project document.
        let store = ConversationStore(rootURL: storeRoot) // Creates the actor in its dedicated child directory.
        let alphaProject = UUID() // Creates the project selected for conversation deletion.
        let betaProject = UUID() // Creates a distinct project that must remain untouched.
        let alphaOne = try await store.createConversation(projectID: alphaProject, title: "Alpha one") // Creates the first Alpha conversation.
        let alphaTwo = try await store.createConversation(projectID: alphaProject, title: "Alpha two") // Creates the second Alpha conversation.
        let beta = try await store.createConversation(projectID: betaProject, title: "Beta") // Creates the isolated Beta conversation.
        let ordinary = try await store.createConversation(title: "Ordinary") // Creates an unassigned normal conversation.
        let alphaBeforeDelete = try await store.conversations(projectID: alphaProject) // Reads only Alpha ownership before deletion.
        let ordinaryBeforeDelete = try await store.listConversations(scope: .withoutProject) // Reads only ordinary chats before deletion.
        XCTAssertEqual(Set(alphaBeforeDelete.map(\.id)), Set([alphaOne.id, alphaTwo.id])) // Confirms exact project filtering.
        XCTAssertEqual(ordinaryBeforeDelete.map(\.id), [ordinary.id]) // Confirms nil-project filtering does not include either project.
        let removedCount = try await store.deleteConversations(projectID: alphaProject) // Applies the explicit project-conversation deletion policy.
        XCTAssertEqual(removedCount, 2) // Confirms only Alpha's two chat records were removed.
        let alphaAfterDelete = try await store.conversations(projectID: alphaProject) // Reads Alpha ownership after the atomic deletion outside an XCTest autoclosure.
        XCTAssertTrue(alphaAfterDelete.isEmpty) // Confirms no Alpha conversations remain.
        let remainingIDs = Set(try await store.listConversations().map(\.id)) // Reads all remaining identities after the atomic deletion.
        XCTAssertEqual(remainingIDs, Set([beta.id, ordinary.id])) // Confirms Beta and ordinary chats remain isolated.
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceSentinel.path)) // Confirms conversation policy never deletes a user-owned source document.
        _ = try await store.deleteConversation(id: beta.id) // Exercises exact single-conversation deletion.
        let finalIDs = Set(try await store.listConversations().map(\.id)) // Reads the final durable identity set.
        XCTAssertEqual(finalIDs, Set([ordinary.id])) // Confirms single deletion does not affect the remaining normal chat.
    } // Ends project filtering and delete-policy test.

    func testHiddenMessageRolesAreRejectedWithoutChangingDurableHistory() async throws { // Proves internal prompts and reasoning-role records cannot be persisted through the append API.
        let root = Self.temporaryRoot(named: "Roles") // Allocates one exact isolated persistence root.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only this test-owned fixture.
        let store = ConversationStore(rootURL: root) // Creates the actor under test.
        let conversation = try await store.createConversation(title: "Visible chat") // Persists one empty ordinary conversation.
        do { // Attempts to append an internal system prompt as though it were visible history.
            _ = try await store.append(ChatMessage(role: "system", content: "Hidden application instruction"), to: conversation.id) // Exercises the no-hidden-prompt boundary.
            XCTFail("System-role messages must never enter conversation persistence.") // Fails if the hidden role is accepted.
        } catch let error as ConversationStoreError { // Captures the expected typed role rejection.
            guard case .invalidMessageRole = error else { return XCTFail("Expected invalidMessageRole, received \(error).") } // Confirms the exact policy failure.
        } // Ends hidden-role rejection.
        let restored = try await store.conversation(id: conversation.id) // Reloads the durable record after the rejected mutation.
        XCTAssertTrue(restored.messages.isEmpty) // Confirms validation occurred before any atomic write.
    } // Ends no-hidden-message test.

    private static func temporaryRoot(named name: String) -> URL { // Creates a unique path without touching unrelated filesystem state.
        FileManager.default.temporaryDirectory.appendingPathComponent("ConversationStore-\(name)-\(UUID().uuidString)", isDirectory: true) // Returns one exact test-owned containment root.
    } // Ends mutation-test root construction.
} // Ends conversation mutation and isolation tests.

final class ConversationStoreCorruptionTests: XCTestCase { // Verifies malformed persistence produces a typed bounded error instead of silent data loss.
    func testMalformedSnapshotReportsTypedBoundedCorruption() async throws { // Loads deliberately malformed JSON through a fresh actor.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConversationStore-Corruption-\(UUID().uuidString)", isDirectory: true) // Allocates one exact isolated corruption fixture.
        defer { try? FileManager.default.removeItem(at: root) } // Removes only this test-owned fixture.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) // Creates the exact snapshot parent directory.
        let malformed = "{\"schemaVersion\":1,\"conversations\":[{\"invalid\":\"\(String(repeating: "x", count: 1_000))\"}]}" // Creates valid JSON with an invalid conversation shape and deliberately long source detail.
        try Data(malformed.utf8).write(to: root.appendingPathComponent(ConversationStore.snapshotFilename), options: .atomic) // Writes only the isolated app-owned fixture path.
        let store = ConversationStore(rootURL: root) // Creates a fresh actor with no cached state.
        do { // Attempts to list the corrupted durable collection.
            _ = try await store.listConversations() // Exercises schema probing, full decoding, and bounded error conversion.
            XCTFail("Malformed conversation JSON must not be treated as an empty store.") // Fails if corruption is hidden or data is silently discarded.
        } catch let error as ConversationStoreError { // Captures the expected typed storage failure.
            guard case let .corruptedStore(detail) = error else { return XCTFail("Expected corruptedStore, received \(error).") } // Confirms corruption remains distinguishable from validation and filesystem failures.
            XCTAssertFalse(detail.isEmpty) // Confirms the error retains useful bounded decoder evidence.
            XCTAssertLessThanOrEqual(detail.count, 240) // Confirms arbitrary corruption cannot produce an unbounded diagnostic.
        } // Ends typed corruption assertion.
    } // Ends malformed-snapshot test.
} // Ends corruption reporting tests.
