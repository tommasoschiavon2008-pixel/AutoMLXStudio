import Darwin // Supplies the read-only proc_pidinfo API for one explicitly tracked process identifier.
import Foundation // Supplies Date and ProcessInfo for operational memory snapshots.

struct ModelMemorySnapshot: Codable, Equatable, Sendable { // Captures bounded operational memory facts at one transition instant.
    let sampledAt: Date // Records when the snapshot was collected for trace ordering.
    let totalPhysicalBytes: UInt64 // Records host physical memory reported by the operating system.
    let trackedProcessID: Int32? // Records only the process identifier explicitly supplied by Project 5 ownership code.
    let trackedProcessResidentBytes: UInt64? // Records current resident memory when macOS permits inspection of the tracked process.
    let trackedProcessVirtualBytes: UInt64? // Records current virtual address-space size when macOS permits inspection of the tracked process.
    let trackedProcessThreadCount: Int? // Records current thread count as a lightweight process-liveness diagnostic.

    var trackedProcessWasSampled: Bool { // Distinguishes a successful zero-byte sample from unavailable process metadata.
        trackedProcessResidentBytes != nil // Uses resident memory availability as the authoritative process-sample signal.
    } // Ends tracked-process sample availability access.
} // Ends operational model memory snapshot metadata.

struct ModelMemorySampler: Sendable { // Reads memory metadata without starting commands, enumerating processes, or mutating process state.
    func snapshot(trackedProcessID: Int32? = nil, sampledAt: Date = Date()) -> ModelMemorySnapshot { // Samples the host and at most one caller-owned process.
        let processMemory = trackedProcessID.flatMap { processID in processID > 0 ? readProcessMemory(processID: processID) : nil } // Rejects invalid identifiers and inspects only the explicit tracked PID.
        return ModelMemorySnapshot( // Builds one immutable transition-ready snapshot.
            sampledAt: sampledAt, // Preserves the caller-provided or current sample timestamp.
            totalPhysicalBytes: ProcessInfo.processInfo.physicalMemory, // Reads total physical memory through the safe Foundation system API.
            trackedProcessID: trackedProcessID, // Records the exact requested PID even when it has already exited.
            trackedProcessResidentBytes: processMemory?.residentBytes, // Stores resident bytes only when proc_pidinfo succeeded.
            trackedProcessVirtualBytes: processMemory?.virtualBytes, // Stores virtual bytes only when proc_pidinfo succeeded.
            trackedProcessThreadCount: processMemory?.threadCount // Stores thread count only when proc_pidinfo succeeded.
        ) // Ends memory snapshot construction.
    } // Ends bounded operational memory sampling.

    private func readProcessMemory(processID: Int32) -> TrackedProcessMemory? { // Reads task information for one Project 5-owned PID without enumerating unrelated processes.
        var taskInfo = proc_taskinfo() // Allocates the fixed macOS task-information result structure.
        let expectedSize = MemoryLayout<proc_taskinfo>.stride // Calculates the exact buffer size expected by PROC_PIDTASKINFO.
        let receivedSize = proc_pidinfo(processID, PROC_PIDTASKINFO, 0, &taskInfo, Int32(expectedSize)) // Requests read-only task metadata for the explicit PID.
        guard receivedSize == Int32(expectedSize) else { return nil } // Treats exited, inaccessible, or invalid processes as an unavailable sample.
        return TrackedProcessMemory(residentBytes: taskInfo.pti_resident_size, virtualBytes: taskInfo.pti_virtual_size, threadCount: Int(taskInfo.pti_threadnum)) // Returns only operational memory and liveness fields.
    } // Ends tracked-process task metadata sampling.
} // Ends the safe model memory sampler.

private struct TrackedProcessMemory: Sendable { // Keeps raw proc_pidinfo results private to the sampler implementation.
    let residentBytes: UInt64 // Stores resident memory bytes returned by macOS.
    let virtualBytes: UInt64 // Stores virtual address-space bytes returned by macOS.
    let threadCount: Int // Stores the process thread count returned by macOS.
} // Ends the private tracked-process memory value.
