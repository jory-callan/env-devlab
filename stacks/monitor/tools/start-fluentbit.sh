#!/bin/bash

# Standalone startup script for Fluent Bit only.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_DIR="$(dirname "${SCRIPT_DIR}")"
FB_DIR="${MONITOR_DIR}/fluentbit"

# Load shared variables from .env when present
if [ -f "${MONITOR_DIR}/.env" ]; then
    set -a; . "${MONITOR_DIR}/.env"; set +a
fi
VICTORIA_LOGS_HOST=${VICTORIA_LOGS_HOST:-victorialogs}
VICTORIA_LOGS_PORT=${VICTORIA_LOGS_PORT:-9428}

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Fluent Bit startup script${NC}"
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
if [ ! -f "${FB_DIR}/docker-compose.yaml" ]; then
    echo -e "${RED}ERROR: ${FB_DIR}/docker-compose.yaml does not exist${NC}"
    exit 1
fi

echo -e "${YELLOW}Configuration:${NC}"
echo -e "VictoriaLogs address: ${BLUE}${VICTORIA_LOGS_HOST}:${VICTORIA_LOGS_PORT}${NC}"

# Hint for remote deployments
if [ "$VICTORIA_LOGS_HOST" = "127.0.0.1" ]; then
    echo -e "${YELLOW}Note: using the default VictoriaLogs address 127.0.0.1:9428${NC}"
    echo -e "${YELLOW}To connect to a remote VictoriaLogs, set the environment variables:${NC}"
    echo -e "${BLUE}export VICTORIA_LOGS_HOST=<VictoriaLogs server IP>${NC}"
    echo -e "${BLUE}export VICTORIA_LOGS_PORT=<VictoriaLogs port, default 9428>${NC}"
    echo ""
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

# Test the VictoriaLogs connection
echo -e "${YELLOW}Testing the VictoriaLogs connection...${NC}"
if curl -sf "http://${VICTORIA_LOGS_HOST}:${VICTORIA_LOGS_PORT}/" >/dev/null 2>&1; then
    echo -e "${GREEN}OK: VictoriaLogs is reachable${NC}"
else
    echo -e "${RED}FAILED: cannot connect to VictoriaLogs at ${VICTORIA_LOGS_HOST}:${VICTORIA_LOGS_PORT}${NC}"
    echo -e "${YELLOW}Please ensure:${NC}"
    echo -e "1. The VictoriaLogs service is running"
    echo -e "2. The network connection is working"
    echo -e "3. The firewall allows port ${VICTORIA_LOGS_PORT}"
    read -p "Continue starting Fluent Bit anyway? (y/n): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Start Fluent Bit
echo -e "\n${YELLOW}Starting Fluent Bit...${NC}"
cd "${FB_DIR}"
docker compose down 2>/dev/null || true

# Export the environment variables and start
export VICTORIA_LOGS_HOST
export VICTORIA_LOGS_PORT
docker compose up -d

# Health check
check_service_health "Fluent Bit" "http://localhost:2020/"

# Show the service status
echo -e "\n${BLUE}================================${NC}"
echo -e "${GREEN}Fluent Bit started!${NC}"
echo -e "${BLUE}================================${NC}"

echo -e "\n${GREEN}Service status:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep fluentbit || true

echo -e "\n${GREEN}Access URLs:${NC}"
echo -e "Fluent Bit UI:    ${BLUE}http://$(hostname -I | awk '{print $1}'):2020${NC}"
echo -e "Local monitoring: ${BLUE}http://localhost:2020${NC}"

echo -e "\n${GREEN}Log input ports:${NC}"
echo -e "Forward input: ${BLUE}$(hostname -I | awk '{print $1}'):24224${NC}"
echo -e "Syslog input:  ${BLUE}$(hostname -I | awk '{print $1}'):5140${NC}"

echo -e "\n${GREEN}Configuration:${NC}"
echo -e "VictoriaLogs target: ${BLUE}${VICTORIA_LOGS_HOST}:${VICTORIA_LOGS_PORT}${NC}"

echo -e "\n${GREEN}Test commands:${NC}"
echo -e "${BLUE}curl \"http://localhost:2020/\"${NC}"
echo -e "${BLUE}docker logs fluentbit${NC}"

echo -e "\n${GREEN}Stop command:${NC}"
echo -e "${BLUE}cd ${FB_DIR} && docker compose down${NC}"

echo -e "\n${BLUE}================================${NC}"
echo -e "${GREEN}Fluent Bit startup complete!${NC}"
echo -e "${BLUE}================================${NC}"
