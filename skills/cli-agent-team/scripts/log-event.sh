#!/usr/bin/env bash
# log-event.sh <task-id> <agent> <size> <result> <session-count> [memo]
#
# LOG.md의 이벤트 이력 테이블에 한 행을 자동으로 추가한다.
# Claude가 Phase 5 단계 6.5에서 수동으로 테이블 행을 편집하는 대신 이 스크립트를 호출한다.
#
# 인수:
#   task-id       예: T001
#   agent         예: codex | agy
#   size          예: 소형 | 중형 | 대형 | 분석
#   result        예: "✅ 완료" | "⚠️ 리밋" | "❌ 오류" | "🔁 폴백"
#   session-count 이 세션에서 해당 에이전트가 처리한 누적 작업 수 (단계 1.5 기준)
#   memo          (선택) 짧은 메모 — 공백이 있으면 따옴표로 감싸기
#
# 예시:
#   bash scripts/log-event.sh T001 codex 중형 "✅ 완료" 2
#   bash scripts/log-event.sh T002 agy 대형 "⚠️ 리밋" 3 "컨텍스트 초과"

set -euo pipefail

TASK_ID="${1:?task-id 필요 (예: T001)}"
AGENT="${2:?agent 필요 (codex | agy)}"
SIZE="${3:?size 필요 (소형 | 중형 | 대형 | 분석)}"
RESULT="${4:?result 필요 (\"✅ 완료\" | \"⚠️ 리밋\" | \"❌ 오류\" | \"🔁 폴백\")}"
SESSION_COUNT="${5:?session-count 필요 (숫자)}"
MEMO="${6:-}"

LOG_FILE="_agent_reports/LOG.md"

if [ ! -f "$LOG_FILE" ]; then
    echo "오류: $LOG_FILE 가 없습니다." >&2
    echo "  먼저 Phase 3에서 LOG.md를 초기화하세요 (task-templates.md 참고)." >&2
    exit 1
fi

TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
HOUR=$(date "+%H")

# 리밋 이벤트 발생 시 시간대 태그를 메모에 추가 — analyze-limits.sh가 나중에 파싱한다
if echo "$RESULT" | grep -q "리밋"; then
    if [ -n "$MEMO" ]; then
        MEMO="${MEMO} [HOUR:${HOUR}]"
    else
        MEMO="[HOUR:${HOUR}]"
    fi
fi

NEW_ROW="| ${TIMESTAMP} | ${TASK_ID} | ${AGENT} | ${SIZE} | ${RESULT} | ${SESSION_COUNT} | ${MEMO} |"

printf "%s\n" "$NEW_ROW" >> "$LOG_FILE"
echo "[log-event] LOG.md 업데이트 완료:"
echo "  $NEW_ROW"
