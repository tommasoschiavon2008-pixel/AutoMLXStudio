# Project 5 Model Catalog

Project 5 V0.2 registers the following offline-first catalog. Registration does not download or invoke a model.

Default model root:

```text
/Volumes/Crucial X9 Pro/app/Models/Project5
```

| Purpose | Repository | Expected folder | Backend | Default state |
|---|---|---|---|---|
| General, Research, Final Composer | `mlx-community/Qwen3-8B-4bit` | `Qwen3-8B-4bit` | MLX LM | Enabled, optional installation |
| Coding, Swift | `mlx-community/Qwen2.5-Coder-7B-Instruct-4bit` | `Qwen2.5-Coder-7B-Instruct-4bit` | MLX LM | Enabled, optional installation |
| Reasoning, Reviewer | `mlx-community/DeepSeek-R1-0528-Qwen3-8B-4bit` | `DeepSeek-R1-0528-Qwen3-8B-4bit` | MLX LM | Enabled, optional installation |
| Translation | `mlx-community/translategemma-4b-it-4bit` | `translategemma-4b-it-4bit` | MLX LM | Enabled, not assigned in V0.2 |
| Vision | `mlx-community/Qwen3-VL-8B-Instruct-4bit` | `Qwen3-VL-8B-Instruct-4bit` | MLX VLM | Enabled; installation and `mlx-vlm` gate execution |
| Speech to Text | `mlx-community/Qwen3-ASR-0.6B-4bit` | `Qwen3-ASR-0.6B-4bit` | MLX Audio | Enabled; installation and `mlx-audio` gate execution |
| Text to Speech | `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-6bit` | `Qwen3-TTS-12Hz-1.7B-Base-6bit` | MLX Audio | Enabled; installation and `mlx-audio` gate execution |
| Embedding | `mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ` | `Qwen3-Embedding-0.6B-4bit-DWQ` | Embedding | Registered, disabled until V0.4 |
| Reranking | `mlx-community/Qwen3-Reranker-0.6B-4bit` | `Qwen3-Reranker-0.6B-4bit` | Reranker | Registered, disabled until V0.4 |

## Installation detection

The Models page scans local folders only. A catalog model is considered installed only when structured validation confirms:

- `config.json`;
- tokenizer metadata for MLX LM, VLM, and Audio repositories;
- at least one `.safetensors` or `.npz` weights file;
- a plausible bounded safetensors header for each container;
- every shard declared by every safetensors index;
- no explicit partial-download marker.

An absent folder is **Not installed**. A present but incomplete folder is **Downloading / incomplete**. Select Folder can point a profile to another local directory. Refresh Catalog repeats the offline inspection and updates disk size where readable. Lock files are warnings, not proof of an active download.

The model kept in the V0.1 `modelIdentifier` setting is migrated as **Legacy fallback**. It remains the final agent fallback and continues to be used by Optimize and Benchmark. A repository-only availability exception applies only to this migrated model so the already working MLX cache configuration is not broken.

## Default assignments

| Agent | Preferred | Declared fallback | Final fallback |
|---|---|---|---|
| General Agent | Qwen3 8B | DeepSeek R1 Qwen3 8B | Legacy model |
| Coding Agent | Qwen2.5 Coder 7B | Compatible installed model | Legacy model |
| Swift Agent | Qwen2.5 Coder 7B | Compatible installed model | Legacy model |
| Research Agent | Qwen3 8B | Compatible installed model | Legacy model |
| Vision Agent | Qwen3 VL 8B | None; Vision backend required | None; text models cannot inspect images |
| Reviewer Agent | DeepSeek R1 Qwen3 8B | Qwen3 8B | Legacy model |
| Final Composer | Qwen3 8B | DeepSeek R1 Qwen3 8B | Legacy model |

Assignments and capability preferences are editable and persisted. A selected model must still be enabled, installed, use the V0.2 text backend, and satisfy every agent capability.

## Runtime audit status — 2026-08-19

The existing Python 3.12.14 environment contains MLX 0.32.1, MLX LM 0.32.0, MLX VLM 0.6.15, MLX Audio 0.5.0, Transformers 5.15.0, and Hugging Face Hub 1.28.0. `pip check` reports no broken requirements. MLX LM package versions were unchanged when the optional packages were added.

The General, Coder, Reasoner, ASR, and TTS folders pass structured local validation. Vision remains **Downloading / incomplete**: its index declares four `model-*-of-00004.safetensors` shards and none of those exact files exists. Two differently named `of-00002` files do not satisfy the manifest. Lock evidence is displayed and left untouched. Translation, Embedding, and Reranker are not installed.

On the 16 GiB validation host, the model budget is 12 GiB after a conservative 4 GiB system reserve. One large Text or Vision runtime may be resident; Audio may coexist only when the sum of conservative estimates fits that budget.

## Test action

For an installed enabled MLX LM model, **Test Text**:

1. validates local files and the existing MLX executable;
2. reuses or loads the model through `ModelResourceManager`;
3. sends a short non-streaming prompt;
4. requires a non-empty response;
5. reports model load and inference time;
6. restores the model that was active before the test, or returns to offline state if no model was active.

First-token timing is not exposed by the current non-streaming completion endpoint and is therefore reported as unavailable rather than estimated.

Models uses backend-specific labels: **Test Text**, **Test Vision**, **Test Transcription**, and **Test Speech**. Text performs its existing bounded completion test. Non-text catalog actions currently perform structured installation and dependency validation; the separately executable hardware scheme performs real deterministic inference with output and timing assertions. No test installs packages, downloads weights, sends Audio/Vision through MLX LM, or autoplays TTS output.
