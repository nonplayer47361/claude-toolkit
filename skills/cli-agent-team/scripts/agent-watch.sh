#!/usr/bin/env bash
# agent-watch.sh <agent> <auth-mode> [project-dir] [skill-dir]
#
# agent-watch.ps1의 bash 버전 — Linux / macOS / WSL 환경에서 실행한다.
# VS Code 없이도 tmux/screen 세션에서 백그라운드로 띄울 수 있다.
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
#   project-dir 프로젝트 루트 절대 경로 (기본: 현재 디렉토리)
#   skill-dir   cli-agent-team 스킬 루트 (기본: 이 스크립트 두 단계 위)

set -euo pipefail

AGENT="${1:?사용법: agent-watch.sh <agent> <auth-mode> [project-dir] [skill-dir]}"
AUTH_MODE="${2:?auth-mode 필요 (full | limited | read-only)}"
PROJECT_DIR="${3:-$(pwd)}"
SKILL_DIR="${4:-$(cd "$(dirname "$0")/.." && pwd)}"

REPORTS_DIR="$PROJECT_DIR/_agent_reports"
PENDING_FILE="$REPORTS_DIR/.pending_$AGENT"
DAEMON_MARKER="$REPORTS_DIR/.daemon_$AGENT"
DISPATCH_SCRIPT="$SKILL_DIR/scripts/dispatch.sh"

mkdir -p "$REPORTS_DIR"
echo "RUNNING" > "$DAEMON_MARKER"

# 이전 세션에서 중단된 IN_PROGRESS 상태 파일 정리
for f in "$REPORTS_DIR"/.status_*_"$AGENT"; do
    [ -f "$f" ] || continue
    if grep -q "IN_PROGRESS" "$f" 2>/dev/null; then
        printf "STALE\n" > "$f"
        echo "[$AGENT] [RECOVER] 잔류 IN_PROGRESS 정리: $(basename "$f") → STALE"
    fi
done

echo ""
echo "[$AGENT] 대기 시작"
echo "[$AGENT] 프로젝트: $PROJECT_DIR"
echo "[$AGENT] 권한: $AUTH_MODE"
echo "[$AGENT] 종료: Ctrl+C"
echo ""

cleanup() {
    rm -f "$DAEMON_MARKER"
    echo ""
    echo "[$AGENT] 종료됨"
    exit 0
}
trap cleanup EXIT INT TERM

while true; do
    if [ -f "$PENDING_FILE" ]; then
        TASK_ID=$(head -1 "$PENDING_FILE")
        MODE=$(sed -n '2p' "$PENDING_FILE")
        MODE="${MODE:-execute}"

        rm -f "$PENDING_FILE"

        STATUS_FILE="$REPORTS_DIR/.status_${TASK_ID}_${AGENT}"
        echo "IN_PROGRESS" > "$STATUS_FILE"

        echo "[$AGENT] 수신: $TASK_ID ($MODE)"
        echo "[$AGENT] 실행 중..."
        echo ""

        if bash "$DISPATCH_SCRIPT" "$AGENT" "$TASK_ID" "$AUTH_MODE" "$PROJECT_DIR" "$MODE"; then
            echo "DONE" > "$STATUS_FILE"
            echo ""
            echo "[$AGENT] 완료: $TASK_ID"
        else
            echo "ERROR" > "$STATUS_FILE"
            echo ""
            echo "[$AGENT] 오류: $TASK_ID (exit code $?)"
        fi

        echo "[$AGENT] -- 다음 지시 대기 중 --"
        echo ""
    fi

    sleep 3
done
