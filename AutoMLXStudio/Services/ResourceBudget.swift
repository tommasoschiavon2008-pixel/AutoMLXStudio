import Foundation // Supplies ProcessInfo and value semantics for unified-memory budgeting.

struct ResourceBudget: Codable, Equatable, Sendable { // Describes the host-aware conservative memory envelope available to local model runtimes.
    let physicalMemoryBytes: UInt64 // Stores total physical unified memory reported by macOS.
    let reservedForSystemBytes: UInt64 // Stores the conservative portion never assigned to models.
    let usableForModelsBytes: UInt64 // Stores the remaining model budget after the system reserve.

    static func current(processInfo: ProcessInfo = .processInfo) -> ResourceBudget { // Calculates a budget from the actual host instead of assuming a sixteen-gigabyte machine.
        let physical = processInfo.physicalMemory // Reads the host's physical unified memory from Foundation.
        let fourGiB = UInt64(4) * 1_073_741_824 // Defines the minimum system-and-application reserve in binary bytes.
        let proportionalReserve = physical / 4 // Reserves twenty-five percent on hosts where that is more conservative.
        let desiredReserve = max(fourGiB, proportionalReserve) // Selects the larger conservative reserve.
        let boundedReserve = min(physical, desiredReserve) // Prevents unsigned underflow on unusually constrained environments.
        return ResourceBudget(physicalMemoryBytes: physical, reservedForSystemBytes: boundedReserve, usableForModelsBytes: physical - boundedReserve) // Returns the exact derived budget.
    } // Ends host budget calculation.
} // Ends resource-budget metadata.

struct ResidentModelEstimate: Equatable, Sendable { // Describes the memory-planning facts needed for one resident or requested model.
    let modelID: String // Identifies the physical registry model.
    let resourceClass: ModelResourceClass // Identifies its large-text, large-Vision, audio, embedding, or reranker policy class.
    let estimatedBytes: UInt64 // Stores a conservative registry-derived byte estimate.
} // Ends resident-model estimate metadata.

enum ResidencyDecision: Equatable, Sendable { // Describes the central manager's deterministic reuse, load, unload-switch, or rejection choice.
    case reuse // Reuses the same already-resident physical model.
    case load // Loads the target without unloading another large runtime.
    case switchFrom(String) // Unloads the named large runtime before loading the target.
    case reject(reason: String) // Refuses a target that cannot fit safely even after allowed release.

    var displayName: String { // Produces concise UI and trace copy without exposing internal policy mechanics.
        switch self { // Selects text for the concrete decision.
        case .reuse: return "Reuse" // Labels an already-resident model.
        case .load: return "Load" // Labels a safe additional or initial load.
        case let .switchFrom(modelID): return "Switch from \(modelID)" // Labels the exact required large-runtime release.
        case let .reject(reason): return "Reject: \(reason)" // Labels a bounded safety refusal.
        } // Ends decision label selection.
    } // Ends residency-decision display access.
} // Ends structured residency decisions.

enum ModelResidencyPolicy { // Implements pure deterministic unified-memory rules independently from process control.
    static func decide(target: ResidentModelEstimate, activeLarge: ResidentModelEstimate?, activeSmall: [ResidentModelEstimate], budget: ResourceBudget) -> ResidencyDecision { // Selects reuse, load, switch, or reject from measured and estimated facts.
        if activeLarge?.modelID == target.modelID || activeSmall.contains(where: { $0.modelID == target.modelID }) { return .reuse } // Reuses a target already represented as resident.
        let activeSmallBytes = activeSmall.reduce(UInt64(0)) { partial, model in partial.addingReportingOverflow(model.estimatedBytes).overflow ? UInt64.max : partial + model.estimatedBytes } // Sums small-runtime estimates without unsigned wraparound.
        let targetIsLarge = target.resourceClass == .largeText || target.resourceClass == .largeVision // Applies exclusive residency to both large runtime families.
        if target.estimatedBytes > budget.usableForModelsBytes { // Rejects a target that cannot fit even on an otherwise empty model budget.
            return .reject(reason: "Estimated model memory exceeds the usable host budget.") // Returns a stable safety reason.
        } // Ends single-target fit validation.
        if targetIsLarge { // Handles mutually exclusive large text and Vision resources.
            if let activeLarge { return .switchFrom(activeLarge.modelID) } // Requires verified release before loading a different large target.
            let combined = activeSmallBytes.addingReportingOverflow(target.estimatedBytes) // Calculates large-plus-small coexistence safely.
            if combined.overflow || combined.partialValue > budget.usableForModelsBytes { return .reject(reason: "Existing small runtimes leave insufficient memory for the large model.") } // Refuses unsafe coexistence instead of silently overcommitting.
            return .load // Allows an initial large load when existing small runtimes still fit.
        } // Ends large-runtime policy.
        let activeLargeBytes = activeLarge?.estimatedBytes ?? 0 // Resolves the current exclusive runtime estimate when present.
        let withSmall = activeSmallBytes.addingReportingOverflow(target.estimatedBytes) // Adds the requested small runtime safely.
        let combined = withSmall.partialValue.addingReportingOverflow(activeLargeBytes) // Adds any resident large runtime safely.
        if !withSmall.overflow, !combined.overflow, combined.partialValue <= budget.usableForModelsBytes { return .load } // Permits small-resource coexistence only within the conservative budget.
        if let activeLarge { // Attempts a safe switch only when releasing the large runtime makes the small target fit.
            if !withSmall.overflow, withSmall.partialValue <= budget.usableForModelsBytes { return .switchFrom(activeLarge.modelID) } // Requires unloading the exact large runtime before the small load.
        } // Ends conditional large-runtime release.
        return .reject(reason: "Estimated resident model memory exceeds the usable host budget.") // Refuses unsafe small-runtime overlap.
    } // Ends deterministic residency choice.
} // Ends pure residency policy.
