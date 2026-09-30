# Chat UI validation

Result: **PASS** for deterministic native rendering on macOS.

The real `ChatView` hierarchy was hosted in an offscreen `NSWindow`/`NSHostingView` and rendered at Retina scale. The host Mac was locked, so a live interactive desktop capture was unavailable; the test-owned native render avoided network, production conversation storage, and production remote-server storage.

Validated states:

- normal 1180×760 and minimum 850×686 logical window sizes;
- local and remote model selection, long model/model-server/conversation names, and controlled truncation;
- empty remote conversation with honest non-streaming description;
- remote failure with bounded message and retained target;
- remote generation with visible Stop and disabled selector/preferences;
- successful unlock and a new remote request after Stop;
- long user/assistant messages, metadata, transcript scrolling, and failed terminal label;
- essential accessibility label/help on the model picker and cancellation action.

No overlap or uncontrolled clipping was observed. At minimum width, intentionally bounded header and picker strings truncate while retaining the primary title, controls, and readable transcript.

Evidence:

- `UI/ChatNormal-1180x760@2x.png`
- `UI/ChatMinimum-850x686@2x.png`
- `UI/AutoMLXStudioV0601ChatRemoteEmpty.png`
- `UI/AutoMLXStudioV0601ChatRemoteError.png`
- `UI/AutoMLXStudioV0601ChatRemoteGenerating.png`
- `UIRenderFinal.log`, `UIRemoteStates.log`, and their `.xcresult` bundles
- `UI.sha256`
