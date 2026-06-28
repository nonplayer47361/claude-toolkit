# claude-toolkit

Reusable Claude Code skills, agent-loop helpers, and MCP server templates.

Claude Code에서 바로 복사해 설치할 수 있는 스킬 모음입니다. Windows PowerShell 사용을 우선 지원하고, macOS/Linux에서는 같은 디렉터리 구조를 `~/.claude/skills`로 복사해 사용할 수 있습니다.

## Included Skills

| Skill | Description | Requirements |
|------|-------------|--------------|
| `cli-agent-team` | Runs a Claude-led multi-agent workflow with optional `codex` and `agy` CLI workers. | Claude Code, Git, Bash, optional `codex` or `agy`, Node.js for `agy` pty bridge |
| `git-helper` | Drafts commit messages, PR descriptions, and branch names from repository context. | Claude Code |
| `code-review-ko` | Reviews code diffs in Korean with bug, security, performance, and maintainability focus. | Claude Code |

## Quick Start: 5 Minutes

### 1. Clone

```powershell
git clone https://github.com/<username>/claude-toolkit.git
cd claude-toolkit
```

macOS/Linux:

```bash
git clone https://github.com/<username>/claude-toolkit.git
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

See [docs/install-guide.md](docs/install-guide.md) for detailed installation steps and [docs/skills-overview.md](docs/skills-overview.md) for per-skill usage.
