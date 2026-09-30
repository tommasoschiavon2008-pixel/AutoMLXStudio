import Darwin // Supplies descriptor-relative filesystem operations that never follow racing path-component symlinks.
import Foundation // Supplies bounded data, file handles, and canonical URL values.

struct EngineeringSecureFileAccess { // Anchors each content operation to directory descriptors inside the authorized root.
    let rootURL: URL // Retains the workspace authority already canonicalized by EngineeringWorkspace.

    func openFile(_ url: URL) throws -> FileHandle { // Opens existing source bytes without a check-then-follow symlink race.
        try withParent(of: url) { parent, name in // Resolves every parent through O_NOFOLLOW descriptors.
            let descriptor = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) // Rejects a final symlink and prevents a FIFO from blocking the app.
            guard descriptor >= 0 else { throw failure() } // Returns a typed filesystem refusal before reading any bytes.
            var metadata = stat() // Receives the actual opened object's metadata rather than a second path lookup.
            guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else { close(descriptor); throw EngineeringRuntimeError.notAFile(url.lastPathComponent) } // Accepts only a regular file and closes every rejected descriptor.
            return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true) // Transfers the exact contained file descriptor to the bounded reader.
        } // Ends descriptor-anchored source opening.
    } // Ends safe source reading setup.

    func read(_ url: URL, maximumBytes: Int) throws -> Data { // Captures mutation preimages without unbounded reads or path races.
        let handle = try openFile(url) // Opens only an actual contained regular file.
        defer { try? handle.close() } // Releases the owned file descriptor on every path.
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data() // Reads one extra byte to detect a size race or oversized file.
        guard data.count <= maximumBytes else { throw EngineeringRuntimeError.outputLimitExceeded(maximumBytes) } // Refuses oversized rollback state instead of consuming arbitrary memory.
        return data // Returns only the validated bounded bytes.
    } // Ends safe mutation-preimage reading.

    func write(_ data: Data, to url: URL, createOnly: Bool, createParents: Bool = false) throws { // Publishes new bytes relative to an anchored parent descriptor.
        try withParent(of: url, createParents: createParents) { parent, name in // Holds the actual parent throughout staging and publication.
            let staging = ".automlx-\(UUID().uuidString).tmp" // Chooses an unguessable single-component staging name.
            let descriptor = openat(parent, staging, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) // Creates a fresh contained regular staging file without following an attacker-created link.
            guard descriptor >= 0 else { throw failure() } // Stops without destination changes when staging fails.
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true) // Owns the staging descriptor independently of path lookup.
            defer { try? handle.close(); unlinkat(parent, staging, 0) } // Cleans up only this exact staging name inside the anchored parent.
            try handle.write(contentsOf: data) // Writes bounded validated authored bytes to the already-open staging inode.
            try handle.synchronize() // Flushes staged bytes before publishing the new directory entry.
            let result = createOnly ? linkat(parent, staging, parent, name, 0) : renameat(parent, staging, parent, name) // Atomically creates without overwrite or replaces the directory entry itself, never a symlink target.
            guard result == 0 else { if errno == EEXIST { throw EngineeringRuntimeError.fileAlreadyExists(name) }; throw failure() } // Preserves racing existing targets and surfaces other publication failures.
        } // Ends anchored atomic publication.
    } // Ends safe text mutation.

    func remove(_ url: URL) throws { // Removes only the directory entry owned by a validated rollback.
        try withParent(of: url) { parent, name in // Anchors the rollback parent against symlink replacement.
            guard unlinkat(parent, name, 0) == 0 else { throw failure() } // Unlinks a single non-directory entry without following its target.
        } // Ends exact anchored removal.
    } // Ends safe created-file rollback.

    private func withParent<T>(of url: URL, createParents: Bool = false, operation: (Int32, String) throws -> T) throws -> T { // Replaces mutable string-path traversal with owned directory descriptors.
        let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/" // Uses a separator-aware boundary rather than a sibling-prefix match.
        guard url.path.hasPrefix(prefix) else { throw EngineeringRuntimeError.sandboxUnavailable("Filesystem target is outside the authorized workspace.") } // Refuses an uncontained canonical target independently of upstream validation.
        let components = String(url.path.dropFirst(prefix.count)).split(separator: "/").map(String.init) // Derives only the already-contained relative components.
        guard let name = components.last, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw EngineeringRuntimeError.sandboxUnavailable("Invalid descriptor-relative filesystem target.") } // Refuses root, empty, or traversal targets before opening a descriptor.
        var parent = open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) // Anchors authority to the selected actual directory and rejects a replaced root symlink.
        guard parent >= 0 else { throw failure() } // Fails closed if the authorized root cannot be opened safely.
        defer { close(parent) } // Releases the last owned parent on every return or thrown error.
        for component in components.dropLast() { // Walks only validated path components, never a combined path that could follow intermediate symlinks.
            if createParents, mkdirat(parent, component, 0o755) != 0, errno != EEXIST { throw failure() } // Creates optional parents only below the currently anchored directory.
            let next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) // Rejects any parent replaced with an outside-pointing symlink after canonicalization.
            guard next >= 0 else { throw failure() } // Refuses the race rather than following it outside the authority.
            close(parent) // Releases the previous descriptor only after securing its contained child.
            parent = next // Advances ownership to the verified real child directory.
        } // Ends no-follow descriptor traversal.
        return try operation(parent, name) // Performs the complete content operation while parent authority remains pinned.
    } // Ends descriptor-relative parent resolution.

    private func failure() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) } // Captures the immediate POSIX failure without exposing file content.
} // Ends direct-tool filesystem race protection.
