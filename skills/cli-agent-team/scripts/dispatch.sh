#!/usr/bin/env bash
# dispatch.sh <cli> <task-id> <auth-mode> [project-dir] [mode] [model-tier]
#
# Dispatches a task to an external CLI coding agent.
# Run with run_in_background: true and wait for the harness notification.
#
#   <cli>         codex | agy | auto   (extend the case block for new CLIs)
#   <task-id>     matches _agent_reports/<task-id>/TASK.md
#   <auth-mode>   full | limited
#                 full    -> approval/sandbox bypass flags (only if user approved
#                            for THIS project — never assumed from other projects)
#                 limited -> the CLI's default approval mode (no bypass)
#   [project-dir] defaults to current directory
#   [mode]        review | execute  (default: execute)
#                 review  -> agent reads BRIEF.md + TASK.md, writes REVIEW.md only.
#                            No source code changes. Claude reports back to user
#                            before the execute dispatch.
#                 execute -> agent performs the actual work described in TASK.md,
#                            writes TODO.md (checklist) and REPORT.md (completion).
#   [model-tier]  fast | quality  (default: quality)
#                 fast    → gpt-5.4-mini / claude-haiku (문서·주석·단순 수정)
#                 quality → gpt-5.5 / claude-sonnet (코드 구현·인증·보안)
#
# See references/cli-dispatch-guide.md for flag details and known gotchas.

set -euo pipefail
DISPATCH_START_TS=$(date +%s 2>/dev/null || echo 0)

# EXIT trap: 에이전트 바이너리가 내부 검증 중 dispatch.sh를 호출해 non-zero 로 종료해도
# REPORT.md에 완료된 AC([x])가 있으면 작업 성공으로 처리한다.
_on_exit() {
  local ec=$?
  [ "$ec" -eq 0 ] && return
  local report="${TASK_DIR:-}"/REPORT.md
  local report_ts
  report_ts=$(stat -c %Y "$report" 2>/dev/null || stat -f %m "$report" 2>/dev/null || echo 0)
  if [ -f "$report" ] \
     && [ "${report_ts:-0}" -gt "${DISPATCH_START_TS:-0}" ] \
     && grep -q -- '- \[x\]' "$report" 2>/dev/null; then
    echo "[dispatch] ⚠ exit ${ec} — REPORT.md 완료 확인됨, 성공으로 처리" >&2
    exit 0
  fi
}
trap _on_exit EXIT

log_error() {
  local task_id="$1" agent="$2" message="$3"
  local reports_dir="${REPORTS_DIR:-_agent_reports}"
  local log_file="${reports_dir}/error.log"
  local ts lines

  mkdir -p "$reports_dir"
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ')"
  printf '[%s] [%s] [%s] %s\n' "$ts" "$task_id" "$agent" "$message" >> "$log_file"

  lines="$(wc -l < "$log_file" 2>/dev/null || echo 0)"
  lines="${lines//[[:space:]]/}"
  if [ "${lines:-0}" -gt 100 ]; then
    tail -50 "$log_file" > "${log_file}.tmp"
    mv "${log_file}.tmp" "$log_file"
  fi
}

# Append previous failure history to FEEDBACK.md before a feedback retry.
append_feedback_history() {
  local task_dir="$1"
  local agent="$2"
  local report_file="${task_dir}/REPORT.md"
  local feedback_file="${task_dir}/FEEDBACK.md"
  local history_marker="<!-- HISTORY -->"
  local round=1

  if [ -f "$feedback_file" ]; then
    round="$(grep -c '^### 회차 ' "$feedback_file" 2>/dev/null || true)"
    round="${round:-0}"
    round=$((round + 1))
  fi

  local prev_summary=""
  if [ -f "$report_file" ]; then
    prev_summary="$(head -20 "$report_file" | grep -v '^#' | tr '\n' ' ' | cut -c1-300 || true)"
  fi

  if [ -f "$feedback_file" ] && ! grep -Fq "$history_marker" "$feedback_file" 2>/dev/null; then
    printf '\n%s\n## 이전 시도 이력\n' "$history_marker" >> "$feedback_file"
  elif [ ! -f "$feedback_file" ]; then
    printf '%s\n## 이전 시도 이력\n' "$history_marker" > "$feedback_file"
  fi

  {
    printf '\n### 회차 %d (%s · %s)\n' "$round" "$agent" "$(date '+%Y-%m-%d %H:%M' 2>/dev/null || echo 'unknown')"
    printf '이전 제출 요약: %s\n' "${prev_summary:-"(REPORT.md 없음)"}"
    printf '결과: 검증 실패 후 재시도\n'
  } >> "$feedback_file"
}

_extract_tokens() {
  local log="$1" agent="$2"
  case "$agent" in
    codex)
      grep -A1 -iE "^tokens used$" "$log" 2>/dev/null \
        | grep -E "^[0-9,]+" | tr -d ',' | tail -1 || \
      grep -oE "[0-9,]+ tokens" "$log" 2>/dev/null \
        | grep -oE "^[0-9,]+" | tr -d ',' | tail -1 || echo 0
      ;;
    agy)
      # agy --print 출력에 토큰 패턴 미확인 — 수집 후 별도 패치
      echo "null"
      ;;
    *) echo 0 ;;
  esac
}

CLI="${1:?usage: dispatch.sh <cli> <task-id> <auth-mode> [project-dir] [mode] [model-tier]}"
TASK_ID="${2:?task-id required}"
AUTH_MODE="${3:?auth-mode required: full|limited}"
DIR="${4:-$(pwd)}"
MODE="${5:-execute}"
MODEL_TIER="${6:-quality}"
case "$MODEL_TIER" in
  fast|quality) ;;
  *) echo "ERROR: unknown model-tier '$MODEL_TIER' (expected fast|quality)" >&2; exit 1 ;;
esac
# CLI 타임아웃 — execute/feedback은 30분, review는 10분 (agy --print-timeout보다 여유 있게)
DISPATCH_TIMEOUT="${DISPATCH_TIMEOUT:-30m}"
[ "$MODE" = "review" ] && DISPATCH_TIMEOUT="${REVIEW_TIMEOUT:-10m}"

TASK_DIR="_agent_reports/${TASK_ID}"
TASK_FILE="${TASK_DIR}/TASK.md"

# 실제 작업 디렉토리로 이동 (상대 경로가 올바르게 동작하도록)
cd "$DIR"
PROJECT_DIR="$(pwd)"

REPORTS_DIR="_agent_reports"
CONF_FILE="${REPORTS_DIR}/.cli-agent-team.conf"
CODEX_ENABLED=true
AGY_ENABLED=true
CODEX_BIN="${CODEX_BIN:-}"
AGY_BIN="${AGY_BIN:-}"

_parse_conf() {
  local key="$1" file="$2"
  grep -E "^${key}=" "$file" 2>/dev/null | head -1 | sed "s/^${key}=//;s/^['\"]//;s/['\"]$//" || true
}

CODEX_MODEL_FAST_DEFAULT="gpt-5.4-mini"
CODEX_MODEL_QUALITY_DEFAULT="gpt-5.5"
AGY_MODEL_FAST_DEFAULT="claude-haiku-4-5-20251001"
AGY_MODEL_QUALITY_DEFAULT="claude-sonnet-4-6"

if [ -f "$CONF_FILE" ]; then
  _codex_bin=$(_parse_conf "CODEX_BIN" "$CONF_FILE")
  _agy_bin=$(_parse_conf "AGY_BIN" "$CONF_FILE")
  _pty_bridge=$(_parse_conf "PTY_BRIDGE_PATH" "$CONF_FILE")
  [ -n "$_codex_bin" ] && CODEX_BIN="$_codex_bin"
  [ -n "$_agy_bin"   ] && AGY_BIN="$_agy_bin"
  [ -n "$_pty_bridge" ] && PTY_BRIDGE_PATH="$_pty_bridge"
  _cm_fast=$(_parse_conf "CODEX_MODEL_FAST" "$CONF_FILE")
  _cm_quality=$(_parse_conf "CODEX_MODEL_QUALITY" "$CONF_FILE")
  _am_fast=$(_parse_conf "AGY_MODEL_FAST" "$CONF_FILE")
  _am_quality=$(_parse_conf "AGY_MODEL_QUALITY" "$CONF_FILE")
  [ -n "$_cm_fast" ]    && CODEX_MODEL_FAST_DEFAULT="$_cm_fast"
  [ -n "$_cm_quality" ] && CODEX_MODEL_QUALITY_DEFAULT="$_cm_quality"
  [ -n "$_am_fast" ]    && AGY_MODEL_FAST_DEFAULT="$_am_fast"
  [ -n "$_am_quality" ] && AGY_MODEL_QUALITY_DEFAULT="$_am_quality"
fi

if [ -z "${CODEX_BIN:-}" ] && command -v codex >/dev/null 2>&1; then
  CODEX_BIN="$(command -v codex)"
fi
if [ -z "${AGY_BIN:-}" ] && command -v agy >/dev/null 2>&1; then
  AGY_BIN="$(command -v agy)"
fi

if [ "$CLI" = "auto" ]; then
  # 1단계: 기본 우선순위 결정 (기존 로직)
  if [ "${AGY_ENABLED:-true}" = "true" ] && [ -n "${AGY_BIN:-}" ]; then
    _AUTO_DEFAULT="agy"
  elif [ "${CODEX_ENABLED:-true}" = "true" ] && [ -n "${CODEX_BIN:-}" ]; then
    _AUTO_DEFAULT="codex"
  else
    _AUTO_DEFAULT="claude"
  fi

  # 2단계: task_type 추출
  _TASK_TYPE_RAW=$(grep -m1 '^task_type:' "$TASK_FILE" 2>/dev/null \
    | sed 's/^task_type:[[:space:]]*//' | tr -d '[:space:]' || true)
  _TASK_TYPE="${_TASK_TYPE_RAW%%.*}"

  # 3단계: .agent_scores.json 기반 보정 (jq 필요, 데이터 충분 시에만)
  _AUTO_CLI="$_AUTO_DEFAULT"
  _SCORES_FILE="${REPORTS_DIR}/.agent_scores.json"
  if [ -n "$_TASK_TYPE" ] && command -v jq >/dev/null 2>&1 && [ -f "$_SCORES_FILE" ]; then
    _AGY_TOTAL=$(jq -r --arg t "$_TASK_TYPE" \
      '.agents.agy[$t].total // 0' "$_SCORES_FILE" 2>/dev/null || echo 0)
    _CODEX_TOTAL=$(jq -r --arg t "$_TASK_TYPE" \
      '.agents.codex[$t].total // 0' "$_SCORES_FILE" 2>/dev/null || echo 0)

    if [ "${_AGY_TOTAL:-0}" -ge 5 ] && [ "${_CODEX_TOTAL:-0}" -ge 5 ]; then
      _AGY_PASS=$(jq -r --arg t "$_TASK_TYPE" \
        '.agents.agy[$t].ac_pass // 0' "$_SCORES_FILE" 2>/dev/null || echo 0)
      _CODEX_PASS=$(jq -r --arg t "$_TASK_TYPE" \
        '.agents.codex[$t].ac_pass // 0' "$_SCORES_FILE" 2>/dev/null || echo 0)
      # 승률 = 100 * pass / total (정수 연산, 소수점 버림)
      _AGY_RATE=$(( (_AGY_PASS * 100) / _AGY_TOTAL ))
      _CODEX_RATE=$(( (_CODEX_PASS * 100) / _CODEX_TOTAL ))
      _DIFF=$(( _AGY_RATE - _CODEX_RATE ))
      _ABS_DIFF=$(( _DIFF < 0 ? -_DIFF : _DIFF ))

      if [ "$_ABS_DIFF" -ge 15 ]; then
        if [ "$_AGY_RATE" -gt "$_CODEX_RATE" ]; then
          _AUTO_CLI="agy"
          echo "[dispatch] auto -> agy 선택 (적응형: ${_TASK_TYPE} agy ${_AGY_RATE}% > codex ${_CODEX_RATE}%)"
        else
          _AUTO_CLI="codex"
          echo "[dispatch] auto -> codex 선택 (적응형: ${_TASK_TYPE} codex ${_CODEX_RATE}% > agy ${_AGY_RATE}%)"
        fi
      else
        echo "[dispatch] auto -> ${_AUTO_DEFAULT} 선택 (적응형: 승률 차이 ${_ABS_DIFF}%p 미미, 기본값)"
      fi
    else
      echo "[dispatch] auto -> ${_AUTO_DEFAULT} 선택 (적응형: 데이터 부족 agy=${_AGY_TOTAL:-0} codex=${_CODEX_TOTAL:-0}, 기본값)"
    fi
  else
    echo "[dispatch] auto -> ${_AUTO_DEFAULT} 선택 (기본값)"
  fi

  CLI="$_AUTO_CLI"
fi

# 최초 선택된 에이전트 보존 — fallback 시 CLI가 덮어써져도 metrics에 원본 에이전트 기록
_ORIGINAL_CLI="$CLI"

case "$CLI" in
  codex)
    if [ "${CODEX_ENABLED:-true}" = "false" ]; then
      log_error "$TASK_ID" "$CLI" "agent disabled (conf: CODEX_ENABLED=false)"
      echo "ERROR: codex는 비활성 상태입니다. (setup.sh --enable-codex 로 활성화)" >&2
      exit 1
    fi
    ;;
  agy)
    if [ "${AGY_ENABLED:-true}" = "false" ]; then
      log_error "$TASK_ID" "$CLI" "agent disabled (conf: AGY_ENABLED=false)"
      echo "ERROR: agy는 비활성 상태입니다. (setup.sh --enable-agy 로 활성화)" >&2
      exit 1
    fi
    ;;
esac

LOG_FILE="${TASK_DIR}/_${CLI}_stdout.log"

run_cli_logged() {
  local tee_mode="$1"
  shift
  local exit_code

  set +e
  if [ "$tee_mode" = "append" ]; then
    "$@" 2>&1 | tee -a "$LOG_FILE"
    exit_code=${PIPESTATUS[0]}
  else
    "$@" 2>&1 | tee "$LOG_FILE"
    exit_code=${PIPESTATUS[0]}
  fi
  set -e

  if [ "$exit_code" -ne 0 ]; then
    log_error "$TASK_ID" "$CLI" "exit $exit_code"
  fi
  return "$exit_code"
}

log_attempt_header() {
  mkdir -p "$(dirname "$LOG_FILE")"
  local _n=1
  if [ -f "$LOG_FILE" ]; then
    local _c
    _c=$(grep -c "^--- 시도 " "$LOG_FILE" 2>/dev/null) || _c=0
    _n=$(( _c + 1 ))
  fi
  printf "\n--- 시도 %d (%s) %s ---\n" "$_n" "$MODE" "$(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
}

if [ ! -f "$TASK_FILE" ]; then
  log_error "$TASK_ID" "$CLI" "TASK.md not found: $TASK_FILE"
  echo "ERROR: $TASK_FILE not found (cwd=$(pwd)). Write the TASK.md before dispatching." >&2
  exit 1
fi

# dispatch 시작 시점의 변경 파일 목록을 스냅샷으로 저장 → verify.sh가 작업 이전 파일을 제외할 수 있도록
mkdir -p "$TASK_DIR"
{
  git diff --name-only HEAD 2>/dev/null || true
  git diff --cached --name-only 2>/dev/null || true
  git ls-files --others --exclude-standard 2>/dev/null || true
} | sort -u > "$TASK_DIR/.pre_dispatch_files"

if [ "$MODE" = "review" ]; then
  MSG="BRIEF.md와 _agent_reports/${TASK_ID}/TASK.md를 읽고, 실행 전 검토 의견을 _agent_reports/${TASK_ID}/REVIEW.md에 작성해줘. 코드·파일은 건드리지 마세요. REVIEW.md 형식은 task-templates.md의 REVIEW.md 섹션을 참고해."
elif [ "$MODE" = "execute" ]; then
  _agents_hint=""
  if [ -f "$PROJECT_DIR/AGENTS.md" ]; then
    _agents_hint="시작 전 AGENTS.md를 읽어 역할과 검증 규칙을 확인해줘.

"
  fi

  _notes_hint=""
  _NOTES_FILE="$PROJECT_DIR/_agent_reports/SHARED_TASK_NOTES.md"
  if [ -f "$_NOTES_FILE" ] && [ -s "$_NOTES_FILE" ]; then
    _notes_hint="
【컨텍스트 브리지】 _agent_reports/SHARED_TASK_NOTES.md를 읽어 이전 태스크의 핵심 결정사항을 파악해줘. 이 태스크 완료 후 핵심 결정(변경 파일·이유·다음 주의사항)을 NOTES 하단에 추가해줘.
"
  fi

  _rtk_hint=""
  if command -v rtk >/dev/null 2>&1; then
    _rtk_hint="

【토큰 절약】 파일 검색은 rtk grep, 코드 탐색은 codebase-memory-mcp search_code를 우선 사용해줘."
  fi

  MSG="${_agents_hint}${_notes_hint}_agent_reports/${TASK_ID}/TASK.md 읽고 시작해줘. 먼저 _agent_reports/${TASK_ID}/TODO.md에 하위작업 체크리스트를 작성하고, 다 끝나면 _agent_reports/${TASK_ID}/REPORT.md에 완료 보고서를 작성해줘. 소스 코드 파일은 TASK.md의 '## 허용 파일' 목록에 있는 것만 생성하거나 수정해줘.

REPORT.md는 반드시 다음 섹션을 포함해야 해:
## AC 체크리스트
- [x] 또는 - [ ] 형식으로 TASK.md의 완료 기준을 하나씩 체크

이 섹션이 없으면 자동 검증이 실패하므로 빠뜨리지 말 것.

【검증 규칙】 스크립트 문법 확인은 반드시 'bash -n <파일>' 형식만 사용할 것. dispatch.sh를 직접 실행하면 exit 코드가 이 세션 전체에 전파되어 작업이 실패로 오판된다.

${_rtk_hint}"
elif [ "$MODE" = "feedback" ]; then
  MSG="_agent_reports/${TASK_ID}/TASK.md와 _agent_reports/${TASK_ID}/FEEDBACK.md를 읽고, FEEDBACK.md에 지적된 사항만 수정해줘. 다른 부분은 건드리지 마세요. 완료 후 REPORT.md에 '## 수정 내역 (회차 N)' 절을 추가해서 무엇을 어떻게 고쳤는지 적어줘."
  MSG="${MSG} FEEDBACK.md 하단의 '## 이전 시도 이력' 섹션을 반드시 읽어서 직전 시도에서 무엇이 잘못됐는지 파악하고 수정해라. 이전 시도와 무엇이 달라졌는지도 REPORT.md에 적어줘."
  append_feedback_history "$TASK_DIR" "$CLI"
else
  echo "ERROR: unknown mode '$MODE' (expected review|execute|feedback)" >&2
  exit 1
fi

run_with_timeout() {
  # timeout이 없는 환경(일부 Git Bash) 대비 — 있으면 감싸고 없으면 그냥 실행
  if command -v timeout >/dev/null 2>&1; then
    timeout "$DISPATCH_TIMEOUT" "$@"
    local ec=$?
    [ $ec -eq 124 ] && echo "ERROR: dispatch timed out after $DISPATCH_TIMEOUT" >&2
    return $ec
  else
    "$@"
  fi
}

case "$CLI" in
  codex)
    case "$MODEL_TIER" in
      fast)    CODEX_MODEL="$CODEX_MODEL_FAST_DEFAULT" ;;
      quality) CODEX_MODEL="$CODEX_MODEL_QUALITY_DEFAULT" ;;
    esac
    log_attempt_header
    case "$AUTH_MODE" in
      full)
        if [ "$MODE" = "feedback" ]; then
          run_cli_logged append run_with_timeout codex exec -m "$CODEX_MODEL" resume --last --dangerously-bypass-approvals-and-sandbox "$MSG"
        else
          run_cli_logged append run_with_timeout codex exec -m "$CODEX_MODEL" --dangerously-bypass-approvals-and-sandbox "$MSG"
        fi
        ;;
      limited)
        if [ "$MODE" = "feedback" ]; then
          run_cli_logged append run_with_timeout codex exec -m "$CODEX_MODEL" resume --last "$MSG"
        else
          run_cli_logged append run_with_timeout codex exec -m "$CODEX_MODEL" "$MSG"
        fi
        ;;
      *)
        echo "ERROR: unknown auth-mode '$AUTH_MODE' (expected full|limited)" >&2
        exit 1
        ;;
    esac
    ;;
  agy)
    # agy는 TTY 없이 실행 시 출력이 사라짐 — ConPTY 래퍼(pty-bridge)로 우회
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PTY_BRIDGE="${PTY_BRIDGE_PATH:-${SCRIPT_DIR}/../../../mcp-servers/pty-bridge/run.js}"
    if [ ! -f "$PTY_BRIDGE" ]; then
      echo "ERROR: pty-bridge not found." >&2
      echo "  search path: $PTY_BRIDGE" >&2
      echo "  resolution options:" >&2
      echo "    1) Set env var: export PTY_BRIDGE_PATH=/absolute/path/to/mcp-servers/pty-bridge/run.js" >&2
      echo "    2) Add to conf: echo 'PTY_BRIDGE_PATH=...' >> _agent_reports/.cli-agent-team.conf" >&2
      echo "    3) Install deps: cd <repo>/mcp-servers/pty-bridge && npm install" >&2
      exit 1
    fi
    AGY_TIMEOUT_MS=1200000
    [ "$MODE" = "review" ] && AGY_TIMEOUT_MS=600000
    case "$MODEL_TIER" in
      fast)    AGY_MODEL="$AGY_MODEL_FAST_DEFAULT" ;;
      quality) AGY_MODEL="$AGY_MODEL_QUALITY_DEFAULT" ;;
    esac
    # agy 플래그 조합
    AGY_FLAGS=(--model "$AGY_MODEL" --print-timeout 20m)
    [ "$MODE" = "feedback" ] && AGY_FLAGS=(--continue "${AGY_FLAGS[@]}")
    [ "$AUTH_MODE" = "full" ] && AGY_FLAGS=("${AGY_FLAGS[@]}" --dangerously-skip-permissions)
    log_attempt_header
    run_cli_logged append node "$PTY_BRIDGE" agy "$LOG_FILE" "$AGY_TIMEOUT_MS" -- --print "$MSG" "${AGY_FLAGS[@]}"
    ;;
  claude)
    log_error "$TASK_ID" "$CLI" "unsupported agent: $CLI"
    echo "ERROR: claude-direct 모드는 아직 구현 중입니다." >&2
    echo "       codex 또는 agy 를 설치하거나 setup.sh --enable-codex 를 실행하세요." >&2
    exit 2
    ;;
  *)
    log_error "$TASK_ID" "$CLI" "unknown agent: $CLI"
    echo "ERROR: unknown cli '$CLI'. Add a case for it here, after verifying" >&2
    echo "its exact non-interactive + auth-bypass flag names via --help." >&2
    exit 1
    ;;
esac

# ── agy 빈 출력 → codex fallback (자동 재시도) ────────────────────────────
if [ "$CLI" = "agy" ] && [ "$MODE" = "execute" ]; then
  _REPORT="${TASK_DIR}/REPORT.md"
  _REPORT_TS=$(stat -c %Y "$_REPORT" 2>/dev/null || stat -f %m "$_REPORT" 2>/dev/null || echo 0)
  if [ ! -f "$_REPORT" ] || [ "${_REPORT_TS:-0}" -le "${DISPATCH_START_TS:-0}" ]; then
    if [ "${CODEX_ENABLED:-true}" = "true" ] && command -v "${CODEX_BIN:-codex}" >/dev/null 2>&1; then
      echo "[dispatch] ⚠ agy 빈 출력 감지 (REPORT.md 없음/미갱신) → codex fallback 실행" >&2
      log_error "$TASK_ID" "agy" "empty output — codex fallback"
      case "$MODEL_TIER" in
        fast)    CODEX_MODEL="$CODEX_MODEL_FAST_DEFAULT" ;;
        quality) CODEX_MODEL="$CODEX_MODEL_QUALITY_DEFAULT" ;;
      esac
      CLI="codex"
      LOG_FILE="${TASK_DIR}/_codex_fallback.log"
      log_attempt_header
      if [ "$AUTH_MODE" = "full" ]; then
        run_cli_logged append run_with_timeout codex exec -m "$CODEX_MODEL" \
          --dangerously-bypass-approvals-and-sandbox "$MSG"
      else
        run_cli_logged append run_with_timeout codex exec -m "$CODEX_MODEL" "$MSG"
      fi
    else
      echo "[dispatch] ⚠ agy 빈 출력 감지, codex 미설치/비활성 — fallback 불가" >&2
      log_error "$TASK_ID" "agy" "empty output, codex fallback 불가"
    fi
  fi
fi

# ── .task_meta.json 생성 (토큰·시간 추적) ────────────────────────────────────
if command -v jq >/dev/null 2>&1; then
  _ELAPSED=$(( $(date +%s 2>/dev/null || echo 0) - ${DISPATCH_START_TS:-0} ))
  _TOKENS=$(_extract_tokens "${LOG_FILE:-/dev/null}" "${CLI:-unknown}")
  _META_FILE="${TASK_DIR}/.task_meta.json"
  _META_TASK_TYPE=$(grep -m1 '^task_type:' "${TASK_FILE:-/dev/null}" 2>/dev/null \
      | sed 's/^task_type:[[:space:]]*//' | tr -d '[:space:]' || true)
  _META_TASK_TYPE="${_META_TASK_TYPE%%.*}"
  _FALLBACK_BOOL="false"
  if [ "${CLI:-}" = "codex" ] && [ -f "${TASK_DIR}/_codex_fallback.log" ]; then
    _FALLBACK_BOOL="true"
  fi
  jq -n \
    --arg  task_id   "${TASK_ID:-unknown}" \
    --arg  agent     "${_ORIGINAL_CLI:-${CLI:-unknown}}" \
    --arg  task_type "${_META_TASK_TYPE:-unknown}" \
    --arg  date      "$(date +%Y-%m-%d)" \
    --argjson elapsed  "${_ELAPSED:-0}" \
    --argjson start_ts "${DISPATCH_START_TS:-0}" \
    --argjson fallback "$_FALLBACK_BOOL" \
    --argjson tokens   "${_TOKENS:-0}" \
    '{task_id:$task_id, agent:$agent, task_type:$task_type, date:$date,
      started_ts:$start_ts, elapsed_sec:$elapsed, tokens_used:$tokens,
      loc_added:0, loc_deleted:0, ac_pass:0, ac_fail:0, fallback_used:$fallback
     }' > "$_META_FILE" 2>/dev/null || true
fi
