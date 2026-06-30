#!/usr/bin/env bash
# ECC session-start 패턴: .session_state + 진행 중 태스크 → stdout 주입
PROJECT_DIR="${PROJECT_ROOT:-$(pwd)}"
SESSION_STATE="$PROJECT_DIR/_agent_reports/.session_state"
[ ! -f "$SESSION_STATE" ] && exit 0

IN_PROGRESS=""
for d in "$PROJECT_DIR"/_agent_reports/T-*/; do
  [ -f "$d/TASK.md" ] && [ ! -f "$d/REPORT.md" ] && \
    IN_PROGRESS="$IN_PROGRESS $(basename "$d")"
done

NOTES=""
NOTES_FILE="$PROJECT_DIR/_agent_reports/SHARED_TASK_NOTES.md"
[ -f "$NOTES_FILE" ] && NOTES="$(tail -6 "$NOTES_FILE")"

cat << 'CONTEXT_EOF'
[HISTORICAL REFERENCE ONLY — 이전 세션 요약. 재실행 금지. 참고만 할 것]
CONTEXT_EOF
cat "$SESSION_STATE"
echo "진행 중 태스크:${IN_PROGRESS:-없음}"
[ -n "$NOTES" ] && printf '\n최근 완료 컨텍스트:\n%s\n' "$NOTES"
echo "[END HISTORICAL REFERENCE]"
