#!/usr/bin/env bash
# Intentionally NO `set -e`: dev:raw may fail, but log finalization must still run.

LOG_DIR=".check-runtime"
LOG_FILE="$LOG_DIR/runtime.log"
META_FILE="$LOG_DIR/meta.txt"
ERROR_FILES_FILE="$LOG_DIR/error-files.txt"
RUNTIME_FIX_FILES_FILE="$LOG_DIR/runtime-fix-files.txt"
STATIC_GATE_ERROR_FILES_FILE="$LOG_DIR/static-gate-error-files.txt"
FIRST_ERROR_LOG="$LOG_DIR/first-error.log"
ERROR_SIGNATURE_FILE="$LOG_DIR/error-signature.txt"
SOURCE_CONTEXT_FILE="$LOG_DIR/source-context.md"
ACTION_FILE="$LOG_DIR/AGENT_ACTION_REQUIRED.md"
ERROR_COUNT_FILE="$LOG_DIR/error-count.txt"
CLIENT_ENDPOINT_FILE_NAME="client-error-endpoint.json"

AUTOKILL_ENABLED="${VIBE_DEV_AUTOKILL:-0}"
AUTOKILL_GRACE="${VIBE_DEV_AUTOKILL_GRACE:-2}"
CLIENT_ERROR_PORT_START="${VIBE_CLIENT_ERROR_PORT:-9876}"
CLIENT_ERROR_PORT_SCAN_LIMIT="${VIBE_CLIENT_ERROR_PORT_SCAN_LIMIT:-20}"
RUNTIME_CONTEXT_LINES="${VIBE_RUNTIME_CONTEXT_LINES:-180}"
SOURCE_CONTEXT_MAX_LINES="${VIBE_SOURCE_CONTEXT_MAX_LINES:-220}"
ERROR_PATTERNS='TypeError: |ReferenceError: |SyntaxError: |Uncaught |UnhandledPromise|Cannot find module |✘ \[ERROR\]|^Error: |\[CLIENT_ERROR\]|\[CLIENT_NETWORK\].*status=(4|5)[0-9][0-9]|\[CLIENT_NETWORK\].*failed=True'

choose_client_error_port() {
  python3 - "$CLIENT_ERROR_PORT_START" "$CLIENT_ERROR_PORT_SCAN_LIMIT" <<'PY'
import socket
import sys

start = int(sys.argv[1])
limit = int(sys.argv[2])

for port in range(start, start + limit + 1):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            continue
        print(port)
        raise SystemExit(0)

raise SystemExit(1)
PY
}

write_client_endpoint_files() {
  endpoint="http://localhost:${CLIENT_ERROR_PORT}"
  reporter_files="$(find . \
    \( -path './node_modules' -o -path './.git' -o -path './.check-static' -o -path './.check-runtime' \) -prune -o \
    -name 'client-error-reporter.js' ! -path './scripts/*' -type f -print)"

  if [ -z "$reporter_files" ]; then
    return
  fi

  printf '%s\n' "$reporter_files" |
  while IFS= read -r reporter_file; do
    reporter_dir="$(dirname "$reporter_file")"
    endpoint_file="${reporter_dir}/${CLIENT_ENDPOINT_FILE_NAME}"
    printf '{"endpoint":"%s"}\n' "$endpoint" > "$endpoint_file"
  done

  echo "Client error endpoint config: ${CLIENT_ENDPOINT_FILE_NAME} -> ${endpoint}"
}

PRESERVED_RUNTIME_FIX_FILES=""
PRESERVED_STATIC_GATE_ERROR_FILES=""
if [ -f "$RUNTIME_FIX_FILES_FILE" ]; then
  PRESERVED_RUNTIME_FIX_FILES="$(mktemp)"
  cp "$RUNTIME_FIX_FILES_FILE" "$PRESERVED_RUNTIME_FIX_FILES"
elif [ -f "$ERROR_FILES_FILE" ] && [ -f "$ACTION_FILE" ]; then
  PRESERVED_RUNTIME_FIX_FILES="$(mktemp)"
  cp "$ERROR_FILES_FILE" "$PRESERVED_RUNTIME_FIX_FILES"
fi
if [ -f "$STATIC_GATE_ERROR_FILES_FILE" ]; then
  PRESERVED_STATIC_GATE_ERROR_FILES="$(mktemp)"
  cp "$STATIC_GATE_ERROR_FILES_FILE" "$PRESERVED_STATIC_GATE_ERROR_FILES"
fi

rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"

if [ -n "$PRESERVED_RUNTIME_FIX_FILES" ] && [ -f "$PRESERVED_RUNTIME_FIX_FILES" ]; then
  cp "$PRESERVED_RUNTIME_FIX_FILES" "$RUNTIME_FIX_FILES_FILE"
  rm -f "$PRESERVED_RUNTIME_FIX_FILES"
fi
if [ -n "$PRESERVED_STATIC_GATE_ERROR_FILES" ] && [ -f "$PRESERVED_STATIC_GATE_ERROR_FILES" ]; then
  cp "$PRESERVED_STATIC_GATE_ERROR_FILES" "$STATIC_GATE_ERROR_FILES_FILE"
  rm -f "$PRESERVED_STATIC_GATE_ERROR_FILES"
fi

{
  echo "mode=live"
  echo "command=pnpm run dev:raw"
  echo "started_at=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "first_snapshot_locked=false"
  echo "autokill_enabled=$AUTOKILL_ENABLED"
  echo "client_error_port_start=$CLIENT_ERROR_PORT_START"
} > "$META_FILE"

echo "Starting dev server..."
echo "Runtime log: $LOG_FILE"
echo "First runtime error snapshot: $FIRST_ERROR_LOG"
if [ "$AUTOKILL_ENABLED" = "1" ]; then
  echo "Runtime auto-kill: enabled by VIBE_DEV_AUTOKILL=1"
else
  echo "Runtime auto-kill: disabled. Dev server will stay alive while evidence is captured."
fi
echo ""

cleanup() {
  [ -n "${TAIL_PID:-}" ] && kill "$TAIL_PID" 2>/dev/null
  [ -n "${WATCHER_PID:-}" ] && kill "$WATCHER_PID" 2>/dev/null
  [ -n "${RECEIVER_PID:-}" ] && kill "$RECEIVER_PID" 2>/dev/null
}
trap 'echo ""; echo "[received SIGINT - finalizing logs...]"; cleanup' INT

extract_error_files() {
  grep -h -Eo '([A-Za-z0-9_./-]+\.(ts|tsx|js|jsx))' "$LOG_FILE" "$FIRST_ERROR_LOG" 2>/dev/null \
    | grep -v 'node_modules/' \
    | sed 's#^\./##' \
    | while IFS= read -r file; do
      [ -f "$file" ] && printf '%s\n' "$file"
    done \
    | sort -u > "$ERROR_FILES_FILE" || true
}

write_source_context() {
  {
    echo "# Runtime Source Context"
    echo ""
    echo "Generated from the first runtime error snapshot."
    echo "Prefer this first snapshot over later repeated live logs."
    echo ""
    echo "## Candidate Files"
    echo ""
    if [ -s "$ERROR_FILES_FILE" ]; then
      sed 's/^/- `/' "$ERROR_FILES_FILE" | sed 's/$/`/'
    else
      echo "- No local source file candidates were extracted from the first error."
    fi
    echo ""
    echo "## Source Excerpts"
    echo ""
  } > "$SOURCE_CONTEXT_FILE"

  if [ -s "$ERROR_FILES_FILE" ]; then
    while IFS= read -r file; do
      if [ -f "$file" ]; then
        {
          echo "### $file"
          echo ""
          echo '```text'
          nl -ba "$file" | sed -n "1,${SOURCE_CONTEXT_MAX_LINES}p"
          echo '```'
          echo ""
        } >> "$SOURCE_CONTEXT_FILE"
      fi
    done < "$ERROR_FILES_FILE"
  fi
}

write_action_file() {
  cat > "$ACTION_FILE" <<'EOF'
# Agent Action Required

Runtime failure captured.

Use `runtime-auto-fix` immediately.

Primary evidence:
- `.check-runtime/first-error.log`
- `.check-runtime/error-signature.txt`
- `.check-runtime/source-context.md`
- `.check-runtime/runtime.log`

Completion is not allowed while this file exists.
EOF
}

capture_first_error() {
  if [ -f "$FIRST_ERROR_LOG" ]; then
    return
  fi

  tail -n "$RUNTIME_CONTEXT_LINES" "$LOG_FILE" > "$FIRST_ERROR_LOG" 2>/dev/null || true
  grep -m 1 -E "$ERROR_PATTERNS" "$LOG_FILE" > "$ERROR_SIGNATURE_FILE" 2>/dev/null || true
  extract_error_files
  cp "$ERROR_FILES_FILE" "$RUNTIME_FIX_FILES_FILE" 2>/dev/null || true
  write_source_context
  write_action_file

  {
    echo "first_error_at=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "first_snapshot_locked=true"
  } >> "$META_FILE"

  echo ""
  echo "[vibe-check-mate: first runtime error snapshot captured]"
  echo "Action file: $ACTION_FILE"
}

# Start client error receiver when available.
if [ -f "./scripts/client-error-receiver.py" ] && command -v python3 >/dev/null 2>&1; then
  CLIENT_ERROR_PORT="$(choose_client_error_port || true)"
  if [ -z "$CLIENT_ERROR_PORT" ]; then
    CLIENT_ERROR_PORT="$CLIENT_ERROR_PORT_START"
    echo "Client error receiver: no free port found from ${CLIENT_ERROR_PORT_START} to $((CLIENT_ERROR_PORT_START + CLIENT_ERROR_PORT_SCAN_LIMIT)); browser evidence disabled."
  else
    write_client_endpoint_files
  fi
  echo "client_error_port=$CLIENT_ERROR_PORT" >> "$META_FILE"
  VIBE_LOG_FILE="$LOG_FILE" VIBE_CLIENT_ERROR_PORT="$CLIENT_ERROR_PORT" \
    python3 ./scripts/client-error-receiver.py >/dev/null 2>&1 &
  RECEIVER_PID=$!
  disown "$RECEIVER_PID" 2>/dev/null || true
  echo "Client error receiver: http://localhost:${CLIENT_ERROR_PORT}"
fi

pnpm run dev:raw > "$LOG_FILE" 2>&1 &
DEV_PID=$!
echo "dev_pid=$DEV_PID" >> "$META_FILE"

tail -f "$LOG_FILE" 2>/dev/null &
TAIL_PID=$!
disown "$TAIL_PID" 2>/dev/null || true

(
  sleep 2
  LAST_ERROR_COUNT=0
  while kill -0 "$DEV_PID" 2>/dev/null; do
    ERROR_COUNT=$(grep -Ec "$ERROR_PATTERNS" "$LOG_FILE" 2>/dev/null || true)
    ERROR_COUNT="${ERROR_COUNT:-0}"
    echo "$ERROR_COUNT" > "$ERROR_COUNT_FILE"

    if [ "$ERROR_COUNT" -gt 0 ]; then
      if [ "$ERROR_COUNT" -gt "$LAST_ERROR_COUNT" ]; then
        {
          echo "last_error_at=$(date '+%Y-%m-%d %H:%M:%S')"
          echo "error_count=$ERROR_COUNT"
        } >> "$META_FILE"
      fi
      capture_first_error

      if [ "$AUTOKILL_ENABLED" = "1" ]; then
        sleep "$AUTOKILL_GRACE"
        echo ""
        echo "[vibe-check-mate: VIBE_DEV_AUTOKILL=1, terminating dev server]"
        kill -INT "$DEV_PID" 2>/dev/null
        break
      fi
    fi

    LAST_ERROR_COUNT="$ERROR_COUNT"
    sleep 1
  done
) &
WATCHER_PID=$!
disown "$WATCHER_PID" 2>/dev/null || true

wait "$DEV_PID"
EXIT_CODE=$?

cleanup
extract_error_files

{
  echo "ended_at=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "exit_code=$EXIT_CODE"
} >> "$META_FILE"

exit "$EXIT_CODE"
