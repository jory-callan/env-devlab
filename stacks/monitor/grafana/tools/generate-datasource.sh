#!/bin/bash

# Generate the Grafana data source provisioning file for VictoriaLogs.
# Uses the VICTORIA_LOGS_HOST and VICTORIA_LOGS_PORT environment variables
# (defaults: victorialogs:9428) and writes datasources/victorialogs.yaml
# next to this script.

VICTORIA_LOGS_HOST=${VICTORIA_LOGS_HOST:-victorialogs}
VICTORIA_LOGS_PORT=${VICTORIA_LOGS_PORT:-9428}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/../datasources"
mkdir -p "${OUT_DIR}"

cat > "${OUT_DIR}/victorialogs.yaml" << EOF
apiVersion: 1

deleteDatasources:
  - name: VictoriaLogs
    orgId: 1

datasources:
  - name: VictoriaLogs
    type: prometheus
    uid: victorialogs
    access: proxy
    url: http://${VICTORIA_LOGS_HOST}:${VICTORIA_LOGS_PORT}/select/logsql
    isDefault: true
    editable: true
    orgId: 1
    version: 1
    jsonData:
      httpMethod: POST
      manageAlerts: true
      timeInterval: 30s
      queryTimeout: 60s
    secureJsonData: {}

  - name: VictoriaLogs-LogQL
    type: loki
    uid: victorialogs-logql
    access: proxy
    url: http://${VICTORIA_LOGS_HOST}:${VICTORIA_LOGS_PORT}
    isDefault: false
    editable: true
    orgId: 1
    version: 1
    jsonData:
      maxLines: 1000
      timeout: 60s
      httpHeaderName1: Content-Type
    secureJsonData:
      httpHeaderValue1: application/json
EOF

echo "Grafana data source configuration generated: VictoriaLogs at ${VICTORIA_LOGS_HOST}:${VICTORIA_LOGS_PORT}"
