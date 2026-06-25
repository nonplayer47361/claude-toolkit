#!/usr/bin/env bash
# update-state.sh <field> <value> [project-dir]
#
# _agent_reports/.session_state 의 특정 필드를 업데이트하고 갱신 시각을 기록한다.
# Claude가 Phase 5 각 단계 전·후에 호출해 루프 상태를 정확히 추적한다.
#
# 사용법:
#   bash scripts/update-state.sh "루프 상태" "단계 3 완료 대기"
#   bash scripts/update-state.sh "다음 행동" "T004 배정 (codex · 중형 · auth 구현)"
#   bash scripts/update-state.sh "BLOCKED" "T003 (3회 피드백 미해결)"
#
# 지원 필드: 루프 상태 / 다음 행동 / 마일스톤 / BLOCKED / 루프 모드 / 리셋 주기 / 루프 프롬프트

set -euo pipefail

FIELD="${1:?필드명 필요 (예: \"루프 상태\")}"
VALUE="${2:?값 필요 (예: \"단계 3 완료 대기\")}"
PROJECT_DIR="${3:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/_agent_reports/.session_state"

if [ ! -f "$STATE_FILE" ]; then
    echo "오류: $STATE_FILE 없음. Phase 3에서 .session_state를 먼저 생성하세요." >&2
    exit 1
fi

TIMESTAMP=$(date "+%Y-%m-%d %H:%M")

# mktemp로 임시 파일 생성 (macOS/Linux 공통 방식 — sed -i 차이 회피)
TMPFILE=$(mktemp)
sed "s|^${FIELD}:.*|${FIELD}: ${VALUE}|; s|^갱신:.*|갱신: ${TIMESTAMP}|" "$STATE_FILE" > "$TMPFILE"
mv "$TMPFILE" "$STATE_FILE"

echo "[update-state] ${FIELD}: ${VALUE}  (${TIMESTAMP})"
