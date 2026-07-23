# openfox-rag

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Intégration RAG pour [OpenFox](https://github.com/openfox/openfox). Un fichier skill qui apprend à l'agent OpenFox à rechercher dans une base de connaissances locale (vaults Obsidian, documentation technique, procédures) via un pipeline de retrieval hybride : **BM25 + Vectoriel → RRF → Reranker cross-encoder**.

Pas de MCP, pas de plugin, pas de processus supplémentaire. Le serveur RAG tourne indépendamment ([rag-system](https://github.com/cried-nutty-won/rag-system)), et l'agent le contrôle entièrement via son terminal intégré avec 10 raccourcis fish.

## Pourquoi

| Sans RAG | Avec openfox-rag |
|----------|-----------------|
| L'agent hallucine ou demande à l'utilisateur de coller la doc | L'agent cherche lui-même dans la base de connaissances |
| Corpus entier injecté dans le contexte (milliers de tokens) | 5-10 chunks pertinents (~2000 tokens) |
| Calcul maximal à chaque requête | Calcul proportionnel à la pertinence réelle |
| Dépend souvent d'APIs cloud | 100% local, aucune donnée ne quitte la machine |

## Fonctionnement

```
Agent OpenFox
    │
    ├──→ Terminal intégré
    │         │
    │         ├──→ rc          (health check)
    │         ├──→ llmers      (démarrer la stack complète)
    │         ├──→ ragr void "requête"   (recherche avec reranker)
    │         ├──→ rag void "requête"    (recherche RRF seule)
    │         ├──→ rst         (tail des logs)
    │         └──→ rsk         (arrêter le serveur)
    │
    └──→ Fichier skill (skills/rag-search.md)
              └──→ Indique à l'agent quand et comment utiliser chaque commande
```

**Zéro processus supplémentaire côté OpenFox.** Le serveur RAG est un service séparé et indépendant. L'agent le démarre, le consulte, le surveille et l'arrête — tout depuis le terminal, exactement comme n'importe quel outil en ligne de commande.

## Commandes

| Commande | Action |
|----------|--------|
| `llmers` | Démarrer la stack complète (embedding + reranker + serveur RAG) |
| `llmes` | Démarrer embedding + serveur RAG (sans reranker) |
| `llme` | Démarrer l'embedding seul (port 8181) |
| `llmr` | Démarrer le reranker seul (port 8184) |
| `rs` | Démarrer le serveur RAG Python seul (port 8182) |
| `rst` | Tail -f des logs du serveur RAG |
| `rag <vault> "<requête>"` | Recherche RRF seule (rapide, ~20ms) |
| `ragr <vault> "<requête>"` | Recherche RRF + reranker (précis, ~10-18s) |
| `rc` | Health check des 3 services |
| `rsk` | Tuer le serveur RAG Python |

## Vaults

`void` · `linux` · `browsing` · `terminal` · `llm` · `images` · `telephone` · `obsidian` · `all`

- `obsidian` : tous les vaults Obsidian
- `all` : tous les vaults (Obsidian + externes)

## Installation

### 1. Installer le serveur RAG

Voir [rag-system](https://github.com/cried-nutty-won/rag-system) pour les instructions complètes.

```bash
git clone https://github.com/cried-nutty-won/rag-system.git
cd rag-system
cp config.sh.example config.sh
# Éditer config.sh avec vos chemins
```

### 2. Ajouter le skill à OpenFox

**Option A : General Instructions (le plus simple)**

Dans OpenFox, aller dans Settings > General Instructions et ajouter :

```
Tu as accès à un système RAG local. Utilise ces commandes dans le terminal :

| Commande | Action |
|----------|--------|
| llmers | Démarrer la stack complète (embedding + reranker + RAG) |
| llmes | Démarrer embedding + RAG (sans reranker) |
| llme | Démarrer l'embedding seul |
| llmr | Démarrer le reranker seul |
| rs | Démarrer le serveur RAG seul |
| rst | Tail -f des logs RAG |
| rag <vault> "<requête>" | Recherche RRF seule (rapide) |
| ragr <vault> "<requête>" | Recherche RRF + reranker (précis) |
| rc | Health check de tous les services |
| rsk | Tuer le serveur RAG |

Avant de coder, consulte toujours la base de connaissances :
rc
ragr obsidian "ta requête"
```

**Option B : Fichier skill**

```bash
cp skills/rag-search.md ~/.config/openfox/skills/
```

Puis dans OpenFox, aller dans Settings > Skills et pointer vers le dossier.

**Option C : AGENTS.md (par projet)**

Ajouter le tableau de commandes et les instructions de recherche dans le fichier `AGENTS.md` du projet.

### 3. Aucun prérequis nécessaire

L'agent contrôle l'intégralité de la stack RAG de manière autonome via le terminal.
Il vérifie la santé (`rc`), démarre la stack (`llmers`), recherche (`rag`/`ragr`),
surveille les logs (`rst`) et arrête les services (`rsk`) — tout seul.

## Configuration du backend

Les modèles d'embedding et de reranking peuvent être servis par le même backend que le LLM de chat, ou par des instances llama-server séparées. Voir [`presets/models-llamacpp.ini`](presets/models-llamacpp.ini) pour une configuration prête à l'emploi.

### Sélection des modèles

| Matériel | Embedding | Reranker | Pourquoi |
|----------|-----------|----------|----------|
| CPU uniquement (8 Go RAM) | 0.6B Q8_0 | 0.6B Q4_K_M | Tient en RAM, latence interactive |
| GPU (6+ Go VRAM) | 4B Q4_K_M | 4B Q4_K_M | Meilleure qualité, ~3s pour 100 candidats |
| GPU (24+ Go VRAM) | 4B F16 | 4B F16 | Qualité maximale, aucune perte de quantification |

### Modèles GGUF

| Modèle | Quant | Taille | Matériel | MTEB |
|--------|-------|--------|----------|------|
| Qwen3-Embedding-0.6B | Q8_0 | 610 Mo | CPU ou GPU | 64.33 |
| Qwen3-Embedding-4B | Q4_K_M | 2.4 Go | GPU recommandé | 69.45 |
| Qwen3-Reranker-0.6B | Q4_K_M | 379 Mo | CPU ou GPU | 65.80 |
| Qwen3-Reranker-4B | Q4_K_M | 2.4 Go | GPU recommandé | 69.76 |

- Embedding : [Qwen/Qwen3-Embedding-0.6B-GGUF](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF) ou [Qwen/Qwen3-Embedding-4B-GGUF](https://huggingface.co/Qwen/Qwen3-Embedding-4B-GGUF) (officiel)
- Reranker : [Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) ou [Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp](https://huggingface.co/Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp) (**obligatoire** — les GGUF communautaires sont cassés, voir [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407))

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

## Intégration dans les workflows

### Étape de workflow custom

Ajouter une étape "Research" avant "Build" dans l'éditeur de workflows d'OpenFox :

```
[Research (RAG)] → [Build] → [Verify] → [Code Review] → [Summary]
```

### General Instructions

Ajouter dans vos General Instructions OpenFox :

```
Avant de coder, consulte toujours la base de connaissances locale via le terminal.
Exécute : rc
Puis : ragr obsidian "ta requête"
Utilise les passages retournés comme contexte. Cite toujours le fichier source.
```

## Performance

| Métrique | RRF seul | Avec Reranker (0.6B) | Avec Reranker (4B) |
|----------|----------|---------------------|-------------------|
| Latence (CPU) | ~20 ms | ~10-18 s (18 candidats) | ~30-40 s (trop lent) |
| Latence (GPU) | ~3 ms | ~1 s (100 candidats) | ~3 s (100 candidats) |
| RAM / VRAM | ~1.7 Go | ~1.7 Go | ~6 Go |
| Précision (NDCG@10) | baseline | +12 pts | +16 pts |

## Limites connues

- **GGUF Reranker** : Seuls les [GGUF Voodisss](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) fonctionnent. Les conversions communautaires sont cassées (tenseur `cls.output.weight` manquant). Voir [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407).
- **Cache prompt host** : llama.cpp [PR #16391](https://github.com/ggml-org/llama.cpp/pull/16391) active par défaut un cache prompt de 8 GiB en RAM host. Pour un serveur embedding/reranker où les prompts ne sont jamais réutilisés, ajouter `--cache-ram 0` pour éviter l'OOM.
- **Candidats reranker > 21 sur CPU** : Le reranker crash. 18 est le sweet spot stable.
- **Pas de hot-reload** : Modifier un fichier Obsidian nécessite de vider le cache + ré-indexer.
- **Cache orphelin** : Les chunks supprimés restent dans le cache JSON (pas de garbage collection).
- **L'agent doit parser la sortie** : L'agent lit la sortie de la commande et extrait les passages pertinents. Fonctionne bien avec les modèles ≥ 7B.

## Références

- [OpenFox](https://github.com/openfox/openfox) — harnais LLM local
- [rag-system](https://github.com/cried-nutty-won/rag-system) — serveur RAG standalone (Python)
- [Blog Qwen3 Embedding](https://qwenlm.github.io/blog/qwen3-embedding/) — documentation officielle
- [Guide Voodisss multi-modèles](https://gist.github.com/VooDisss/42bce4eb5c76d3c325633886c5e348ee) — référence models.ini llamacpp
- [GGUF Reranker Voodisss](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) — conversions GGUF fonctionnelles
- [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407) — pourquoi les GGUF reranker communautaires sont cassés
- [llama.cpp PR #16391](https://github.com/ggml-org/llama.cpp/pull/16391) — cache prompt host (défaut 8 GiB)
- Dave Ebbelaar, "Hybrid Retrieval from Scratch" (2026) — méthodologie

## Licence

[MIT](LICENSE) — cohérent avec l'écosystème OpenFox.
