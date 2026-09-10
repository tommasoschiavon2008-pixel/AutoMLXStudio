import Foundation // Supplies UUID identities, checked continuations, and asynchronous UI request streams.

actor EngineeringApprovalBroker: EngineeringApprovalProviding { // Bridges runtime approval requests to a nonblocking application coordinator with default-deny cancellation.
    private struct PendingDecision: Sendable { // Retains the exact request and its sole suspended runtime continuation.
        let request: EngineeringApprovalRequest // Stores immutable command, workspace, reason, and risk evidence for UI presentation.
        let continuation: CheckedContinuation<EngineeringApprovalDecision, Never> // Resumes the exact waiting invocation once and never throws across the protocol boundary.
    } // Ends one pending approval entry.

    private var pendingByID: [UUID: PendingDecision] = [:] // Indexes unresolved decisions by the runtime-generated request identity.
    private var pendingOrder: [UUID] = [] // Preserves deterministic first-request ordering for coordinator snapshots.
    private let requests: AsyncStream<EngineeringApprovalRequest> // Publishes bounded typed requests without blocking the runtime actor or main thread.
    private let requestContinuation: AsyncStream<EngineeringApprovalRequest>.Continuation // Owns the producer side of the application request stream.

    init(maximumBufferedRequests: Int = 32) { // Creates a reusable broker with a finite notification buffer and authoritative pending snapshot.
        var installedContinuation: AsyncStream<EngineeringApprovalRequest>.Continuation? // Temporarily captures the producer installed synchronously by AsyncStream.
        requests = AsyncStream(bufferingPolicy: .bufferingNewest(max(1, maximumBufferedRequests))) { continuation in // Bounds abandoned UI notifications while retaining current state separately.
            installedContinuation = continuation // Captures the stream producer before initialization completes.
        } // Ends request-stream construction.
        guard let installedContinuation else { preconditionFailure("AsyncStream did not install its continuation synchronously.") } // Treats an impossible standard-library contract violation as programmer failure.
        requestContinuation = installedContinuation // Retains the producer for actor-isolated request publication.
    } // Ends broker construction.

    func decision(for request: EngineeringApprovalRequest) async -> EngineeringApprovalDecision { // Suspends one runtime invocation until an exact UI answer or cooperative cancellation.
        guard !Task.isCancelled else { return .deny } // Applies default deny before publishing work for an already-cancelled invocation.
        guard pendingByID[request.id] == nil else { return .deny } // Refuses ambiguous duplicate identities without disturbing the original waiter.
        return await withTaskCancellationHandler(operation: { // Couples runtime timeout or owner cancellation to exact continuation cleanup.
            await waitForDecision(for: request) // Registers and awaits only this typed request.
        }, onCancel: { // Runs when EngineeringToolRuntime cancels its losing approval-race task.
            Task { await self.cancelPendingRequest(id: request.id) } // Removes and safely denies only this exact pending waiter.
        }) // Ends cancellation-aware approval suspension.
    } // Ends approval-provider conformance.

    func pendingRequest() -> EngineeringApprovalRequest? { // Returns the oldest still-unresolved request for simple single-prompt UI coordination.
        compactPendingOrder() // Removes any stale order entries before exposing coordinator state.
        guard let identifier = pendingOrder.first else { return nil } // Reports no prompt after resolution, timeout, or cancellation.
        return pendingByID[identifier]?.request // Returns immutable typed evidence without exposing the continuation.
    } // Ends pending-request snapshot access.

    func requestStream() -> AsyncStream<EngineeringApprovalRequest> { // Returns the reusable nonblocking notification stream for UI or coordinator observation.
        requests // Exposes only immutable typed requests while the actor remains the sole decision owner.
    } // Ends request-stream access.

    @discardableResult func resolve(id: UUID, decision: EngineeringApprovalDecision) -> Bool { // Applies one explicit allow-once or deny answer to one exact request.
        guard let pending = removePending(id: id) else { return false } // Ignores stale, duplicate, timed-out, or foreign UI answers safely.
        pending.continuation.resume(returning: decision) // Resumes the exact runtime waiter once after actor state no longer marks it pending.
        return true // Confirms that this answer owned and resolved a live request.
    } // Ends explicit UI resolution.

    func cancelAll() { // Safely dismisses every pending prompt when a controller, window, or session shuts down.
        let unresolved = pendingOrder.compactMap { pendingByID[$0] } // Captures deterministic live waiters before clearing actor state.
        pendingByID.removeAll(keepingCapacity: false) // Removes all authority-bearing request entries before any continuation resumes.
        pendingOrder.removeAll(keepingCapacity: false) // Clears the presentation order together with the authoritative dictionary.
        for pending in unresolved { // Visits every previously live request exactly once.
            pending.continuation.resume(returning: .deny) // Applies the safe default without granting any external side effect.
        } // Ends bulk default-deny resolution.
    } // Ends broker shutdown cleanup.

    private func waitForDecision(for request: EngineeringApprovalRequest) async -> EngineeringApprovalDecision { // Installs the exact waiter while executing on the broker actor.
        guard !Task.isCancelled else { return .deny } // Closes the race between the public preflight check and actor-isolated registration.
        return await withCheckedContinuation { continuation in // Suspends without blocking a thread until UI, timeout cancellation, or shutdown resolves it.
            guard !Task.isCancelled else { continuation.resume(returning: .deny); return } // Refuses publication if cancellation arrived immediately before registration.
            pendingByID[request.id] = PendingDecision(request: request, continuation: continuation) // Makes the continuation discoverable only under its unguessable runtime identity.
            pendingOrder.append(request.id) // Records stable FIFO order for snapshot consumers.
            requestContinuation.yield(request) // Notifies the UI with typed data after authoritative pending state exists.
        } // Ends exact decision suspension.
    } // Ends actor-isolated waiter registration.

    private func cancelPendingRequest(id: UUID) { // Handles cooperative cancellation for one runtime approval-race task.
        guard let pending = removePending(id: id) else { return } // Ignores cancellation that lost a race to an explicit UI answer.
        pending.continuation.resume(returning: .deny) // Unblocks the cancelled provider task with a safe non-authorizing result.
    } // Ends exact cancellation cleanup.

    private func removePending(id: UUID) -> PendingDecision? { // Atomically removes one request from both authoritative and ordered state.
        guard let pending = pendingByID.removeValue(forKey: id) else { return nil } // Ensures every continuation can be taken at most once.
        pendingOrder.removeAll { $0 == id } // Removes the corresponding presentation identity without affecting other prompts.
        return pending // Transfers sole continuation ownership to the resolving caller.
    } // Ends pending-entry removal.

    private func compactPendingOrder() { // Repairs order metadata defensively without changing any live decision.
        pendingOrder.removeAll { pendingByID[$0] == nil } // Drops identifiers already removed by resolution or cancellation.
    } // Ends order compaction.
} // Ends the cancellation-safe Engineering approval broker.
