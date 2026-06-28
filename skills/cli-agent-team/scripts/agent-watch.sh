#!/usr/bin/env bash
# agent-watch.sh <agent> <auth-mode> [project-dir] [skill-dir]
#
# agent-watch.ps1의 bash 동등본 — Linux / macOS / WSL 환경에서 사용한다.
# VS Code 터미널이나 tmux/screen 세션에 띄워 두고 쓸 수 있다.
#
# 사용법:
#   bash agent-watch.sh codex full /abs/path/to/project
#   bash agent-watch.sh agy limited /abs/path/to/project ~/.claude/skills/cli-agent-team
#
# 백그라운드 실행 (tmux):
#   tmux new-session -d -s "codex-watch" "bash ~/.claude/skills/cli-agent-team/scripts/agent-watch.sh codex full /path/to/project"
#
# 인수:
#   agent       codex | agy
#   auth-mode   full | limited | read-only
#   project-dir 프로젝트 루트 절대경로 (기본: 현재 디렉토리)
#   skill-dir   cli-agent-team 스킬 루트 (기본: 이 스크립트 두 단계 위)

set -euo pipefail

AGENT="${1:?필수: agent-watch.sh <agent> <auth-mode> [project-dir] [skill-dir]}"
AUTH_MODE="${2:?auth-mode 필요 (full | limited | read-only)}"
PROJECT_DIR="${3:-$(pwd)}"
SKILL_DIR="${4:-$(cd "$(dirname "$0")/.." && pwd)}"

REPORTS_DIR="$PROJECT_DIR/_agent_reports"
PENDING_FILE="$REPORTS_DIR/.pending_$AGENT"
DAEMON_MARKER="$REPORTS_DIR/.daemon_$AGENT"
DISPATCH_SCRIPT="$SKILL_DIR/scripts/dispatch.sh"

mkdir -p "$REPORTS_DIR"
echo "RUNNING" > "$DAEMON_MARKER"

# 비정상 종료에 IN_PROGRESS 남은 상태 복구
for f in "$REPORTS_DIR"/.status_*_"$AGENT"; do
    [ -f "$f" ] || continue
    if grep -q "IN_PROGRESS" "$f" 2>/dev/null; then
        printf "STALE\n" > "$f"
        echo "[$AGENT] [RECOVER] 이전에 IN_PROGRESS 상태: $(basename "$f") → STALE"
    fi
done

echo ""
echo "[$AGENT] 감시 시작"
echo "[$AGENT] 프로젝트: $PROJECT_DIR"
echo "[$AGENT] 권한: $AUTH_MODE"
echo "[$AGENT] 종료: Ctrl+C"
echo ""

cleanup() {
    rm -f "$DAEMON_MARKER"
    echo ""
    echo "[$AGENT] 종료"
    exit 0
}
trap cleanup EXIT INT TERM

while true; do
    if [ -f "$PENDING_FILE" ]; then
        TASK_ID=$(head -1 "$PENDING_FILE")
        MODE=$(sed -n '2p' "$PENDING_FILE")
        MODE="${MODE:-execute}"
        MODEL_TIER=$(sed -n '3p' "$PENDING_FILE")
        MODEL_TIER="${MODEL_TIER:-quality}"

        rm -f "$PENDING_FILE"

        STATUS_FILE="$REPORTS_DIR/.status_${TASK_ID}_${AGENT}"
        echo "IN_PROGRESS" > "$STATUS_FILE"

        echo "[$AGENT] 시작: $TASK_ID ($MODE / $MODEL_TIER)"
        echo "[$AGENT] 실행 중..."
        echo ""

        set +e
        bash "$DISPATCH_SCRIPT" "$AGENT" "$TASK_ID" "$AUTH_MODE" "$PROJECT_DIR" "$MODE" "$MODEL_TIER"
        EXIT_CODE=$?
        set -e

        if [ "$EXIT_CODE" -eq 0 ]; then
            echo "DONE" > "$STATUS_FILE"
            echo ""
            echo "[$AGENT] 완료: $TASK_ID"
        else
            # 2차 검사: REPORT.md에 완료 AC([x])가 있으면 작업 성공으로 간주
            REPORT_PATH="$PROJECT_DIR/_agent_reports/$TASK_ID/REPORT.md"
            WORK_DONE=false
            if [ -f "$REPORT_PATH" ] && grep -q -- '- \[x\]' "$REPORT_PATH" 2>/dev/null; then
                WORK_DONE=true
            fi

            if [ "$WORK_DONE" = true ]; then
                echo "DONE" > "$STATUS_FILE"
                echo ""
                echo "[$AGENT] 완료 (exit $EXIT_CODE 이나 → REPORT.md AC 확인): $TASK_ID"
                echo "[$AGENT]   ※ 도구 호출 중 exit $EXIT_CODE 발생은 무시"
            else
                echo "ERROR" > "$STATUS_FILE"
                echo ""
                echo "[$AGENT] 오류: $TASK_ID (exit $EXIT_CODE)"
            fi
        fi

        echo "[$AGENT] -- 다음 태스크 대기 중 --"
        echo ""
    fi

    sleep 3
done