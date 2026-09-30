# Remote Engineering physical revalidation

Status: **PENDING.** Run this only when the physical Windows host is available. Work on a disposable copy of this fixture; keep this baseline intentionally failing.

The values below describe the previous test environment. They are not application constants. Confirm the current Windows address and loaded model before use.

```sh
export AUTOMLX_WINDOWS_HOST=192.168.1.20
export AUTOMLX_WINDOWS_PORT=1234
export AUTOMLX_WINDOWS_BASE_PATH=/v1
export AUTOMLX_WINDOWS_MODEL='qwen/qwen3-4b-2507'
```

1. Start Windows, LM Studio (or the intended OpenAI-compatible server), the model above, and private-LAN serving.
2. In Remote Models on the Mac, configure the confirmed environment values, test health, and refresh discovery. Put any bearer token in the app's Keychain-backed credential field only.
3. In ordinary Chat, choose the discovered remote model and request `Reply with exactly: AUTOMLX_WINDOWS_OK`.
4. Verify multi-turn memory, then start a long response, press Stop, and confirm a later short response succeeds.
5. Copy this directory to a disposable Mac workspace. Confirm `make test` fails in under one second.
6. In Engineering, request: `Fix shipping_total so the observable test passes. Make the smallest correct change, then run the approved test and verify the result.`
7. Approve the one-line edit and `make test` separately. Confirm the Mac changes `subtotal - fee` to `subtotal + fee`, the real test passes, and post-edit verification observes the changed file.
8. Repeat from a fresh disposable copy while denying the edit. Confirm the file remains byte-identical and the run ends with permission denied.

The production runtime already resolves the allowlisted `make` executable and requires explicit process approval. Do not weaken containment, default-deny, or approval rules. A harness must compare executable plus arguments semantically rather than requiring the literal spelling `/usr/bin/make test`.

Record only sanitized results. Do not record tokens. Do not mark this file PASS until the complete physical workflow has actually run.
