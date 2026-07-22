# openfox-rag

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Serveur MCP pour [OpenFox](https://github.com/openfox/openfox). Expose un tool `rag_search` à l'agent OpenFox via le [Model Context Protocol](https://modelcontextprotocol.io), lui permettant de rechercher dans une base de connaissances locale (vaults Obsidian, documentation technique, procédures) via un pipeline de retrieval hybride : **BM25 + Vectoriel → RRF → Reranker cross-encoder**.

Configuré dans OpenFox via **Settings > Tools > MCP** — exactement comme Brave Search. Zéro modification du core OpenFox.

## Pourquoi

| Sans RAG | Avec openfox-rag |
|----------|-----------------|
| L'agent hallucine ou demande à l'utilisateur de coller la doc | L'agent cherche lui-même dans la base de connaissances |
| Corpus entier injecté dans le contexte (milliers de tokens) | 5-10 chunks pertinents (~2000 tokens) |
| Calcul maximal à chaque requête | Calcul proportionnel à la pertinence réelle |
| Dépend souvent d'APIs cloud | 100% local, aucune donnée ne quitte la machine |

## Architecture

```
Agent OpenFox
    │
    ├──→ Backend LLM (vLLM / llamacpp / sglang)
    │         ├──→ Modèle de chat (DeepSeek, Qwen3, etc.)
    │         ├──→ Qwen3-Embedding (0.6B ou 4B)  ← même backend
    │         └──→ Qwen3-Reranker (0.6B ou 4B)   ← même backend
    │
    └──→ Serveur MCP openfox-rag (ce repo)
              ├──→ POST /v1/embeddings  (même backend)
              ├──→ POST /v1/rerank      (même backend)
              ├──→ BM25 + RRF           (local, dans le serveur MCP)
              ├──→ Cache d'embeddings   (~/.config/openfox/rag-cache/)
              └──→ Tool rag_search      (visible par l'agent)
```

**Zéro processus supplémentaire.** L'embedding et le reranker sont servis par le même backend que le LLM de chat. Le serveur MCP gère la logique RAG (BM25, RRF, cache) en Node.js et appelle les endpoints du backend existant.

## Installation

### 1. Prérequis

- OpenFox installé (`npm i -g openfox`)
- Node.js >= 24
- Backend LLM avec support embedding + reranking :
  - **llamacpp** : `--models-preset models.ini` (voir [`presets/models-llamacpp.ini`](presets/models-llamacpp.ini))
  - **vLLM** : `--task embedding` + `--task score`
  - **sglang** : support embedding natif
- Modèles GGUF (choisir selon votre matériel) :

  | Modèle | Quant | Taille | Matériel | MTEB |
  |--------|-------|--------|----------|------|
  | Qwen3-Embedding-0.6B | Q8_0 | 610 Mo | CPU ou GPU | 64.33 |
  | Qwen3-Embedding-4B | Q4_K_M | 2.4 Go | GPU recommandé | 69.45 |
  | Qwen3-Reranker-0.6B | Q4_K_M | 379 Mo | CPU ou GPU | 65.80 |
  | Qwen3-Reranker-4B | Q4_K_M | 2.4 Go | GPU recommandé | 69.76 |

  - Embedding : [Qwen/Qwen3-Embedding-0.6B-GGUF](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF) ou [Qwen/Qwen3-Embedding-4B-GGUF](https://huggingface.co/Qwen/Qwen3-Embedding-4B-GGUF) (officiel)
  - Reranker : [Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) ou [Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp](https://huggingface.co/Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp) (**obligatoire** — les GGUF communautaires sont cassés, voir [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407))

### 2. Installer le serveur MCP

```bash
cd /chemin/vers/openfox-rag
npm install
```

### 3. Configurer dans OpenFox

Settings > Tools > MCP :

```json
{
  "mcpServers": {
    "rag": {
      "command": "node",
      "args": ["/chemin/vers/openfox-rag/mcp/server.js"],
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
        "RAG_VAULTS": "void:/chemin/vers/obsidian/001 Void 000,linux:/chemin/vers/obsidian/000 linux 000,llm:/chemin/vers/obsidian/004 llm 000"
      }
    }
  }
}
```

L'agent peut aussi le configurer lui-même : *"mets en place le MCP RAG"* — même pattern que Brave Search.

### 4. Référence de configuration

| Paramètre | Variable d'env | Défaut | Description |
|-----------|---------------|--------|-------------|
| Activer RAG | *(supprimer l'entrée MCP pour désactiver)* | — | Active/désactive le tool `rag_search` |
| URL du backend | `RAG_BACKEND_URL` | `http://localhost:8000` | URL du backend LLM (vLLM/llamacpp/sglang) |
| Modèle d'embedding | `RAG_EMBEDDING_MODEL` | `Qwen3-Embedding-0.6B` | Nom du modèle dans le backend |
| Modèle de reranking | `RAG_RERANKER_MODEL` | `Qwen3-Reranker-0.6B` | Nom du modèle dans le backend |
| Vault par défaut | `RAG_DEFAULT_VAULT` | `obsidian` | Vault par défaut pour les recherches |
| Top K | `RAG_TOP_K` | `5` | Nombre de résultats |
| Candidats reranker | `RAG_RERANK_CANDIDATES` | `18` | Candidats envoyés au reranker |
| Activer le reranker | `RAG_ENABLE_RERANKER` | `true` | Active le reranking cross-encoder |
| Ratio alpha | `RAG_ALPHA_RATIO` | `0.36` | Seuil de filtrage des chunks |
| Répertoire de cache | `RAG_CACHE_DIR` | `~/.config/openfox/rag-cache/` | Emplacement du cache d'embeddings |
| Vaults | `RAG_VAULTS` | *(vide)* | Paires `nom:/chemin` séparées par des virgules |

### 5. Ajouter des vaults

Les vaults sont configurés via la variable d'environnement `RAG_VAULTS` :

```
RAG_VAULTS=void:/chemin/vers/obsidian/001 Void 000,linux:/chemin/vers/obsidian/000 linux 000,llm:/chemin/vers/obsidian/004 llm 000
```

| Nom | Chemin |
|-----|--------|
| void | `/chemin/vers/obsidian/001 Void 000` |
| linux | `/chemin/vers/obsidian/000 linux 000` |
| llm | `/chemin/vers/obsidian/004 llm 000` |

Périmètres spéciaux :
- `obsidian` : tous les vaults Obsidian configurés
- `all` : tous les vaults (Obsidian + externes)

### 6. Redémarrer OpenFox

Le tool `rag_search` apparaît automatiquement dans la liste des tools de l'agent.

## Configuration du backend

### llamacpp (models.ini)

Un seul serveur, un seul port, trois modèles. Le routeur swap les modèles en VRAM à la demande.

#### Modèles 0.6B (CPU, ~1 Go total)

```ini
[*]
n-gpu-layers = all
batch-size = 2048
ubatch-size = 2048
load-on-startup = Qwen3-Embedding-0.6B

[Qwen3-Embedding-0.6B]
model = /chemin/vers/Qwen3-Embedding-0.6B-Q8_0.gguf
embedding = true
pooling = last
ctx-size = 8192

[Qwen3-Reranker-0.6B]
model = /chemin/vers/Qwen3-Reranker-0.6B-Q4_K_M.gguf
reranking = true
pooling = rank
embedding = true
ctx-size = 1024

[deepseek-v4-flash]
model = /chemin/vers/DeepSeek-V4-Flash.gguf
ctx-size = 32768
```

#### Modèles 4B (GPU recommandé, ~5 Go total)

```ini
[*]
n-gpu-layers = all
batch-size = 2048
ubatch-size = 2048
load-on-startup = Qwen3-Embedding-4B

[Qwen3-Embedding-4B]
model = /chemin/vers/Qwen3-Embedding-4B-Q4_K_M.gguf
embedding = true
pooling = last
ctx-size = 32768

[Qwen3-Reranker-4B]
model = /chemin/vers/Qwen3-Reranker-4B-Q4_K_M.gguf
reranking = true
pooling = rank
embedding = true
ctx-size = 32768

[deepseek-v4-flash]
model = /chemin/vers/DeepSeek-V4-Flash.gguf
ctx-size = 32768
```

```bash
llama-server --host 127.0.0.1 --port 8000 --models-max 1 --models-preset models.ini
```

> **Note sur le pooling** : Le [blog officiel Qwen3](https://qwenlm.github.io/blog/qwen3-embedding/) dit `last` (hidden state du token [EOS] final) pour l'embedding. Le [guide Voodisss](https://gist.github.com/VooDisss/42bce4eb5c76d3c325633886c5e348ee) dit `mean`. La doc officielle fait foi : utiliser `last`.

### vLLM (cluster GPU)

#### Modèles 0.6B

```bash
vllm serve Qwen/Qwen3-Embedding-0.6B \
  --served-model-name Qwen3-Embedding-0.6B \
  --task embedding --port 8000 &

vllm serve Qwen/Qwen3-Reranker-0.6B \
  --served-model-name Qwen3-Reranker-0.6B \
  --task score --port 8001 &
```

#### Modèles 4B

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

## Tool exposé à l'agent

```json
{
  "name": "rag_search",
  "description": "Recherche dans la base de connaissances locale (notes Obsidian, documentation technique, procédures). À utiliser quand l'utilisateur pose une question sur ses notes, sa documentation, ou quand tu as besoin de vérifier une référence technique avant de coder.",
  "parameters": {
    "query": "string — requête de recherche en langage naturel",
    "vault": "string — obsidian | all | void | linux | llm | terminal",
    "top_k": "integer — nombre de résultats (défaut: 5)",
    "rerank": "boolean — activer le reranker (défaut: true)"
  }
}
```

## Intégration dans les workflows

### Étape de workflow custom

Ajouter une étape "Research" avant "Build" dans l'éditeur de workflows d'OpenFox :

```
[Research (RAG)] → [Build] → [Verify] → [Code Review] → [Summary]
```

### General Instructions

Ajouter dans vos General Instructions OpenFox :

```
Avant de coder, consulte toujours la base de connaissances locale
via rag_search pour vérifier les procédures et références techniques.
```

## Serveur RAG standalone (alternative)

Si vous préférez un serveur RAG Python séparé (BM25 + vectoriel + RRF + reranker) plutôt que le serveur MCP intégré :

**[rag-system](https://github.com/cried-nutty-won/rag-system)** — implémentation de référence complète avec documentation.

Le serveur MCP peut aussi fonctionner en **mode proxy** en pointant `RAG_BACKEND_URL` vers `http://127.0.0.1:8182`. Dans ce mode, le serveur MCP forward toutes les requêtes de recherche vers le serveur RAG Python, qui gère l'embedding, le BM25, le RRF et le reranking en interne.

## Performance

| Métrique | RRF seul | Avec Reranker (0.6B) | Avec Reranker (4B) |
|----------|----------|---------------------|-------------------|
| Latence (CPU) | ~20 ms | ~10-18 s (18 candidats) | ~30-40 s (trop lent) |
| Latence (GPU) | ~3 ms | ~1 s (100 candidats) | ~3 s (100 candidats) |
| RAM / VRAM | ~1.7 Go | ~1.7 Go | ~6 Go |
| Précision (NDCG@10) | baseline | +12 pts | +16 pts |

### Guide de sélection des modèles

| Matériel | Embedding | Reranker | Pourquoi |
|----------|-----------|----------|----------|
| CPU uniquement (8 Go RAM) | 0.6B Q8_0 | 0.6B Q4_K_M | Tient en RAM, latence interactive |
| GPU (6+ Go VRAM) | 4B Q4_K_M | 4B Q4_K_M | Meilleure qualité, ~3s pour 100 candidats |
| GPU (24+ Go VRAM) | 4B F16 | 4B F16 | Qualité maximale, aucune perte de quantification |

## Limites connues

- **GGUF Reranker** : Seuls les [GGUF Voodisss](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) fonctionnent. Les conversions communautaires sont cassées (tenseur `cls.output.weight` manquant). Voir [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407).
- **Cache prompt host** : llama.cpp [PR #16391](https://github.com/ggml-org/llama.cpp/pull/16391) active par défaut un cache prompt de 8 GiB en RAM host. Pour un serveur embedding/reranker où les prompts ne sont jamais réutilisés, ajouter `--cache-ram 0` pour éviter l'OOM.
- **Candidats reranker > 21 sur CPU** : Le reranker crash. 18 est le sweet spot stable.
- **Pas de hot-reload** : Modifier un fichier Obsidian nécessite de vider le cache + ré-indexer.
- **Cache orphelin** : Les chunks supprimés restent dans le cache JSON (pas de garbage collection).

## Références

- [OpenFox](https://github.com/openfox/openfox) — harnais LLM local
- [rag-system](https://github.com/cried-nutty-won/rag-system) — implémentation de référence standalone (Python)
- [Blog Qwen3 Embedding](https://qwenlm.github.io/blog/qwen3-embedding/) — documentation officielle
- [Guide Voodisss multi-modèles](https://gist.github.com/VooDisss/42bce4eb5c76d3c325633886c5e348ee) — référence models.ini llamacpp
- [GGUF Reranker Voodisss](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) — conversions GGUF fonctionnelles
- [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407) — pourquoi les GGUF reranker communautaires sont cassés
- [llama.cpp PR #16391](https://github.com/ggml-org/llama.cpp/pull/16391) — cache prompt host (défaut 8 GiB)
- Dave Ebbelaar, "Hybrid Retrieval from Scratch" (2026) — méthodologie

## Licence

[MIT](LICENSE) — cohérent avec l'écosystème OpenFox.
