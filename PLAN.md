# PLAN.md — claude-toolkit

관련: [[AGENTS.md]] | [[skills/cli-agent-team/SKILL.md]]

마지막 업데이트: 2026-06-28

---

## 프로젝트 목표

Claude Code용 스킬·에이전트·MCP 서버를 개발하고 배포하는 작업 공간.
핵심: cli-agent-team 스킬을 통해 Claude 오케스트레이터 + codex/agy 하위 에이전트 다중 에이전트 루프 구성.

---

## 완료된 작업

### cli-agent-team 스킬 고도화 (2026-06-27 ~ 2026-06-28)

#### Phase 0 — 기반 (이전 세션)
- [x] dispatch.sh / trigger.sh / agent-watch.ps1 / verify.sh 기본 구조 구현
- [x] 14개 실패 시나리오 테스트 (`run_failure_tests.sh`)
- [x] `_agent_reports/` gitignore 추가

#### Phase 1 — 참조 문서
- [x] T001: `references/agents-template.md` (Karpathy 4규칙, 역할 카드, 모델 티어)
- [x] T002: `references/soul-template.md` (SOUL.md 오케스트레이터 원칙)
- [x] T003: `references/commands/` (start-task, review, cross-check 슬래시 커맨드)
- [x] T004: `references/task-templates.md` EARS AC 형식 추가
- [x] T005: MD 파일 [[wikilink]] 연결

#### Phase 2 — 스크립트 강화
- [x] T006: `dispatch.sh` MODEL_TIER 6번째 파라미터 (fast/quality 동적 모델 선택)
- [x] T007: `trigger.sh` MODEL_TIER + ERROR 세분화 / `agent-watch.ps1` MODEL_TIER 전파
- [x] T009: `run_failure_tests.sh` MODEL_TIER 테스트 케이스 4개 추가
- [x] `dispatch.sh` agy PTY-bridge 연동 (headless 실행 문제 해결)

#### Phase 3 — 구조 확장
- [x] T010: `references/_specs-template/` SDD 3-doc 구조
- [x] T011: `references/{codex,agy}.agent_capability.json` A2A 역할 카드
- [x] T012: `scripts/dashboard.sh` 태스크·데몬 상태 표시 (--watch/--verbose)
- [x] `mcp-servers/pty-bridge/` node-pty ConPTY 래퍼

#### 선택적 개선 (2026-06-28)
- [x] `~/.claude/SOUL.md` 오케스트레이터 전역 원칙 적용
- [x] `AGENTS.md` 프로젝트 루트 적용 (실제 발견한 패턴·결정 포함)
- [x] `PLAN.md` 작성 (이 파일)

#### 인프라 설치 완료 (2026-06-28)
- [x] Memory MCP (`@modelcontextprotocol/server-memory`) 설치 및 연결
- [x] Sequential Thinking MCP (`@modelcontextprotocol/server-sequential-thinking`) 설치 및 연결
- [x] `lat.md` 설치 + `lat init` → `lat.md/` 커밋
- [x] VS Code Foam 확장 설치 (Antigravity IDE)
- [x] `wshobson/agents` → `~/.claude/agents/` 설치

#### 선택 작업 완료 (2026-06-28)
- [x] `run_failure_tests.sh` 확장: PTY-01/02 추가, pipefail 버그 수정, SIM09 수정
- [x] E2E 파이프라인 테스트: dispatch→pty-bridge→agy→verify 전 구간 통과 (T-E2E-01)
- [x] `dashboard.sh` 개선: 실시간 시계, 변경 감지, IN_PROGRESS 우선 정렬, 역방향
- [x] `dashboard.sh --watch` 실사용 검증 (T-DASH-01 라이브 테스트)
- [x] Memory MCP 지식 마이그레이션 (8 엔티티, 7 관계 그래프 저장)
- [x] 새 스킬 개발: `git-helper` (커밋/PR/브랜치), `code-review-ko` (한국어 리뷰)

---

## M5 — workflow 품질 개선 (2026-06-28~)

### 진행 대기

(없음)

### 완료

| ID | 설명 | 커밋 |
|----|------|------|
| T-M5-SCOPE | verify.sh temporal scope fix — dispatch 이전 변경 파일 제외 | 1e9e4d4 |
| T-M5-CROSS | cross-agent review 파이프라인 — 두 에이전트 독립 리뷰 후 통합 | (이번 커밋) |

---

## M4 — adaptive routing + 스킬 완성도 (2026-06-28~)

### 진행 대기

(없음)

### 완료

| ID | 설명 | 커밋 |
|----|------|------|
| T-M4-AUTO | dispatch.sh `auto` 모드 → `.agent_scores.json` 기반 adaptive routing 구현 | 584d29e |
| T-M4-PROBE | probe-cli.sh agy full 실행 → agy 실제 모델 확인 → agent-characteristics.md 갱신 | 1c6dfe6 |
| T-M4-VERIFY | verify.sh 타입 체크·보안 패턴 검사 확장 | d29fc03 |
| T-M4-INIT | `agent-team init` 대화형 초기화 명령 (setup.sh 대체) | 1c34d19 |

---

## M6 — 토큰 최적화 인프라 (2026-06-29~)

### 진행 대기

(없음)

### 완료

| ID | 설명 | 비고 |
|----|------|------|
| T-M6-RTK-INSTALL | RTK v0.43.0 설치 — Claude Code hook, agy rules, Codex AGENTS.md | 수동 설치 |
| T-M6-CBM-INSTALL | codebase-memory-mcp v0.8.1 설치 — 6개 에이전트 자동 등록 | 수동 설치 |
| T-M6-SERENA-INSTALL | Serena v1.5.3 설치 — Claude Code MCP 등록 | 수동 설치 |
| T-M6-RTK-DISPATCH | dispatch.sh execute MSG에 RTK + codebase-memory 사용 지침 삽입 | 85421af |
| T-M6-CBM-INDEX | codebase-memory-mcp 인덱싱 완료 (409 nodes, shell script 제외됨) | MCP stdout |
| T-M6-SERENA-HOOKS | Serena hooks 등록 (activate — settings.json 제약으로 수동 적용 필요) | partial |

---

## M7 — 안정성·적응형 강화 (2026-06-29~)

### 완료

| ID | 설명 | 커밋 |
|----|------|------|
| T-M7-RETRY | dispatch.sh: agy 빈 출력 감지 → codex fallback 자동 실행 | (이번 커밋) |
| T-M7-SCORE-AUTO | verify.sh: 검증 통과 시 AC 점수 자동 집계·기록, record-score.sh project-dir 파라미터 추가 | (이번 커밋) |

---

## 남은 작업

### 인프라 설치 완료 현황

| 항목 | 상태 |
|------|------|
| Memory MCP | ✅ 설치됨 |
| Sequential Thinking MCP | ✅ 설치됨 |
| RTK v0.43.0 | ✅ 설치됨 (Claude+agy+Codex) |
| codebase-memory-mcp v0.8.1 | ✅ 설치됨 (6개 에이전트) |
| Serena v1.5.3 | ✅ 설치됨 |

### 선택 작업

| 항목 | 상태 |
|------|------|
| `run_failure_tests.sh` 확장 | ✅ 완료 |
| E2E 파이프라인 테스트 | ✅ 완료 |
| `dashboard.sh --watch` 실사용 검증 | ✅ 완료 |
| `dashboard.sh` 개선 (실시간 시계·정렬) | ✅ 완료 |
| Memory MCP 지식 마이그레이션 | ✅ 완료 |
| 새 스킬: `git-helper` | ✅ 완료 |
| 새 스킬: `code-review-ko` | ✅ 완료 |

---

## 커밋 이력 (주요)

| 커밋 | 내용 |
|------|------|
| `fec9fc6` | feat: git-helper, code-review-ko 스킬 추가 |
| `6e794f8` | feat: dashboard.sh 개선 (실시간 시계, 변경 감지, 정렬) |
| `5915715` | test(E2E): dispatch→pty-bridge→agy→verify 전 구간 통과 |
| `82ae864` | fix: run_failure_tests 버그 2개 수정 + PTY/SIM09 테스트 개선 |
| `3af65a2` | chore: lat.md 초기화 |
| `b1b0fc7` | feat: SOUL.md·AGENTS.md·PLAN.md 적용 |
| `5f967a2` | feat: cli-agent-team 다중에이전트 구조 고도화 (Phase 1-3) |
| `e8d8f51` | chore: _agent_reports/ gitignore 추가 |
