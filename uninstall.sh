#!/usr/bin/env bash
# openfox-rag — Uninstaller
# Removes aliases, OpenFox skill, and optionally the repo
# Usage: bash uninstall.sh [--dry-run]

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

# ── Shell detection ─────────────────────────────────────────
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
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  This script will remove:"
echo -e "    • Shell aliases (10 shortcuts)"
echo -e "    • OpenFox skill (rag-search.md)"
echo -e "    • Optionally: the openfox-rag repo"
echo ""
echo -e "  ${YELLOW}It will NOT remove:${NC}"
echo -e "    • rag-system (separate repo)"
echo -e "    • Your Obsidian vaults or documentation"
echo -e "    • GGUF models"
echo ""

detect_shell
info "Shell: ${SHELL_NAME} → ${SHELL_CONFIG}"

# ── Step 1: Remove shell aliases ───────────────────────────
header "Step 1/3: Remove shell aliases"

if grep -q "openfox-rag aliases" "$SHELL_CONFIG" 2>/dev/null; then
    ask_yes_no "Remove openfox-rag aliases from ${SHELL_CONFIG}?" "y" REMOVE_ALIASES
    if [[ "$REMOVE_ALIASES" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${YELLOW}[DRY-RUN]${NC} Would remove alias block from ${SHELL_CONFIG}"
        else
            # Remove the block between the markers
            sed -i '/# ── openfox-rag aliases ──/,/# ── end openfox-rag aliases ──/d' "$SHELL_CONFIG"
            # Clean up leftover blank lines
            sed -i '/^$/N;/^\n$/d' "$SHELL_CONFIG"
        fi
        success "Aliases removed from ${SHELL_CONFIG}"
    else
        info "Aliases kept"
    fi
else
    info "No openfox-rag aliases found in ${SHELL_CONFIG}"
fi

# ── Step 2: Remove OpenFox skill ───────────────────────────
header "Step 2/3: Remove OpenFox skill"

SKILL_FILE="${HOME}/.config/openfox/skills/rag-search.md"

if [[ -f "$SKILL_FILE" ]]; then
    ask_yes_no "Remove OpenFox skill (${SKILL_FILE})?" "y" REMOVE_SKILL
    if [[ "$REMOVE_SKILL" == true ]]; then
        run rm -f "$SKILL_FILE"
        success "Skill removed"
    else
        info "Skill kept"
    fi
else
    info "No OpenFox skill found at ${SKILL_FILE}"
fi

# ── Step 3: Remove repo (optional) ─────────────────────────
header "Step 3/3: Remove openfox-rag repo (optional)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ask_yes_no "Remove the openfox-rag repo (${SCRIPT_DIR})?" "n" REMOVE_REPO
if [[ "$REMOVE_REPO" == true ]]; then
    run rm -rf "$SCRIPT_DIR"
    success "Repo removed"
else
    info "Repo kept"
fi

# ── Summary ─────────────────────────────────────────────────
header "Uninstall complete"

echo -e "${BOLD}What was removed:${NC}"
if [[ "${REMOVE_ALIASES:-false}" == true ]]; then
    echo -e "  ${GREEN}✓${NC} Shell aliases (${SHELL_CONFIG})"
else
    echo -e "  ${YELLOW}–${NC} Shell aliases (kept)"
fi
if [[ "${REMOVE_SKILL:-false}" == true ]]; then
    echo -e "  ${GREEN}✓${NC} OpenFox skill (rag-search.md)"
else
    echo -e "  ${YELLOW}–${NC} OpenFox skill (kept)"
fi
if [[ "${REMOVE_REPO:-false}" == true ]]; then
    echo -e "  ${GREEN}✓${NC} openfox-rag repo"
else
    echo -e "  ${YELLOW}–${NC} openfox-rag repo (kept)"
fi
echo ""
echo -e "${BOLD}What was NOT removed:${NC}"
echo -e "  ${CYAN}•${NC} rag-system (separate repo)"
echo -e "  ${CYAN}•${NC} GGUF models"
echo -e "  ${CYAN}•${NC} Obsidian vaults and documentation"
echo -e "  ${CYAN}•${NC} Embedding cache (~/.rag/)"
echo ""
echo -e "${BOLD}To fully remove the RAG system, run:${NC}"
echo -e "  ${CYAN}cd /path/to/rag-system && bash uninstall.sh${NC}"
echo ""
