#!/usr/bin/env bash
# reset-task.sh <task-id> <agent> [project-dir]
#
# ERROR 또는 STALE 상태에 멈춘 태스크를 초기화해 재시도를 가능하게 한다.
# trigger.sh는 재실행 시 STATUS 파일을 자동으로 삭제하지만,
# 이 스크립트로 상태를 확인하고 수동 초기화할 수 있다.
#
# 사용법:
#   bash scripts/reset-task.sh T003 codex
#   bash scripts/reset-task.sh T003 codex /abs/path/to/project
#
# 이후 작업:
#   trigger.sh를 다시 실행하면 새 작업으로 처리된다.

set -euo pipefail

TASK_ID="${1:?task-id 필요 (예: T003)}"
AGENT="${2:?agent 필요 (codex 또는 agy)}"
PROJECT_DIR="${3:-$(pwd)}"

REPORTS_DIR="$PROJECT_DIR/_agent_reports"
STATUS_FILE="$REPORTS_DIR/.status_${TASK_ID}_${AGENT}"

echo ""
echo "[$TASK_ID / $AGENT] 상태 초기화"
echo "────────────────────────────────────────"

if [ ! -f "$STATUS_FILE" ]; then
    echo "  상태 파일 없음: $STATUS_FILE"
    echo "  → 이미 초기화되어 있거나 task-id/agent가 잘못됨"
    exit 0
fi

CURRENT=$(cat "$STATUS_FILE" 2>/dev/null | tr -d '[:space:]' || echo "(읽기 실패)")
echo "  현재 상태: $CURRENT"

case "$CURRENT" in
    ERROR|STALE|IN_PROGRESS)
        rm -f "$STATUS_FILE"
        echo "  ✅ 상태 파일 삭제됨 — trigger.sh를 다시 실행하세요"
        ;;
    DONE)
        echo "  ⚠️  이 태스크는 이미 DONE 상태입니다."
        echo "  정말 재실행하려면 수동으로 삭제하세요:"
        echo "    rm \"$STATUS_FILE\""
        exit 1
        ;;
    *)
        echo "  ⚠️  알 수 없는 상태: $CURRENT"
        rm -f "$STATUS_FILE"
        echo "  상태 파일 삭제됨"
        ;;
esac
