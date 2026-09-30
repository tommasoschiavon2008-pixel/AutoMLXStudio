# V0.6.1.1 Engineering security closure — 2026-09-30

## Result

**PASS for the tested V0.6.1.1 workspace/command boundary.** The post-fix production Engineering runtime runs approved commands and their ordinary descendants inside a deny-default macOS Seatbelt profile. The preserved pre-fix `make boundary-probe` no longer returns the outside-only marker, while `make inside-probe` succeeds. Direct file reads and writes use descriptor-relative, no-follow traversal to resist path-validation/symlink-replacement races. No reproducible containment escape remained in the executed probes.

This is **not** a claim of complete macOS security certification or of an end-to-end post-fix SwiftUI approval-sheet test. The post-fix physical probe used the actual signed-app XCTest host, production runtime, real `make`, the preserved fixture and a one-shot approval provider; native UI automation was unavailable. Process-tree cleanup was verified for same-process-group child, grandchild and background-child cases, not for a deliberately daemonized `setsid` descendant. See `SECURITY-MODEL.md` for the trust boundary.

## Evidence

| Gate | Evidence | Result |
| --- | --- | --- |
| Original pre-fix failure | `ROOT-CAUSE.md`, preserved fixture and `PRE-FIX-STATE.md` | Approved Makefile read sibling marker before fix |
| Descriptor TOCTOU regression | `ConcurrentRaceTargeted.log` | 11 containment tests, 0 failures; deterministic replacement and concurrent atomic directory/symlink swaps included |
| Existing Engineering / containment regression | `FullRegressionFinalCurrent.log` | 242 tests, 7 skipped, 0 failures |
| Physical post-fix boundary | `PhysicalPostFixCurrent.log` | Preserved `make inside-probe` succeeded; `make boundary-probe` denied; marker not returned or changed; 1 test passed |
| Debug arm64 | `FullRegressionFinalCurrent.log` and signed Debug product | Test/build succeeded; arm64 slice; code signature verified |
| Release arm64 | `ReleaseArm64OnlyCurrent.log` and signed Release product | Build succeeded; arm64 slice only; code signature verified |
| Release Universal | `UniversalCurrent.log` and signed Release product | Build succeeded; arm64 and x86_64 slices; code signature verified |

The earlier 238-test pre-TOCTOU run was **not** reused as final evidence. The 242-test suite ran after the descriptor change and the concurrent race test was added. The physical probe and release builds used the current application source; the last source edit after those builds added only a test case.

## Implemented boundary

- `EngineeringCommandSandbox` constructs a per-workspace deny-default profile, with private runtime storage and narrowly selected root-owned Apple toolchain/system read exceptions. It has no unrestricted launch fallback. Only the outer product sandbox is authoritative; SwiftPM's unsupported nested sandbox is disabled for contained SwiftPM commands.
- `EngineeringOwnedProcess` launches into a dedicated process group atomically, closes unspecified inherited descriptors, terminates the owned group on Stop/timeout and kills same-group background children before reaping the leader.
- `EngineeringSecureFileAccess` opens each parent with `openat(... O_NOFOLLOW ...)`, reads only an opened regular file, and publishes mutations with descriptor-relative `linkat`/`renameat`; rollback uses `unlinkat`.
- The runtime retains explicit Deny/Allow Once behavior. One approval does not become a persistent filesystem grant.
- Tests cover relative and absolute paths, symlink and hard-link attempts, shell/Makefile/grandchild indirection, environment and temporary-directory tricks, `/var` aliases, outside writes, real SwiftPM build/test, Stop, timeout, background children, fail-closed setup and direct-tool races.

## Final source/security audit

The repository has no `.git` metadata, so a normal `git diff`/status cannot be produced. Existing source was not reset or discarded. Current changed files were reviewed against `PreFixSources`; the new code adds containment rather than broad filesystem exceptions. Write authority is limited to the selected canonical workspace and private runtime. Read-only platform exceptions are specific to system and verified developer-toolchain paths; arbitrary home, sibling, `/usr/local`, global `/tmp`, and `/System/Volumes/Data` are not granted. No command approval bypass or unsandboxed fallback was found in the reviewed execution path.

## Residual limitations

- `/usr/bin/sandbox-exec` is a deprecated/undocumented platform interface. If it disappears or setup fails, execution currently fails closed; a supported App-Sandboxed helper would be the long-term replacement.
- A deliberately detached new session/process group was not included in the process-lifecycle acceptance tests. The inherited filesystem sandbox still applies to its descendants, but exact emergency termination of such a daemonized process is not established by these tests.
- Post-fix approval-sheet interaction was not physically exercised through the app UI in this validation run. The signed-app XCTest path exercised the same production approval/runtime boundary.
- Repository-level commit/push evidence is unavailable because this operational copy contains no Git repository.
