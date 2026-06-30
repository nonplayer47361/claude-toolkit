<div align="center">

<img src="https://img.shields.io/badge/Made%20with-Vibe%20Coding-a371f7?style=for-the-badge&logo=anthropic&logoColor=white" alt="Made with Vibe Coding" />
&nbsp;
<img src="https://img.shields.io/badge/For-Vibe%20Coding-388bfd?style=for-the-badge&logo=github&logoColor=white" alt="For Vibe Coding" />
&nbsp;
<img src="https://img.shields.io/github/v/release/nonplayer47361/claude-toolkit?style=for-the-badge&color=brightgreen" alt="GitHub Release" />
&nbsp;
<img src="https://img.shields.io/badge/license-MIT-blue?style=for-the-badge" alt="MIT License" />

<br/><br/>

> **바이브코딩으로, 바이브코딩을 위한 개발툴을 만든다.**
>
> *AI와 함께 대화하며 코드를 짜는 방식 그 자체로,*
> *더 잘 코딩할 수 있게 해주는 도구를 개발한다.*

</div>

---

# claude-toolkit

**Reusable Claude Code skills, multi-agent loop helpers, and MCP server templates.**

Claude Code를 즉시 쓸 수 있는 설치형 스킬 모음입니다.
핵심은 `cli-agent-team` — Claude가 오케스트레이터(뇌)가 되고 `codex` · `agy` 같은 외부 CLI 에이전트가 실제 코드를 짜는 **다중 에이전트 개발 루프**입니다.

> **외부 에이전트란?**
> - **codex** — [OpenAI Codex CLI](https://github.com/openai/codex). GPT-4o 기반 터미널 코딩 에이전트.
> - **agy** — [Antigravity CLI](https://github.com/antigravity-dev/agy). Google이 개발한 Gemini 기반 코딩 에이전트.
> - **둘 다 선택 사항.** 없어도 Claude 단독으로 모든 핵심 기능이 동작합니다.

---

## 원라이너 설치 (git clone 불필요)

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/nonplayer47361/claude-toolkit/main/scripts/install.ps1 | iex
```

**macOS / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/nonplayer47361/claude-toolkit/main/scripts/install.sh | bash
```

Claude Code를 재시작하면 `/git-commit`, `/git-pr`, `/git-branch`, `/code-review-ko` 명령어를 바로 사용할 수 있습니다.

---

## 이게 왜 필요한가?

| 상황 | Claude 단독 | 이 툴킷 (cli-agent-team) |
|------|------------|--------------------------|
| 단순 질문·단일 작업 | 충분 | 과잉 (쓸 필요 없음) |
| 장기 프로젝트 | 세션마다 컨텍스트 재설명 | `.session_state` + ECC 훅으로 자동 재개 |
| 독립 작업 2개 동시 | 순차 실행 | codex + agy 병렬 dispatch |
| Rate limit 이후 재개 | 처음부터 다시 | 훅이 자동으로 이전 상태 복원 |
| 에이전트 결과 신뢰성 | 결과 직접 확인 | verify.sh 5항목 자동 검증 |
| 어떤 에이전트가 더 나은지 | 감에 의존 | AC 승률 누적 → 자동 배정 최적화 |

**권장 사용 시나리오:** 여러 날에 걸친 프로젝트, 독립 작업을 병렬로 처리하고 싶을 때, 에이전트 결과를 자동으로 검증하고 싶을 때.

---

## 포함된 스킬

| 스킬 | 명령어 | 설명 | setup 필요 |
|------|--------|------|-----------|
| `git-helper` | `/git-commit` `/git-pr` `/git-branch` | 커밋 메시지·PR 설명·브랜치 이름 자동 생성 | No |
| `code-review-ko` | `/code-review-ko` | 한국어 코드 리뷰 (버그·보안·성능·가독성) | No |
| `cli-agent-team` | 스킬 이름으로 호출 | Claude 오케스트레이터 + codex/agy 다중 에이전트 루프 | Yes — `setup.sh` |

---

## cli-agent-team — 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│  User  ──►  Claude Code (Orchestrator / Brain)                  │
│                    │                                            │
│          ┌─────────┴─────────┐                                  │
│          │                   │                                  │
│       codex              agy (+ pty-bridge on Windows)          │
│      (Worker)            (Worker)                               │
│          │                   │                                  │
│    REPORT.md           REPORT.md                                │
│          │                   │                                  │
│          └─────────┬─────────┘                                  │
│                    │                                            │
│             verify.sh (5항목 자동 검증)                          │
│                    │                                            │
│          ┌─────────┴──────────┐                                  │
│          ▼                    ▼                                  │
│        PASS              FAIL                                   │
│       커밋              FEEDBACK.md 재배정                       │
│          │                                                      │
│   record-score.sh                                               │
│  .agent_scores.json 누적                                        │
│          │                                                      │
│  다음 배정 시 적응형 스코어 반영                                  │
└─────────────────────────────────────────────────────────────────┘
```

**역할 분담:**
- **Claude** = 뇌. TASK.md 작성 → 에이전트 배정 → REPORT.md 검토 → 커밋 · 재배정
- **codex / agy** = 손. 실제 코드 작성 · 파일 수정 · REPORT.md 제출
- **codex와 agy는 선택 사항.** 둘 다 없어도 Claude 단독 운영 가능

### 실제 실행 흐름 예시

```bash
# 1. 에이전트에게 태스크 배정
$ bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh dispatch codex T001 limited "$(pwd)" execute

[dispatch] T001 → codex  (execute · limited · quality)
[dispatch] TASK.md 확인: ✅
[dispatch] 실행 중... (codex headless mode)
[dispatch] 완료 (47초)
[dispatch] REPORT.md 수신: ✅
```

```bash
# 2. 결과 자동 검증
$ bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh verify T001 "$(pwd)"

[verify] T001 — codex
[verify] 1/5 스코프 검사............. ✅  허용 파일만 변경됨
[verify] 2/5 AC 체크리스트........... ✅  4/4 항목 통과
[verify] 3/5 보안 스캔 (AgentShield). ✅  이상 없음
[verify] 4/5 완료 증거 파일.......... ✅  utils/formatter.js 존재·변경됨
[verify] 5/5 자동 검증 명령.......... ✅  (없음 — 건너뜀)
[verify] ✅ 검증 통과 — 커밋 진행 가능
[scores] codex/code_implementation: pass=4 fail=0 (승률 100.0%)
```

에이전트가 작성한 REPORT.md 예시:

```markdown
## AC 체크리스트
- [x] formatDate 함수가 utils/formatter.js에 추가됨
- [x] 세 가지 format 모두 동작함
- [x] 기존 코드 변경 없음
- [x] REPORT.md의 AC 체크리스트 모두 [x] 처리됨
```

전체 워크스루: [docs/walkthrough.md](docs/walkthrough.md)

---

## cli-agent-team — 사용 레벨

필요한 만큼만 설치해서 시작할 수 있습니다.

| 레벨 | 필요 도구 | 사용 가능 기능 |
|------|----------|--------------|
| **Level 1 — 기본** | Claude Code + Git | 오케스트레이션, TASK/REPORT 구조, verify, 점수 기록 |
| **Level 2 — 확장** | + codex 또는 agy | 외부 에이전트 dispatch, 병렬 배정, 적응형 스코어링 |
| **Level 3 — 전체** | + Node.js + jq | 데몬 모드, 실시간 대시보드, 일일 효율 리뷰, ECC 훅 |

**Level 1으로 시작하고 필요할 때 올리면 됩니다.** codex/agy 없이도 Claude가 직접 오케스트레이터 + 작업자로 동작합니다.

---

## cli-agent-team — 주요 기능

### 1. 적응형 에이전트 스코어링

태스크 유형(task_type)별로 AC 승률을 추적합니다. 샘플 5건 이상, 승률 차이 15%p 이상이면 더 잘하는 에이전트에 자동 배정됩니다.

```bash
# 결과 기록
bash ~/.claude/skills/cli-agent-team/scripts/record-score.sh codex shell_scripting 8 1

# 점수 파일: _agent_reports/.agent_scores.json
# { "agents": { "codex": { "shell_scripting": { "ac_pass": 8, "ac_fail": 1, "total": 9 } } } }
```

유효한 task_type 14종: `shell_scripting` `documentation` `code_implementation` `testing` `refactoring` `ui_component` `styling` `api_backend` `database` `security` `devops` `config` `data_processing` `analysis`

---

### 2. AgentShield — 7카테고리 보안 스캔

`verify.sh`가 에이전트 결과물을 자동 보안 스캔합니다.

| 카테고리 | 감지 패턴 |
|---------|---------|
| API 키 노출 | `sk-`, `AKIA`, `ghp_` 등 하드코딩 시크릿 |
| 위험한 명령 | `rm -rf /`, `git reset --hard` |
| 코드 인젝션 | `eval $()`, backtick 치환 |
| 권한 남용 | `chmod 777`, `sudo` 무분별 사용 |
| 네트워크 노출 | 0.0.0.0 바인딩, 인증 없는 엔드포인트 |
| 경로 탈출 | `../../` 상위 디렉터리 접근 |
| 환경 오염 | `.env` 직접 수정, 시스템 변수 덮어쓰기 |

---

### 3. 병렬 Dispatch

서로 독립적인 두 태스크를 codex + agy에 동시에 배정합니다.

```bash
# 충돌 여부 사전 검사
bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh parallel-check T001 T002 "$(pwd)"

# 통과 시 동시 배정
bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh dispatch codex T001 limited "$(pwd)" execute
bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh dispatch agy   T002 limited "$(pwd)" execute
```

`parallel-check.sh`가 선행 태스크 완료 여부와 `## 허용 파일` 목록 충돌을 자동으로 검사합니다. 같은 에이전트 병렬 실행은 금지(codex 1 + agy 1이 최대).

---

### 4. ECC 패턴 — 세션 연속성

Claude Code 세션이 끊겨도 컨텍스트가 유지됩니다.

- **session-start 훅** — 세션 시작 시 `_agent_reports/.session_state` 자동 로드
- **pre-compact 훅** — 컨텍스트 압축 직전 진행 상태 자동 저장
- **SHARED_TASK_NOTES.md** — 이터레이션 간 에이전트 공유 메모 브리지

```bash
# 훅 스크립트 위치
skills/cli-agent-team/scripts/hooks/session-start.sh
skills/cli-agent-team/scripts/hooks/pre-compact.sh
```

---

### 5. 일일 효율 리뷰

완료된 태스크의 토큰·LOC·AC를 분석해 `daily/YYYY-MM-DD.md`를 자동 생성합니다.

```bash
bash ~/.claude/skills/cli-agent-team/scripts/daily-review.sh

# 출력 예시: daily/2026-06-30.md
# | 에이전트 | 태스크 | AC 통과율 | 총 토큰 | 평균 소요 | 총 LOC |
# | codex   | 3건    | 89%      | 12,400  | 142s     | 87     |
```

---

### 6. 워크트리 격리

병렬 작업 중 메인 트리가 오염되는 것을 막습니다.

```bash
# 격리된 git worktree에서 에이전트 실행
bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh worktree codex T001 limited "$(pwd)"
```

- 실패 시 worktree 변경이 메인으로 전파되지 않음
- EXIT/INT/TERM 트랩으로 강제 중단 시 worktree 자동 정리
- `rsync --delete`로 삭제·rename까지 메인에 정확히 반영

---

### 7. 데몬 모드 (실시간 에이전트 대기)

터미널 패널에 에이전트 watcher를 상시 실행해두고, Claude가 `trigger.sh`로 즉시 배정합니다.

```powershell
# Windows — VS Code 터미널 패널
~\.claude\skills\cli-agent-team\scripts\agent-watch.ps1 -Agent codex -AuthMode limited
~\.claude\skills\cli-agent-team\scripts\agent-watch.ps1 -Agent agy   -AuthMode limited
```

```bash
# macOS/Linux — tmux 등 별도 터미널
bash ~/.claude/skills/cli-agent-team/scripts/agent-watch.sh codex limited
bash ~/.claude/skills/cli-agent-team/scripts/agent-watch.sh agy   limited
```

```bash
# Claude가 배정
bash ~/.claude/skills/cli-agent-team/scripts/trigger.sh codex T001 execute . quality

# 대시보드 (별도 터미널)
bash ~/.claude/skills/cli-agent-team/scripts/dashboard.sh --watch
```

---

### 8. 자동 검증 (verify.sh 5항목)

에이전트 결과물을 자동으로 검증합니다.

1. **스코프** — `## 허용 파일` 외 변경 없음
2. **AC 체크리스트** — REPORT.md의 `- [ ]` 항목이 0개
3. **보안 패턴** — AgentShield 7카테고리 통과
4. **완료 증거 파일** — TASK.md에 명시된 파일 존재/변경 확인
5. **자동 검증 명령** — AGENT_ROLES.md에 등록된 lint/test 통과

```bash
bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh verify T001 "$(pwd)"
```

---

### 9. 자동 폴백

agy가 빈 출력(2바이트)을 반환하면 codex로 자동 전환됩니다. 원래 배정 에이전트는 `_ORIGINAL_CLI`로 추적되어 `.task_meta.json`에 정확히 기록됩니다.

---

## 워크플로우 한눈에 보기

### 직접 모드 (데몬 없이)

```bash
# 1. 프로젝트 초기화
cd your-project
bash ~/.claude/skills/cli-agent-team/scripts/setup.sh

# 2. Claude가 TASK.md 작성 후 배정
bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh dispatch codex T001 limited "$(pwd)" execute quality

# 3. 자동 검증
bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh verify T001 "$(pwd)"

# 4. 커밋 (verify.sh 통과 후)
git add . && git commit -m "feat: T001 완료"
```

### 데몬 모드 (실시간)

```
터미널 A │ agent-watch.ps1 -Agent codex -AuthMode limited
터미널 B │ agent-watch.ps1 -Agent agy   -AuthMode limited
터미널 C │ dashboard.sh --watch
터미널 D │ Claude Code (trigger.sh로 배정)
```

---

## 빠른 시작 (1분)

### 원라이너 설치 (권장)

**Windows:**
```powershell
irm https://raw.githubusercontent.com/nonplayer47361/claude-toolkit/main/scripts/install.ps1 | iex
```

**macOS / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/nonplayer47361/claude-toolkit/main/scripts/install.sh | bash
```

### 직접 설치 (git clone)

```powershell
git clone https://github.com/nonplayer47361/claude-toolkit.git
cd claude-toolkit
.\scripts\setup.ps1       # Windows
bash scripts/setup.sh     # macOS/Linux
```

### Claude Code 재시작 후 사용

```
/git-commit       # 커밋 메시지 생성 (staged diff 분석)
/git-pr           # PR 설명 작성
/git-branch       # 브랜치 이름 제안
/code-review-ko   # 한국어 코드 리뷰
```

### cli-agent-team 프로젝트 초기화

```bash
cd your-project
bash ~/.claude/skills/cli-agent-team/scripts/setup.sh
bash ~/.claude/skills/cli-agent-team/scripts/setup.sh --status
```

---

## 시스템 요구사항

| 도구 | 필요 여부 | 용도 |
|------|---------|------|
| Claude Code CLI | **필수** | 오케스트레이터, 스킬 실행 |
| Git + Bash | **필수** | 버전 관리, 스크립트 실행 |
| Node.js | 선택 (agy 사용 시) | Windows pty-bridge |
| jq | 선택 | 적응형 스코어링, daily-review |
| [codex CLI](https://github.com/openai/codex) | 선택 | OpenAI Codex — GPT-4o 기반 터미널 코딩 에이전트 |
| [agy CLI](https://github.com/antigravity-dev/agy) | 선택 | Antigravity — Google 개발 Gemini 기반 코딩 에이전트 |

---

## 스크립트 레퍼런스

| 스크립트 | 역할 |
|---------|------|
| `setup.sh` | 에이전트 감지 + `.cli-agent-team.conf` 생성 |
| `init.sh` | 프로젝트 대화형 초기화 (PLAN.md, AGENT_ROLES.md, AGENTS.md 생성) |
| `dispatch.sh` | 에이전트에게 태스크 직접 실행 |
| `trigger.sh` | 데몬 모드 에이전트에게 태스크 전달 |
| `verify.sh` | 5항목 자동 검증 + 보안 스캔 |
| `agent-watch.ps1 / .sh` | 에이전트 데몬 watcher |
| `dashboard.sh` | 실시간 태스크·에이전트 상태 표시 |
| `record-score.sh` | AC 결과를 `.agent_scores.json`에 누적 |
| `daily-review.sh` | 일별 효율 리포트 생성 (`daily/YYYY-MM-DD.md`) |
| `parallel-check.sh` | 병렬 배정 전 충돌 검사 |
| `worktree-dispatch.sh` | git worktree 격리 환경에서 에이전트 실행 |
| `agent-shield.sh` | 7카테고리 보안 스캔 단독 실행 |
| `cross-review.sh` | 두 에이전트가 같은 코드를 독립 리뷰 후 비교 |
| `analyze-limits.sh` | rate limit 패턴 분석 |
| `probe-cli.sh` | CLI 에이전트 비대화형 실행 가능 여부 검증 |
| `doctor.sh` | 환경 진단 (CLI 설치, conf, Node.js, jq 등) |
| `update-state.sh` | `.session_state` 업데이트 (ECC 패턴) |

---

## 문서

| 문서 | 내용 |
|------|------|
| [Install Guide](docs/install-guide.md) | 단계별 설치 및 검증 |
| [Quickstart](docs/quickstart.md) | 5분 안에 첫 태스크 실행 |
| [**E2E Walkthrough**](docs/walkthrough.md) | 처음부터 끝까지 실제 예시 (출력 포함) |
| [Skills Overview](docs/skills-overview.md) | 스킬별 사용법과 예시 |
| [cli-agent-team Guide](docs/cli-agent-team-guide.md) | 전체 다중 에이전트 워크플로우 |
| [Architecture](docs/architecture.md) | 내부 동작 기술 문서 (기여자용) |
| [Contributing](CONTRIBUTING.md) | 기여 가이드 |

---

## 트러블슈팅

| 증상 | 해결 |
|------|------|
| 스킬 명령어가 Claude Code에 안 보임 | Claude Code 재시작. `~/.claude/skills/` 디렉터리 확인 |
| `bash: command not found` (Windows) | Git Bash 설치 후 PATH 추가, 또는 WSL 사용 |
| 한글 깨짐 (Windows) | `chcp 65001` 실행 |
| agy 출력이 비어 있음 | pty-bridge 경유 확인: `node ~/.claude/mcp-servers/pty-bridge/run.js -- agy --help` |
| `ERROR_AC` | REPORT.md의 `- [ ]` 항목 확인. AC 체크리스트 섹션 필수 |
| `ERROR_TEST` | 검증 명령 로그 확인. FEEDBACK.md 작성 후 재배정 |
| 데몬 마커 없음 | `agent-watch.ps1`을 프로젝트 루트에서 재실행. `-ProjectDir` 명시 |
| record-score.sh skip | `jq` 미설치. `winget install jqlang.jq` 또는 `brew install jq` |

```bash
# 환경 진단 한 번에
bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh doctor
```

---

## Contributing

**PR과 이슈 모두 환영합니다.** 함께 만들어가는 프로젝트입니다.

### 기여할 수 있는 것들

- 새로운 에이전트 지원 추가 (Gemini CLI, Aider 등)
- 새로운 스킬 제작 (예: `/debug-ko`, `/test-gen`)
- 기존 스크립트 버그 수정 및 개선
- macOS/Linux 호환성 개선
- 문서 개선 (예제 추가, 번역)
- 새로운 task_type 추가 (record-score.sh 스키마 확장)

### 기여 방법

```bash
# 1. 레포 포크 및 클론
git clone https://github.com/YOUR_USERNAME/claude-toolkit.git
cd claude-toolkit

# 2. 브랜치 생성
git checkout -b feat/your-feature

# 3. 변경 후 커밋
git commit -m "feat: 설명"

# 4. PR 생성
gh pr create
```

### 스킬 만드는 법

```bash
# 새 스킬 템플릿 생성
.\scripts\new-skill.ps1 -SkillName my-skill    # Windows
# 또는 skills/_template/ 복사
```

`skills/<이름>/SKILL.md`에 frontmatter `name`·`description`·`triggers` 필수.

### MCP 서버 만드는 법

```bash
.\scripts\new-mcp.ps1 -ServerName my-server    # Windows
cd mcp-servers/my-server && npm install
```

`mcp-servers/<이름>/index.js` + `package.json` (ESM, stdio transport).

이슈 제보 시 로그 파일 첨부:
```bash
bash scripts/export-issue.sh
# issue-report-*.txt 생성 → GitHub Issues에 첨부
```

---

## 라이선스

MIT License — 자유롭게 쓰고, 고치고, 배포하세요.

---

## 한국어 안내

### 포함된 스킬

| 스킬 | 명령어 | 설명 | setup.sh 필요 |
|------|--------|------|--------------|
| `git-helper` | `/git-commit` `/git-pr` `/git-branch` | 커밋 메시지·PR 설명·브랜치 이름 자동 생성 | No |
| `code-review-ko` | `/code-review-ko` | 한국어 코드 리뷰 (버그·보안·성능·가독성) | No |
| `cli-agent-team` | — | Claude 오케스트레이터 + codex/agy 다중 에이전트 루프 | Yes |

### 빠른 시작 (1분)

**원라이너 설치 (권장 — git clone 불필요)**

Windows:
```powershell
irm https://raw.githubusercontent.com/nonplayer47361/claude-toolkit/main/scripts/install.ps1 | iex
```

macOS/Linux:
```bash
curl -fsSL https://raw.githubusercontent.com/nonplayer47361/claude-toolkit/main/scripts/install.sh | bash
```

**직접 설치 (git clone)**

```powershell
git clone https://github.com/nonplayer47361/claude-toolkit.git
cd claude-toolkit
.\scripts\setup.ps1       # Windows
bash scripts/setup.sh     # macOS/Linux
```

**Claude Code 재시작 후 사용:**
```
/git-commit       # 커밋 메시지 생성
/git-pr           # PR 설명 작성
/git-branch       # 브랜치 이름 제안
/code-review-ko   # 한국어 코드 리뷰
```

### cli-agent-team (다중 에이전트)

codex 또는 agy가 있으면 다중 에이전트 루프를 사용할 수 있습니다.

```bash
# 프로젝트 초기화 (프로젝트 루트에서)
bash ~/.claude/skills/cli-agent-team/scripts/setup.sh

# 에이전트 데몬 시작
~\.claude\skills\cli-agent-team\scripts\agent-watch.ps1 -Agent codex -AuthMode limited

# 대시보드 (별도 터미널)
bash ~/.claude/skills/cli-agent-team/scripts/dashboard.sh --watch
```

### 주요 기능 요약

| 기능 | 설명 |
|------|------|
| 적응형 스코어링 | task_type별 AC 승률 추적, 자동 에이전트 배분 보정 |
| AgentShield | 7카테고리 보안 스캔 자동 수행 |
| 병렬 dispatch | codex + agy 동시 실행, 파일 충돌 자동 감지 |
| ECC 패턴 | 세션 간 컨텍스트 자동 유지 |
| 일일 효율 리뷰 | 토큰/LOC/AC 분석 리포트 자동 생성 |
| 워크트리 격리 | 병렬 작업 시 메인 트리 오염 방지 |
| 자동 폴백 | agy 실패 시 codex 자동 전환 |
| 자동 검증 | 스코프·AC·보안·파일·테스트 5항목 자동 검증 |

### 문서

| 문서 | 내용 |
|------|------|
| [설치 가이드](docs/install-guide.md) | 단계별 설치 |
| [빠른 시작](docs/quickstart.md) | 5분 안에 첫 태스크 실행 |
| [**E2E 워크스루**](docs/walkthrough.md) | 처음부터 끝까지 실제 예시 (터미널 출력 포함) |
| [스킬 개요](docs/skills-overview.md) | 스킬별 사용법과 예시 |
| [cli-agent-team 가이드](docs/cli-agent-team-guide.md) | 다중 에이전트 전체 워크플로우 |
| [아키텍처](docs/architecture.md) | 내부 동작 기술 문서 |
| [기여 가이드](CONTRIBUTING.md) | PR·이슈·스킬 추가 방법 |

### 문제 신고

오류 발생 시 로그를 내보내서 이슈로 제출해 주세요:
```bash
bash scripts/export-issue.sh
```
생성된 `issue-report-*.txt` 파일을 [GitHub Issues](https://github.com/nonplayer47361/claude-toolkit/issues)에 첨부해 주세요.

### 기여

PR과 이슈 모두 환영합니다! 새로운 에이전트 지원, 스킬 추가, 버그 수정, 문서 개선 — 어떤 형태든 기여를 기다립니다.
