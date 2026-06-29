#!/usr/bin/env bash
# verify.sh <task-id> [project-dir]
#
# Phase 5 단계 6에서 Claude가 호출 — 네 가지를 자동 검증한다:
#   1. 스코프 초과 — TASK.md "허용 파일" 외 변경 여부
#   2. AC 체크리스트 — REPORT.md "AC 체크리스트" 미완료 항목 여부
#   3. 자동 검증 명령어 — AGENT_ROLES.md "자동 검증 명령어" 통과 여부
#   4. 완료 증거 파일 — TASK.md "완료 증거 파일" 목록의 파일 존재/변경 여부
#
# exit 0 = 전체 통과 (단계 7 진행 가능)
# exit 1 = 하나 이상 실패 (FEEDBACK.md 작성 후 단계 8)
#
# 사용법:
#   bash scripts/verify.sh T001
#   bash scripts/verify.sh T001 /abs/path/to/project

set -euo pipefail

TASK_ID="${1:?task-id 필요 (예: T001)}"
PROJECT_DIR="${2:-$(pwd)}"

TASK_FILE="$PROJECT_DIR/_agent_reports/$TASK_ID/TASK.md"
REPORT_FILE="$PROJECT_DIR/_agent_reports/$TASK_ID/REPORT.md"
AGENT_ROLES="$PROJECT_DIR/AGENT_ROLES.md"

FAILED=0
SCOPE_FAIL=0
AC_FAIL=0
EV_FAIL=0
SEC_FAIL=0
SEP="────────────────────────────────────────"

echo ""
echo "[$TASK_ID] verify.sh 시작"
echo "$SEP"

# ── 전제 조건 확인 ──────────────────────────────────────────────────

if [ ! -f "$TASK_FILE" ]; then
    echo "❌ TASK.md 없음: $TASK_FILE" >&2
    exit 1
fi

if [ ! -f "$REPORT_FILE" ]; then
    echo "❌ REPORT.md 없음 — 에이전트가 완료 보고를 작성하지 않았거나 실패함"
    exit 1
fi

if [ ! -s "$REPORT_FILE" ]; then
    echo "❌ REPORT.md가 비어 있음"
    exit 1
fi

# ── 섹션 추출 헬퍼 ──────────────────────────────────────────────────
# awk 대신 grep+tail+head 사용 — Windows Git Bash에서 awk 한글 패턴 미지원 우회
extract_section() {
    local file="$1"
    local pattern="$2"   # grep -E 패턴 (한글 포함)
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

# ── 1. 스코프 초과 검사 ─────────────────────────────────────────────

echo ""
echo "[검사 1/4] 스코프 초과"

ALLOWED_SECTION=$(extract_section "$TASK_FILE" "^## 허용 파일" | grep '^- ' | sed 's/^- //' || true)

if [ -z "$ALLOWED_SECTION" ]; then
    echo "  ⏭️  TASK.md에 '## 허용 파일' 없음 — 건너뜀"
else
    # dispatch 시점의 스냅샷과 비교하여 작업 이전 변경파일을 제외
    PRE_DISPATCH_FILE="$PROJECT_DIR/_agent_reports/$TASK_ID/.pre_dispatch_files"

    CHANGED_ALL=$(cd "$PROJECT_DIR" && {
        git diff --name-only HEAD 2>/dev/null || true
        git diff --cached --name-only 2>/dev/null || true
        git ls-files --others --exclude-standard 2>/dev/null || true
    } | sort -u)

    if [ -f "$PRE_DISPATCH_FILE" ]; then
        # dispatch 이후 변경분만 추출 (교집합 제거)
        CHANGED=$(comm -23 \
            <(echo "$CHANGED_ALL") \
            <(sort "$PRE_DISPATCH_FILE") \
        )
        if [ -z "$CHANGED" ] && [ -n "$CHANGED_ALL" ]; then
            echo "  ℹ️  모든 변경파일은 dispatch 이전부터 존재 → 범위 검사 생략"
            CHANGED=""
        fi
    else
        # .pre_dispatch_files 없으면 기존 방식으로 폴백
        CHANGED="$CHANGED_ALL"
        echo "  ℹ️  .pre_dispatch_files 없음 → 전체 diff로 폴백"
    fi

    if [ -z "$CHANGED" ]; then
        echo "  ⚠️  변경된 파일 없음 (git diff HEAD 기준)"
        FAILED=1
    else
        SCOPE_FAIL=0
        while IFS= read -r changed_file; do
            MATCH=0
            while IFS= read -r allowed; do
                [ -z "$allowed" ] && continue
                if [[ "$changed_file" == "$allowed" ]] || \
                   [[ "$changed_file" == "$allowed/"* ]]; then
                    MATCH=1
                    break
                fi
            done <<< "$ALLOWED_SECTION"
            if [ "$MATCH" -eq 0 ]; then
                echo "  ❌ 스코프 초과: $changed_file"
                SCOPE_FAIL=1
                FAILED=1
            fi
        done <<< "$CHANGED"

        if [ "$SCOPE_FAIL" -eq 0 ]; then
            echo "  ✅ 모든 변경이 허용 파일 범위 내"
        fi
    fi
fi

# ── 2. AC 체크리스트 확인 ───────────────────────────────────────────

echo ""
echo "[검사 2/4] AC 체크리스트"

# 한글(AC 체크리스트) 또는 영어(Acceptance Checklist) 모두 허용
AC_LINES=$(extract_section "$REPORT_FILE" "^## (AC 체크리스트|Acceptance Checklist)" | grep '^\- \[' || true)

if [ -z "$AC_LINES" ]; then
    echo "  ❌ REPORT.md에 '## AC 체크리스트' (또는 Acceptance Checklist) 섹션 없음"
    FAILED=1
else
    AC_FAIL=0
    while IFS= read -r line; do
        if echo "$line" | grep -q '^\- \[ \]'; then
            echo "  ❌ 미완료: ${line#- }"
            AC_FAIL=1
            FAILED=1
        elif echo "$line" | grep -qE '^\- \[[xX]\]'; then
            echo "  ✅ ${line#- }"
        fi
    done <<< "$AC_LINES"

    if [ "$AC_FAIL" -eq 0 ]; then
        echo "  ✅ 모든 AC 항목 완료"
    fi
fi

# ── 3. 자동 검증 명령어 ─────────────────────────────────────────────

echo ""
echo "[검사 3/4] 자동 검증 명령어"

if [ "${SCOPE_FAIL:-0}" -eq 1 ]; then
    echo "  ⚠️  스코프 검사 실패 — 명령 실행 건너뜀 (보안)"
elif [ ! -f "$AGENT_ROLES" ]; then
    echo "  ⏭️  AGENT_ROLES.md 없음 — 건너뜀"
else
    # 불릿(`- `) 있는 형식과 없는 형식 모두 지원: "- test: npm test" → "test: npm test"
    VERIFY_CMDS=$(extract_section "$AGENT_ROLES" "^## 자동 검증 명령어" \
        | grep -v "^<!--" \
        | sed 's/^- //' \
        | grep '^[a-zA-Z].*:' || true)

    if [ -z "$VERIFY_CMDS" ]; then
        echo "  ⏭️  AGENT_ROLES.md에 실행 가능한 검증 명령어 없음 — 건너뜀"
    else
        TMPOUT=$(mktemp)
        while IFS= read -r cmdline; do
            [ -z "$cmdline" ] && continue
            label=$(echo "$cmdline" | cut -d: -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            # xargs 대신 sed — xargs는 따옴표를 파싱해 eval 오류 유발
            cmd=$(echo "$cmdline" | cut -d: -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ -z "$cmd" ] && continue
            # "(없음" 으로 시작하는 명령어는 정의되지 않은 것으로 간주하고 건너뜀
            case "$cmd" in
                \(없음*|\(none*) echo "  ⏭️  $label: 정의 없음 — 건너뜀"; continue ;;
            esac

            if echo "$cmd" | grep -qE '[;&|`$(){}]|&&|\|\|'; then
                echo "  ❌ 명령 거부: 셸 메타문자 포함 — '$cmd'" >&2
                FAILED=1
                continue
            fi

            echo "  >>  $label: $cmd"
            _cmd_bin=$(echo "$cmd" | sed 's/^[[:space:]]*//' | cut -d' ' -f1 | sed 's|.*/||')
            _wl="bash sh npm npx pnpm yarn node tsc pytest cargo make bun deno go python python3 mypy jest mocha vitest mvn gradle cmake rtk"
            _ok=false
            for _w in $_wl; do [ "$_cmd_bin" = "$_w" ] && _ok=true && break; done
            if [ "$_ok" = false ]; then
                echo "  ❌ $label: 허용되지 않은 실행 파일 '$_cmd_bin'"
                echo "       화이트리스트: $_wl"
                FAILED=1
                continue
            fi
            read -ra _argv <<< "$cmd"
            if (cd "$PROJECT_DIR" && "${_argv[@]}" >"$TMPOUT" 2>&1); then
                echo "  ✅ $label 통과"
            else
                echo "  ❌ $label 실패:"
                sed 's/^/      /' "$TMPOUT"
                FAILED=1
            fi
        done <<< "$VERIFY_CMDS"
        rm -f "$TMPOUT"
    fi
fi

# ── 4. 완료 증거 파일 확인 ──────────────────────────────────────────

echo ""
echo "[검사 4/5] 완료 증거 파일"

EVIDENCE_LINES=$(extract_section "$TASK_FILE" "^## 완료 증거 파일" | grep '^- ' | sed 's/^- //' || true)

if [ -z "$EVIDENCE_LINES" ]; then
    echo "  ⏭️  TASK.md에 '## 완료 증거 파일' 없음 — 건너뜀"
else
    EV_FAIL=0
    CHANGED_LIST=$(cd "$PROJECT_DIR" && {
        git diff --name-only HEAD 2>/dev/null || true
        git diff --cached --name-only 2>/dev/null || true
        git ls-files --others --exclude-standard 2>/dev/null || true
    } | sort -u)

    while IFS= read -r evline; do
        [ -z "$evline" ] && continue
        evfile=$(echo "$evline" | awk '{print $1}')
        evtype=$(echo "$evline" | awk '{print $2}')

        FULL_PATH="$PROJECT_DIR/$evfile"

        if [ ! -f "$FULL_PATH" ] && [ ! -d "$FULL_PATH" ]; then
            echo "  ❌ 파일 없음: $evfile"
            EV_FAIL=1
            FAILED=1
            continue
        fi

        if [ "$evtype" = "수정됨" ] || [ "$evtype" = "생성됨" ]; then
            if echo "$CHANGED_LIST" | grep -qF "$evfile"; then
                echo "  ✅ $evfile ($evtype)"
            else
                echo "  ❌ $evfile — git diff에 변경 없음 (${evtype} 기대)"
                EV_FAIL=1
                FAILED=1
            fi
        else
            echo "  ✅ $evfile (존재 확인)"
        fi
    done <<< "$EVIDENCE_LINES"

    if [ "$EV_FAIL" -eq 0 ]; then
        echo "  ✅ 모든 완료 증거 파일 확인됨"
    fi
fi

# ── 5. 보안 패턴 스캔 ────────────────────────────────────────────────

echo ""
echo "[검사 5/5] 보안 패턴 스캔"

SEC_DIFF=$(cd "$PROJECT_DIR" && git diff HEAD 2>/dev/null || true)

if [ -z "$SEC_DIFF" ]; then
    echo "  ⏭️  변경된 내용 없음 — 건너뜀"
else
    SEC_FAIL=0

    # 1. 시크릿 패턴 감지 (추가된 줄만: ^+[^+])
    SECRET_HIT=$(echo "$SEC_DIFF" | grep '^+[^+]' | \
        grep -iE '(api[_-]?key|secret|password|passwd|token|bearer)\s*[=:]\s*["'"'"'][^"'"'"']{8,}' \
        2>/dev/null || true)
    if [ -n "$SECRET_HIT" ]; then
        echo "  ❌ 시크릿 패턴 감지 — 민감 정보 포함 가능성"
        echo "$SECRET_HIT" | head -3 | sed 's/^/      /'
        SEC_FAIL=1
        FAILED=1
    fi

    # 2. 위험 명령어 패턴 감지 (추가된 줄만)
    DANGER_HIT=$(echo "$SEC_DIFF" | grep '^+[^+]' | \
        grep -E '(rm\s+-rf\s|git\s+reset\s+--hard|DROP\s+TABLE|chmod\s+777|eval\s+\$)' \
        2>/dev/null || true)
    if [ -n "$DANGER_HIT" ]; then
        echo "  ❌ 위험 명령어 패턴 감지 — 검토 필요"
        echo "$DANGER_HIT" | head -3 | sed 's/^/      /'
        SEC_FAIL=1
        FAILED=1
    fi

    if [ "$SEC_FAIL" -eq 0 ]; then
        echo "  ✅ 보안 패턴 이상 없음"
    fi
fi

# ── 결과 요약 ────────────────────────────────────────────────────────

echo ""
echo "$SEP"
echo "[$TASK_ID] 총 실패 항목 수: ${FAILED}"
if [ "$FAILED" -eq 0 ]; then
    echo "[$TASK_ID] ✅ 전체 검증 통과 — 단계 7(커밋)으로 진행"

    # AC 점수 자동 집계 → record-score.sh 호출 (jq 필요, task_type 인식 시에만)
    _TASK_TYPE=$(grep -m1 '^task_type:' "$TASK_FILE" 2>/dev/null \
        | sed 's/^task_type:[[:space:]]*//' | tr -d '[:space:]' | cut -d. -f1 || true)
    if [ -n "${_TASK_TYPE:-}" ]; then
        _TASK_DIR="$(dirname "$REPORT_FILE")"
        _AC_PASS=$(grep -cE '^\s*- \[x\]' "$REPORT_FILE" 2>/dev/null || echo 0)
        _AC_FAIL=$(grep -cE '^\s*- \[ \]' "$REPORT_FILE" 2>/dev/null || echo 0)
        _AGENT=""
        [ -f "${_TASK_DIR}/_agy_stdout.log" ]     && _AGENT="agy"
        [ -f "${_TASK_DIR}/_codex_fallback.log" ] && _AGENT="codex"
        [ -f "${_TASK_DIR}/_codex_stdout.log" ] && [ -z "$_AGENT" ] && _AGENT="codex"
        SCRIPT_DIR_V="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -n "${_AGENT:-}" ] && command -v jq >/dev/null 2>&1; then
            bash "${SCRIPT_DIR_V}/record-score.sh" "$_AGENT" "$_TASK_TYPE" \
                "${_AC_PASS:-0}" "${_AC_FAIL:-0}" "$PROJECT_DIR" 2>/dev/null \
                && echo "  [자동] record-score: $_AGENT / $_TASK_TYPE / pass=${_AC_PASS} fail=${_AC_FAIL}" \
                || echo "  [자동] record-score skip (task_type 불인식 또는 오류)"
        fi
    fi
    exit 0
else
    echo "[$TASK_ID] ❌ 검증 실패 — 위 항목을 FEEDBACK.md에 포함해 단계 8(재배정)으로"

    # 실패 원인 코드 판별 (우선순위: 보안 > 스코프 > AC > 증거 > 검증명령)
    if [ "${SEC_FAIL:-0}" -eq 1 ]; then _FR="SEC_PATTERN"
    elif [ "${SCOPE_FAIL:-0}" -eq 1 ]; then _FR="SCOPE_VIOLATION"
    elif [ "${AC_FAIL:-0}" -eq 1 ]; then _FR="AC_INCOMPLETE"
    elif [ "${EV_FAIL:-0}" -eq 1 ]; then _FR="FILE_MISSING"
    else _FR="VERIFY_CMD_FAIL"; fi

    _TASK_TYPE_F=$(grep -m1 '^task_type:' "$TASK_FILE" 2>/dev/null \
        | sed 's/^task_type:[[:space:]]*//' | tr -d '[:space:]' | cut -d. -f1 || true)
    if [ -n "${_TASK_TYPE_F:-}" ]; then
        _TASK_DIR_F="$(dirname "$REPORT_FILE")"
        _AGENT_F=""
        [ -f "${_TASK_DIR_F}/_agy_stdout.log" ]     && _AGENT_F="agy"
        [ -f "${_TASK_DIR_F}/_codex_fallback.log" ] && _AGENT_F="codex"
        [ -f "${_TASK_DIR_F}/_codex_stdout.log" ] && [ -z "$_AGENT_F" ] && _AGENT_F="codex"
        SCRIPT_DIR_F="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -n "${_AGENT_F:-}" ] && command -v jq >/dev/null 2>&1; then
            FAIL_REASON="$_FR" bash "${SCRIPT_DIR_F}/record-score.sh" \
                "$_AGENT_F" "$_TASK_TYPE_F" "0" "0" "$PROJECT_DIR" 2>/dev/null \
                && echo "  [자동] record-fail: $_AGENT_F / $_TASK_TYPE_F / reason=$_FR" \
                || true
        fi
    fi
    exit 1
fi
