#!/usr/bin/env bash
# worktree-dispatch.sh <cli> <task-id> <auth-mode> [project-dir] [mode] [model-tier]
#
# dispatch.sh 래퍼 — git worktree에서 에이전트를 격리 실행한다.
# 병렬 실행 시 에이전트 간 파일 시스템 충돌 방지.
#
# 동작:
#   1. _worktrees/<task-id>/ 에 git worktree 생성 (브랜치: worktree/<task-id>)
#   2. TASK.md 를 worktree에 복사
#   3. dispatch.sh 를 worktree 디렉토리 기준으로 실행
#   4. REPORT.md / REVIEW.md / TODO.md 를 원래 _agent_reports/<task-id>/ 로 복사
#   5. 에이전트가 변경한 소스 파일을 메인 프로젝트로 반영
#   6. worktree + 임시 브랜치 정리
#
# 사용법:
#   bash scripts/worktree-dispatch.sh codex T001 full . execute
#   bash scripts/worktree-dispatch.sh agy   T002 full . review

set -euo pipefail

CLI="${1:?cli 필요 (codex|agy|auto)}"
TASK_ID="${2:?task-id 필요}"
AUTH_MODE="${3:?auth-mode 필요 (full|limited)}"
PROJECT_DIR="${4:-$(pwd)}"
MODE="${5:-execute}"
MODEL_TIER="${6:-quality}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR="$PROJECT_DIR/_agent_reports/$TASK_ID"
WORKTREE_ROOT="$PROJECT_DIR/_worktrees"
WORKTREE_DIR="$WORKTREE_ROOT/$TASK_ID"
BRANCH="worktree/$TASK_ID"

# ── 사전 조건 ──────────────────────────────────────────────────────────
if [ ! -f "$TASK_DIR/TASK.md" ]; then
  echo "ERROR: TASK.md 없음: $TASK_DIR/TASK.md" >&2
  exit 1
fi

if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: git repository 아님: $PROJECT_DIR" >&2
  exit 1
fi

# uncommitted changes 확인 — worktree 생성 전 main이 clean해야 함
if ! git -C "$PROJECT_DIR" diff --quiet HEAD 2>/dev/null; then
  echo "[worktree] ⚠ uncommitted changes 감지 — 일반 dispatch.sh로 폴백" >&2
  exec bash "$SCRIPT_DIR/dispatch.sh" "$CLI" "$TASK_ID" "$AUTH_MODE" "$PROJECT_DIR" "$MODE" "$MODEL_TIER"
fi

# ── 기존 worktree 정리 ─────────────────────────────────────────────────
if [ -d "$WORKTREE_DIR" ]; then
  echo "[worktree] 기존 worktree 발견, 제거: $WORKTREE_DIR" >&2
  git -C "$PROJECT_DIR" worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
  git -C "$PROJECT_DIR" branch -D "$BRANCH" 2>/dev/null || true
fi

# ── worktree 생성 ──────────────────────────────────────────────────────
mkdir -p "$WORKTREE_ROOT"
echo "[worktree] 생성: $WORKTREE_DIR (브랜치: $BRANCH)" >&2
git -C "$PROJECT_DIR" worktree add "$WORKTREE_DIR" -b "$BRANCH" 2>&1

# _agent_reports/<task-id>/ 를 worktree에 복사 (TASK.md 포함)
WORKTREE_TASK_DIR="$WORKTREE_DIR/_agent_reports/$TASK_ID"
mkdir -p "$WORKTREE_TASK_DIR"
cp -r "$TASK_DIR/"* "$WORKTREE_TASK_DIR/" 2>/dev/null || true

# ── dispatch.sh 실행 (worktree 기준) ───────────────────────────────────
echo "[worktree] dispatch.sh 실행 (cwd: $WORKTREE_DIR)" >&2
DISPATCH_EXIT=0
bash "$SCRIPT_DIR/dispatch.sh" \
  "$CLI" "$TASK_ID" "$AUTH_MODE" "$WORKTREE_DIR" "$MODE" "$MODEL_TIER" \
  || DISPATCH_EXIT=$?

# ── 산출물 복사 (REPORT/REVIEW/TODO) ──────────────────────────────────
echo "[worktree] 산출물 복사 → $TASK_DIR" >&2
for f in REPORT.md REVIEW.md TODO.md _agy_stdout.log _codex_stdout.log _codex_fallback.log; do
  src="$WORKTREE_TASK_DIR/$f"
  [ -f "$src" ] && cp "$src" "$TASK_DIR/" && echo "  복사: $f" >&2
done

# ── 소스 변경 파일 반영 ────────────────────────────────────────────────
echo "[worktree] 소스 변경 파일 적용 → $PROJECT_DIR" >&2
CHANGED_IN_WORKTREE=$(
  git -C "$WORKTREE_DIR" diff --name-only HEAD 2>/dev/null || true
  git -C "$WORKTREE_DIR" diff --cached --name-only 2>/dev/null || true
  git -C "$WORKTREE_DIR" ls-files --others --exclude-standard 2>/dev/null || true
)

while IFS= read -r relpath; do
  [ -z "$relpath" ] && continue
  [[ "$relpath" == _agent_reports/* ]] && continue
  [[ "$relpath" == _worktrees/* ]] && continue
  src="$WORKTREE_DIR/$relpath"
  dst="$PROJECT_DIR/$relpath"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  소스 적용: $relpath" >&2
  fi
done <<< "$CHANGED_IN_WORKTREE"

# ── worktree 정리 ──────────────────────────────────────────────────────
echo "[worktree] 정리: $WORKTREE_DIR" >&2
git -C "$PROJECT_DIR" worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
git -C "$PROJECT_DIR" branch -D "$BRANCH" 2>/dev/null || true

echo "[worktree] 완료 (dispatch exit: $DISPATCH_EXIT)" >&2
exit "$DISPATCH_EXIT"
