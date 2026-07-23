# Guide d'intégration du RAG dans OpenFox

Ce guide explique comment connecter le système RAG ([rag-system](https://github.com/cried-nutty-won/rag-system)) à OpenFox pour que l'agent puisse consulter la base de connaissances locale de manière autonome.

## Principe

Le RAG est un service indépendant. OpenFox n'a besoin d'aucun plugin, d'aucun MCP, d'aucun processus supplémentaire. L'agent utilise son **terminal intégré** pour contrôler la stack RAG via 10 raccourcis fish.

```
Agent OpenFox
    │
    └──→ Terminal intégré
              │
              ├──→ rc              → "Les services sont-ils actifs ?"
              ├──→ llmers          → "Démarre la stack complète"
              ├──→ ragr void "q"   → "Cherche avec reranker"
              ├──→ rag void "q"    → "Cherche rapidement"
              ├──→ rst             → "Montre les logs"
              └──→ rsk             → "Arrête le serveur"
```

## Méthode 1 : General Instructions (recommandé)

La méthode la plus simple. Fonctionne immédiatement, sans fichier supplémentaire.

### Étapes

1. Ouvrir OpenFox
2. Aller dans **Settings > General Instructions**
3. Ajouter le texte suivant :

```
Tu as accès à un système RAG local pour consulter la base de connaissances
de l'utilisateur (notes Obsidian, documentation technique, procédures).

Commandes disponibles dans le terminal :

| Commande | Action |
|----------|--------|
| llmers | Démarrer la stack complète (embedding + reranker + RAG) |
| llmes | Démarrer embedding + RAG (sans reranker) |
| llme | Démarrer l'embedding seul |
| llmr | Démarrer le reranker seul |
| rs | Démarrer le serveur RAG seul |
| rst | Tail -f des logs RAG |
| rag <vault> "<requête>" | Recherche RRF seule (rapide, ~20ms) |
| ragr <vault> "<requête>" | Recherche RRF + reranker (précis, ~10-18s) |
| rc | Health check de tous les services |
| rsk | Tuer le serveur RAG |

Vaults disponibles : void, linux, browsing, terminal, llm, images,
telephone, obsidian (tous les vaults Obsidian), all (tous les vaults).

Protocole avant de coder :
1. Exécute rc pour vérifier que les services sont actifs
2. Si les services sont arrêtés, exécute llmers et attends 10 secondes
3. Exécute ragr <vault> "<requête pertinente>" pour chercher dans la doc
4. Utilise les passages retournés comme contexte pour ta réponse
5. Cite toujours le fichier source

Quand utiliser :
- L'utilisateur pose une question sur ses notes ou sa documentation
- Tu dois vérifier une référence technique avant de coder
- Tu écris du code de configuration (nftables, dracut, sfdisk, etc.)
- L'utilisateur dit "cherche dans mes notes", "regarde dans ma doc"

Quand ne PAS utiliser :
- La réponse est dans le code du projet actuel
- C'est une question de connaissance générale
- L'utilisateur dit explicitement de ne pas chercher
```

4. Redémarrer OpenFox

### Vérification

Dans une session OpenFox, demander :

```
Cherche dans mes notes comment configurer nftables
```

L'agent doit :
1. Exécuter `rc` dans le terminal
2. Si nécessaire, exécuter `llmers`
3. Exécuter `ragr linux "nftables configuration"`
4. Lire la sortie et répondre en citant les sources

## Méthode 2 : Fichier skill

Pour une intégration plus structurée, avec un fichier dédié.

### Étapes

1. Copier le fichier skill :

```bash
mkdir -p ~/.config/openfox/skills
cp /path/to/openfox-rag/skills/rag-search.md ~/.config/openfox/skills/
```

2. Dans OpenFox, aller dans **Settings > Skills**
3. Pointer vers le dossier `~/.config/openfox/skills/`
4. Redémarrer OpenFox

Le skill apparaît automatiquement dans le contexte de l'agent.

### Contenu du skill

Voir [`skills/rag-search.md`](../skills/rag-search.md) pour le contenu complet.

## Méthode 3 : AGENTS.md (par projet)

Pour une intégration par projet, sans modifier la configuration globale d'OpenFox.

### Étapes

1. Créer ou éditer le fichier `AGENTS.md` à la racine du projet :

```markdown
# AGENTS.md

## Base de connaissances locale

Un serveur RAG tourne sur cette machine. Il permet de chercher dans les
notes Obsidian, la documentation technique et les procédures de l'utilisateur.

### Commandes

| Commande | Action |
|----------|--------|
| rc | Vérifier que les services RAG sont actifs |
| llmers | Démarrer la stack complète si arrêtée |
| ragr <vault> "<requête>" | Recherche précise (avec reranker) |
| rag <vault> "<requête>" | Recherche rapide (RRF seul) |
| rsk | Arrêter le serveur RAG |

### Vaults

void, linux, browsing, terminal, llm, images, telephone, obsidian, all

### Protocole

Avant de coder, consulte la base de connaissances :

```bash
rc
ragr obsidian "ta requête"
```

Utilise les passages retournés comme contexte. Cite toujours le fichier source.
```

2. Ouvrir le projet dans OpenFox
3. L'agent lit automatiquement `AGENTS.md` au démarrage de la session

## Configuration du serveur RAG

Le serveur RAG doit être installé et configuré avant utilisation.
Voir [rag-system](https://github.com/cried-nutty-won/rag-system) pour les instructions complètes.

### Résumé rapide

```bash
# 1. Cloner et configurer
git clone https://github.com/cried-nutty-won/rag-system.git
cd rag-system
cp config.sh.example config.sh
# Éditer config.sh avec vos chemins

# 2. Installer les dépendances Python
python3 -m venv ~/.venv/main
~/.venv/main/bin/pip install numpy requests rank_bm25

# 3. Télécharger les modèles
mkdir -p $GGUF_DIR
huggingface-cli download Qwen/Qwen3-Embedding-0.6B-GGUF \
  Qwen3-Embedding-0.6B-Q8_0.gguf --local-dir $GGUF_DIR
huggingface-cli download Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp \
  Qwen3-Reranker-0.6B-Q4_K_M.gguf --local-dir $GGUF_DIR

# 4. Configurer les alias fish
# Ajouter dans ~/.config/fish/config.fish :
alias llmers='bash /path/to/rag-system/llama/start-rag-llm_embed_reranker_server.sh &'
alias llmes='bash /path/to/rag-system/llama/start-rag-llm_embed_server.sh &'
alias llme='bash /path/to/rag-system/llama/start-llm-embed-qwen3-06b.sh &'
alias llmr='bash /path/to/rag-system/llama/start-llm-reranker-06b.sh &'
alias rs='bash /path/to/rag-system/server/rag_server_rerank.py &'
alias rst='tail -f /tmp/rag_server_rerank.log'
alias rag='bash /path/to/rag-system/server/search_vault.sh --no-rerank'
alias ragr='bash /path/to/rag-system/server/search_vault.sh'
alias rc='curl -s http://127.0.0.1:8182/health | jq .'
alias rsk='pkill -f rag_server_rerank'

# 5. Premier lancement
llmers
# Attendre l'indexation (~5-15 min)
rc
```

### Backend LLM partagé (optionnel)

Les modèles d'embedding et de reranking peuvent être servis par le même
backend que le LLM de chat. Voir [`presets/models-llamacpp.ini`](../presets/models-llamacpp.ini).

```bash
llama-server --host 127.0.0.1 --port 8000 --models-max 1 --models-preset models.ini
```

## Dépannage

| Problème | Solution |
|----------|----------|
| `rc` ne répond pas | Exécuter `llmers` et attendre 10s |
| `llmers` échoue | Vérifier que les alias fish sont configurés |
| Recherche sans résultats | Essayer un autre vault ou une requête plus large |
| Reranker timeout | Utiliser `rag` au lieu de `ragr` (RRF seul) |
| Port déjà occupé | `rsk` puis `rs`, ou `pkill -f llama-server` puis `llmers` |
| Logs | `rst` |
| Scores reranker ~1e-28 | Mauvais GGUF. Retélécharger depuis [Voodisss](https://huggingface.co/Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp) |
| OOM au démarrage | Ajouter `--cache-ram 0` aux scripts llama-server |

## Comparaison des méthodes

| Méthode | Portée | Fichier | Complexité |
|---------|--------|---------|------------|
| General Instructions | Global (tous les projets) | Aucun | Minimal |
| Fichier skill | Global (tous les projets) | `skills/rag-search.md` | Faible |
| AGENTS.md | Par projet | `AGENTS.md` à la racine | Faible |

**Recommandation** : General Instructions pour un usage personnel, AGENTS.md pour un projet partagé en équipe.
