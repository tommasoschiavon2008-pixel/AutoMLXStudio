import SwiftUI // Supplies native macOS views for reusable workflow metadata.

struct WorkflowTraceSummaryView: View { // Renders one compact real-workflow metadata line for Chat.
    let trace: WorkflowTrace // Accepts the trace linked to the assistant response.

    var body: some View { // Defines the compact specialist, model, and duration presentation.
        HStack(spacing: 5) { // Keeps metadata visually subordinate to the answer.
            Text(trace.specialistName) // Shows the actual specialist selected by Director.
                .fontWeight(.medium) // Gives the most useful metadata item modest emphasis.
            Text("·") // Separates metadata fields without adding decorative controls.
                .foregroundStyle(.tertiary) // Keeps the separator unobtrusive.
            Text(shortModelIdentifier) // Shows the assigned model without repeating a long repository prefix.
                .lineLimit(1) // Keeps the chat line compact.
                .truncationMode(.middle) // Preserves useful beginning and ending identifier segments.
            Text("·") // Separates model identity from elapsed duration.
                .foregroundStyle(.tertiary) // Keeps the separator unobtrusive.
            Text(Self.duration(trace.totalDurationMilliseconds)) // Shows actual end-to-end workflow latency.
                .monospacedDigit() // Prevents timing text from shifting visually.
            if trace.status != .succeeded { // Adds non-color status communication only for recovered or failed workflows.
                Image(systemName: trace.status == .degraded ? "exclamationmark.triangle.fill" : "xmark.octagon.fill") // Selects a semantic recovery or failure symbol.
                    .foregroundStyle(trace.status == .degraded ? .orange : .red) // Reinforces the textual accessibility label with a standard state color.
                    .accessibilityLabel(trace.status.rawValue.capitalized) // Exposes status meaning to assistive technology.
            } // Ends exceptional workflow status display.
        } // Ends the compact metadata row.
        .font(.caption) // Keeps trace metadata subordinate to message content.
        .foregroundStyle(.secondary) // Uses the existing restrained macOS text hierarchy.
    } // Ends the compact summary body.

    private var shortModelIdentifier: String { // Derives a useful short model label for compact contexts.
        trace.modelIdentifier.split(separator: "/").last.map(String.init) ?? trace.modelIdentifier // Keeps the final repository component or local model name.
    } // Ends short model-label derivation.

    static func duration(_ milliseconds: Int) -> String { // Formats measured trace durations consistently across both views.
        if milliseconds < 1_000 { return "\(milliseconds) ms" } // Keeps subsecond workflow timings precise.
        return String(format: "%.1f s", Double(milliseconds) / 1_000) // Converts longer durations into concise seconds.
    } // Ends workflow-duration formatting.
} // Ends the compact workflow summary component.

struct WorkflowStepListView: View { // Renders actual workflow stages as a native vertical trace.
    let trace: WorkflowTrace // Accepts the complete workflow trace.
    var showsDetail = true // Controls whether a surface needs operational stage descriptions.

    var body: some View { // Defines the ordered stage list.
        VStack(alignment: .leading, spacing: 0) { // Preserves the execution order with compact vertical rhythm.
            ForEach(Array(trace.steps.enumerated()), id: \.element.id) { index, step in // Iterates over actual and skipped stages with positional context.
                stepRow(step) // Renders the current operational stage.
                if index < trace.steps.count - 1 { // Adds a connector only between adjacent stages.
                    Image(systemName: "arrow.down") // Communicates pipeline order using a native symbol.
                        .font(.caption2) // Keeps the connector visually quiet.
                        .foregroundStyle(.tertiary) // Prevents the connector from competing with stage state.
                        .frame(width: 20) // Aligns the connector beneath stage status icons.
                        .padding(.vertical, 3) // Separates stage rows without excessive whitespace.
                        .accessibilityHidden(true) // Avoids redundant narration because list order is already semantic.
                } // Ends inter-stage connector display.
            } // Ends workflow stage iteration.
            if showsDetail, let memory = trace.memory { // Adds a transparent retrieval inspector only on roomier advanced trace surfaces.
                Divider() // Separates execution stages from bounded Project Memory diagnostics.
                    .padding(.vertical, 8) // Gives the inspector a clear structural boundary.
                VStack(alignment: .leading, spacing: 5) { // Groups non-sensitive query, strategy, selection, and context facts.
                    Label("Project Memory", systemImage: "text.magnifyingglass") // Names the service-level retrieval inspector explicitly.
                        .font(.callout.weight(.semibold)) // Gives the advanced subsection modest hierarchy.
                    LabeledContent("Decision", value: memory.decision) // Shows the deterministic memory router outcome.
                    if let query = memory.query { LabeledContent("Query", value: query) } // Shows only the bounded visible retrieval query when search executed.
                    if let strategy = memory.strategy { LabeledContent("Strategy", value: strategy.displayName) } // Shows lexical, vector, hybrid, reranked, or fallback mode actually used.
                    LabeledContent("Candidates", value: memory.candidateCount.formatted()) // Shows actual candidates considered before context assembly.
                    LabeledContent("Selected chunks", value: memory.selectedChunkIDs.count.formatted()) // Shows exact selected identity count rather than every discarded retrieval.
                    LabeledContent("Injected context", value: "\(memory.injectedCharacterCount.formatted()) characters") // Shows the actual bounded rendered character contribution.
                    LabeledContent("Retrieval time", value: WorkflowTraceSummaryView.duration(memory.durationMilliseconds)) // Shows measured memory decision, retrieval, and assembly latency.
                    if let reason = memory.fallbackReason { Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } // Shows bounded runtime or no-result evidence without a traceback.
                    if !memory.selectedChunkIDs.isEmpty { Text("Chunk IDs: \(memory.selectedChunkIDs.map { String($0.uuidString.prefix(8)) }.joined(separator: ", "))").font(.caption2.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled) } // Exposes short exact identities for citation debugging without source contents.
                } // Ends retrieval inspector content.
                .font(.caption) // Keeps advanced evidence subordinate to user-facing workflow stages.
                .accessibilityElement(children: .contain) // Preserves individual labeled facts for inspection.
            } // Ends optional Project Memory inspector.
        } // Ends the ordered workflow stack.
    } // Ends the workflow list body.

    private func stepRow(_ step: WorkflowStep) -> some View { // Renders one operational stage with state and timing.
        HStack(alignment: .top, spacing: 10) { // Aligns state, stage detail, and measured duration.
            Image(systemName: statusSymbol(for: step.status)) // Shows a non-color semantic state indicator.
                .foregroundStyle(statusColor(for: step.status)) // Applies the standard success, skip, or failure color.
                .frame(width: 20) // Aligns every stage label consistently.
                .accessibilityLabel(step.status.rawValue.capitalized) // Announces state to assistive technology.
            VStack(alignment: .leading, spacing: 2) { // Groups stage name and optional operational detail.
                HStack(spacing: 6) { // Keeps the concrete stage and its typed operational category together.
                    Text(step.name) // Shows the actual stage or selected agent name.
                        .font(.callout.weight(.medium)) // Establishes clear hierarchy without oversized text.
                    Text(step.stage.kind.displayName) // Shows whether this is routing, validation, resource work, an agent, a service, or output.
                        .font(.caption2.weight(.medium)) // Keeps the category subordinate to the concrete stage.
                        .foregroundStyle(.secondary) // Uses neutral hierarchy instead of decorative category colors.
                        .padding(.horizontal, 5) // Creates a compact native metadata tag.
                        .padding(.vertical, 1) // Keeps the tag height restrained.
                        .background(.quaternary) // Separates the category from the stage name in both appearances.
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous)) // Uses restrained geometry consistent with metadata badges.
                } // Ends stage identity and category row.
                if showsDetail { // Adds operational metadata only where the surface has room.
                    Text(step.detail) // Explains success, skip, or failure without exposing model reasoning.
                        .font(.caption) // Keeps detail subordinate to the stage name.
                        .foregroundStyle(.secondary) // Uses the native secondary text hierarchy.
                        .fixedSize(horizontal: false, vertical: true) // Allows long error recovery text to wrap safely.
                } // Ends optional operational detail display.
            } // Ends stage label grouping.
            Spacer(minLength: 16) // Pushes timing into a stable trailing column.
            Text(step.status == .skipped ? "Skipped" : WorkflowTraceSummaryView.duration(step.durationMilliseconds)) // Shows either policy state or measured latency.
                .font(.caption.monospacedDigit()) // Keeps operational values compact and aligned.
                .foregroundStyle(.secondary) // Keeps timing subordinate to stage identity.
        } // Ends the workflow stage row.
        .accessibilityElement(children: .combine) // Presents each stage as one concise accessible unit.
    } // Ends workflow stage row rendering.

    private func statusSymbol(for status: WorkflowStepStatus) -> String { // Maps step outcomes to standard macOS symbols.
        switch status { // Selects a symbol for the current step state.
        case .succeeded: return "checkmark.circle.fill" // Marks successful execution.
        case .skipped: return "forward.end.circle" // Marks intentional policy or recovery skipping.
        case .failed: return "exclamationmark.triangle.fill" // Marks a recoverable or terminal failure.
        } // Ends status-symbol selection.
    } // Ends status-symbol mapping.

    private func statusColor(for status: WorkflowStepStatus) -> Color { // Maps step outcomes to restrained semantic colors.
        switch status { // Selects a color for the current step state.
        case .succeeded: return .green // Uses the existing app success color.
        case .skipped: return .secondary // Keeps intentional skips visually neutral.
        case .failed: return .orange // Signals an operational issue without overstating recovered failures.
        } // Ends status-color selection.
    } // Ends status-color mapping.
} // Ends the shared workflow stage list.
