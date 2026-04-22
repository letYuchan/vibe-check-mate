#!/usr/bin/env bash
# Intentionally NO `set -e`: dev:raw가 실패해도 뒷부분(에러 파일 추출, meta 갱신)이 실행돼야 함.

LOG_DIR=".check-runtime"
LOG_FILE="$LOG_DIR/runtime.log"
META_FILE="$LOG_DIR/meta.txt"
ERROR_FILES_FILE="$LOG_DIR/error-files.txt"

# 항상 최신 상태만 유지
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"

{
  echo "command=pnpm run dev:raw"
  echo "started_at=$(date '+%Y-%m-%d %H:%M:%S')"
} > "$META_FILE"

echo "🚀 Starting dev server..."
echo "📄 Runtime log: $LOG_FILE"
echo "⚠️  HMR 기반 dev server는 에러 발생 후에도 계속 실행됩니다."
echo "   에러가 로그에 찍힌 것을 확인한 뒤 Ctrl+C로 종료해야 .check-runtime/이 finalize됩니다."
echo ""

# Ctrl+C 시에도 meta/error-files 정리가 보장되도록 trap
trap 'echo ""; echo "[received SIGINT — finalizing logs...]"' INT

pnpm run dev:raw 2>&1 | tee "$LOG_FILE"
EXIT_CODE=${PIPESTATUS[0]}

# 로그에서 관련 파일 후보 추출
grep -h -Eo '([A-Za-z0-9_./-]+\.(ts|tsx|js|jsx))' "$LOG_FILE" \
  | sort -u > "$ERROR_FILES_FILE" || true

{
  echo "ended_at=$(date '+%Y-%m-%d %H:%M:%S')"
  echo "exit_code=$EXIT_CODE"
} >> "$META_FILE"

exit $EXIT_CODE
