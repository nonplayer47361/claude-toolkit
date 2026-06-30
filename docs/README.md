# docs/ 문서 안내

처음 방문했다면 아래 **"어디서 시작할까?"** 를 읽고 목적에 맞는 문서로 이동하세요.

---

## 어디서 시작할까?

### 외부 에이전트(codex / agy)를 쓰고 싶다 → 패러다임 A

codex(OpenAI/GPT-4o) 또는 agy(Antigravity/Gemini)가 설치된 환경이라면 **cli-agent-team 스킬**을 사용하세요.
Claude가 오케스트레이터가 되어 외부 CLI를 배정·검증·커밋합니다.

```
빠른 시작:  docs/quickstart.md
설치:       docs/install-guide.md
E2E 예시:   docs/walkthrough.md
```

### Claude Code만 있다 → 패러다임 B

codex/agy 없이 Claude Code만으로 다중 에이전트 팀을 구성하고 싶다면 **내부 서브에이전트 패턴**을 사용하세요.
Claude가 `Agent()` 도구로 planner / qa-analyst / impl-dev 같은 서브에이전트를 직접 생성합니다.

```
개념 설명:  docs/multi-agent-architecture.md
세팅 방법:  docs/project-setup-guide.md
```

---

## 두 패러다임 비교

| | 패러다임 A — 외부 CLI | 패러다임 B — 내부 서브에이전트 |
|---|---|---|
| **필요 도구** | codex 또는 agy (선택) | Claude Code만 |
| **통신 방식** | `TASK.md` → `REPORT.md` 파일 기반 | `_workspace/` 파일 + SendMessage |
| **검증** | verify.sh 5-point 게이트 | QA 에이전트가 직접 검증 |
| **병렬 실행** | codex + agy 동시 배정 가능 | Agent() 병렬 호출 |
| **관련 스킬** | cli-agent-team | harness |

---

## 전체 문서 목록

### 패러다임 A — cli-agent-team (외부 CLI)

| 파일 | 설명 |
|------|------|
| [quickstart.md](quickstart.md) | 5분 안에 첫 태스크 실행하기 |
| [install-guide.md](install-guide.md) | 설치 단계별 가이드 (원라이너 포함) |
| [walkthrough.md](walkthrough.md) | E2E 완전 예시 — doctor→dispatch→verify→commit |
| [cli-agent-team-guide.md](cli-agent-team-guide.md) | 사용 가이드 (직접 모드 / 데몬 모드 / 병렬 배정) |
| [architecture.md](architecture.md) | 내부 기술 레퍼런스 — 스크립트 전체, 데이터 흐름 |
| [troubleshooting.md](troubleshooting.md) | 문제 해결 FAQ |

### 패러다임 B — 내부 서브에이전트 (Claude Agent())

| 파일 | 설명 |
|------|------|
| [multi-agent-architecture.md](multi-agent-architecture.md) | 개념과 구조 — planner/qa/impl 역할 분담 |
| [project-setup-guide.md](project-setup-guide.md) | 새 프로젝트에 내부 서브에이전트 세팅하는 방법 |

### 공통

| 파일 | 설명 |
|------|------|
| [skills-overview.md](skills-overview.md) | 스킬 3종(git-helper, code-review-ko, cli-agent-team) 개요 |

---

## 내부 문서

`docs/internal/` 폴더에는 개발 과정에서 생성된 계획서·분석 문서가 있습니다. 사용자 문서가 아닙니다.
