#!/usr/bin/env bash
# init.sh — cli-agent-team 대화형 초기화 스크립트
#
# 사용법:
#   bash skills/cli-agent-team/scripts/init.sh
#   bash skills/cli-agent-team/scripts/init.sh /abs/path/to/project
#
# 동작:
#   1. 대화형 질문으로 프로젝트 정보 수집
#   2. PLAN.md 및 AGENT_ROLES.md 자동 생성
#   3. _agent_reports/ 디렉토리 생성
#   4. .gitignore에 _agent_reports/ 항목 추가
#   5. setup.sh 호출하여 에이전트 감지 및 conf 생성

# ── 디렉토리 설정 ─────────────────────────────────────────────────────────────
# 인수가 있으면 해당 경로, 없으면 현재 디렉토리
if [ -n "${1:-}" ]; then
  PROJECT_DIR="$1"
else
  PROJECT_DIR="$(pwd)"
fi

# init.sh 자체가 있는 스크립트 디렉토리 (setup.sh 호출용)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SEP="================================================================"

echo ""
echo "=== cli-agent-team init ==="
echo ""

# ── [1/4] 프로젝트 이름 ───────────────────────────────────────────────────────
read -p "[1/4] 프로젝트 이름을 입력하세요 (예: my-app): " PROJECT_NAME
if [ -z "$PROJECT_NAME" ]; then
  echo "[init] 오류: 프로젝트 이름은 비워둘 수 없습니다." >&2
  exit 1
fi

echo ""

# ── [2/4] 프로젝트 유형 ───────────────────────────────────────────────────────
echo "[2/4] 프로젝트 유형을 선택하세요:"
echo "  1) 웹앱 (프론트엔드/백엔드/풀스택)"
echo "  2) CLI 도구 / 스크립트 / 자동화"
echo "  3) 봇 (Discord, Telegram, Slack 등)"
echo "  4) 라이브러리 / SDK / 패키지"
echo "  5) 기타"
read -p "선택 (1-5): " TYPE_NUM

case "$TYPE_NUM" in
  1) PROJECT_TYPE="웹앱 (프론트엔드/백엔드/풀스택)" ;;
  2) PROJECT_TYPE="CLI 도구 / 스크립트 / 자동화" ;;
  3) PROJECT_TYPE="봇 (Discord, Telegram, Slack 등)" ;;
  4) PROJECT_TYPE="라이브러리 / SDK / 패키지" ;;
  5) PROJECT_TYPE="기타" ;;
  *)
    echo "[init] 오류: 올바른 번호(1-5)를 선택하세요." >&2
    exit 1
    ;;
esac

echo ""

# ── [3/4] 기술 스택 ───────────────────────────────────────────────────────────
read -p "[3/4] 기술 스택 또는 주요 언어를 입력하세요 (예: TypeScript, Python, Go): " TECH_STACK
if [ -z "$TECH_STACK" ]; then
  TECH_STACK="(미지정)"
fi

echo ""

# ── [4/4] 첫 번째 마일스톤 이름 ──────────────────────────────────────────────
read -p "[4/4] 첫 번째 마일스톤 이름을 입력하세요 (예: MVP, 기반 구축): " MILESTONE_NAME
if [ -z "$MILESTONE_NAME" ]; then
  MILESTONE_NAME="M1"
fi

echo ""

# ── 설정 확인 ─────────────────────────────────────────────────────────────────
echo "설정을 확인하세요:"
echo "  프로젝트: $PROJECT_NAME"
echo "  유형    : $PROJECT_TYPE"
echo "  스택    : $TECH_STACK"
echo "  M1      : $MILESTONE_NAME"
read -p "계속하시겠습니까? (Y/n): " CONFIRM

case "${CONFIRM:-Y}" in
  [nN]|[nN][oO])
    echo "[init] 취소되었습니다."
    exit 0
    ;;
esac

echo ""

# ── 날짜 ─────────────────────────────────────────────────────────────────────
TODAY=$(date +%Y-%m-%d)

# ── PLAN.md 생성 ──────────────────────────────────────────────────────────────
PLAN_FILE="$PROJECT_DIR/PLAN.md"
SKIP_PLAN=false

if [ -f "$PLAN_FILE" ]; then
  read -p "PLAN.md가 이미 존재합니다. 덮어씁니까? (y/N): " OVERWRITE
  if [ "${OVERWRITE:-N}" != "y" ] && [ "${OVERWRITE:-N}" != "Y" ]; then
    echo "[init] PLAN.md 건너뜀"
    SKIP_PLAN=true
  fi
fi

if [ "$SKIP_PLAN" = false ]; then
  cat > "$PLAN_FILE" << PLAN_EOF
# PLAN.md — ${PROJECT_NAME}

마지막 업데이트: ${TODAY}

---

## 프로젝트 목표

${PROJECT_TYPE} 프로젝트. 기술 스택: ${TECH_STACK}.

---

## ${MILESTONE_NAME}

### 진행 대기

| ID | 설명 | 담당 | 규모 | 우선순위 |
|----|------|------|------|---------|
| T001 | 첫 번째 태스크 작성 | 미지정 | 소형 | P1 |

### 완료

(없음)

---

## 커밋 이력 (주요)

(없음)
PLAN_EOF
  echo "[init] PLAN.md 생성 완료: $PLAN_FILE"
fi

# ── AGENT_ROLES.md 생성 ───────────────────────────────────────────────────────
ROLES_FILE="$PROJECT_DIR/AGENT_ROLES.md"
SKIP_ROLES=false

if [ -f "$ROLES_FILE" ]; then
  read -p "AGENT_ROLES.md가 이미 존재합니다. 덮어씁니까? (y/N): " OVERWRITE_ROLES
  if [ "${OVERWRITE_ROLES:-N}" != "y" ] && [ "${OVERWRITE_ROLES:-N}" != "Y" ]; then
    echo "[init] AGENT_ROLES.md 건너뜀"
    SKIP_ROLES=true
  fi
fi

if [ "$SKIP_ROLES" = false ]; then
  cat > "$ROLES_FILE" << ROLES_EOF
# AGENT_ROLES.md — ${PROJECT_NAME}

## 이 프로젝트의 권한 수준

수준: 제한된 자율
사유: 스캐폴딩 기본값 — 권한 수준 상향 시 이 줄을 수정하고 사유를 기록할 것

## 역할 분담

| 에이전트 | 역할 |
|---------|-----|
| Claude | 오케스트레이터 (계획·검토·커밋) |
| Codex | 소~중형 구현 (1~200줄, 명세 명확한 작업) |
| agy | 대형 구현·분석 (200줄↑, 탐색 작업) |

## 작업 라우팅

| 작업 유형 | 1순위 | 폴백 |
|---------|------|-----|
| 소형 구현 (1~20줄) | Codex | agy |
| 중형 구현 (20~200줄) | Codex | agy |
| 대형 구현·분석 | agy | Codex |
| 코드 리뷰·커밋 | Claude | — |

## 병렬 실행

Codex + agy 병렬: 허용
같은 에이전트 병렬: 금지

## 자동 검증 명령어

<!-- 프로젝트별로 아래를 채워주세요 -->
syntax-check: (없음 — 채워주세요)

## 마일스톤 게이트

- 구조적 결정 (새 의존성·스키마 변경·OAuth): 항상 사용자 확인
- 완료 작업 3개마다 게이트 발동
ROLES_EOF
  echo "[init] AGENT_ROLES.md 생성 완료: $ROLES_FILE"
fi

# ── AGENTS.md 생성 — Codex/agy/Claude 공통 읽기용 ─────────────────────────────
AGENTS_FILE="$PROJECT_DIR/AGENTS.md"
if [ ! -f "$AGENTS_FILE" ]; then
  # 주의: << 'AGENTS_EOF' (quoted) — 본문 셸 치환 방지
  PROJECT_NAME_VAL="$PROJECT_NAME"
  cat > "$AGENTS_FILE" << 'AGENTS_EOF'
# AGENTS.md — 프로젝트 에이전트 공통 지침
# Claude Code, Codex, agy 가 프로젝트 시작 시 자동으로 읽습니다.

## 역할

| 에이전트 | 역할 | 작업 범위 |
|---------|-----|---------|
| Claude  | 오케스트레이터 (계획·검토·커밋) | 코드 직접 작성 금지 |
| Codex   | 소~중형 구현 | 1~200줄, 명세 명확한 작업 |
| agy     | 대형 구현·탐색 | 200줄↑, 분석·탐색 작업 |

## 검증 규칙

- 스크립트 문법 확인: `bash -n <파일>` 만 사용 (직접 실행 금지)
- 소스 코드 변경: TASK.md `## 허용 파일` 목록만
- 완료 후 반드시: `_agent_reports/<task-id>/REPORT.md` 작성
- REPORT.md 내 `## AC 체크리스트` 섹션 필수

## 보안 규칙

- API 키·토큰·패스워드 하드코딩 금지
- `rm -rf` / `git reset --hard` 사용 전 확인
- `eval $()` 패턴 금지
- `chmod 777` 금지
AGENTS_EOF
  # PROJECT_NAME은 heredoc 밖에서 치환
  PROJECT_NAME_SED=$(printf '%s' "$PROJECT_NAME_VAL" | sed 's/[&|\\]/\\&/g')
  sed -i "s|^# AGENTS.md — 프로젝트 에이전트 공통 지침|# AGENTS.md — ${PROJECT_NAME_SED}|" "$AGENTS_FILE" 2>/dev/null || true
  echo "[init] AGENTS.md 생성 완료: $AGENTS_FILE"
fi

# ── _agent_reports/ 디렉토리 생성 ─────────────────────────────────────────────
REPORTS_DIR="$PROJECT_DIR/_agent_reports"
mkdir -p "$REPORTS_DIR"
echo "[init] _agent_reports/ 디렉토리 확인: $REPORTS_DIR"

# ── .gitignore에 _agent_reports/ 항목 추가 ────────────────────────────────────
GITIGNORE_FILE="$PROJECT_DIR/.gitignore"
if [ -f "$GITIGNORE_FILE" ]; then
  if grep -qF "_agent_reports/" "$GITIGNORE_FILE"; then
    echo "[init] .gitignore: _agent_reports/ 이미 존재, 건너뜀"
  else
    printf "\n# cli-agent-team\n_agent_reports/\n" >> "$GITIGNORE_FILE"
    echo "[init] .gitignore에 _agent_reports/ 추가 완료"
  fi
else
  printf "# cli-agent-team\n_agent_reports/\n" > "$GITIGNORE_FILE"
  echo "[init] .gitignore 생성 및 _agent_reports/ 추가 완료"
fi

# ── setup.sh 호출 ─────────────────────────────────────────────────────────────
SETUP_SH="$SCRIPT_DIR/setup.sh"
echo ""
echo "$SEP"
echo "[init] setup.sh 호출 중..."
echo "$SEP"

# setup.sh는 PROJECT_DIR를 기준으로 실행해야 conf 파일 경로가 올바름
if [ -f "$SETUP_SH" ]; then
  (cd "$PROJECT_DIR" && bash "$SETUP_SH")
else
  echo "[init] 경고: setup.sh를 찾을 수 없습니다: $SETUP_SH" >&2
  echo "[init] 수동으로 'bash setup.sh'를 실행하세요." >&2
fi

echo ""
echo "$SEP"
echo "[init] 완료!"
echo "  프로젝트: $PROJECT_NAME"
echo "  위치    : $PROJECT_DIR"
echo ""
echo "다음 단계:"
echo "  1. PLAN.md에서 태스크 목록을 채워주세요"
echo "  2. AGENT_ROLES.md에서 권한 수준을 확인하세요"
echo "  3. bash scripts/agent-watch.sh 로 모니터를 시작하세요"
echo "$SEP"
