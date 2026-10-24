#!/usr/bin/env bash
# Install uv and configure PyPI/Python mirrors (macOS)
# Usage: ./uv-install.sh [-y|--yes]
# Menu: 1 install + configure, 2 configure mirrors only, 0 exit
set -euo pipefail

ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

PYPI_INDEX="https://mirrors.aliyun.com/pypi/simple/"
PY_MIRROR="https://registry.npmmirror.com/-/binary/python-build-standalone"

UV_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/uv"
UV_CONFIG="$UV_CONFIG_DIR/uv.toml"

has_uv() { command -v uv >/dev/null 2>&1; }

# ---- Configure: ~/.config/uv/uv.toml ----
configure() {
    local marker="# uv-install.sh"
    mkdir -p "$UV_CONFIG_DIR"

    if [[ -f "$UV_CONFIG" ]] && grep -qs "$marker" "$UV_CONFIG"; then
        echo "  $UV_CONFIG: already configured, skipped."
    elif [[ -f "$UV_CONFIG" ]]; then
        echo "  $UV_CONFIG exists but was not written by this script:"
        echo "  --- current content ---"
        cat "$UV_CONFIG"
        echo "  -----------------------"
        return
    else
        cat > "$UV_CONFIG" <<EOF
# Written by uv-install.sh (env-devlab/scripts/macos)

# Python build downloads through npmmirror
python-install-mirror = "$PY_MIRROR"

[[index]]
url = "$PYPI_INDEX"
default = true

[pip]
index-url = "$PYPI_INDEX"
EOF
        echo "  $UV_CONFIG: written."
    fi
}

# ---- Install uv via the official installer ----
install_uv() {
    if has_uv; then
        echo "  uv is already installed. Skipped."
        echo "    Command : $(command -v uv)"
        echo "    Version : $(uv --version)"
        return 0
    fi

    if command -v brew >/dev/null 2>&1; then
        echo "  Installing uv via Homebrew ..."
        brew install uv
    else
        echo "  Installing uv via the official installer ..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi

    if ! has_uv; then
        echo "  Install failed: uv command still not found." >&2
        exit 1
    fi
    echo "  uv installed: $(command -v uv)"
}

# ---- Print the plan up front ----
echo "

========================================
 uv Install Plan
========================================
  uv   : $([[ has_uv ]] && echo "installed ($(command -v uv))" || echo "not installed")
  PyPI : $PYPI_INDEX
  Py   : $PY_MIRROR
  Conf : $UV_CONFIG
========================================

"

# ---- Menu ----
if [[ $ASSUME_YES -eq 1 ]]; then
    install_uv
    configure
else
    echo "  [1] Install uv + configure mirrors"
    echo "  [2] Configure mirrors only"
    echo "  [0] Exit"
    read -r -p "Please select: " choice
    case "$choice" in
        1) install_uv; configure ;;
        2) configure ;;
        *) echo "  Exited."; exit 0 ;;
    esac
fi

echo ""
echo "  uv needs no shell hook. Try:"
echo "    uv python install 3.12    # download a Python version (uses the mirror)"
echo "    uv python list --only-installed"
echo "    uv init && uv add requests && uv run python"
echo ""
echo "  Data dir (default ~/.cache/uv):"
echo "    uv cache dir"
echo "    uv python dir"
