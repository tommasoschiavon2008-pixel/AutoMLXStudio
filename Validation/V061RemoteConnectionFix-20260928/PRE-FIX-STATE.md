# AutoMLXStudio remote connection repair — pre-fix state

Date: 2026-09-28.

The historical V0.6.1 source manifest passed all 108 entries before source changes. The unmodified check is preserved in `FreezeManifest-PreFix.log`.

The operational directory `/Volumes/AutoMLXShrd/AutoMLXStudioV1_3` has no `.git` repository at or above its root on this volume. Consequently there is no local HEAD, Git status, or Git diff to record. The manifest and these pre-fix hashes identify the source state instead:

| File | SHA-256 before repair |
| --- | --- |
| `project.yml` | `1463b7794d4428f822e9b8632be91d5e7dfed5ed2fd5b9bf6cc5974fd27f5b3f` |
| `AutoMLXStudio.xcodeproj/project.pbxproj` | `d699c9e7e1faaa4c1ad336d95645e6300b689176ab5b90917151c7eea603b9e5` |
| `AutoMLXStudio/Services/RemoteInferenceBackend.swift` | `0c8e36616a8b5694b6770f44e70fc2cc83f1379fd90cf8f4b42bb21c7651a17d` |
| `AutoMLXStudioTests/RemoteInferenceBackendTests.swift` | `93e2726440a112413a7664c9eda9b6b27b5f83a91f6f6cc7ce2dc47783016735` |
| `AutoMLXStudioTests/RemoteModelsControllerTests.swift` | `476ab0bf6a5c7fc44cad82d6aa687e5322043747765186ecf5223d04e2af7bb4` |

The inspected frozen Debug bundle is `Validation/V061BenchmarkHarness-20260911/DerivedData-Debug/Build/Products/Debug/AutoMLXStudio.app`. Its effective `Info.plist` has no `NSLocalNetworkUsageDescription` or ATS exception. Its signing state is ad hoc, linker signed, with no team identifier and no sandbox entitlements. The project's app sandbox setting is `NO`.

At the time of diagnosis, the non-secret runtime store contained two enabled HTTP profiles: an obsolete `192.168.1.20:1234/v1` entry and the current `192.168.1.7:1234/v1` entry. The latter uses OpenAI-compatible API and no authentication. This document intentionally omits credentials and the complete runtime store.

Mac Terminal `curl` to `http://192.168.1.7:1234/v1/models` returned HTTP 200 and included `qwen/qwen3-4b-2507`. The actual AutoMLXStudio process logged a pre-HTTP Network.framework path failure: `unsatisfied (Local network prohibited)` on interface `en7`; CFNetwork reported zero response bytes and `NSURLErrorDomain` code `-1009`, with underlying `kCFErrorDomainCFNetwork` code `-1009` and POSIX network error 50. The focused unmodified-process evidence is in `PreFix-Network-Denial.log`.

The live transport failure occurs before HTTP validation or JSON decoding. The existing `RemoteInferenceBackend.perform` maps `.notConnectedToInternet` to `.connectionLost`, which explains the misleading UI wording, “The connection to the remote server was lost.”
