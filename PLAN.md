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

## 남은 작업

### 인프라 설치 (사용자 직접 실행)

```powershell
# Memory MCP — 세션 간 지식 그래프 보존
claude mcp add memory npx @modelcontextprotocol/server-memory

# Sequential Thinking MCP — PLAN.md 작성 전 구조적 추론
claude mcp add sequentialthinking npx @modelcontextprotocol/server-sequentialthinking
```

```bash
# lat.md — [[wikilink]] 기반 MD 지식 그래프
npm install -g lat.md && lat init
```

VS Code 마켓플레이스: `Foam` 확장 설치 (wikilink 시각화)

```
# wshobson 플러그인 (Claude Code 내에서)
/plugin marketplace add wshobson/agents
```

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
