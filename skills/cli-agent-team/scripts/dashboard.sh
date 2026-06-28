#!/usr/bin/env bash
# dashboard.sh — 에이전트 상태 대시보드
#
# 사용법:
#   bash scripts/dashboard.sh            # 기본 보기
#   bash scripts/dashboard.sh --verbose  # 로그 포함
#   bash scripts/dashboard.sh --watch    # 실시간 모드
#                                         (시계 1초 갱신,
#                                          태스크 변경 시에만 전체 갱신)

set -euo pipefail

# ─── 색상 정의 ──────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── 경로 설정 ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REPORTS_DIR="${PROJECT_ROOT}/_agent_reports"

# ─── 인자 파싱 ──────────────────────────────────────────────────────────────
VERBOSE=false
WATCH=false

for arg in "$@"; do
  case "$arg" in
    --verbose) VERBOSE=true ;;
    --watch)   WATCH=true ;;
    --help|-h)
      echo "사용법: bash dashboard.sh [--verbose] [--watch]"
      echo "  --verbose  최근 로그 5줄 출력"
      echo "  --watch    실시간 모드 (시계 1초 갱신, 태스크 변경 시 전체 갱신)"
      exit 0
      ;;
  esac
done

# ─── 데몬 상태 ──────────────────────────────────────────────────────────────
daemon_status() {
  local name="$1"
  local marker="${REPORTS_DIR}/.daemon_${name}"
  if [ -f "$marker" ]; then
    echo -e "  ${name}$(printf '%*s' $((8 - ${#name})) '')${GREEN}● RUNNING${RESET}"
  else
    echo -e "  ${name}$(printf '%*s' $((8 - ${#name})) '')○ 중지됨"
  fi
}

# ─── STATUS 판단 ─────────────────────────────────────────────────────────────
get_task_status() {
  local task_dir="$1"
  local task_id="$2"

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

  if [ -f "${task_dir}/REPORT.md" ]; then
    if grep -q '\- \[ \]' "${task_dir}/REPORT.md" 2>/dev/null; then
      echo "IN_PROGRESS"
    else
      echo "DONE"
    fi
    return
  fi

  [ -f "${task_dir}/TASK.md" ] && echo "PENDING" && return
  echo "UNKNOWN"
}

# ─── 에이전트 이름 ──────────────────────────────────────────────────────────
get_agent() {
  local task_dir="$1"
  local task_id="$2"

  local status_file
  status_file="$(ls "${REPORTS_DIR}/.status_${task_id}_"* 2>/dev/null | head -1 || true)"
  if [ -n "$status_file" ] && [ -f "$status_file" ]; then
    basename "$status_file" | sed 's/^\.status_[^_]*_//'
    return
  fi

  if ls "${task_dir}/_codex_stdout.log" 2>/dev/null | grep -q codex; then
    echo "codex"
  elif ls "${task_dir}/_agy_stdout.log" 2>/dev/null | grep -q agy; then
    echo "agy"
  else
    echo "-"
  fi
}

# ─── 마지막 업데이트 시간 ───────────────────────────────────────────────────
get_updated() {
  local task_dir="$1"
  local target_file=""

  for f in REPORT.md TODO.md TASK.md; do
    if [ -f "${task_dir}/${f}" ]; then
      target_file="${task_dir}/${f}"
      break
    fi
  done

  [ -z "$target_file" ] && echo "-" && return

  if date -r "$target_file" "+%m-%d %H:%M" 2>/dev/null; then
    return
  fi
  stat -c "%y" "$target_file" 2>/dev/null | cut -c6-11,12-16 || echo "-"
}

# ─── 태스크 한 줄 출력 ──────────────────────────────────────────────────────
print_task_row() {
  local status="$1" task_id="$2" agent="$3" updated="$4"
  local colored_status

  case "$status" in
    DONE)        colored_status="${GREEN}✅ DONE${RESET}" ;;
    IN_PROGRESS) colored_status="${YELLOW}🔄 IN_PROGRESS${RESET}" ;;
    ERROR)       colored_status="${RED}❌ ERROR${RESET}" ;;
    PENDING)     colored_status="📋 PENDING" ;;
    *)           colored_status="❓ UNKNOWN" ;;
  esac

  printf "  %-14s " "$task_id"
  printf "${colored_status}"
  local pad=$(( 22 - ${#status} - 3 ))
  [ "$pad" -lt 1 ] && pad=1
  printf "%${pad}s" ""
  printf "%-8s %s\n" "$agent" "$updated"
}

# ─── 태스크 목록 (IN_PROGRESS 최상단 → 최신순) ──────────────────────────────
print_task_list() {
  if [ ! -d "$REPORTS_DIR" ]; then
    echo "  (태스크 없음)"
    return
  fi

  # ls -td: 수정 시간 역순(최신 먼저)
  local all_dirs
  all_dirs="$(ls -td "${REPORTS_DIR}"/*/ 2>/dev/null || true)"

  if [ -z "$all_dirs" ]; then
    echo "  (태스크 없음)"
    return
  fi

  # 우선순위 버킷 파일에 수집 (서브셸 없이 파일 리다이렉트 사용)
  local tmp_bucket
  tmp_bucket="$(mktemp)"

  while IFS= read -r task_dir; do
    [ -z "$task_dir" ] && continue
    task_dir="${task_dir%/}"
    local task_id status agent updated prio
    task_id="$(basename "$task_dir")"
    status="$(get_task_status "$task_dir" "$task_id")"
    agent="$(get_agent "$task_dir" "$task_id")"
    updated="$(get_updated "$task_dir")"

    # 우선순위: IN_PROGRESS=1, ERROR=2, DONE=3, PENDING=4
    case "$status" in
      IN_PROGRESS) prio=1 ;;
      ERROR)       prio=2 ;;
      DONE)        prio=3 ;;
      PENDING)     prio=4 ;;
      *)           prio=9 ;;
    esac

    echo "${prio}|${status}|${task_id}|${agent}|${updated}"
  done <<< "$all_dirs" > "$tmp_bucket"

  if [ ! -s "$tmp_bucket" ]; then
    echo "  (태스크 없음)"
    rm -f "$tmp_bucket"
    return
  fi

  # 우선순위 기준 stable sort (같은 우선순위 내 원래 순서 = 최신순 유지)
  local tmp_sorted
  tmp_sorted="$(mktemp)"
  sort -t'|' -k1,1n -s "$tmp_bucket" > "$tmp_sorted"

  local printed=0
  while IFS='|' read -r prio status task_id agent updated; do
    print_task_row "$status" "$task_id" "$agent" "$updated"
    printed=$(( printed + 1 ))
  done < "$tmp_sorted"

  [ "$printed" -eq 0 ] && echo "  (태스크 없음)"

  rm -f "$tmp_bucket" "$tmp_sorted"
}

# ─── 헤더(시계 포함) ────────────────────────────────────────────────────────
print_header() {
  echo ""
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║        Agent Dashboard — $(date '+%Y-%m-%d %H:%M:%S')        ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${RESET}"
}

# ─── 전체 대시보드 출력 ─────────────────────────────────────────────────────
print_dashboard() {
  print_header
  echo ""

  echo -e "${BOLD}[데몬]${RESET}"
  daemon_status "codex"
  daemon_status "agy"
  echo ""

  echo -e "${BOLD}[태스크]${RESET}"
  printf "  %-14s %-22s %-8s %s\n" "TASK_ID" "STATUS" "AGENT" "UPDATED"
  printf "  %-14s %-22s %-8s %s\n" "--------------" "--------------------" "--------" "--------"
  print_task_list
  echo ""

  if [ "$VERBOSE" = true ]; then
    echo -e "${BOLD}[최근 로그]${RESET}"
    local found_log=false
    for task_dir in "${REPORTS_DIR}"/*/; do
      [ -d "$task_dir" ] || continue
      task_dir="${task_dir%/}"
      for log_file in "${task_dir}"/_agy_stdout.log "${task_dir}"/_codex_stdout.log; do
        if [ -f "$log_file" ]; then
          local rel_log="${log_file#"${PROJECT_ROOT}/"}"
          echo -e "  ${CYAN}${rel_log}${RESET} (마지막 5줄)"
          tail -5 "$log_file" | while IFS= read -r line; do echo "    $line"; done
          echo ""
          found_log=true
        fi
      done
    done
    [ "$found_log" = false ] && echo "  (로그 없음)" && echo ""
  fi
}

# ─── 변경 감지용 지문 ───────────────────────────────────────────────────────
get_fingerprint() {
  # 의미 있는 상태 변화만 감지:
  #   - 태스크 디렉토리 목록 (태스크 추가/삭제)
  #   - .status_* 파일 내용 (IN_PROGRESS→DONE 등 상태 전환)
  #   - .daemon_* 파일 존재 여부 (데몬 up/down)
  {
    ls -d "${REPORTS_DIR}"/*/  2>/dev/null        # 태스크 추가/삭제
    cat  "${REPORTS_DIR}"/.status_* 2>/dev/null   # 상태 파일 내용
    ls   "${REPORTS_DIR}"/.daemon_* 2>/dev/null   # 데몬 마커
  } | cksum 2>/dev/null || echo "0 0"
}

# ─── 실행 ───────────────────────────────────────────────────────────────────
if [ "$WATCH" = true ]; then
  # clear 후 print_header가 출력하는 줄 위치:
  #   row 1: echo ""  (빈 줄)
  #   row 2: ╔══...╗
  #   row 3: ║ Dashboard — TIME ║  ← 시계 줄
  #   row 4: ╚══...╝
  CLOCK_ROW=3

  LAST_FP=""
  while true; do
    CURRENT_FP="$(get_fingerprint)"
    if [ "$CURRENT_FP" != "$LAST_FP" ]; then
      # 태스크/데몬 변경 — 전체 갱신
      clear
      print_dashboard
      LAST_FP="$CURRENT_FP"
    else
      # 시계만 갱신 (ANSI 커서 이동 → 해당 행 덮어쓰기)
      printf "\e[${CLOCK_ROW};1H"
      printf "${BOLD}${CYAN}║        Agent Dashboard — $(date '+%Y-%m-%d %H:%M:%S')        ║${RESET}"
    fi
    sleep 1
  done
else
  print_dashboard
fi
