# Engineering usage and safety

## Start a session

1. Open **Engineering** in the sidebar and choose **Open Workspace**. Authorize only the directory the agent may inspect or change.
2. Enter the requested change and expected verification. Choose Fast (8 turns), Balanced (16, with Reviewer), or Thorough (30, with Reviewer and Composer).
3. Optionally enable Project Memory and select its exact project. Memory retrieval does not authorize editing that project's directory.
4. Select Local, or configure and discover a server under **Remote Models**, then select its server/model in Engineering. The remote model receives selected context and tool results. Compatible configured local fallback may run if remote inference fails.
5. Run. Inspect live model attempts and tool activity. Each interactive edit/build requires **Allow Once** or **Deny**. External side-effect commands always require approval.
6. Read completion and verification separately. Review app-owned changes and their diff. A rollback is separately confirmed and refuses to overwrite a file changed since the recorded operation.

The native page scrolls at the minimum window size. Approval previews have bounded scrolling so the decision buttons remain reachable. Keyboard Run is Command-Return; Open Workspace is Command-Shift-O; Escape denies an approval.

## Approval contract

The production builder enables per-operation workspace-mutation approval. Lower-level runtime consumers retain the previous explicitly preauthorized workspace policy unless they enable this option; the mandatory external-side-effect default-deny rule is unchanged.

Read-only typed operations need no separate approval. A proposed edit shows its tool, workspace, relative path, optimistic original hash where applicable, bounded content preview, and complete proposed-content SHA-256. Truncated previews are labeled. A process shows its separate executable/arguments and reason. Decisions apply only to the exact pending request ID, not future actions. A blocked operation cannot be promoted by approval.

Stop cancels the exact session, inference request, approval wait, and owned process. It does not terminate unrelated processes and does not automatically roll back completed changes. A late Allow Once cannot resurrect a cancelled request. Missing/dismissed authority and approval timeout never become permission.

## Filesystem boundary

The production workspace validates canonical paths, traversal, sensitive/hidden paths, and symlink containment. Reads/searches/output are bounded. Edits use optimistic SHA-256 preconditions and tracked atomic writes. Listing omits outside symlink entries rather than failing safe siblings. Rollback is Git-independent and conflict-preserving. The controller does not change workspace authority while a run is active.

## Process boundary and residual risk

Commands use an allowlisted executable with separate arguments, contained working directory, finite deadline, bounded output, sanitized environment, and isolated runtime HOME/TMP. Raw shells, sudo, destructive utilities, history rewriting, and obvious outside paths are blocked before approval. Only exact child processes owned by this runtime may be cancelled.

This is **not an operating-system sandbox**. Approved build/test tools may execute project scripts, compiler plugins, or dependencies that themselves access the filesystem or network. Workspace path checks constrain direct tools and arguments; they do not prove arbitrary build scripts safe. Use trusted projects, review scripts and approvals, and prefer an isolated checkout for untrusted code. A real test process exit is evidence of that command, not proof that its test coverage is adequate.

## Evidence and limits

The engine enforces 8/16/30 primary turns, a bounded argument-repair opportunity, at most four native calls per model turn, bounded history, and repeated-action detection. Reviewer/Composer have no tools. Their failure is visible and does not silently invalidate the best primary candidate.

Verification comes only from concrete build/test tool outcomes, never model prose. A later tracked mutation invalidates checks on older bytes. A later failed check prevents the final status from appearing verified. Earlier operational events remain available. Cancellation/failure preserves completed transaction evidence and yields an honest partial result.

Credentials remain behind the Keychain token vault; profile JSON excludes tokens. Error/activity rendering applies bounded secret redaction. HTTP on a non-loopback endpoint shows a cleartext warning: it does not encrypt traffic. Use a trusted LAN/private overlay or TLS endpoint and do not expose an unauthenticated server publicly.

## Known limitations

- No physically verified Windows endpoint in this validation session.
- Physical local MLX/ASR/TTS/multi-model tests remain opt-in; Vision's missing shards are not repaired or downloaded here.
- Remote streaming and Ollama-native transport are not implemented in this milestone.
- Unknown discovered capability is not equivalent to confirmed native-tool compatibility.
- Build/test command scope is user-selected and may be incomplete; no test-coverage guarantee is implied.
- In-memory conversation/session state survives navigation, not application restart.
