#!/bin/bash

# One-click stop script for the observability stack (VictoriaLogs +
# Fluent Bit + Grafana). Stops the components in reverse dependency order
# and optionally cleans up containers, networks and dangling volumes.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_DIR="$(dirname "${SCRIPT_DIR}")"
VL_DIR="${MONITOR_DIR}/victorialogs"
FB_DIR="${MONITOR_DIR}/fluentbit"
GF_DIR="${MONITOR_DIR}/grafana"

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Observability stack stop script${NC}"
echo -e "${BLUE}================================${NC}"

# 1. Stop Grafana
echo -e "\n${YELLOW}1. Stopping Grafana...${NC}"
if [ -f "${GF_DIR}/docker-compose.yaml" ]; then
    cd "${GF_DIR}"
    docker compose down 2>/dev/null || true
    echo -e "${GREEN}OK: Grafana stopped${NC}"
else
    echo -e "${YELLOW}WARNING: Grafana compose file not found, skipping${NC}"
fi

# 2. Stop Fluent Bit
echo -e "\n${YELLOW}2. Stopping Fluent Bit...${NC}"
if [ -f "${FB_DIR}/docker-compose.yaml" ]; then
    cd "${FB_DIR}"
    docker compose down 2>/dev/null || true
    echo -e "${GREEN}OK: Fluent Bit stopped${NC}"
else
    echo -e "${YELLOW}WARNING: Fluent Bit compose file not found, skipping${NC}"
fi

# 3. Stop VictoriaLogs
echo -e "\n${YELLOW}3. Stopping VictoriaLogs...${NC}"
if [ -f "${VL_DIR}/docker-compose.yaml" ]; then
    cd "${VL_DIR}"
    docker compose down 2>/dev/null || true
    echo -e "${GREEN}OK: VictoriaLogs stopped${NC}"
else
    echo -e "${YELLOW}WARNING: VictoriaLogs compose file not found, skipping${NC}"
fi

# 4. Clean up leftover containers
echo -e "\n${YELLOW}4. Cleaning up related containers...${NC}"
CONTAINERS_TO_REMOVE=$(docker ps -a --filter "name=victorialogs" --filter "name=fluentbit" --filter "name=grafana" -q 2>/dev/null || true)

if [ -n "$CONTAINERS_TO_REMOVE" ]; then
    echo -e "${YELLOW}Found related containers, removing them...${NC}"
    docker rm -f $CONTAINERS_TO_REMOVE 2>/dev/null || true
    echo -e "${GREEN}OK: container cleanup complete${NC}"
else
    echo -e "${GREEN}OK: no containers to clean up${NC}"
fi

# 5. Network cleanup (interactive)
echo -e "\n${YELLOW}5. Cleaning up the network...${NC}"
if docker network ls --format '{{.Name}}' | grep -qx "net-shared"; then
    echo -e "${YELLOW}Remove the net-shared network? (y/n): ${NC}"
    read -r REMOVE_NETWORK
    if [[ $REMOVE_NETWORK =~ ^[Yy]$ ]]; then
        docker network rm net-shared 2>/dev/null || true
        echo -e "${GREEN}OK: network removed${NC}"
    else
        echo -e "${YELLOW}WARNING: keeping the net-shared network${NC}"
    fi
else
    echo -e "${GREEN}OK: the net-shared network does not exist${NC}"
fi

# 6. Dangling volume cleanup (interactive)
echo -e "\n${YELLOW}6. Cleaning up Docker volumes...${NC}"
VOLUMES_TO_REMOVE=$(docker volume ls --filter "dangling=true" -q 2>/dev/null || true)
if [ -n "$VOLUMES_TO_REMOVE" ]; then
    echo -e "${YELLOW}Remove unused Docker volumes? (y/n): ${NC}"
    read -r REMOVE_VOLUMES
    if [[ $REMOVE_VOLUMES =~ ^[Yy]$ ]]; then
        docker volume rm $VOLUMES_TO_REMOVE 2>/dev/null || true
        echo -e "${GREEN}OK: unused volumes removed${NC}"
    fi
else
    echo -e "${GREEN}OK: no unused volumes to remove${NC}"
fi

# Show the current status
echo -e "\n${BLUE}================================${NC}"
echo -e "${GREEN}Stop operation complete!${NC}"
echo -e "${BLUE}================================${NC}"

echo -e "\n${GREEN}Currently running related containers:${NC}"
RUNNING_CONTAINERS=$(docker ps --filter "name=victorialogs" --filter "name=fluentbit" --filter "name=grafana" --format "{{.Names}}" 2>/dev/null || true)

if [ -n "$RUNNING_CONTAINERS" ]; then
    echo -e "${RED}WARNING: the following containers are still running:${NC}"
    echo "$RUNNING_CONTAINERS"
    echo -e "\n${YELLOW}To force-stop them, run:${NC}"
    echo -e "${BLUE}docker stop \$(docker ps -q --filter \"name=victorialogs\" --filter \"name=fluentbit\" --filter \"name=grafana\")${NC}"
else
    echo -e "${GREEN}OK: all related containers are stopped${NC}"
fi

echo -e "\n${GREEN}Data directory status:${NC}"
echo -e "VictoriaLogs data: ${VL_DIR}/victoria-logs-data"
echo -e "Grafana data:      ${GF_DIR}/grafana-data"
echo -e "Log directory:     ${FB_DIR}/logs"

echo -e "\n${YELLOW}Notes:${NC}"
echo -e "- Data directories are NOT deleted; history is kept on restart"
echo -e "- To clean up completely, delete the data folders manually"
echo -e "- To start again: bash ${SCRIPT_DIR}/start-all.sh"

echo -e "\n${BLUE}================================${NC}"
echo -e "${GREEN}Observability stack stopped!${NC}"
echo -e "${BLUE}================================${NC}"
