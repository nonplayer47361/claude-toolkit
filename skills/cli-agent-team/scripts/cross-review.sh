#!/usr/bin/env bash
set -euo pipefail

# cross-review.sh — 두 에이전트(agy + codex)가 동일 태스크를 독립 리뷰 후 FINAL_DECISION.md 생성
#
# 사용법:
#   bash skills/cli-agent-team/scripts/cross-review.sh <task-id> [project-dir]

TASK_ID="${1:?사용법: cross-review.sh <task-id> [project-dir]}"
PROJECT_DIR="${2:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR="$PROJECT_DIR/_agent_reports/$TASK_ID"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

if [ ! -f "$TASK_DIR/TASK.md" ]; then
  echo "[cross-review] 오류: $TASK_DIR/TASK.md 없음" >&2
  exit 1
fi

echo "[cross-review] $TASK_ID — 크로스 리뷰 시작 ($TIMESTAMP)"

# ── agy 리뷰 ─────────────────────────────────────────────────────────────────
echo "[cross-review] agy 리뷰 시작..."
if bash "$SCRIPT_DIR/dispatch.sh" agy "$TASK_ID" full "$PROJECT_DIR" review; then
  if [ -f "$TASK_DIR/REVIEW.md" ]; then
    cp "$TASK_DIR/REVIEW.md" "$TASK_DIR/REVIEW_agy.md"
    echo "[cross-review] ✅ agy REVIEW_agy.md 저장"
  else
    echo "[cross-review] ⚠ agy REVIEW.md 미생성 — REVIEW_agy.md 없음"
  fi
else
  echo "[cross-review] ⚠ agy dispatch 실패 (exit $?) — 계속 진행"
fi

# ── codex 리뷰 ───────────────────────────────────────────────────────────────
echo "[cross-review] codex 리뷰 시작..."
if bash "$SCRIPT_DIR/dispatch.sh" codex "$TASK_ID" full "$PROJECT_DIR" review; then
  if [ -f "$TASK_DIR/REVIEW.md" ]; then
    cp "$TASK_DIR/REVIEW.md" "$TASK_DIR/REVIEW_codex.md"
    echo "[cross-review] ✅ codex REVIEW_codex.md 저장"
  else
    echo "[cross-review] ⚠ codex REVIEW.md 미생성 — REVIEW_codex.md 없음"
  fi
else
  echo "[cross-review] ⚠ codex dispatch 실패 (exit $?) — 계속 진행"
fi

# 두 리뷰가 모두 없으면 의미가 없음
if [ ! -f "$TASK_DIR/REVIEW_agy.md" ] && [ ! -f "$TASK_DIR/REVIEW_codex.md" ]; then
  echo "[cross-review] 오류: agy·codex 리뷰 모두 생성 실패" >&2
  exit 1
fi

# ── FINAL_DECISION.md 생성 ───────────────────────────────────────────────────
AGY_CONTENT="(리뷰 없음)"
CODEX_CONTENT="(리뷰 없음)"
[ -f "$TASK_DIR/REVIEW_agy.md" ]   && AGY_CONTENT=$(cat "$TASK_DIR/REVIEW_agy.md")
[ -f "$TASK_DIR/REVIEW_codex.md" ] && CODEX_CONTENT=$(cat "$TASK_DIR/REVIEW_codex.md")

cat > "$TASK_DIR/FINAL_DECISION.md" << FINAL_EOF
# FINAL_DECISION — ${TASK_ID}

생성: ${TIMESTAMP}

## agy 리뷰

${AGY_CONTENT}

---

## codex 리뷰

${CODEX_CONTENT}

---

## 통합 판단

<!-- Claude가 위 두 리뷰를 읽고 아래를 채울 것 -->
- 공통 우려: (TODO)
- agy만 지적: (TODO)
- codex만 지적: (TODO)

결론: (PROCEED / REVISE)
사유: (TODO)
FINAL_EOF

echo "[cross-review] ✅ FINAL_DECISION.md 생성: $TASK_DIR/FINAL_DECISION.md"
echo "[cross-review] 완료."
