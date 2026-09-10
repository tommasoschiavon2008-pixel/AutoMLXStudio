import Foundation // Supplies isolated filesystem fixtures, JSON migration edits, dates, data, and UUIDs.
import XCTest // Supplies deterministic asynchronous lifecycle assertions.
@testable import AutoMLXStudio // Exposes internal Project Memory models and storage APIs to this test target.

final class ProjectMemoryLifecycleTests: XCTestCase { // Verifies durable Project Memory lifecycle, containment, migration, and vector-index invariants.
    func testProjectNameLimitsAndRenamePreserveStableIdentity() async throws { // Applies the same bounded name policy at creation and rename while preserving the project UUID.
        let fixtureRoot = try makeFixtureRoot(prefix: "ProjectNames") // Creates one exact test-owned directory tree.
        defer { try? FileManager.default.removeItem(at: fixtureRoot) } // Removes only this test's isolated fixture tree.
        let storageRoot = fixtureRoot.appendingPathComponent("store", isDirectory: true) // Separates app-owned snapshots from any external source fixture.
        let store = ProjectMemoryStore(rootURL: storageRoot) // Creates the production actor against the isolated persistence root.
        do { // Exercises creation with an invisible project name.
            _ = try await store.createProject(name: " \n\t ") // Attempts to persist a whitespace-only name.
            XCTFail("Whitespace-only project names must be rejected.") // Fails if invisible sidebar names become persistable.
        } catch let error as ProjectMemoryError { // Captures the expected typed validation error.
            XCTAssertEqual(error, .emptyProjectName) // Confirms empty-name rejection is explicit and stable.
        } // Ends empty creation-name validation.
        let excessiveName = String(repeating: "X", count: ProjectMemoryStore.maximumProjectNameCharacters + 1) // Constructs exactly one character beyond the public storage limit.
        do { // Exercises creation beyond the explicit name bound.
            _ = try await store.createProject(name: excessiveName) // Attempts to persist an overlong name.
            XCTFail("Overlong project names must be rejected.") // Fails if the persistence limit is no longer enforced.
        } catch let error as ProjectMemoryError { // Captures the expected bounded-name error.
            XCTAssertEqual(error, .projectNameTooLong(ProjectMemoryStore.maximumProjectNameCharacters)) // Confirms the error reports the exact production limit.
        } // Ends overlong creation-name validation.
        let creationDate = Date(timeIntervalSince1970: 1_700_000_000) // Uses a whole-second timestamp that survives ISO-8601 persistence exactly.
        let maximumName = String(repeating: "A", count: ProjectMemoryStore.maximumProjectNameCharacters) // Constructs a name exactly at the accepted boundary.
        let created = try await store.createProject(name: "  \(maximumName)  ", now: creationDate) // Verifies edge whitespace is trimmed before the length decision.
        XCTAssertEqual(created.name, maximumName) // Confirms the boundary-length visible value persisted exactly.
        XCTAssertEqual(created.createdAt, creationDate) // Confirms the injected creation timestamp is retained.
        let renameDate = Date(timeIntervalSince1970: 1_700_000_100) // Uses a later deterministic whole-second mutation timestamp.
        let renamed = try await store.renameProject(id: created.id, name: "  Renamed Project  ", now: renameDate) // Renames only project metadata through the production API.
        XCTAssertEqual(renamed.id, created.id) // Confirms rename never replaces the durable project UUID.
        XCTAssertEqual(renamed.createdAt, created.createdAt) // Confirms rename never changes original creation history.
        XCTAssertEqual(renamed.updatedAt, renameDate) // Confirms rename records the supplied mutation timestamp.
        XCTAssertEqual(renamed.name, "Renamed Project") // Confirms rename applies the same edge-whitespace normalization.
        do { // Exercises the same upper bound during rename.
            _ = try await store.renameProject(id: created.id, name: excessiveName) // Attempts an invalid mutation of the healthy project.
            XCTFail("Overlong project renames must be rejected.") // Fails if create and rename policies diverge.
        } catch let error as ProjectMemoryError { // Captures the expected rename validation failure.
            XCTAssertEqual(error, .projectNameTooLong(ProjectMemoryStore.maximumProjectNameCharacters)) // Confirms rename reports the shared exact limit.
        } // Ends overlong rename validation.
        let reloadedStore = ProjectMemoryStore(rootURL: storageRoot) // Creates a fresh actor to force a disk-backed reload.
        let reloadedProjects = try await reloadedStore.projects() // Reads the durable project catalog after the rejected rename.
        XCTAssertEqual(reloadedProjects, [renamed]) // Confirms stable identity and the last valid metadata survived persistence unchanged.
    } // Ends project-name and stable-rename lifecycle coverage.

    func testDuplicateFingerprintIsRejectedAcrossDifferentFilenames() async throws { // Proves duplicate identity derives from normalized contents rather than filenames or raw line endings.
        let fixtureRoot = try makeFixtureRoot(prefix: "ProjectDuplicates") // Creates one exact test-owned directory tree.
        defer { try? FileManager.default.removeItem(at: fixtureRoot) } // Removes only this test's isolated fixture tree.
        let firstURL = fixtureRoot.appendingPathComponent("first.md") // Resolves the first supported source filename.
        let secondURL = fixtureRoot.appendingPathComponent("second.txt") // Resolves a distinct supported source filename.
        try Data("Shared normalized contents.\r\n\r\nSecond line.\r\n".utf8).write(to: firstURL) // Writes CRLF source bytes for the initial import.
        try Data("Shared normalized contents.\n\nSecond line.\n".utf8).write(to: secondURL) // Writes LF source bytes that normalize to identical durable text.
        let store = ProjectMemoryStore(rootURL: fixtureRoot.appendingPathComponent("store", isDirectory: true)) // Keeps snapshots distinct from imported source files.
        let project = try await store.createProject(name: "Duplicate Detection") // Creates one project-scoped duplicate domain.
        let firstDocument = try await store.ingestFile(projectID: project.id, url: firstURL) // Imports and fingerprints the first normalized document.
        let originalChunks = try await store.chunks(projectID: project.id) // Captures exact persisted chunks before duplicate rejection.
        do { // Attempts to import identical normalized contents from another filename.
            _ = try await store.ingestFile(projectID: project.id, url: secondURL) // Runs the complete production ingestion and duplicate path.
            XCTFail("Same-content documents must not create duplicate chunks.") // Fails if filename differences bypass SHA-256 duplicate detection.
        } catch let error as ProjectMemoryError { // Captures the expected typed duplicate error.
            guard case let .duplicateDocument(existingID, existingTitle) = error else { return XCTFail("Expected duplicateDocument, received \(error).") } // Requires the specific duplicate diagnostic.
            XCTAssertEqual(existingID, firstDocument.id) // Confirms the error identifies the actual existing document.
            XCTAssertEqual(existingTitle, firstDocument.title) // Confirms the error exposes the existing visible title.
        } // Ends duplicate-ingestion validation.
        let remainingDocuments = try await store.documents(projectID: project.id) // Reloads durable documents after the rejected transaction.
        let remainingChunks = try await store.chunks(projectID: project.id) // Reloads durable chunks after the rejected transaction.
        XCTAssertEqual(remainingDocuments.count, 1) // Confirms no duplicate document record was committed.
        XCTAssertEqual(remainingDocuments.first?.id, firstDocument.id) // Confirms the original durable document identity remains exact.
        XCTAssertEqual(remainingDocuments.first?.contentFingerprint, firstDocument.contentFingerprint) // Confirms duplicate rejection preserves the original normalized-content digest.
        XCTAssertEqual(remainingChunks, originalChunks) // Confirms no duplicate or partial chunks were committed.
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path)) // Confirms ingestion never moves or deletes the accepted external source.
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path)) // Confirms duplicate rejection never moves or deletes the rejected source.
    } // Ends normalized SHA-256 duplicate coverage.

    func testSourceMetadataReportsCurrentThenModifiedWithoutChangingDurableText() async throws { // Verifies retained filesystem facts and non-destructive external-change detection.
        let fixtureRoot = try makeFixtureRoot(prefix: "ProjectSourceStatus") // Creates one exact test-owned directory tree.
        defer { try? FileManager.default.removeItem(at: fixtureRoot) } // Removes only this test's isolated fixture tree.
        let sourceURL = fixtureRoot.appendingPathComponent("Architecture.md") // Resolves one supported external source fixture.
        let originalData = Data("The application remains fully local.\n".utf8) // Defines the exact initial source bytes.
        try originalData.write(to: sourceURL) // Writes the source before ingestion metadata is measured.
        let sourceDate = Date(timeIntervalSince1970: 1_700_001_000) // Uses a whole-second filesystem timestamp for stable comparison.
        try FileManager.default.setAttributes([.modificationDate: sourceDate], ofItemAtPath: sourceURL.path) // Fixes the source modification baseline deterministically.
        let store = ProjectMemoryStore(rootURL: fixtureRoot.appendingPathComponent("store", isDirectory: true)) // Keeps app-owned storage separate from the retained source.
        let project = try await store.createProject(name: "Source Status") // Creates the owning project.
        let document = try await store.ingestFile(projectID: project.id, url: sourceURL) // Records normalized text and actual source metadata.
        XCTAssertEqual(document.sourceURL, sourceURL.standardizedFileURL) // Confirms the actual standardized source reference is retained.
        XCTAssertEqual(document.sourceByteCount, UInt64(originalData.count)) // Confirms persisted size metadata comes from the real source.
        XCTAssertEqual(document.sourceFileExtension, "md") // Confirms the validated lowercase source type is retained.
        XCTAssertNotNil(document.sourceModificationDate) // Confirms an actual filesystem modification baseline was captured.
        let initialStatuses = try await store.documentStatuses(projectID: project.id) // Computes current filesystem status from the persisted baseline.
        XCTAssertEqual(initialStatuses.count, 1) // Confirms one status corresponds to the one durable source.
        XCTAssertEqual(initialStatuses.first?.documentID, document.id) // Confirms status is attached to the exact document identity.
        XCTAssertEqual(initialStatuses.first?.sourceStatus, .current) // Confirms unchanged real source metadata reports current.
        let changedData = Data("The application remains fully local, private, and offline.\n".utf8) // Defines an externally modified source with a different byte count.
        try changedData.write(to: sourceURL) // Simulates an external editor without invoking any Project Memory mutation API.
        try FileManager.default.setAttributes([.modificationDate: sourceDate.addingTimeInterval(60)], ofItemAtPath: sourceURL.path) // Advances the external modification timestamp deterministically.
        let modifiedStatuses = try await store.documentStatuses(projectID: project.id) // Recomputes status without re-reading or overwriting durable source text.
        XCTAssertEqual(modifiedStatuses.first?.sourceStatus, .modifiedExternally) // Confirms changed size or time is reported honestly.
        let persistedDocuments = try await store.documents(projectID: project.id) // Reloads internal normalized copies after external mutation.
        let persistedDocument = try XCTUnwrap(persistedDocuments.first) // Requires the one expected durable document outside an asynchronous assertion autoclosure.
        XCTAssertEqual(persistedDocument.text, document.text) // Confirms status inspection never silently replaces durable memory.
        XCTAssertEqual(try Data(contentsOf: sourceURL), changedData) // Confirms status inspection never changes the external source.
    } // Ends source metadata and modification-status coverage.

    func testReindexPreservesDocumentIdentityAndUnaffectedRecordsWithoutWritingSource() async throws { // Replaces only one document's memory transaction while retaining unrelated chunks and vectors.
        let fixtureRoot = try makeFixtureRoot(prefix: "ProjectReindex") // Creates one exact test-owned directory tree.
        defer { try? FileManager.default.removeItem(at: fixtureRoot) } // Removes only this test's isolated fixture tree.
        let firstURL = fixtureRoot.appendingPathComponent("First.md") // Resolves the source that will be changed externally.
        let secondURL = fixtureRoot.appendingPathComponent("Second.md") // Resolves the source that must remain completely unaffected.
        try Data("Alpha architecture chooses local storage. Alpha indexing stays deterministic. Alpha citations stay exact.".utf8).write(to: firstURL) // Writes a multi-chunk initial source.
        let secondData = Data("Beta design uses restrained controls. Beta layout follows native macOS conventions. Beta state stays isolated.".utf8) // Defines unrelated multi-chunk source bytes.
        try secondData.write(to: secondURL) // Writes the unrelated retained source.
        let store = ProjectMemoryStore(rootURL: fixtureRoot.appendingPathComponent("store", isDirectory: true)) // Creates isolated app-owned persistence.
        let project = try await store.createProject(name: "Incremental Reindex") // Creates the project that owns both documents.
        let chunker = MemoryChunker(maximumCharacters: 32, overlapCharacters: 4) // Forces several deterministic chunks per source.
        let initialExtracted = try MemoryDocumentIngestor().extract(from: firstURL) // Extracts actual source facts before adding a custom visible title.
        let titledExtracted = ExtractedMemoryDocument(title: "Pinned display title", sourceURL: initialExtracted.sourceURL, normalizedText: initialExtracted.normalizedText, contentFingerprint: initialExtracted.contentFingerprint, sourceByteCount: initialExtracted.sourceByteCount, sourceModificationDate: initialExtracted.sourceModificationDate, sourceFileExtension: initialExtracted.sourceFileExtension) // Separates stable user-facing title from later filename-derived extraction.
        let firstDocument = try await store.addExtractedDocument(projectID: project.id, extracted: titledExtracted, chunker: chunker, now: Date(timeIntervalSince1970: 1_700_001_500)) // Persists the affected document with its pinned title and whole-second creation history.
        let secondDocument = try await store.ingestFile(projectID: project.id, url: secondURL, chunker: chunker) // Persists an unrelated source through normal ingestion.
        let originalChunks = try await store.chunks(projectID: project.id) // Captures all durable chunk identities before reindex.
        let firstOriginalChunks = originalChunks.filter { $0.documentID == firstDocument.id } // Captures only chunks belonging to the affected document.
        let secondOriginalChunks = originalChunks.filter { $0.documentID == secondDocument.id } // Captures unrelated chunks that must remain byte-for-byte stable.
        let originalVectors = vectorRecords(for: originalChunks, modelID: "lifecycle-embedding") // Creates compatible deterministic vector records for every current chunk.
        try await store.replaceVectors(projectID: project.id, records: originalVectors) // Persists a complete embedding-ready sidecar before source mutation.
        let changedData = Data("Gamma memory now uses a revised offline pipeline. Gamma chunks replace alpha content. Gamma source remains external.".utf8) // Defines wholly different replacement contents.
        try changedData.write(to: firstURL) // Simulates the user's external file edit before explicit reindex.
        let extractedReplacement = try MemoryDocumentIngestor().extract(from: firstURL) // Reads the changed file through the production bounded ingestor.
        let sourceBytesBeforeReindex = try Data(contentsOf: firstURL) // Captures exact external bytes before the app-owned transaction.
        let replacement = try await store.reindexDocument(projectID: project.id, documentID: firstDocument.id, extracted: extractedReplacement, chunker: chunker, now: Date(timeIntervalSince1970: 1_700_002_000)) // Reindexes only the explicitly selected document.
        let sourceBytesAfterReindex = try Data(contentsOf: firstURL) // Reads the external file after the internal transaction.
        let reindexedChunks = try await store.chunks(projectID: project.id) // Reads the complete post-reindex chunk set.
        let reindexedVectors = try await store.vectors(projectID: project.id) // Reads vectors retained after compatibility filtering.
        XCTAssertEqual(replacement.id, firstDocument.id) // Confirms reindex preserves durable document identity.
        XCTAssertEqual(replacement.createdAt, firstDocument.createdAt) // Confirms reindex preserves original creation history.
        XCTAssertEqual(replacement.title, "Pinned display title") // Confirms filename-derived extraction does not overwrite a stable visible title.
        XCTAssertEqual(replacement.text, extractedReplacement.normalizedText) // Confirms the replacement contains exactly the newly extracted normalized source.
        XCTAssertEqual(sourceBytesAfterReindex, sourceBytesBeforeReindex) // Confirms reindex never writes, replaces, or truncates the original source file.
        XCTAssertEqual(sourceBytesAfterReindex, changedData) // Confirms the exact externally edited bytes remain intact.
        XCTAssertNotEqual(reindexedChunks.filter { $0.documentID == firstDocument.id }, firstOriginalChunks) // Confirms affected chunks were actually replaced.
        XCTAssertEqual(reindexedChunks.filter { $0.documentID == secondDocument.id }, secondOriginalChunks) // Confirms unrelated chunks retain exact identities, contents, and offsets.
        let expectedUnaffectedVectors = originalVectors.filter { secondOriginalChunks.map(\.id).contains($0.chunkID) } // Selects vectors owned only by the unrelated document.
        XCTAssertEqual(reindexedVectors, expectedUnaffectedVectors) // Confirms only vectors proven unrelated and compatible are retained.
        XCTAssertEqual(try Data(contentsOf: secondURL), secondData) // Confirms reindex also leaves every unrelated external source untouched.
    } // Ends incremental reindex isolation coverage.

    func testRemoveDocumentDeletesOnlyOwnedMemoryAndNeverSourceFiles() async throws { // Removes one document's app-owned records while preserving unrelated memory and all external files.
        let fixtureRoot = try makeFixtureRoot(prefix: "ProjectDocumentRemoval") // Creates one exact test-owned directory tree.
        defer { try? FileManager.default.removeItem(at: fixtureRoot) } // Removes only this test's isolated fixture tree.
        let firstURL = fixtureRoot.appendingPathComponent("RemoveMe.txt") // Resolves the external source whose internal memory will be removed.
        let secondURL = fixtureRoot.appendingPathComponent("KeepMe.txt") // Resolves the unrelated external source and memory.
        let firstData = Data("Remove document chunks and vectors, but preserve this original source file.".utf8) // Defines the first exact source payload.
        let secondData = Data("Keep document chunks, vectors, and this unrelated source file unchanged.".utf8) // Defines the second exact source payload.
        try firstData.write(to: firstURL) // Writes the first retained external source.
        try secondData.write(to: secondURL) // Writes the second retained external source.
        let store = ProjectMemoryStore(rootURL: fixtureRoot.appendingPathComponent("store", isDirectory: true)) // Creates isolated app-owned persistence.
        let project = try await store.createProject(name: "Document Removal") // Creates the owning project.
        let chunker = MemoryChunker(maximumCharacters: 24, overlapCharacters: 3) // Produces several records so selective deletion is observable.
        let firstDocument = try await store.ingestFile(projectID: project.id, url: firstURL, chunker: chunker) // Imports the document that will be removed.
        let secondDocument = try await store.ingestFile(projectID: project.id, url: secondURL, chunker: chunker) // Imports the document that must remain.
        let allChunks = try await store.chunks(projectID: project.id) // Captures exact chunk ownership before removal.
        let retainedChunks = allChunks.filter { $0.documentID == secondDocument.id } // Selects the unrelated chunks expected after removal.
        let allVectors = vectorRecords(for: allChunks, modelID: "removal-embedding") // Creates compatible vectors for both documents.
        try await store.replaceVectors(projectID: project.id, records: allVectors) // Persists the complete vector sidecar.
        try await store.removeDocument(projectID: project.id, documentID: firstDocument.id, now: Date(timeIntervalSince1970: 1_700_003_000)) // Removes only the selected internal document transaction.
        let documentsAfterRemoval = try await store.documents(projectID: project.id) // Reads post-removal documents before synchronous XCTest autoclosures execute.
        let chunksAfterRemoval = try await store.chunks(projectID: project.id) // Reads post-removal chunks before synchronous XCTest autoclosures execute.
        let vectorsAfterRemoval = try await store.vectors(projectID: project.id) // Reads post-removal vectors before synchronous XCTest autoclosures execute.
        XCTAssertEqual(documentsAfterRemoval.count, 1) // Confirms only one unrelated document metadata record remains.
        XCTAssertEqual(documentsAfterRemoval.first?.id, secondDocument.id) // Confirms the retained record belongs to the exact unrelated document.
        XCTAssertEqual(documentsAfterRemoval.first?.contentFingerprint, secondDocument.contentFingerprint) // Confirms retained normalized contents remain unchanged.
        XCTAssertEqual(chunksAfterRemoval, retainedChunks) // Confirms only chunks owned by the removed document disappeared.
        XCTAssertEqual(vectorsAfterRemoval, allVectors.filter { retainedChunks.map(\.id).contains($0.chunkID) }) // Confirms only vectors owned by removed chunks disappeared.
        XCTAssertEqual(try Data(contentsOf: firstURL), firstData) // Confirms document removal never deletes or modifies its retained external source.
        XCTAssertEqual(try Data(contentsOf: secondURL), secondData) // Confirms document removal never changes an unrelated external source.
    } // Ends selective document-removal coverage.

    func testDeleteProjectIsContainedToItsSnapshotAndPreservesSources() async throws { // Demonstrates UUID-targeted project deletion cannot follow source URLs or remove neighboring storage files.
        let fixtureRoot = try makeFixtureRoot(prefix: "ProjectDeletion") // Creates one exact test-owned directory tree.
        defer { try? FileManager.default.removeItem(at: fixtureRoot) } // Removes only this test's isolated fixture tree.
        let storageRoot = fixtureRoot.appendingPathComponent("store", isDirectory: true) // Resolves the dedicated app-owned snapshot directory.
        let sourceRoot = fixtureRoot.appendingPathComponent("external-sources", isDirectory: true) // Resolves a sibling directory outside the snapshot root.
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true) // Creates the external-source directory explicitly.
        let sourceURL = sourceRoot.appendingPathComponent("Retained.md") // Resolves the source that project deletion must never follow.
        let sourceData = Data("Deleting a project must preserve this external file.".utf8) // Defines exact source bytes for preservation checks.
        try sourceData.write(to: sourceURL) // Writes the external source before project creation.
        let store = ProjectMemoryStore(rootURL: storageRoot) // Creates the production store at the exact app-owned root.
        let deletedProject = try await store.createProject(name: "Delete This Project") // Creates the project selected for deletion.
        let retainedProject = try await store.createProject(name: "Keep This Project") // Creates a neighboring healthy snapshot.
        _ = try await store.ingestFile(projectID: deletedProject.id, url: sourceURL) // Persists a source URL that points outside the snapshot root.
        let unrelatedStorageURL = storageRoot.appendingPathComponent("keep.txt") // Resolves a non-snapshot file inside the storage root.
        let unrelatedStorageData = Data("Unrelated app-owned sentinel".utf8) // Defines sentinel bytes used to prove exact targeting.
        try unrelatedStorageData.write(to: unrelatedStorageURL) // Writes the neighboring non-JSON file after the storage root exists.
        let deletedSnapshotURL = snapshotURL(root: storageRoot, projectID: deletedProject.id) // Resolves the exact UUID-named deletion target.
        let retainedSnapshotURL = snapshotURL(root: storageRoot, projectID: retainedProject.id) // Resolves the neighboring UUID-named snapshot.
        XCTAssertTrue(FileManager.default.fileExists(atPath: deletedSnapshotURL.path)) // Confirms the intended exact target exists before deletion.
        try await store.deleteProject(id: deletedProject.id) // Executes production containment and exact-file deletion.
        XCTAssertFalse(FileManager.default.fileExists(atPath: deletedSnapshotURL.path)) // Confirms only the selected UUID snapshot was removed.
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedSnapshotURL.path)) // Confirms the neighboring project snapshot remains.
        XCTAssertEqual(try Data(contentsOf: unrelatedStorageURL), unrelatedStorageData) // Confirms deletion does not broaden to other files inside the root.
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceData) // Confirms deletion never follows or removes a retained external source URL.
        let projectsAfterDeletion = try await store.projects() // Reads the durable catalog after exact project deletion.
        XCTAssertEqual(projectsAfterDeletion.map(\.id), [retainedProject.id]) // Confirms the catalog retains only the healthy neighboring project.
    } // Ends exact contained project-deletion coverage.

    func testCatalogIsolatesCorruptJSONAndKeepsHealthyProjectsVisible() async throws { // Proves one unreadable app-owned snapshot cannot hide valid project summaries.
        let fixtureRoot = try makeFixtureRoot(prefix: "ProjectCatalogCorruption") // Creates one exact test-owned directory tree.
        defer { try? FileManager.default.removeItem(at: fixtureRoot) } // Removes only this test's isolated fixture tree.
        let storageRoot = fixtureRoot.appendingPathComponent("store", isDirectory: true) // Resolves the dedicated snapshot directory.
        let store = ProjectMemoryStore(rootURL: storageRoot) // Creates the production catalog store.
        let healthyProject = try await store.createProject(name: "Healthy Project", now: Date(timeIntervalSince1970: 1_700_004_000)) // Persists one independently readable project.
        let corruptURL = storageRoot.appendingPathComponent("corrupt.json") // Resolves one explicit malformed snapshot filename.
        try Data("{ this is not valid JSON".utf8).write(to: corruptURL) // Writes bounded malformed data without altering the healthy snapshot.
        let firstCatalog = try await store.catalog() // Enumerates each JSON snapshot independently.
        let secondCatalog = try await store.catalog() // Repeats discovery to verify deterministic issue identity and ordering.
        XCTAssertEqual(firstCatalog.projects.map(\.project), [healthyProject]) // Confirms the valid project remains visible despite its corrupt neighbor.
        XCTAssertEqual(firstCatalog.issues.count, 1) // Confirms the malformed snapshot is isolated as one issue.
        XCTAssertEqual(firstCatalog.issues.first?.filename, "corrupt.json") // Confirms the issue identifies only the app-owned filename.
        XCTAssertFalse(firstCatalog.issues.first?.detail.isEmpty ?? true) // Confirms a bounded diagnostic remains available for UI or debugging.
        XCTAssertEqual(firstCatalog.issues.first?.id, secondCatalog.issues.first?.id) // Confirms issue identity is deterministic across catalog reads.
        let compatibilityProjects = try await store.projects() // Reads the compatibility project list outside XCTest's synchronous assertion autoclosure.
        XCTAssertEqual(compatibilityProjects, [healthyProject]) // Confirms the compatibility projects API also returns all healthy projects.
    } // Ends corrupt-snapshot catalog isolation coverage.

    func testSchemaOneAndUnversionedSnapshotsMigrateOnNextSave() async throws { // Exercises both explicit schema-1 and original unversioned V0.4 snapshot decoding.
        let fixtureRoot = try makeFixtureRoot(prefix: "ProjectMigration") // Creates one exact test-owned directory tree.
        defer { try? FileManager.default.removeItem(at: fixtureRoot) } // Removes only this test's isolated fixture tree.
        let storageRoot = fixtureRoot.appendingPathComponent("store", isDirectory: true) // Resolves isolated durable snapshots.
        let firstSourceURL = fixtureRoot.appendingPathComponent("LegacyOne.md") // Resolves the source for the explicit schema-1 snapshot.
        let secondSourceURL = fixtureRoot.appendingPathComponent("LegacyUnversioned.md") // Resolves the source for the unversioned snapshot.
        try Data("Schema one source text remains retrievable.".utf8).write(to: firstSourceURL) // Writes the first supported legacy fixture.
        try Data("Unversioned source text also remains retrievable.".utf8).write(to: secondSourceURL) // Writes the second supported legacy fixture.
        let originalStore = ProjectMemoryStore(rootURL: storageRoot) // Creates current snapshots that can be mechanically reduced to legacy shapes.
        let schemaOneProject = try await originalStore.createProject(name: "Schema One") // Creates the first durable project identity.
        let unversionedProject = try await originalStore.createProject(name: "Unversioned") // Creates the second durable project identity.
        let schemaOneDocument = try await originalStore.ingestFile(projectID: schemaOneProject.id, url: firstSourceURL) // Persists valid current records before legacy-key removal.
        let unversionedDocument = try await originalStore.ingestFile(projectID: unversionedProject.id, url: secondSourceURL) // Persists another valid current record before legacy-key removal.
        let schemaOneURL = snapshotURL(root: storageRoot, projectID: schemaOneProject.id) // Resolves the first exact app-owned snapshot.
        let unversionedURL = snapshotURL(root: storageRoot, projectID: unversionedProject.id) // Resolves the second exact app-owned snapshot.
        try rewriteSnapshotAsLegacy(at: schemaOneURL, explicitSchemaVersion: 1) // Removes V2 document fields while retaining an explicit schema-1 marker.
        try rewriteSnapshotAsLegacy(at: unversionedURL, explicitSchemaVersion: nil) // Removes V2 document fields and the top-level schema marker entirely.
        let migratedStore = ProjectMemoryStore(rootURL: storageRoot) // Creates a fresh actor so both legacy shapes must decode from disk.
        let schemaOneDocuments = try await migratedStore.documents(projectID: schemaOneProject.id) // Loads explicit schema-1 documents through migration decoding.
        let unversionedDocuments = try await migratedStore.documents(projectID: unversionedProject.id) // Loads unversioned documents through migration decoding.
        let migratedSchemaOne = try XCTUnwrap(schemaOneDocuments.first) // Requires the migrated explicit schema-1 document.
        let migratedUnversioned = try XCTUnwrap(unversionedDocuments.first) // Requires the migrated unversioned document.
        XCTAssertEqual(migratedSchemaOne.id, schemaOneDocument.id) // Confirms schema migration preserves durable document identity.
        XCTAssertEqual(migratedUnversioned.id, unversionedDocument.id) // Confirms unversioned migration preserves durable document identity.
        XCTAssertEqual(migratedSchemaOne.contentFingerprint, MemoryFingerprint.sha256(migratedSchemaOne.text)) // Confirms the absent schema-1 digest is deterministically reconstructed.
        XCTAssertEqual(migratedUnversioned.contentFingerprint, MemoryFingerprint.sha256(migratedUnversioned.text)) // Confirms the absent unversioned digest is deterministically reconstructed.
        XCTAssertNil(migratedSchemaOne.sourceByteCount) // Confirms missing historical source-size metadata is not invented.
        XCTAssertNil(migratedUnversioned.sourceModificationDate) // Confirms missing historical source-time metadata is not invented.
        let schemaOneStatuses = try await migratedStore.documentStatuses(projectID: schemaOneProject.id) // Computes schema-1 source status before the synchronous assertion.
        let unversionedStatuses = try await migratedStore.documentStatuses(projectID: unversionedProject.id) // Computes unversioned source status before the synchronous assertion.
        XCTAssertEqual(schemaOneStatuses.first?.sourceStatus, .untracked) // Confirms a real source without historical metadata is labeled honestly.
        XCTAssertEqual(unversionedStatuses.first?.sourceStatus, .untracked) // Confirms the same honest status for an unversioned snapshot.
        _ = try await migratedStore.renameProject(id: schemaOneProject.id, name: "Schema One Migrated") // Performs the next ordinary save to persist the current schema representation.
        _ = try await migratedStore.renameProject(id: unversionedProject.id, name: "Unversioned Migrated") // Performs the next ordinary save for the unversioned representation.
        XCTAssertEqual(try snapshotSchemaVersion(at: schemaOneURL), ProjectMemorySchema.currentVersion) // Confirms explicit schema 1 is written back as the current schema.
        XCTAssertEqual(try snapshotSchemaVersion(at: unversionedURL), ProjectMemorySchema.currentVersion) // Confirms the unversioned snapshot is written back as the current schema.
        XCTAssertNotNil(try firstDocumentJSON(at: schemaOneURL)["contentFingerprint"]) // Confirms the reconstructed digest becomes durable on save.
        XCTAssertNotNil(try firstDocumentJSON(at: unversionedURL)["contentFingerprint"]) // Confirms unversioned migration also persists its reconstructed digest.
    } // Ends legacy snapshot migration coverage.

    func testChunkIdentifiersAreDeterministicAndOwnershipSensitive() { // Verifies stable chunk UUIDs include document ownership, boundaries, and exact normalized contents.
        let projectID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")! // Uses a fixed project UUID for reproducible identity seeds.
        let documentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")! // Uses a fixed document UUID for reproducible identity seeds.
        let otherDocumentID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")! // Uses a second fixed ownership identity.
        let text = "Deterministic chunks keep exact offsets. Deterministic chunks keep stable fingerprints. Deterministic chunks aid incremental indexing." // Supplies enough text for several bounded windows.
        let chunker = MemoryChunker(maximumCharacters: 36, overlapCharacters: 6) // Uses explicit deterministic boundary settings.
        let firstRun = chunker.chunks(documentID: documentID, projectID: projectID, text: text) // Produces the baseline chunk records.
        let secondRun = chunker.chunks(documentID: documentID, projectID: projectID, text: text) // Repeats the identical operation.
        let otherOwnerRun = chunker.chunks(documentID: otherDocumentID, projectID: projectID, text: text) // Repeats contents under another durable document identity.
        XCTAssertGreaterThan(firstRun.count, 1) // Confirms the fixture exercises multiple identity seeds.
        XCTAssertEqual(firstRun, secondRun) // Confirms IDs, contents, ownership, indexes, and offsets are all reproducible.
        XCTAssertEqual(firstRun.map(\.id), secondRun.map(\.id)) // States the stable UUID contract explicitly.
        XCTAssertNotEqual(firstRun.map(\.id), otherOwnerRun.map(\.id)) // Confirms identical contents cannot collide across document ownership.
        XCTAssertEqual(Set(firstRun.map(\.id)).count, firstRun.count) // Confirms every chunk within one document has a distinct deterministic UUID.
    } // Ends deterministic chunk-identity coverage.

    func testIncrementalVectorUpsertClearAndStaleFingerprintRejection() async throws { // Verifies incremental physical-vector mutation never accepts stale chunk contents.
        let fixtureRoot = try makeFixtureRoot(prefix: "ProjectVectors") // Creates one exact test-owned directory tree.
        defer { try? FileManager.default.removeItem(at: fixtureRoot) } // Removes only this test's isolated fixture tree.
        let store = ProjectMemoryStore(rootURL: fixtureRoot.appendingPathComponent("store", isDirectory: true)) // Creates isolated durable memory storage.
        let project = try await store.createProject(name: "Incremental Vectors") // Creates the vector sidecar owner.
        _ = try await store.addDocument(projectID: project.id, title: "Vector Source", sourceURL: nil, text: "First vector chunk has apples. Second vector chunk has oranges. Third vector chunk has pears.", chunker: MemoryChunker(maximumCharacters: 28, overlapCharacters: 0)) // Creates several deterministic current chunks.
        let chunks = try await store.chunks(projectID: project.id) // Reads exact chunk fingerprints required for valid indexing.
        XCTAssertGreaterThan(chunks.count, 1) // Confirms incremental behavior spans more than one chunk.
        let records = vectorRecords(for: chunks, modelID: "incremental-embedding") // Creates one compatible current-fingerprint vector per chunk.
        try await store.upsertVectors(projectID: project.id, records: [records[0]]) // Adds only the first current vector.
        let partialVectors = try await store.vectors(projectID: project.id) // Reads partial vector state before the synchronous assertion.
        let partialSummary = try await store.summary(projectID: project.id) // Reads partial index status before the synchronous assertion.
        XCTAssertEqual(partialVectors, [records[0]]) // Confirms the partial upsert persists exactly one supplied record.
        XCTAssertEqual(partialSummary.indexStatus, .stale) // Confirms a partial physical index is reported as rebuild-needed.
        let stateBeforeStaleAttempt = try await store.vectors(projectID: project.id) // Captures exact valid state before a rejected mutation.
        let staleRecord = MemoryVectorRecord(projectID: project.id, chunkID: chunks[1].id, vector: [8, 8], modelID: "incremental-embedding", chunkFingerprint: String(repeating: "0", count: 64), modelRevision: "test-revision") // Supplies a well-shaped vector tied to the wrong chunk contents.
        do { // Attempts the explicitly stale incremental mutation.
            try await store.upsertVectors(projectID: project.id, records: [staleRecord]) // Runs full production validation before any commit.
            XCTFail("A stale vector fingerprint must be rejected.") // Fails if incompatible embeddings can enter the current index.
        } catch let error as ProjectMemoryError { // Captures the expected typed vector error.
            guard case let .invalidVector(detail) = error else { return XCTFail("Expected invalidVector, received \(error).") } // Requires the stale-vector validation domain.
            XCTAssertTrue(detail.contains("fingerprint")) // Confirms the diagnostic identifies content compatibility rather than an unrelated failure.
        } // Ends stale fingerprint validation.
        let stateAfterStaleAttempt = try await store.vectors(projectID: project.id) // Reads vector state after rejected validation.
        XCTAssertEqual(stateAfterStaleAttempt, stateBeforeStaleAttempt) // Confirms rejected upsert is fully non-mutating.
        try await store.upsertVectors(projectID: project.id, records: Array(records.dropFirst())) // Adds every remaining current vector without replacing the first.
        let completeVectors = try await store.vectors(projectID: project.id) // Reads the composed full vector sidecar.
        let completeSummary = try await store.summary(projectID: project.id) // Reads full-index readiness after incremental composition.
        XCTAssertEqual(Set(completeVectors.map(\.chunkID)), Set(chunks.map(\.id))) // Confirms incremental upsert composes into complete coverage.
        XCTAssertEqual(completeSummary.indexStatus, .embeddingReady) // Confirms complete matching fingerprints report physical readiness.
        let replacementRecord = MemoryVectorRecord(projectID: project.id, chunkID: chunks[0].id, vector: [9, 9], modelID: "incremental-embedding", chunkFingerprint: chunks[0].contentFingerprint, modelRevision: "test-revision") // Creates a new vector value for one existing current chunk.
        try await store.upsertVectors(projectID: project.id, records: [replacementRecord]) // Replaces only the matching chunk record.
        let replacedVectors = try await store.vectors(projectID: project.id) // Reads the incrementally replaced sidecar.
        XCTAssertEqual(replacedVectors.count, chunks.count) // Confirms replacement does not duplicate a chunk vector.
        XCTAssertEqual(replacedVectors.first(where: { $0.chunkID == chunks[0].id }), replacementRecord) // Confirms the supplied chunk receives the exact replacement vector.
        let documentsBeforeClear = try await store.documents(projectID: project.id) // Captures lexical source state before clearing rebuildable vectors.
        let chunksBeforeClear = try await store.chunks(projectID: project.id) // Captures deterministic chunks before clearing rebuildable vectors.
        try await store.clearVectors(projectID: project.id, now: Date(timeIntervalSince1970: 1_700_005_000)) // Removes only the app-owned physical vector sidecar.
        let vectorsAfterClear = try await store.vectors(projectID: project.id) // Reads the cleared vector sidecar.
        let documentsAfterClear = try await store.documents(projectID: project.id) // Reads durable documents after vector clearing.
        let chunksAfterClear = try await store.chunks(projectID: project.id) // Reads lexical chunks after vector clearing.
        let summaryAfterClear = try await store.summary(projectID: project.id) // Reads truthful readiness after vector clearing.
        XCTAssertTrue(vectorsAfterClear.isEmpty) // Confirms every rebuildable vector record is cleared.
        XCTAssertEqual(documentsAfterClear, documentsBeforeClear) // Confirms clear never removes durable normalized documents.
        XCTAssertEqual(chunksAfterClear, chunksBeforeClear) // Confirms clear never removes lexical chunks.
        XCTAssertEqual(summaryAfterClear.indexStatus, .lexicalReady) // Confirms useful zero-model retrieval remains honestly available.
    } // Ends incremental vector lifecycle coverage.

    private func makeFixtureRoot(prefix: String) throws -> URL { // Creates one unique directory whose complete ownership is limited to a single test.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true) // Resolves a collision-resistant temporary path.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) // Creates the exact fixture root before writing files.
        return root // Returns the proven test-owned directory.
    } // Ends isolated fixture-root creation.

    private func snapshotURL(root: URL, projectID: UUID) -> URL { // Reconstructs the production UUID-only snapshot location for black-box persistence assertions.
        root.appendingPathComponent(projectID.uuidString.lowercased(), isDirectory: false).appendingPathExtension("json").standardizedFileURL // Matches the production containment-safe filename convention exactly.
    } // Ends snapshot URL construction.

    private func vectorRecords(for chunks: [MemoryChunk], modelID: String) -> [MemoryVectorRecord] { // Creates deterministic finite same-dimension vectors tied to current chunk fingerprints.
        chunks.enumerated().map { offset, chunk in // Produces exactly one compatible record per supplied chunk.
            MemoryVectorRecord(projectID: chunk.projectID, chunkID: chunk.id, vector: [Float(offset + 1), 1], modelID: modelID, chunkFingerprint: chunk.contentFingerprint, modelRevision: "test-revision") // Records exact ownership, finite values, model identity, and current content compatibility.
        } // Ends deterministic vector mapping.
    } // Ends vector fixture construction.

    private func rewriteSnapshotAsLegacy(at url: URL, explicitSchemaVersion: Int?) throws { // Mechanically removes only fields absent from schema 1 or the original unversioned format.
        let data = try Data(contentsOf: url) // Reads the exact app-owned test snapshot.
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProjectMemoryError.persistenceFailed("Test snapshot was not a JSON object.") } // Requires the expected keyed snapshot representation.
        if let explicitSchemaVersion { object["schemaVersion"] = explicitSchemaVersion } else { object.removeValue(forKey: "schemaVersion") } // Selects explicit schema 1 or the original absent-version representation.
        object.removeValue(forKey: "indexIssue") // Removes the V2 recoverable-index metadata key.
        guard var documents = object["documents"] as? [[String: Any]] else { throw ProjectMemoryError.persistenceFailed("Test snapshot documents were not JSON objects.") } // Requires editable document dictionaries.
        for index in documents.indices { // Removes only document metadata introduced after the foundation schema.
            documents[index].removeValue(forKey: "contentFingerprint") // Simulates legacy documents before SHA-256 persistence.
            documents[index].removeValue(forKey: "sourceByteCount") // Simulates legacy documents without source-size history.
            documents[index].removeValue(forKey: "sourceModificationDate") // Simulates legacy documents without source-time history.
            documents[index].removeValue(forKey: "sourceFileExtension") // Simulates legacy documents without validated extension metadata.
        } // Ends per-document legacy shaping.
        object["documents"] = documents // Restores the edited legacy document collection into the snapshot object.
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) // Encodes valid deterministic legacy JSON.
        try legacyData.write(to: url, options: .atomic) // Replaces only the exact test snapshot atomically.
    } // Ends legacy snapshot fixture transformation.

    private func snapshotSchemaVersion(at url: URL) throws -> Int? { // Reads the top-level schema marker after migration persistence.
        let data = try Data(contentsOf: url) // Reads the exact migrated snapshot bytes.
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any]) // Requires a keyed JSON snapshot.
        return object["schemaVersion"] as? Int // Returns the persisted numeric schema marker when present.
    } // Ends schema-version inspection.

    private func firstDocumentJSON(at url: URL) throws -> [String: Any] { // Reads the first persisted document dictionary for migration assertions.
        let data = try Data(contentsOf: url) // Reads the exact migrated snapshot bytes.
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any]) // Requires a keyed JSON snapshot.
        let documents = try XCTUnwrap(object["documents"] as? [[String: Any]]) // Requires the expected document array.
        return try XCTUnwrap(documents.first) // Returns the first migrated document dictionary.
    } // Ends migrated document JSON inspection.
} // Ends comprehensive Project Memory lifecycle tests.
