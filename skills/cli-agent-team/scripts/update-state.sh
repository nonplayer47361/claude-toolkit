#!/usr/bin/env bash
# update-state.sh <field> <value> [project-dir]
#
# _agent_reports/.session_state 파일의 특정 필드를 갱신하는 헬퍼 스크립트
# Claude가 Phase 5 등 각 단계에서 루프 상태를 업데이트하기 위해 사용
#
# 사용법:
#   bash scripts/update-state.sh "루프 상태" "단계 3 리뷰 중"
#   bash scripts/update-state.sh "현재 작업" "T004 배포 (codex · 프론트 · auth 구현)"
#   bash scripts/update-state.sh "BLOCKED" "T003 (3일 째 미결)"
#
# 지원 필드: 루프 상태 / 현재 작업 / 에러요약 / BLOCKED / 루프 모드 / 리뷰 주기 / 루프 프롬프트
set -euo pipefail

FIELD="${1:?첫번째 인자 필드명 필요 (예: \"루프 상태\")}"
VALUE="${2:?두번째 인자 값 필요 (예: \"단계 3 리뷰 중\")}"
PROJECT_DIR="${3:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/_agent_reports/.session_state"

if [ ! -f "$STATE_FILE" ]; then
    echo "오류: $STATE_FILE 없음. Phase 3에서 .session_state를 먼저 생성하세요." >&2
    exit 1
fi

# 임시 파일 이름 (PID 포함으로 충돌 방지)
TMP_FILE="${STATE_FILE}.tmp.$$"

# EXIT trap: 스크립트가 어떤 이유로든 종료될 때 임시 파일 정리
trap 'rm -f "${TMP_FILE:-}" 2>/dev/null' EXIT

TIMESTAMP=$(date "+%Y-%m-%d %H:%M")

# 쓰기 전 기존 파일 백업
if [ -f "$STATE_FILE" ]; then
    cp "$STATE_FILE" "${STATE_FILE}.bak" 2>/dev/null || true
fi

# 임시 파일에 먼저 쓰기 (macOS/Linux 공용 방식, sed -i 차이 무관)
sed "s|^${FIELD}:.*|${FIELD}: ${VALUE}|; s|^갱신:.*|갱신: ${TIMESTAMP}|" "$STATE_FILE" > "$TMP_FILE"

# 원자적 rename으로 최종 반영
mv -f "$TMP_FILE" "$STATE_FILE"

echo "[update-state] ${FIELD}: ${VALUE}  (${TIMESTAMP})"
