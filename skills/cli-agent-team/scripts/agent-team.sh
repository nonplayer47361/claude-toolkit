#!/usr/bin/env bash
# agent-team.sh — cli-agent-team 통합 CLI 래퍼
# Usage: bash agent-team.sh <command> [args...]
#
# 개별 스크립트를 직접 경로 없이 호출할 수 있도록 단일 진입점을 제공한다.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: agent-team <command> [args...]

Commands:
  init                       프로젝트 초기화 (init.sh)
  doctor                     환경 진단 (doctor.sh)
  dispatch <cli> <task-id> <auth> [dir] [mode] [tier]
                             에이전트 배정 (dispatch.sh)
  worktree <cli> <task-id> <auth> [dir] [mode] [tier]
                             워크트리 격리 배정 (worktree-dispatch.sh)
  verify <task-id> [dir]     결과 검증 (verify.sh)
  dashboard [--watch] [--verbose]
                             대시보드 (dashboard.sh)
  cross-review <task-id> <auth> [dir] [tier]
                             교차 리뷰 (cross-review.sh)
  score <agent> <type> <pass> <fail> [dir]
                             점수 기록 (record-score.sh)
  parallel-check <t-a> <t-b> [dir]
                             병렬 안전성 판정 (parallel-check.sh)
  help                       이 도움말 출력

환경:
  PROJECT_DIR  기본 프로젝트 경로 (미설정 시 현재 디렉토리)
EOF
}

CMD="${1:-}"
shift || true

case "$CMD" in
  init)            bash "$SCRIPT_DIR/init.sh" "$@" ;;
  doctor)          bash "$SCRIPT_DIR/doctor.sh" "$@" ;;
  dispatch)        bash "$SCRIPT_DIR/dispatch.sh" "$@" ;;
  worktree)        bash "$SCRIPT_DIR/worktree-dispatch.sh" "$@" ;;
  verify)          bash "$SCRIPT_DIR/verify.sh" "$@" ;;
  dashboard)       bash "$SCRIPT_DIR/dashboard.sh" "$@" ;;
  cross-review|review) bash "$SCRIPT_DIR/cross-review.sh" "$@" ;;
  score)           bash "$SCRIPT_DIR/record-score.sh" "$@" ;;
  parallel-check)  bash "$SCRIPT_DIR/parallel-check.sh" "$@" ;;
  help|--help|-h)  usage ;;
  "")
    echo "agent-team: 명령어를 지정하세요." >&2
    usage >&2
    exit 1
    ;;
  *)
    echo "agent-team: 알 수 없는 명령어 '$CMD'" >&2
    echo "  'agent-team help' 로 사용법을 확인하세요." >&2
    exit 1
    ;;
esac
