import AppKit // Supplies native macOS open and save panels for explicit artifact locations.
import SwiftUI // Supplies the complete native Benchmark workflow.
import UniformTypeIdentifiers // Supplies the strict JSON document type for suite import and export.

enum BenchmarkPage: String, CaseIterable, Identifiable { // Defines the stable Benchmark workspace destinations and exposes them to native layout validation.
    case overview = "Overview" // Shows latest evidence and category health.
    case newRun = "New Run" // Configures an exact suite and model target.
    case history = "History" // Filters and manages durable runs.
    case comparison = "Compare" // Compares exactly two selected runs.
    case suites = "Custom Suites" // Creates, imports, exports, and duplicates suites.
    var id: String { rawValue } // Supplies stable segmented-control identity.
} // Ends Benchmark workspace destinations.

struct BenchmarkView: View { // Presents the complete native V0.6.1 evaluation workflow.
    @EnvironmentObject private var appState: AppState // Reads exact configured local and remote model choices.
    @ObservedObject var controller: BenchmarkController // Observes app-owned run, history, and persistence state.
    @State private var page: BenchmarkPage // Preserves current Benchmark workspace destination or an explicit isolated validation destination.
    @State private var selectedSuiteID = BuiltInBenchmarkSuite.suiteID // Defaults to the immutable original suite.
    @State private var selectedTarget: ModelGenerationTarget? // Stores one collision-safe backend-qualified model selection.
    @State private var runMode: BenchmarkRunMode = .quick // Defaults to the inexpensive cross-category selection.
    @State private var selectedCategory: BenchmarkCategory = .general // Supplies the required category-mode choice.
    @State private var runsPerCase = 1 // Defaults to one deterministic execution.
    @State private var warmupEnabled = false // Keeps warmup explicitly disabled by default.
    @State private var maxOutputTokens = 512 // Supplies a conservative model-wide ceiling.
    @State private var weights = BenchmarkScoreWeights.default // Starts with the requested 35/25/20/15/5 policy.
    @State private var historySearch = "" // Filters history by model or suite name.
    @State private var historyCategory: BenchmarkCategory? // Filters history by evaluated category.
    @State private var historyState: BenchmarkRunState? // Filters history by lifecycle state.
    @State private var selectedCaseResultID: UUID? // Opens one detailed case result or an explicit isolated validation fixture.
    @State private var pendingDeletion: BenchmarkRun? // Holds one run awaiting destructive confirmation.
    @State private var customName = "" // Stores a new suite name draft.
    @State private var customCaseName = "" // Stores a new case name draft.
    @State private var customPrompt = "" // Stores a new case prompt draft.
    @State private var customExpected = "" // Stores a new exact expected answer draft.
    @State private var customCategory: BenchmarkCategory = .general // Stores the new case category.

    init(controller: BenchmarkController, initialPage: BenchmarkPage = .overview, initialCaseResultID: UUID? = nil) { // Creates the production default view or a deterministic native-render validation state.
        self.controller = controller // Observes the same app-owned or isolated controller instance.
        _page = State(initialValue: initialPage) // Seeds only the requested initial workspace destination.
        _selectedCaseResultID = State(initialValue: initialCaseResultID) // Seeds optional case inspection without changing production navigation behavior.
    } // Ends benchmark view construction.

    var body: some View { // Builds the complete Benchmark surface.
        VStack(spacing: 0) { // Keeps header and page content visually stable.
            header // Shows page identity, navigation, and active Stop action.
            Divider() // Separates persistent navigation from changing content.
            Group { if controller.isRunning { runningView } else { pageContent } } // Prioritizes live execution and cancellation visibility.
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Uses the available detail column.
        } // Ends Benchmark root stack.
        .task { await controller.load(); if selectedTarget == nil { selectedTarget = appState.effectiveChatModelChoice?.target } } // Loads durable state once and selects the existing exact Chat model when usable.
        .alert("Benchmark issue", isPresented: Binding(get: { controller.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(controller.errorMessage ?? "Unknown benchmark issue.") } // Surfaces bounded recoverable failures.
        .confirmationDialog("Delete this benchmark run?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) { // Confirms the exact material deletion.
            Button("Delete Run", role: .destructive) { if let run = pendingDeletion { Task { await controller.deleteRun(run) } }; pendingDeletion = nil } // Deletes only the selected recoverable history record.
            Button("Cancel", role: .cancel) { pendingDeletion = nil } // Preserves evidence.
        } message: { Text("The selected local history record will be removed. Export it first if you need a copy.") } // Explains deletion impact.
    } // Ends Benchmark view body.

    private var header: some View { // Presents native title, segmented destinations, and active status.
        HStack(spacing: 16) { // Aligns identity and workflow actions.
            VStack(alignment: .leading, spacing: 3) { // Groups concise title and scope.
                Text("Model Evaluation").font(.largeTitle.bold()) // Names correctness-first Benchmark purpose.
                Text("Offline cases, deterministic grading, truthful metrics").foregroundStyle(.secondary) // Clarifies the harness boundary.
            } // Ends title block.
            Spacer(minLength: 20) // Preserves breathing room.
            Picker("Benchmark page", selection: $page) { ForEach(BenchmarkPage.allCases) { Text($0.rawValue).tag($0) } } // Navigates the persistent Benchmark workspace.
                .pickerStyle(.segmented) // Uses a familiar compact macOS control.
                .frame(maxWidth: 520) // Prevents the segmented control from dominating wide layouts.
            if controller.isRunning { Button("Stop", role: .destructive) { controller.stop() }.keyboardShortcut(".", modifiers: .command).help("Stop scheduling cases and preserve completed results").accessibilityLabel("Stop benchmark") } // Exposes cooperative cancellation prominently with an explicit assistive label.
        } // Ends header row.
        .padding(.horizontal, 24) // Aligns with existing detail pages.
        .padding(.vertical, 18) // Gives title appropriate vertical space.
    } // Ends Benchmark header.

    @ViewBuilder private var pageContent: some View { // Routes the selected idle workspace.
        switch page { // Selects one bounded destination.
        case .overview: overviewView // Shows dashboard or intentional empty state.
        case .newRun: newRunView // Shows validated run configuration.
        case .history: historyView // Shows filters and durable records.
        case .comparison: comparisonView // Shows fairness checks and score differences.
        case .suites: customSuitesView // Shows safe declarative suite management.
        } // Ends page routing.
    } // Ends idle page content.

    private var overviewView: some View { // Summarizes recent evidence without dashboard decoration overload.
        ScrollView { // Supports compact windows and longer category lists.
            VStack(alignment: .leading, spacing: 22) { // Builds one calm vertical information hierarchy.
                if let run = controller.selectedRun ?? controller.runs.first { resultSummary(run) } // Shows the selected or latest result.
                else { // Shows intentional first-use state.
                    ContentUnavailableView("No evaluation results", systemImage: "checkmark.seal", description: Text("Start with a Quick run to validate the selected model across all eight categories.")) // Explains the next useful action.
                        .frame(maxWidth: .infinity, minHeight: 320) // Gives empty state enough focus.
                    Button("Configure First Run") { page = .newRun }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity) // Moves directly to the required action.
                } // Ends first-use state.
                if !controller.recommendations.isEmpty { recommendationsView } // Shows evidence-derived leaders only when categories exist.
                if !controller.storageIssues.isEmpty { storageIssuesView } // Reports isolated corrupt records without blocking valid history.
            } // Ends Overview content.
            .padding(24) // Aligns content with header.
            .frame(maxWidth: 1120, alignment: .leading) // Keeps long lines readable.
            .frame(maxWidth: .infinity) // Centers the constrained content column.
        } // Ends Overview scrolling.
    } // Ends Overview.

    private var newRunView: some View { // Configures one exact reproducible evaluation.
        Form { // Uses native macOS grouped form alignment and accessibility.
            Section("Evaluation") { // Groups suite and selection scope.
                Picker("Suite", selection: $selectedSuiteID) { ForEach(controller.suites) { suite in Text("\(suite.name) · \(suite.cases.count) cases").tag(suite.id) } }.accessibilityLabel("Benchmark suite") // Selects immutable built-in or persisted custom suite with an explicit assistive label.
                Picker("Mode", selection: $runMode) { ForEach(BenchmarkRunMode.allCases) { Text($0.displayName).tag($0) } } // Selects Quick, Standard, Category, or Custom.
                if runMode == .category { Picker("Category", selection: $selectedCategory) { ForEach(BenchmarkCategory.allCases) { Label($0.displayName, systemImage: $0.symbol).tag($0) } } } // Supplies required category-mode input.
                LabeledContent("Cases") { Text("\(selectedCasesCount)") } // Previews exact case selection count.
            } // Ends evaluation selection.
            Section("Model target") { // Groups backend-qualified physical model identity.
                Picker("Model", selection: $selectedTarget) { Text("Choose a model").tag(nil as ModelGenerationTarget?); ForEach(appState.chatModelChoices.filter(\.isSelectable)) { choice in Text("\(choice.displayName) — \(choice.groupName)").tag(Optional(choice.target)) } }.accessibilityLabel("Benchmark model") // Prevents same-name collisions across servers and exposes the selector purpose explicitly.
                if let selectedTarget { LabeledContent("Backend", value: selectedTarget.backendID.rawValue); LabeledContent("Model ID", value: selectedTarget.modelID) } // Displays exact captured target.
                Text("No fallback or adaptive routing is used. Remote targets receive benchmark prompts only when you explicitly start a run.").font(.callout).foregroundStyle(.secondary) // Discloses routing and remote-input boundaries.
            } // Ends model target section.
            Section("Execution") { // Groups reproducibility and resource settings.
                Picker("Runs per case", selection: $runsPerCase) { Text("1").tag(1); Text("3").tag(3); Text("5").tag(5) } // Restricts repeats to validated options.
                Toggle("Unscored warmup", isOn: $warmupEnabled) // Makes warmup explicit and reproducible.
                Stepper("Maximum output tokens: \(maxOutputTokens)", value: $maxOutputTokens, in: 64...4096, step: 64) // Bounds generated output safely.
                LabeledContent("LLM judge", value: "Disabled — deterministic score remains authoritative") // Makes separated optional judging status explicit.
                if selectedSuite?.cases.contains(where: { $0.category == .longContext }) == true { Label("Long Context uses locally generated synthetic input. Actual model context capacity may be unknown.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } // Warns before larger prompts.
            } // Ends execution settings.
            Section("Score weights") { // Exposes the requested configurable dimension weights.
                weightControl("Quality", value: $weights.quality) // Edits correctness weight.
                weightControl("Reliability", value: $weights.reliability) // Edits response-contract weight.
                weightControl("Tool Use", value: $weights.toolUse) // Edits tool correctness weight.
                weightControl("Engineering", value: $weights.engineering) // Edits engineering workflow weight.
                weightControl("Performance", value: $weights.performance) // Edits modest latency weight.
                LabeledContent("Total", value: String(format: "%.0f%%", weights.total * 100)) // Makes invalid totals visible before start.
            } // Ends score weights.
            Section { HStack { Spacer(); Button("Start Benchmark") { startBenchmark() }.buttonStyle(.borderedProminent).disabled(!canStart).accessibilityLabel("Start benchmark"); Spacer() } } // Presents one explicitly labeled primary execution action.
        } // Ends native configuration form.
        .formStyle(.grouped) // Uses restrained system grouping.
        .scrollContentBackground(.hidden) // Matches existing app detail background.
    } // Ends New Run.

    private var runningView: some View { // Shows live sequential progress and completed case evidence.
        VStack(alignment: .leading, spacing: 18) { // Builds a focused cancellable running state.
            HStack { // Aligns state identity and elapsed evidence.
                VStack(alignment: .leading, spacing: 4) { Text("Benchmark running").font(.title2.bold()); Text(controller.progress.currentCaseName ?? "Preparing next case…").foregroundStyle(.secondary) } // Names current work without token-level churn.
                Spacer() // Separates progress metrics.
                Text("\(controller.progress.completed) of \(controller.progress.total)").font(.title3.monospacedDigit()) // Shows exact completed repetitions.
            } // Ends running state heading.
            ProgressView(value: Double(controller.progress.completed), total: Double(max(1, controller.progress.total))).accessibilityLabel("Benchmark progress").accessibilityValue("\(controller.progress.completed) of \(controller.progress.total)") // Shows truthful accessible sequential completion.
            HStack(spacing: 24) { LabeledContent("Failures", value: "\(controller.progress.failures)"); LabeledContent("Elapsed", value: duration(controller.progress.elapsedMilliseconds)); Spacer(); Button("Stop and Keep Completed", role: .destructive) { controller.stop() }.accessibilityLabel("Stop benchmark and keep completed results") } // Shows key live facts and explicitly labeled preservation behavior.
            Divider() // Separates progress from completed results.
            if let run = controller.activeRun, !run.results.isEmpty { caseResultsTable(run) } // Shows already durable results during execution.
            else { ContentUnavailableView("Waiting for the first result", systemImage: "hourglass", description: Text("Cases run sequentially. A timeout or malformed answer will not stop the remaining suite.")) } // Explains intentional waiting state.
        } // Ends running content.
        .padding(24) // Aligns with page content.
    } // Ends Running.

    private var historyView: some View { // Filters and manages durable run history.
        VStack(spacing: 12) { // Keeps filters attached to the table.
            HStack { // Presents compact native filters.
                TextField("Filter model or suite", text: $historySearch).textFieldStyle(.roundedBorder).frame(maxWidth: 280) // Filters model and suite identity.
                Picker("Category", selection: $historyCategory) { Text("All categories").tag(nil as BenchmarkCategory?); ForEach(BenchmarkCategory.allCases) { Text($0.displayName).tag(Optional($0)) } }.frame(maxWidth: 180) // Filters evaluated category.
                Picker("State", selection: $historyState) { Text("All states").tag(nil as BenchmarkRunState?); Text("Completed").tag(Optional(BenchmarkRunState.completed)); Text("Cancelled").tag(Optional(BenchmarkRunState.cancelled)); Text("Failed").tag(Optional(BenchmarkRunState.failed)) }.frame(maxWidth: 150) // Filters durable lifecycle.
                Spacer() // Moves count to trailing edge.
                Text("\(filteredRuns.count) runs").foregroundStyle(.secondary) // Shows filter result count.
            } // Ends history filters.
            if filteredRuns.isEmpty { ContentUnavailableView("No matching runs", systemImage: "clock.arrow.circlepath", description: Text("Change the filters or start a new benchmark.")) } // Shows intentional filter empty state.
            else { // Shows durable history table.
                Table(filteredRuns, selection: $controller.selectedRunID) { // Enables native single-row result selection.
                    TableColumn("Model") { run in Text(run.modelConfiguration.target.modelID).lineLimit(1).truncationMode(.middle) } // Shows exact model ID.
                    TableColumn("Suite") { run in Text(run.suiteName).lineLimit(1) } // Shows suite snapshot identity.
                    TableColumn("Score") { run in Text(score(run.summary?.overallScore)).monospacedDigit() } // Shows weighted score.
                    TableColumn("State") { run in Label(run.state.rawValue.capitalized, systemImage: stateSymbol(run.state)).foregroundStyle(stateColor(run.state)) } // Shows semantic lifecycle.
                    TableColumn("Date") { run in Text(run.startedAt.formatted(date: .abbreviated, time: .shortened)) } // Shows timestamp.
                    TableColumn("Compare") { run in Toggle("Compare \(run.modelConfiguration.target.modelID)", isOn: Binding(get: { controller.comparisonRunIDs.contains(run.id) }, set: { controller.setComparisonSelection(run, selected: $0) })).labelsHidden().accessibilityLabel("Compare run for \(run.modelConfiguration.target.modelID)") } // Selects up to two runs with an explicit model-qualified assistive label.
                } // Ends history table columns.
                .contextMenu(forSelectionType: UUID.self) { ids in if let id = ids.first, let run = controller.runs.first(where: { $0.id == id }) { Button("Run Again") { controller.runAgain(run) }; Button(run.isBaseline ? "Remove Baseline" : "Set as Baseline") { Task { await controller.toggleBaseline(run) } }; Divider(); Button("Delete", role: .destructive) { pendingDeletion = run } } } primaryAction: { ids in if let id = ids.first { controller.selectedRunID = id; page = .overview } } // Provides native history actions.
                HStack { // Presents visible actions for keyboard and discoverability.
                    Button("Open Result") { page = .overview }.disabled(controller.selectedRun == nil) // Opens selected details.
                    Button("Run Again") { if let run = controller.selectedRun { controller.runAgain(run) } }.disabled(controller.selectedRun == nil) // Repeats exact settings.
                    Button("Export JSON + Markdown") { if let run = controller.selectedRun { exportResult(run) } }.disabled(controller.selectedRun == nil).accessibilityLabel("Export benchmark result as JSON and Markdown") // Writes both formats with an explicit assistive label.
                    Spacer() // Separates destructive action.
                    Button("Delete", role: .destructive) { pendingDeletion = controller.selectedRun }.disabled(controller.selectedRun == nil) // Requests confirmation.
                } // Ends history actions.
            } // Ends non-empty history.
        } // Ends history content.
        .padding(20) // Aligns filters and table.
    } // Ends History.

    private var comparisonView: some View { // Compares two explicitly selected history records.
        ScrollView { // Supports detailed score and warning content.
            VStack(alignment: .leading, spacing: 18) { // Creates a single readable comparison column.
                Text("Select two runs in History. Model and backend may differ; suite, cases, repeats, generation settings, weights, and architecture must match.").foregroundStyle(.secondary) // Explains fair comparison policy.
                if let comparison = controller.comparison { // Shows two-run result.
                    HStack(alignment: .firstTextBaseline) { Text(comparison.first.modelConfiguration.target.modelID).font(.title3.bold()); Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary); Text(comparison.second.modelConfiguration.target.modelID).font(.title3.bold()); Spacer(); Label(comparison.comparability.isComparable ? "Comparable" : "Review differences", systemImage: comparison.comparability.isComparable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(comparison.comparability.isComparable ? .green : .orange) } // Shows identity and verdict.
                    if !comparison.comparability.differences.isEmpty { ForEach(comparison.comparability.differences, id: \.self) { Label($0, systemImage: "exclamationmark.circle").foregroundStyle(.secondary) } } // Lists every fairness mismatch.
                    comparisonTable(comparison) // Shows dimension scores side by side.
                } else { ContentUnavailableView("Choose two runs", systemImage: "arrow.left.arrow.right", description: Text("Use the Compare checkboxes in History.")).frame(maxWidth: .infinity, minHeight: 300) } // Shows clear selection action.
            } // Ends comparison content.
            .padding(24) // Aligns with other pages.
            .frame(maxWidth: 1000, alignment: .leading) // Keeps comparisons readable.
            .frame(maxWidth: .infinity) // Centers content.
        } // Ends comparison scrolling.
    } // Ends Compare.

    private var customSuitesView: some View { // Creates and manages declarative user suites safely.
        HSplitView { // Separates suite inventory from editor and import preview.
            List(selection: $selectedSuiteID) { // Shows built-in and custom suite identity.
                Section("Built-in · Read Only") { suiteRow(controller.builtInSuite) } // Makes immutability visible.
                Section("Custom") { ForEach(controller.customSuites) { suiteRow($0) } } // Shows editable local suites.
            } // Ends suite list.
            .frame(minWidth: 250, idealWidth: 290) // Keeps names readable.
            Form { // Presents safe creation and selected suite actions.
                Section("Create Exact-Match Suite") { // Provides a useful minimum custom-suite editor.
                    TextField("Suite name", text: $customName) // Captures suite identity.
                    TextField("Case name", text: $customCaseName) // Captures case identity.
                    Picker("Category", selection: $customCategory) { ForEach(BenchmarkCategory.allCases) { Text($0.displayName).tag($0) } } // Captures scoring category.
                    TextField("Prompt", text: $customPrompt, axis: .vertical).lineLimit(3...8) // Captures bounded declarative input.
                    TextField("Exact expected answer", text: $customExpected) // Captures safe exact grader data.
                    Button("Create Suite") { createCustomSuite() }.disabled(customName.trimmed.isEmpty || customCaseName.trimmed.isEmpty || customPrompt.trimmed.isEmpty) // Persists only a complete minimum suite.
                } // Ends custom suite creation.
                Section("Import / Export") { // Presents explicit file operations.
                    HStack { Button("Import JSON…") { importSuite() }.accessibilityLabel("Import benchmark suite JSON"); Button("Export Selected…") { exportSuite() }.disabled(selectedSuite == nil).accessibilityLabel("Export selected benchmark suite"); Button("Duplicate Selected") { if let suite = selectedSuite { Task { await controller.duplicate(suite) } } }.disabled(selectedSuite == nil) } // Exposes explicitly labeled versioned interoperability and built-in duplication.
                    Text("Imports are limited to 2 MB and declarative graders. No scripts, shell commands, or arbitrary code can be imported.").font(.callout).foregroundStyle(.secondary) // Explains safety boundary.
                    if let preview = controller.importPreview { VStack(alignment: .leading, spacing: 6) { Label("Validated preview", systemImage: "checkmark.circle.fill").foregroundStyle(.green); Text(preview.name).font(.headline); Text("\(preview.cases.count) cases · suite version \(preview.version)").foregroundStyle(.secondary); Button("Save Imported Suite") { Task { await controller.saveCustomSuite(preview) } }.buttonStyle(.borderedProminent) } } // Requires explicit persistence after preview.
                } // Ends import and export.
                if let suite = selectedSuite { Section("Selected Suite") { LabeledContent("Name", value: suite.name); LabeledContent("Version", value: "\(suite.version)"); LabeledContent("Cases", value: "\(suite.cases.count)"); Text(suite.description).foregroundStyle(.secondary); if !suite.isBuiltIn { Button("Delete Custom Suite", role: .destructive) { Task { await controller.deleteCustomSuite(suite) } } } } } // Shows selected suite detail and bounded destructive action.
            } // Ends suite management form.
            .formStyle(.grouped) // Uses system visual hierarchy.
            .frame(minWidth: 480) // Preserves form legibility.
        } // Ends suite split view.
    } // Ends Custom Suites.

    private func resultSummary(_ run: BenchmarkRun) -> some View { // Presents one complete result with case detail.
        VStack(alignment: .leading, spacing: 18) { // Groups run identity, scores, metrics, and cases.
            HStack(alignment: .top) { // Aligns identity and result actions.
                VStack(alignment: .leading, spacing: 4) { // Groups reproducibility identity.
                    HStack { Text(run.modelConfiguration.target.modelID).font(.title2.bold()); if run.isBaseline { Label("Baseline", systemImage: "flag.fill").foregroundStyle(.blue) } } // Shows exact model and optional baseline.
                    Text("\(run.suiteName) · \(run.startedAt.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary) // Shows suite snapshot and date.
                    HStack { Label(run.state.rawValue.capitalized, systemImage: stateSymbol(run.state)).foregroundStyle(stateColor(run.state)); Text("\(run.modelConfiguration.target.backendID.rawValue) · \(run.mode.displayName) · \(run.modelConfiguration.runsPerCase)× repetitions").foregroundStyle(.secondary) }.font(.callout) // Shows explicit lifecycle and execution configuration, including cancelled and failed states.
                } // Ends identity block.
                Spacer() // Separates actions.
                Button("Run Again") { controller.runAgain(run) } // Repeats exact deterministic settings.
                Button("Export…") { exportResult(run) }.accessibilityLabel("Export benchmark result as JSON and Markdown") // Writes JSON and Markdown together with an explicit assistive label.
            } // Ends result identity row.
            if let summary = run.summary { // Shows calculated scores and raw metrics.
                HStack(spacing: 26) { metric("Overall", score(summary.overallScore)); metric("Quality", score(summary.qualityScore)); metric("Reliability", score(summary.reliabilityScore)); metric("Tool", score(summary.toolUseScore)); metric("Engineering", score(summary.engineeringScore)) } // Shows concise primary dimensions.
                Divider() // Separates headline scores.
                HStack(spacing: 28) { metric("Mean latency", milliseconds(summary.performance.meanLatencyMilliseconds)); metric("Median", milliseconds(summary.performance.medianLatencyMilliseconds)); metric("P95", milliseconds(summary.performance.p95LatencyMilliseconds)); metric("Tokens", summary.totalTokens.map(String.init) ?? "N/A"); metric("Tokens/sec", summary.performance.meanOutputTokensPerSecond.map { String(format: "%.1f", $0) } ?? "N/A"); metric("Tool calls", "\(summary.toolCalls)") } // Shows only truthful optional metrics.
                categoryScoreGrid(summary) // Shows all evaluated category scores.
            } // Ends summary metrics.
            Divider() // Separates run summary and case inspection.
            caseResultsTable(run) // Shows every completed repetition and detail.
        } // Ends result summary.
    } // Ends result summary view.

    private func caseResultsTable(_ run: BenchmarkRun) -> some View { // Shows case list and selected result detail.
        HSplitView { // Keeps dense results scannable while supporting full inspection.
            Table(run.results, selection: $selectedCaseResultID) { // Uses native sortable-style columns.
                TableColumn("Case") { result in Text(result.caseName).lineLimit(1) } // Shows stable snapshot name.
                TableColumn("Category") { result in Text(result.category.displayName) } // Shows score taxonomy.
                TableColumn("Run") { result in Text("\(result.repetition)").monospacedDigit() } // Shows repetition.
                TableColumn("Status") { result in Label(result.status.rawValue.capitalized, systemImage: caseSymbol(result.status)).foregroundStyle(caseColor(result.status)) } // Shows semantic status.
                TableColumn("Score") { result in Text(score(result.score)).monospacedDigit() } // Shows deterministic score.
                TableColumn("Latency") { result in Text("\(result.timing.totalDurationMilliseconds) ms").monospacedDigit() } // Shows truthful total time.
            } // Ends case result table.
            .frame(minWidth: 590, minHeight: 260) // Preserves useful column space.
            if let result = selectedCaseResult(in: run) { // Shows full selected case evidence.
                ScrollView { // Allows long synthetic inputs without expanding the layout.
                    VStack(alignment: .leading, spacing: 12) { // Groups case identity and evidence.
                        Text(result.caseName).font(.headline) // Shows snapshot case identity.
                        LabeledContent("Grader", value: result.grader) // Shows deterministic strategy.
                        LabeledContent("Status", value: result.status.rawValue.capitalized) // Shows terminal result.
                        LabeledContent("Score", value: score(result.score)) // Shows deterministic score.
                        Text("Expected / grading").font(.caption).foregroundStyle(.secondary) // Labels grading evidence.
                        Text(result.gradingDetails) // Explains visible grader outcome.
                        Text("Input").font(.caption).foregroundStyle(.secondary) // Labels prompt snapshot.
                        Text(result.input).textSelection(.enabled) // Shows bounded exact input.
                        Text("Output").font(.caption).foregroundStyle(.secondary) // Labels output snapshot.
                        Text(result.output ?? "No output").textSelection(.enabled) // Shows output or explicit absence.
                        if let error = result.errorMessage { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } // Shows bounded failure detail.
                    } // Ends case evidence.
                    .padding(16) // Gives readable detail spacing.
                    .frame(maxWidth: .infinity, alignment: .leading) // Keeps text leading aligned.
                } // Ends case detail scrolling.
                .frame(minWidth: 300, idealWidth: 380) // Keeps detail readable.
            } else { ContentUnavailableView("Select a case", systemImage: "doc.text.magnifyingglass").frame(minWidth: 300) } // Shows intentional case-detail empty state.
        } // Ends case result split.
    } // Ends case table and detail.

    private var recommendationsView: some View { // Shows transparent category leaders without applying them.
        VStack(alignment: .leading, spacing: 10) { // Groups explanation and role rows.
            Text("Best model by role").font(.title3.bold()) // Names recommendation area.
            Text("Recommendations are derived from completed category scores only. They do not change model assignments or routing.").foregroundStyle(.secondary) // Discloses non-adaptive behavior.
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 8) { ForEach(controller.recommendations) { recommendation in GridRow { Text(recommendation.role.displayName).foregroundStyle(.secondary); Text(recommendation.target.modelID).lineLimit(1); Text(score(recommendation.score)).monospacedDigit() } } } // Presents evidence-linked role leaders.
        } // Ends recommendation area.
    } // Ends recommendations.

    private var storageIssuesView: some View { // Reports non-blocking isolated persistence issues.
        VStack(alignment: .leading, spacing: 6) { Label("Some benchmark records were skipped", systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(.orange); ForEach(controller.storageIssues, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) } } // Lists bounded corrupt record diagnostics.
    } // Ends storage issues.

    private func comparisonTable(_ comparison: BenchmarkRunComparison) -> some View { // Shows side-by-side aggregate score values.
        let first = comparison.first.summary // Reads first calculated summary.
        let second = comparison.second.summary // Reads second calculated summary.
        return Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 10) { // Uses a simple native comparison matrix.
            GridRow { Text("Dimension").font(.headline); Text("First").font(.headline); Text("Second").font(.headline); Text("Δ").font(.headline) } // Writes column headings.
            comparisonRow("Overall", first?.overallScore, second?.overallScore) // Compares weighted overall.
            comparisonRow("Quality", first?.qualityScore, second?.qualityScore) // Compares quality.
            comparisonRow("Reliability", first?.reliabilityScore, second?.reliabilityScore) // Compares reliability.
            comparisonRow("Tool Use", first?.toolUseScore, second?.toolUseScore) // Compares tool behavior.
            comparisonRow("Engineering", first?.engineeringScore, second?.engineeringScore) // Compares engineering workflow.
            comparisonRow("Performance", first?.performanceScore, second?.performanceScore) // Compares bounded performance contribution.
        } // Ends score comparison grid.
    } // Ends comparison table.

    private func comparisonRow(_ name: String, _ first: Double?, _ second: Double?) -> some View { // Builds one aligned comparison row.
        GridRow { Text(name).foregroundStyle(.secondary); Text(score(first)).monospacedDigit(); Text(score(second)).monospacedDigit(); Text(delta(first, second)).monospacedDigit() } // Shows both values and signed second-minus-first delta.
    } // Ends comparison row.

    private func categoryScoreGrid(_ summary: ModelEvaluationSummary) -> some View { // Shows all eight category scores compactly.
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) { // Creates two aligned category columns.
            ForEach(Array(BenchmarkCategory.allCases.enumerated()), id: \.element.id) { index, category in // Iterates stable taxonomy order.
                if index.isMultiple(of: 2) { GridRow { categoryScore(category, summary); if BenchmarkCategory.allCases.indices.contains(index + 1) { categoryScore(BenchmarkCategory.allCases[index + 1], summary) } } } // Places two accessible metrics per row.
            } // Ends category iteration.
        } // Ends category grid.
    } // Ends category score grid.

    private func categoryScore(_ category: BenchmarkCategory, _ summary: ModelEvaluationSummary) -> some View { // Builds one semantic category metric.
        LabeledContent { Text(score(summary.categoryScores[category])).monospacedDigit() } label: { Label(category.displayName, systemImage: category.symbol).foregroundStyle(.secondary) } // Shows icon, category, and optional score.
    } // Ends category metric.

    private func metric(_ label: String, _ value: String) -> some View { // Builds one restrained label-value pair without decorative cards.
        VStack(alignment: .leading, spacing: 3) { Text(value).font(.title3.bold()).monospacedDigit(); Text(label).font(.caption).foregroundStyle(.secondary) } // Uses typography for hierarchy.
    } // Ends compact metric.

    private func weightControl(_ label: String, value: Binding<Double>) -> some View { // Builds one bounded accessible score-weight editor.
        HStack { Text(label); Slider(value: value, in: 0...1, step: 0.05).accessibilityLabel("\(label) weight"); Text(String(format: "%.0f%%", value.wrappedValue * 100)).monospacedDigit().frame(width: 48, alignment: .trailing) } // Shows and edits exact percentage.
    } // Ends weight control.

    private func suiteRow(_ suite: BenchmarkSuite) -> some View { // Builds one suite inventory row.
        VStack(alignment: .leading, spacing: 2) { Text(suite.name); Text("\(suite.cases.count) cases · v\(suite.version)").font(.caption).foregroundStyle(.secondary) }.tag(suite.id) // Shows stable identity and size.
    } // Ends suite row.

    private var selectedSuite: BenchmarkSuite? { controller.suites.first { $0.id == selectedSuiteID } } // Resolves current suite without fallback mutation.

    private var selectedCasesCount: Int { // Previews mode-derived case count.
        guard let suite = selectedSuite else { return 0 } // Requires a valid suite selection.
        switch runMode { // Applies current visible selection policy.
        case .quick: return min(10, suite.cases.filter { $0.tags.contains("quick") }.count) // Counts tagged quick cases.
        case .standard: return suite.cases.count // Counts all standard cases.
        case .category: return suite.cases.filter { $0.category == selectedCategory }.count // Counts selected category.
        case .custom: return suite.cases.count // Counts complete custom suite.
        } // Ends selection count.
    } // Ends case-count preview.

    private var canStart: Bool { selectedSuite != nil && selectedTarget != nil && selectedCasesCount > 0 && abs(weights.total - 1) < 0.0001 } // Requires a complete exact configuration and 100% weight total.

    private var filteredRuns: [BenchmarkRun] { // Applies visible history filters deterministically.
        controller.runs.filter { run in // Evaluates every durable run.
            let query = historySearch.trimmed // Normalizes boundary whitespace.
            let matchesText = query.isEmpty || run.suiteName.localizedCaseInsensitiveContains(query) || run.modelConfiguration.target.modelID.localizedCaseInsensitiveContains(query) // Matches visible suite or model identity.
            let matchesCategory = historyCategory.map { run.summary?.categoryScores[$0] != nil } ?? true // Requires evidence for selected category.
            let matchesState = historyState.map { run.state == $0 } ?? true // Requires selected lifecycle state.
            return matchesText && matchesCategory && matchesState // Applies all active filters.
        } // Ends run filtering.
    } // Ends filtered history.

    private func startBenchmark() { // Converts UI state into a complete immutable execution configuration.
        guard let suite = selectedSuite, let target = selectedTarget else { return } // Requires exact suite and target.
        let localProfile = appState.modelRegistry.model(id: target.modelID) // Resolves optional local metadata without loading a model.
        let localIdentity = localProfile?.localPath.map { URL(fileURLWithPath: $0).lastPathComponent } // Stores only a privacy-safe path component.
        let model = BenchmarkModelConfiguration(target: target, quantization: nil, localPathIdentity: localIdentity, mlxConfiguration: target.backendID == .localMLX ? "MLX LM adapter" : nil, temperature: nil, maxOutputTokens: maxOutputTokens, contextLength: nil, seed: nil, streaming: false, qualityMode: "Deterministic", appVersion: BenchmarkEnvironment.current().appVersion, warmupEnabled: warmupEnabled, runsPerCase: runsPerCase) // Captures truthful known settings and leaves unknown metadata nil.
        let configuration = BenchmarkExecutionConfiguration(mode: runMode, selectedCategory: runMode == .category ? selectedCategory : nil, selectedCaseIDs: [], model: model, weights: weights, judge: .init(isEnabled: false, target: nil)) // Keeps optional LLM judge separated and disabled.
        controller.start(suite: suite, configuration: configuration) // Starts the validated sequential engine.
    } // Ends run configuration conversion.

    private func createCustomSuite() { // Creates one safe exact-match suite from the visible minimum editor.
        let item = BenchmarkCase(name: customCaseName.trimmed, category: customCategory, prompt: customPrompt.trimmed, expectedDescription: customExpected, grading: .exact(expected: customExpected), timeoutSeconds: 60, maxOutputTokens: 256, tags: [], difficulty: .easy) // Creates one declarative non-executable case.
        let suite = BenchmarkSuite(name: customName.trimmed, description: "User-created exact-match benchmark suite.", category: nil, cases: [item]) // Creates one editable version-one suite.
        Task { await controller.saveCustomSuite(suite) } // Validates and persists through the actor store.
        customName = ""; customCaseName = ""; customPrompt = ""; customExpected = "" // Clears the completed draft.
    } // Ends custom suite creation.

    private func importSuite() { // Opens a native single-file JSON import panel.
        let panel = NSOpenPanel() // Creates a user-controlled file chooser.
        panel.allowedContentTypes = [.json] // Restricts selection to JSON.
        panel.allowsMultipleSelection = false // Bounds import to one preview at a time.
        panel.canChooseDirectories = false // Requires a file.
        guard panel.runModal() == .OK, let url = panel.url else { return } // Honors cancellation without side effects.
        do { let data = try Data(contentsOf: url, options: [.mappedIfSafe]); Task { await controller.previewImport(data: data) } } // Reads and validates the explicitly selected bounded file.
        catch { controller.errorMessage = String(error.localizedDescription.prefix(512)) } // Surfaces local read failure.
    } // Ends suite import panel.

    private func exportSuite() { // Saves one selected suite as canonical versioned JSON.
        guard let suite = selectedSuite else { return } // Requires visible selection.
        Task { // Obtains actor-produced JSON before presenting save result.
            guard let data = await controller.suiteExportData(suite) else { return } // Stops on validation failure.
            await MainActor.run { // Presents save panel on the application actor.
                let panel = NSSavePanel() // Creates a native user-controlled destination.
                panel.allowedContentTypes = [.json] // Restricts extension to JSON.
                panel.nameFieldStringValue = "\(suite.name.replacingOccurrences(of: " ", with: "-"))-v\(suite.version).json" // Suggests a descriptive non-sensitive filename.
                if panel.runModal() == .OK, let url = panel.url { do { try data.write(to: url, options: [.atomic]) } catch { controller.errorMessage = String(error.localizedDescription.prefix(512)) } } // Writes only after explicit confirmation.
            } // Ends main-actor save panel.
        } // Ends suite export task.
    } // Ends suite export panel.

    private func exportResult(_ run: BenchmarkRun) { // Chooses one directory for paired JSON and Markdown artifacts.
        let panel = NSOpenPanel() // Creates a native destination chooser.
        panel.canChooseDirectories = true // Allows one output directory.
        panel.canChooseFiles = false // Prevents ambiguous file replacement.
        panel.canCreateDirectories = true // Allows an explicit new report folder.
        panel.prompt = "Export Here" // Clarifies directory selection action.
        guard panel.runModal() == .OK, let directory = panel.url else { return } // Honors cancellation.
        controller.export(run, to: directory) // Writes both formats through the exporter.
    } // Ends result export panel.

    private func selectedCaseResult(in run: BenchmarkRun) -> BenchmarkCaseResult? { selectedCaseResultID.flatMap { id in run.results.first { $0.id == id } } } // Resolves exact case result selection.
    private func score(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "N/A" } // Formats optional scores without inventing zero.
    private func score(_ value: Double) -> String { String(format: "%.1f", value) } // Formats required scores consistently.
    private func milliseconds(_ value: Double?) -> String { value.map { String(format: "%.0f ms", $0) } ?? "N/A" } // Formats optional latency honestly.
    private func duration(_ milliseconds: Int) -> String { String(format: "%.1f s", Double(milliseconds) / 1_000) } // Formats elapsed time compactly.
    private func delta(_ first: Double?, _ second: Double?) -> String { guard let first, let second else { return "N/A" }; return String(format: "%+.1f", second - first) } // Formats signed comparison delta.
    private func stateSymbol(_ state: BenchmarkRunState) -> String { switch state { case .completed: return "checkmark.circle.fill"; case .cancelled: return "stop.circle"; case .failed: return "xmark.octagon.fill"; case .queued, .running: return "clock" } } // Maps run lifecycle to semantic symbols.
    private func stateColor(_ state: BenchmarkRunState) -> Color { switch state { case .completed: return .green; case .cancelled: return .orange; case .failed: return .red; case .queued, .running: return .secondary } } // Maps run lifecycle to redundant semantic color.
    private func caseSymbol(_ status: BenchmarkCaseStatus) -> String { switch status { case .passed: return "checkmark.circle.fill"; case .failed: return "xmark.circle.fill"; case .error: return "exclamationmark.octagon.fill"; case .cancelled: return "stop.circle" } } // Maps case outcome to symbols.
    private func caseColor(_ status: BenchmarkCaseStatus) -> Color { switch status { case .passed: return .green; case .failed: return .red; case .error: return .orange; case .cancelled: return .secondary } } // Maps case outcome to redundant semantic color.
} // Ends V0.6.1 Benchmark UI.

private extension String { // Adds boundary-only form normalization.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } // Returns visible form content without boundary whitespace.
} // Ends form text helper.
