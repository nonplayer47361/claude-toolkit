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

# TASK_ID 형식 검증 (영숫자·하이픈·언더스코어만 허용)
if ! echo "$TASK_ID" | grep -qE '^[A-Za-z0-9_-]+$'; then
  echo "ERROR: TASK_ID 형식 오류 — 영숫자·하이픈·언더스코어만 허용: '$TASK_ID'" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR="$PROJECT_DIR/_agent_reports/$TASK_ID"
WORKTREE_ROOT="$PROJECT_DIR/_worktrees"
WORKTREE_DIR="$WORKTREE_ROOT/$TASK_ID"
BRANCH="worktree/$TASK_ID"

# cleanup 변수 — worktree 생성 후 설정됨 (생성 전은 빈 문자열로 안전)
WORKTREE_PATH=""
BRANCH_NAME=""

# 정리 함수 — EXIT/INT/TERM 시 자동 호출
_cleanup_worktree() {
  local exit_code=$?
  if [ -n "${WORKTREE_PATH:-}" ] && [ -d "$WORKTREE_PATH" ]; then
    echo "[worktree] 정리 중: $WORKTREE_PATH" >&2
    git -C "$PROJECT_DIR" worktree remove --force "$WORKTREE_PATH" 2>/dev/null || true
  fi
  if [ -n "${BRANCH_NAME:-}" ]; then
    git -C "$PROJECT_DIR" branch -D "$BRANCH_NAME" 2>/dev/null || true
  fi
  exit $exit_code
}
trap '_cleanup_worktree' EXIT INT TERM

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

# worktree 생성 완료 — trap이 정리 대상을 인식하도록 변수 설정
WORKTREE_PATH="$WORKTREE_DIR"
BRANCH_NAME="$BRANCH"

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

if [ "$DISPATCH_EXIT" -ne 0 ]; then
  echo "[worktree] dispatch 실패 (exit $DISPATCH_EXIT) - 메인 트리 복사 중단" >&2
  exit "$DISPATCH_EXIT"
fi

# ── 산출물 복사 (REPORT/REVIEW/TODO) ──────────────────────────────────
echo "[worktree] 산출물 복사 → $TASK_DIR" >&2
for f in REPORT.md REVIEW.md TODO.md _agy_stdout.log _codex_stdout.log _codex_fallback.log; do
  src="$WORKTREE_TASK_DIR/$f"
  [ -f "$src" ] && cp "$src" "$TASK_DIR/" && echo "  복사: $f" >&2
done

# ── 소스 변경 파일 반영 ────────────────────────────────────────────────
echo "[worktree] 소스 변경 파일 적용 → $PROJECT_DIR" >&2
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete \
    --exclude='/.git' \
    --exclude='/_agent_reports/' \
    --exclude='/_worktrees/' \
    --exclude='/.env' \
    --exclude='/.env.*' \
    "$WORKTREE_DIR/" "$PROJECT_DIR/"
else
  echo "[worktree] 경고: rsync 없음 — 삭제된 파일은 메인 트리에 반영되지 않음" >&2
  (
    shopt -s dotglob nullglob
    for src in "$WORKTREE_DIR"/*; do
      name="$(basename "$src")"
      case "$name" in
        .git|_agent_reports|_worktrees|.env|.env.*) continue ;;
      esac
      cp -r "$src" "$PROJECT_DIR/"
    done
  )
fi

# ── worktree 정리 ──────────────────────────────────────────────────────
echo "[worktree] 정리: $WORKTREE_DIR" >&2
git -C "$PROJECT_DIR" worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
git -C "$PROJECT_DIR" branch -D "$BRANCH" 2>/dev/null || true

echo "[worktree] 완료 (dispatch exit: $DISPATCH_EXIT)" >&2
exit "$DISPATCH_EXIT"
