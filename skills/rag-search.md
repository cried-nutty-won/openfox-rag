# RAG — Local Knowledge Base

You have full control over a local RAG (Retrieval-Augmented Generation) system.
You can start it, search it, monitor it, and stop it — all from the terminal.

## Commands

| Command | Action |
|---------|--------|
| `llmers` | Start full stack (embedding + reranker + RAG server) |
| `llmes` | Start embedding + RAG server (no reranker) |
| `llme` | Start embedding only (port 8181) |
| `llmr` | Start reranker only (port 8184) |
| `rs` | Start Python RAG server only (port 8182) |
| `rst` | Tail -f RAG server logs |
| `rag <vault> "<query>"` | Search with RRF only (fast, ~20ms) |
| `ragr <vault> "<query>"` | Search with RRF + reranker (precise, ~10-18s) |
| `rc` | Health check all 3 services |
| `rsk` | Kill the Python RAG server |

## Vaults

 `eric` · `void` · `linux` · `browsing` · `terminal` · `llm` · `images` · `telephone` · `openfox` · `obsidian` · `all`

- `obsidian`: all Obsidian vaults
- `all`: all vaults (Obsidian + external)

## Workflow

### 1. Check if RAG is running

```bash
rc
```

If all 3 services are healthy, skip to step 3.

### 2. Start the RAG stack

```bash
llmers
```

Wait 5-10 seconds, then verify:

```bash
rc
```

### 3. Search

Fast search (RRF only, ~20ms):

```bash
rag void "nftables configuration"
```

Precise search (RRF + reranker, ~10-18s):

```bash
ragr void "nftables configuration"
```

With custom top_k:

```bash
rag all "dracut mkinitcpio" 10
```

### 4. Read the results

The output is JSON. Each result contains:

- `source`: filename
- `path`: full path
- `confidence`: relevance score (0-100)
- `rerank_score`: reranker score (0.0-1.0), if reranking was enabled
- `text`: the relevant passage

Use the retrieved passages as context for your answer.
Always cite the source file.

### 5. Monitor (if needed)

```bash
rst
```

### 6. Stop (if needed)

```bash
rsk
```

## When to use

- The user asks about their notes, documentation, or procedures
- You need to verify a technical reference before writing code
- The user says "search my notes", "check my docs", "look in my vault"
- You are about to write configuration code (nftables, dracut, sfdisk, etc.)
  and want to check the user's existing procedures first
- The user asks a question about Void Linux, terminal setup, LLM configuration,
  or any topic that might be in their vaults

## When NOT to use

- The answer is in the current project's code
- It is a general knowledge question unrelated to the user's documents
- The user explicitly says not to search

## Examples

User: "Configure nftables for my server"

```bash
rc
# If not running:
llmers
# Wait, then:
ragr linux "nftables configuration firewall"
```

User: "What did I write about dracut?"

```bash
rag void "dracut"
```

User: "Search everything about Qwen3"

```bash
ragr all "Qwen3 embedding reranker" 10
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `rc` shows services down | Run `llmers` and wait 10s |
| Search returns no results | Try a different vault or broader query |
| Reranker timeout | Use `rag` instead of `ragr` (RRF only) |
| Port already in use | `rsk` then `rs`, or `pkill -f llama-server` then `llmers` |
| Need to check logs | `rst` |
