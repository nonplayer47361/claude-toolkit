#!/usr/bin/env bash
# dispatch.sh <cli> <task-id> <auth-mode> [project-dir] [mode]
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
#
# See references/cli-dispatch-guide.md for flag details and known gotchas.

set -euo pipefail

CLI="${1:?usage: dispatch.sh <cli> <task-id> <auth-mode> [project-dir] [mode]}"
TASK_ID="${2:?task-id required}"
AUTH_MODE="${3:?auth-mode required: full|limited}"
DIR="${4:-$(pwd)}"
MODE="${5:-execute}"

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
  MSG="_agent_reports/${TASK_ID}/TASK.md 읽고 시작해줘. 먼저 _agent_reports/${TASK_ID}/TODO.md에 하위작업 체크리스트를 작성하고, 다 끝나면 _agent_reports/${TASK_ID}/REPORT.md에 완료 보고서를 작성해줘. 소스 코드 파일은 TASK.md의 '## 허용 파일' 목록에 있는 것만 생성하거나 수정해줘."
elif [ "$MODE" = "feedback" ]; then
  MSG="_agent_reports/${TASK_ID}/TASK.md와 _agent_reports/${TASK_ID}/FEEDBACK.md를 읽고, FEEDBACK.md에 지적된 사항만 수정해줘. 다른 부분은 건드리지 마세요. 완료 후 REPORT.md에 '## 수정 내역 (회차 N)' 절을 추가해서 무엇을 어떻게 고쳤는지 적어줘."
else
  echo "ERROR: unknown mode '$MODE' (expected review|execute|feedback)" >&2
  exit 1
fi

case "$CLI" in
  codex)
    case "$AUTH_MODE" in
      full)
        if [ "$MODE" = "feedback" ]; then
          codex exec resume --last --dangerously-bypass-approvals-and-sandbox "$MSG" 2>&1 | tee "$LOG_FILE"
        else
          codex exec --dangerously-bypass-approvals-and-sandbox "$MSG" 2>&1 | tee "$LOG_FILE"
        fi
        ;;
      limited)
        if [ "$MODE" = "feedback" ]; then
          codex exec resume --last "$MSG" 2>&1 | tee "$LOG_FILE"
        else
          codex exec "$MSG" 2>&1 | tee "$LOG_FILE"
        fi
        ;;
      *)
        echo "ERROR: unknown auth-mode '$AUTH_MODE' (expected full|limited)" >&2
        exit 1
        ;;
    esac
    ;;
  agy)
    case "$AUTH_MODE" in
      full)
        if [ "$MODE" = "feedback" ]; then
          agy --continue --print "$MSG" --dangerously-skip-permissions --print-timeout 20m 2>&1 | tee "$LOG_FILE"
        else
          agy --print "$MSG" --dangerously-skip-permissions --print-timeout 20m 2>&1 | tee "$LOG_FILE"
        fi
        ;;
      limited)
        if [ "$MODE" = "feedback" ]; then
          agy --continue --print "$MSG" --print-timeout 20m 2>&1 | tee "$LOG_FILE"
        else
          agy --print "$MSG" --print-timeout 20m 2>&1 | tee "$LOG_FILE"
        fi
        ;;
      *)
        echo "ERROR: unknown auth-mode '$AUTH_MODE' (expected full|limited)" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "ERROR: unknown cli '$CLI'. Add a case for it here, after verifying" >&2
    echo "its exact non-interactive + auth-bypass flag names via --help." >&2
    exit 1
    ;;
esac
