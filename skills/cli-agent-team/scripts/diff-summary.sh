#!/usr/bin/env bash
# diff-summary.sh <task-id> [project-dir]
#
# 에이전트 작업 완료 후 git diff를 구조화된 요약으로 출력한다.
#
# 사용법:
#   bash skills/cli-agent-team/scripts/diff-summary.sh T001
#   bash skills/cli-agent-team/scripts/diff-summary.sh T001 /abs/path/to/project
#
# 주의: set -euo pipefail 사용하지 않음 — 각 git 명령 실패 시에도 계속 실행
#       || true 로 개별 실패 무시

TASK_ID="${1:?사용법: diff-summary.sh <task-id> [project-dir]  예) diff-summary.sh T001}"
PROJECT_DIR="${2:-$(pwd)}"
TASK_FILE="$PROJECT_DIR/_agent_reports/$TASK_ID/TASK.md"

SEP="════════════════════════════════════════"

# ── git 환경 확인 ────────────────────────────────────────────────────

if ! command -v git > /dev/null 2>&1; then
    echo "오류: git 명령을 찾을 수 없습니다." >&2
    exit 1
fi

if ! git -C "$PROJECT_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    echo "오류: '$PROJECT_DIR' 는 git 저장소가 아닙니다." >&2
    exit 1
fi

# ── 섹션 추출 헬퍼 (Windows Git Bash 호환) ───────────────────────────
# awk 대신 grep+tail+head 사용 — Windows Git Bash에서 awk 한글 패턴 미지원 우회
extract_section() {
    local file="$1"
    local pattern="$2"
    local start
    start=$(grep -n -E "$pattern" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    [ -z "$start" ] && return 0
    local after
    after=$(tail -n "+$((start + 1))" "$file" | grep -n "^##[^#]" | head -1 | cut -d: -f1)
    if [ -z "$after" ]; then
        tail -n "+$((start + 1))" "$file"
    else
        tail -n "+$((start + 1))" "$file" | head -n "$((after - 1))"
    fi
}

# ── 변경 파일 목록 수집 ──────────────────────────────────────────────
# name-status 형식: "M\tfile.ts", "A\tnew.ts", "D\told.ts"

# HEAD 대비 변경 (unstaged)
UNSTAGED_STATUS=$(git -C "$PROJECT_DIR" diff --name-status HEAD 2>/dev/null || true)
# 스테이징된 변경
STAGED_STATUS=$(git -C "$PROJECT_DIR" diff --cached --name-status 2>/dev/null || true)
# 미추적 신규 파일
UNTRACKED=$(git -C "$PROJECT_DIR" ls-files --others --exclude-standard 2>/dev/null || true)

# 파일별 상태를 병합 (중복 제거, 신규 파일 우선 A, 수정 M, 삭제 D)
declare -A FILE_STATUS

# unstaged 처리
while IFS=$'\t' read -r status file; do
    [ -z "$file" ] && continue
    FILE_STATUS["$file"]="$status"
done <<< "$UNSTAGED_STATUS"

# staged 처리 (이미 있으면 staged 정보로 덮어씀)
while IFS=$'\t' read -r status file; do
    [ -z "$file" ] && continue
    FILE_STATUS["$file"]="$status"
done <<< "$STAGED_STATUS"

# untracked 처리
while IFS= read -r file; do
    [ -z "$file" ] && continue
    FILE_STATUS["$file"]="A"
done <<< "$UNTRACKED"

# ── 변경 파일 없으면 종료 ────────────────────────────────────────────

if [ ${#FILE_STATUS[@]} -eq 0 ]; then
    echo "변경된 파일 없음 (git diff HEAD 기준)"
    exit 0
fi

# ── 줄 수 집계 ───────────────────────────────────────────────────────
# 유형별 카운터
COUNT_MODIFIED=0
COUNT_ADDED=0
COUNT_DELETED=0
TOTAL_ADDED=0
TOTAL_REMOVED=0

# 표 행 저장용
TABLE_ROWS=""

for file in "${!FILE_STATUS[@]}"; do
    status="${FILE_STATUS[$file]}"

    # 유형 레이블
    case "$status" in
        M*) type_label="modified"; COUNT_MODIFIED=$((COUNT_MODIFIED + 1)) ;;
        A*) type_label="added";    COUNT_ADDED=$((COUNT_ADDED + 1)) ;;
        D*) type_label="deleted";  COUNT_DELETED=$((COUNT_DELETED + 1)) ;;
        R*) type_label="renamed";  COUNT_MODIFIED=$((COUNT_MODIFIED + 1)) ;;
        *)  type_label="$status";  COUNT_MODIFIED=$((COUNT_MODIFIED + 1)) ;;
    esac

    # 추가/삭제 줄 수 계산
    # untracked 파일은 git diff 대상이 아니므로 줄 수를 직접 카운트
    if [ "$type_label" = "added" ] && ! git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null | grep -qF "$file"; then
        # 미추적 파일: 전체 줄 수를 추가로 간주
        full_path="$PROJECT_DIR/$file"
        if [ -f "$full_path" ]; then
            added_lines=$(wc -l < "$full_path" 2>/dev/null || echo 0)
            added_lines=$((added_lines + 0))
        else
            added_lines=0
        fi
        removed_lines=0
    else
        added_lines=$(git -C "$PROJECT_DIR" diff HEAD -- "$file" 2>/dev/null | grep -c '^+[^+]' || true)
        removed_lines=$(git -C "$PROJECT_DIR" diff HEAD -- "$file" 2>/dev/null | grep -c '^-[^-]' || true)
        # staged도 포함
        staged_added=$(git -C "$PROJECT_DIR" diff --cached -- "$file" 2>/dev/null | grep -c '^+[^+]' || true)
        staged_removed=$(git -C "$PROJECT_DIR" diff --cached -- "$file" 2>/dev/null | grep -c '^-[^-]' || true)
        added_lines=$((added_lines + staged_added))
        removed_lines=$((removed_lines + staged_removed))
    fi

    TOTAL_ADDED=$((TOTAL_ADDED + added_lines))
    TOTAL_REMOVED=$((TOTAL_REMOVED + removed_lines))

    # 삭제 줄 표시: 0이면 "—"
    if [ "$removed_lines" -eq 0 ]; then
        removed_display="—"
    else
        removed_display="-$removed_lines"
    fi

    # 표 행 누적
    TABLE_ROWS="${TABLE_ROWS}${file}\t${type_label}\t+${added_lines}\t${removed_display}\n"
done

TOTAL_FILES=${#FILE_STATUS[@]}

# ── 출력 시작 ────────────────────────────────────────────────────────

printf "\n# %s Diff Summary\n" "$TASK_ID"
printf "%s\n\n" "$SEP"

# ── 변경 파일 표 ─────────────────────────────────────────────────────

printf "## 변경 파일 (%d개)\n" "$TOTAL_FILES"
printf "| 파일 | 유형 | 줄 추가 | 줄 삭제 |\n"
printf "|------|------|--------|--------|\n"

while IFS=$'\t' read -r f t a r; do
    [ -z "$f" ] && continue
    printf "| %s | %s | %s | %s |\n" "$f" "$t" "$a" "$r"
done < <(printf "%b" "$TABLE_ROWS" | sort)

# ── 핵심 변경 요약 ───────────────────────────────────────────────────

printf "\n## 핵심 변경 요약\n"
printf -- "- 수정 파일 %d개, 신규 파일 %d개, 삭제 파일 %d개\n" \
    "$COUNT_MODIFIED" "$COUNT_ADDED" "$COUNT_DELETED"
printf -- "- 총 +%d줄 / -%d줄\n" "$TOTAL_ADDED" "$TOTAL_REMOVED"

# ── 위험 신호 감지 ───────────────────────────────────────────────────

printf "\n## 위험 신호 (자동 감지)\n"

RISK_FOUND=0

# 변경 파일 목록 (파일명만, 줄바꿈 구분)
CHANGED_FILES=""
for file in "${!FILE_STATUS[@]}"; do
    CHANGED_FILES="${CHANGED_FILES}${file}\n"
done

# 1. 의존성 파일 변경 감지
if printf "%b" "$CHANGED_FILES" | grep -qE '(package\.json|package-lock\.json|yarn\.lock|Cargo\.lock|requirements\.txt|go\.sum)'; then
    printf "⚠ 의존성 파일 변경 감지 — 추가된 패키지 확인 필요\n"
    RISK_FOUND=1
fi

# 2. 시크릿 패턴 감지
SECRET_HIT=$(git -C "$PROJECT_DIR" diff HEAD 2>/dev/null | \
    grep -iE '(api[_-]?key|secret|password|token|bearer)\s*[=:]\s*["'"'"'][^"'"'"']{8,}' || true)
if [ -n "$SECRET_HIT" ]; then
    printf "⚠ 시크릿 패턴 감지 — 민감 정보 포함 여부 확인\n"
    RISK_FOUND=1
fi

# 3. 위험 명령어 패턴 감지
DANGER_HIT=$(git -C "$PROJECT_DIR" diff HEAD 2>/dev/null | \
    grep -E '(rm\s+-rf|git\s+reset\s+--hard|DROP\s+TABLE)' || true)
if [ -n "$DANGER_HIT" ]; then
    printf "⚠ 위험 명령어 패턴 감지 — 검토 필요\n"
    RISK_FOUND=1
fi

# 4. 스코프 외 파일 감지 (TASK.md 허용 파일과 대조)
if [ -f "$TASK_FILE" ]; then
    ALLOWED_SECTION=$(extract_section "$TASK_FILE" "^## 허용 파일" | grep '^- ' | sed 's/^- //' || true)
    if [ -n "$ALLOWED_SECTION" ]; then
        for file in "${!FILE_STATUS[@]}"; do
            MATCH=0
            while IFS= read -r allowed; do
                [ -z "$allowed" ] && continue
                if [ "$file" = "$allowed" ] || \
                   echo "$file" | grep -q "^${allowed}/"; then
                    MATCH=1
                    break
                fi
            done <<< "$ALLOWED_SECTION"
            if [ "$MATCH" -eq 0 ]; then
                printf "⚠ 허용 범위 외 파일 감지: %s\n" "$file"
                RISK_FOUND=1
            fi
        done
    fi
    # TASK.md에 허용 파일 섹션 없으면 건너뜀
fi
# TASK.md 없으면 스코프 검사 건너뜀

if [ "$RISK_FOUND" -eq 0 ]; then
    printf "(없음) — 자동 검사 통과\n"
fi

# ── 확인 필요 섹션 ───────────────────────────────────────────────────

printf "\n## 확인 필요\n"
if [ "$RISK_FOUND" -eq 0 ]; then
    printf "(없음)\n"
else
    printf "위 위험 신호 항목을 검토하세요.\n"
fi

printf "\n%s\n\n" "$SEP"
