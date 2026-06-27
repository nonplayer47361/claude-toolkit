#!/usr/bin/env bash
# trigger.sh <agent> <task-id> <mode> [project-dir]
#
# 에이전트 데몬(agent-watch.ps1)이 실행 중일 때만 사용.
# 트리거 파일을 써서 데몬에게 작업을 전달하고, 완료 신호를 기다린다.
#
# Claude는 데몬 모드에서 dispatch.sh 대신 이 스크립트를 run_in_background로 호출한다.
# 데몬 미실행 상태이면 명확한 오류를 낸다 — 데몬 없이 직접 실행은 dispatch.sh를 쓴다.
#
# 흐름:
#   Claude           → trigger.sh 호출 (run_in_background)
#   trigger.sh       → .pending_<agent> 파일 작성
#   agent-watch.ps1  → 파일 감지 → dispatch.sh 실행 → .status_<task-id>_<agent>=DONE
#   trigger.sh       → DONE 감지 → 종료 (Claude에게 harness 알림)

set -euo pipefail

AGENT="${1:?usage: trigger.sh <agent> <task-id> <mode> [project-dir]}"
TASK_ID="${2:?task-id required}"
MODE="${3:-execute}"
DIR="${4:-$(pwd)}"

cd "$DIR"

REPORTS_DIR="_agent_reports"
DAEMON_MARKER="${REPORTS_DIR}/.daemon_${AGENT}"
PENDING="${REPORTS_DIR}/.pending_${AGENT}"
STATUS="${REPORTS_DIR}/.status_${TASK_ID}_${AGENT}"

# 데몬 실행 여부 확인
if [ ! -f "$DAEMON_MARKER" ]; then
  echo "ERROR: ${AGENT} 데몬이 실행 중이지 않습니다." >&2
  echo "" >&2
  echo "  VS Code 터미널 패널에서 먼저 실행하세요:" >&2
  echo "  .\\scripts\\agent-watch.ps1 -Agent ${AGENT} -AuthMode <full|limited>" >&2
  echo "" >&2
  echo "  또는 데몬 없이 직접 실행하려면:" >&2
  echo "  bash scripts/dispatch.sh ${AGENT} ${TASK_ID} <auth-mode> [dir] ${MODE}" >&2
  exit 1
fi

# 이전 트리거가 아직 처리 중이면 대기
if [ -f "$PENDING" ]; then
  echo "[trigger] ${AGENT}가 이미 다른 트리거를 처리 중 — 대기..."
  while [ -f "$PENDING" ]; do
    sleep 2
  done
fi

# 상태 파일 초기화 (이전 run 잔재 제거)
rm -f "$STATUS"

# 트리거 파일 작성 (1행: task-id, 2행: mode)
printf "%s\n%s\n" "$TASK_ID" "$MODE" > "$PENDING"
echo "[trigger] ${AGENT} → ${TASK_ID} (${MODE}) 전송"

# 데몬이 트리거를 수신할 때까지 대기 (PENDING 파일 소멸 = 데몬이 가져감)
echo "[trigger] ${AGENT} 데몬 수신 대기..."
WAIT=0
while [ -f "$PENDING" ]; do
  sleep 1
  WAIT=$((WAIT + 1))
  if [ $WAIT -ge 30 ]; then
    echo "ERROR: ${AGENT} 데몬이 30초 안에 트리거를 수신하지 않았습니다." >&2
    echo "  agent-watch.ps1이 실행 중인지 확인하세요." >&2
    rm -f "$PENDING"
    exit 1
  fi
done
echo "[trigger] ${AGENT} 수신 완료 — 작업 완료 대기 중..."

# 완료(DONE) 신호 대기 (작업은 수분~수십분 걸릴 수 있음)
while true; do
  if [ -f "$STATUS" ] && grep -q "DONE" "$STATUS"; then
    echo "[trigger] ${AGENT} → ${TASK_ID} 완료"
    exit 0
  fi
  sleep 5
done
