#!/bin/bash
# Quick-apply entry: checks dependencies, installs collections, then runs
# the initialization playbooks.
#
# Usage:
#   bash apply.sh <playbook> [extra args passed through to ansible-playbook]
#
# Playbooks:
#   linux-init   Linux base initialization (hostname, mirrors, base packages,
#                kernel, swap, ulimit, logging, security)
#   docker       Install and configure Docker CE
#   all          Run linux-init first, then docker
#
# Examples:
#   bash apply.sh linux-init
#   bash apply.sh docker -l node1
#   bash apply.sh all --check --diff
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

INVENTORY="inventories/production/hosts.ini"
REQUIREMENTS="requirements.yml"

# --- Dependency checks ---
if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "ERROR: ansible-playbook not found. Install it first:"
    echo "  pip install ansible"
    echo "  or Rocky/CentOS: dnf install ansible-core"
    echo "  or Ubuntu:       apt install ansible-core"
    exit 1
fi

if [ ! -f "$INVENTORY" ]; then
    echo "ERROR: inventory not found: $INVENTORY"
    exit 1
fi

# --- Install required collections (no-op when already present) ---
echo "==> Checking ansible collection dependencies"
ansible-galaxy collection install -r "$REQUIREMENTS" >/dev/null 2>&1 \
    || ansible-galaxy collection install -r "$REQUIREMENTS"

run_playbook() {
    local name="$1"; shift
    local playbook="playbooks/${name}.yml"
    if [ ! -f "$playbook" ]; then
        echo "ERROR: playbook not found: $playbook"
        exit 1
    fi
    echo "==> Running $playbook"
    ansible-playbook -i "$INVENTORY" "$playbook" "$@"
}

case "${1:-}" in
    linux-init)
        shift; run_playbook linux-init "$@"
        ;;
    docker)
        shift; run_playbook docker "$@"
        ;;
    all)
        shift
        run_playbook linux-init "$@"
        run_playbook docker "$@"
        ;;
    *)
        echo "Usage: $0 {linux-init|docker|all} [extra args]"
        echo "Example: $0 all -l node1 --check"
        exit 1
        ;;
esac
