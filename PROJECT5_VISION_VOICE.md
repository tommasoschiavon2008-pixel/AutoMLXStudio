# Project 5 Vision and Voice

## Implemented runtime boundaries

Vision and Voice are real local runtime paths, not text-model simulations.

```text
Image → validation → Fast Router → Vision Agent → MLX VLM
                                      └→ Swift/Coding/Research → Reviewer → Composer

Mic → permission → 16 kHz mono WAV → MLX Audio ASR → editable composer → Send
Stored assistant text → optional MLX Audio TTS → one controlled AVAudioPlayer
```

`MLXVLMVisionService` invokes the installed `mlx_vlm.generate` entrypoint with separate arguments, exact local model and image paths, bounded generation, a four-minute timeout, and Hugging Face/Transformers offline flags. It returns actual output, minimally parsed `VisualAnalysis`, physical model ID/path, measured one-shot duration, and the central residency decision. The CLI does not separate load and inference, so `loadDuration` remains `nil`.

An image plus a Swift, coding, or research request runs Vision first and hands structured visible evidence to the matching specialist. A pure description request remains Vision-only. A Vision failure skips downstream text specialists instead of guessing. Vision never falls back to MLX LM.

`MLXASRRuntimeAdapter` invokes `mlx_audio.stt.generate`, parses its JSON output, measures the input using `AVAudioFile`, and reports language only if the backend supplies it. `MLXTTSRuntimeAdapter` invokes `mlx_audio.tts.generate` with the locally validated Ryan/English configuration, discovers the generated WAV, derives duration from decoded frames, and never passes `--play`.

Voice defaults are conservative: transcripts appear in the composer and remain editable; **Send automatically after transcription** is persisted and OFF by default. **Speak assistant responses** is persisted and OFF by default. Text is stored before TTS starts. TTS failure cannot remove the answer, new playback stops the prior player, explicit Stop is available, and leaving Chat stops playback.

## Process, resource, and temporary-file safety

All VLM/Audio commands use a shell-free owned-process runner with exact executable, PID, arguments, timeout, bounded stdout/stderr, cooperative cancellation, graceful termination, and exact-PID force only after grace. It never scans for or terminates arbitrary Python processes.

`ModelResourceManager` reserves one large Vision runtime exclusively against large Text. Small Audio may coexist only when conservative estimates fit the host-derived budget; otherwise the exact app-owned Text process is released first. One-shot reservations are released on success, parse failure, timeout, and cancellation.

Generated Voice artifacts live under the app-owned temporary namespace `AutoMLXStudioVoice/Generated`. Playback cleanup and one-day age cleanup prove containment before deletion. User recordings, imports, model folders, and unrelated temporary files are never deleted.

## Validated host status — 2026-08-19

Environment: Python 3.12.14, MLX 0.32.1, MLX LM 0.32.0, MLX VLM 0.6.15, MLX Audio 0.5.0, Transformers 5.15.0, Hugging Face Hub 1.28.0. `pip check` is clean.

Vision weights are not launchable because the shard index requires four exact `of-00004` files that are absent. The hardware test therefore skips before process launch and reports the missing filenames. A programmatic 640×320 PNG fixture (white background, rectangle, circle, `PROJECT 5`, arrow) and the full real VLM assertions are ready under `RUN_MLX_VISION_HARDWARE_TESTS=1` for when the external download becomes complete.

ASR was physically validated using a deterministic macOS-synthesized phrase, converted to mono 16 kHz Int16 WAV. Input duration was 1.6350625 s. Qwen3 ASR returned non-empty `Project Five Voice Test.` output in 2.15 s processing time (3.78 s total command observation), with 1.32 GB observed peak memory.

TTS was physically validated with `Project 5 voice test.` using Qwen3 TTS 1.7B 6-bit, Ryan, English. It produced an 84,524-byte mono 24 kHz Int16 WAV lasting 1.76 s. Processing time was 3.94 s (8.10 s total command observation), with 3.52 GB observed peak memory. Playback was intentionally not started.

The opt-in hardware XCTest methods reproduce those modality checks. Normal tests skip expensive inference, and Vision remains independently skip-capable while its download is incomplete.
