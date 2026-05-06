#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "Stopping and removing containers, networks, volumes and images..."
docker compose down --volumes --remove-orphans

echo "Removing dangling images and unused resources..."
docker image prune -af
docker network prune -f
docker volume prune -f

echo "Teardown complete."
