#!/usr/bin/env bash
# parallel-check.sh <task-id-1> <task-id-2> [project-dir]
#
# 두 태스크를 동시에 실행해도 안전한지 판정한다.
# AGENT_ROLES.md에 "병렬 실행: 허용"이 있고 이 스크립트가 exit 0을 반환할 때만
# Claude가 두 에이전트에 동시 배정한다.
#
# 두 조건을 모두 통과해야 exit 0 (병렬 가능):
#   1. 두 태스크 모두 선행 태스크가 없거나 모두 DONE
#   2. 두 태스크의 "허용 파일" 목록이 겹치지 않음 (파일 충돌 없음)
#
# exit 0 = 병렬 가능
# exit 1 = 순차 필요 (이유 출력)
#
# 사용법:
#   bash scripts/parallel-check.sh T001 T002
#   bash scripts/parallel-check.sh T001 T002 /abs/path/to/project

set -euo pipefail

TASK_ID_1="${1:?task-id-1 필요}"
TASK_ID_2="${2:?task-id-2 필요}"
PROJECT_DIR="${3:-$(pwd)}"

AGENT_ROLES="${PROJECT_DIR}/AGENT_ROLES.md"
PARALLEL_ALLOWED=false

if [ -f "$AGENT_ROLES" ]; then
    if grep -qE "병렬\s*실행\s*:\s*허용|parallel\s*execution\s*:\s*allowed" "$AGENT_ROLES" 2>/dev/null; then
        PARALLEL_ALLOWED=true
    fi
fi

if [ "$PARALLEL_ALLOWED" != "true" ]; then
    echo "[parallel-check] AGENT_ROLES.md에 병렬 실행 허용 설정 없음 → 순차 실행" >&2
    exit 1
fi

TASK_FILE_1="$PROJECT_DIR/_agent_reports/$TASK_ID_1/TASK.md"
TASK_FILE_2="$PROJECT_DIR/_agent_reports/$TASK_ID_2/TASK.md"
PLAN_FILE="$PROJECT_DIR/PLAN.md"

SEP="────────────────────────────────────────"
FAILED=0

echo ""
echo "[$TASK_ID_1 || $TASK_ID_2] parallel-check 시작"
echo "$SEP"

# ── 섹션 추출 헬퍼 ──────────────────────────────────────────────────
# awk 한글 패턴 미지원(Windows Git Bash) 우회 — grep+tail+head 사용
extract_section() {
    local file="$1"
    local pattern="$2"
    local start
    start=$(grep -n -E "$pattern" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    [ -z "$start" ] && return 0
    local after
    after=$(tail -n "+$((start + 1))" "$file" | grep -n "^## " | head -1 | cut -d: -f1)
    if [ -z "$after" ]; then
        tail -n "+$((start + 1))" "$file"
    else
        tail -n "+$((start + 1))" "$file" | head -n "$((after - 1))"
    fi
}

# ── 전제 조건 ─────────────────────────────────────────────────────────
for tid in "$TASK_ID_1" "$TASK_ID_2"; do
    tf="$PROJECT_DIR/_agent_reports/$tid/TASK.md"
    if [ ! -f "$tf" ]; then
        echo "❌ TASK.md 없음: $tf"
        echo "  TASK.md를 먼저 작성하세요 (단계 2)."
        exit 1
    fi
done

# ── 검사 1: 선행 태스크 충족 여부 ─────────────────────────────────────
echo ""
echo "[검사 1/2] 선행 태스크 충족"

check_prereq() {
    local task_id="$1"
    local task_file="$2"

    local prereq_raw
    prereq_raw=$(grep -E '^선행:' "$task_file" 2>/dev/null | head -1 | sed 's/^선행: *//' || true)
    prereq_raw="${prereq_raw:-없음}"

    # 괄호 안 설명 제거: "T002, T004 (모두 DONE 확인됨)" → "T002,T004"
    local prereq_clean
    prereq_clean=$(echo "$prereq_raw" | sed 's/([^)]*)//g' | tr -d ' ')

    if [ "$prereq_clean" = "없음" ] || [ -z "$prereq_clean" ]; then
        echo "  ✅ $task_id: 선행 없음"
        return 0
    fi

    # PLAN.md가 없으면 확인 불가
    if [ ! -f "$PLAN_FILE" ]; then
        echo "  ⚠️  $task_id: PLAN.md 없음 — 선행 확인 불가, 순차 실행 권장"
        return 1
    fi

    # PLAN.md "## 완료" 섹션에서 선행 task-id 검색
    # 완료 섹션 포맷 (양쪽 지원):
    #   표 형식:      "| T001 | 작업명 | 커밋해시 | 비고 |"
    #   체크박스 형식: "- [x] T001: ..."
    local done_content
    done_content=$(extract_section "$PLAN_FILE" "^## 완료")

    local all_done=1
    # 쉼표로 구분된 task-id 목록을 순회
    for prereq in $(echo "$prereq_clean" | tr ',' '\n' | grep -v '^$'); do
        if echo "$done_content" | grep -qE "(\| *${prereq} *\||- \[x\] ${prereq}[: ])"; then
            echo "  ✅ $task_id: 선행 $prereq 완료 확인됨"
        else
            echo "  ❌ $task_id: 선행 $prereq 가 완료 섹션에 없음 — 순차 실행 필요"
            all_done=0
        fi
    done

    [ "$all_done" -eq 1 ] && return 0 || return 1
}

check_prereq "$TASK_ID_1" "$TASK_FILE_1" || FAILED=1
check_prereq "$TASK_ID_2" "$TASK_FILE_2" || FAILED=1

# ── 검사 2: 허용 파일 충돌 여부 ──────────────────────────────────────
echo ""
echo "[검사 2/2] 허용 파일 충돌"

get_allowed() {
    local file="$1"
    # awk 한글 패턴 미지원(Windows Git Bash) 우회 — grep으로 시작 줄 찾고 tail+head로 추출
    local start
    start=$(grep -n "^## 허용 파일" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    [ -z "$start" ] && return 0
    local after
    after=$(tail -n "+$((start + 1))" "$file" | grep -n "^##[^#]" | head -1 | cut -d: -f1)
    if [ -z "$after" ]; then
        tail -n "+$((start + 1))" "$file" | grep '^- ' | sed 's/^- //' || true
    else
        tail -n "+$((start + 1))" "$file" | head -n "$((after - 1))" | grep '^- ' | sed 's/^- //' || true
    fi
}

ALLOWED_1=$(get_allowed "$TASK_FILE_1")
ALLOWED_2=$(get_allowed "$TASK_FILE_2")

if [ -z "$ALLOWED_1" ] || [ -z "$ALLOWED_2" ]; then
    echo "  ⚠️  허용 파일 목록이 하나 이상 비어 있음 — 충돌 판정 불가 → 순차 실행 권장"
    FAILED=1
else
    CONFLICT=0
    while IFS= read -r file1; do
        [ -z "$file1" ] && continue
        while IFS= read -r file2; do
            [ -z "$file2" ] && continue
            # 접두사 겹침 검사: 한쪽이 다른 쪽의 접두사이거나 완전히 같으면 충돌
            if [[ "$file1" == "$file2" ]] || \
               [[ "$file2" == "$file1"* ]] || \
               [[ "$file1" == "$file2"* ]]; then
                echo "  ❌ 파일 충돌: $file1  ↔  $file2"
                CONFLICT=1
                FAILED=1
            fi
        done <<< "$ALLOWED_2"
    done <<< "$ALLOWED_1"

    if [ "$CONFLICT" -eq 0 ]; then
        echo "  ✅ 허용 파일 겹침 없음"
        echo "     $TASK_ID_1: $(echo "$ALLOWED_1" | tr '\n' ' ')"
        echo "     $TASK_ID_2: $(echo "$ALLOWED_2" | tr '\n' ' ')"
    fi
fi

# ── 결과 요약 ─────────────────────────────────────────────────────────
echo ""
echo "$SEP"
if [ "$FAILED" -eq 0 ]; then
    echo "[$TASK_ID_1 || $TASK_ID_2] ✅ 병렬 실행 가능"
    echo "  → codex에 $TASK_ID_1, agy에 $TASK_ID_2 동시 dispatch"
    exit 0
else
    echo "[$TASK_ID_1 || $TASK_ID_2] ❌ 병렬 불가 — 순차 실행"
    exit 1
fi
