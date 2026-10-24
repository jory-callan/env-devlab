#!/usr/bin/env bash
# Install fnm (Fast Node Manager) and configure Node.js mirrors (macOS)
# Usage: ./fnm-install.sh [-y|--yes]
# Menu: 1 install + configure, 2 configure mirrors/hooks only, 0 exit
set -euo pipefail

ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# ---- Mirror settings (npmmirror, same as the Windows scripts) ----
NODE_DIST_MIRROR="https://npmmirror.com/mirrors/node/"
NPM_REGISTRY="https://registry.npmmirror.com/"

has_fnm() { command -v fnm >/dev/null 2>&1; }

# ---- Configure: env exports in shell profiles + ~/.npmrc registry ----
configure() {
    local export_line="export FNM_NODE_DIST_MIRROR=\"$NODE_DIST_MIRROR\""
    local marker="fnm-install.sh"

    write_profile() {
        local profile="$1" hook="$2"
        grep -qs "$marker" "$profile" 2>/dev/null && {
            echo "  $profile: already configured, skipped."
            return
        }
        {
            echo ""
            echo "# fnm (added by $marker)"
            echo "$export_line"
            echo "$hook"
        } >> "$profile"
        echo "  $profile: appended FNM_NODE_DIST_MIRROR + fnm env hook."
    }

    # zsh: hook in .zprofile, export in .zprofile too
    write_profile "$HOME/.zprofile" 'eval "$(fnm env --use-on-cd --shell zsh)"'
    # bash: hook in .bashrc (bash does not read .zprofile)
    if ! grep -qs "$marker" "$HOME/.bashrc" 2>/dev/null; then
        {
            echo ""
            echo "# fnm (added by $marker)"
            echo "$export_line"
            echo 'eval "$(fnm env --use-on-cd --shell bash)"'
        } >> "$HOME/.bashrc"
        echo "  $HOME/.bashrc: appended FNM_NODE_DIST_MIRROR + fnm env hook."
    fi

    # npm registry -> ~/.npmrc
    local npmrc="$HOME/.npmrc"
    if [[ -f "$npmrc" ]] && grep -qs "registry=" "$npmrc"; then
        echo "  $npmrc: registry= already set, not modified:"
        grep "registry=" "$npmrc" | head -n 1
    else
        printf 'registry=%s\n' "$NPM_REGISTRY" >> "$npmrc"
        echo "  $npmrc: registry set to $NPM_REGISTRY"
    fi
}

# ---- Install fnm via the official installer ----
install_fnm() {
    if has_fnm; then
        echo "  fnm is already installed. Skipped."
        echo "    Command : $(command -v fnm)"
        echo "    Version : $(fnm --version)"
        return 0
    fi

    if command -v brew >/dev/null 2>&1; then
        echo "  Installing fnm via Homebrew ..."
        brew install fnm
    else
        echo "  Installing fnm via the official installer ..."
        curl -fsSL https://fnm.vercel.app/install | bash
    fi

    if ! has_fnm; then
        echo "  Install failed: fnm command still not found." >&2
        exit 1
    fi
    echo "  fnm installed: $(command -v fnm)"
}

# ---- Print the plan up front ----
echo "

========================================
 fnm Install Plan
========================================
  fnm      : $([[ has_fnm ]] && echo "installed ($(command -v fnm))" || echo "not installed")
  Node dl  : FNM_NODE_DIST_MIRROR=$NODE_DIST_MIRROR
  npm reg  : $NPM_REGISTRY
  Hook     : eval \"\$(fnm env --use-on-cd)\"
========================================

"

# ---- Menu ----
if [[ $ASSUME_YES -eq 1 ]]; then
    install_fnm
    configure
else
    echo "  [1] Install fnm + configure mirrors and shell hooks"
    echo "  [2] Configure mirrors and shell hooks only"
    echo "  [0] Exit"
    read -r -p "Please select: " choice
    case "$choice" in
        1) install_fnm; configure ;;
        2) configure ;;
        *) echo "  Exited."; exit 0 ;;
    esac
fi

echo ""
echo "  Open a NEW terminal afterwards, then:"
echo "    fnm install 24      # or: fnm install --lts  (downloads via the mirror)"
echo "    fnm list"
echo "    fnm use 24"
echo "    node -v"
echo ""
echo "  Default fnm data dir: \$FNM_DIR or ~/.local/share/fnm"
