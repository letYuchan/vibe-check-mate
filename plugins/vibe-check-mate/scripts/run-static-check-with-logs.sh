#!/usr/bin/env bash
# Intentionally NO `set -e`: lint/typecheck가 실패해도 둘 다 돌려서 전체 상태를 로그로 남겨야 함.

LOG_DIR=".check-static"
ACTION_FILE="$LOG_DIR/AGENT_ACTION_REQUIRED.md"

# 항상 최신 상태 유지
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"

echo "Running lint..."
pnpm run lint 2>&1 | tee "$LOG_DIR/lint.log"
LINT_EXIT=${PIPESTATUS[0]}

echo "Running typecheck..."
pnpm run typecheck 2>&1 | tee "$LOG_DIR/typecheck.log"
TYPECHECK_EXIT=${PIPESTATUS[0]}

# 에러 파일 추출
grep -h -Eo '([A-Za-z0-9_./-]+\.(ts|tsx|js|jsx))' \
  "$LOG_DIR/lint.log" \
  "$LOG_DIR/typecheck.log" \
  | sed 's#^\./##' \
  | while IFS= read -r file; do
    [ -f "$file" ] && printf '%s\n' "$file"
  done \
  | sort -u > "$LOG_DIR/error-files.txt" || true

if [ "$LINT_EXIT" -ne 0 ] || [ "$TYPECHECK_EXIT" -ne 0 ]; then
  cat > "$ACTION_FILE" <<'EOF'
# Agent Action Required

Static checks failed.

Use `static-auto-fix` immediately.

Primary evidence:
- `.check-static/lint.log`
- `.check-static/typecheck.log`
- `.check-static/error-files.txt`

Completion is not allowed while this file exists.
EOF
  echo "❌ Static checks failed. Logs saved in $LOG_DIR/"
  echo "ACTION REQUIRED: read $ACTION_FILE and run static-auto-fix."
  exit 1
fi

# 성공 시 제거
rm -rf "$LOG_DIR"

echo "✅ Static checks passed."
exit 0
