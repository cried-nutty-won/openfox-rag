# openfox-rag   [(en)](README.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Intégration RAG pour [OpenFox](https://github.com/openfox/openfox). Un fichier skill qui permet à l'agent OpenFox avec un mini llm spécialisé en recherche documentaire de 0,6B
et un second mini llm de 0,6B spécialisé en classement, de chercher efficacement
dans la documentation locale: coffres Obsidian, docs techniques, manuels, procédures...
et ainsi gagner en tokens, en vitesse, en écomomie d'énergie, en qualité et en précision via un pipeline de retrieval hybride : **BM25 + Vectoriel → RRF → Reranker cross-encoder**.

Pas de MCP, pas de plugin, pas de processus supplémentaire. Le serveur RAG tourne indépendamment ([rag-system](https://github.com/cried-nutty-won/rag-system)), et l'agent le contrôle entièrement via son terminal intégré avec 10 raccourcis shell.

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
    │         ├──→ ragr void "requête"   (recherche précise)
    │         ├──→ rag void "requête"    (recherche rapide)
    │         ├──→ rst         (tail des logs)
    │         └──→ rsk         (arrêter le serveur)
    │
    └──→ Fichier skill (skills/rag-search.md)
              └──→ Indique à l'agent quand et comment utiliser chaque commande
```

**Zéro processus supplémentaire côté OpenFox.** Le serveur RAG est un service séparé et indépendant. L'agent le démarre, le consulte, le surveille et l'arrête — tout depuis le terminal, exactement comme n'importe quel outil en ligne de commande.

---
---

## Installation

```bash
mkdir -p ~/rag
git clone https://github.com/cried-nutty-won/openfox-rag.git ~/rag/openfox-rag
cd ~/rag/openfox-rag
bash install.sh
```

L'installateur :

- Détecte l'OS, la RAM, le GPU (NVIDIA, Apple Silicon, lspci)
- Détecte le shell (fish, bash, zsh, sh) et écrit les alias dans le bon fichier de config
- Propose les modèles 0.6B (défaut) ou 4B (GPU uniquement — masqués sur CPU)
- Télécharge les GGUF depuis Qwen officiel + Voodisss
- Clone et configure [rag-system](https://github.com/cried-nutty-won/rag-system)
- Scanne les vaults Obsidian et documentation (boucle interactive)
- Installe le skill OpenFox (`~/.config/openfox/skills/rag-search.md`)
- Affiche toutes les commandes et les chemins vers la doc à la fin

### Mode dry-run

Tester sans rien modifier :

```bash
bash install.sh --dry-run
```

---

## Commandes

| Commande | Action |
|----------|--------|
| `llmers` | Démarrer la stack complète (embedding + reranker + serveur RAG) |
| `llmes` | Démarrer embedding + serveur RAG (sans reranker) |
| `llme` | Démarrer l'embedding seul (port 8181) |
| `llmr` | Démarrer le reranker seul (port 8184) |
| `rs` | Démarrer le serveur RAG Python seul (port 8182) |
| `rst` | Tail -f des logs du serveur RAG |
| `rag <vault> "<requête>"` | Recherche rapide (~20ms) |
| `ragr <vault> "<requête>"` | Recherche lente et précise avec reranker (~10-18s CPU, ~1s GPU) |
| `rc` | Health check des 3 services |
| `rsk` | Tuer le serveur RAG Python |

## Vaults

Configurés de manière interactive pendant l'installation. Chaque vault a un nom court utilisé dans les commandes :

```bash
rag void "configuration nftables"         # recherche dans le vault "void"
ragr linux "hooks dracut"                  # recherche précise dans "linux"
ragr all "ta requête"                      # recherche dans tous les vaults
rag obsidian "ta requête"                  # recherche dans tous les vaults Obsidian
```

---

## Sélection des modèles

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

> **Note :** Les scores MTEB de l'embedding et du reranker ne sont **pas comparables** — ils évaluent des tâches différentes (récupération vectorielle vs. reclassement de paires). Le gain réel du reranker dans le pipeline est de **+12 points NDCG@10** (benchmark FinanceQA), pas la différence entre les deux scores MTEB ci-dessus.

- Embedding : [Qwen/Qwen3-Embedding-0.6B-GGUF](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF) ou [Qwen/Qwen3-Embedding-4B-GGUF](https://huggingface.co/Qwen/Qwen3-Embedding-4B-GGUF) (officiel)
- Reranker : [Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) ou [Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp](https://huggingface.co/Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp) (**obligatoire** — les GGUF communautaires sont cassés, voir [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407))

---

**MTEB** est le benchmark de référence pour évaluer la qualité des modèles d'embedding. Il mesure la capacité d'un modèle à produire des vecteurs qui capturent le sens du texte, à travers **8 types de tâches** :

| Tâche | Ce que ça mesure | Exemple |
|---|---|---|
| **Retrieval** | Retrouver le bon document parmi des milliers | "Quelle est la procédure nftables ?" → trouver le bon fichier |
| **Reranking** | Réordonner des candidats par pertinence | Classer 18 chunks du plus au moins pertinent |
| **Classification** | Catégoriser un texte | "Ce document parle-t-il de réseau ou de stockage ?" |
| **Clustering** | Regrouper des textes similaires | Regrouper les notes par thème |
| **STS** (Semantic Textual Similarity) | Mesurer la similarité entre deux phrases | "nftables firewall" ≈ "pare-feu nftables" |
| **Pair Classification** | Dire si deux textes sont liés | "Cette procédure correspond-elle à cette question ?" |
| **Bitext Mining** | Trouver la traduction correspondante | FR ↔ EN |
| **Summarization** | Évaluer la qualité d'un résumé | — |

### Pourquoi c'est pertinent pour le RAG

Le score MTEB **Retrieval** est le plus important pour le RAG : il mesure directement la capacité du modèle à retrouver le bon document. Plus le score est élevé, moins le RAG a besoin du reranker pour compenser.

| Modèle | MTEB Multilingual | MTEB Retrieval | Dimensions |
|---|---|---|---|
| Qwen3-Embedding-0.6B | 64.33 | 64.64 | 1024 |
| Qwen3-Embedding-4B | 69.45 | 69.60 | 2560 |
| Qwen3-Embedding-8B | 70.58 | 70.88 | 4096 |

Le 0.6B est suffisant pour un RAG local avec reranker. Le 4B apporte +5 points mais nécessite un GPU.

---

## Configuration du backend

Les modèles d'embedding et de reranking peuvent être servis par le même backend que le LLM de chat, ou par des instances llama-server séparées. Voir [`presets/models-llamacpp.ini`](presets/models-llamacpp.ini) pour une configuration prête à l'emploi.

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

> **Note sur le pooling** : Le [blog officiel Qwen3](https://qwenlm.github.io/blog/qwen3-embedding/) dit `last` (hidden state du token [EOS] final) pour l'embedding. Certains guides communautaires disent `mean`. La doc officielle fait foi : utiliser `last`.

### vLLM (cluster GPU)

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

### ollama (embedding uniquement)

Ollama ne supporte pas le reranking. Le serveur RAG bascule automatiquement en RRF pur (BM25 + vectoriel, sans reranker).

```bash
ollama pull qwen3-embedding:0.6b
```

```bash
# Configuration du serveur RAG pour ollama
export LLAMA_EMBED_URL="http://127.0.0.1:11434/api/embeddings"
# Pas d'URL de reranker — basculement automatique en RRF
```

### Résumé de compatibilité des backends

| Backend | Embedding | Reranking | Mode RAG |
|---|---|---|---|
| llamacpp | ✅ `POST /embedding` | ✅ `POST /v1/rerank` | Hybride + Reranker |
| vLLM | ✅ `POST /v1/embeddings` | ✅ `POST /v1/rerank` | Hybride + Reranker |
| sglang | ✅ `POST /v1/embeddings` | ✅ `POST /v1/rerank` | Hybride + Reranker |
| ollama | ✅ `POST /api/embeddings` | ❌ | Hybride (RRF uniquement) |

Le serveur RAG s'adapte automatiquement : si le reranker est injoignable, il bascule en RRF pur sans erreur.

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

| Métrique | Recherche rapide | Recherche précise (0.6B) | Recherche précise (4B) |
|----------|-----------------|-------------------------|------------------------|
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

- [OpenFox](https://github.com/openfox/openfox) — harnais LLM local (pour agents IA)
- [rag-system](https://github.com/cried-nutty-won/rag-system) — serveur RAG standalone (Python)
- [Blog Qwen3 Embedding](https://qwenlm.github.io/blog/qwen3-embedding/) — documentation officielle
- [Guide Voodisss multi-modèles](https://gist.github.com/VooDisss/42bce4eb5c76d3c325633886c5e348ee) — référence models.ini llamacpp
- [GGUF Reranker Voodisss](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) — conversions GGUF fonctionnelles
- [llama.cpp #16407](https://github.com/ggml-org/llama.cpp/issues/16407) — pourquoi les GGUF reranker communautaires sont cassés
- [llama.cpp PR #16391](https://github.com/ggml-org/llama.cpp/pull/16391) — cache prompt host (défaut 8 GiB)
- Dave Ebbelaar, "Hybrid Retrieval from Scratch" (2026) — méthodologie

## Système Recommandé

Void Linux avec niri desktop.
Faster boot, occupe seulement 1Go RAM, gestionnaire de packages rapide et complet.
Pas de system.d mais runit qui est plus léger, rapide et confidentiel. 
Excellent équilibre entre sécurité et fluidité.

## Licence

[MIT](LICENSE)
