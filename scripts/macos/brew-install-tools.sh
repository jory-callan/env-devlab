#!/usr/bin/env bash
# Install common CLI tools via Homebrew (macOS)
# Usage: ./brew-install-tools.sh [-y|--yes]
# Requires: brew (see install-brew.sh)
set -euo pipefail

ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

if ! command -v brew >/dev/null 2>&1; then
    echo "  brew not found. Run install-brew.sh first." >&2
    exit 1
fi

# Edit this list to suit your needs (space-separated).
# Core CLI essentials
FORMULAE=(
    wget
    p7zip
    iproute2mac        # iproute2-style `ip` command for macOS
    tree
    jq
    yq
    ripgrep
    fd
    fzf
    tmux
    htop
    bat
    lsd
    duf
    procs
    httpie
    cloc
    lazygit
)

# ---- Print the install plan up front ----
echo "

========================================
 Homebrew Tools Install Plan
========================================
  brew home : $(brew --prefix)
$(printf '  - %s\n' "${FORMULAE[@]}")
========================================

"

# ---- Menu: 0 exit, 1 install ----
if [[ $ASSUME_YES -ne 1 ]]; then
    echo "  [1] Install all of the above"
    echo "  [2] Install one by one (choose each package)"
    echo "  [0] Exit"
    read -r -p "Please select: " choice
    case "$choice" in
        1) ;;
        2)
            selected=()
            for f in "${FORMULAE[@]}"; do
                if brew list --formula "$f" >/dev/null 2>&1; then
                    echo "  $f: already installed, skipped."
                    continue
                fi
                read -r -p "  Install $f? [y/N]: " yn
                if [[ "${yn:-n}" =~ ^[Yy]$ ]]; then
                    selected+=("$f")
                fi
            done
            [[ ${#selected[@]} -eq 0 ]] && { echo "  Nothing selected. Exited."; exit 0; }
            FORMULAE=("${selected[@]}")
            ;;
        *) echo "  Exited."; exit 0 ;;
    esac
fi

echo "  brew update --auto-update ..."
brew update --auto-update >/dev/null 2>&1 || true

for f in "${FORMULAE[@]}"; do
    if brew list --formula "$f" >/dev/null 2>&1; then
        echo "  $f: already installed, skipped."
        continue
    fi
    echo "  Installing $f ..."
    if brew install "$f"; then
        echo "  $f: done."
    else
        echo "  $f: FAILED, continue with the rest." >&2
    fi
done

echo ""
echo "  All done. Verify with:"
echo "    brew list --formula"
echo "    ip -V   (iproute2mac)"
echo "    7z      (p7zip)"
