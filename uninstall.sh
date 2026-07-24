#!/usr/bin/env bash
# openfox-rag — Uninstaller (full cleanup: openfox-rag + rag-system)
# Usage: bash uninstall.sh [--dry-run]

set -euo pipefail

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

DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true ;;
    esac
done

run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} $*"
    else
        "$@"
    fi
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

detect_shell() {
    local shell_name
    shell_name="$(basename "${SHELL:-/bin/bash}")"
    case "$shell_name" in
        fish)
            SHELL_NAME="fish"
            SHELL_CONFIG="${HOME}/.config/fish/config.fish"
            ;;
        zsh)
            SHELL_NAME="zsh"
            SHELL_CONFIG="${HOME}/.zshrc"
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
            ;;
        *)
            SHELL_NAME="$shell_name"
            SHELL_CONFIG="${HOME}/.${shell_name}rc"
            ;;
    esac
}

# ── Banner ──────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║        openfox-rag — Uninstaller                ║"
echo "  ║   Removes openfox-rag + rag-system entirely     ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  This script will remove:"
echo -e "    • Running RAG services"
echo -e "    • Shell aliases (openfox-rag + rag-system)"
echo -e "    • OpenFox skill (rag-search.md)"
echo -e "    • rag-system repo, models, cache, venv"
echo -e "    • openfox-rag repo"
echo ""
echo -e "  ${YELLOW}It will NOT remove:${NC}"
echo -e "    • Your Obsidian vaults or documentation"
echo ""

detect_shell
info "Shell: ${SHELL_NAME} → ${SHELL_CONFIG}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect rag-system location
RAG_DIR=""
if [[ -f "${HOME}/rag-system/config.sh" ]]; then
    RAG_DIR="${HOME}/rag-system"
elif [[ -f "${SCRIPT_DIR}/../rag-system/config.sh" ]]; then
    RAG_DIR="$(cd "${SCRIPT_DIR}/../rag-system" && pwd)"
fi

# Load rag-system config if found
GGUF_DIR="${HOME}/models/GGUF/rag"
VENV_DIR="${HOME}/.venv/main"
CACHE_DIR="${HOME}/.rag"
if [[ -n "$RAG_DIR" && -f "${RAG_DIR}/config.sh" ]]; then
    source "${RAG_DIR}/config.sh" 2>/dev/null || true
fi

# ── Step 1: Stop services ──────────────────────────────────
header "Step 1/6: Stop RAG services"

if pgrep -f "rag_server_rerank" &>/dev/null || \
   pgrep -f "llama-server.*8181" &>/dev/null || \
   pgrep -f "llama-server.*8184" &>/dev/null; then
    info "Running services detected"
    ask_yes_no "Stop all RAG services?" "y" STOP_SERVICES
    if [[ "$STOP_SERVICES" == true ]]; then
        run pkill -f "rag_server_rerank" 2>/dev/null || true
        run pkill -f "llama-server.*8181" 2>/dev/null || true
        run pkill -f "llama-server.*8184" 2>/dev/null || true
        run pkill -f "Qwen3-Embedding" 2>/dev/null || true
        run pkill -f "Qwen3-Reranker" 2>/dev/null || true
        success "Services stopped"
    fi
else
    success "No RAG services running"
fi

# ── Step 2: Remove aliases ─────────────────────────────────
header "Step 2/6: Remove shell aliases"

ALIASES_REMOVED=false
if grep -q "openfox-rag aliases" "$SHELL_CONFIG" 2>/dev/null; then
    ask_yes_no "Remove openfox-rag aliases from ${SHELL_CONFIG}?" "y" RM1
    if [[ "$RM1" == true ]]; then
        run sed -i '/# ── openfox-rag aliases ──/,/# ── end openfox-rag aliases ──/d' "$SHELL_CONFIG"
        ALIASES_REMOVED=true
    fi
fi
if grep -q "rag-system aliases" "$SHELL_CONFIG" 2>/dev/null; then
    ask_yes_no "Remove rag-system aliases from ${SHELL_CONFIG}?" "y" RM2
    if [[ "$RM2" == true ]]; then
        run sed -i '/# ── rag-system aliases ──/,/# ── end rag-system aliases ──/d' "$SHELL_CONFIG"
        ALIASES_REMOVED=true
    fi
fi
if [[ "$ALIASES_REMOVED" == true ]]; then
    run sed -i '/^$/N;/^\n$/d' "$SHELL_CONFIG"
    success "Aliases removed"
else
    info "No aliases found or kept"
fi

# ── Step 3: Remove OpenFox skill ───────────────────────────
header "Step 3/6: Remove OpenFox skill"

SKILL_FILE="${HOME}/.config/openfox/skills/rag-search.md"
if [[ -f "$SKILL_FILE" ]]; then
    ask_yes_no "Remove OpenFox skill?" "y" REMOVE_SKILL
    if [[ "$REMOVE_SKILL" == true ]]; then
        run rm -f "$SKILL_FILE"
        success "Skill removed"
    fi
else
    info "No OpenFox skill found"
fi

# ── Step 4: Remove rag-system data ─────────────────────────
header "Step 4/6: Remove rag-system (repo, models, cache, venv)"

# Cache
if [[ -d "$CACHE_DIR" ]]; then
    CACHE_SIZE=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
    info "Embedding cache: ${CACHE_DIR} (${CACHE_SIZE})"
    ask_yes_no "Remove embedding cache?" "y" REMOVE_CACHE
    if [[ "$REMOVE_CACHE" == true ]]; then
        run rm -rf "$CACHE_DIR"
        success "Cache removed"
    fi
fi

# Models
if [[ -d "$GGUF_DIR" ]]; then
    MODEL_SIZE=$(du -sh "$GGUF_DIR" 2>/dev/null | cut -f1)
    info "GGUF models: ${GGUF_DIR} (${MODEL_SIZE})"
    ask_yes_no "Remove GGUF models?" "y" REMOVE_MODELS
    if [[ "$REMOVE_MODELS" == true ]]; then
        run rm -rf "$GGUF_DIR"
        success "Models removed"
    fi
fi

# Venv
if [[ -d "$VENV_DIR" ]]; then
    VENV_SIZE=$(du -sh "$VENV_DIR" 2>/dev/null | cut -f1)
    info "Python venv: ${VENV_DIR} (${VENV_SIZE})"
    ask_yes_no "Remove Python venv?" "y" REMOVE_VENV
    if [[ "$REMOVE_VENV" == true ]]; then
        run rm -rf "$VENV_DIR"
        # Clean activate line from shell config
        if [[ -f "$SHELL_CONFIG" ]]; then
            run sed -i "\|${VENV_DIR}/bin/activate|d" "$SHELL_CONFIG"
        fi
        success "Venv removed (+ activate line cleaned from ${SHELL_CONFIG})"
    fi
fi

# rag-system repo
if [[ -n "$RAG_DIR" && -d "$RAG_DIR" ]]; then
    info "rag-system repo: ${RAG_DIR}"
    ask_yes_no "Remove rag-system repo?" "y" REMOVE_RAG
    if [[ "$REMOVE_RAG" == true ]]; then
        run rm -rf "$RAG_DIR"
        success "rag-system removed"
    fi
else
    info "rag-system repo not found"
fi

# ── Step 5: Remove openfox-rag repo ────────────────────────
header "Step 5/6: Remove openfox-rag repo"

ask_yes_no "Remove openfox-rag repo (${SCRIPT_DIR})?" "y" REMOVE_REPO
if [[ "$REMOVE_REPO" == true ]]; then
    run rm -rf "$SCRIPT_DIR"
    success "openfox-rag removed"
fi

# ── Step 6: Summary ────────────────────────────────────────
header "Step 6/6: Done"

echo -e "${BOLD}Removed:${NC}"
[[ "${STOP_SERVICES:-false}" == true ]] && echo -e "  ${GREEN}✓${NC} RAG services"
[[ "${ALIASES_REMOVED:-false}" == true ]] && echo -e "  ${GREEN}✓${NC} Shell aliases"
[[ "${REMOVE_SKILL:-false}" == true ]] && echo -e "  ${GREEN}✓${NC} OpenFox skill"
[[ "${REMOVE_CACHE:-false}" == true ]] && echo -e "  ${GREEN}✓${NC} Embedding cache"
[[ "${REMOVE_MODELS:-false}" == true ]] && echo -e "  ${GREEN}✓${NC} GGUF models"
[[ "${REMOVE_VENV:-false}" == true ]] && echo -e "  ${GREEN}✓${NC} Python venv"
[[ "${REMOVE_RAG:-false}" == true ]] && echo -e "  ${GREEN}✓${NC} rag-system repo"
[[ "${REMOVE_REPO:-false}" == true ]] && echo -e "  ${GREEN}✓${NC} openfox-rag repo"
echo ""
echo -e "${BOLD}Not removed:${NC}"
echo -e "  ${CYAN}•${NC} Obsidian vaults and documentation"
echo ""
echo -e "${BOLD}Reload shell:${NC} ${CYAN}source ${SHELL_CONFIG}${NC}"
echo ""
