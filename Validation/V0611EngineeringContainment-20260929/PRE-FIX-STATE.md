# Pre-fix state — 2026-09-29

Operational repository: `/Volumes/AutoMLXShrd/AutoMLXStudioV1_3`. This record was created before any implementation changes. The prior repaired application is a post-V0.6.1 patch; its previous physical validation documented `FILESYSTEM BOUNDARY: FAIL` for an approved `make` target. Historical validation records were not modified.

Relevant SHA-256 source state:

| Path | SHA-256 |
| --- | --- |
| `AutoMLXStudio/Services/EngineeringProcessRunner.swift` | `1e33fd2a960cbd903bb59eb39595cb6a2bbf2cac95592d49fc6c1bfe753695bb` |
| `AutoMLXStudio/Services/EngineeringToolRuntime.swift` | `b0ecc00a9627181d98291a5429a4f89b0e730b9e0f64d4938404d1c6389c4838` |
| `AutoMLXStudio/Services/EngineeringWorkspace.swift` | `3f14e39ae7716dd278c32e930bb38624950310cfa0d0160fc717a5b5859d7c51` |
| `AutoMLXStudio/Services/EngineeringController.swift` | `15e2c23ea4855400ab0dae4f9a2ef9f25cb331f0c66cdf6bd72405c2fbf36d45` |
| `AutoMLXStudio/Services/EngineeringSessionBuilder.swift` | `7a4aa80aa29691393ff0542e1a5f6ee13e4c8c9ca81c6a9e6ef227a61bfd94fd` |
| `AutoMLXStudio/Views/EngineeringView.swift` | `0befc5241d0616ca1718dc4971c4c2535118f48cb5b85c8c841aa0846fcbdb3d` |
| `AutoMLXStudio/Core/Engineering/EngineeringModels.swift` | `bb61b5bd46c53d20304e98eabc5088dea67f2f4aebcdf26e8c5a86d3e4a7486d` |
| `AutoMLXStudioTests/EngineeringToolRuntimeTests.swift` | `5e8f8fd591036e2aa0c2e14c59edc401b39d8ab316b3dee4a3136b8e292fde8a` |
| `project.yml` | `93cf9434e963fdf3d1d35cfb801022742b04a8f8df6d50b2f0253cfeae062803` |
| `AutoMLXStudio.xcodeproj/project.pbxproj` | `2cfe9361dc1cd31eb3e2342650059ff6d0c794813d863069e71fae19355da450` |

The checkout has no Git metadata at this volume boundary. Exact baseline copies of these files are held in `PreFixSources/` for a reproducible final patch; the historical V0.6.1 freeze remains untouched.

Execution trace before repair: `EngineeringController` opens a user-selected `EngineeringWorkspace`; `EngineeringSessionBuilder` creates `EngineeringToolRuntime(requiresMutationApproval: true)`; `EngineeringToolRuntime.execute` classifies `run_command`, waits for one-shot approval when classified as a mutation, resolves only its working directory through `EngineeringWorkspace`, prepares a sanitized environment, and calls `EngineeringProcessRunner.run`. The runner directly launches a host `Process`, with no OS-enforced filesystem restriction. `make` invokes recipes via a shell and can launch children. `EngineeringWorkspace` canonicalizes paths for direct file operations, but not arbitrary file opens by child processes.

The checked-in build sets `ENABLE_APP_SANDBOX = NO`; no app or child sandbox entitlement is present. `project.yml` has `NSLocalNetworkUsageDescription` from the Windows connection repair. The product has no `MARKETING_VERSION`/`CFBundleShortVersionString` setting in the checked-in project.
