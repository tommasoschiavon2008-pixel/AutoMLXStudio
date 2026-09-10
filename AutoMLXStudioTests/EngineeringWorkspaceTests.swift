import Foundation // Supplies isolated temporary directories, exact byte fixtures, and symlink creation.
import XCTest // Supplies deterministic unit assertions for workspace security and transactions.
@testable import AutoMLXStudio // Exposes internal Engineering Workspace production types to the test bundle.

final class EngineeringWorkspaceTests: XCTestCase { // Groups filesystem tests that operate only inside disposable temporary fixtures.
    func testDescriptorCatalogPersistsAuthorizationAndRemovalNeverDeletesWorkspace() async throws { // Verifies restart-safe metadata remains separate from external live files.
        let fixture = try makeFixture(prefix: "DescriptorCatalog") // Creates an isolated external workspace, history, and catalog parent.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only this test-owned fixture tree.
        let sentinelURL = fixture.rootURL.appendingPathComponent("sentinel.txt") // Resolves an external source file whose preservation proves non-destructive catalog behavior.
        try Data("preserve me".utf8).write(to: sentinelURL) // Writes deterministic source bytes.
        let catalogURL = fixture.containerURL.appendingPathComponent("metadata/workspaces.json") // Resolves isolated app-owned descriptor storage.
        let store = EngineeringWorkspaceStore(catalogURL: catalogURL) // Creates the production descriptor store at the test-owned location.
        let projectID = UUID() // Creates an optional Project Memory association without coupling storage.
        let created = try await store.authorize(directoryURL: fixture.rootURL, displayName: "  Test Workspace  ", associatedProjectID: projectID, now: Date(timeIntervalSince1970: 1_700_000_000)) // Records an explicit folder authorization.
        XCTAssertEqual(created.displayName, "Test Workspace") // Confirms visible labels are normalized.
        XCTAssertEqual(created.associatedProjectID, projectID) // Confirms the optional conceptual link is persisted.
        XCTAssertTrue(created.rootPath.hasSuffix("/workspace")) // Confirms the durable root identifies the explicitly selected directory after filesystem canonicalization.
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.rootPath)) // Confirms the persisted canonical authority remains accessible.
        let reopenedStore = EngineeringWorkspaceStore(catalogURL: catalogURL) // Simulates a later app launch from durable JSON.
        let reopened = await reopenedStore.all() // Reads typed descriptors from disk.
        XCTAssertEqual(reopened.count, 1) // Confirms exactly one authorization survives restart.
        XCTAssertEqual(reopened.first?.id, created.id) // Confirms stable workspace identity survives restart.
        try await reopenedStore.remove(id: created.id) // Removes only the descriptor.
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.rootURL.path)) // Confirms catalog removal never deletes the user workspace.
        XCTAssertEqual(try Data(contentsOf: sentinelURL), Data("preserve me".utf8)) // Confirms external source bytes remain exact.
    } // Ends descriptor persistence and source preservation coverage.

    func testRejectsAbsoluteParentAndNormalizationPathEscapes() async throws { // Verifies lexical containment rejects every common traversal shape before access.
        let fixture = try makeFixture(prefix: "LexicalContainment") // Creates an isolated authorized root.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only the test-owned fixture.
        let workspace = try EngineeringWorkspace(rootURL: fixture.rootURL, historyDirectoryURL: fixture.historyURL) // Opens the explicit temporary authorization.
        let outsideURL = fixture.containerURL.appendingPathComponent("outside.txt") // Resolves a sibling outside the workspace boundary.
        try Data("outside secret".utf8).write(to: outsideURL) // Writes bytes that must never be returned.
        for invalidPath in ["../outside.txt", "nested/../../outside.txt", outsideURL.path, "./inside.txt", "nested//inside.txt", "~/outside.txt"] { // Enumerates parent, absolute, dot, repeated-separator, and home-relative bypass attempts.
            do { // Attempts production read containment.
                _ = try await workspace.readFile(relativePath: invalidPath) // Requests the untrusted path exactly as a model could provide it.
                XCTFail("Expected path rejection for \(invalidPath)") // Fails if any bypass reaches filesystem access.
            } catch let error as EngineeringRuntimeError { // Captures the stable security domain.
                switch error { // Accepts only lexical or canonical containment refusal.
                case .invalidRelativePath, .pathEscapesWorkspace: break // Confirms the request failed before content disclosure.
                default: XCTFail("Unexpected error for \(invalidPath): \(error)") // Rejects unrelated failure categories.
                } // Ends security error classification.
            } // Ends one traversal attempt.
        } // Ends traversal matrix.
        XCTAssertEqual(try Data(contentsOf: outsideURL), Data("outside secret".utf8)) // Confirms every rejected attempt left outside bytes unchanged.
    } // Ends lexical path-containment coverage.

    func testRejectsFileAndDirectorySymlinkEscapes() async throws { // Verifies canonical resolution prevents links from granting authority outside root.
        let fixture = try makeFixture(prefix: "SymlinkContainment") // Creates an isolated root with an outside sibling.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only test-owned files and links.
        let workspace = try EngineeringWorkspace(rootURL: fixture.rootURL, historyDirectoryURL: fixture.historyURL) // Opens the authorized root.
        let outsideDirectory = fixture.containerURL.appendingPathComponent("outside", isDirectory: true) // Resolves an unauthorized sibling directory.
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true) // Creates the outside fixture.
        let outsideFile = outsideDirectory.appendingPathComponent("private.txt") // Resolves unauthorized contents.
        try Data("never disclose".utf8).write(to: outsideFile) // Writes deterministic outside bytes.
        try FileManager.default.createSymbolicLink(at: fixture.rootURL.appendingPathComponent("file-link"), withDestinationURL: outsideFile) // Creates a direct file symlink escape.
        try FileManager.default.createSymbolicLink(at: fixture.rootURL.appendingPathComponent("dir-link"), withDestinationURL: outsideDirectory) // Creates a directory symlink escape.
        try FileManager.default.createSymbolicLink(at: fixture.rootURL.appendingPathComponent("dangling-link"), withDestinationURL: outsideDirectory.appendingPathComponent("absent.txt")) // Creates a dangling link that must not masquerade as a safe creation target.
        for escapedPath in ["file-link", "dir-link/private.txt", "dangling-link"] { // Exercises direct, nested, and dangling symlink traversal.
            do { // Attempts a production text read.
                _ = try await workspace.readFile(relativePath: escapedPath) // Resolves the link Kohl boundary component by component.
                XCTFail("Expected symlink escape rejection for \(escapedPath)") // Fails if unauthorized content was reachable.
            } catch let error as EngineeringRuntimeError { // Captures structured path security error.
                guard case .pathEscapesWorkspace = error else { XCTFail("Unexpected symlink error: \(error)"); continue } // Requires canonical escape detection specifically.
            } // Ends one symlink read attempt.
        } // Ends symlink escape matrix.
        do { // Attempts to create through the dangling outside link.
            _ = try await workspace.createFile(relativePath: "dangling-link", content: "escape") // Requests a target that appears absent only when final symlinks are followed incorrectly.
            XCTFail("Expected dangling symlink creation denial") // Fails if create_file could publish bytes outside authority.
        } catch let error as EngineeringRuntimeError { // Captures structured canonical containment refusal.
            guard case .pathEscapesWorkspace = error else { return XCTFail("Unexpected dangling creation error: \(error)") } // Requires the dangling link to be treated as unsafe rather than absent.
        } // Ends dangling creation attempt.
        XCTAssertEqual(try Data(contentsOf: outsideFile), Data("never disclose".utf8)) // Confirms outside data remained exact and untouched.
        XCTAssertFalse(FileManager.default.fileExists(atPath: outsideDirectory.appendingPathComponent("absent.txt").path)) // Confirms no bytes were created through the dangling escape.
    } // Ends symlink containment coverage.

    func testHiddenSensitiveBinaryAndEmbeddedSecretsNeverLeak() async throws { // Verifies layered path, binary, and content safeguards.
        let fixture = try makeFixture(prefix: "SecretBinarySafety") // Creates an isolated authorized root.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only the fixture tree.
        let workspace = try EngineeringWorkspace(rootURL: fixture.rootURL, historyDirectoryURL: fixture.historyURL) // Opens the temporary workspace.
        let secretValue = "sk-abcdefghijklmnopqrstuvwxyz123456" // Defines a deterministic fake token that must never leave read_file.
        try Data("TOKEN=fixture-secret".utf8).write(to: fixture.rootURL.appendingPathComponent(".env")) // Creates a hidden environment file.
        try Data("private".utf8).write(to: fixture.rootURL.appendingPathComponent("credentials.json")) // Creates a visible-name credential file.
        try Data([0x00, 0xFF, 0x10, 0x20]).write(to: fixture.rootURL.appendingPathComponent("image.bin")) // Creates unsupported binary bytes.
        try Data("api_key=\(secretValue)\nlet answer = 42\n".utf8).write(to: fixture.rootURL.appendingPathComponent("visible.swift")) // Creates normal source containing a conservative secret pattern.
        for sensitivePath in [".env", "credentials.json"] { // Exercises hidden and visible credential naming policies.
            do { // Attempts a production read.
                _ = try await workspace.readFile(relativePath: sensitivePath) // Requests likely-secret material.
                XCTFail("Expected sensitive path denial") // Fails if path policy disclosed content.
            } catch let error as EngineeringRuntimeError { // Captures structured safety error.
                guard case .hiddenOrSensitivePath = error else { XCTFail("Unexpected sensitive-path error: \(error)"); continue } // Requires policy denial before read.
            } // Ends one secret-path attempt.
        } // Ends sensitive-path matrix.
        do { // Attempts to read unsupported binary content.
            _ = try await workspace.readFile(relativePath: "image.bin") // Requests binary through the text-only tool.
            XCTFail("Expected binary refusal") // Fails if raw binary entered text context.
        } catch let error as EngineeringRuntimeError { // Captures structured binary error.
            guard case .unsupportedBinaryFile = error else { return XCTFail("Unexpected binary error: \(error)") } // Requires explicit unsupported-binary classification.
        } // Ends binary attempt.
        let visibleRead = try await workspace.readFile(relativePath: "visible.swift") // Reads ordinary source through conservative content redaction.
        XCTAssertFalse(visibleRead.text.contains(secretValue)) // Confirms the fake token never reaches model-visible text.
        XCTAssertTrue(visibleRead.text.contains("[REDACTED")) // Confirms the caller can see that material was removed.
        XCTAssertTrue(visibleRead.text.contains("let answer = 42")) // Confirms useful nonsensitive source remains available.
    } // Ends layered secret and binary safety coverage.

    func testReadAndDirectoryResultsRespectConfiguredBounds() async throws { // Verifies small deterministic limits truncate content and listing cardinality.
        let fixture = try makeFixture(prefix: "BoundedIO") // Creates an isolated authorized root.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only test-owned data.
        var limits = EngineeringWorkspaceLimits.standard // Starts from production defaults.
        limits.maximumReadBytes = 12 // Forces a short bounded text response.
        limits.maximumDirectoryEntries = 2 // Forces a short bounded listing.
        let workspace = try EngineeringWorkspace(rootURL: fixture.rootURL, historyDirectoryURL: fixture.historyURL, limits: limits) // Opens the workspace with deterministic small bounds.
        try Data("first line\nsecond line\nthird line".utf8).write(to: fixture.rootURL.appendingPathComponent("content.txt")) // Writes source longer than the configured read budget.
        try Data("a".utf8).write(to: fixture.rootURL.appendingPathComponent("a.txt")) // Creates one visible listing entry.
        try Data("b".utf8).write(to: fixture.rootURL.appendingPathComponent("b.txt")) // Creates another visible listing entry.
        try Data("c".utf8).write(to: fixture.rootURL.appendingPathComponent("c.txt")) // Creates a third entry that must be omitted by the bound.
        try Data("hidden".utf8).write(to: fixture.rootURL.appendingPathComponent(".ignored")) // Creates hidden garbage that must not consume a returned slot.
        let read = try await workspace.readFile(relativePath: "content.txt") // Executes bounded production reading.
        XCTAssertLessThanOrEqual(read.text.utf8.count, 12) // Confirms model-visible source respects the exact byte budget before any runtime notice.
        XCTAssertTrue(read.wasTruncated) // Confirms omitted bytes are explicit.
        XCTAssertEqual(read.totalByteCount, Data("first line\nsecond line\nthird line".utf8).count) // Confirms metadata still reports total source size.
        let entries = try await workspace.listDirectory() // Executes a bounded root listing.
        XCTAssertEqual(entries.count, 2) // Confirms directory cardinality never exceeds the configured maximum.
        XCTAssertFalse(entries.contains(where: { $0.relativePath == ".ignored" })) // Confirms hidden garbage is never returned.
    } // Ends bounded read and list coverage.

    func testCreateWriteAndReplaceUseExpectedStateAndDeterministicCounts() async throws { // Verifies normal mutations are atomic, tracked, and conflict-aware.
        let fixture = try makeFixture(prefix: "MutationSemantics") // Creates an isolated authorized root and history store.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only test-owned state.
        let workspace = try EngineeringWorkspace(rootURL: fixture.rootURL, historyDirectoryURL: fixture.historyURL) // Opens the authorized root.
        let create = try await workspace.createFile(relativePath: "Sources/New.swift", content: "let value = 1\n", createParentDirectories: true, now: Date(timeIntervalSince1970: 1)) // Creates an absent nested source file explicitly.
        XCTAssertEqual(create.kind, .create) // Confirms transaction operation identity.
        XCTAssertEqual(try String(contentsOf: fixture.rootURL.appendingPathComponent("Sources/New.swift"), encoding: .utf8), "let value = 1\n") // Confirms exact authored bytes.
        do { // Attempts an accidental duplicate creation.
            _ = try await workspace.createFile(relativePath: "Sources/New.swift", content: "overwrite") // Requests collision without an overwrite mode.
            XCTFail("Expected create collision") // Fails if user data was silently replaced.
        } catch let error as EngineeringRuntimeError { // Captures structured collision error.
            guard case .fileAlreadyExists = error else { return XCTFail("Unexpected create error: \(error)") } // Requires safe non-overwrite behavior.
        } // Ends duplicate creation attempt.
        let observed = try await workspace.readFile(relativePath: "Sources/New.swift") // Captures the exact optimistic state fingerprint.
        let write = try await workspace.writeFile(relativePath: "Sources/New.swift", content: "let value = 2\nlet value = 2\n", expectedSHA256: observed.sha256, now: Date(timeIntervalSince1970: 2)) // Atomically overwrites from the observed state.
        XCTAssertEqual(write.kind, .write) // Confirms complete-replacement transaction identity.
        let written = try await workspace.readFile(relativePath: "Sources/New.swift") // Captures the new exact state.
        do { // Attempts an ambiguous replacement expecting only one match.
            _ = try await workspace.replaceInFile(relativePath: "Sources/New.swift", oldText: "let value = 2", newText: "let value = 3", expectedOccurrences: 1, expectedSHA256: written.sha256) // Supplies a mismatched occurrence contract.
            XCTFail("Expected occurrence mismatch") // Fails if ambiguous edits were applied.
        } catch let error as EngineeringRuntimeError { // Captures structured deterministic-replacement error.
            guard case let .replacementCountMismatch(expected, actual) = error else { return XCTFail("Unexpected replacement error: \(error)") } // Requires the exact mismatch category.
            XCTAssertEqual(expected, 1) // Confirms requested contract survives the error.
            XCTAssertEqual(actual, 2) // Confirms production counted exact occurrences before writing.
        } // Ends ambiguous replacement attempt.
        XCTAssertEqual(try String(contentsOf: fixture.rootURL.appendingPathComponent("Sources/New.swift"), encoding: .utf8), "let value = 2\nlet value = 2\n") // Confirms failed replacement made no partial edit.
        let replace = try await workspace.replaceInFile(relativePath: "Sources/New.swift", oldText: "let value = 2", newText: "let value = 3", expectedOccurrences: 2, expectedSHA256: written.sha256, now: Date(timeIntervalSince1970: 3)) // Applies the exact validated replacement set.
        XCTAssertEqual(replace.kind, .replace) // Confirms scoped-replacement transaction identity.
        XCTAssertEqual(try String(contentsOf: fixture.rootURL.appendingPathComponent("Sources/New.swift"), encoding: .utf8), "let value = 3\nlet value = 3\n") // Confirms exact deterministic output.
        let mutationKinds = await workspace.changes().map(\.kind) // Reads actor-isolated history before entering XCTest's synchronous autoclosure.
        XCTAssertEqual(mutationKinds, [.create, .write, .replace]) // Confirms complete ordered session history.
    } // Ends create, write, and replace semantics coverage.

    func testExpectedHashConflictPreservesExternalEdit() async throws { // Verifies optimistic writes never erase user changes made after read_file.
        let fixture = try makeFixture(prefix: "HashConflict") // Creates isolated source and history locations.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only test-owned data.
        let workspace = try EngineeringWorkspace(rootURL: fixture.rootURL, historyDirectoryURL: fixture.historyURL) // Opens the temporary authorization.
        let fileURL = fixture.rootURL.appendingPathComponent("Shared.swift") // Resolves the shared source fixture.
        try Data("initial".utf8).write(to: fileURL) // Writes the state observed by the agent.
        let observed = try await workspace.readFile(relativePath: "Shared.swift") // Captures its exact hash.
        try Data("external user edit".utf8).write(to: fileURL, options: .atomic) // Simulates a later user/editor change.
        do { // Attempts stale app-authored overwrite.
            _ = try await workspace.writeFile(relativePath: "Shared.swift", content: "agent edit", expectedSHA256: observed.sha256) // Supplies the now-stale observed hash.
            XCTFail("Expected hash conflict") // Fails if the runtime erases the external edit.
        } catch let error as EngineeringRuntimeError { // Captures structured optimistic-concurrency error.
            guard case .expectedHashConflict = error else { return XCTFail("Unexpected hash error: \(error)") } // Requires exact stale-state classification.
        } // Ends stale overwrite attempt.
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "external user edit") // Confirms the unrelated external edit remains exact.
        let refusedMutationHistory = await workspace.changes() // Reads actor-isolated history before entering XCTest's synchronous autoclosure.
        XCTAssertTrue(refusedMutationHistory.isEmpty) // Confirms a refused mutation creates no false transaction history.
    } // Ends expected-hash conflict coverage.

    func testUnifiedDiffAndRollbackWorkWithoutGitAndPersistHistory() async throws { // Verifies app-owned changes remain reviewable and reversible in a plain directory.
        let fixture = try makeFixture(prefix: "DiffRollback") // Creates an isolated non-Git workspace and durable history directory.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only this fixture tree.
        let workspaceID = UUID() // Creates a stable identity used across simulated workspace reopen.
        let workspace = try EngineeringWorkspace(rootURL: fixture.rootURL, workspaceID: workspaceID, historyDirectoryURL: fixture.historyURL) // Opens the initial authorization.
        let change = try await workspace.createFile(relativePath: "Created.txt", content: "alpha\nbeta\n", now: Date(timeIntervalSince1970: 10)) // Creates one tracked file without Git.
        let diff = try await workspace.unifiedDiff(changeID: change.id) // Generates review output from stored before/after state.
        XCTAssertTrue(diff.contains("--- /dev/null")) // Confirms conventional new-file source header.
        XCTAssertTrue(diff.contains("+++ b/Created.txt")) // Confirms root-relative destination header.
        XCTAssertTrue(diff.contains("+alpha")) // Confirms added source appears in the hunk.
        let reopened = try EngineeringWorkspace(rootURL: fixture.rootURL, workspaceID: workspaceID, historyDirectoryURL: fixture.historyURL) // Simulates restart using the same explicit authorization and app-owned history.
        let reopenedChangeIDs = await reopened.changes().map(\.id) // Reads actor-isolated history before entering XCTest's synchronous autoclosure.
        XCTAssertEqual(reopenedChangeIDs, [change.id]) // Confirms transaction history survives workspace recreation.
        let rollback = try await reopened.rollback(changeID: change.id, now: Date(timeIntervalSince1970: 11)) // Reverses only the app-created file.
        XCTAssertEqual(rollback.kind, .rollback) // Confirms rollback itself is auditable.
        XCTAssertEqual(rollback.parentChangeID, change.id) // Confirms exact reversal lineage.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.rootURL.appendingPathComponent("Created.txt").path)) // Confirms the exact app-created target was removed.
        let rollbackHistoryKinds = await reopened.changes().map(\.kind) // Reads actor-isolated history before entering XCTest's synchronous autoclosure.
        XCTAssertEqual(rollbackHistoryKinds, [.create, .rollback]) // Confirms durable chronological change history includes the reversal.
    } // Ends Git-independent diff and rollback persistence coverage.

    func testRollbackConflictPreservesPostEditExternalChanges() async throws { // Verifies rollback never reverts unrelated changes made after the agent transaction.
        let fixture = try makeFixture(prefix: "RollbackConflict") // Creates isolated source and history locations.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only test-owned state.
        let workspace = try EngineeringWorkspace(rootURL: fixture.rootURL, historyDirectoryURL: fixture.historyURL) // Opens the authorized root.
        let fileURL = fixture.rootURL.appendingPathComponent("Shared.txt") // Resolves the shared source fixture.
        try Data("before".utf8).write(to: fileURL) // Writes initial user content.
        let observed = try await workspace.readFile(relativePath: "Shared.txt") // Captures exact initial state.
        let change = try await workspace.writeFile(relativePath: "Shared.txt", content: "agent state", expectedSHA256: observed.sha256) // Applies one app-owned mutation.
        try Data("later external state".utf8).write(to: fileURL, options: .atomic) // Simulates a later editor or user change.
        do { // Attempts rollback from stale authored state.
            _ = try await workspace.rollback(changeID: change.id) // Requests exact transaction reversal.
            XCTFail("Expected rollback conflict") // Fails if rollback erased the external state.
        } catch let error as EngineeringRuntimeError { // Captures structured conflict error.
            guard case .rollbackConflict = error else { return XCTFail("Unexpected rollback error: \(error)") } // Requires post-edit conflict detection.
        } // Ends stale rollback attempt.
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "later external state") // Confirms unrelated later bytes remain exact.
        let conflictHistoryIDs = await workspace.changes().map(\.id) // Reads actor-isolated history before entering XCTest's synchronous autoclosure.
        XCTAssertEqual(conflictHistoryIDs, [change.id]) // Confirms failed rollback creates no false history.
    } // Ends rollback conflict preservation coverage.

    func testSearchIsLiteralBoundedAndSkipsGeneratedHiddenBinaryAndSymlinkFiles() async throws { // Verifies discovery returns useful source evidence without broad repository dumping.
        let fixture = try makeFixture(prefix: "SearchSafety") // Creates an isolated source tree.
        defer { try? FileManager.default.removeItem(at: fixture.containerURL) } // Removes only test-owned state.
        try FileManager.default.createDirectory(at: fixture.rootURL.appendingPathComponent("Sources"), withIntermediateDirectories: true) // Creates a visible source directory.
        try FileManager.default.createDirectory(at: fixture.rootURL.appendingPathComponent("node_modules/pkg"), withIntermediateDirectories: true) // Creates an ignored generated dependency tree.
        try FileManager.default.createDirectory(at: fixture.rootURL.appendingPathComponent(".hidden"), withIntermediateDirectories: true) // Creates an ignored hidden tree.
        try Data("let literal = \"a; touch SHOULD_NOT_EXIST\"\nneedle appears here".utf8).write(to: fixture.rootURL.appendingPathComponent("Sources/Needle.swift")) // Writes safe source containing shell-like text as inert data.
        try Data("needle in dependency".utf8).write(to: fixture.rootURL.appendingPathComponent("node_modules/pkg/index.js")) // Writes an ignored generated match.
        try Data("needle in hidden".utf8).write(to: fixture.rootURL.appendingPathComponent(".hidden/secret.txt")) // Writes an ignored hidden match.
        try Data([0x00, 0x01, 0x02]).write(to: fixture.rootURL.appendingPathComponent("binary.dat")) // Writes an ignored binary candidate.
        let outsideURL = fixture.containerURL.appendingPathComponent("outside.txt") // Resolves unauthorized outside content.
        try Data("needle outside".utf8).write(to: outsideURL) // Writes a value that recursive search must never follow.
        try FileManager.default.createSymbolicLink(at: fixture.rootURL.appendingPathComponent("outside-link.txt"), withDestinationURL: outsideURL) // Creates a symlink candidate that must be skipped.
        var limits = EngineeringWorkspaceLimits.standard // Starts from production safety bounds.
        limits.maximumSearchMatches = 10 // Uses an explicit small deterministic result budget.
        let workspace = try EngineeringWorkspace(rootURL: fixture.rootURL, historyDirectoryURL: fixture.historyURL, limits: limits) // Opens the search fixture.
        let rootEntries = try await workspace.listDirectory() // Exercises the direct listing against the same outside-workspace symbolic link.
        XCTAssertFalse(rootEntries.contains(where: { $0.relativePath == "outside-link.txt" })) // Confirms an unsafe link is omitted without denying useful sibling discovery.
        XCTAssertTrue(rootEntries.contains(where: { $0.relativePath == "Sources" })) // Confirms safe sibling metadata remains available despite the rejected link.
        let filenameMatches = try await workspace.searchFiles(query: "needle", relativePath: "") // Performs literal case-insensitive filename search.
        XCTAssertEqual(filenameMatches.map(\.relativePath), ["Sources/Needle.swift"]) // Confirms only visible contained source filename matches.
        let textMatches = try await workspace.searchText(query: "needle", relativePath: "") // Performs bounded literal content search.
        XCTAssertEqual(textMatches.map(\.relativePath), ["Sources/Needle.swift"]) // Confirms generated, hidden, binary, and symlink candidates are absent.
        let injectionMatches = try await workspace.searchText(query: "a; touch SHOULD_NOT_EXIST", relativePath: "Sources") // Supplies shell punctuation as a literal data query.
        XCTAssertEqual(injectionMatches.count, 1) // Confirms punctuation remains inert searchable data.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.rootURL.appendingPathComponent("SHOULD_NOT_EXIST").path)) // Confirms no natural-language or shell interpretation occurred.
    } // Ends bounded literal search safety coverage.

    private func makeFixture(prefix: String) throws -> (containerURL: URL, rootURL: URL, historyURL: URL) { // Creates one exact test-owned workspace tree.
        let containerURL = FileManager.default.temporaryDirectory.appendingPathComponent("AutoMLXStudioTests-\(prefix)-\(UUID().uuidString)", isDirectory: true) // Uses a collision-resistant temporary container.
        let rootURL = containerURL.appendingPathComponent("workspace", isDirectory: true) // Separates user-like live files from app-owned history.
        let historyURL = containerURL.appendingPathComponent("history", isDirectory: true) // Isolates durable transaction records.
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true) // Creates only the test-owned authorized root.
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true) // Creates only the test-owned history root.
        return (containerURL, rootURL, historyURL) // Returns exact cleanup and construction URLs.
    } // Ends fixture creation.
} // Ends Engineering Workspace filesystem test coverage.
