#!/usr/bin/env bash
# dispatch.sh <cli> <task-id> <auth-mode> [project-dir] [mode] [model-tier]
#
# Dispatches a task to an external CLI coding agent.
# Run with run_in_background: true and wait for the harness notification.
#
#   <cli>         codex | agy   (extend the case block for new CLIs)
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
LOG_FILE="${TASK_DIR}/_${CLI}_stdout.log"

# 실제 작업 디렉토리로 이동 (상대 경로가 올바르게 동작하도록)
cd "$DIR"

if [ ! -f "$TASK_FILE" ]; then
  echo "ERROR: $TASK_FILE not found (cwd=$(pwd)). Write the TASK.md before dispatching." >&2
  exit 1
fi

if [ "$MODE" = "review" ]; then
  MSG="BRIEF.md와 _agent_reports/${TASK_ID}/TASK.md를 읽고, 실행 전 검토 의견을 _agent_reports/${TASK_ID}/REVIEW.md에 작성해줘. 코드·파일은 건드리지 마세요. REVIEW.md 형식은 task-templates.md의 REVIEW.md 섹션을 참고해."
elif [ "$MODE" = "execute" ]; then
  MSG="_agent_reports/${TASK_ID}/TASK.md 읽고 시작해줘. 먼저 _agent_reports/${TASK_ID}/TODO.md에 하위작업 체크리스트를 작성하고, 다 끝나면 _agent_reports/${TASK_ID}/REPORT.md에 완료 보고서를 작성해줘. 소스 코드 파일은 TASK.md의 '## 허용 파일' 목록에 있는 것만 생성하거나 수정해줘.

REPORT.md는 반드시 다음 섹션을 포함해야 해:
## AC 체크리스트
- [x] 또는 - [ ] 형식으로 TASK.md의 완료 기준을 하나씩 체크

이 섹션이 없으면 자동 검증이 실패하므로 빠뜨리지 말 것."
elif [ "$MODE" = "feedback" ]; then
  MSG="_agent_reports/${TASK_ID}/TASK.md와 _agent_reports/${TASK_ID}/FEEDBACK.md를 읽고, FEEDBACK.md에 지적된 사항만 수정해줘. 다른 부분은 건드리지 마세요. 완료 후 REPORT.md에 '## 수정 내역 (회차 N)' 절을 추가해서 무엇을 어떻게 고쳤는지 적어줘."
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
      fast)    CODEX_MODEL="gpt-5.4-mini" ;;
      quality) CODEX_MODEL="gpt-5.5" ;;
    esac
    case "$AUTH_MODE" in
      full)
        if [ "$MODE" = "feedback" ]; then
          run_with_timeout codex exec -m "$CODEX_MODEL" resume --last --dangerously-bypass-approvals-and-sandbox "$MSG" 2>&1 | tee "$LOG_FILE"
        else
          run_with_timeout codex exec -m "$CODEX_MODEL" --dangerously-bypass-approvals-and-sandbox "$MSG" 2>&1 | tee "$LOG_FILE"
        fi
        ;;
      limited)
        if [ "$MODE" = "feedback" ]; then
          run_with_timeout codex exec -m "$CODEX_MODEL" resume --last "$MSG" 2>&1 | tee "$LOG_FILE"
        else
          run_with_timeout codex exec -m "$CODEX_MODEL" "$MSG" 2>&1 | tee "$LOG_FILE"
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
    PTY_BRIDGE="${SCRIPT_DIR}/../../../mcp-servers/pty-bridge/run.js"
    if [ ! -f "$PTY_BRIDGE" ]; then
      echo "ERROR: pty-bridge not found at $PTY_BRIDGE" >&2
      echo "  Run: cd mcp-servers/pty-bridge && npm install" >&2
      exit 1
    fi
    AGY_TIMEOUT_MS=1200000
    [ "$MODE" = "review" ] && AGY_TIMEOUT_MS=600000
    case "$MODEL_TIER" in
      fast)    AGY_MODEL="claude-haiku-4-5-20251001" ;;
      quality) AGY_MODEL="claude-sonnet-4-6" ;;
    esac
    # agy 플래그 조합
    AGY_FLAGS=(--model "$AGY_MODEL" --print-timeout 20m)
    [ "$MODE" = "feedback" ] && AGY_FLAGS=(--continue "${AGY_FLAGS[@]}")
    [ "$AUTH_MODE" = "full" ] && AGY_FLAGS=("${AGY_FLAGS[@]}" --dangerously-skip-permissions)
    node "$PTY_BRIDGE" agy "$LOG_FILE" "$AGY_TIMEOUT_MS" -- --print "$MSG" "${AGY_FLAGS[@]}" 2>&1 | tee -a "$LOG_FILE"
    ;;
  *)
    echo "ERROR: unknown cli '$CLI'. Add a case for it here, after verifying" >&2
    echo "its exact non-interactive + auth-bypass flag names via --help." >&2
    exit 1
    ;;
esac
