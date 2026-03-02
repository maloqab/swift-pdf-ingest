#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PDF_DIR=""
MANIFEST_PATH=""
DB_PATH="${REPO_ROOT}/runtime/data/pipeline.sqlite"
SEEN_FILE="${REPO_ROOT}/runtime/state/seen-pdfs.txt"
STATE_FILE="${REPO_ROOT}/runtime/state/swift_ingest_state.json"
MAX_DOCS="25"
TIMEOUT_SECONDS=""
OCR_FALLBACK="on"

usage() {
  cat <<'EOF'
Usage: scripts/run_ingest.sh --pdf-dir <dir> --manifest <path> [options]

Required:
  --pdf-dir <dir>           Directory containing PDF files to ingest
  --manifest <path>         Source manifest JSON file

Optional:
  --db-path <path>          SQLite output path (default: runtime/data/pipeline.sqlite)
  --seen-file <path>        Seen signatures file (default: runtime/state/seen-pdfs.txt)
  --state-file <path>       Runtime state JSON path (default: runtime/state/swift_ingest_state.json)
  --max-docs <n>            Max PDFs per invocation (default: 25)
  --timeout-seconds <n>     Optional processing deadline in seconds
  --ocr-fallback <on|off>   Vision OCR fallback toggle (default: on)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pdf-dir)
      PDF_DIR="$2"; shift 2 ;;
    --manifest)
      MANIFEST_PATH="$2"; shift 2 ;;
    --db-path)
      DB_PATH="$2"; shift 2 ;;
    --seen-file)
      SEEN_FILE="$2"; shift 2 ;;
    --state-file)
      STATE_FILE="$2"; shift 2 ;;
    --max-docs)
      MAX_DOCS="$2"; shift 2 ;;
    --timeout-seconds)
      TIMEOUT_SECONDS="$2"; shift 2 ;;
    --ocr-fallback)
      OCR_FALLBACK="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "run_ingest error: unknown argument $1" >&2
      usage
      exit 2 ;;
  esac
done

if [[ -z "${PDF_DIR}" || -z "${MANIFEST_PATH}" ]]; then
  echo "run_ingest error: --pdf-dir and --manifest are required" >&2
  usage
  exit 2
fi

mkdir -p "$(dirname "${DB_PATH}")" "$(dirname "${SEEN_FILE}")" "$(dirname "${STATE_FILE}")"

BIN_DIR="$(cd "${REPO_ROOT}" && swift build --product SwiftIngestRuntime --show-bin-path)"
BIN_PATH="${BIN_DIR}/SwiftIngestRuntime"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "run_ingest error: SwiftIngestRuntime binary missing at ${BIN_PATH}" >&2
  exit 2
fi

CMD=(
  "${BIN_PATH}"
  --inbox "${PDF_DIR}"
  --source-manifest "${MANIFEST_PATH}"
  --db-path "${DB_PATH}"
  --seen-file "${SEEN_FILE}"
  --state-file "${STATE_FILE}"
  --max-docs "${MAX_DOCS}"
  --ocr-fallback "${OCR_FALLBACK}"
)

if [[ -n "${TIMEOUT_SECONDS}" ]]; then
  CMD+=(--timeout-seconds "${TIMEOUT_SECONDS}")
fi

exec "${CMD[@]}"
