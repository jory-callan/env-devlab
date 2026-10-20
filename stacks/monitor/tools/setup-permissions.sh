#!/bin/bash

# Permission setup script for the observability stack (VictoriaLogs +
# Fluent Bit + Grafana). Creates the directory layout and fixes ownership
# so the containers can write to their data directories.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_DIR="$(dirname "${SCRIPT_DIR}")"
VL_DIR="${MONITOR_DIR}/victorialogs"
FB_DIR="${MONITOR_DIR}/fluentbit"
GF_DIR="${MONITOR_DIR}/grafana"

echo -e "${GREEN}Setting up observability stack permissions...${NC}"

# Must run as root (directory ownership changes)
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script as root: sudo $0${NC}"
    exit 1
fi

# Create the grafana user/group if missing (Grafana container uses UID 472)
if ! id -u 472 >/dev/null 2>&1; then
    useradd -r -u 472 -g root -s /bin/false grafana || true
fi

echo -e "${YELLOW}Creating directory structure...${NC}"

# Main directories
mkdir -p "${VL_DIR}/victoria-logs-data"
mkdir -p "${FB_DIR}/conf"
mkdir -p "${FB_DIR}/logs"
mkdir -p "${GF_DIR}/grafana-data"
mkdir -p "${GF_DIR}/dashboards"
mkdir -p "${GF_DIR}/datasources"

# VictoriaLogs permissions
echo -e "${YELLOW}Setting VictoriaLogs permissions...${NC}"
chown -R 1000:1000 "${VL_DIR}/victoria-logs-data"
chmod -R 755 "${VL_DIR}/victoria-logs-data"

# Fluent Bit permissions
echo -e "${YELLOW}Setting Fluent Bit permissions...${NC}"
chown -R root:root "${FB_DIR}/logs"
chmod -R 755 "${FB_DIR}/logs"
chmod -R 644 "${FB_DIR}/conf"

# Grafana permissions (the container runs with uid=472)
echo -e "${YELLOW}Setting Grafana permissions...${NC}"
chown -R 472:472 "${GF_DIR}/grafana-data"
chmod -R 755 "${GF_DIR}/grafana-data"
chmod -R 644 "${GF_DIR}/dashboards"

echo -e "${GREEN}Permission setup complete.${NC}"
