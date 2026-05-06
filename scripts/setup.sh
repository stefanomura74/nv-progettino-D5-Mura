#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

info() {
  printf "[INFO] %s\n" "$*"
}

fatal() {
  printf "[ERROR] %s\n" "$*" >&2
  exit 1
}

if ! command_exists docker; then
  fatal "Docker is not installed. Install Docker and retry."
fi

DOCKER_COMPOSE_CMD=""
if command_exists docker-compose; then
  DOCKER_COMPOSE_CMD="docker-compose"
elif docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker compose"
fi

cd "${PROJECT_ROOT}"

if [[ -f "docker-compose.yml" || -f "docker-compose.yaml" ]]; then
  if [[ -z "${DOCKER_COMPOSE_CMD}" ]]; then
    fatal "docker-compose is not available. Install docker-compose or use Docker Engine with Compose support."
  fi

  info "Found compose file. Building and starting services."
  ${DOCKER_COMPOSE_CMD} build --pull
  ${DOCKER_COMPOSE_CMD} up -d
  info "Docker Compose services are up."
  exit 0
fi

if [[ -f "Dockerfile" ]]; then
  IMAGE_NAME="${IMAGE_NAME:-$(basename "${PROJECT_ROOT}")}""
  info "Building Docker image '${IMAGE_NAME}:latest'."
  docker build -t "${IMAGE_NAME}:latest" .
  info "Docker image built successfully."
  exit 0
fi

fatal "No Dockerfile or docker-compose.yml found in ${PROJECT_ROOT}."