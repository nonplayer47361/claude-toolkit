# AGENTS.md — claude-toolkit

관련: [[skills/cli-agent-team/references/soul-template]] | [[skills/cli-agent-team/references/task-templates]] | [[skills/cli-agent-team/SKILL.md]]

사람이 검토·승인한 프로젝트 운영 규칙. Memory MCP 자동 기억과 달리 이 파일이 최우선 신뢰 기준이다.

---

## 에이전트 행동 원칙 (Karpathy 4규칙)

### 1. Think Before Coding
- 작업 시작 전 목표·가정·허용 범위·완료 기준을 명시한다.
- 모호하거나 위험한 변경은 코딩 전에 질문한다.

### 2. Simplicity First
- 요청받은 것만 최소한으로 구현한다. 미래 기능 선제 추가 금지.

### 3. Surgical Changes
- 태스크와 무관한 코드·주석·포맷을 건드리지 않는다.

### 4. Goal-Driven Execution
- 테스트 가능한 완료 기준을 먼저 확인하고, 구현 후 검증 명령을 실행한다.

---

## 에이전트 역할 카드

### codex
| 항목 | 내용 |
|------|------|
| 강점 | 알고리즘 구현, 단위 테스트, Bash 스크립트, 성능 최적화, 복잡한 리팩토링 |
| 제약 | 인증 파일 수정 금지, DB 스키마 직접 변경 금지 |
| 모델 티어 | quality (`gpt-5.5`) 기본 |
| headless | ✅ 직접 실행 가능 |

### agy
| 항목 | 내용 |
|------|------|
| 강점 | 문서 작성, 주석 정리, TODO 갱신, 인라인 수정, REPORT 작성 |
| 제약 | 새 파일 생성 최소화, 아키텍처 결정 단독 불가 |
| 모델 티어 | fast (`claude-haiku-4-5-20251001`) 기본 |
| headless | ⚠️ TTY 필요 — 반드시 `mcp-servers/pty-bridge/run.js` 경유 |

---

## 모델 티어 선택 기준

| 티어 | 모델 | 사용 기준 |
|------|------|-----------|
| fast | gpt-5.4-mini / claude-haiku | TODO·문서·주석·REPORT·단순 반복 |
| quality | gpt-5.5 / claude-sonnet | 인증·보안·DB·공개 API·복잡 로직·설계 판단 |

---

## 병렬 실행 정책

- **최대 2개 동시**: codex 1개 + agy 1개
- 같은 에이전트를 병렬로 띄우지 않는다 (agy 내부 상태 혼선 위험)
- 파일 충돌 없는 경우에만 병렬, 기본은 순차 실행

---

## 아키텍처 결정 로그

| 날짜 | 결정 내용 | 이유 |
|------|-----------|------|
| 2026-06-28 | agy headless 실행을 pty-bridge(node-pty ConPTY)로 우회 | agy는 TTY 없으면 응답을 stdout이 아닌 터미널에 직접 써서 출력이 버려짐 |
| 2026-06-28 | dispatch.sh에 MODEL_TIER 6번째 파라미터 추가 | 문서 태스크(fast)와 코드 태스크(quality) 간 비용/품질 트레이드오프 제어 |
| 2026-06-28 | 병렬 실행을 codex+agy 각 1개로 제한 | agy 4개 병렬 시 내부 작업 디렉토리 혼선으로 TASK.md를 못 찾는 버그 발생 |
| 2026-06-28 | trigger.sh ERROR를 ERROR_AC / ERROR_TEST / ERROR_TIMEOUT으로 세분화 | 단순 ERROR로는 재시도 전략을 구분할 수 없어 맹목적 재시도 발생 |

---

## 접근 금지 파일

- `.env`, `.env.*`
- `mcp-servers/pty-bridge/node_modules/`
- `_agent_reports/` (런타임 상태, git 미추적)

---

## 반복 실패 패턴

| 태스크 | 증상 | 원인 | 해결책 |
|--------|------|------|--------|
| T_AGY_* | agy `--print` 실행 시 exit 0, 출력 0바이트 | TTY 없으면 응답을 터미널에 직접 씀 → 파이프 환경에서 사라짐 | `mcp-servers/pty-bridge/run.js` 경유 실행 |
| T006 | dispatch.sh에서 `MODEL_TIER` 미정의 변수 오류 | agy가 변수 선언 없이 case 블록만 추가 | `MODEL_TIER="${6:-quality}"` 라인 수동 추가 |
| Round1 T011 | agy가 `.gemini/antigravity-cli/scratch`에서 TASK.md 탐색 | agy 4개 병렬 실행 시 내부 컨텍스트 혼선 | 병렬 실행 2개 이하 제한 후 재실행으로 해결 |
| run_failure_tests SIM13+ | MODEL/PTY 테스트가 실제로 실행되지 않음 | `run_test` 내 grep 파이프에 `\|\| true` 누락 → pipefail로 스크립트 종료 | grep 파이프 끝에 `\|\| true` 추가 |
| SIM09 | `parallel-check.sh` 선행 T001 완료 확인 실패 | PLAN.md가 표 형식(`\| T001 \|`)에서 체크박스 형식(`- [x] T001:`)으로 변경됨 | grep 패턴을 양쪽 형식 지원으로 확장 |

---

## 태스크 완료 기준 (공통)

- [ ] TASK.md 허용 파일 목록 밖 수정 없음
- [ ] `bash -n <스크립트>` 문법 검사 통과
- [ ] REPORT.md에 `## AC 체크리스트` 섹션 존재, `[ ]` 항목 없음
- [ ] 기존 동작과 호환성 유지 확인
