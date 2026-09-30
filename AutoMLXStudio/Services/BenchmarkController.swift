import Foundation // Supplies URLs, dates, and observable controller state.

@MainActor
final class BenchmarkController: ObservableObject { // Owns benchmark UI state across sidebar navigation and coordinates engine persistence.
    @Published private(set) var builtInSuite = BuiltInBenchmarkSuite.standard // Exposes the immutable shipped suite.
    @Published private(set) var customSuites: [BenchmarkSuite] = [] // Exposes persisted editable suites.
    @Published private(set) var runs: [BenchmarkRun] = [] // Exposes newest-first durable history.
    @Published private(set) var activeRun: BenchmarkRun? // Exposes the current durable execution snapshot.
    @Published private(set) var progress = BenchmarkProgress(completed: 0, total: 0, currentCaseName: nil, failures: 0, elapsedMilliseconds: 0) // Exposes low-frequency execution progress.
    @Published private(set) var isRunning = false // Prevents overlapping benchmark runs.
    @Published var selectedRunID: UUID? // Preserves result selection across view refreshes.
    @Published var comparisonRunIDs: Set<UUID> = [] // Stores up to two history selections for comparison.
    @Published var importPreview: BenchmarkSuite? // Stores validated preview before explicit persistence.
    @Published var errorMessage: String? // Surfaces bounded validation, persistence, and export failures.
    @Published private(set) var storageIssues: [String] = [] // Surfaces isolated corrupt records without blocking valid history.

    private let store: BenchmarkStore // Owns versioned record persistence.
    private let engine: BenchmarkEvaluationEngine // Owns deterministic grading and sequential execution.
    private let client: any BenchmarkGenerationClient // Owns production dispatcher access or deterministic test generation.
    private var runTask: Task<Void, Never>? // Retains exactly one UI-started run for cooperative Stop.
    private var didLoad = false // Avoids unnecessary disk reload on repeated sidebar appearances.

    init(store: BenchmarkStore = BenchmarkStore(), engine: BenchmarkEvaluationEngine = BenchmarkEvaluationEngine(), client: any BenchmarkGenerationClient) { // Creates an app-owned or test-isolated controller.
        self.store = store // Stores persistence dependency.
        self.engine = engine // Stores evaluation dependency.
        self.client = client // Stores generation dependency.
    } // Ends benchmark controller construction.

    var suites: [BenchmarkSuite] { [builtInSuite] + customSuites } // Combines immutable built-in and editable custom suites.
    var selectedRun: BenchmarkRun? { selectedRunID.flatMap { id in runs.first { $0.id == id } } } // Resolves current result detail safely.
    var comparison: BenchmarkRunComparison? { let values = comparisonRunIDs.compactMap { id in runs.first { $0.id == id } }; guard values.count == 2 else { return nil }; return BenchmarkAnalysis.compare(values[0], values[1]) } // Builds live two-run comparison only with exactly two valid records.
    var recommendations: [BenchmarkRoleRecommendation] { BenchmarkAnalysis.bestModelsByRole(from: runs) } // Derives role leaders without enabling adaptive routing.

    func load() async { // Restores valid runs and custom suites exactly once per app-owned controller.
        guard !didLoad else { return } // Preserves current active state across navigation.
        didLoad = true // Marks the disk load as attempted.
        let runLoad = await store.loadRuns() // Loads independent run records.
        let suiteLoad = await store.loadCustomSuites() // Loads independent custom suites.
        runs = runLoad.values.sorted { $0.startedAt > $1.startedAt } // Presents newest evidence first.
        customSuites = suiteLoad.values // Preserves store ordering.
        storageIssues = runLoad.issues + suiteLoad.issues // Surfaces skipped corrupt records without blocking valid values.
        selectedRunID = selectedRunID ?? runs.first?.id // Opens the latest result when available.
    } // Ends persisted-state loading.

    func start(suite: BenchmarkSuite, configuration: BenchmarkExecutionConfiguration) { // Starts one validated run without overlapping active work.
        guard !isRunning else { return } // Prevents simultaneous resource-owning evaluations.
        errorMessage = nil // Clears a previous recoverable error.
        do { // Validates before publishing running state.
            try BenchmarkSuiteValidator.validate(suite) // Validates suite snapshot.
            try BenchmarkSuiteValidator.validate(weights: configuration.weights, runsPerCase: configuration.model.runsPerCase) // Validates scoring and repeats.
            let selected = try engine.selectedCases(in: suite, configuration: configuration) // Validates selection and calculates progress.
            progress = BenchmarkProgress(completed: 0, total: selected.count * configuration.model.runsPerCase, currentCaseName: nil, failures: 0, elapsedMilliseconds: 0) // Publishes exact initial denominator.
        } catch { errorMessage = bounded(error.localizedDescription); return } // Stops safely on invalid configuration.
        isRunning = true // Publishes active ownership.
        activeRun = nil // Clears stale progress detail.
        let store = self.store // Captures Sendable actor independently from main-actor state.
        let engine = self.engine // Captures immutable Sendable evaluator.
        let client = self.client // Captures immutable Sendable generation client.
        let checkpoint: @MainActor @Sendable (BenchmarkProgress, BenchmarkRun) -> Void = { [weak self] progress, snapshot in self?.publish(progress: progress, snapshot: snapshot) } // Creates an actor-qualified immutable UI publication closure.
        runTask = Task { [weak self] in // Starts one cooperative UI-owned workflow.
            do { // Executes and persists progress checkpoints.
                let completed = try await engine.run(suite: suite, configuration: configuration, client: client) { progress, snapshot in // Executes the production-shaped harness.
                    try? await store.save(run: snapshot) // Persists each completed case independently from UI lifecycle.
                    await checkpoint(progress, snapshot) // Publishes one low-frequency checkpoint through the controller actor.
                } // Ends engine execution.
                try await store.save(run: completed) // Persists final completed or cancelled state.
                self?.upsert(completed) // Inserts or updates newest-first history.
                self?.activeRun = completed // Preserves terminal result for Running/Results transition.
                self?.selectedRunID = completed.id // Opens the new result.
            } catch is CancellationError { // Handles cancellation before a final run snapshot exists.
                self?.errorMessage = nil // Treats explicit Stop as non-error.
            } catch { self?.errorMessage = self?.bounded(error.localizedDescription) } // Surfaces fatal validation/storage failure.
            self?.isRunning = false // Releases active ownership on every terminal path.
            self?.runTask = nil // Releases task storage.
        } // Ends UI-owned run task creation.
    } // Ends benchmark start.

    func stop() { // Requests cooperative cancellation without deleting completed results.
        runTask?.cancel() // Propagates cancellation through timeout and dispatcher tasks.
    } // Ends benchmark Stop.

    func runAgain(_ run: BenchmarkRun) { // Repeats a history record against its exact current suite snapshot when available.
        guard let suite = suites.first(where: { $0.id == run.suiteID && $0.version == run.suiteVersion }) else { errorMessage = "The original suite version is no longer available."; return } // Prevents silent suite substitution.
        let configuration = BenchmarkExecutionConfiguration(mode: run.mode, selectedCategory: run.selectedCategory, selectedCaseIDs: Set(run.caseIDs), model: run.modelConfiguration, weights: run.scoreWeights, judge: .init(isEnabled: false, target: nil)) // Recreates deterministic settings while keeping optional judge disabled.
        start(suite: suite, configuration: configuration) // Starts through the same validated path.
    } // Ends Run Again.

    func deleteRun(_ run: BenchmarkRun) async { // Deletes one selected durable history record.
        guard !isRunning || activeRun?.id != run.id else { errorMessage = "Stop the active run before deleting it."; return } // Protects the active checkpoint file.
        do { try await store.deleteRun(id: run.id); runs.removeAll { $0.id == run.id }; comparisonRunIDs.remove(run.id); if selectedRunID == run.id { selectedRunID = runs.first?.id } } // Deletes exact record and synchronizes selections.
        catch { errorMessage = bounded(error.localizedDescription) } // Surfaces a recoverable persistence failure.
    } // Ends run deletion.

    func toggleBaseline(_ run: BenchmarkRun) async { // Designates at most one baseline per exact model target.
        var changed: [BenchmarkRun] = [] // Collects records requiring persistence.
        for index in runs.indices { // Updates matching model-target history deterministically.
            if runs[index].modelConfiguration.target == run.modelConfiguration.target { // Restricts baseline ownership to one target history.
                let newValue = runs[index].id == run.id ? !runs[index].isBaseline : false // Toggles selected record and clears peer baseline.
                if runs[index].isBaseline != newValue { runs[index].isBaseline = newValue; changed.append(runs[index]) } // Records only actual changes.
            } // Ends target match.
        } // Ends baseline normalization.
        for value in changed { try? await store.save(run: value) } // Persists every changed record independently.
    } // Ends baseline toggle.

    func duplicate(_ suite: BenchmarkSuite) async { // Creates an editable copy of built-in or custom content.
        let copy = suite.duplicated() // Generates a new suite identity while preserving declarative task definitions.
        do { try await store.save(suite: copy); customSuites.insert(copy, at: 0) } // Persists and presents the new editable copy.
        catch { errorMessage = bounded(error.localizedDescription) } // Surfaces validation or storage failure.
    } // Ends suite duplication.

    func saveCustomSuite(_ suite: BenchmarkSuite) async { // Saves one validated user-created suite.
        do { try await store.save(suite: suite); customSuites.removeAll { $0.id == suite.id }; customSuites.insert(suite, at: 0); importPreview = nil } // Replaces the exact custom revision.
        catch { errorMessage = bounded(error.localizedDescription) } // Preserves the previous saved suite on failure.
    } // Ends custom-suite save.

    func deleteCustomSuite(_ suite: BenchmarkSuite) async { // Deletes one editable suite without affecting immutable run snapshots.
        guard !suite.isBuiltIn else { errorMessage = BenchmarkValidationError.builtInMutation.localizedDescription; return } // Protects shipped suite.
        do { try await store.deleteSuite(id: suite.id); customSuites.removeAll { $0.id == suite.id } } // Removes only selected suite persistence.
        catch { errorMessage = bounded(error.localizedDescription) } // Surfaces recoverable deletion failure.
    } // Ends custom-suite deletion.

    func previewImport(data: Data) async { // Validates a suite and stores preview without persistence.
        do { importPreview = try await store.importPreview(data: data); errorMessage = nil } // Publishes only safe declarative preview.
        catch { importPreview = nil; errorMessage = bounded(error.localizedDescription) } // Rejects invalid imports visibly.
    } // Ends suite import preview.

    func suiteExportData(_ suite: BenchmarkSuite) async -> Data? { // Produces versioned suite export for a save panel.
        do { return try await store.suiteExportData(suite) } // Returns canonical JSON.
        catch { errorMessage = bounded(error.localizedDescription); return nil } // Surfaces export failure.
    } // Ends suite export.

    func export(_ run: BenchmarkRun, to directory: URL) { // Writes JSON and Markdown result artifacts to a user-selected directory.
        do { _ = try BenchmarkReportExporter.write(run: run, to: directory); errorMessage = nil } // Produces both requested formats atomically.
        catch { errorMessage = bounded(error.localizedDescription) } // Surfaces export failure without changing evidence.
    } // Ends result export.

    func setComparisonSelection(_ run: BenchmarkRun, selected: Bool) { // Maintains an explicit maximum of two comparison runs.
        if selected { if comparisonRunIDs.count == 2, let first = comparisonRunIDs.first { comparisonRunIDs.remove(first) }; comparisonRunIDs.insert(run.id) } // Adds selected run while evicting one older set entry.
        else { comparisonRunIDs.remove(run.id) } // Removes deselected run.
    } // Ends comparison selection.

    private func upsert(_ run: BenchmarkRun) { // Maintains newest-first history without duplicate progress entries.
        runs.removeAll { $0.id == run.id } // Removes an earlier checkpoint with the same identity.
        runs.insert(run, at: 0) // Presents terminal evidence first.
    } // Ends history upsert.

    private func publish(progress: BenchmarkProgress, snapshot: BenchmarkRun) { // Applies one Sendable engine checkpoint on the main actor.
        self.progress = progress // Updates visible completion and failure counts.
        activeRun = snapshot // Updates the durable partial result shown by Running.
    } // Ends main-actor checkpoint publication.

    private func bounded(_ value: String) -> String { String(value.replacingOccurrences(of: "\n", with: " ").prefix(512)) } // Bounds visible diagnostics.
} // Ends persistent benchmark controller.
