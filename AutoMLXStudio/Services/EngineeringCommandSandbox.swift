import Darwin // Supplies exact POSIX ownership checks for the selected Apple developer toolchain.
import Foundation // Supplies canonical file URLs, fixed trusted process launch, and sandbox profile construction.

struct EngineeringSandboxedCommand: Sendable { // Carries the sole executable and argument vector permitted to cross the command boundary.
    let executableURL: URL // Points only to the system-owned sandbox launcher.
    let arguments: [String] // Supplies a generated deny-default profile followed by the trusted real executable and original arguments.
    let environment: [String: String] // Supplies the sanitized caller environment plus one verified developer-directory identity.
} // Ends sandboxed launch metadata.

enum EngineeringCommandSandbox { // Builds a fail-closed per-workspace macOS process sandbox for Engineering commands and descendants.
    private static let sandboxExecutableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec") // Pins the macOS Seatbelt launcher without PATH lookup.
    private static let xcodeDeveloperURL = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer", isDirectory: true) // Accepts the standard root-owned Xcode toolchain.
    private static let commandLineToolsURL = URL(fileURLWithPath: "/Library/Developer/CommandLineTools", isDirectory: true) // Accepts the standard root-owned command-line toolchain.

    static func prepare(executableURL: URL, arguments: [String], workspaceRootURL: URL, runtimeDirectoryURL: URL, environment: [String: String]) throws -> EngineeringSandboxedCommand { // Establishes containment before any model-requested command starts.
        guard FileManager.default.isExecutableFile(atPath: sandboxExecutableURL.path) else { throw EngineeringRuntimeError.sandboxUnavailable("macOS process sandbox is unavailable; Engineering command was not run.") } // Never falls back to an unrestricted Process.
        let workspace = try canonicalDirectory(workspaceRootURL) // Revalidates the selected existing workspace immediately before launch.
        let runtime = try canonicalDirectory(runtimeDirectoryURL) // Revalidates the app-owned private HOME/TMPDIR root immediately before launch.
        let developer = try selectedDeveloperDirectory() // Resolves only a root-owned trusted Apple toolchain outside workspace authority.
        let realExecutable = try resolvedExecutable(executableURL, developerDirectoryURL: developer) // Avoids `/usr/bin` xcrun shims that attempt global temporary cache writes.
        let profile = try makeProfile(workspacePath: workspace.path, runtimePath: runtime.path, developerPath: developer.path) // Produces a deny-default policy for this exact canonical authorization.
        var childEnvironment = environment // Starts from the existing non-secret allowlist rather than the host environment.
        childEnvironment["DEVELOPER_DIR"] = developer.path // Prevents toolchain lookup through an inaccessible user preference or global temporary cache.
        let sdkRelativePath = developer.path == xcodeDeveloperURL.path ? "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" : "SDKs/MacOSX.sdk" // Selects only the macOS SDK bundled in the verified developer installation.
        childEnvironment["SDKROOT"] = try canonicalDirectory(developer.appendingPathComponent(sdkRelativePath)).path // Gives SwiftPM an explicit trusted SDK without invoking host-global discovery.
        childEnvironment["PATH"] = "\(developer.appendingPathComponent("Toolchains/XcodeDefault.xctoolchain/usr/bin").path):\(developer.appendingPathComponent("usr/bin").path):\(environment["PATH"] ?? "/usr/bin:/bin")" // Lets SwiftPM find only the verified toolchain's own subcommands before fixed host utilities.
        let isSwiftPackageCommand = executableURL.lastPathComponent == "swift" && ["build", "test", "package", "run"].contains(arguments.first ?? "") // Identifies only SwiftPM commands that otherwise try an unsupported second sandbox_init.
        let nestedSandboxOption = isSwiftPackageCommand && !arguments.contains("--disable-sandbox") ? ["--disable-sandbox"] : [] // Disables only SwiftPM's redundant inner sandbox; the mandatory outer OS boundary remains unchanged.
        let nativeBuildOption = isSwiftPackageCommand && ["build", "test", "run"].contains(arguments.first ?? "") && !arguments.contains(where: { $0.hasPrefix("--build-system") }) ? ["--build-system", "native"] : [] // Uses SwiftPM's in-process build engine, which preserves the private TMPDIR instead of relying on host-global Xcode services.
        let launchArguments = ["-p", profile, "--", realExecutable.path] + arguments + nestedSandboxOption + nativeBuildOption // Preserves user argument boundaries and always places the complete invocation inside the generated sandbox.
        return EngineeringSandboxedCommand(executableURL: sandboxExecutableURL, arguments: launchArguments, environment: childEnvironment) // Exposes no unrestricted launch path.
    } // Ends fail-closed sandbox preparation.

    private static func canonicalDirectory(_ url: URL) throws -> URL { // Obtains a real filesystem identity rather than trusting lexical URL normalization.
        let canonicalPath: String? = url.path.withCString { source in // Bridges the requested path into POSIX canonicalization.
            guard let resolved = Darwin.realpath(source, nil) else { return nil } // Requires the complete existing filesystem path to resolve.
            defer { Darwin.free(resolved) } // Releases only the buffer allocated by realpath.
            return String(cString: resolved) // Captures macOS's authoritative `/private/var` spelling and any symlink targets.
        } // Ends exact POSIX path canonicalization.
        guard let canonicalPath else { throw EngineeringRuntimeError.sandboxUnavailable("A required containment directory cannot be canonicalized; Engineering command was not run.") } // Refuses an unresolved root instead of widening the profile.
        let canonical = URL(fileURLWithPath: canonicalPath, isDirectory: true) // Reconstructs the real existing directory URL.
        var isDirectory: ObjCBool = false // Receives the existing target type without guessing from a trailing slash.
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw EngineeringRuntimeError.sandboxUnavailable("A required containment directory is unavailable; Engineering command was not run.") } // Refuses absent or non-directory authority roots.
        return canonical // Returns the path identity used in all generated Seatbelt rules.
    } // Ends canonical directory validation.

    private static func selectedDeveloperDirectory() throws -> URL { // Reads only the fixed system developer-directory selection.
        let selector = Process() // Creates a trusted helper that receives no model-controlled arguments.
        let pipe = Pipe() // Captures the bounded system selection path.
        selector.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select") // Pins Apple's selector directly.
        selector.arguments = ["-p"] // Requests the active developer root without executing a project tool.
        selector.standardOutput = pipe // Captures only the selected directory.
        selector.standardError = FileHandle.nullDevice // Suppresses unrelated host diagnostics from the model channel.
        do { try selector.run() } catch { throw EngineeringRuntimeError.sandboxUnavailable("Trusted developer toolchain could not be identified; Engineering command was not run.") } // Refuses to continue if the system selection cannot start.
        selector.waitUntilExit() // Waits for the short fixed selector invocation before constructing a profile.
        guard selector.terminationStatus == 0 else { throw EngineeringRuntimeError.sandboxUnavailable("Trusted developer toolchain could not be identified; Engineering command was not run.") } // Refuses an invalid system selection.
        let data = pipe.fileHandleForReading.readDataToEndOfFile() // Reads the single small path line after process exit.
        guard data.count < 4_096, let selected = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !selected.isEmpty else { throw EngineeringRuntimeError.sandboxUnavailable("Trusted developer toolchain path is invalid; Engineering command was not run.") } // Bounds and decodes the selection safely.
        let canonical = try canonicalDirectory(URL(fileURLWithPath: selected, isDirectory: true)) // Resolves the selected developer root before comparison.
        let trustedPaths = [xcodeDeveloperURL, commandLineToolsURL].map { $0.standardizedFileURL.resolvingSymlinksInPath().path } // Lists only the two system locations granted read-only exceptions.
        let readRoot = canonical.path == xcodeDeveloperURL.path ? URL(fileURLWithPath: "/Applications/Xcode.app", isDirectory: true) : canonical // Includes Xcode's root-owned shared frameworks when using its developer directory.
        guard trustedPaths.contains(canonical.path), rootOwns(canonical), rootOwns(readRoot) else { throw EngineeringRuntimeError.sandboxUnavailable("Selected developer toolchain is outside trusted system locations; Engineering command was not run.") } // Refuses arbitrary user-controlled toolchains.
        return canonical // Returns the verified read-only developer path.
    } // Ends trusted toolchain selection.

    private static func rootOwns(_ url: URL) -> Bool { // Prevents a user-writable replacement from becoming a read-only sandbox exception.
        var metadata = stat() // Receives exact filesystem owner identity.
        return url.path.withCString { Darwin.lstat($0, &metadata) == 0 && metadata.st_uid == 0 && metadata.st_mode & 0o022 == 0 } // Requires root ownership and rejects group/world-writable toolchain roots.
    } // Ends toolchain ownership verification.

    private static func resolvedExecutable(_ url: URL, developerDirectoryURL: URL) throws -> URL { // Selects a real trusted tool instead of an Xcode-dispatch shim.
        let name = url.lastPathComponent // Identifies the previously allowlisted executable without accepting an arbitrary new name.
        let relativePath: String? // Stores a fixed path relative to the verified Apple developer directory.
        switch name { // Covers Apple command wrappers that otherwise require unrestricted cache paths.
        case "make", "git", "xcodebuild": relativePath = "usr/bin/\(name)" // Selects actual Xcode or Command Line Tools binaries.
        case "swift": relativePath = developerDirectoryURL.path == xcodeDeveloperURL.path ? "Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" : "usr/bin/swift" // Selects the active toolchain's actual Swift driver.
        default: relativePath = nil // Keeps non-shim allowlisted utilities at their previously validated fixed host path.
        } // Ends fixed toolchain mapping.
        let candidate = relativePath.map { developerDirectoryURL.appendingPathComponent($0).standardizedFileURL } ?? url.standardizedFileURL // Applies only the fixed mapping or the prevalidated executable.
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else { throw EngineeringRuntimeError.sandboxUnavailable("Trusted build executable is unavailable inside the selected toolchain; Engineering command was not run.") } // Fails closed instead of returning to a shim or alternate PATH entry.
        return candidate // Returns the exact binary that runs under Seatbelt.
    } // Ends trusted executable selection.

    static func makeProfile(workspacePath: String, runtimePath: String, developerPath: String) throws -> String { // Produces the same policy used by the real process and regression tests.
        let roots = [workspacePath, runtimePath] // Starts from only the two writable authorization roots.
        let aliases = roots.compactMap { $0.hasPrefix("/private/var/") ? String($0.dropFirst("/private".count)) : nil } // Mirrors macOS's `/var` symlink spelling for the same canonical temporary directories.
        let ancestorPaths = Array(Set((roots + aliases).flatMap(ancestors(of:)))).sorted() // Adds exact parent directories solely for `getcwd` and path traversal metadata.
        let ancestorRules = try ancestorPaths.map { "(literal \(try quoted($0)))" }.joined(separator: " ") // Escapes each exact ancestor as a profile string literal.
        let workspaceRule = "(subpath \(try quoted(workspacePath)))" // Allows recursive access only beneath the canonical selected workspace.
        let runtimeRule = "(subpath \(try quoted(runtimePath)))" // Allows recursive access only beneath the private app runtime.
        let aliasReadRules = try aliases.map { "(subpath \(try quoted($0)))" }.joined(separator: " ") // Allows alternate `/var` spelling of the same exact authorized roots.
        let aliasWriteRules = aliasReadRules // Applies identical write authority to only those same filesystem objects.
        let developerReadRoot = developerPath == xcodeDeveloperURL.path ? "/Applications/Xcode.app" : developerPath // Includes Xcode's own root-owned shared frameworks outside Contents/Developer.
        let developerRule = "(subpath \(try quoted(developerReadRoot)))" // Allows read-only access to the verified Apple toolchain bundle.
        let systemDeveloperReadRule = developerPath == xcodeDeveloperURL.path ? "(subpath \"/Library/Developer/PrivateFrameworks\")" : "(subpath \"/Library/Developer/CommandLineTools\")" // Limits developer-support reads to the selected toolchain or Apple's Xcode private-framework dependencies.
        let readRules = [workspaceRule, runtimeRule, aliasReadRules, developerRule, "(subpath \"/System/Library\")", "(subpath \"/bin\")", "(subpath \"/sbin\")", "(subpath \"/usr/bin\")", "(subpath \"/usr/sbin\")", "(subpath \"/usr/lib\")", "(subpath \"/usr/libexec\")", "(subpath \"/usr/share\")", "(subpath \"/private/etc\")", systemDeveloperReadRule, "(literal \"/dev\")", "(literal \"/dev/null\")", "(literal \"/dev/random\")", "(literal \"/dev/urandom\")", "(literal \"/dev/zero\")", "(subpath \"/dev/fd\")"].joined(separator: " ") // Excludes `/System/Volumes/Data` and arbitrary home, volume, unrelated developer data, `/usr/local`, or device contents.
        return """
        (version 1)
        (deny default)
        (allow process-exec)
        (allow process-fork)
        (allow signal (target same-sandbox))
        (allow process-info* (target self) (target same-sandbox)) ; Let compiler drivers resolve their own executable identity as well as children.
        (allow sysctl-read) ; Let compilers identify the host architecture and OS deployment version without mutation.
        (allow file-read* \(readRules))
        (allow file-read* (literal "/")) ; Permit libc startup's root-directory read without recursive access below root.
        (allow file-read-metadata \(ancestorRules)) ; Resolve workspace ancestors without enumerating their unrelated directory contents.
        (allow file-read-metadata (literal "/Applications") (literal "/Library") (literal "/usr") (literal "/private/var") (literal "/private/var/select")) ; Permit trusted toolchain ancestor resolution without their directory contents.
        (allow file-read* (literal "/private/var/select/sh")) ; Resolve the root-owned system shell selector used by Apple tools.
        (allow file-read* (literal "/Library/Preferences/com.apple.dt.Xcode.plist")) ; Read only Apple's root-owned license acceptance record.
        (allow file-read* (subpath "/Library/Apple/System/Library")) ; Load Apple's relocated system frameworks used by Xcode SDK discovery, not user libraries.
        (allow file-write* \(workspaceRule) \(runtimeRule) \(aliasWriteRules) (literal "/dev/null"))
        (deny system-fcntl (fcntl-command 80 110))
        """ // Ends the generated allowlist; no unsandboxed fallback is ever emitted.
    } // Ends dynamic profile construction.

    private static func ancestors(of path: String) -> [String] { // Lists exact directories from root to—but not including—the writable authority root.
        var cursor = URL(fileURLWithPath: path, isDirectory: true).deletingLastPathComponent() // Begins at the direct parent that `getcwd` may inspect.
        var result: [String] = [] // Collects only exact parent identities, never recursive subpaths.
        while true { // Walks toward the filesystem root in a bounded path-component sequence.
            result.append(cursor.path) // Grants metadata access only to this one ancestor directory.
            if cursor.path == "/" { break } // Stops at the root without underflow.
            cursor = cursor.deletingLastPathComponent() // Advances one level upward.
        } // Ends exact ancestor traversal.
        return result // Returns the finite literal path set.
    } // Ends ancestor enumeration.

    private static func quoted(_ path: String) throws -> String { // Encodes one canonical path safely inside Seatbelt string syntax.
        guard path.hasPrefix("/"), !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw EngineeringRuntimeError.sandboxUnavailable("Containment path cannot be represented safely; Engineering command was not run.") } // Refuses relative or control-character paths before profile compilation.
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") // Escapes profile-string backslashes and quotes without interpreting model text.
        return "\"\(escaped)\"" // Returns one syntactically closed Seatbelt string literal.
    } // Ends profile path quoting.
} // Ends macOS Engineering command sandbox construction.
