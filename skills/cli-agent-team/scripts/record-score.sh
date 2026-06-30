#!/usr/bin/env bash
# record-score.sh — 에이전트 태스크 성능 점수 기록 스크립트
# Usage: bash record-score.sh <agent> <task_type> <ac_pass> <ac_fail> [project-dir] [task-dir]
# Env  : PROJECT_ROOT=<path> — 프로젝트 루트 경로 (최우선). 미설정 시 5번째 인자 사용,
#        그마저 없으면 스크립트 위치 기준 ../../.. 을 fallback으로 사용.
#        FAIL_REASON=<code>  — 실패 원인 코드 (verify.sh가 설정)
#        유효 코드: SCOPE_VIOLATION | AC_INCOMPLETE | SEC_PATTERN | FILE_MISSING | VERIFY_CMD_FAIL
#
# 유효한 agent 값: agy, codex
# 유효한 task_type 값 (14종):
#   shell_scripting, documentation, code_implementation, testing, refactoring,
#   ui_component, styling, api_backend, database, security,
#   devops, config, data_processing, analysis

set -euo pipefail

# ─── 상수 ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT 우선순위: env var > 5번째 인자(project-dir) > ../../.. fallback
# (fallback은 아래 인수 파싱 후 결정되므로 여기서는 sentinel 설정)
_SCRIPT_FALLBACK_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

VALID_AGENTS=("agy" "codex")
VALID_TASK_TYPES=(
  "shell_scripting" "documentation" "code_implementation" "testing" "refactoring"
  "ui_component" "styling" "api_backend" "database" "security"
  "devops" "config" "data_processing" "analysis"
)

# ─── 의존성 확인 ─────────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq 가 설치되지 않았습니다. brew install jq / apt install jq 로 설치하세요." >&2
  exit 1
fi

# ─── 인수 파싱 ───────────────────────────────────────────────────────────────
if [[ $# -lt 4 ]] || [[ $# -gt 6 ]]; then
  echo "Usage: bash record-score.sh <agent> <task_type> <ac_pass> <ac_fail> [project-dir] [task-dir]" >&2
  echo "  agent       : agy | codex" >&2
  echo "  task_type   : shell_scripting | documentation | code_implementation | testing | refactoring" >&2
  echo "              | ui_component | styling | api_backend | database | security" >&2
  echo "              | devops | config | data_processing | analysis" >&2
  echo "  ac_pass     : 통과한 AC 수 (정수)" >&2
  echo "  ac_fail     : 실패한 AC 수 (정수)" >&2
  echo "  project-dir : (선택) 점수 파일 위치 기준 프로젝트 경로" >&2
  echo "  task-dir    : (선택) _agent_reports/<task-id>/ 경로 — .task_meta.json 읽기 및 .agent_metrics.json 누적" >&2
  exit 1
fi

AGENT="$1"
TASK_TYPE="$2"
AC_PASS="$3"
AC_FAIL="$4"
# PROJECT_ROOT 결정: env var → 5번째 인자 → ../../.. fallback
if [[ -n "${PROJECT_ROOT:-}" ]]; then
  : # env var 그대로 사용
elif [[ -n "${5:-}" ]]; then
  PROJECT_ROOT="${5}"
else
  PROJECT_ROOT="$_SCRIPT_FALLBACK_ROOT"
fi
TASK_DIR_ARG="${6:-}"  # _agent_reports/<task-id>/ 경로 (선택)
SCORES_FILE="$PROJECT_ROOT/_agent_reports/.agent_scores.json"
METRICS_FILE="$PROJECT_ROOT/_agent_reports/.agent_metrics.json"
LOCK_FILE="${SCORES_FILE}.lock"
LOCK_DIR="${SCORES_FILE}.lockdir"
_LOCK_MODE=""

release_scores_lock() {
  case "${_LOCK_MODE:-}" in
    flock)
      exec 9>&-
      ;;
    mkdir)
      rmdir "$LOCK_DIR" 2>/dev/null || true
      ;;
  esac
  _LOCK_MODE=""
}

acquire_scores_lock() {
  mkdir -p "$(dirname "$SCORES_FILE")"

  if command -v flock >/dev/null 2>&1; then
    _LOCK_MODE="flock"
    exec 9>"$LOCK_FILE"
    if ! flock -w 10 9; then
      exec 9>&-
      _LOCK_MODE=""
      echo "ERROR: 점수 파일 락 획득 실패 (10초 타임아웃): $LOCK_FILE" >&2
      exit 1
    fi
  else
    _LOCK_MODE="mkdir"
    local lock_acquired=false
    for ((_i = 1; _i <= 20; _i++)); do
      if mkdir "$LOCK_DIR" 2>/dev/null; then
        lock_acquired=true
        break
      fi
      sleep 0.5
    done
    if [[ "$lock_acquired" != true ]]; then
      _LOCK_MODE=""
      echo "ERROR: 점수 파일 락 획득 실패 (10초 타임아웃): $LOCK_DIR" >&2
      exit 1
    fi
  fi

  trap 'release_scores_lock' EXIT
  trap 'release_scores_lock; exit 130' INT
  trap 'release_scores_lock; exit 143' TERM
}

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
  "version": 2,
  "last_updated": "1970-01-01T00:00:00Z",
  "agents": {
    "agy": {
      "shell_scripting":     { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "documentation":       { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "code_implementation": { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "testing":             { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "refactoring":         { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "ui_component":        { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "styling":             { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "api_backend":         { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "database":            { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "security":            { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "devops":              { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "config":              { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "data_processing":     { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "analysis":            { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "fail_reasons": { "SCOPE_VIOLATION": 0, "AC_INCOMPLETE": 0, "SEC_PATTERN": 0, "FILE_MISSING": 0, "VERIFY_CMD_FAIL": 0 }
    },
    "codex": {
      "shell_scripting":     { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "documentation":       { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "code_implementation": { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "testing":             { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "refactoring":         { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "ui_component":        { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "styling":             { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "api_backend":         { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "database":            { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "security":            { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "devops":              { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "config":              { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "data_processing":     { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "analysis":            { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "fail_reasons": { "SCOPE_VIOLATION": 0, "AC_INCOMPLETE": 0, "SEC_PATTERN": 0, "FILE_MISSING": 0, "VERIFY_CMD_FAIL": 0 }
    }
  }
}'

# ─── 점수 파일 읽기 (없으면 초기 스키마 생성) ────────────────────────────────
acquire_scores_lock

if [[ ! -f "$SCORES_FILE" ]]; then
  mkdir -p "$(dirname "$SCORES_FILE")"
  echo "$INITIAL_SCHEMA" > "$SCORES_FILE"
  echo "[scores] 초기 점수 파일 생성: $SCORES_FILE"
fi

# ─── JSON 업데이트 ────────────────────────────────────────────────────────────
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
FAIL_REASON="${FAIL_REASON:-}"

UPDATED_JSON="$(jq \
  --arg agent "$AGENT" \
  --arg task_type "$TASK_TYPE" \
  --argjson ac_pass "$AC_PASS" \
  --argjson ac_fail "$AC_FAIL" \
  --arg now "$NOW" \
  --arg fail_reason "$FAIL_REASON" \
  '
  .last_updated = $now |
  .agents[$agent][$task_type] //= {"ac_pass":0,"ac_fail":0,"total":0} |
  .agents[$agent][$task_type].ac_pass += $ac_pass |
  .agents[$agent][$task_type].ac_fail += $ac_fail |
  .agents[$agent][$task_type].total   = (.agents[$agent][$task_type].ac_pass + .agents[$agent][$task_type].ac_fail) |
  if ($fail_reason != "") then
    .agents[$agent].fail_reasons //= {} |
    .agents[$agent].fail_reasons[$fail_reason] = ((.agents[$agent].fail_reasons[$fail_reason] // 0) + 1)
  else . end
  ' "$SCORES_FILE")"

echo "$UPDATED_JSON" > "$SCORES_FILE"
release_scores_lock
trap - EXIT INT TERM

# ─── 요약 출력 ────────────────────────────────────────────────────────────────
NEW_PASS="$(echo "$UPDATED_JSON" | jq ".agents[\"$AGENT\"][\"$TASK_TYPE\"].ac_pass")"
NEW_FAIL="$(echo "$UPDATED_JSON" | jq ".agents[\"$AGENT\"][\"$TASK_TYPE\"].ac_fail")"
NEW_TOTAL="$(echo "$UPDATED_JSON" | jq ".agents[\"$AGENT\"][\"$TASK_TYPE\"].total")"

if [[ "$NEW_TOTAL" -gt 0 ]]; then
  WIN_RATE="$(awk "BEGIN { printf \"%.1f\", ($NEW_PASS / $NEW_TOTAL) * 100 }")"
else
  WIN_RATE="0.0"
fi

TOTAL_FAILS="$(echo "$UPDATED_JSON" | jq --arg agent "$AGENT" '[.agents[$agent].fail_reasons // {} | to_entries[].value] | add // 0')"
echo "[scores] ${AGENT} / ${TASK_TYPE}: pass=${NEW_PASS} fail=${NEW_FAIL} total=${NEW_TOTAL} (승률 ${WIN_RATE}%) | 누적 실패유형 합계: ${TOTAL_FAILS}"

# ── .agent_metrics.json 누적 (task-dir 지정 시, .task_meta.json 읽기) ─────────
if [[ -n "${TASK_DIR_ARG:-}" ]]; then
  _META_PATH="${TASK_DIR_ARG}/.task_meta.json"
  if [[ -f "$_META_PATH" ]]; then
    _META_JSON="$(cat "$_META_PATH")"
    if [[ ! -f "$METRICS_FILE" ]]; then
      echo "[]" > "$METRICS_FILE"
    fi
    jq --argjson record "$_META_JSON" '. + [$record]' "$METRICS_FILE" \
      > "${METRICS_FILE}.tmp" 2>/dev/null && \
      mv "${METRICS_FILE}.tmp" "$METRICS_FILE" || true
    _MID="$(echo "$_META_JSON" | jq -r '.task_id // "unknown"' 2>/dev/null || echo "unknown")"
    echo "[metrics] .agent_metrics.json 레코드 추가: ${_MID}"
  fi
fi
