# PLAN.md — claude-toolkit

관련: [[AGENTS.md]] | [[skills/cli-agent-team/SKILL.md]]

마지막 업데이트: 2026-06-29

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
| T-M7-RETRY | dispatch.sh: agy 빈 출력 감지 → codex fallback 자동 실행 | 2562085 |
| T-M7-SCORE-AUTO | verify.sh: 검증 통과 시 AC 점수 자동 집계·기록, record-score.sh project-dir 파라미터 추가 | 2562085 |
| T-M7-DOCTOR | doctor.sh: RTK·Serena·CBM 토큰 최적화 인프라 체크 추가 | e590eaf |
| T-M7-DASHBOARD | dashboard.sh: 헤더에 RTK 토큰 절약량 표시 | 0b1f2ac |
| T-M7-INSTALL | install-skill.ps1: --Update 플래그 — scripts/+SKILL.md만 교체, references/ 보존 | 6ba40c0 |
| T-M7-WORKTREE | worktree-dispatch.sh 신규 — git worktree 격리 실행, 병렬 충돌 방지 | efaf729 |

---

## M8 — 보안·확장성·사용성 강화 (2026-06-29)

### 완료

| ID | 설명 | 내용 |
|----|------|------|
| T-M8-EVAL | verify.sh: `eval "$cmd"` → 화이트리스트 + `bash -c` 교체 (보안) | |
| T-M8-LOG | dispatch.sh: agy/codex 로그 append 통일 + 시도 헤더 삽입 | |
| T-M8-FAIL | verify.sh + record-score.sh: 실패 원인 코드 체계 (fail_reasons) | |
| T-M8-TYPE | record-score.sh: task_type 5종 → 14종 세분화 (플랫) | |
| T-M8-CLI | agent-team.sh: 통합 CLI 래퍼 신규 생성 | |
| T-M8-DOCS | docs/quickstart.md: 5분 안에 첫 태스크 가이드 | |

---

## M9 — 보안 강화 (2026-06-29) [완료 5/5]

> 리뷰 취합본 기반. M8-EVAL이 `eval` 제거에 그쳐 화이트리스트 우회가 여전히 가능.
> 셸 메타문자 인젝션, 권한 하드코딩, conf source 등 공격면 폐쇄.

### 완료

| ID | 설명 | 커밋 |
|----|------|------|
| T-M9-VERIFY-SEC | verify.sh: 메타문자 차단 + 배열 실행 + 스코프 실패 시 조기 skip | e78ca64 |
| T-M9-INIT-DEFAULT | init.sh: 기본 권한 `완전자율` → `제한된 자율` | e78ca64 |
| T-M9-CONF-SOURCE | dispatch.sh: conf source 제거 → _parse_conf grep 파싱 교체 | c136839 |
| T-M9-CROSS-AUTH | cross-review.sh: $2 인자 버그 수정 + full 하드코딩 제거 | 36b55a1 |
| T-M9-TASKID-VALID | worktree-dispatch.sh: TASK_ID 형식 검증 추가 | 80ee520 |

---

## M10 — 이식성·경로 수정 (2026-06-29) [완료 4/4]

> `dashboard.sh`와 `record-score.sh`의 `../../..` 하드코딩이 `install-skill.ps1` 설치 즉시 깨짐.
> `dispatch.sh`·`verify.sh`의 위치 독립 방식(`[project-dir]` 인자)으로 통일.

### 완료

| ID | 설명 | 커밋 |
|----|------|------|
| T-M10-DASH-PATH | dashboard.sh: --project-dir 인자 + PROJECT_ROOT env 우선 적용 | 5b9182d |
| T-M10-SCORE-PATH | record-score.sh: PROJECT_ROOT env > 5번째 인자 > fallback 순위 | 5b9182d |
| T-M10-SETUP-MSG | setup.sh: bash .ps1 오류 안내 → PowerShell/bash 분리 안내 | 7e568c4 |
| T-M10-DISPATCH-RTK | dispatch.sh: RTK/CBM 지시 command -v rtk 조건부화 | cc7f118 |

---

## M11 — 동시성·워크트리 안전성 (2026-06-29) [완료 5/5]

> 병렬 모드에서 공유 상태 파일 손상, 실패 작업의 메인 작업트리 오염,
> 강제 중단 시 가비지 워크트리 방치 문제 해결.

### 완료

| ID | 설명 | 커밋 |
|----|------|------|
| T-M11-LOCK | record-score.sh: flock/mkdir 락 — 병렬 호출 시 .agent_scores.json 원자화 | 125e145 |
| T-M11-WT-CLEANUP | worktree-dispatch.sh: EXIT/INT/TERM trap — 강제 중단 시 워크트리 자동 정리 | 125e145 |
| T-M11-WT-FAIL | worktree-dispatch.sh: dispatch 실패 시 메인 트리 복사 차단 | 6546450 |
| T-M11-WT-DELETE | worktree-dispatch.sh: cp → rsync --delete — 삭제·rename 메인에 반영 | 851673f |
| T-M11-WT-DIRTY | worktree-dispatch.sh: dirty 폴백 제거 → 경고 메시지로 교체 | 65a465e |

---

## M12 — 코드 품질·확장성 (2026-06-29) [완료 6/6]

> 문서-구현 불일치 누적, 확장 비용, 코드 중복 해결.
> 3번째 에이전트 추가 시 파일 직접 편집 없이 가능한 구조로.

### 완료

| ID | 설명 | 커밋 |
|----|------|------|
| T-M12-INIT-WIRE | agent-team.sh: usage 주석 setup.sh → init.sh 정정 | 424a8df |
| T-M12-MODEL-CONF | dispatch.sh: 모델 ID conf 변수화 — 하드코딩 제거 | 9c18bdf |
| T-M12-PARALLEL-ROLES | parallel-check.sh: AGENT_ROLES.md 병렬 허용 게이트 적용 | 75b2488 |
| T-M12-PARALLEL-PATH | parallel-check.sh: 경로 기반 파일 충돌 감지 (오탐 방지) | 190bcdf |
| T-M12-SCORE-STAT | record-score.sh + verify.sh: 실패 통계 출력 추가 | 8995067 |
| T-M12-EXTRACT-UNIFY | verify.sh + parallel-check.sh: extract_section 함수 통일 | 65a1fbb |

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
