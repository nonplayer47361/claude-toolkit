<div align="center">

<img src="https://img.shields.io/badge/Made%20with-Vibe%20Coding-a371f7?style=for-the-badge&logo=anthropic&logoColor=white" alt="Made with Vibe Coding" />
&nbsp;
<img src="https://img.shields.io/badge/For-Vibe%20Coding-388bfd?style=for-the-badge&logo=github&logoColor=white" alt="For Vibe Coding" />

<br/><br/>

> **바이브코딩으로, 바이브코딩을 위한 개발툴을 만든다.**
>
> *AI와 함께 대화하며 코드를 짜는 방식 그 자체로,*
> *더 잘 코딩할 수 있게 해주는 도구를 개발한다.*

</div>

---

# claude-toolkit

Reusable Claude Code skills, agent-loop helpers, and MCP server templates.

Claude Code를 바로 쓸 수 있는 설치형 스킬 모음입니다. Windows PowerShell 을 우선 지원하고, macOS/Linux는 동일 파일을 그냥 `~/.claude/skills`에 복사해 쓸 수 있습니다.

## Included Skills

| Skill | Description | Requirements | Run setup? |
|------|-------------|--------------|-----------|
| `cli-agent-team` | Runs a Claude-led multi-agent workflow with optional `codex` and `agy` CLI workers. | Claude Code, Git, Bash, optional `codex` or `agy`, Node.js for `agy` pty bridge | Yes — `setup.sh` |
| `git-helper` | Drafts commit messages, PR descriptions, and branch names from repository context. | Claude Code | No |
| `code-review-ko` | Reviews code diffs in Korean with bug, security, performance, and maintainability focus. | Claude Code | No |

## Quick Start: 5 Minutes

### 1. Clone

```powershell
git clone https://github.com/nonplayer47361/claude-toolkit.git
cd claude-toolkit
```

macOS/Linux:

```bash
git clone https://github.com/nonplayer47361/claude-toolkit.git
cd claude-toolkit
```

### 2. Install Basic Skills

Windows PowerShell:

```powershell
.\scripts\install-skill.ps1 -SkillName git-helper
.\scripts\install-skill.ps1 -SkillName code-review-ko
```

macOS/Linux:

```bash
mkdir -p ~/.claude/skills
cp -R skills/git-helper ~/.claude/skills/
cp -R skills/code-review-ko ~/.claude/skills/
```

### 3. Use in Claude Code

```text
/git-commit       # Draft a commit message
/git-pr           # Draft a PR description
/git-branch       # Suggest branch names
/code-review-ko   # Review code in Korean
```

Restart Claude Code after installing skills if commands do not appear immediately.

## How It Works

`cli-agent-team` puts Claude in the orchestrator role:

1. Claude writes a TASK.md for each work item
2. Claude dispatches the task to codex or agy (or both in parallel)
3. The worker agent reads TASK.md, writes code, and produces REPORT.md
4. Claude reviews REPORT.md and commits approved changes
5. Scores accumulate — Claude gradually assigns more work to the better-performing agent per task type

Workers (`codex`, `agy`) are optional. Claude works alone if neither is installed.

## cli-agent-team

`cli-agent-team` is for projects that want Claude to orchestrate external coding agents such as `codex` or `agy`. It creates task files, dispatches work, collects reports, and verifies completion.

Install:

```powershell
.\scripts\install-skill.ps1 -SkillName cli-agent-team
```

macOS/Linux:

```bash
mkdir -p ~/.claude/skills
cp -R skills/cli-agent-team ~/.claude/skills/
```

Initialize a project:

```bash
bash skills/cli-agent-team/scripts/setup.sh
bash skills/cli-agent-team/scripts/setup.sh --status
```

Optional agent requirements:

- `codex`: required only when you want Codex CLI workers.
- `agy`: required only when you want Antigravity CLI workers.
- Node.js: required for `agy` on Windows because `mcp-servers/pty-bridge/run.js` provides the TTY bridge.
- Claude Code remains the required orchestrator and fallback.

Run agents (separate terminals):

```powershell
# 에이전트 워치 루프 실행 (처음 실행)
~\.claude\skills\cli-agent-team\scripts\agent-watch.ps1 -Agent codex -AuthMode full
~\.claude\skills\cli-agent-team\scripts\agent-watch.ps1 -Agent agy -AuthMode full

# 대시보드 (별도 터미널)
bash ~/.claude/skills/cli-agent-team/scripts/dashboard.sh --watch
```

## Documentation

- [Install Guide](docs/install-guide.md) — step-by-step installation
- [Skills Overview](docs/skills-overview.md) — per-skill usage and examples  
- [cli-agent-team Guide](docs/cli-agent-team-guide.md) — full multi-agent workflow

---

## 한국어 안내

### 포함된 스킬

| 스킬 | 설명 | 필요 도구 | setup.sh 필요 |
|------|------|----------|--------------| 
| `cli-agent-team` | Claude가 오케스트레이터, codex/agy가 작업자인 다중 에이전트 루프 | Claude Code, Git, Bash, Node.js(선택), codex/agy(선택) | Yes |
| `git-helper` | 커밋 메시지·PR 설명·브랜치 이름 자동 생성 | Claude Code | No |
| `code-review-ko` | 한국어 코드 리뷰 (버그·보안·성능·가독성) | Claude Code | No |

### 빠른 시작 (5분)

**1. 클론 및 설치**

Windows:
```powershell
git clone https://github.com/nonplayer47361/claude-toolkit.git
cd claude-toolkit
.\scripts\setup.ps1
```

macOS/Linux:
```bash
git clone https://github.com/nonplayer47361/claude-toolkit.git
cd claude-toolkit
bash scripts/setup.sh
```

**2. Claude Code 재시작**

**3. 사용**

```
/git-commit       # 커밋 메시지 생성
/git-pr           # PR 설명 작성
/git-branch       # 브랜치 이름 제안
/code-review-ko   # 한국어 코드 리뷰
```

### cli-agent-team (다중 에이전트)

codex 또는 agy가 있으면 다중 에이전트 루프를 사용할 수 있다.

```powershell
# 에이전트 데몬 시작
~\.claude\skills\cli-agent-team\scripts\agent-watch.ps1 -Agent codex -AuthMode full

# 대시보드 (별도 터미널)
bash ~/.claude/skills/cli-agent-team/scripts/dashboard.sh --watch
```

자세한 내용: [cli-agent-team 가이드](docs/cli-agent-team-guide.md)

### 문서

| 문서 | 내용 |
|------|------|
| [설치 가이드](docs/install-guide.md) | 단계별 설치 |
| [스킬 개요](docs/skills-overview.md) | 스킬별 사용법과 예시 |
| [cli-agent-team 가이드](docs/cli-agent-team-guide.md) | 다중 에이전트 전체 워크플로우 |

### 문제 신고

오류 발생 시 로그를 내보내서 이슈로 제출해 주세요:
```bash
bash scripts/export-issue.sh
```
생성된 `issue-report-*.txt` 파일을 [GitHub Issues](https://github.com/nonplayer47361/claude-toolkit/issues)에 첨부해 주세요.