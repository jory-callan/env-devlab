#!/bin/bash
# Create the shared Docker bridge network used by all stacks.
# Every stack attaches to "net-shared" so containers can resolve each other
# by container name. Run this once per Docker host (idempotent).
set -e

NETWORK_NAME="net-shared"
SUBNET="172.21.0.0/16"

if docker network ls --format '{{.Name}}' | grep -qx "${NETWORK_NAME}"; then
  echo "Network ${NETWORK_NAME} already exists, nothing to do."
else
  docker network create --driver bridge --subnet="${SUBNET}" "${NETWORK_NAME}"
  echo "Network ${NETWORK_NAME} created (driver=bridge, subnet=${SUBNET})."
fi
