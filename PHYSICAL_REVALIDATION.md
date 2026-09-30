# V0.6.0.1 physical Windows revalidation

Status: **PENDING — Windows is offline and was not contacted on 11 September 2026.**

This run intentionally validates software readiness only. The historical evidence in `Validation/V06PhysicalWindows-20260910/` is preserved unchanged. When the Windows host is available, revalidate only the V0.6.0.1 delta: ordinary Chat UI remote routing and the permanent Engineering fixture.

The fixture-local short form is `Validation/Fixtures/RemoteEngineering/PHYSICAL_REVALIDATION.md`.

## Known prior environment

The last physical run observed the following environment. These values are operational inputs for the revalidation session, not constants in application source code:

```sh
export AUTOMLX_WINDOWS_HOST=192.168.1.20
export AUTOMLX_WINDOWS_PORT=1234
export AUTOMLX_WINDOWS_BASE_PATH=/v1
export AUTOMLX_WINDOWS_MODEL='qwen/qwen3-4b-2507'
```

Confirm the address and model in the Windows server before use; DHCP or the loaded model may have changed. Configure the endpoint through Remote Models and select the discovered model in Chat. If bearer authentication is enabled, enter the token through the app so it remains in Keychain—never place it in this file, an environment variable, source, screenshots, or logs.

## Fast delta procedure

1. Start the user-managed OpenAI-compatible server on Windows and restrict it to the trusted private LAN.
2. On the Mac, open Remote Models, confirm the existing non-secret profile or enter host, port, scheme, and base path from the environment above, then run Connection Test and Refresh Models.
3. In ordinary Chat, select the Windows server section and `$AUTOMLX_WINDOWS_MODEL`. Send `Reply with exactly: AUTOMLX_CHAT_WINDOWS_OK` and record the visible remote identity, complete response, duration, and usage when the provider reports it.
4. Send two additional turns in the same Chat: `Remember the code word cedar.` then `What code word did I ask you to remember?` Confirm the answer is `cedar` and the request is not duplicated.
5. Start a deliberately long ordinary Chat response, press Stop, confirm the spinner terminates promptly, prior history remains, the model selection remains remote, and a later short request succeeds.
6. Switch Chat to a local installed text model and send a short request; switch back to the remote model and confirm the same conversation history remains while each new response uses the newly selected backend.
7. Exercise one controlled remote error at a time—offline/refused connection, timeout, HTTP 500 if the server offers a safe test mode, malformed response through a disposable proxy if available, missing model, disabled server, removed server, and unavailable credential. Confirm no crash, indefinite spinner, history loss, or silent target substitution.
8. Copy `Validation/Fixtures/RemoteEngineering/` to a disposable working directory on the Mac. Do not repair the permanent baseline fixture itself. Confirm `make test` fails in well below one second.
9. Open the disposable copy in Engineering, select the remote Windows model, and request the exact task from the fixture README. Approve the one-line edit and `make test` separately. Confirm the Mac changes `subtotal - fee` to `subtotal + fee`, the real test passes, verification observes the changed file, and Windows never receives filesystem authority.
10. Repeat the Engineering test while denying the edit; confirm the file remains byte-identical and the run terminates as permission denied.

## Safe-command denial note

The prior physical harness denied a safe test request because its validation filter expected the literal command `/usr/bin/make test`, while the model correctly emitted `make test`. This was a harness assertion mismatch, not a runtime policy defect. The production runtime already resolves `make` through its allowlist and requires explicit process approval. Do not weaken the allowlist, containment checks, or approval rules. A new harness should compare the validated executable and arguments semantically.

## Acceptance record

| Delta check | Required observation | Status |
|---|---|---|
| Ordinary Chat remote selection | Grouped server/model selection remains selected | PENDING |
| Ordinary Chat response | Exact remote target produces visible text | PENDING |
| Multi-turn | System plus user/assistant/user context is coherent and not duplicated | PENDING |
| Stop and recovery | In-flight remote Chat cancels; next request succeeds | PENDING |
| Backend switch | Local/remote switch keeps history; next turn uses the new target | PENDING |
| Error states | No crash, stuck spinner, history loss, selection loss, or silent fallback | PENDING |
| Engineering fixture | Exact one-line repair, approved test, and post-edit verification pass | PENDING |
| Denial/locality | Denied edit is unchanged; all file/process work remains on Mac | PENDING |

Do not mark these rows PASS from deterministic tests or from the 10 September backend harness. They require a new physical Windows session through the V0.6.0.1 UI and fixture.
