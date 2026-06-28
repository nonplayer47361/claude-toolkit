#!/usr/bin/env bash
# run_failure_tests.sh [project-dir] [skill-dir]
#
# cli-agent-team 스킬 실패 시나리오 E2E 테스트.
# 최대 20개 시나리오: 12개 실패 감지 + 1개 정상(병렬 허용) + 1개 회복(ERROR 후 재트리거)
#   + 4개 MODEL_TIER + 최대 2개 PTY-bridge (node-pty 설치 시).
# 데몬 없이 실행 가능 (testcli 격리 에이전트로 trigger.sh 테스트).
#
# 사용법:
#   bash run_failure_tests.sh /path/to/project /path/to/skill
#
# 각 테스트는 독립적으로 실행되며, 사이드이펙트를 정리하고 종료한다.

set -uo pipefail

PROJECT_DIR="${1:-$(pwd)}"
SKILL_DIR="${2:-$(cd "$(dirname "$0")/.." && pwd)}"

DISPATCH="$SKILL_DIR/scripts/dispatch.sh"
VERIFY="$SKILL_DIR/scripts/verify.sh"
PARALLEL="$SKILL_DIR/scripts/parallel-check.sh"
TRIGGER="$SKILL_DIR/scripts/trigger.sh"
RESET="$SKILL_DIR/scripts/reset-task.sh"

REPORTS="$PROJECT_DIR/_agent_reports"

PASS=0
FAIL=0
TOTAL=0
SEP="════════════════════════════════════════"
LAST_OUTPUT=""   # run_test 직후 assert_output이 참조하는 마지막 테스트 출력

# ── 테스트 헬퍼 ─────────────────────────────────────────────────────────

run_test() {
    local name="$1"
    local expect_exit="$2"   # "fail"(non-zero) | "pass"(0)
    local description="$3"
    shift 3
    # 이후 인자: 실행할 커맨드

    TOTAL=$((TOTAL + 1))
    echo ""
    echo "[$name] $description"

    local out
    local actual_exit=0
    out=$(set +e; "$@" 2>&1; echo "EXIT:$?") || true
    actual_exit=$(echo "$out" | tail -1 | sed 's/EXIT://')
    out=$(echo "$out" | head -n -1)
    LAST_OUTPUT="$out"

    local result_ok=0
    if [ "$expect_exit" = "fail" ] && [ "$actual_exit" -ne 0 ]; then
        result_ok=1
    elif [ "$expect_exit" = "pass" ] && [ "$actual_exit" -eq 0 ]; then
        result_ok=1
    fi

    if [ "$result_ok" -eq 1 ]; then
        echo "  ✅ PASS (exit $actual_exit)"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL (기대: $expect_exit, 실제 exit: $actual_exit)"
        FAIL=$((FAIL + 1))
    fi

    # 핵심 출력 1~3줄만 표시 (grep 0건 시에도 pipefail 방지)
    echo "$out" | grep -E "(ERROR|❌|✅|WARNING|완료 섹션|파일 충돌|REPORT|TASK|스코프|미완료|실패|없음)" \
        | head -3 | sed 's/^/      /' || true
}

# 직전 run_test의 출력에서 패턴을 검증.
# 실패 시 해당 run_test 결과를 소급해서 FAIL로 전환 (TOTAL은 그대로).
assert_output() {
    local pattern="$1"
    local msg="${2:-출력 검증}"
    if echo "$LAST_OUTPUT" | grep -qE "$pattern"; then
        echo "  ✅ $msg"
    else
        echo "  ❌ $msg ('$pattern' 미발견 — 다른 이유로 실패했을 가능성)"
        PASS=$((PASS - 1))
        FAIL=$((FAIL + 1))
    fi
}

# ── 테스트 픽스처 ────────────────────────────────────────────────────────

make_task() {
    local task_id="$1"
    local allowed="$2"        # 줄바꿈 구분 파일 목록 (비어도 됨)
    local prereq="${3:-없음}"
    local dir="$REPORTS/$task_id"
    mkdir -p "$dir"
    cat > "$dir/TASK.md" <<EOF
# TASK.md — $task_id

배정: codex
선행: $prereq
규모: 소형

## 목표
실패 시나리오 테스트용 가짜 태스크.

## 허용 파일
$(echo "$allowed" | sed 's/^/- /')

## 완료 증거 파일
$(echo "$allowed" | head -1 | sed 's/^/- /' | sed 's/$/ 생성됨/')

## AC 체크리스트
- [ ] 테스트 항목 완료
EOF
}

make_report() {
    local task_id="$1"
    local unchecked="${2:-0}"  # 1이면 미완료 항목 포함
    local empty="${3:-0}"      # 1이면 빈 파일
    local dir="$REPORTS/$task_id"
    mkdir -p "$dir"
    if [ "$empty" -eq 1 ]; then
        : > "$dir/REPORT.md"
        return
    fi
    if [ "$unchecked" -eq 1 ]; then
        cat > "$dir/REPORT.md" <<'EOF'
# REPORT.md — 테스트

## 요약
테스트용 보고서

## AC 체크리스트
- [x] 완료 항목
- [ ] 미완료 항목
EOF
    else
        cat > "$dir/REPORT.md" <<'EOF'
# REPORT.md — 테스트

## 요약
테스트용 보고서

## AC 체크리스트
- [x] 완료 항목
EOF
    fi
}

cleanup() {
    # 테스트 픽스처 정리
    for tid in T-SIM01 T-SIM02 T-SIM03 T-SIM04 T-SIM05 T-SIM06 \
               T-SIM07 T-SIM07a T-SIM07b T-SIM08 T-SIM08b \
               T-SIM09a T-SIM09b T-SIM10 T-SIM11 T-SIM11b T-SIM12 T-SIM13; do
        rm -rf "$REPORTS/$tid" 2>/dev/null || true
    done
    # 테스트용 격리 에이전트(testcli) 관련 파일
    rm -f "$REPORTS/.daemon_testcli" 2>/dev/null || true
    rm -f "$REPORTS/.pending_testcli" 2>/dev/null || true
    rm -f "$REPORTS/.status_"*"_testcli" 2>/dev/null || true
    # 스코프 위반 테스트 잔재
    rm -f "$PROJECT_DIR/test-scope-violation.txt" 2>/dev/null || true
    # npm test 실패 테스트 잔재
    rm -f "$PROJECT_DIR/tests/failing_sim.test.js" 2>/dev/null || true
    # pty-bridge 테스트 임시 출력 파일
    rm -f "$REPORTS/.pty_test_01.txt" "$REPORTS/.pty_test_02.txt" 2>/dev/null || true
}

# 시작 전 정리
cleanup

echo "$SEP"
echo "cli-agent-team 실패 시나리오 테스트"
echo "프로젝트: $PROJECT_DIR"
echo "스킬:     $SKILL_DIR"
echo "$SEP"

# ── 사전 검사: git 작업 트리가 깨끗한지 확인 ─────────────────────────────
# verify.sh 스코프 검사(검사 1/4)가 `git diff HEAD` + `git ls-files --others`를
# 사용하므로, 테스트 전 repo가 깨끗해야 시뮬레이션 결과가 정확하다.
PRECHECK_DIRTY=$(cd "$PROJECT_DIR" && {
    git diff --name-only HEAD 2>/dev/null
    git diff --cached --name-only 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
} | grep -v "^_agent_reports/" || true)

if [ -n "$PRECHECK_DIRTY" ]; then
    echo ""
    echo "⚠️  경고: 프로젝트 디렉터리에 커밋되지 않은 변경 사항이 있습니다:"
    echo "$PRECHECK_DIRTY" | sed 's/^/    /'
    echo ""
    echo "  verify.sh 스코프 검사(SIM04~06)가 예기치 않은 파일을 감지할 수 있습니다."
    echo "  테스트는 계속하지만 결과 해석 시 주의하세요."
    echo ""
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. dispatch.sh — TASK.md 없음
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
run_test "SIM01" "fail" "dispatch.sh: TASK.md 없음 → exit 1" \
    bash "$DISPATCH" codex T-NOEXIST full "$PROJECT_DIR"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. verify.sh — REPORT.md 없음
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
make_task "T-SIM02" "routes/todos.js"
run_test "SIM02" "fail" "verify.sh: REPORT.md 없음 → exit 1" \
    bash "$VERIFY" T-SIM02 "$PROJECT_DIR"
rm -rf "$REPORTS/T-SIM02"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. verify.sh — REPORT.md 비어 있음
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
make_task "T-SIM03" "routes/todos.js"
make_report "T-SIM03" 0 1  # empty=1
run_test "SIM03" "fail" "verify.sh: REPORT.md 비어 있음 → exit 1" \
    bash "$VERIFY" T-SIM03 "$PROJECT_DIR"
rm -rf "$REPORTS/T-SIM03"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. verify.sh — AC 체크리스트 미완료 항목
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
make_task "T-SIM04" "routes/todos.js"
make_report "T-SIM04" 1 0  # unchecked=1
run_test "SIM04" "fail" "verify.sh: AC 체크리스트 미완료 항목 → exit 1" \
    bash "$VERIFY" T-SIM04 "$PROJECT_DIR"
rm -rf "$REPORTS/T-SIM04"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. verify.sh — 스코프 위반 (허용 외 파일 변경)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
make_task "T-SIM05" "routes/todos.js"
make_report "T-SIM05" 0 0
# 허용 외 신규 파일 생성 (untracked → git ls-files --others 로 감지)
echo "scope violation test" > "$PROJECT_DIR/test-scope-violation.txt"
run_test "SIM05" "fail" "verify.sh: 허용 외 파일 변경(스코프 위반) → exit 1" \
    bash "$VERIFY" T-SIM05 "$PROJECT_DIR"
rm -f "$PROJECT_DIR/test-scope-violation.txt"
rm -rf "$REPORTS/T-SIM05"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. verify.sh — npm test 실패 (의도적 실패 테스트)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
make_task "T-SIM06" "tests/failing_sim.test.js"
make_report "T-SIM06" 0 0
# 의도적으로 실패하는 Jest 테스트 생성 (untracked)
mkdir -p "$PROJECT_DIR/tests"
cat > "$PROJECT_DIR/tests/failing_sim.test.js" <<'EOF'
// 실패 시나리오 테스트 — verify.sh 검사 3/4 실패 유도
test('의도적 실패', () => {
  expect(1).toBe(2);
});
EOF
run_test "SIM06" "fail" "verify.sh: npm test 실패 → exit 1" \
    bash "$VERIFY" T-SIM06 "$PROJECT_DIR"
# check 3/4(npm test)가 실패 원인임을 단언 — exit code만으로는 check 1~4 중 어느 것인지 불명확
assert_output "❌ test 실패" "check 3/4 (npm test) 실패 라벨 확인"
rm -f "$PROJECT_DIR/tests/failing_sim.test.js"
rm -rf "$REPORTS/T-SIM06"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7. parallel-check.sh — 허용 파일 충돌 → 거부
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
make_task "T-SIM07a" "routes/todos.js"
make_task "T-SIM07b" "routes/todos.js"  # 동일 파일 → 충돌
run_test "SIM07" "fail" "parallel-check: 허용 파일 충돌(동일 파일) → exit 1" \
    bash "$PARALLEL" T-SIM07a T-SIM07b "$PROJECT_DIR"
rm -rf "$REPORTS/T-SIM07a" "$REPORTS/T-SIM07b"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 8. parallel-check.sh — 선행 태스크 미완료 → 거부
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
make_task "T-SIM08" "routes/new.js" "T-FAKEPRE"   # 선행: T-FAKEPRE (PLAN.md 완료 섹션에 없음)
make_task "T-SIM08b" "server.js"
run_test "SIM08" "fail" "parallel-check: 선행 태스크 미완료(T-FAKEPRE) → exit 1" \
    bash "$PARALLEL" T-SIM08 T-SIM08b "$PROJECT_DIR"
rm -rf "$REPORTS/T-SIM08" "$REPORTS/T-SIM08b"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 9. parallel-check.sh — 선행 있음 + 모두 완료 → 통과
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
make_task "T-SIM09a" "routes/new.js" "T001"   # T001은 PLAN.md 완료 섹션에 있음
make_task "T-SIM09b" "server.js"
run_test "SIM09" "pass" "parallel-check: 선행 완료(T001) + 파일 다름 → exit 0" \
    bash "$PARALLEL" T-SIM09a T-SIM09b "$PROJECT_DIR"
rm -rf "$REPORTS/T-SIM09a" "$REPORTS/T-SIM09b"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 10. trigger.sh — 데몬 마커 없음 → 즉시 실패
# (격리: testcli 에이전트 이름 사용 → 실제 codex/agy 데몬 간섭 없음)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# .daemon_testcli 가 없는 상태에서 trigger.sh 실행 → 즉시 exit 1
rm -f "$REPORTS/.daemon_testcli"
run_test "SIM10" "fail" "trigger.sh: 데몬 마커 없음(testcli) → 즉시 exit 1" \
    bash "$TRIGGER" testcli T-SIM10 execute "$PROJECT_DIR"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 11. trigger.sh — 데몬 마커 있음, 수신 안 됨 (PICKUP_TIMEOUT=5)
# (격리: testcli 에이전트 이름 사용 → 실제 데몬이 .pending_testcli 를 픽업하지 않음)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "RUNNING" > "$REPORTS/.daemon_testcli"
make_task "T-SIM11" "routes/new.js"
echo "  (5초 대기 중 — PICKUP_TIMEOUT=5 testcli 테스트)"
run_test "SIM11" "fail" "trigger.sh: 데몬 마커 있음 + 수신 안 됨(testcli, 5s) → exit 1" \
    env PICKUP_TIMEOUT=5 bash "$TRIGGER" testcli T-SIM11 execute "$PROJECT_DIR"
rm -f "$REPORTS/.daemon_testcli"
rm -f "$REPORTS/.pending_testcli"
rm -rf "$REPORTS/T-SIM11"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 11b. trigger.sh — 전체 작업 타임아웃 (TASK_TIMEOUT=10)
# 수신은 됐지만 완료 신호가 오지 않는 경우 → exit 3
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "RUNNING" > "$REPORTS/.daemon_testcli"
make_task "T-SIM11b" "routes/new.js"
echo "  (10초 대기 중 — TASK_TIMEOUT=10 testcli 테스트)"
echo "  (배경 프로세스가 5초 후 .pending_testcli 제거해 픽업 시뮬레이션)"
# 배경 프로세스: 5초 후 pending 파일 삭제 (데몬 픽업 시뮬레이션)
(sleep 5 && rm -f "$REPORTS/.pending_testcli") &
BG_PID=$!
TOTAL=$((TOTAL + 1))
set +e
PICKUP_TIMEOUT=30 TASK_TIMEOUT=10 bash "$TRIGGER" testcli T-SIM11b execute "$PROJECT_DIR" 2>&1
SIM11b_EXIT=$?
set -e
kill "$BG_PID" 2>/dev/null || true
if [ "$SIM11b_EXIT" -eq 3 ]; then
    echo "  ✅ PASS (exit 3 — TASK_TIMEOUT 정상 동작)"
    PASS=$((PASS + 1))
else
    echo "  ❌ FAIL (기대: exit 3, 실제: exit $SIM11b_EXIT)"
    FAIL=$((FAIL + 1))
fi
rm -f "$REPORTS/.daemon_testcli"
rm -rf "$REPORTS/T-SIM11b"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 12. reset-task.sh — ERROR 상태 초기화
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "ERROR" > "$REPORTS/.status_T-SIM12_codex"
run_test "SIM12" "pass" "reset-task.sh: ERROR 상태 파일 삭제 → exit 0" \
    bash "$RESET" T-SIM12 codex "$PROJECT_DIR"
# 파일이 실제로 삭제됐는지 확인
if [ -f "$REPORTS/.status_T-SIM12_codex" ]; then
    echo "  ❌ 상태 파일이 남아 있음! (reset-task.sh 버그)"
    FAIL=$((FAIL + 1))
    PASS=$((PASS - 1))
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 13. [회복] ERROR 후 재트리거 → 자동 정상 완료
# trigger.sh는 실행 시 STATUS 파일을 자동 삭제하므로 reset-task.sh 없이 재시도 가능.
# 가짜 데몬(배경 프로세스)이 pickup → DONE 기록 → trigger.sh exit 0 확인.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "RUNNING" > "$REPORTS/.daemon_testcli"
echo "ERROR" > "$REPORTS/.status_T-SIM13_testcli"
make_task "T-SIM13" "routes/new.js"
echo "  (SIM13: 가짜 데몬이 pickup 감지 후 DONE 기록 — 회복 루프 검증)"
# 가짜 데몬: .pending_testcli 감지 → 제거(픽업 시뮬) → 2초 후 DONE 기록
(
  COUNT=0
  while [ "$COUNT" -lt 20 ]; do
    if [ -f "$REPORTS/.pending_testcli" ]; then
      rm -f "$REPORTS/.pending_testcli"
      sleep 2
      echo "DONE" > "$REPORTS/.status_T-SIM13_testcli"
      exit 0
    fi
    sleep 1
    COUNT=$((COUNT + 1))
  done
) &
SIM13_BG_PID=$!

run_test "SIM13" "pass" "[회복] ERROR 상태 후 재트리거 → 가짜 데몬이 DONE 기록 → exit 0" \
    env PICKUP_TIMEOUT=15 bash "$TRIGGER" testcli T-SIM13 execute "$PROJECT_DIR"

kill "$SIM13_BG_PID" 2>/dev/null || true
rm -f "$REPORTS/.daemon_testcli"
rm -rf "$REPORTS/T-SIM13"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# TC-MODEL-01: 잘못된 MODEL_TIER 값 거부
# dispatch.sh 6번째 인자로 유효하지 않은 값 → exit 1, stderr에 "unknown model-tier"
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
run_test "MODEL01" "fail" "dispatch.sh: 잘못된 MODEL_TIER(invalid_tier) → exit 1" \
    bash "$DISPATCH" codex T_DUMMY limited "$PROJECT_DIR" execute invalid_tier
assert_output "unknown model-tier" "stderr에 'unknown model-tier' 포함 확인"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# TC-MODEL-02: fast 티어 전달 시 오류 없이 파싱
# MODEL_TIER=fast → 파싱 성공, 이후 TASK.md 없음으로 exit 1
# stderr에 "unknown model-tier"가 없어야 파싱 성공으로 간주
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
run_test "MODEL02" "fail" "dispatch.sh: fast 티어 파싱 성공 → TASK.md not found로 exit 1" \
    bash "$DISPATCH" codex NONEXISTENT limited "$PROJECT_DIR" execute fast
assert_output "TASK.md" "exit 원인이 TASK.md not found임 확인 (model-tier 오류 아님)"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# TC-MODEL-03: quality 티어 기본값 (6번째 인자 생략)
# MODEL_TIER 생략 시 기본값 quality 사용 → TASK.md 없음으로 exit 1
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
run_test "MODEL03" "fail" "dispatch.sh: MODEL_TIER 기본값(quality) — 6번째 인자 생략 → TASK.md not found" \
    bash "$DISPATCH" codex NONEXISTENT limited "$PROJECT_DIR" execute
assert_output "TASK.md" "exit 원인이 TASK.md not found임 확인 (기본값 적용됨)"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# TC-MODEL-04: trigger.sh MODEL_TIER 5번째 파라미터 파싱
# 데몬 없는 환경에서 trigger.sh 호출 → 즉시 "데몬" 오류로 exit 1
# model-tier는 .pending 작성 전에 파싱되므로 오류 메시지만 확인
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
rm -f "$REPORTS/.daemon_testcli"
run_test "MODEL04" "fail" "trigger.sh: 5번째 파라미터(fast) 전달 + 데몬 없음 → '데몬' 오류 exit 1" \
    bash "$TRIGGER" testcli T_DUMMY execute "$PROJECT_DIR" fast
assert_output "데몬" "stderr에 '데몬' 포함 확인"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# TC-PTY-01: pty-bridge — 존재하지 않는 CLI 실행 → exit non-zero
# TC-PTY-02: pty-bridge — 타임아웃(100ms) 후 finish(1) → exit 1
# node-pty 미설치 환경에서는 SKIP (TOTAL에 포함하지 않음)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PTY_BRIDGE_DIR="$(cd "$(dirname "$DISPATCH")/../../../mcp-servers/pty-bridge" 2>/dev/null && pwd || echo "")"
PTY_BRIDGE_SCRIPT="${PTY_BRIDGE_DIR}/run.js"
PTY_OUT_01="$REPORTS/.pty_test_01.txt"
PTY_OUT_02="$REPORTS/.pty_test_02.txt"

if [ -f "$PTY_BRIDGE_SCRIPT" ] && [ -d "${PTY_BRIDGE_DIR}/node_modules/node-pty" ]; then
    run_test "PTY01" "fail" "pty-bridge: 존재하지 않는 CLI(pty_nonexistent_xyz) → exit non-zero" \
        node "$PTY_BRIDGE_SCRIPT" pty_nonexistent_xyz "$PTY_OUT_01" 5000

    run_test "PTY02" "fail" "pty-bridge: 100ms 타임아웃(node 무한루프) → exit 1" \
        node "$PTY_BRIDGE_SCRIPT" node "$PTY_OUT_02" 100 -- -e "setInterval(()=>{},99999)"
    assert_output "pty-bridge.*timeout" "stderr에 '[pty-bridge] timeout' 메시지 확인"

    rm -f "$PTY_OUT_01" "$PTY_OUT_02"
else
    echo ""
    echo "⏭  PTY01 / PTY02 SKIP — node-pty 미설치 (TOTAL 미포함)"
    echo "   해결: cd mcp-servers/pty-bridge && npm install"
fi

# ── 최종 결과 ─────────────────────────────────────────────────────────
echo ""
echo "$SEP"
echo "테스트 결과: $PASS 통과 / $FAIL 실패 / $TOTAL 총"
echo "$SEP"
echo ""

cleanup

# 테스트 후 git 상태 확인 (오염물 탐지)
POSTCHECK_DIRTY=$(cd "$PROJECT_DIR" && {
    git diff --name-only HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
} | grep -v "^_agent_reports/" || true)

if [ -n "$POSTCHECK_DIRTY" ]; then
    echo "⚠️  테스트 후 잔재 파일 감지 — 테스트가 파일을 정리하지 못했습니다:"
    echo "$POSTCHECK_DIRTY" | sed 's/^/    /'
    echo "  수동으로 삭제하거나 git checkout 하세요."
fi

[ "$FAIL" -eq 0 ] && exit 0 || exit 1

