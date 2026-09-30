# Windows remote readiness

## V0.6.0.1 update — 11 September 2026

Ordinary Chat now uses the shared backend dispatcher for both local and remote text, persists the exact backend/server/model choice per conversation, prevents target switching during generation, preserves history across backend switches, rejects normal-Chat tool calls without execution, and records truthful duration/usage metadata. Deterministic software validation is documented in `PROJECT6_VALIDATION.md`.

The Windows host was offline during this update. Therefore the previous physical result remains **PARTIAL** and every V0.6.0.1 physical delta remains **PENDING**. Use `PHYSICAL_REVALIDATION.md` for the complete focused checklist and `Validation/Fixtures/RemoteEngineering/PHYSICAL_REVALIDATION.md` beside the permanent fixture; do not infer a physical pass from intercepted HTTP tests.

Software integration is implemented and deterministically tested. **V0.6.0.1 PHYSICALLY VERIFIED: NO — PENDING PHYSICAL VALIDATION.** A prior V0.6 backend/Engineering session produced partial physical evidence on 10 September, but no real Windows host or LAN inference server was available/used for the V0.6.0.1 Chat UI delta.

The Mac continues to own UI, session orchestration, project memory selection, filesystem, tools, approval, and process execution. The Windows machine supplies inference only. LM Studio is one possible OpenAI-compatible server; no provider-specific API is required beyond the supported OpenAI-compatible endpoints and native tool-call contract.

The 10 September physical session already confirmed TCP, `/v1/models`, Remote Models persistence/health/discovery, real backend inference, multi-turn, cancellation, the remote Engineering read/write round-trip, approvals, Stop recovery, and Mac tool locality. At that checkpoint, ordinary Chat UI remote routing and complete fixture verification remained open. V0.6.0.1 closes those items in software; both still require the focused physical delta below before the Windows status can change from PARTIAL/PENDING.

## Prepare a real test

- On Windows, run a user-managed OpenAI-compatible server and a model suitable for coding and native tools. Select the model explicitly in that server.
- Bind it to the intended private interface and port. Restrict the firewall to the trusted Mac/private network. Do not expose an unauthenticated inference endpoint to the public Internet.
- Configure authentication if supported. Enter the bearer token in the Mac app's credential control; it belongs in Keychain, not screenshots, logs, source files, or profile JSON.
- Add the endpoint in Remote Models. For `http://192.168.1.50:1234/v1`, enter host `192.168.1.50`, port `1234`, HTTP, and `/v1` separately. Replace the example address with the actual Windows host.
- Review the LAN HTTP warning. HTTP is cleartext, including selected source context; prefer a trusted private route or TLS where available.
- Use a disposable Mac workspace with a small known bug and independent test. Start with Fast to isolate remote primary inference from local Reviewer/Composer stages.

## Physical acceptance checklist

Record date, Mac/Windows versions, server/version, model identifier, endpoint scheme/port, and sanitized result for each row. Never record a token.

| Check | Required real observation | Status |
|---|---|---|
| Health | Mac receives a compatible API response from the Windows host | PENDING |
| Discovery | `/v1/models` returns the selected Windows model identity | PENDING |
| Generation | A simple text request receives the selected model's answer | PENDING |
| Multi-turn | The next request uses the prior conversation correctly | PENDING |
| Cancellation | Stop ends the Mac-owned inference request promptly; unrelated processes remain running | PENDING |
| Timeout | An unreachable or deliberately delayed test endpoint produces a bounded timeout, without a false success | PENDING |
| Native tools | Windows returns a valid call; the Mac executes it after policy checks | PENDING |
| Correlation | The next Windows request contains the assistant call and its matching Mac tool result | PENDING |
| Full Engineering | Inspect → approve edit → real test → verify completes in the disposable Mac workspace | PENDING |
| Deny | Denying the proposed edit leaves the file unchanged and ends with permission denied | PENDING |
| Locality | File changes/processes occur on the Mac; Windows has no direct filesystem access to that workspace | PENDING |
| Fallback | A controlled remote failure either uses only an explicitly compatible local assignment, visibly, or reports failure | PENDING |

Deterministic URLProtocol tests already cover real request serialization/parsing, discovery, native multi-turn correlation, and Mac tool execution. They deliberately open no network connection, so they cannot validate firewall rules, server-specific model behavior, real latency, or Windows GPU/VRAM capacity.

On a native-tool incompatibility, retain the safe failure trace, verify the server/model's actual tool support, or use the local strict-JSON route. Do not relabel discovery's unknown capabilities as supported to force a pass.
