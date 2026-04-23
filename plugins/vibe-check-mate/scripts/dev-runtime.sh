#!/usr/bin/env bash
# Intentionally NO `set -e`: dev:raw가 실패해도 뒷부분(에러 파일 추출, meta 갱신)이 실행돼야 함.

LOG_DIR=".check-runtime"
LOG_FILE="$LOG_DIR/runtime.log"
META_FILE="$LOG_DIR/meta.txt"
ERROR_FILES_FILE="$LOG_DIR/error-files.txt"

# Auto-kill 설정
AUTOKILL_GRACE="${VIBE_DEV_AUTOKILL_GRACE:-2}"      # 에러 감지 후 대기 초수 (스택트레이스 수집 여유)
AUTOKILL_DISABLED="${VIBE_DEV_NO_AUTOKILL:-0}"      # 1로 설정 시 auto-kill 비활성화
ERROR_PATTERNS='TypeError: |ReferenceError: |SyntaxError: |Uncaught |UnhandledPromise|Cannot find module |✘ \[ERROR\]|^Error: '

rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"

{
  echo "command=pnpm run dev:raw"
  echo "started_at=$(date '+%Y-%m-%d %H:%M:%S')"
} > "$META_FILE"

echo "🚀 Starting dev server..."
echo "📄 Runtime log: $LOG_FILE"
if [ "$AUTOKILL_DISABLED" = "1" ]; then
  echo "⚠️  Auto-kill disabled — HMR server continues after error. Ctrl+C로 직접 종료해야 .check-runtime/이 finalize됩니다."
else
  echo "🤖 Auto-kill on runtime error: enabled (disable with VIBE_DEV_NO_AUTOKILL=1)"
fi
echo ""

cleanup() {
  [ -n "${TAIL_PID:-}" ] && kill "$TAIL_PID" 2>/dev/null
  [ -n "${WATCHER_PID:-}" ] && kill "$WATCHER_PID" 2>/dev/null
}
trap 'echo ""; echo "[received SIGINT — finalizing logs...]"; cleanup' INT

# dev 서버는 log 파일로 출력
pnpm run dev:raw > "$LOG_FILE" 2>&1 &
DEV_PID=$!

# 사용자 터미널에도 실시간 표시
tail -f "$LOG_FILE" &
TAIL_PID=$!

# Watcher: 에러 패턴 감지 시 grace period 후 auto-kill
if [ "$AUTOKILL_DISABLED" != "1" ]; then
  (
    # 초기 2초: dev server 배너 안에 에러 단어가 섞여있을 가능성 우회
    sleep 2
    while kill -0 "$DEV_PID" 2>/dev/null; do
      if grep -qE "$ERROR_PATTERNS" "$LOG_FILE" 2>/dev/null; then
        sleep "$AUTOKILL_GRACE"
        echo ""
        echo "[vibe-check-mate auto-kill: runtime error detected — terminating dev server to finalize .check-runtime/]"
        kill -INT "$DEV_PID" 2>/dev/null
        break
      fi
      sleep 1
    done
  ) &
  WATCHER_PID=$!
fi

wait "$DEV_PID"
EXIT_CODE=$?

cleanup

# 로그에서 관련 파일 후보 추출
grep -h -Eo '([A-Za-z0-9_./-]+\.(ts|tsx|js|jsx))' "$LOG_FILE" \
  | sort -u > "$ERROR_FILES_FILE" || true

{
  echo "ended_at=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "exit_code=$EXIT_CODE"
} >> "$META_FILE"

exit "$EXIT_CODE"
