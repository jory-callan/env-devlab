#!/usr/bin/env bash
# Install global npm packages
set -euo pipefail

command -v npm >/dev/null 2>&1 || { echo "npm not found." >&2; exit 1; }

# Add new global packages here (space-separated).
GLOBALS=(
    serve      # static file server
    pnpm       # fast package manager
)


# ---- Print the install plan up front ----
echo "

========================================
 npm Global Packages Install Plan
========================================
  npm home : $(command -v npm)
  version  : $(npm --version)
$(printf '  - %s\n' "${GLOBALS[@]}")
========================================
"

for pkg in "${GLOBALS[@]}"; do
    if command -v "$pkg" >/dev/null 2>&1; then
        echo "  $pkg: already installed, skipped."
    else
        npm install -g "$pkg"
        echo "  $pkg: done. -> $(command -v "$pkg")"
    fi
done
