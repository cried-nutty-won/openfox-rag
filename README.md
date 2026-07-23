# openfox-rag   [(fr)](README.fr.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

RAG integration for [OpenFox](https://github.com/openfox/openfox). A skill file that teaches the OpenFox agent to search local knowledge bases (Obsidian vaults, technical docs, procedures) through a hybrid retrieval pipeline: **BM25 + Vector → RRF → Cross-encoder Reranker**.

No MCP, no plugin, no additional process. The RAG server runs independently ([rag-system](https://github.com/cried-nutty-won/rag-system)), and the agent controls it entirely via its built-in terminal using 10 shell shortcuts.

## Why

| Without RAG | With openfox-rag |
|-------------|-----------------|
| Agent hallucinates or asks user to paste docs | Agent searches the knowledge base autonomously |
| Entire corpus stuffed into context (thousands of tokens) | 5-10 relevant chunks (~2000 tokens) |
| Maximum compute per query | Compute proportional to actual relevance |
| Often depends on cloud APIs | 100% local, no data leaves the machine |

## How it works

```
OpenFox Agent
    │
    ├──→ Built-in terminal
    │         │
    │         ├──→ rc          (health check)
    │         ├──→ llmers      (start full stack)
    │         ├──→ ragr void "query"   (precise search)
    │         ├──→ rag void "query"    (fast search)
    │         ├──→ rst         (tail logs)
    │         └──→ rsk         (stop server)
    │
    └──→ Skill file (skills/rag-search.md)
              └──→ Tells the agent when and how to use each command
```

**Zero additional processes on the OpenFox side.** The RAG server is a separate, independent service. The agent starts it, searches it, monitors it, and stops it — all from the terminal, exactly like any other command-line tool.

---

## Installation

```bash
git clone https://github.com/cried-nutty-won/openfox-rag.git
cd openfox-rag
bash install.sh
```

The installer:

- Detects OS, RAM, GPU (NVIDIA, Apple Silicon, lspci)
- Detects shell (fish, bash, zsh, sh) and writes aliases to the correct config
- Offers 0.6B models (default) or 4B models (GPU only — hidden on CPU)
- Downloads GGUF from official Qwen + Voodisss
- Clones and configures [rag-system](https://github.com/cried-nutty-won/rag-system)
- Scans for Obsidian and documentation vaults (interactive loop)
- Installs the OpenFox skill (`~/.config/openfox/skills/rag-search.md`)
- Displays all commands and documentation paths at the end

### Dry-run mode

Test without modifying anything:

```bash
bash install.sh --dry-run
```

## Commands

| Command | Action |
|---------|--------|
| `llmers` | Start full stack (embedding + reranker + RAG server) |
| `llmes` | Start embedding + RAG server (no reranker) |
| `llme` | Start embedding only (port 8181) |
| `llmr` | Start reranker only (port 8184) |
| `rs` | Start Python RAG server only (port 8182) |
| `rst` | Tail -f RAG server logs |
| `rag <vault> "<query>"` | Fast search (~20ms) |
| `ragr <vault> "<query>"` | Slow and precise search with reranker (~10-18s CPU, ~1s GPU) |
| `rc` | Health check all 3 services |
| `rsk` | Kill the Python RAG server |

## Vaults

Configured interactively during installation. Each vault has a short name used in commands:

```bash
rag void "nftables configuration"        # search vault "void"
ragr linux "dracut hooks"                 # precise search in "linux"
ragr all "your query"                     # search all vaults
rag obsidian "your query"                 # search all Obsidian vaults
```

---

## Model selection

| Hardware | Embedding | Reranker | Why |
|----------|-----------|----------|-----|
| CPU only (8 GB RAM) | 0.6B Q8_0 | 0.6B Q4_K_M | Fits in RAM, interactive latency |
| GPU (6+ GB VRAM) | 4B Q4_K_M | 4B Q4_K_M | Best quality, ~3s for 100 candidates |
| GPU (24+ GB VRAM) | 4B F16 | 4B F16 | Maximum quality, no quantization loss |

### GGUF models

| Model | Quant | Size | Hardware | MTEB |
|-------|-------|------|----------|------|
| Qwen3-Embedding-0.6B | Q8_0 | 610 MB | CPU or GPU | 64.33 |
| Qwen3-Embedding-4B | Q4_K_M | 2.4 GB | GPU recommended | 69.45 |
| Qwen3-Reranker-0.6B | Q4_K_M | 379 MB | CPU or GPU | 65.80 |
| Qwen3-Reranker-4B | Q4_K_M | 2.4 GB | GPU recommended | 69.76 |

- Embedding: [Qwen/Qwen3-Embedding-0.6B-GGUF](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF) or [Qwen/Qwen3-Embedding-4B-GGUF](https://huggingface.co/Qwen/Qwen3-Embedding-4B-GGUF) (official)
- Reranker: [Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) or [Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp](https://huggingface.co/Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp) (**mandatory** — community GGUFs are broken, see [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407))

---

**MTEB** (Massive Text Embedding Benchmark) is the reference benchmark for evaluating embedding model quality. It measures a model's ability to produce vectors that capture text meaning, across **8 task types**:

| Task | What it measures | Example |
|---|---|---|
| **Retrieval** | Finding the right document among thousands | "What is the nftables procedure?" → find the right file |
| **Reranking** | Reordering candidates by relevance | Rank 18 chunks from most to least relevant |
| **Classification** | Categorizing a text | "Is this document about networking or storage?" |
| **Clustering** | Grouping similar texts | Group notes by topic |
| **STS** (Semantic Textual Similarity) | Measuring similarity between two sentences | "nftables firewall" ≈ "nftables firewall rules" |
| **Pair Classification** | Determining if two texts are related | "Does this procedure match this question?" |
| **Bitext Mining** | Finding the corresponding translation | FR ↔ EN |
| **Summarization** | Evaluating summary quality | — |

### Why it matters for RAG

The MTEB **Retrieval** score is the most important for RAG: it directly measures the model's ability to find the right document. The higher the score, the less the RAG needs the reranker to compensate.

| Model | MTEB Multilingual | MTEB Retrieval | Dimensions |
|---|---|---|---|
| Qwen3-Embedding-0.6B | 64.33 | 64.64 | 1024 |
| Qwen3-Embedding-4B | 69.45 | 69.60 | 2560 |
| Qwen3-Embedding-8B | 70.58 | 70.88 | 4096 |

The 0.6B is sufficient for a local RAG with reranker. The 4B adds +5 points but requires a GPU.

---

## Backend Configuration

The embedding and reranker models can be served by the same backend as the chat LLM, or by separate llama-server instances. See [`presets/models-llamacpp.ini`](presets/models-llamacpp.ini) for a ready-to-use configuration.

### llamacpp (models.ini)

One server, one port, three models. The router swaps models in/out of VRAM on demand.

#### 0.6B models (CPU-friendly, ~1 GB total)

```ini
[*]
n-gpu-layers = all
batch-size = 2048
ubatch-size = 2048
load-on-startup = Qwen3-Embedding-0.6B

[Qwen3-Embedding-0.6B]
model = /path/to/Qwen3-Embedding-0.6B-Q8_0.gguf
embedding = true
pooling = last
ctx-size = 8192

[Qwen3-Reranker-0.6B]
model = /path/to/Qwen3-Reranker-0.6B-Q4_K_M.gguf
reranking = true
pooling = rank
embedding = true
ctx-size = 1024

[deepseek-v4-flash]
model = /path/to/DeepSeek-V4-Flash.gguf
ctx-size = 32768
```

#### 4B models (GPU recommended, ~5 GB total)

```ini
[*]
n-gpu-layers = all
batch-size = 2048
ubatch-size = 2048
load-on-startup = Qwen3-Embedding-4B

[Qwen3-Embedding-4B]
model = /path/to/Qwen3-Embedding-4B-Q4_K_M.gguf
embedding = true
pooling = last
ctx-size = 32768

[Qwen3-Reranker-4B]
model = /path/to/Qwen3-Reranker-4B-Q4_K_M.gguf
reranking = true
pooling = rank
embedding = true
ctx-size = 32768

[deepseek-v4-flash]
model = /path/to/DeepSeek-V4-Flash.gguf
ctx-size = 32768
```

```bash
llama-server --host 127.0.0.1 --port 8000 --models-max 1 --models-preset models.ini
```

> **Note on pooling**: The official [Qwen3 blog](https://qwenlm.github.io/blog/qwen3-embedding/) says `last` (hidden state of the final [EOS] token) for embedding. Some community guides say `mean`. Official docs take precedence: use `last`.

### vLLM (GPU cluster)

```bash
vllm serve Qwen/Qwen3-Embedding-0.6B \
  --served-model-name Qwen3-Embedding-0.6B \
  --task embedding --port 8000 &

vllm serve Qwen/Qwen3-Reranker-0.6B \
  --served-model-name Qwen3-Reranker-0.6B \
  --task score --port 8001 &
```

### sglang

```bash
python -m sglang.launch_server \
  --model-path Qwen/Qwen3-Embedding-0.6B \
  --is-embedding --port 8000 &
```

### ollama (embedding only)

Ollama does not support reranking. The RAG server automatically falls back to pure RRF (BM25 + vector, no reranker).

```bash
ollama pull qwen3-embedding:0.6b
```

```bash
# RAG server configuration for ollama
export LLAMA_EMBED_URL="http://127.0.0.1:11434/api/embeddings"
# No reranker URL — automatic RRF fallback
```

### Backend compatibility summary

| Backend | Embedding | Reranking | RAG mode |
|---|---|---|---|
| llamacpp | ✅ `POST /embedding` | ✅ `POST /v1/rerank` | Hybrid + Reranker |
| vLLM | ✅ `POST /v1/embeddings` | ✅ `POST /v1/rerank` | Hybrid + Reranker |
| sglang | ✅ `POST /v1/embeddings` | ✅ `POST /v1/rerank` | Hybrid + Reranker |
| ollama | ✅ `POST /api/embeddings` | ❌ | Hybrid (RRF only) |

The RAG server adapts automatically: if the reranker is unreachable, it falls back to pure RRF without error.

## Workflow Integration

### Custom workflow step

Add a "Research" step before "Build" in OpenFox's workflow editor:

```
[Research (RAG)] → [Build] → [Verify] → [Code Review] → [Summary]
```

### General Instructions

Add to your OpenFox General Instructions:

```
Before coding, always consult the local knowledge base via the terminal.
Run: rc
Then: ragr obsidian "your query"
Use the retrieved passages as context. Always cite the source file.
```

## Performance

| Metric | Fast search | Precise search (0.6B) | Precise search (4B) |
|--------|-------------|----------------------|---------------------|
| Latency (CPU) | ~20 ms | ~10-18 s (18 candidates) | ~30-40 s (too slow) |
| Latency (GPU) | ~3 ms | ~1 s (100 candidates) | ~3 s (100 candidates) |
| RAM / VRAM | ~1.7 GB | ~1.7 GB | ~6 GB |
| Accuracy (NDCG@10) | baseline | +12 pts | +16 pts |

## Known Limitations

- **Reranker GGUF**: Only [Voodisss GGUFs](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) work. Community conversions are broken (missing `cls.output.weight` tensor). See [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407).
- **Host prompt cache**: llama.cpp [PR #16391](https://github.com/ggml-org/llama.cpp/pull/16391) defaults to 8 GiB host prompt cache. For embedding/reranker servers where prompts are never reused, add `--cache-ram 0` to prevent OOM.
- **Reranker candidates > 21 on CPU**: The reranker crashes. 18 is the stable sweet spot.
- **No hot-reload**: Modifying an Obsidian file requires cache clear + re-index.
- **Orphan cache**: Deleted chunks remain in the JSON cache (no garbage collection yet).
- **Agent must parse output**: The agent reads the command output and extracts relevant passages. Works well with models ≥ 7B.

## References

- [OpenFox](https://github.com/openfox/openfox) — local-LLM-first agentic coding assistant
- [rag-system](https://github.com/cried-nutty-won/rag-system) — standalone RAG server (Python)
- [Qwen3 Embedding blog](https://qwenlm.github.io/blog/qwen3-embedding/) — official documentation
- [Voodisss multi-model guide](https://gist.github.com/VooDisss/42bce4eb5c76d3c325633886c5e348ee) — llamacpp models.ini reference
- [Voodisss Reranker GGUF](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) — working GGUF conversions
- [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407) — why community reranker GGUFs are broken
- [llama.cpp PR #16391](https://github.com/ggml-org/llama.cpp/pull/16391) — host prompt cache (8 GiB default)
- Dave Ebbelaar, "Hybrid Retrieval from Scratch" (2026) — methodology

## License

[MIT](LICENSE) — consistent with the OpenFox ecosystem.
