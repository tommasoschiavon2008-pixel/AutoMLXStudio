import SwiftUI // Supplies the native macOS agent registry and trace interface.

struct AgentsView: View { // Displays registered agents, persisted V0.2 assignments, and the most recent real workflow.
    @EnvironmentObject private var appState: AppState // Reads the central registries, model setting, server state, and workflow trace.

    var body: some View { // Defines the complete Agents destination.
        ScrollView { // Allows the operational content to remain usable in shorter windows.
            VStack(alignment: .leading, spacing: 22) { // Uses the spacing rhythm established by Dashboard.
                header // Shows the destination title and concise purpose.
                registrySection // Shows the six centrally registered LLM agents.
                latestWorkflowSection // Shows the latest actual workflow or an instructive empty state.
            } // Ends the primary Agents content stack.
            .padding(24) // Matches the existing Dashboard and Benchmark page inset.
            .frame(maxWidth: .infinity, alignment: .leading) // Keeps content aligned to the native detail surface.
        } // Ends the scrollable Agents surface.
        .background(Color(nsColor: .windowBackgroundColor)) // Preserves the existing macOS appearance in dark and light modes.
    } // Ends the Agents view body.

    private var header: some View { // Renders the page heading without a decorative hero treatment.
        VStack(alignment: .leading, spacing: 5) { // Matches the heading cadence used by Dashboard.
            Text("Agents") // Names the new sidebar destination.
                .font(.largeTitle.bold()) // Uses the existing top-level page hierarchy.
            Text("Agent roles, compatible model assignments, fallbacks, and operational workflow trace.") // Explains exactly what the V0.2 page displays.
                .foregroundStyle(.secondary) // Keeps supporting copy visually subordinate.
        } // Ends the page heading stack.
    } // Ends the Agents page header.

    private var registrySection: some View { // Displays all six LLM agent definitions from AgentRegistry.
        GroupBox("Agent registry") { // Uses one native container instead of a repeated card grid.
            ScrollView(.horizontal) { // Preserves readable assignment columns in narrower windows without compressing controls.
                VStack(spacing: 0) { // Builds a dense, scannable registry list.
                    ForEach(Array(appState.agentRegistry.agents.enumerated()), id: \.element.id) { index, agent in // Reads the actual central registry in stable order.
                        if index > 0 { Divider() } // Separates rows with the existing native component vocabulary.
                        agentRow(agent) // Renders the current agent assignment and status.
                    } // Ends registry iteration.
                } // Ends registry iteration.
                .frame(minWidth: 1_270, alignment: .leading) // Maintains stable desktop columns including lightweight local performance facts.
                .padding(.vertical, 2) // Adds restrained breathing room within the native GroupBox.
            } // Ends the horizontal assignment table viewport.
        } // Ends the registry container.
    } // Ends the agent registry section.

    private func agentRow(_ agent: AgentDefinition) -> some View { // Renders one actual registry entry.
        HStack(spacing: 14) { // Aligns identity, capability, model assignment, fallback, resolution, and status columns.
            Image(systemName: symbol(for: agent.kind)) // Uses a native role-specific symbol.
                .font(.title3) // Gives the symbol enough presence for scanning.
                .foregroundStyle(.secondary) // Avoids decorative accent color on inactive content.
                .frame(width: 30) // Aligns all agent names regardless of symbol width.
                .accessibilityHidden(true) // Leaves the adjacent text as the meaningful accessible label.
            VStack(alignment: .leading, spacing: 3) { // Groups agent name and type.
                Text(agent.name) // Shows the centralized registry name.
                    .font(.headline) // Establishes the primary row hierarchy.
                Text(agent.kind.displayName) // Shows the agent orchestration type.
                    .font(.caption) // Keeps the type subordinate to the name.
                    .foregroundStyle(.secondary) // Uses the native secondary text color.
            } // Ends agent identity grouping.
            .frame(width: 150, alignment: .leading) // Establishes a stable identity column.
            VStack(alignment: .leading, spacing: 3) { // Groups required capability labels.
                Text("Required") // Names the capability requirement column.
                    .font(.caption) // Keeps the label compact.
                    .foregroundStyle(.secondary) // Uses secondary hierarchy for column labels.
                Text(capabilityText(for: agent)) // Shows the real typed capability declarations.
                    .font(.callout) // Keeps capability values legible.
                    .lineLimit(2) // Allows explicit Swift and reasoning requirements without excessive width.
            } // Ends required capability grouping.
            .frame(width: 150, alignment: .leading) // Establishes a stable requirement column.
            VStack(alignment: .leading, spacing: 3) { // Groups the editable preferred-model assignment.
                Text("Preferred model") // Names the assignment column explicitly.
                    .font(.caption) // Keeps the label compact.
                    .foregroundStyle(.secondary) // Uses secondary hierarchy for column labels.
                Picker("Preferred model", selection: preferredModelBinding(agent)) { // Provides persisted compatible model choices through a native control.
                    Text("Automatic") // Allows ModelRouter capability and legacy fallback selection.
                        .tag(Optional<String>.none) // Stores an absent explicit preferred model.
                    ForEach(appState.compatibleModels(for: agent)) { profile in // Suggests only models satisfying all agent requirements.
                        Text(profile.installationState == .installed ? profile.displayName : "\(profile.displayName) · Not installed") // Keeps optional catalog state visible before selection.
                            .tag(Optional(profile.id)) // Stores the stable physical model registry ID.
                    } // Ends compatible model choices.
                } // Ends preferred-model Picker.
                .labelsHidden() // Avoids repeating the visible column label.
                .frame(width: 230, alignment: .leading) // Gives model names enough desktop width.
            } // Ends preferred-model assignment grouping.
            VStack(alignment: .leading, spacing: 3) { // Shows the deterministic fallback chain separately from the preference.
                Text("Fallbacks") // Names the fallback column.
                    .font(.caption) // Keeps the label subordinate.
                    .foregroundStyle(.secondary) // Uses native secondary hierarchy.
                Text(appState.fallbackModelNames(for: agent)) // Shows declared alternatives and the final migrated V0.1 fallback.
                    .font(.caption) // Keeps potentially longer fallback copy compact.
                    .foregroundStyle(.secondary) // Keeps fallback detail subordinate.
                    .lineLimit(2) // Allows a concise two-line recovery chain.
                    .help(appState.fallbackModelNames(for: agent)) // Exposes the complete chain on hover.
            } // Ends fallback grouping.
            .frame(width: 210, alignment: .leading) // Establishes a stable fallback column.
            VStack(alignment: .leading, spacing: 3) { // Shows the current deterministic ModelRouter resolution preview.
                Text("Resolved model") // Names the actual current selection column.
                    .font(.caption) // Keeps the label subordinate.
                    .foregroundStyle(.secondary) // Uses native secondary hierarchy.
                Text(appState.resolvedModel(for: agent)?.displayName ?? "Unavailable") // Shows the same model production routing can currently use.
                    .font(.callout.weight(.medium)) // Makes actual resolution scannable.
                    .lineLimit(1) // Keeps the row compact.
                    .truncationMode(.middle) // Preserves useful name segments.
            } // Ends resolved-model grouping.
            .frame(width: 170, alignment: .leading) // Establishes a stable actual model column.
            performanceSummary(for: agent) // Shows bounded session-local execution evidence without external telemetry.
                .frame(width: 205, alignment: .leading) // Keeps request, outcome, duration, and fallback facts scannable.
            statusLabel(for: agent) // Shows whether an enabled installed compatible model can currently execute.
                .frame(width: 86, alignment: .leading) // Keeps availability states aligned across rows.
        } // Ends one registry row.
        .padding(.horizontal, 8) // Aligns content inside the GroupBox border.
        .padding(.vertical, 11) // Provides comfortable click-free information density.
    } // Ends agent registry row rendering.

    @ViewBuilder
    private var latestWorkflowSection: some View { // Displays the most recent actual trace from AppState.
        GroupBox("Latest workflow") { // Uses the same native container vocabulary as the registry.
            if let trace = appState.latestWorkflowTrace { // Shows workflow metadata only after a real request executes.
                VStack(alignment: .leading, spacing: 16) { // Groups summary metadata and the ordered trace.
                    workflowHeader(trace) // Shows intent, model, outcome, and total measured duration.
                    Divider() // Separates request summary from stage execution.
                    WorkflowStepListView(trace: trace) // Renders each actual, skipped, or failed stage in order.
                } // Ends the latest-workflow content stack.
                .padding(8) // Matches existing GroupBox internal padding.
            } else { // Provides a useful first-run explanation before Chat has executed a workflow.
                ContentUnavailableView( // Uses a native empty-state component.
                    "No workflow yet", // States the current empty condition.
                    systemImage: "point.3.connected.trianglepath.dotted", // Reuses the sidebar workflow symbol.
                    description: Text("Send a message in Chat to run Fast Router, Director, a specialist, and the configured quality stages.") // Teaches how real data appears here.
                ) // Ends the native empty state.
                .frame(maxWidth: .infinity, minHeight: 190) // Gives the empty state deliberate but restrained space.
            } // Ends empty or populated workflow selection.
        } // Ends the latest workflow container.
    } // Ends latest-workflow section rendering.

    private func workflowHeader(_ trace: WorkflowTrace) -> some View { // Renders concise workflow-level operational metadata.
        HStack(alignment: .top, spacing: 24) { // Arranges metadata in a stable scannable row.
            labeledValue("Intent", trace.intent.rawValue.capitalized) // Shows the deterministic router result.
            labeledValue("Specialist", trace.specialistName) // Shows the Director-selected specialist.
            labeledValue("Model", trace.modelIdentifier, flexible: true) // Shows the exact configured model identifier.
            labeledValue("Total", WorkflowTraceSummaryView.duration(trace.totalDurationMilliseconds)) // Shows measured end-to-end latency.
            Label(trace.status.rawValue.capitalized, systemImage: outcomeSymbol(trace.status)) // Shows overall status with text and icon.
                .font(.callout.weight(.medium)) // Gives operational state clear but restrained emphasis.
                .foregroundStyle(outcomeColor(trace.status)) // Uses semantic state color in addition to the text label.
        } // Ends workflow summary metadata.
    } // Ends workflow header rendering.

    private func labeledValue(_ label: String, _ value: String, flexible: Bool = false) -> some View { // Creates a consistent compact metadata field.
        VStack(alignment: .leading, spacing: 3) { // Groups the field label and value.
            Text(label) // Shows the operational field name.
                .font(.caption) // Keeps the label subordinate.
                .foregroundStyle(.secondary) // Uses native secondary hierarchy.
            Text(value) // Shows the real trace value.
                .font(.callout.weight(.medium)) // Makes the value scannable without a metric-card treatment.
                .lineLimit(1) // Keeps the workflow header compact.
                .truncationMode(.middle) // Preserves useful portions of long model identifiers.
        } // Ends the metadata field stack.
        .frame(maxWidth: flexible ? .infinity : nil, alignment: .leading) // Gives only the model field flexible width.
    } // Ends compact metadata-field rendering.

    private func statusLabel(for agent: AgentDefinition) -> some View { // Shows whether deterministic routing can currently resolve a usable model.
        let available = appState.resolvedModel(for: agent) != nil // Uses production ModelRouter rules instead of server-only state.
        return Label(available ? "Available" : "Unavailable", systemImage: available ? "checkmark.circle.fill" : "exclamationmark.circle") // Communicates model availability with text and symbol.
            .font(.caption.weight(.medium)) // Keeps status compact and scannable.
            .foregroundStyle(available ? Color.green : Color.orange) // Uses semantic state color in addition to explicit text.
    } // Ends agent status rendering.

    private func performanceSummary(for agent: AgentDefinition) -> some View { // Derives lightweight local metrics from the bounded in-memory workflow history.
        let metrics = agentMetrics(for: agent.id) // Computes one immutable recent evidence snapshot for this registry row.
        return VStack(alignment: .leading, spacing: 3) { // Groups local request, result, latency, model, and fallback facts compactly.
            Text("Recent local activity") // Names the telemetry-free session scope explicitly.
                .font(.caption) // Keeps the column heading subordinate.
                .foregroundStyle(.secondary) // Uses native metadata hierarchy.
            if metrics.requests == 0 { // Handles agents not executed in the bounded current-session trace history.
                Text("No requests this session") // Avoids presenting zero as a health or quality judgment.
                    .font(.caption) // Keeps empty evidence compact.
                    .foregroundStyle(.secondary) // Uses neutral styling.
            } else { // Shows actual recorded executions only.
                Text("\(metrics.requests) requests · \(metrics.successes) succeeded · \(metrics.failures) failed") // Reports exact bounded counts.
                    .font(.caption) // Fits the stable desktop column.
                    .lineLimit(1) // Keeps row height predictable.
                Text("Avg \(WorkflowTraceSummaryView.duration(metrics.averageMilliseconds)) · \(metrics.fallbacks) fallback\(metrics.fallbacks == 1 ? "" : "s")") // Reports measured recent duration and explicit fallback frequency.
                    .font(.caption2.monospacedDigit()) // Keeps changing numerical facts stable.
                    .foregroundStyle(.secondary) // Makes detail subordinate.
                if let modelID = metrics.latestModelID { Text(modelID.split(separator: "/").last.map(String.init) ?? modelID).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) } // Shows the most recently selected actual model when known.
            } // Ends empty-versus-recorded metrics.
        } // Ends local performance summary.
        .accessibilityElement(children: .combine) // Reads the complete evidence snapshot coherently.
    } // Ends agent performance summary.

    private func agentMetrics(for agentID: String) -> AgentRecentMetrics { // Aggregates only the last 30 app-owned traces already bounded by AppState.
        let executions = appState.workflowHistory.flatMap(\.modelExecutions).filter { $0.agentID == agentID }.prefix(20) // Limits averaging to the 20 most recent physical attempts for this logical agent.
        let values = Array(executions) // Materializes the bounded slice once for repeated transparent calculations.
        let successes = values.filter { $0.status == .succeeded }.count // Counts actual completed model attempts.
        let failures = values.filter { $0.status == .failed }.count // Counts actual failed model attempts and excludes skipped stages.
        let totalMilliseconds = values.reduce(0) { $0 + $1.totalStageMilliseconds } // Sums measured routing, loading, and inference durations.
        let average = values.isEmpty ? 0 : totalMilliseconds / values.count // Computes an honest integer recent average without presenting invented precision.
        let latestModel = values.first(where: { $0.status == .succeeded })?.selectedModelID ?? values.first?.selectedModelID // Prefers the latest successful physical model while retaining last attempted identity on failure.
        return AgentRecentMetrics(requests: values.count, successes: successes, failures: failures, averageMilliseconds: average, latestModelID: latestModel, fallbacks: values.filter(\.usedFallback).count) // Returns one immutable UI evidence value.
    } // Ends bounded local metric aggregation.

    private func preferredModelBinding(_ agent: AgentDefinition) -> Binding<String?> { // Creates a controlled persisted Picker binding.
        Binding(get: { appState.modelRegistry.assignment(for: agent.id)?.preferredModelID }, set: { appState.setPreferredModel($0, forAgent: agent.id) }) // Reads the separate assignment and delegates mutation to AppState.
    } // Ends preferred-model binding construction.

    private func capabilityText(for agent: AgentDefinition) -> String { // Formats typed capabilities deterministically for the registry UI.
        agent.requiredCapabilities.map(\.displayName).sorted().joined(separator: ", ") // Sorts labels so display order remains stable.
    } // Ends capability formatting.

    private func symbol(for kind: AgentKind) -> String { // Maps agent roles to native semantic symbols.
        switch kind { // Selects a role symbol for the current agent kind.
        case .core: return "arrow.triangle.branch" // Represents orchestration control.
        case .specialist: return "person.crop.circle.badge.checkmark" // Represents a domain specialist.
        case .engineering: return "hammer" // Represents the one bounded agent that coordinates approved workspace tools.
        case .reviewer: return "checkmark.seal" // Represents quality validation.
        case .output: return "text.alignleft" // Represents final response composition.
        } // Ends role-symbol selection.
    } // Ends role-symbol mapping.

    private func outcomeSymbol(_ status: WorkflowOutcomeStatus) -> String { // Maps workflow outcomes to standard semantic symbols.
        switch status { // Selects the symbol for the current overall outcome.
        case .succeeded: return "checkmark.circle.fill" // Marks complete success.
        case .degraded: return "exclamationmark.triangle.fill" // Marks successful fallback recovery.
        case .failed: return "xmark.octagon.fill" // Marks terminal workflow failure.
        } // Ends outcome-symbol selection.
    } // Ends workflow outcome-symbol mapping.

    private func outcomeColor(_ status: WorkflowOutcomeStatus) -> Color { // Maps overall outcomes to restrained semantic colors.
        switch status { // Selects the color for the current overall outcome.
        case .succeeded: return .green // Uses the existing success color.
        case .degraded: return .orange // Uses warning color for recovered execution.
        case .failed: return .red // Uses error color for terminal failure.
        } // Ends outcome-color selection.
    } // Ends workflow outcome-color mapping.
} // Ends the Agents view.

private struct AgentRecentMetrics { // Stores one bounded session-local aggregation without persistence or external telemetry.
    let requests: Int // Counts recent physical execution attempts for the logical agent.
    let successes: Int // Counts attempts whose actual model inference completed successfully.
    let failures: Int // Counts attempts whose model selection, load, or inference failed.
    let averageMilliseconds: Int // Stores measured average recent stage-attempt duration.
    let latestModelID: String? // Stores the latest selected physical model identity when any attempt exists.
    let fallbacks: Int // Counts attempts that used a declared fallback instead of the preferred model.
} // Ends local agent metric value.
