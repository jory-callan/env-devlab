#!/bin/bash

# Standalone startup script for VictoriaLogs only.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_DIR="$(dirname "${SCRIPT_DIR}")"
VL_DIR="${MONITOR_DIR}/victorialogs"

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}VictoriaLogs startup script${NC}"
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

# Check that the compose file exists
if [ ! -f "${VL_DIR}/docker-compose.yaml" ]; then
    echo -e "${RED}ERROR: ${VL_DIR}/docker-compose.yaml does not exist${NC}"
    exit 1
fi

# Function: wait for the service health endpoint
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

# Start VictoriaLogs
echo -e "\n${YELLOW}Starting VictoriaLogs...${NC}"
cd "${VL_DIR}"
docker compose down 2>/dev/null || true
docker compose up -d

# Health check
check_service_health "VictoriaLogs" "http://localhost:9428/"

# Show the service status
echo -e "\n${BLUE}================================${NC}"
echo -e "${GREEN}VictoriaLogs started!${NC}"
echo -e "${BLUE}================================${NC}"

echo -e "\n${GREEN}Service status:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep victorialogs || true

echo -e "\n${GREEN}Access URLs:${NC}"
echo -e "VictoriaLogs API: ${BLUE}http://$(hostname -I | awk '{print $1}'):9428${NC}"
echo -e "Local access:     ${BLUE}http://localhost:9428${NC}"

echo -e "\n${GREEN}API test commands:${NC}"
echo -e "${BLUE}curl \"http://localhost:9428/\"${NC}"
echo -e "${BLUE}curl \"http://localhost:9428/select/logsql/query\" -d 'query=*'${NC}"

echo -e "\n${GREEN}Stop command:${NC}"
echo -e "${BLUE}cd ${VL_DIR} && docker compose down${NC}"

echo -e "\n${BLUE}================================${NC}"
echo -e "${GREEN}VictoriaLogs startup complete!${NC}"
echo -e "${BLUE}================================${NC}"
