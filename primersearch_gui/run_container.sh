#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUI_DIR="${ROOT_DIR}/primersearch_gui"
RUNS_DIR="${GUI_DIR}/runs"

CONFIG_FILE="${CONFIG_FILE:-${GUI_DIR}/container.env}"
if [[ -f "${CONFIG_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
  set +a
fi

IMAGE_NAME="${IMAGE_NAME:-primersearch-gui}"
PLATFORM="${PLATFORM:-linux/amd64}"
SHINY_MAX_UPLOAD_MB="${SHINY_MAX_UPLOAD_MB:-2048}"
GENOMES_MOUNT="${GENOMES_MOUNT:-/data/GENOMES}"

mkdir -p "${RUNS_DIR}"

docker buildx build --platform="${PLATFORM}" \
  -f "${GUI_DIR}/Dockerfile" \
  -t "${IMAGE_NAME}" \
  --load \
  "${ROOT_DIR}"

run_args=(
  --rm
  --platform="${PLATFORM}"
  -p 3838:3838
  -e "SHINY_MAX_UPLOAD_MB=${SHINY_MAX_UPLOAD_MB}"
  -v "${RUNS_DIR}:/app/primersearch_gui/runs"
)

if [[ -n "${GENOMES_DIR:-}" ]]; then
  if [[ ! -d "${GENOMES_DIR}" ]]; then
    echo "GENOMES_DIR does not exist: ${GENOMES_DIR}" >&2
    exit 1
  fi
  run_args+=(-v "${GENOMES_DIR}:${GENOMES_MOUNT}:ro")
fi

docker run "${run_args[@]}" "${IMAGE_NAME}"
