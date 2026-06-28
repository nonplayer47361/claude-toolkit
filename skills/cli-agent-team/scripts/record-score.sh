#!/usr/bin/env bash
# record-score.sh — 에이전트 태스크 성능 점수 기록 스크립트
# Usage: bash record-score.sh <agent> <task_type> <ac_pass> <ac_fail>
#
# 유효한 agent 값: agy, codex
# 유효한 task_type 값: shell_scripting, documentation, code_implementation, testing, refactoring

set -euo pipefail

# ─── 상수 ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SCORES_FILE="$PROJECT_ROOT/_agent_reports/.agent_scores.json"

VALID_AGENTS=("agy" "codex")
VALID_TASK_TYPES=("shell_scripting" "documentation" "code_implementation" "testing" "refactoring")

# ─── 의존성 확인 ─────────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq 가 설치되지 않았습니다. brew install jq / apt install jq 로 설치하세요." >&2
  exit 1
fi

# ─── 인수 파싱 ───────────────────────────────────────────────────────────────
if [[ $# -ne 4 ]]; then
  echo "Usage: bash record-score.sh <agent> <task_type> <ac_pass> <ac_fail>" >&2
  echo "  agent     : agy | codex" >&2
  echo "  task_type : shell_scripting | documentation | code_implementation | testing | refactoring" >&2
  echo "  ac_pass   : 통과한 AC 수 (정수)" >&2
  echo "  ac_fail   : 실패한 AC 수 (정수)" >&2
  exit 1
fi

AGENT="$1"
TASK_TYPE="$2"
AC_PASS="$3"
AC_FAIL="$4"

# ─── 인수 유효성 검사 ────────────────────────────────────────────────────────
is_valid_agent=false
for v in "${VALID_AGENTS[@]}"; do
  [[ "$AGENT" == "$v" ]] && is_valid_agent=true && break
done
if [[ "$is_valid_agent" == false ]]; then
  echo "ERROR: 유효하지 않은 agent '${AGENT}'. 유효한 값: ${VALID_AGENTS[*]}" >&2
  exit 1
fi

is_valid_task_type=false
for v in "${VALID_TASK_TYPES[@]}"; do
  [[ "$TASK_TYPE" == "$v" ]] && is_valid_task_type=true && break
done
if [[ "$is_valid_task_type" == false ]]; then
  echo "ERROR: 유효하지 않은 task_type '${TASK_TYPE}'. 유효한 값: ${VALID_TASK_TYPES[*]}" >&2
  exit 1
fi

if ! [[ "$AC_PASS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: ac_pass 는 0 이상의 정수여야 합니다." >&2
  exit 1
fi

if ! [[ "$AC_FAIL" =~ ^[0-9]+$ ]]; then
  echo "ERROR: ac_fail 는 0 이상의 정수여야 합니다." >&2
  exit 1
fi

# ─── 초기 스키마 ─────────────────────────────────────────────────────────────
INITIAL_SCHEMA='{
  "version": 1,
  "last_updated": "1970-01-01T00:00:00Z",
  "agents": {
    "agy": {
      "shell_scripting":      { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "documentation":        { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "code_implementation":  { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "testing":              { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "refactoring":          { "ac_pass": 0, "ac_fail": 0, "total": 0 }
    },
    "codex": {
      "shell_scripting":      { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "documentation":        { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "code_implementation":  { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "testing":              { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "refactoring":          { "ac_pass": 0, "ac_fail": 0, "total": 0 }
    }
  }
}'

# ─── 점수 파일 읽기 (없으면 초기 스키마 생성) ────────────────────────────────
if [[ ! -f "$SCORES_FILE" ]]; then
  mkdir -p "$(dirname "$SCORES_FILE")"
  echo "$INITIAL_SCHEMA" > "$SCORES_FILE"
  echo "[scores] 초기 점수 파일 생성: $SCORES_FILE"
fi

# ─── JSON 업데이트 ────────────────────────────────────────────────────────────
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

UPDATED_JSON="$(jq \
  --arg agent "$AGENT" \
  --arg task_type "$TASK_TYPE" \
  --argjson ac_pass "$AC_PASS" \
  --argjson ac_fail "$AC_FAIL" \
  --arg now "$NOW" \
  '
  .last_updated = $now |
  .agents[$agent][$task_type].ac_pass += $ac_pass |
  .agents[$agent][$task_type].ac_fail += $ac_fail |
  .agents[$agent][$task_type].total   = (.agents[$agent][$task_type].ac_pass + .agents[$agent][$task_type].ac_fail)
  ' "$SCORES_FILE")"

echo "$UPDATED_JSON" > "$SCORES_FILE"

# ─── 요약 출력 ────────────────────────────────────────────────────────────────
NEW_PASS="$(echo "$UPDATED_JSON" | jq ".agents[\"$AGENT\"][\"$TASK_TYPE\"].ac_pass")"
NEW_FAIL="$(echo "$UPDATED_JSON" | jq ".agents[\"$AGENT\"][\"$TASK_TYPE\"].ac_fail")"
NEW_TOTAL="$(echo "$UPDATED_JSON" | jq ".agents[\"$AGENT\"][\"$TASK_TYPE\"].total")"

if [[ "$NEW_TOTAL" -gt 0 ]]; then
  WIN_RATE="$(awk "BEGIN { printf \"%.1f\", ($NEW_PASS / $NEW_TOTAL) * 100 }")"
else
  WIN_RATE="0.0"
fi

echo "[scores] ${AGENT} / ${TASK_TYPE}: pass=${NEW_PASS} fail=${NEW_FAIL} total=${NEW_TOTAL} (승률 ${WIN_RATE}%)"