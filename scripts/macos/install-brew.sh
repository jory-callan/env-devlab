#!/usr/bin/env bash
# Install Homebrew (macOS)
# Usage: ./install-brew.sh [-y|--yes] [--mirror aliyun|none]
set -euo pipefail

MIRROR="none"
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --mirror) MIRROR="$2"; shift 2 ;;
        --mirror=*) MIRROR="${1#--mirror=}" ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

API_DOMAIN="https://formulae.brew.sh"
BOTTLE_DOMAIN=""
CLONE_PREFIX=""
MIRROR_NOTE="official sources"

if [[ "$MIRROR" == "aliyun" ]]; then
    CLONE_PREFIX="https://mirrors.aliyun.com/homebrew/"
    API_DOMAIN="https://mirrors.aliyun.com/homebrew-bottles/api"
    BOTTLE_DOMAIN="https://mirrors.aliyun.com/homebrew-bottles"
    MIRROR_NOTE="mirrors.aliyun.com (Aliyun)"
elif [[ "$MIRROR" != "none" ]]; then
    echo "Unknown mirror: $MIRROR (use 'aliyun' or 'none')" >&2
    exit 1
fi

# ---- Idempotency: skip if brew already exists ----
if command -v brew >/dev/null 2>&1; then
    echo "  Homebrew is already installed. Skipped."
    echo "    Command : $(command -v brew)"
    echo "    Version : $(brew --version | head -n 1)"
    exit 0
fi

# ---- Print the install plan up front ----
echo "

========================================
 Homebrew Install Plan
========================================
  Mirror  : $MIRROR_NOTE
  API     : $API_DOMAIN
  Bottles : ${BOTTLE_DOMAIN:-official (ghcr.io)}
========================================

"

# ---- Menu: 0 exit, 1 install ----
if [[ $ASSUME_YES -ne 1 ]]; then
    echo "  [1] Install"
    echo "  [0] Exit"
    read -r -p "Please select: " choice
    if [[ "$choice" != "1" ]]; then
        echo "  Exited."
        exit 0
    fi
fi

export HOMEBREW_API_DOMAIN="$API_DOMAIN"
if [[ -n "$BOTTLE_DOMAIN" ]]; then
    export HOMEBREW_BOTTLE_DOMAIN="$BOTTLE_DOMAIN"
fi

echo "  Installing Homebrew from $MIRROR_NOTE (this may take a few minutes)..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# ---- Aliyun: re-point git remotes so brew update also uses the mirror ----
if [[ -n "$CLONE_PREFIX" ]]; then
    reword() { git -C "$1" remote set-url origin "$2" 2>/dev/null || true; }
    for prefix in /opt/homebrew /usr/local; do
        [[ -d "$prefix/Homebrew" ]] && reword "$prefix/Homebrew" "${CLONE_PREFIX}brew.git"
        for repo in homebrew-core homebrew-cask; do
            tap="$prefix/Library/Taps/homebrew/$repo"
            [[ -d "$tap" ]] && reword "$tap" "${CLONE_PREFIX}${repo}.git"
        done
    done
fi

# ---- Verify & print follow-up steps ----
BREW_CMD=""
for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x "$p" ]] && BREW_CMD="$p" && break
done

if [[ -z "$BREW_CMD" ]]; then
    echo "  Install failed: brew binary not found." >&2
    exit 1
fi

echo ""
echo "  Homebrew installed: $BREW_CMD"
echo ""
if [[ "$BREW_CMD" == "/opt/homebrew/bin/brew" ]]; then
    echo "  Add Homebrew to PATH (Apple Silicon, zsh):"
    echo ""
    echo "    echo 'eval \"\$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile"
    echo "    eval \"\$(/opt/homebrew/bin/brew shellenv)\""
    echo ""
fi
if [[ -n "$CLONE_PREFIX" ]]; then
    echo "  Keep the Aliyun mirror permanent, add to ~/.zprofile:"
    echo "    export HOMEBREW_API_DOMAIN=\"$API_DOMAIN\""
    echo "    export HOMEBREW_BOTTLE_DOMAIN=\"$BOTTLE_DOMAIN\""
    echo ""
fi
echo "  Restart your terminal, then run: $(basename "$BREW_CMD") -v"

