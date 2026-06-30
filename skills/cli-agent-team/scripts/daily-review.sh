#!/usr/bin/env bash
# daily-review.sh [project-dir] [date]
#
# .agent_metrics.json 을 읽어 일별 에이전트 효율 리뷰 문서를 생성한다.
# 출력: <project-dir>/daily/YYYY-MM-DD.md
#
# 사용법:
#   bash scripts/daily-review.sh                     # 오늘 날짜, 현재 디렉토리
#   bash scripts/daily-review.sh /abs/path/to/proj   # 특정 프로젝트
#   bash scripts/daily-review.sh . 2026-06-30        # 특정 날짜

set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
TARGET_DATE="${2:-$(date +%Y-%m-%d)}"
METRICS_FILE="$PROJECT_DIR/_agent_reports/.agent_metrics.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "[daily-review] jq 미설치 — 건너뜀" >&2
  exit 0
fi

if [ ! -f "$METRICS_FILE" ]; then
  echo "[daily-review] .agent_metrics.json 없음: $METRICS_FILE" >&2
  exit 1
fi

DAILY_DIR="$PROJECT_DIR/daily"
mkdir -p "$DAILY_DIR"
OUT_FILE="$DAILY_DIR/${TARGET_DATE}.md"

# 날짜 필터링
TODAY_RECORDS=$(jq -c --arg d "$TARGET_DATE" '[.[] | select(.date == $d)]' "$METRICS_FILE" 2>/dev/null || echo "[]")
TOTAL_TASKS=$(echo "$TODAY_RECORDS" | jq 'length' 2>/dev/null || echo 0)
ALL_RECORDS_COUNT=$(jq 'length' "$METRICS_FILE" 2>/dev/null || echo 0)

# ── 문서 생성 ─────────────────────────────────────────────────────────────────
{
printf '# 에이전트 효율 리뷰 — %s\n\n' "$TARGET_DATE"

printf '## 오늘 요약\n\n'

if [ "${TOTAL_TASKS:-0}" -eq 0 ]; then
  printf '오늘(%s) 완료된 태스크 없음 (전체 누적: %s건)\n' "$TARGET_DATE" "${ALL_RECORDS_COUNT:-0}"
else
  printf '| 에이전트 | 태스크 | AC 통과율 | 총 토큰 | 토큰/태스크 | 평균 소요 | 총 LOC | 토큰/LOC |\n'
  printf '|---------|--------|---------|---------|------------|---------|-------|--------|\n'

  echo "$TODAY_RECORDS" | jq -r '
    group_by(.agent) | .[] |
    . as $grp |
    ($grp | length) as $n |
    ($grp | map(.ac_pass) | add // 0) as $ap |
    ($grp | map(.ac_fail) | add // 0) as $af |
    ($grp | map(select(.tokens_used != null)) | length) as $with_tokens |
    ($grp | map(.tokens_used // 0) | add // 0) as $tok |
    ($grp | map(.elapsed_sec // 0) | add // 0) as $elapsed_sum |
    ($grp | map(.loc_added // 0) | add // 0) as $loc |
    ($grp[0].agent) as $agent |
    [
      $agent,
      ($n | tostring),
      (if ($ap + $af) > 0 then (($ap / ($ap + $af) * 100) | round | tostring) + "%" else "—" end),
      (if $with_tokens < $n then "—(미수집)" elif $tok > 0 then ($tok | tostring) else "0" end),
      (if $with_tokens < $n then "—" elif $n > 0 then (($tok / $n) | round | tostring) else "—" end),
      (if $n > 0 then (($elapsed_sum / $n) | round | tostring) + "s" else "—" end),
      ($loc | tostring),
      (if $with_tokens < $n then "—" elif $loc > 0 then (($tok / $loc) | round | tostring) else "—" end)
    ] | @tsv
  ' 2>/dev/null | while IFS=$'\t' read -r ag tks acp toks tpk elv loc tloc; do
    printf '| %-8s | %s건    | %-9s | %-9s | %-11s | %-9s | %-6s | %-8s |\n' \
      "$ag" "$tks" "$acp" "$toks" "$tpk" "$elv" "$loc" "$tloc"
  done || true

  printf '\n'

  # agy 토큰 미수집 확인
  AGY_NULL=$(echo "$TODAY_RECORDS" | jq '[.[] | select(.agent == "agy" and .tokens_used == null)] | length' 2>/dev/null || echo 0)
  if [ "${AGY_NULL:-0}" -gt 0 ]; then
    printf '> ⚠ agy 토큰 미수집(%s건) — agy --print 출력 샘플 확인 후 패턴 추가 예정\n\n' "$AGY_NULL"
  fi
fi

printf '## 태스크 유형별 효율 비교\n\n'

if [ "${TOTAL_TASKS:-0}" -eq 0 ]; then
  printf '오늘 데이터 없음\n'
else
  echo "$TODAY_RECORDS" | jq -r '
    group_by(.task_type) | .[] |
    . as $grp |
    ($grp[0].task_type) as $tt |
    ($grp | group_by(.agent) | map({
      agent: .[0].agent,
      tasks: length,
      ac_pass: (map(.ac_pass) | add // 0),
      ac_fail: (map(.ac_fail) | add // 0)
    })) as $agents |
    [$tt, ($agents | map("\(.agent):\(if (.ac_pass+.ac_fail)>0 then ((.ac_pass/(.ac_pass+.ac_fail)*100)|round|tostring)+"%" else "—" end)") | join(" vs "))]
    | @tsv
  ' 2>/dev/null | while IFS=$'\t' read -r tt agents; do
    printf '%s\n' "- **${tt}**: ${agents}"
  done || true
fi

printf '\n## 개별 태스크 기록\n\n'
printf '| task_id | agent | task_type | elapsed | tokens | loc+ | ac |\n'
printf '|---------|-------|-----------|---------|--------|------|----|\n'

echo "$TODAY_RECORDS" | jq -r '
  .[] |
  [
    .task_id,
    .agent,
    (.task_type // "—"),
    ((.elapsed_sec // 0) | tostring) + "s",
    (if .tokens_used == null then "—" else (.tokens_used | tostring) end),
    ((.loc_added // 0) | tostring),
    ((.ac_pass // 0) | tostring) + "/" + (((.ac_pass // 0) + (.ac_fail // 0)) | tostring)
  ] | @tsv
' 2>/dev/null | while IFS=$'\t' read -r tid ag tt el tok loc ac; do
  printf '| %-12s | %-6s | %-18s | %-7s | %-6s | %-4s | %s |\n' \
    "$tid" "$ag" "$tt" "$el" "$tok" "$loc" "$ac"
done || true

printf '\n## 다음 세션 Claude 배정 참고\n\n'

if [ "${TOTAL_TASKS:-0}" -eq 0 ]; then
  printf '오늘 데이터 없음 — 누적 .agent_scores.json 참고\n'
else
  echo "$TODAY_RECORDS" | jq -r '
    group_by(.agent) | .[] |
    . as $grp |
    ($grp[0].agent) as $ag |
    ($grp | map(.ac_pass) | add // 0) as $ap |
    ($grp | map(.ac_fail) | add // 0) as $af |
    ($ap + $af) as $tot |
    (if $tot > 0 then ($ap / $tot * 100 | round) else 0 end) as $rate |
    "- \($ag): \(length)건, AC 통과율 \($rate)%\(if $rate >= 80 then " [good]" elif $rate >= 60 then " [warn]" else " [low]" end)"
  ' 2>/dev/null || true
fi

printf '\n---\n생성: %s UTC\n' "$(date -u +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date)"
} > "$OUT_FILE"

echo "[daily-review] 생성: $OUT_FILE (태스크 ${TOTAL_TASKS}건)"
