#!/usr/bin/env bash
# setup.sh [project-dir] [skill-dir]
#
# 신규 프로젝트에 cli-agent-team 기본 구조를 빠르게 초기화한다.
# Phase 3에서 파일을 하나하나 수동으로 만드는 대신 이 스크립트를 먼저 실행한다.
# 생성 후 <...> 플레이스홀더만 채우면 루프를 시작할 수 있다.
#
# 생성 파일 (이미 있으면 덮어쓰지 않음):
#   _agent_reports/.session_state  루프 상태 파일
#   _agent_reports/LOG.md          전체 이벤트 로그 (시간대 통계 포함)
#   PLAN.md                        작업 보드
#   AGENT_ROLES.md                 역할·권한·라우팅 정의
#   .gitignore                     _agent_reports/ 항목 추가
#
# 사용법:
#   bash ~/.claude/skills/cli-agent-team/scripts/setup.sh
#   bash ~/.claude/skills/cli-agent-team/scripts/setup.sh /path/to/project

set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
SKILL_DIR="${2:-$(cd "$(dirname "$0")/.." && pwd)}"

echo ""
echo "[setup] cli-agent-team 초기화"
echo "[setup] 프로젝트: $PROJECT_DIR"
echo ""

mkdir -p "$PROJECT_DIR/_agent_reports"

# ── .session_state ────────────────────────────────────────────────────
STATE_FILE="$PROJECT_DIR/_agent_reports/.session_state"
if [ ! -f "$STATE_FILE" ]; then
    cat > "$STATE_FILE" << 'EOF'
갱신: YYYY-MM-DD HH:MM (Asia/Seoul)
마일스톤: M1 — <마일스톤 이름>
다음 행동: <task-id> 배정 (<agent> · <규모> · <한 줄 설명>)
루프 상태: 단계 1 대기
BLOCKED: (없음)
루프 모드: manual
리셋 주기: 0
루프 프롬프트: cli-agent-team
EOF
    echo "[setup] ✅ 생성: _agent_reports/.session_state"
else
    echo "[setup] ⏭️  유지: _agent_reports/.session_state (이미 있음)"
fi

# ── LOG.md ────────────────────────────────────────────────────────────
LOG_FILE="$PROJECT_DIR/_agent_reports/LOG.md"
if [ ! -f "$LOG_FILE" ]; then
    cat > "$LOG_FILE" << 'EOF'
# LOG.md — 이벤트 로그

## 현재 배정 창 (window)

| 에이전트 | window | 현재 세션 작업 수 | 연속 성공 세션 |
|---------|--------|-----------------|--------------|
| codex   | 3      | 0               | 0            |
| agy     | 3      | 0               | 0            |

## 시간대별 리밋 빈도

<!-- log-event.sh가 ⚠️ 리밋 이벤트 발생 시 [HOUR:XX] 태그를 자동 기록한다.
     패턴 분석: bash scripts/analyze-limits.sh
     특정 시간대에 리밋이 잦으면 그 시간대는 해당 에이전트 우선순위를 한 단계 낮춘다. -->

| 시간대 | codex 리밋 | agy 리밋 | 메모 |
|--------|----------|---------|------|
| 00-06  | 0        | 0       |      |
| 06-09  | 0        | 0       |      |
| 09-12  | 0        | 0       |      |
| 12-15  | 0        | 0       |      |
| 15-18  | 0        | 0       |      |
| 18-21  | 0        | 0       |      |
| 21-24  | 0        | 0       |      |

## 이벤트 이력

| 시각 | task-id | 에이전트 | 규모 | 결과 | 세션 작업 수 | 메모 |
|------|---------|---------|------|------|------------|------|
EOF
    echo "[setup] ✅ 생성: _agent_reports/LOG.md"
else
    echo "[setup] ⏭️  유지: _agent_reports/LOG.md (이미 있음)"
fi

# ── PLAN.md ───────────────────────────────────────────────────────────
PLAN_FILE="$PROJECT_DIR/PLAN.md"
if [ ! -f "$PLAN_FILE" ]; then
    cat > "$PLAN_FILE" << 'EOF'
# PLAN.md — <프로젝트명> 작업 보드

> 루프 상태: `_agent_reports/.session_state` 참고.

## 진행 중
| ID | 작업 | 배정 | 상태 | 참고 |
|----|------|------|------|------|

## 대기 (우선순위 순)
| ID | 작업 | 선행 | 비고 |
|----|------|------|------|

## 완료 (최근)
| ID | 작업 | 커밋 | 비고 |
|----|------|------|------|

## BLOCKED
| ID | 작업 | 사유 |
|----|------|------|

## 보류 / 미정
| 항목 | 비고 |
|------|------|

## 마일스톤 구조
| ID | 마일스톤 | 태스크 | 자동 통과 가능 |
|----|---------|--------|--------------|
| M1 | <이름> | <T001, T002, ...> | 조건 충족 시 |
EOF
    echo "[setup] ✅ 생성: PLAN.md"
else
    echo "[setup] ⏭️  유지: PLAN.md (이미 있음)"
fi

# ── AGENT_ROLES.md ────────────────────────────────────────────────────
ROLES_FILE="$PROJECT_DIR/AGENT_ROLES.md"
if [ ! -f "$ROLES_FILE" ]; then
    cat > "$ROLES_FILE" << 'EOF'
# AGENT_ROLES.md — <프로젝트명> 에이전트 역할 정의

## 권한 수준

**수준**: <full | limited | read-only>
**사유**: <이유 — 예: 시스템 파일 접근 필요, 프로덕션 환경 아님>

## 병렬 실행

**허용 여부**: <허용 | 비허용>
<!-- 허용 시: 독립 태스크(선행 없음 + 허용 파일 비겹침)에 한해 codex+agy 동시 배정 가능 -->

## 작업 라우팅 테이블

| 작업 유형 | 1순위 | 폴백 1 | 폴백 2 |
|---------|-------|-------|-------|
| 소형 구현 (1~20줄) | codex | agy | Claude (최후) |
| 중형 구현 (20~200줄) | codex | agy | Claude (최후) |
| 대형 구현 / 분석 (200줄↑) | agy | codex | Claude (최후) |
| 코드 리뷰·검토 | Claude | — | — |
| 커밋/PR | Claude (항상) | — | — |

## 도메인별 역할 분담

<이 프로젝트 고유의 에이전트별 담당 영역>

## 자동 검증 명령어

<!-- verify.sh가 이 명령어들을 실행해 통과 여부를 확인한다 -->
<!-- lint: npm run lint -->
<!-- test: npm test -->
<!-- build: npm run build -->

## 마일스톤 게이트 정책

- 구조적 결정 게이트: 항상 사용자 확인 (새 의존성·스키마·OAuth 등)
- 완료 개수 게이트: 마일스톤 단위 (기본, 조정 가능)

## 보안 규칙 (변경 불가)

- 권한 수준은 이 문서에서 정한 것을 따른다 — 임의 승격 금지
- 에이전트는 절대 커밋하지 않는다
- .env / 토큰 / 시크릿 파일을 읽거나 출력하지 않는다
EOF
    echo "[setup] ✅ 생성: AGENT_ROLES.md"
else
    echo "[setup] ⏭️  유지: AGENT_ROLES.md (이미 있음)"
fi

# ── .gitignore ────────────────────────────────────────────────────────
GITIGNORE_FILE="$PROJECT_DIR/.gitignore"
if ! grep -q "_agent_reports/" "$GITIGNORE_FILE" 2>/dev/null; then
    printf "\n# cli-agent-team 작업 로그 (감사 추적 원하면 이 줄 삭제)\n_agent_reports/\n" >> "$GITIGNORE_FILE"
    echo "[setup] ✅ .gitignore에 _agent_reports/ 추가"
else
    echo "[setup] ⏭️  .gitignore: _agent_reports/ 이미 있음"
fi

echo ""
echo "[setup] 완료. 다음 단계:"
echo "  1. PLAN.md: 프로젝트명·마일스톤·태스크 목록 채우기"
echo "  2. AGENT_ROLES.md: 권한 수준·도메인 분담·자동 검증 명령어 채우기"
echo "  3. _agent_reports/.session_state: 마일스톤 이름·루프 모드 설정"
echo "  4. 데몬 시작:"
echo "     Windows: .\\scripts\\agent-watch.ps1 -Agent codex -AuthMode <수준>"
echo "     Linux/macOS: bash scripts/agent-watch.sh codex <수준>"
echo ""
