#!/usr/bin/env bash
# dashboard.sh — 프로젝트 태스크 대시보드
#
# 사용법:
#   bash scripts/dashboard.sh            # 기본 출력
#   bash scripts/dashboard.sh --verbose  # 로그 포함
#   bash scripts/dashboard.sh --watch    # 실시간 갱신
#                                         (1초마다 갱신,
#                                          태스크 변경 시에만 전체 재출력)

set -euo pipefail

# 색상 코드 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# 경로 기준 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REPORTS_DIR="${PROJECT_ROOT}/_agent_reports"

# 인수 파싱
VERBOSE=false
WATCH=false

for arg in "$@"; do
  case "$arg" in
    --verbose) VERBOSE=true ;;
    --watch)   WATCH=true ;;
    --help|-h)
      echo "사용법: bash dashboard.sh [--verbose] [--watch]"
      echo "  --verbose  최근 로그 5줄 출력"
      echo "  --watch    실시간 갱신 (1초마다 갱신, 태스크 변경 시 전체 재출력)"
      exit 0
      ;;
  esac
done

# 데몬 상태 표시
daemon_status() {
  local name="$1"
  local marker="${REPORTS_DIR}/.daemon_${name}"
  if [ -f "$marker" ]; then
    echo -e "  ${name}$(printf '%*s' $((8 - ${#name})) '')${GREEN}● RUNNING${RESET}"
  else
    echo -e "  ${name}$(printf '%*s' $((8 - ${#name})) '')○ 정지"
  fi
}

# 태스크 STATUS 판별
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

# 담당 에이전트 이름 추출
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

# 가장 최근 업데이트 시각 추출
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

# 태스크 행 출력
print_task_row() {
  local status="$1" task_id="$2" agent="$3" updated="$4"
  local colored_status

  case "$status" in
    DONE)        colored_status="${GREEN}✓ DONE${RESET}" ;;
    IN_PROGRESS) colored_status="${YELLOW}⚙ IN_PROGRESS${RESET}" ;;
    ERROR)       colored_status="${RED}✗ ERROR${RESET}" ;;
    PENDING)     colored_status="⋯ PENDING" ;;
    *)           colored_status="? UNKNOWN" ;;
  esac

  printf "  %-14s " "$task_id"
  printf "${colored_status}"
  local pad=$(( 22 - ${#status} - 3 ))
  [ "$pad" -lt 1 ] && pad=1
  printf "%${pad}s" ""
  printf "%-8s %s\n" "$agent" "$updated"
}

# 태스크 목록 (IN_PROGRESS 우선·최신순) 출력
print_task_list() {
  if [ ! -d "$REPORTS_DIR" ]; then
    echo "  (태스크 없음)"
    return
  fi

  # ls -td: 수정 시각 순(최신 위)
  local all_dirs
  all_dirs="$(ls -td "${REPORTS_DIR}"/*/ 2>/dev/null || true)"

  if [ -z "$all_dirs" ]; then
    echo "  (태스크 없음)"
    return
  fi

  # 우선순위 별로 묶어 출력 (같은 우선순위 내 최신 디렉토리 순)
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

  # 우선순위 기준 stable sort (같은 우선순위 내 순서 = 최신순 유지)
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

# 헤더 출력 (시각 갱신용)
print_header() {
  echo ""
  echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}${CYAN}║        Agent Dashboard ▸ $(date '+%Y-%m-%d %H:%M:%S')        ║${RESET}"
  echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"
}

# 전체 대시보드 출력
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

  if [ "$WATCH" = true ]; then
    echo -e "  ${BOLD}[r]${RESET} 재시도  ${BOLD}[c]${RESET} 취소  ${BOLD}[q]${RESET} 종료"
  fi
}

# 핑거프린트 변화 감지
get_fingerprint() {
  # 의미 있는 변화만 감지:
  #   - 태스크 디렉토리 목록 (태스크 추가/삭제)
  #   - .status_* 파일 내용 (IN_PROGRESS→DONE 등 상태 전환)
  #   - .daemon_* 파일 유무 (데몬 up/down)
  {
    ls -d "${REPORTS_DIR}/"/  2>/dev/null        # 태스크 추가/삭제
    cat  "${REPORTS_DIR}"/.status_* 2>/dev/null   # 상태 변경
    ls   "${REPORTS_DIR}"/.daemon_* 2>/dev/null   # 데몬 유무
  } | cksum 2>/dev/null || echo "0 0"
}

# 메인 실행
if [ "$WATCH" = true ]; then
  # clear 후 print_header가 차지하는 고정 위치:
  #   row 1: echo ""  (빈 줄)
  #   row 2: ══...══
  #   row 3: ║ Dashboard ▸ TIME ║  ← 시각 갱신 행
  #   row 4: ══...══
  CLOCK_ROW=3

  LAST_FP=""
  while true; do
    CURRENT_FP="$(get_fingerprint)"
    if [ "$CURRENT_FP" != "$LAST_FP" ]; then
      # 태스크/데몬 변경 → 전체 재출력
      clear
      print_dashboard
      LAST_FP="$CURRENT_FP"
    else
      # 시각만 갱신 (ANSI 커서 이동으로 해당 행만 덮어씀)
      printf "\e[${CLOCK_ROW};1H"
      printf "${BOLD}${CYAN}║        Agent Dashboard ▸ $(date '+%Y-%m-%d %H:%M:%S')        ║${RESET}"
    fi

    KEY=""
    read -t 1 -n 1 KEY 2>/dev/null || true

    case "$KEY" in
      r|R)
        # 재시도: ERROR 상태 태스크 ID 입력받아 reset-task.sh 호출
        echo ""
        echo "재시도할 태스크 ID를 입력하세요 (Enter 확인):"
        read -r RETRY_ID 2>/dev/null || RETRY_ID=""
        if [ -n "$RETRY_ID" ]; then
          RESET_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/reset-task.sh"
          if [ -f "$RESET_SCRIPT" ]; then
            # 에이전트 이름을 상태 파일에서 자동 탐색
            STATUS_FILE="$(ls "${REPORTS_DIR}/.status_${RETRY_ID}_"* 2>/dev/null | head -1 || true)"
            if [ -n "$STATUS_FILE" ]; then
              AGENT_NAME="$(basename "$STATUS_FILE" | sed 's/^\.status_[^_]*_//')"
              bash "$RESET_SCRIPT" "$RETRY_ID" "$AGENT_NAME" && echo "  ✓ $RETRY_ID 재시도 준비 완료 (trigger.sh 실행 필요)" || echo "  ✗ reset 실패"
            else
              echo "  ✗ 상태 파일 없음: $RETRY_ID"
            fi
          else
            echo "  ✗ reset-task.sh 없음: $RESET_SCRIPT"
          fi
        fi
        LAST_FP=""  # 다음 루프에서 전체 재출력
        ;;
      c|C)
        # 취소: IN_PROGRESS 태스크를 ERROR로 강제 전환 (수동 개입 필요 상황)
        echo ""
        echo "취소할 태스크 ID를 입력하세요 (Enter 확인):"
        read -r CANCEL_ID 2>/dev/null || CANCEL_ID=""
        if [ -n "$CANCEL_ID" ]; then
          STATUS_FILE="$(ls "${REPORTS_DIR}/.status_${CANCEL_ID}_"* 2>/dev/null | head -1 || true)"
          if [ -n "$STATUS_FILE" ] && [ -f "$STATUS_FILE" ]; then
            echo "ERROR" > "$STATUS_FILE"
            echo "  ✓ $CANCEL_ID 를 ERROR 상태로 전환했습니다"
          else
            echo "  ✗ 상태 파일 없음: $CANCEL_ID"
          fi
        fi
        LAST_FP=""
        ;;
      q|Q)
        echo ""
        echo "대시보드 종료"
        exit 0
        ;;
    esac
  done
else
  print_dashboard
fi