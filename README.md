Salut,

Je propose un serveur MCP `openfox-rag` qui ajoute un tool `rag_search` à l'agent,
lui permettant de chercher dans une base de connaissances locale (vaults Obsidian,
docs techniques, procédures) avant de coder.

Exactement le même pattern que Brave Search : l'utilisateur configure le serveur
MCP dans Settings > Tools > MCP, et l'agent voit un nouveau tool `rag_search`.
Zéro modification du core OpenFox.

Repos :
- Serveur MCP + logique RAG : https://github.com/cried-nutty-won/openfox-rag
- Implémentation de référence (Python) : https://github.com/cried-nutty-won/rag-system

## Le problème

Quand l'agent travaille sur un projet, il n'a aucun moyen de consulter la
documentation locale de l'utilisateur. Il doit soit halluciner, soit demander
à l'utilisateur de coller la doc manuellement dans le contexte.

Concrètement, si j'ai une procédure nftables dans mes notes Obsidian et que
je demande à l'agent de configurer un firewall, il ne peut pas la trouver.
Il va générer une config générique, probablement incorrecte pour mon setup.

Un tool RAG permettrait à l'agent de chercher lui-même dans mes notes et ma
doc technique, exactement comme il utilise déjà web_search pour chercher en ligne.

## Pourquoi MCP et pas un plugin

J'ai analysé le code d'OpenFox. L'API des plugins (`ProviderPluginRegistry`)
ne supporte que les providers :

```typescript
registry.registerAuth(auth)
registry.registerTransport(transport)
registry.registerPreset(preset)
```

Il n'y a pas de `registry.registerTool()`. Les tools (`edit_file`, `read`,
`session_metadata`, etc.) sont dans `src/server/tools/` — ils font partie
du core.

Le MCP est le mécanisme prévu pour ajouter des tools externes sans toucher
au core. C'est exactement ce que tu montres dans ta vidéo avec Brave Search :
l'agent configure le MCP, deux nouveaux tools apparaissent, l'agent les
appelle naturellement.

## Architecture

```
OpenFox Agent
    │
    ├──→ Backend LLM existant (vLLM / llamacpp / sglang)
    │         ├──→ Chat model (DeepSeek V4 Flash, Qwen3, etc.)
    │         ├──→ Qwen3-Embedding-0.6B  ← même backend, même port
    │         └──→ Qwen3-Reranker-0.6B   ← même backend, même port
    │
    └──→ Serveur MCP openfox-rag (process séparé, comme Brave Search)
              ├──→ POST /v1/embeddings  (même backend)
              ├──→ POST /v1/rerank      (même backend)
              ├──→ BM25 + RRF           (local, dans le serveur MCP)
              ├──→ Cache embeddings     (~/.config/openfox/rag-cache/)
              └──→ Tool rag_search      (visible par l'agent)
```

**L'embedding et le reranker sont servis par le même backend que le LLM de chat.**
Le serveur MCP gère la logique RAG (BM25, RRF, cache) en Node.js et appelle
les endpoints du backend existant. Zéro modèle supplémentaire à charger.

## Configuration dans OpenFox

Settings > Tools > MCP (exactement comme Brave Search) :

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
        "RAG_VAULTS": "void:/path/to/obsidian/001 Void 000,linux:/path/to/obsidian/000 linux 000"
      }
    }
  }
}
```

L'agent peut aussi le configurer lui-même : "mets en place le MCP RAG"
→ il configure tout, comme avec Brave Search dans ta vidéo.

## Pipeline de recherche

```
Query utilisateur
       │
       ├──→ Embedding (Qwen3-0.6B) → Cosine similarity → Ranking vectoriel
       │                                                        │
       └──→ Tokenisation → BM25Okapi → Ranking BM25            │
                                         │                      │
                                         └── RRF (k=60) ───────┘
                                                  │
                                          Top 18 candidats
                                                  │
                                          Reranker (Qwen3-0.6B)
                                          (cross-encoder, lit query+doc conjointement)
                                                  │
                                          Résultats finaux
```

Le reranker est l'étape qui apporte le plus de gain qualitatif.
Dans le benchmark FinanceQA de Dave Ebbelaar ("Hybrid Retrieval from Scratch", 2026),
l'ajout d'un reranker améliore le NDCG@10 de **+12 points**.

## Tool exposé à l'agent

```json
{
  "name": "rag_search",
  "description": "Recherche dans la base de connaissances locale (notes Obsidian, documentation technique, procédures). À utiliser quand l'utilisateur pose une question sur ses notes, sa documentation, ou quand tu as besoin de vérifier une référence technique avant de coder.",
  "parameters": {
    "query": "string — requête de recherche",
    "vault": "string — obsidian | all | void | linux | llm | terminal",
    "top_k": "integer — nombre de résultats (défaut: 5)",
    "rerank": "boolean — activer le reranker (défaut: true)"
  }
}
```

## Intégration dans les workflows

Avec les workflows custom (système de blocs), on peut ajouter une étape
"research" avant "build" :

```
[Research (RAG)] → [Build] → [Verify] → [Code Review] → [Summary]
```

Et dans les General Instructions :

```
Avant de coder, consulte toujours la base de connaissances locale
via rag_search pour vérifier les procédures et références techniques.
```

## Compatibilité backend

| Backend | Embedding | Reranker | Notes |
|---------|-----------|----------|-------|
| llamacpp | `/v1/embeddings` | `/v1/rerank` | Via `--models-preset models.ini`, un seul port |
| vLLM | `/v1/embeddings` | `/v1/rerank` | `--task embedding` + `--task score` |
| sglang | `/v1/embeddings` | `/v1/rerank` | Support natif |
| ollama | `/api/embeddings` | ❌ | Embedding seul, pas de reranking |

### llamacpp (models.ini)

Un seul serveur, un seul port, trois modèles. Le routeur swap automatiquement :

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

```bash
llama-server --host 127.0.0.1 --port 8000 --models-max 1 --models-preset models.ini
```

### vLLM (ton cluster DGX Spark)

```bash
vllm serve Qwen/Qwen3-Embedding-0.6B \
  --served-model-name Qwen3-Embedding-0.6B \
  --task embedding --port 8000 &

vllm serve Qwen/Qwen3-Reranker-0.6B \
  --served-model-name Qwen3-Reranker-0.6B \
  --task score --port 8001 &
```

## Points techniques critiques

### GGUF reranker : Voodisss uniquement

Les GGUF communautaires de Qwen3-Reranker sont **cassés** (llama.cpp #16407).
Il leur manque le tenseur `cls.output.weight` (classifieur yes/no),
le metadata `pooling_type=RANK` et le chat template de reranking.
Résultat : scores poubelles (`4.5e-23`).

Seuls les GGUF de [Voodisss](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp)
(convertis avec le `convert_hf_to_gguf.py` officiel) fonctionnent.

### Pooling

- Embedding : `pooling = last` (hidden state du token [EOS] final).
  Le blog officiel Qwen3 dit explicitement `last`. Le guide Voodisss dit `mean`.
  La doc officielle fait foi.
- Reranker : `pooling = rank` (obligatoire, active le classifieur).

### Host prompt cache

llama.cpp PR #16391 active par défaut un cache prompt de 8 GiB en RAM host.
Pour un serveur embedding/reranker où les prompts ne sont jamais réutilisés,
c'est du gaspillage pur. dvcdsys/code-index a documenté le problème en production :
RSS passe de 365 Mo à 11,3 Go → OOM kill. Avec `--cache-ram 0`, ça plafonne à ~900 Mo.

### Reranker candidates

18 candidats est le sweet spot stable sur CPU (~580ms/candidat, ~10s total).
Au-delà de 21, le reranker crash sur CPU (timeout ou saturation mémoire).
Sur GPU, 100 candidats prennent ~1s avec le 0.6B.

## Performance

| Métrique | RRF seul | Avec Reranker |
|----------|----------|---------------|
| Latence CPU | ~20 ms | ~10-18 s (18 candidats) |
| Latence GPU | ~3 ms | ~1 s (100 candidats) |
| RAM (stack complète) | ~1.7 Go | ~1.7 Go |
| Précision (NDCG@10) | baseline | +12 pts |

## Modèles utilisés

| Modèle | Quant | Taille | Rôle |
|--------|-------|--------|------|
| Qwen3-Embedding-0.6B | Q8_0 | 610 Mo | Embedding (bi-encoder) |
| Qwen3-Reranker-0.6B | Q4_K_M | 379 Mo | Reranker (cross-encoder) |

Le Q4_K_M est le sweet spot officiel : 3× plus petit que F16, perte de 0.3%
(benchmark Voodisss, MTEB AskUbuntuDupQuestions).

## Pourquoi c'est pertinent pour OpenFox

1. **Différenciation** : peu de harnais LLM locaux offrent un RAG intégré
2. **Alignement écosystème** : llama.cpp + Qwen3, mêmes technos qu'OpenFox
3. **Zéro friction** : MCP optionnel, désactivé par défaut, même backend
4. **Multi-utilisateurs** : avec vLLM sur ton DGX Spark, le RAG bénéficie
   du batching natif et des sessions concurrentes
5. **Confidentialité** : 100% local, aucune donnée ne quitte la machine
6. **Pattern existant** : exactement le même mécanisme que Brave Search
   (MCP configuré dans Settings > Tools)

## Évolution possible : extension de l'API plugin

À plus long terme, il serait propre d'étendre `ProviderPluginRegistry`
pour supporter les tools :

```typescript
// Actuel
registry.registerAuth(auth)
registry.registerTransport(transport)
registry.registerPreset(preset)

// Proposition
registry.registerTool(tool)  // ← nouveau
```

Cela permettrait d'intégrer le RAG comme un vrai plugin OpenFox
(avec UI de config dans Settings > RAG) plutôt que comme un MCP externe.
Je peux ouvrir une PR séparée pour cette extension si ça t'intéresse.

## Ce que je propose de faire

1. Le serveur MCP est en cours de développement :
   https://github.com/cried-nutty-won/openfox-rag
2. J'implémente le code complet (chunker, embedder, reranker, BM25, RRF, cache)
3. Je fournis un workflow custom "research-then-build" en exemple
4. Si tu veux l'extension `registry.registerTool()`, j'ouvre une PR séparée

Le serveur RAG Python standalone (https://github.com/cried-nutty-won/rag-system)
peut aussi servir de dépendance externe si tu préfères que le MCP
soit un simple proxy vers un serveur séparé.

## Références

- [openfox-rag](https://github.com/cried-nutty-won/openfox-rag) — serveur MCP RAG (Node.js)
- [rag-system](https://github.com/cried-nutty-won/rag-system) — implémentation de référence (Python)
- [Qwen3 Embedding](https://qwenlm.github.io/blog/qwen3-embedding/) — doc officielle
- [Voodisss GGUF](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) — GGUF reranker fonctionnels
- [Guide Voodisss multi-modèles](https://gist.github.com/VooDisss/42bce4eb5c76d3c325633886c5e348ee) — models.ini
- [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407) — GGUF reranker cassés
- [llama.cpp PR #16391](https://github.com/ggml-org/llama.cpp/pull/16391) — host prompt cache
- Dave Ebbelaar, "Hybrid Retrieval from Scratch" (2026) — méthodologie

Dis-moi si ça t'intéresse et je fais le PR.
```

---

### Différences avec la version précédente

| Aspect | Version précédente | Version réécrite |
|---|---|---|
| Mécanisme | Plugin OpenFox (`tools` + `settings` dans l'export) | **Serveur MCP** (pattern Brave Search) |
| Justification | Aucune | Analyse du code : `ProviderPluginRegistry` ne supporte que les providers |
| Configuration | Settings > RAG (UI custom) | Settings > Tools > MCP (existant) |
| Modification OpenFox | Implicite (nécessitait `registerTool`) | **Zéro** (MCP natif) |
| Évolution | Non mentionnée | Proposition d'extension `registry.registerTool()` en PR séparée |
| Repo openfox-rag | Plugin Node.js | **Serveur MCP** Node.js |
