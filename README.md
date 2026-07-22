# openfox-rag

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

MCP server for [OpenFox](https://github.com/openfox/openfox). Exposes a `rag_search` tool to the OpenFox agent via the [Model Context Protocol](https://modelcontextprotocol.io), enabling it to search local knowledge bases (Obsidian vaults, technical docs, procedures) through a hybrid retrieval pipeline: **BM25 + Vector → RRF → Cross-encoder Reranker**.

Configured in OpenFox via **Settings > Tools > MCP** — exactly like Brave Search. Zero modification to OpenFox core.

## Why

| Without RAG | With openfox-rag |
|-------------|-----------------|
| Agent hallucinates or asks user to paste docs | Agent searches the knowledge base autonomously |
| Entire corpus stuffed into context (thousands of tokens) | 5-10 relevant chunks (~2000 tokens) |
| Maximum compute per query | Compute proportional to actual relevance |
| Often depends on cloud APIs | 100% local, no data leaves the machine |

## Architecture

```
OpenFox Agent
    │
    ├──→ LLM Backend (vLLM / llamacpp / sglang)
    │         ├──→ Chat model (DeepSeek, Qwen3, etc.)
    │         ├──→ Qwen3-Embedding-0.6B  ← same backend
    │         └──→ Qwen3-Reranker-0.6B   ← same backend
    │
    └──→ openfox-rag MCP server (this repo)
              ├──→ POST /v1/embeddings  (same backend)
              ├──→ POST /v1/rerank      (same backend)
              ├──→ BM25 + RRF           (local, inside the MCP server)
              ├──→ Embedding cache      (~/.config/openfox/rag-cache/)
              └──→ Tool rag_search      (visible by the agent)
```

**Zero additional processes.** Embedding and reranker are served by the same backend as the chat LLM. The MCP server handles RAG logic (BM25, RRF, cache) in Node.js and calls the existing backend's endpoints.

## Installation

### 1. Prerequisites

- OpenFox installed (`npm i -g openfox`)
- Node.js >= 24
- LLM backend with embedding + reranking support:
  - **llamacpp**: `--models-preset models.ini` (see [`presets/models-llamacpp.ini`](presets/models-llamacpp.ini))
  - **vLLM**: `--task embedding` + `--task score`
  - **sglang**: native embedding support
- GGUF models (choose based on your hardware):

  | Model | Quant | Size | Hardware | MTEB |
  |-------|-------|------|----------|------|
  | Qwen3-Embedding-0.6B | Q8_0 | 610 MB | CPU or GPU | 64.33 |
  | Qwen3-Embedding-4B | Q4_K_M | 2.4 GB | GPU recommended | 69.45 |
  | Qwen3-Reranker-0.6B | Q4_K_M | 379 MB | CPU or GPU | 65.80 |
  | Qwen3-Reranker-4B | Q4_K_M | 2.4 GB | GPU  | 69.76 |

  - as you can see in the MTEB score tests, the difference is not that big between 0.6B and 4B models
  - for GPU users Qwen3-Embedding-4B with Qwen3-Reranker-0.6B is probably the sweet spot for most users as the latency due to reranking is the most perceived.
  - 8B models are insignificant and though not recommanded
  
  - Embedding: [Qwen/Qwen3-Embedding-0.6B-GGUF](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF) or [Qwen/Qwen3-Embedding-4B-GGUF](https://huggingface.co/Qwen/Qwen3-Embedding-4B-GGUF) (official)
  - Reranker: [Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) or [Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp](https://huggingface.co/Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp) (**mandatory** — community GGUFs are broken, see [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407))
  
### 2. Install the MCP server

```bash
cd /path/to/openfox-rag
npm install
```

### 3. Configure in OpenFox

Settings > Tools > MCP:

```json
{
  "mcpServers": {
    "rag": {
      "command": "node",
      "args": ["/path/to/openfox-rag/mcp/server.js"],
      "env": {
        "RAG_BACKEND_URL": "http://localhost:8000",
        "RAG_EMBEDDING_MODEL": "Qwen3-Embedding-0.6B",
        "RAG_RERANKER_MODEL": "Qwen3-Reranker-0.6B",
        "RAG_DEFAULT_VAULT": "obsidian",
        "RAG_TOP_K": "5",
        "RAG_RERANK_CANDIDATES": "18",
        "RAG_ENABLE_RERANKER": "true",
        "RAG_ALPHA_RATIO": "0.36",
        "RAG_CACHE_DIR": "~/.config/openfox/rag-cache/",
        "RAG_VAULTS": "void:/path/to/obsidian/001 Void 000,linux:/path/to/obsidian/000 linux 000,llm:/path/to/obsidian/004 llm 000"
      }
    }
  }
}
```

The agent can also configure it autonomously: *"set up the RAG MCP"* — same pattern as Brave Search.

### 4. Configuration reference

| Setting | Env var | Default | Description |
|---------|---------|---------|-------------|
| Enable RAG | *(remove MCP entry to disable)* | — | Toggle the `rag_search` tool on/off |
| Backend URL | `RAG_BACKEND_URL` | `http://localhost:8000` | LLM backend URL (vLLM/llamacpp/sglang) |
| Embedding model | `RAG_EMBEDDING_MODEL` | `Qwen3-Embedding-0.6B` | Model name in the backend |
| Reranker model | `RAG_RERANKER_MODEL` | `Qwen3-Reranker-0.6B` | Model name in the backend |
| Default vault | `RAG_DEFAULT_VAULT` | `obsidian` | Default vault for searches |
| Top K | `RAG_TOP_K` | `5` | Number of results |
| Rerank candidates | `RAG_RERANK_CANDIDATES` | `18` | Candidates sent to the reranker |
| Enable reranker | `RAG_ENABLE_RERANKER` | `true` | Enable cross-encoder reranking |
| Alpha ratio | `RAG_ALPHA_RATIO` | `0.36` | Chunk filter threshold |
| Cache directory | `RAG_CACHE_DIR` | `~/.config/openfox/rag-cache/` | Embedding cache location |
| Vaults | `RAG_VAULTS` | *(empty)* | Comma-separated `name:/path` pairs |

### 5. Add vaults

Vaults are configured via the `RAG_VAULTS` environment variable:

```
RAG_VAULTS=void:/path/to/obsidian/001 Void 000,linux:/path/to/obsidian/000 linux 000,llm:/path/to/obsidian/004 llm 000
```

| Name | Path |
|------|------|
| void | `/path/to/obsidian/001 Void 000` |
| linux | `/path/to/obsidian/000 linux 000` |
| llm | `/path/to/obsidian/004 llm 000` |

Special vault scopes:
- `obsidian`: all configured Obsidian vaults
- `all`: all vaults (Obsidian + external)

### 6. Restart OpenFox

The `rag_search` tool appears automatically in the agent's tool list.

## Backend Configuration

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

> **Note on pooling**: The official [Qwen3 blog](https://qwenlm.github.io/blog/qwen3-embedding/) says `last` (hidden state of the final [EOS] token) for embedding. The [Voodisss guide](https://gist.github.com/VooDisss/42bce4eb5c76d3c325633886c5e348ee) says `mean`. Official docs take precedence: use `last`.

### vLLM (GPU cluster)

#### 0.6B models

```bash
vllm serve Qwen/Qwen3-Embedding-0.6B \
  --served-model-name Qwen3-Embedding-0.6B \
  --task embedding --port 8000 &

vllm serve Qwen/Qwen3-Reranker-0.6B \
  --served-model-name Qwen3-Reranker-0.6B \
  --task score --port 8001 &
```

#### 4B models

```bash
vllm serve Qwen/Qwen3-Embedding-4B \
  --served-model-name Qwen3-Embedding-4B \
  --task embedding --port 8000 &

vllm serve Qwen/Qwen3-Reranker-4B \
  --served-model-name Qwen3-Reranker-4B \
  --task score --port 8001 &
```

### sglang

```bash
python -m sglang.launch_server \
  --model-path Qwen/Qwen3-Embedding-0.6B \
  --is-embedding --port 8000 &
```

## Tool Exposed to the Agent

```json
{
  "name": "rag_search",
  "description": "Search local knowledge base (Obsidian vaults, technical docs, procedures). Use when the user asks about their notes, documentation, or when you need to verify a technical reference before coding.",
  "parameters": {
    "query": "string — natural language search query",
    "vault": "string — obsidian | all | void | linux | llm | terminal",
    "top_k": "integer — number of results (default: 5)",
    "rerank": "boolean — enable reranker (default: true)"
  }
}
```

## Workflow Integration

### Custom workflow step

Add a "Research" step before "Build" in OpenFox's workflow editor:

```
[Research (RAG)] → [Build] → [Verify] → [Code Review] → [Summary]
```

### General Instructions

Add to your OpenFox General Instructions:

```
Before coding, always consult the local knowledge base via rag_search
to verify procedures, configurations, and technical references.
```

## Standalone RAG Server (Alternative)

If you prefer a separate Python RAG server (BM25 + vector + RRF + reranker) instead of the integrated MCP server:

**[rag-system](https://github.com/cried-nutty-won/rag-system)** — full reference implementation with documentation.

The MCP server can also run in **proxy mode** by pointing `RAG_BACKEND_URL` to `http://127.0.0.1:8182`. In this mode, the MCP server forwards all search requests to the Python RAG server, which handles embedding, BM25, RRF, and reranking internally.

## Performance

| Metric | RRF only | With Reranker (0.6B) | With Reranker (4B) |
|--------|----------|---------------------|-------------------|
| Latency (CPU) | ~20 ms | ~10-18 s (18 candidates) | ~30-40 s (too slow) |
| Latency (GPU) | ~3 ms | ~1 s (100 candidates) | ~3 s (100 candidates) |
| RAM / VRAM | ~1.7 GB | ~1.7 GB | ~6 GB |
| Accuracy (NDCG@10) | baseline | +12 pts | +16 pts |

### Model selection guide

| Hardware | Embedding | Reranker | Why |
|----------|-----------|----------|-----|
| CPU only (8 GB RAM) | 0.6B Q8_0 | 0.6B Q4_K_M | Fits in RAM, interactive latency |
| GPU (6+ GB VRAM) | 4B Q4_K_M | 4B Q4_K_M | Best quality, ~3s for 100 candidates |
| GPU (24+ GB VRAM) | 4B F16 | 4B F16 | Maximum quality, no quantization loss |

## Known Limitations

- **Reranker GGUF**: Only [Voodisss GGUFs](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) work. Community conversions are broken (missing `cls.output.weight` tensor). See [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407).
- **Host prompt cache**: llama.cpp [PR #16391](https://github.com/ggml-org/llama.cpp/pull/16391) defaults to 8 GiB host prompt cache. For embedding/reranker servers where prompts are never reused, add `--cache-ram 0` to prevent OOM.
- **Reranker candidates > 21 on CPU**: The reranker crashes. 18 is the stable sweet spot.
- **No hot-reload**: Modifying an Obsidian file requires cache clear + re-index.
- **Orphan cache**: Deleted chunks remain in the JSON cache (no garbage collection yet).

## References

- [OpenFox](https://github.com/openfox/openfox) — local-LLM-first agentic coding assistant
- [rag-system](https://github.com/cried-nutty-won/rag-system) — standalone RAG reference implementation (Python)
- [Qwen3 Embedding blog](https://qwenlm.github.io/blog/qwen3-embedding/) — official documentation
- [Voodisss multi-model guide](https://gist.github.com/VooDisss/42bce4eb5c76d3c325633886c5e348ee) — llamacpp models.ini reference
- [Voodisss Reranker GGUF](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) — working GGUF conversions
- [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407) — why community reranker GGUFs are broken
- [llama.cpp PR #16391](https://github.com/ggml-org/llama.cpp/pull/16391) — host prompt cache (8 GiB default)
- Dave Ebbelaar, "Hybrid Retrieval from Scratch" (2026) — methodology

## auteur

cried-nutty-won with qwen-3.8-max

## License

[MIT](LICENSE) — consistent with the OpenFox ecosystem.
