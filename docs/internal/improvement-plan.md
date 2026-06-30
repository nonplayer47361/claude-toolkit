# claude-toolkit 종합 개선 계획

> 작성 기준: ChatGPT 피드백 + Gemini 피드백 + Claude 코드 직접 분석 (3종 통합)
> 작성일: 2026-06-28

---

## 0. 피드백 3종의 시각 차이

| 관점 | 주요 포커스 | 대표 지적 |
|------|------------|-----------|
| **ChatGPT** | 제품 방향성 + 기능 체계화 | "MVP 너무 크다. 단일 태스크 루프부터 안정화" |
| **Gemini** | 아키텍처 안정성 + 비용 최적화 | ".session_state 원자적 쓰기, 루핑 트랩, 모델 불일치" |
| **Claude (직접 분석)** | 코드 레벨 버그 + 설치 후 작동 여부 | "설치 후 agy 경로 깨짐, EXIT trap false positive, auto 모드 실제로 adaptive 아님" |

---

## 1. Claude가 코드에서 직접 발견한 문제 (신규)

두 AI가 못 짚은 실제 코드 버그와 설계 결함입니다.

### 1.1 설치 후 agy가 동작하지 않음 (고중증 버그)

**위치:** `dispatch.sh` 215~219번째 줄

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PTY_BRIDGE="${SCRIPT_DIR}/../../../mcp-servers/pty-bridge/run.js"
```

**문제:** 스킬을 `~/.claude/skills/cli-agent-team/`에 설치하면 이 경로는
`~/.claude/mcp-servers/pty-bridge/run.js`를 가리킴 — 존재하지 않는 경로.
`mcp-servers/`는 원본 repo에 있지, 설치 대상에 복사되지 않음.

**즉:** 스킬 설치 후 agy를 처음 사용하는 사람은 무조건 `ERROR: pty-bridge not found`를 만남.

**수정 방향:**
```bash
# 환경 변수로 외부화
PTY_BRIDGE="${PTY_BRIDGE_PATH:-${SCRIPT_DIR}/../../../mcp-servers/pty-bridge/run.js}"
```
또는 `setup.sh` 가 설치 시 pty-bridge도 함께 복사하거나, 경로를 `.cli-agent-team.conf`에 기록.

---

### 1.2 EXIT trap이 이전 실행의 성공을 현재 실패에 재사용함 (고중증 버그)

**위치:** `dispatch.sh` 30~38번째 줄

```bash
_on_exit() {
  local ec=$?
  [ "$ec" -eq 0 ] && return
  local report="${TASK_DIR:-}"/REPORT.md
  if [ -f "$report" ] && grep -q -- '- \[x\]' "$report" 2>/dev/null; then
    exit 0   # ← 여기가 문제
  fi
}
```

**문제:** `feedback` 모드에서 재실행 시, 이전 `execute` 실행이 남긴 REPORT.md에
`- [x]`가 있으면 현재 feedback 실행이 완전히 실패해도 exit 0으로 처리됨.
"실패를 성공으로 덮어씌우는" 정반대의 효과.

**수정 방향:** 타임스탬프 비교 — REPORT.md가 이번 dispatch 시작 이후에 수정됐을 때만 적용.
```bash
DISPATCH_START_TS=$(date +%s)
# ...
if [ -f "$report" ] && [ "$(stat -c %Y "$report" 2>/dev/null || echo 0)" -gt "$DISPATCH_START_TS" ]; then
  grep -q -- '- \[x\]' "$report" && exit 0
fi
```

---

### 1.3 `auto` 모드가 실제로 adaptive하지 않음 (중증 설계 결함)

**위치:** `dispatch.sh` 98~107번째 줄

```bash
if [ "$CLI" = "auto" ]; then
  if [ "${AGY_ENABLED:-true}" = "true" ] && [ -n "${AGY_BIN:-}" ]; then
    CLI="agy"       # ← 항상 agy 우선
  elif ...; then
    CLI="codex"
  fi
fi
```

**문제:** `.agent_scores.json`이 있고 task_type별 성공률 데이터가 쌓여 있어도,
`auto` 모드는 그걸 전혀 참조하지 않음. 항상 "agy가 있으면 agy".
SKILL.md에 설명된 "adaptive scoring"이 실제로 배정 결정에 연결되지 않음.

**수정 방향:**
```bash
# .agent_scores.json 읽어서 TASK_TYPE별 승률 비교 후 선택
TASK_TYPE=$(grep '^task_type:' "$TASK_FILE" | head -1 | cut -d: -f2 | tr -d ' ')
# agy_score vs codex_score 비교 후 CLI 결정
```

---

### 1.4 verify.sh 스코프 체크의 접두사 매칭 오류 (중증 버그)

**위치:** `verify.sh` 93~96번째 줄

```bash
if [[ "$changed_file" == "$allowed" ]] || \
   [[ "$changed_file" == "$allowed/"* ]] || \
   [[ "$changed_file" == "$allowed"* ]]; then   # ← 이 줄이 문제
```

세 번째 조건 `"$allowed"*`는 허용 파일이 `src/auth.ts`일 때
`src/auth.ts.bak`, `src/auth-test.ts`도 매칭시킴.
에이전트가 `.bak` 파일을 생성하거나 비슷한 이름 파일을 건드려도 통과.

**수정 방향:** 세 번째 조건 제거 또는 `.`으로 시작하는 확장자만 허용.

---

### 1.5 agy/codex 로그 처리 방식 불일치 (경증 버그)

**위치:** `dispatch.sh`

```bash
# codex: 덮어쓰기
run_cli_logged write run_with_timeout codex ...

# agy: 추가(append)
run_cli_logged append node "$PTY_BRIDGE" agy ...
```

`feedback` 모드에서 codex는 로그가 덮어쓰여서 이전 시도의 기록이 사라짐.
agy는 모든 시도가 누적되어 로그가 거대해짐.

**수정 방향:** 두 에이전트 모두 `append` 모드로 통일하되, 시도별 헤더(`--- 시도 2 ---`)를 삽입.

---

### 1.6 verify.sh의 eval 보안 위험 (경증)

**위치:** `verify.sh` 171번째 줄

```bash
if (cd "$PROJECT_DIR" && eval "$cmd" >"$TMPOUT" 2>&1); then
```

`AGENT_ROLES.md`가 외부 에이전트에 의해 수정될 수 있는 파일이라면,
악의적인 명령어가 삽입될 경우 `eval`이 실행함.

**수정 방향:** 허용 명령어 화이트리스트 또는 `bash -c "$cmd"` 대신 배열 기반 실행.

---

## 2. 3종 피드백 통합 우선순위

### P0 — 지금 당장 고쳐야 할 버그 (Claude 발견)

| # | 문제 | 파일 | 영향 |
|---|------|------|------|
| 1 | pty-bridge 경로 하드코딩 → 설치 후 agy 불능 | `dispatch.sh:215` | 신규 사용자 100% 차단 |
| 2 | EXIT trap false positive → 실패를 성공으로 처리 | `dispatch.sh:30` | 검증 신뢰성 붕괴 |
| 3 | verify.sh 스코프 접두사 오매칭 | `verify.sh:93` | 스코프 위반 미탐지 |

### P1 — 아키텍처 안정성 (Gemini + Claude)

| # | 문제 | 출처 | 영향 |
|---|------|------|------|
| 4 | `.session_state` 원자적 쓰기 미구현 | Gemini | rate limit 후 상태 파일 0바이트 |
| 5 | FEEDBACK.md에 실패 히스토리 미누적 | Gemini | 에이전트 무한 루프 |
| 6 | agy 모델 ID 불일치 (문서: Gemini, 코드: claude-sonnet) | Gemini+Claude | 오케스트레이터 혼동 |
| 7 | `auto` 모드가 실제로 adaptive하지 않음 | Claude | scoring 데이터 미활용 |

### P2 — 기능 완성 (ChatGPT + Claude)

| # | 기능 | 출처 |
|---|------|------|
| 8 | `agent-team doctor` — 환경 진단 | ChatGPT |
| 9 | `agent-team init` — 초기화 (setup.sh 대체) | ChatGPT |
| 10 | `agent-team diff-summary` — diff 요약기 | ChatGPT |
| 11 | CONTRACT.md 병렬 작업 시 필수 정책 | ChatGPT |
| 12 | 실패 원인 코드 체계 (SCOPE_VIOLATION 등) | ChatGPT |
| 13 | agy/codex 로그 처리 통일 | Claude |

### P3 — 품질 향상 (3종 공통)

| # | 기능 | 출처 |
|---|------|------|
| 14 | verify.sh → 타입 체크, 보안 패턴, 테스트 커버리지 추가 | ChatGPT |
| 15 | 교차 리뷰 파이프라인 (REVIEW_BY_*, FINAL_DECISION) | ChatGPT + Gemini |
| 16 | task_type 세분화 (4개 → 14개+) | ChatGPT |
| 17 | 동적 컨텍스트 가지치기 (마일스톤별 세션 압축) | Gemini |
| 18 | 정적 태스크 트리아지 (diff 크기 기반 사전 라우팅) | Gemini |
| 19 | verify.sh eval 보안 위험 제거 | Claude |

### P4 — 장기 목표

| # | 기능 | 출처 |
|---|------|------|
| 20 | Git worktree 기반 병렬 작업 | ChatGPT |
| 21 | 실시간 비용/절감 대시보드 | Gemini |
| 22 | `agent-team` CLI 명령어 체계 통합 | ChatGPT |
| 23 | 프로젝트 이름 변경 (`agent-team` 또는 `cli-agent-team`) | ChatGPT |
| 24 | adaptive routing 고도화 + confidence score | ChatGPT + Claude |

---

## 3. 단계별 개발 로드맵

### Phase 0 — 버그 픽스 (1~2일, 배포 전 필수)

**목표:** 설치 후 기본 동작이 되는 상태

```
✅ pty-bridge 경로 환경 변수화 or setup.sh에서 복사
✅ EXIT trap 타임스탬프 조건 추가
✅ verify.sh 스코프 접두사 버그 수정
✅ agy 모델 ID 문서 또는 코드 통일 (probe-cli.sh로 확인 후)
```

완료 기준: `bash setup.sh` → `dispatch.sh agy T001 full` → `verify.sh T001` 정상 작동

---

### Phase 1 — 단일 태스크 루프 안정화 (1~2주)

**목표:** `TASK.md → dispatch → REPORT.md → verify → commit` 루프가 10회 연속 안정 작동

```
🔲 .session_state 원자적 쓰기 구현 (임시파일 → rename)
🔲 FEEDBACK.md 실패 히스토리 누적 로직 (회차별 summary 추가)
🔲 agy/codex 로그 append + 시도 헤더 통일
🔲 verify.sh eval → 안전한 명령 실행으로 교체
🔲 REPORT.md 타임스탬프 기반 존재 검증 강화
```

완료 기준: 동일 프로젝트에서 10개 태스크 연속 수행 시 80% 이상 수동 개입 없이 verify 통과

---

### Phase 2 — 진단 및 사용성 (1~2주)

**목표:** 새 프로젝트에서 5분 안에 첫 태스크 실행 가능

```
🔲 agent-team doctor (CLI 존재, headless 실행, pty-bridge 경로, 한국어 경로 체크)
🔲 agent-team init (setup.sh 리뉴얼 — 템플릿 생성 + 대화형 설정)
🔲 agent-team task create "요구사항" → TASK.md 자동 생성
🔲 Windows 경로 공백·한국어 명시적 처리
🔲 빠른 시작 문서 (5분 안에 첫 태스크)
```

---

### Phase 3 — 검증 게이트 강화 (2~3주)

**목표:** 에이전트 결과물의 품질을 자동으로 판단하는 기준 확립

```
🔲 verify.sh 확장:
   - 타입 체크 (tsc --noEmit / mypy)
   - 테스트 커버리지 (기존 대비 하락 감지)
   - 보안 패턴 (API key, rm -rf, --force)
   - 의존성 변경 감지 (package.json diff)
   - diff 요약 출력 (agent-team diff-summary)
🔲 실패 원인 코드 체계 도입 (.agent_scores.json에 fail_reasons 기록)
🔲 auto 모드를 실제 scoring 데이터 기반으로 교체
🔲 task_type 세분화 (frontend.ui_component 등 14종+)
```

---

### Phase 4 — 교차 리뷰 구조 (2~3주)

**목표:** 구현 에이전트 ≠ 리뷰 에이전트

```
🔲 agent-team review T001 --by agy → REVIEW_BY_AGY.md
🔲 agent-team cross-check T001 → FINAL_DECISION.md
🔲 구현자와 리뷰어 동일 에이전트 방지 로직
🔲 리뷰 체크리스트 표준화
🔲 동적 컨텍스트 가지치기 (Phase 게이트 통과 시 세션 요약)
```

---

### Phase 5 — 병렬 작업 안전화 (3~4주)

**목표:** 여러 태스크를 동시에 실행해도 main 브랜치가 오염되지 않음

```
🔲 CONTRACT.md 병렬 작업 시 필수화
🔲 Git worktree 기반 태스크 격리
🔲 patch export + merge 전 conflict check
🔲 정적 태스크 트리아지 (diff 크기 → 에이전트 자동 선택)
🔲 worktree merge 명령 (agent-team merge T001)
```

---

### Phase 6 — 도구화 및 배포 (지속)

```
🔲 agent-team CLI 명령어 체계 완성
🔲 실시간 비용 절감 대시보드
🔲 설치 스크립트 정리 + macOS/Linux 완전 지원
🔲 샘플 프로젝트 + README 리뉴얼
🔲 (검토) 프로젝트 이름 agent-team 또는 cli-agent-team으로 변경
```

---

## 4. MVP 재정의

ChatGPT와 내 분석을 종합한 MVP 범위입니다.

**MVP 목표:**
> 한 개 태스크를 한 개 에이전트에게 안전하게 배정하고,  
> 결과를 검증한 뒤 사람이 승인해서 커밋할 수 있게 한다.  
> 그 과정에서 설치 후 즉시 작동해야 한다.

**MVP에 포함:**

| 기능 | Phase |
|------|-------|
| pty-bridge 경로 버그 수정 | 0 |
| EXIT trap false positive 수정 | 0 |
| .session_state 원자적 쓰기 | 1 |
| FEEDBACK.md 히스토리 누적 | 1 |
| verify.sh 스코프 버그 수정 | 0 |
| agent-team doctor | 2 |
| agent-team init | 2 |
| diff-summary 출력 | 3 |

**MVP에서 제외 (나중에):**
- 완전 자동 loop
- adaptive scoring 실제 연동
- worktree 병렬 작업
- 교차 리뷰
- 대시보드

---

## 5. 핵심 성공 지표

| 단계 | 지표 |
|------|------|
| Phase 0 완료 | 신규 설치 후 agy dispatch 성공 |
| Phase 1 완료 | 10회 연속 태스크 80% 이상 verify 통과 |
| Phase 2 완료 | 새 프로젝트에서 5분 안에 첫 태스크 실행 |
| Phase 3 완료 | 타입 오류·테스트 실패·스코프 위반 자동 감지 |
| Phase 4 완료 | 교차 리뷰 루프 안정 작동 |
| Phase 5 완료 | 2개 태스크 동시 실행 후 충돌 없이 merge |

---

## 6. 3종 피드백이 공통으로 강조한 한 줄

> 이 프로젝트의 성패는 "얼마나 많은 AI를 붙였는가"가 아니라,  
> **"AI들이 만든 결과를 얼마나 안전하게 검증하고 통합할 수 있는가"**에 달려 있다.

핵심 개발 키워드 3가지:
1. **Safety** — 권한, 스코프, 보안, rollback, 원자적 쓰기
2. **Verifiability** — 타입 체크, 테스트, diff 요약, 실패 원인 기록
3. **Orchestration** — 역할 분담, 교차 리뷰, worktree 격리, adaptive routing
