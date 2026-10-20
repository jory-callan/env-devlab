#!/bin/bash

# One-click startup script for the VictoriaLogs + Fluent Bit + Grafana
# observability stack. Starts the components in dependency order and waits
# for each health check to pass.

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

# Load shared variables from .env when present
if [ -f "${MONITOR_DIR}/.env" ]; then
    set -a; . "${MONITOR_DIR}/.env"; set +a
fi
VICTORIA_LOGS_HOST=${VICTORIA_LOGS_HOST:-victorialogs}
VICTORIA_LOGS_PORT=${VICTORIA_LOGS_PORT:-9428}

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Observability stack startup script${NC}"
echo -e "${BLUE}================================${NC}"

# Check that Docker is running
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker is not running, please start the Docker service first${NC}"
    exit 1
fi

# Check that Docker Compose (v2) is available
if ! docker compose version >/dev/null 2>&1; then
    echo -e "${RED}ERROR: docker compose is not installed${NC}"
    exit 1
fi

# Make sure the shared network exists
if ! docker network ls --format '{{.Name}}' | grep -qx "net-shared"; then
    echo -e "${YELLOW}Creating the net-shared network...${NC}"
    docker network create net-shared >/dev/null
fi

# Function: wait for a service health endpoint
check_service_health() {
    local service_name="$1"
    local health_url="$2"
    local max_attempts=30
    local attempt=1

    echo -e "${YELLOW}Waiting for ${service_name} health check...${NC}"

    while [ $attempt -le $max_attempts ]; do
        if curl -sf "$health_url" >/dev/null 2>&1; then
            echo -e "${GREEN}OK: ${service_name} passed the health check${NC}"
            return 0
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done

    echo -e "\n${RED}FAILED: ${service_name} health check failed${NC}"
    return 1
}

# 1. Start VictoriaLogs
echo -e "\n${YELLOW}1. Starting VictoriaLogs...${NC}"
if [ -f "${VL_DIR}/docker-compose.yaml" ]; then
    cd "${VL_DIR}"
    docker compose down 2>/dev/null || true
    docker compose up -d
    check_service_health "VictoriaLogs" "http://localhost:9428/"
else
    echo -e "${RED}ERROR: ${VL_DIR}/docker-compose.yaml does not exist${NC}"
    exit 1
fi

# 2. Start Fluent Bit
echo -e "\n${YELLOW}2. Starting Fluent Bit...${NC}"
if [ -f "${FB_DIR}/docker-compose.yaml" ]; then
    cd "${FB_DIR}"
    docker compose down 2>/dev/null || true
    docker compose up -d
    check_service_health "Fluent Bit" "http://localhost:2020/"
else
    echo -e "${RED}ERROR: ${FB_DIR}/docker-compose.yaml does not exist${NC}"
    exit 1
fi

# 3. Start Grafana
echo -e "\n${YELLOW}3. Starting Grafana...${NC}"
if [ -f "${GF_DIR}/docker-compose.yaml" ]; then
    cd "${GF_DIR}"
    docker compose down 2>/dev/null || true
    docker compose up -d
    check_service_health "Grafana" "http://localhost:3000/api/health"
else
    echo -e "${RED}ERROR: ${GF_DIR}/docker-compose.yaml does not exist${NC}"
    exit 1
fi

# Show the service status
echo -e "\n${BLUE}================================${NC}"
echo -e "${GREEN}All services started!${NC}"
echo -e "${BLUE}================================${NC}"

echo -e "\n${GREEN}Service status:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(victorialogs|fluentbit|grafana)" || true

echo -e "\n${GREEN}Access URLs:${NC}"
echo -e "VictoriaLogs API: ${BLUE}http://localhost:9428${NC}"
echo -e "Grafana UI:       ${BLUE}http://localhost:3000${NC} (see ../.env for credentials)"
echo -e "Fluent Bit UI:    ${BLUE}http://localhost:2020${NC}"

echo -e "\n${YELLOW}Notes:${NC}"
echo -e "- To add custom log sources, see fluentbit/conf/custom-logs.conf"
echo -e "- Configuration files are in fluentbit/conf/"
echo -e "- Restart Fluent Bit after changing the configuration"

echo -e "\n${GREEN}Quick commands:${NC}"
echo -e "View logs:    ${BLUE}docker logs <container-name>${NC}"
echo -e "Restart:      ${BLUE}docker compose restart${NC}"
echo -e "Stop all:     ${BLUE}bash ${SCRIPT_DIR}/stop-all.sh${NC}"

echo -e "\n${GREEN}VictoriaLogs query examples:${NC}"
echo -e "${BLUE}curl \"http://localhost:9428/select/logsql/query\" -d 'query=*'${NC}"
echo -e "${BLUE}curl \"http://localhost:9428/select/logsql/query\" -d 'query=service:nginx'${NC}"

echo -e "\n${GREEN}Grafana data source:${NC}"
echo -e "Type: Loki (VictoriaLogs is LogQL-compatible)"
echo -e "URL:  http://${VICTORIA_LOGS_HOST}:${VICTORIA_LOGS_PORT}"

echo -e "\n${BLUE}================================${NC}"
echo -e "${GREEN}Observability stack startup complete!${NC}"
echo -e "${BLUE}================================${NC}"
