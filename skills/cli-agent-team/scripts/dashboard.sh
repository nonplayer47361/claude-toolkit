#!/usr/bin/env bash
# dashboard.sh — 에이전트 상태 대시보드
#
# 사용법:
#   bash scripts/dashboard.sh            # 기본 보기
#   bash scripts/dashboard.sh --verbose  # 로그 포함
#   bash scripts/dashboard.sh --watch    # 3초마다 갱신

set -euo pipefail

# ─── 색상 정의 ───────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── 경로 설정 ───────────────────────────────────────────────────────────────
# 스크립트 위치에서 프로젝트 루트를 자동 탐색
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# skills/cli-agent-team/scripts → 프로젝트 루트(3단계 상위)
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REPORTS_DIR="${PROJECT_ROOT}/_agent_reports"

# ─── 인자 파싱 ───────────────────────────────────────────────────────────────
VERBOSE=false
WATCH=false

for arg in "$@"; do
  case "$arg" in
    --verbose) VERBOSE=true ;;
    --watch)   WATCH=true ;;
    --help|-h)
      echo "사용법: bash dashboard.sh [--verbose] [--watch]"
      echo "  --verbose  최근 로그 5줄 출력"
      echo "  --watch    3초마다 화면 갱신"
      exit 0
      ;;
  esac
done

# ─── 데몬 상태 판단 ──────────────────────────────────────────────────────────
daemon_status() {
  local name="$1"
  local marker="${REPORTS_DIR}/.daemon_${name}"
  if [ -f "$marker" ]; then
    echo -e "  ${name}$(printf '%*s' $((8 - ${#name})) '')${GREEN}● RUNNING${RESET}"
  else
    echo -e "  ${name}$(printf '%*s' $((8 - ${#name})) '')○ 중지됨"
  fi
}

# ─── STATUS 판단 로직 ─────────────────────────────────────────────────────────
# 우선순위: .status_<ID>_<agent> 파일 > REPORT.md 유무
get_task_status() {
  local task_dir="$1"
  local task_id="$2"

  # .status_<ID>_<agent> 파일 탐색
  local status_file
  status_file="$(ls "${REPORTS_DIR}/.status_${task_id}_"* 2>/dev/null | head -1 || true)"

  if [ -n "$status_file" ] && [ -f "$status_file" ]; then
    local val
    val="$(cat "$status_file" | tr -d '[:space:]')"
    case "$val" in
      DONE)        echo "DONE" ;;
      IN_PROGRESS) echo "IN_PROGRESS" ;;
      ERROR*)      echo "ERROR" ;;
      *)           echo "UNKNOWN" ;;
    esac
    return
  fi

  # REPORT.md 유무로 판단
  if [ -f "${task_dir}/REPORT.md" ]; then
    # REPORT.md가 있고 미완료 체크박스 [ ] 가 없으면 DONE
    if grep -q '\- \[ \]' "${task_dir}/REPORT.md" 2>/dev/null; then
      echo "IN_PROGRESS"
    else
      echo "DONE"
    fi
    return
  fi

  # TASK.md만 있으면 PENDING
  if [ -f "${task_dir}/TASK.md" ]; then
    echo "PENDING"
    return
  fi

  echo "UNKNOWN"
}

# ─── 에이전트 이름 추출 ──────────────────────────────────────────────────────
get_agent() {
  local task_dir="$1"
  local task_id="$2"

  # .status_<ID>_<agent> 파일에서 에이전트 이름 추출
  local status_file
  status_file="$(ls "${REPORTS_DIR}/.status_${task_id}_"* 2>/dev/null | head -1 || true)"
  if [ -n "$status_file" ] && [ -f "$status_file" ]; then
    # 파일명에서 마지막 _ 이후 추출
    basename "$status_file" | sed 's/^\.status_[^_]*_//'
    return
  fi

  # 로그 파일에서 에이전트 이름 추론
  if ls "${task_dir}/_codex_stdout.log" 2>/dev/null | head -1 | grep -q codex; then
    echo "codex"
  elif ls "${task_dir}/_agy_stdout.log" 2>/dev/null | head -1 | grep -q agy; then
    echo "agy"
  else
    echo "-"
  fi
}

# ─── 마지막 업데이트 시간 ────────────────────────────────────────────────────
get_updated() {
  local task_dir="$1"
  local target_file=""

  # REPORT.md > TODO.md > TASK.md 순으로 최신 파일 사용
  for f in REPORT.md TODO.md TASK.md; do
    if [ -f "${task_dir}/${f}" ]; then
      target_file="${task_dir}/${f}"
      break
    fi
  done

  if [ -z "$target_file" ]; then
    echo "-"
    return
  fi

  # GNU date와 macOS date 모두 지원
  if date -r "$target_file" "+%Y-%m-%d %H:%M" 2>/dev/null; then
    return
  fi
  # fallback: stat
  stat -c "%y" "$target_file" 2>/dev/null | cut -c1-16 || echo "-"
}

# ─── 메인 출력 함수 ──────────────────────────────────────────────────────────
print_dashboard() {
  echo ""
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║        Agent Dashboard — $(date '+%Y-%m-%d %H:%M:%S')        ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
  echo ""

  # ── 섹션 1: 데몬 상태 ──────────────────────────────────────────────────────
  echo -e "${BOLD}[데몬]${RESET}"
  daemon_status "codex"
  daemon_status "agy"
  echo ""

  # ── 섹션 2: 태스크 목록 ───────────────────────────────────────────────────
  echo -e "${BOLD}[태스크]${RESET}"
  printf "  %-12s %-22s %-8s %s\n" "TASK_ID" "STATUS" "AGENT" "UPDATED"
  printf "  %-12s %-22s %-8s %s\n" "------------" "--------------------" "--------" "----------------"

  # _agent_reports/ 아래 디렉토리 목록 (수정 시간 역순, 최근 10개)
  if [ ! -d "$REPORTS_DIR" ]; then
    echo "  (태스크 없음)"
  else
    local count=0
    # 수정 시간 기준 역순 정렬 (GNU find 사용 시 -printf, fallback은 ls -t)
    local task_dirs
    if ls -td "${REPORTS_DIR}"/*/  2>/dev/null | head -10 | grep -q .; then
      task_dirs="$(ls -td "${REPORTS_DIR}"/*/ 2>/dev/null | head -10)"
    else
      task_dirs=""
    fi

    if [ -z "$task_dirs" ]; then
      echo "  (태스크 없음)"
    else
      while IFS= read -r task_dir; do
        task_dir="${task_dir%/}"
        task_id="$(basename "$task_dir")"
        [ "$count" -ge 10 ] && break

        local status agent updated colored_status

        status="$(get_task_status "$task_dir" "$task_id")"
        agent="$(get_agent "$task_dir" "$task_id")"
        updated="$(get_updated "$task_dir")"

        case "$status" in
          DONE)
            colored_status="${GREEN}✅ DONE${RESET}"
            ;;
          IN_PROGRESS)
            colored_status="${YELLOW}🔄 IN_PROGRESS${RESET}"
            ;;
          ERROR)
            colored_status="${RED}❌ ERROR${RESET}"
            ;;
          PENDING)
            colored_status="📋 PENDING"
            ;;
          *)
            colored_status="❓ UNKNOWN"
            ;;
        esac

        printf "  %-12s " "$task_id"
        printf "${colored_status}"
        # 이모지 포함 시 폭 보정 (이모지 2칸 차지)
        local raw_len=${#status}
        local pad=$(( 22 - raw_len - 3 ))
        [ "$pad" -lt 1 ] && pad=1
        printf "%${pad}s" ""
        printf "%-8s %s\n" "$agent" "$updated"

        count=$(( count + 1 ))
      done <<< "$task_dirs"
    fi
  fi

  echo ""

  # ── 섹션 3: 최근 로그 (--verbose 시) ──────────────────────────────────────
  if [ "$VERBOSE" = true ]; then
    echo -e "${BOLD}[최근 로그]${RESET}"
    local found_log=false
    for task_dir in "${REPORTS_DIR}"/*/; do
      task_dir="${task_dir%/}"
      for log_file in "${task_dir}"/_agy_stdout.log "${task_dir}"/_codex_stdout.log; do
        if [ -f "$log_file" ]; then
          local rel_log="${log_file#"${PROJECT_ROOT}/"}"
          echo -e "  ${CYAN}${rel_log}${RESET} (마지막 5줄)"
          tail -5 "$log_file" | while IFS= read -r line; do
            echo "    $line"
          done
          echo ""
          found_log=true
        fi
      done
    done
    if [ "$found_log" = false ]; then
      echo "  (로그 없음)"
      echo ""
    fi
  fi
}

# ─── 실행 ────────────────────────────────────────────────────────────────────
if [ "$WATCH" = true ]; then
  while true; do
    clear
    print_dashboard
    sleep 3
  done
else
  print_dashboard
fi
