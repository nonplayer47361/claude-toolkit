#!/usr/bin/env bash
# analyze-limits.sh [project-dir]
#
# LOG.md의 [HOUR:XX] 태그를 분석해 에이전트별 시간대 리밋 빈도를 출력한다.
# Claude가 Phase 5 단계 1.5에서 배정 에이전트를 결정할 때 참고한다.
#
# 현재 시간대에 리밋이 잦은 에이전트는 우선순위를 한 단계 낮춰 배정한다:
#   리밋 횟수 >= 2 → 해당 에이전트 우선순위 -1 단계 (이번 시간대 한정)
#   리밋 횟수 >= 4 → 해당 에이전트 이번 시간대 건너뜀, 폴백으로 진행
#
# 사용법:
#   bash scripts/analyze-limits.sh
#   bash scripts/analyze-limits.sh /abs/path/to/project

set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
LOG_FILE="$PROJECT_DIR/_agent_reports/LOG.md"

if [ ! -f "$LOG_FILE" ]; then
    echo "오류: $LOG_FILE 없음" >&2
    exit 1
fi

CURRENT_HOUR=$(date "+%H" | sed 's/^0//')  # 앞 0 제거 (08 → 8)
CURRENT_HOUR="${CURRENT_HOUR:-0}"

# 현재 시간대 버킷 계산 (3시간 단위)
BUCKET_START=$(( (CURRENT_HOUR / 3) * 3 ))
BUCKET_END=$(( BUCKET_START + 3 ))
BUCKET_LABEL=$(printf "%02d-%02d" $BUCKET_START $BUCKET_END)

SEP="────────────────────────────────────────"

echo ""
echo "시간대 리밋 분석 (현재: ${CURRENT_HOUR}시 → 버킷: ${BUCKET_LABEL})"
echo "$SEP"

# LOG.md에서 리밋 행 추출
LIMIT_LINES=$(grep "⚠️ 리밋\|리밋" "$LOG_FILE" 2>/dev/null | grep "\[HOUR:" || true)

if [ -z "$LIMIT_LINES" ]; then
    echo "  데이터 없음 (리밋 이벤트가 아직 기록되지 않음)"
    echo ""
    echo "추천: 데이터 없음 → 기본 라우팅 테이블 사용"
    exit 0
fi

# 에이전트별 시간대 카운트
count_agent_bucket() {
    local agent="$1"
    local bstart="$2"
    local bend="$3"
    local count=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        hour_tag=$(echo "$line" | grep -o '\[HOUR:[0-9]*\]' | grep -o '[0-9]*' || true)
        [ -z "$hour_tag" ] && continue
        hour_num="${hour_tag:-0}"
        if echo "$line" | grep -qi "| *${agent} *|" 2>/dev/null; then
            if [ "$hour_num" -ge "$bstart" ] && [ "$hour_num" -lt "$bend" ]; then
                count=$(( count + 1 ))
            fi
        fi
    done <<< "$LIMIT_LINES"
    echo "$count"
}

CODEX_COUNT=$(count_agent_bucket "codex" "$BUCKET_START" "$BUCKET_END")
AGY_COUNT=$(count_agent_bucket "agy" "$BUCKET_START" "$BUCKET_END")

echo "  현재 버킷(${BUCKET_LABEL}) 리밋 횟수:"
echo "    codex: ${CODEX_COUNT}회"
echo "    agy:   ${AGY_COUNT}회"
echo ""

# 추천 출력
echo "배정 조정 추천:"
if [ "$CODEX_COUNT" -ge 4 ]; then
    echo "  ⚠️  codex: 이번 시간대 리밋 잦음(${CODEX_COUNT}회) → 건너뛰고 agy 우선 배정"
elif [ "$CODEX_COUNT" -ge 2 ]; then
    echo "  ⚠️  codex: 리밋 주의(${CODEX_COUNT}회) → 우선순위 한 단계 낮춤"
else
    echo "  ✅  codex: 이번 시간대 정상 (${CODEX_COUNT}회)"
fi

if [ "$AGY_COUNT" -ge 4 ]; then
    echo "  ⚠️  agy: 이번 시간대 리밋 잦음(${AGY_COUNT}회) → 건너뛰고 codex 우선 배정"
elif [ "$AGY_COUNT" -ge 2 ]; then
    echo "  ⚠️  agy: 리밋 주의(${AGY_COUNT}회) → 우선순위 한 단계 낮춤"
else
    echo "  ✅  agy: 이번 시간대 정상 (${AGY_COUNT}회)"
fi

echo ""

# 전체 시간대별 요약
echo "전체 시간대 요약:"
for bstart in 0 3 6 9 12 15 18 21; do
    bend=$(( bstart + 3 ))
    label=$(printf "%02d-%02d" $bstart $bend)
    c=$(count_agent_bucket "codex" "$bstart" "$bend")
    a=$(count_agent_bucket "agy" "$bstart" "$bend")
    marker=""
    [ "$bstart" -eq "$BUCKET_START" ] && marker=" ◀ 현재"
    printf "  %s  codex:%d  agy:%d%s\n" "$label" "$c" "$a" "$marker"
done
echo ""
