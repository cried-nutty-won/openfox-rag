#!/usr/bin/env bash
# openfox-rag — Interactive RAG installer
# Installs rag-system + configures shell aliases + OpenFox skill
# Usage: bash install.sh

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
header()  { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}\n"; }

# ── Dry-run mode ────────────────────────────────────────────
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n)
            DRY_RUN=true
            ;;
    esac
done

run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} $*"
    else
        "$@"
    fi
}

run_write() {
    local file="$1"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} Would write to: ${file}"
    else
        cat > "$file"
    fi
}

# ── Helpers ─────────────────────────────────────────────────
ask() {
    local prompt="$1" default="$2" var_name="$3"
    echo -e "${BOLD}${prompt}${NC}"
    echo -e "  ${CYAN}Default: ${default}${NC}"
    read -rp "  > " answer
    answer="${answer:-$default}"
    eval "$var_name=\"$answer\""
}

ask_yes_no() {
    local prompt="$1" default="$2" var_name="$3"
    echo -e "${BOLD}${prompt}${NC} ${CYAN}[${default}]${NC}"
    read -rp "  > " answer
    answer="${answer:-$default}"
    if [[ "$answer" =~ ^[Yy] ]]; then
        eval "$var_name=true"
    else
        eval "$var_name=false"
    fi
}

check_command() {
    command -v "$1" &>/dev/null
}

# ── Shell detection ─────────────────────────────────────────
detect_shell() {
    local shell_name
    shell_name="$(basename "${SHELL:-/bin/bash}")"

    case "$shell_name" in
        fish)
            SHELL_NAME="fish"
            SHELL_CONFIG="${HOME}/.config/fish/config.fish"
            SHELL_CONFIG_DIR="${HOME}/.config/fish"
            ;;
        zsh)
            SHELL_NAME="zsh"
            SHELL_CONFIG="${HOME}/.zshrc"
            SHELL_CONFIG_DIR="${HOME}"
            ;;
        bash)
            SHELL_NAME="bash"
            if [[ -f "${HOME}/.bashrc" ]]; then
                SHELL_CONFIG="${HOME}/.bashrc"
            elif [[ -f "${HOME}/.bash_profile" ]]; then
                SHELL_CONFIG="${HOME}/.bash_profile"
            else
                SHELL_CONFIG="${HOME}/.bashrc"
            fi
            SHELL_CONFIG_DIR="${HOME}"
            ;;
        sh|dash|ash)
            SHELL_NAME="sh"
            SHELL_CONFIG="${HOME}/.profile"
            SHELL_CONFIG_DIR="${HOME}"
            ;;
        *)
            SHELL_NAME="$shell_name"
            SHELL_CONFIG="${HOME}/.${shell_name}rc"
            SHELL_CONFIG_DIR="${HOME}"
            ;;
    esac
}

# ── Banner ──────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║         openfox-rag — RAG Installer             ║"
echo "  ║   Hybrid Retrieval for OpenFox (local LLM)      ║"
echo "  ║   BM25 + Vector → RRF → Cross-encoder Reranker  ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  This script will install and configure:"
echo -e "    • rag-system server (Python + llama.cpp)"
echo -e "    • Qwen3 embedding + reranker models (GGUF)"
echo -e "    • Shell aliases (10 shortcuts)"
echo -e "    • OpenFox skill (rag-search.skill.md)"
echo ""

# ── Check repo location ────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPECTED_DIR="${HOME}/rag/openfox-rag"
if [[ "$SCRIPT_DIR" != "$EXPECTED_DIR" ]]; then
    warn "openfox-rag is at: ${SCRIPT_DIR}"
    warn "Expected location:  ${EXPECTED_DIR}"
    ask_yes_no "Move to ${EXPECTED_DIR}?" "y" MOVE_REPO
    if [[ "$MOVE_REPO" == true ]]; then
        run mkdir -p "${HOME}/rag"
        run mv "$SCRIPT_DIR" "$EXPECTED_DIR"
        success "Moved to ${EXPECTED_DIR}"
        exec "${EXPECTED_DIR}/install.sh" "$@"
    fi
fi

# ── Step 1: System detection ───────────────────────────────
header "Step 1/10: System detection"

# OS
OS="$(uname -s)"
ARCH="$(uname -m)"
info "OS: ${OS} (${ARCH})"

# Shell
detect_shell
success "Shell detected: ${SHELL_NAME} → ${SHELL_CONFIG}"

# RAM
if [[ "$OS" == "Linux" ]]; then
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
elif [[ "$OS" == "Darwin" ]]; then
    TOTAL_RAM_MB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
else
    TOTAL_RAM_MB=8192
    warn "Unknown OS, assuming 8 GB RAM"
fi
TOTAL_RAM_GB=$(( TOTAL_RAM_MB / 1024 ))
info "RAM: ${TOTAL_RAM_GB} GB (${TOTAL_RAM_MB} MB)"

# GPU detection
HAS_GPU=false
GPU_NAME=""
GPU_VRAM_MB=0

if check_command nvidia-smi; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "")
    GPU_VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
    if [[ -n "$GPU_NAME" ]]; then
        HAS_GPU=true
        success "GPU detected: ${GPU_NAME} (${GPU_VRAM_MB} MB VRAM)"
    fi
elif [[ "$OS" == "Darwin" ]] && [[ "$ARCH" == "arm64" ]]; then
    HAS_GPU=true
    GPU_NAME="Apple Silicon (Metal)"
    GPU_VRAM_MB=$TOTAL_RAM_MB
    success "GPU detected: ${GPU_NAME} (unified memory: ${TOTAL_RAM_GB} GB)"
elif check_command lspci; then
    if lspci 2>/dev/null | grep -qiE 'vga|3d|display'; then
        GPU_NAME=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -1 | sed 's/.*: //')
        HAS_GPU=true
        warn "GPU detected via lspci: ${GPU_NAME} (VRAM unknown)"
    fi
fi

if [[ "$HAS_GPU" == false ]]; then
    warn "No GPU detected — CPU-only mode"
    warn "4B models will NOT be offered (too slow on CPU)"
fi

# Model selection
if [[ "$HAS_GPU" == true ]]; then
    echo ""
    echo -e "${BOLD}Model selection:${NC}"
    echo -e "  ${GREEN}1) 0.6B models (recommended)${NC} — ~1 GB RAM, fast on CPU and GPU"
    echo -e "  ${CYAN}2) 4B models (GPU only)${NC}    — ~6 GB VRAM, best quality"
    echo ""
    read -rp "  Choose [1]: " model_choice
    model_choice="${model_choice:-1}"
else
    model_choice="1"
    info "0.6B models selected (CPU-only configuration)"
fi

if [[ "$model_choice" == "2" ]]; then
    EMBED_MODEL="Qwen3-Embedding-4B-Q4_K_M"
    EMBED_HF="Qwen/Qwen3-Embedding-4B-GGUF"
    EMBED_FILE="Qwen3-Embedding-4B-Q4_K_M.gguf"
    EMBED_SIZE="2.4 GB"
    RERANK_MODEL="Qwen3-Reranker-4B-Q4_K_M"
    RERANK_HF="Voodisss/Qwen3-Reranker-4B-GGUF-llama_cpp"
    RERANK_FILE="Qwen3-Reranker-4B-Q4_K_M.gguf"
    RERANK_SIZE="2.4 GB"
    EMBED_CTX=32768
    EMBED_DIM=2560
    MODEL_ID="qwen3-embed-4b"
    success "4B models selected (embedding: ${EMBED_SIZE}, reranker: ${RERANK_SIZE})"
else
    EMBED_MODEL="Qwen3-Embedding-0.6B-Q8_0"
    EMBED_HF="Qwen/Qwen3-Embedding-0.6B-GGUF"
    EMBED_FILE="Qwen3-Embedding-0.6B-Q8_0.gguf"
    EMBED_SIZE="610 MB"
    RERANK_MODEL="Qwen3-Reranker-0.6B-Q4_K_M"
    RERANK_HF="Voodisss/Qwen3-Reranker-0.6B-GGUF-llama_cpp"
    RERANK_FILE="Qwen3-Reranker-0.6B-Q4_K_M.gguf"
    RERANK_SIZE="379 MB"
    EMBED_CTX=8192
    EMBED_DIM=1024
    MODEL_ID="qwen3-embed-06b"
    success "0.6B models selected (embedding: ${EMBED_SIZE}, reranker: ${RERANK_SIZE})"
fi

# ── Step 2: Paths ───────────────────────────────────────────
header "Step 2/10: Installation paths"

echo -e "${BOLD}Proposed directory structure:${NC}"
echo ""
echo -e "  ${CYAN}~/rag/rag-system/${NC}         RAG server (Python + scripts)"
echo -e "  ${CYAN}~/rag/openfox-rag/${NC}        OpenFox integration (this repo)"
echo -e "  ${CYAN}~/rag/models/GGUF/${NC}        GGUF models (${EMBED_SIZE} + ${RERANK_SIZE})"
echo -e "  ${CYAN}~/.venv/main/${NC}             Python virtual environment"
echo -e "  ${CYAN}~/.rag/${NC}                   Embedding cache"
echo -e "  ${CYAN}~/.config/openfox/skills/${NC}  OpenFox skill file"
echo ""

ask "Where to install rag-system?" "$HOME/rag/rag-system" RAG_DIR
ask "Where to store GGUF models?" "$HOME/rag/models/GGUF" GGUF_DIR
ask "Where is your Python venv?" "$HOME/.venv/main" VENV_DIR
ask "Where is your Obsidian vault directory?" "$HOME/obsidian" OBSIDIAN_DIR
ask "Where is your documentation directory?" "$HOME/docs" DOCS_DIR

# llama.cpp binary
if check_command llama-server; then
    LLAMA_BIN=$(command -v llama-server)
    success "llama-server found: ${LLAMA_BIN}"
else
    # Search common locations
    LLAMA_CANDIDATES=(
        "$HOME/llama.cpp/build/bin/llama-server"
        "$HOME/llama-cpp-turboquant/build-cpu/bin/llama-server"
        "$HOME/llama-cpp/build/bin/llama-server"
        "$HOME/.local/bin/llama-server"
        "/usr/local/bin/llama-server"
        "/usr/bin/llama-server"
    )
    LLAMA_FOUND=""
    for candidate in "${LLAMA_CANDIDATES[@]}"; do
        if [[ -f "$candidate" ]]; then
            LLAMA_FOUND="$candidate"
            break
        fi
    done
    if [[ -n "$LLAMA_FOUND" ]]; then
        success "llama-server found: ${LLAMA_FOUND}"
        LLAMA_BIN="$LLAMA_FOUND"
    else
        ask "Path to llama-server binary?" "$HOME/llama.cpp/build/bin/llama-server" LLAMA_BIN
        if [[ ! -f "$LLAMA_BIN" ]]; then
            warn "llama-server not found at ${LLAMA_BIN}"
            warn "You will need to compile llama.cpp before using the RAG"
            warn "See: https://github.com/ggml-org/llama.cpp"
        fi
    fi
fi

# ── Step 3: Clone rag-system ───────────────────────────────
header "Step 3/10: Clone rag-system"

if [[ -d "$RAG_DIR" ]]; then
    warn "rag-system already exists at ${RAG_DIR}"
    ask_yes_no "Re-clone (will overwrite)?" "n" RECLONE
    if [[ "$RECLONE" == true ]]; then
        run rm -rf "$RAG_DIR"
    fi
fi

if [[ ! -d "$RAG_DIR" ]]; then
    info "Cloning rag-system..."
    run mkdir -p "$(dirname "$RAG_DIR")"
    run git clone https://github.com/cried-nutty-won/rag-system.git "$RAG_DIR"
    success "rag-system cloned to ${RAG_DIR}"
else
    success "rag-system already present at ${RAG_DIR}"
fi

# ── Step 4: Python environment ─────────────────────────────
header "Step 4/10: Python environment"

if [[ ! -d "$VENV_DIR" ]]; then
    info "Creating Python venv at ${VENV_DIR}..."
    run python3 -m venv "$VENV_DIR"
    success "Venv created"
else
    success "Venv already exists at ${VENV_DIR}"
fi

info "Installing Python dependencies (numpy, requests, rank_bm25)..."
run "${VENV_DIR}/bin/pip" install --quiet numpy requests rank_bm25 huggingface-hub
success "Python dependencies installed"

# ── Step 5: Download models ────────────────────────────────
header "Step 5/10: Download models"

run mkdir -p "$GGUF_DIR"

# Détecter la commande disponible (venv d'abord, puis PATH)
if [[ -x "${VENV_DIR}/bin/hf" ]]; then
    HF_CMD="${VENV_DIR}/bin/hf download"
elif command -v hf &> /dev/null; then
    HF_CMD="hf download"
elif [[ -x "${VENV_DIR}/bin/huggingface-cli" ]]; then
    HF_CMD="${VENV_DIR}/bin/huggingface-cli download"
elif command -v huggingface-cli &> /dev/null; then
    HF_CMD="huggingface-cli download"
else
    error "Ni 'hf' ni 'huggingface-cli' trouvé."
    info "Installation de huggingface-hub dans le venv..."
    run "${VENV_DIR}/bin/pip" install --quiet huggingface-hub
    if [[ -x "${VENV_DIR}/bin/hf" ]]; then
        HF_CMD="${VENV_DIR}/bin/hf download"
    else
        error "Échec de l'installation de huggingface-hub"
        exit 1
    fi
fi

# Embedding
echo "[INFO] Downloading embedding model..."
$HF_CMD "$EMBED_HF" "$EMBED_FILE" --local-dir "$GGUF_DIR"

# Reranker
echo "[INFO] Downloading reranker model..."
$HF_CMD "$RERANK_HF" "$RERANK_FILE" --local-dir "$GGUF_DIR"

# ── Step 6: Configure rag-system ───────────────────────────
header "Step 6/10: Configure rag-system"

# Write config.sh
if [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Would write config to: ${RAG_DIR}/config.sh"
else
    cat > "${RAG_DIR}/config.sh" << CONFIGEOF
# openfox-rag configuration
# Generated by install.sh on $(date +%Y-%m-%d)

LLAMA_CPP_BIN="${LLAMA_BIN}"
GGUF_DIR="${GGUF_DIR}"
OBSIDIAN_DIR="${OBSIDIAN_DIR}"
VENV_PYTHON="${VENV_DIR}/bin/python3"
RAG_SCRIPTS_DIR="${RAG_DIR}/server"
LLAMA_SCRIPTS_DIR="${RAG_DIR}/llama"
LOG_DIR="/tmp"
CONFIGEOF
fi

success "config.sh written"

# Make scripts executable
run chmod +x "${RAG_DIR}/llama/"*.sh 2>/dev/null || true
run chmod +x "${RAG_DIR}/server/"*.py 2>/dev/null || true
run chmod +x "${RAG_DIR}/fish/"*.sh 2>/dev/null || true
success "Scripts made executable"

# ── Step 7/10: Configure vaults ───────────────────────────
header "Step 7/10: Configure vaults"

echo -e "${BOLD}Add your knowledge base vaults one by one.${NC}"
echo -e "  Press ${CYAN}Enter${NC} on an empty name to finish."
echo ""

VAULTS_PYTHON=""
VAULTS_REGEX=""
VAULT_COUNT=0

while true; do
    echo -e "${BOLD}Vault #$((VAULT_COUNT + 1))${NC}"
    echo -e "  ${CYAN}Type:${NC} obsidian or docs"
    read -rp "  Type [obsidian]: " vault_type
    vault_type="${vault_type:-obsidian}"

    if [[ "$vault_type" == "obsidian" ]]; then
        default_path="${OBSIDIAN_DIR}"
    else
        default_path="${DOCS_DIR}"
    fi

    echo ""
    echo -e "  ${BOLD}Scanning ${default_path} ...${NC}"

    DIRS_FOUND=()
    if [[ -d "$default_path" ]]; then
        while IFS= read -r -d '' dir; do
            DIRS_FOUND+=("$dir")
        done < <(find -L "$default_path" -maxdepth 1 -mindepth 1 -type d ! -name '.*' -print0 | sort -z)
    fi

    if [[ ${#DIRS_FOUND[@]} -gt 0 ]]; then
        echo ""
        for i in "${!DIRS_FOUND[@]}"; do
            echo -e "  ${GREEN}$((i+1)))${NC} $(basename "${DIRS_FOUND[$i]}")"
        done
        echo ""
        echo -e "  Enter a ${CYAN}number${NC} to select, or a ${CYAN}custom path${NC}."
        echo -e "  Press ${CYAN}Enter${NC} on empty to finish adding vaults."
        read -rp "  > " vault_input
    else
        warn "No directories found in ${default_path}"
        echo -e "  Enter a ${CYAN}custom path${NC}, or press ${CYAN}Enter${NC} to finish."
        read -rp "  > " vault_input
    fi

    # Empty input = finish
    if [[ -z "$vault_input" ]]; then
        break
    fi

    # Resolve path
    if [[ "$vault_input" =~ ^[0-9]+$ ]] && [[ ${#DIRS_FOUND[@]} -gt 0 ]]; then
        idx=$((vault_input - 1))
        if [[ $idx -ge 0 && $idx -lt ${#DIRS_FOUND[@]} ]]; then
            vault_path="${DIRS_FOUND[$idx]}"
        else
            warn "Invalid number. Try again."
            continue
        fi
    else
        vault_path="$vault_input"
    fi

    if [[ ! -d "$vault_path" ]]; then
        warn "Directory not found: ${vault_path}. Try again."
        continue
    fi

    # Ask for vault name
    default_name=$(basename "$vault_path" | sed 's/^[0-9]* *//;s/ *$//;s/ /_/g' | tr '[:upper:]' '[:lower:]')
    read -rp "  Vault name [${default_name}]: " vault_name
    vault_name="${vault_name:-$default_name}"

    # Check for duplicates
    if echo "$VAULTS_REGEX" | grep -qw "$vault_name"; then
        warn "Vault '${vault_name}' already exists. Try another name."
        continue
    fi

    # Add vault
    VAULTS_PYTHON+="    \"${vault_name}\": {\"path\": \"${vault_path}\"},\n"
    if [[ -n "$VAULTS_REGEX" ]]; then
        VAULTS_REGEX+="|"
    fi
    VAULTS_REGEX+="${vault_name}"
    VAULT_COUNT=$((VAULT_COUNT + 1))
    success "Vault added: ${vault_name} → ${vault_path}"
    echo ""
done

if [[ $VAULT_COUNT -eq 0 ]]; then
    warn "No vaults configured. You will need to configure VAULTS_CONFIG manually."
    warn "Edit: ${RAG_DIR}/server/rag_server_rerank.py"
else
    success "${VAULT_COUNT} vault(s) configured: ${VAULTS_REGEX}"
fi

# ── Step 8: Shell aliases ──────────────────────────────────
header "Step 8/10: Shell aliases (${SHELL_NAME})"

# Ensure config directory exists
mkdir -p "$SHELL_CONFIG_DIR"

# Build alias block
ALIAS_BLOCK="
# ── openfox-rag aliases ──
alias llmers='bash ${RAG_DIR}/llama/start-rag-llm_embed_reranker_server.sh &'
alias llmes='bash ${RAG_DIR}/llama/start-rag-llm_embed_server.sh &'
alias llme='bash ${RAG_DIR}/llama/start-llm-embed-qwen3-06b.sh &'
alias llmr='bash ${RAG_DIR}/llama/start-llm-reranker-06b.sh &'
alias rs='bash ${RAG_DIR}/server/rag_server_rerank.py &'
alias rst='tail -f /tmp/rag_server_rerank.log'
alias rag='bash ${RAG_DIR}/server/search_vault.sh --no-rerank'
alias ragr='bash ${RAG_DIR}/server/search_vault.sh'
alias rc='curl -s http://127.0.0.1:8182/health | jq .'
alias rsk='pkill -f rag_server_rerank'
# ── end openfox-rag aliases ──
"

if grep -q "openfox-rag aliases" "$SHELL_CONFIG" 2>/dev/null; then
    warn "Aliases already present in ${SHELL_CONFIG} — skipping"
else
    if [[ "$DRY_RUN" == true ]]; then
       echo -e "  ${YELLOW}[DRY-RUN]${NC} Would append aliases to: ${SHELL_CONFIG}"
    else
       echo "$ALIAS_BLOCK" >> "$SHELL_CONFIG"
    fi
    success "Aliases added to ${SHELL_CONFIG}"
fi

# ── Step 9: OpenFox skill ──────────────────────────────────
header "Step 9/10: OpenFox skill"

OPENFOX_SKILLS_DIR="$HOME/.config/openfox/skills"
ask_yes_no "Install OpenFox skill (rag-search.skill.md)?" "y" INSTALL_SKILL

if [[ "$INSTALL_SKILL" == true ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} Would write skill to: ${OPENFOX_SKILLS_DIR}/rag-search.skill.md"
    else
        mkdir -p "$OPENFOX_SKILLS_DIR"
        cat > "${OPENFOX_SKILLS_DIR}/rag-search.skill.md" << 'SKILLEOF'
---
id: rag-search
name: RAG Local Search
description: "Search the user's local knowledge base (Obsidian vaults and docs) via hybrid retrieval plus reranker. Load when the user asks about their notes, documentation, procedures, or before writing system configuration like nftables, dracut, sfdisk."
version: 1.0.0
---
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

__VAULTS_LIST__

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
rag __FIRST_VAULT__ "nftables configuration"
```

Precise search (RRF + reranker, ~10-18s):

```bash
ragr __FIRST_VAULT__ "nftables configuration"
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

## When NOT to use

- The answer is in the current project's code
- It is a general knowledge question unrelated to the user's documents
- The user explicitly says not to search

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `rc` shows services down | Run `llmers` and wait 10s |
| Search returns no results | Try a different vault or broader query |
| Reranker timeout | Use `rag` instead of `ragr` (RRF only) |
| Port already in use | `rsk` then `rs`, or `pkill -f llama-server` then `llmers` |
| Need to check logs | `rst` |
SKILLEOF
        # Injecter la liste dynamique des vaults configurés
        if [[ -n "$VAULTS_REGEX" ]]; then
            VAULTS_DISPLAY="${VAULTS_REGEX//|/ · } · obsidian · all"
            FIRST_VAULT="${VAULTS_REGEX%%|*}"
        else
            VAULTS_DISPLAY="obsidian · all"
            FIRST_VAULT="obsidian"
        fi
        SKILL_CONTENT=$(cat "${OPENFOX_SKILLS_DIR}/rag-search.skill.md")
        SKILL_CONTENT="${SKILL_CONTENT//__VAULTS_LIST__/${VAULTS_DISPLAY}}"
        SKILL_CONTENT="${SKILL_CONTENT//__FIRST_VAULT__/${FIRST_VAULT}}"
        printf '%s\n' "$SKILL_CONTENT" > "${OPENFOX_SKILLS_DIR}/rag-search.skill.md"
        success "OpenFox skill installed: ${OPENFOX_SKILLS_DIR}/rag-search.skill.md"
    fi
else
    info "Skill installation skipped"
fi

# ── Step 10: Verification + Summary ────────────────────────
header "Step 10/10: Verification"

echo -e "${BOLD}Installation summary:${NC}"
echo ""
echo -e "  rag-system:     ${GREEN}${RAG_DIR}${NC}"
echo -e "  Models:         ${GREEN}${GGUF_DIR}${NC}"
echo -e "    Embedding:    ${EMBED_MODEL} (${EMBED_SIZE})"
echo -e "    Reranker:     ${RERANK_MODEL} (${RERANK_SIZE})"
echo -e "  Python venv:    ${GREEN}${VENV_DIR}${NC}"
echo -e "  Obsidian:       ${GREEN}${OBSIDIAN_DIR}${NC}"
echo -e "  Vaults:         ${VAULT_COUNT} configured"
echo -e "  Shell:          ${GREEN}${SHELL_NAME}${NC} → ${SHELL_CONFIG}"
if [[ "$INSTALL_SKILL" == true ]]; then
echo -e "  OpenFox skill:  ${GREEN}${OPENFOX_SKILLS_DIR}/rag-search.skill.md${NC}"
fi
echo ""

# Check llama-server
if [[ -f "$LLAMA_BIN" ]]; then
    success "llama-server: ${LLAMA_BIN}"
else
    warn "llama-server: NOT FOUND at ${LLAMA_BIN}"
    warn "Compile llama.cpp before first use: https://github.com/ggml-org/llama.cpp"
fi

# Check models
if [[ -f "${GGUF_DIR}/${EMBED_FILE}" ]]; then
    success "Embedding model: ${EMBED_FILE}"
elif [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Embedding model: would be downloaded"
else
    error "Embedding model: MISSING"
fi

if [[ -f "${GGUF_DIR}/${RERANK_FILE}" ]]; then
    success "Reranker model: ${RERANK_FILE}"
elif [[ "$DRY_RUN" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${NC} Reranker model: would be downloaded"
else
    error "Reranker model: MISSING"
fi

# Check Python deps
if "${VENV_DIR}/bin/python3" -c "import numpy, requests, rank_bm25" 2>/dev/null; then
    success "Python dependencies: OK"
else
    error "Python dependencies: MISSING"
fi

# ── Final output ────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║          Installation complete                   ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BOLD}${CYAN}━━━ Commands ━━━${NC}"
echo ""
echo -e "  ${GREEN}llmers${NC}              Start full stack (embedding + reranker + RAG)"
echo -e "  ${GREEN}llmes${NC}               Start embedding + RAG (no reranker)"
echo -e "  ${GREEN}llme${NC}                Start embedding only (port 8181)"
echo -e "  ${GREEN}llmr${NC}                Start reranker only (port 8184)"
echo -e "  ${GREEN}rs${NC}                  Start RAG server only (port 8182)"
echo -e "  ${GREEN}rst${NC}                 Tail -f RAG server logs"
echo -e "  ${GREEN}rag${NC} <vault> \"<q>\"   Fast search (~20ms)"
echo -e "  ${GREEN}ragr${NC} <vault> \"<q>\"  Slow and precise search with reranker (~10-18s)"
echo -e "  ${GREEN}rc${NC}                  Health check all 3 services"
echo -e "  ${GREEN}rsk${NC}                 Kill the RAG server"
echo ""

echo -e "${BOLD}${CYAN}━━━ Quick start ━━━${NC}"
echo ""
echo -e "  1. ${BOLD}Reload your shell:${NC}"
if [[ "$SHELL_NAME" == "fish" ]]; then
echo -e "     ${CYAN}source ~/.config/fish/config.fish${NC}"
elif [[ "$SHELL_NAME" == "zsh" ]]; then
echo -e "     ${CYAN}source ~/.zshrc${NC}"
elif [[ "$SHELL_NAME" == "bash" ]]; then
echo -e "     ${CYAN}source ~/.bashrc${NC}"
else
echo -e "     ${CYAN}source ${SHELL_CONFIG}${NC}"
fi
echo ""
echo -e "  2. ${BOLD}Start the RAG stack:${NC}"
echo -e "     ${CYAN}llmers${NC}"
echo ""
echo -e "  3. ${BOLD}Wait for first indexing:${NC} ~5-15 min (instant on subsequent runs)"
echo ""
echo -e "  4. ${BOLD}Verify:${NC}"
echo -e "     ${CYAN}rc${NC}"
echo ""
echo -e "  5. ${BOLD}Search:${NC}"
echo ""
echo -e "     Fast search (~20ms):"
if [[ -n "$VAULTS_REGEX" ]]; then
    first_vault=$(echo "$VAULTS_REGEX" | cut -d'|' -f1)
    echo -e "     ${CYAN}rag ${first_vault} \"your query\"${NC}"
else
    echo -e "     ${CYAN}rag obsidian \"your query\"${NC}"
fi
echo ""
echo -e "     Slow and precise search with reranker (~10-18s):"
if [[ -n "$VAULTS_REGEX" ]]; then
    echo -e "     ${CYAN}ragr ${first_vault} \"your query\"${NC}"
else
    echo -e "     ${CYAN}ragr obsidian \"your query\"${NC}"
fi
echo ""
echo -e "     Search a specific vault:"
if [[ -n "$VAULTS_REGEX" ]]; then
    echo -e "     ${CYAN}rag <vault_name> \"your query\"${NC}"
    echo -e "     Available vaults: ${GREEN}${VAULTS_REGEX}${NC}"
else
    echo -e "     ${CYAN}rag <vault_name> \"your query\"${NC}"
fi
echo ""
echo -e "     Search all vaults at once:"
echo -e "     ${CYAN}ragr all \"your query\"${NC}"
echo ""

echo -e "${BOLD}${CYAN}━━━ Vaults ━━━${NC}"
echo ""
if [[ -n "$VAULTS_REGEX" ]]; then
echo -e "  Available: ${GREEN}${VAULTS_REGEX}${NC}"
else
echo -e "  ${YELLOW}No vaults configured. Edit: ${RAG_DIR}/server/rag_server_rerank.py${NC}"
fi
echo -e "  Special:   ${GREEN}obsidian${NC} (all Obsidian vaults) · ${GREEN}all${NC} (everything)"
echo ""

echo -e "${BOLD}${CYAN}━━━ Documentation ━━━${NC}"
echo ""
echo -e "  RAG server docs:     ${CYAN}${RAG_DIR}/doc/${NC}"
echo -e "  RAG quick start:     ${CYAN}${RAG_DIR}/doc/00 Quick Start Guide.md${NC}"
echo -e "  RAG full doc:        ${CYAN}${RAG_DIR}/doc/01 Full Documentation.md${NC}"
echo -e "  OpenFox integration: ${CYAN}$(cd "$(dirname "$0")" && pwd)/doc/integration.md${NC}"
echo -e "  OpenFox skill:       ${CYAN}${OPENFOX_SKILLS_DIR}/rag-search.skill.md${NC}"
echo -e "  models.ini preset:   ${CYAN}$(cd "$(dirname "$0")" && pwd)/presets/models-llamacpp.ini${NC}"
echo ""

echo -e "${BOLD}${CYAN}━━━ OpenFox ━━━${NC}"
echo ""
echo -e "  Restart OpenFox to load the skill."
echo -e "  The agent will see the RAG commands automatically."
echo ""
