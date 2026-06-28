# Install Guide

This guide installs `claude-toolkit` skills for Claude Code. Windows PowerShell is the primary path; macOS/Linux commands are included where they differ.

## 1. Prerequisites

Check the required tools:

```powershell
git --version
claude --version
```

For `cli-agent-team`, also check optional worker tools:

```powershell
codex --version
agy --version
node --version
```

Requirements:

- Git is required to clone the repository.
- Claude Code CLI is required to use the installed skills.
- Node.js is required only for `cli-agent-team` when using `agy` through the pty bridge.
- `codex` and `agy` are optional. Install at least one only if you want external worker agents.
- Bash is required for `cli-agent-team` scripts. On Windows, use Git Bash or WSL if `bash` is not available in PowerShell.

## 2. Install Skills

Clone the repository:

```powershell
git clone https://github.com/<username>/claude-toolkit.git
cd claude-toolkit
```

Install simple Claude Code skills on Windows:

```powershell
.\scripts\install-skill.ps1 -SkillName git-helper
.\scripts\install-skill.ps1 -SkillName code-review-ko
```

Install `cli-agent-team` on Windows:

```powershell
.\scripts\install-skill.ps1 -SkillName cli-agent-team
```

Install skills on macOS/Linux:

```bash
git clone https://github.com/<username>/claude-toolkit.git
cd claude-toolkit
mkdir -p ~/.claude/skills
cp -R skills/git-helper ~/.claude/skills/
cp -R skills/code-review-ko ~/.claude/skills/
cp -R skills/cli-agent-team ~/.claude/skills/
```

Project-local install on Windows:

```powershell
.\scripts\install-skill.ps1 -SkillName git-helper -ProjectPath C:\projects\my-app
```

After installation, restart Claude Code if newly installed commands are not detected.

## 3. Run cli-agent-team setup.sh

From a project that should use the multi-agent loop, run:

```bash
bash skills/cli-agent-team/scripts/setup.sh
```

Check the detected agent configuration:

```bash
bash skills/cli-agent-team/scripts/setup.sh --status
```

Disable or enable optional agents:

```bash
bash skills/cli-agent-team/scripts/setup.sh --disable-codex
bash skills/cli-agent-team/scripts/setup.sh --disable-agy
bash skills/cli-agent-team/scripts/setup.sh --enable-codex
bash skills/cli-agent-team/scripts/setup.sh --enable-agy
```

The setup script writes `_agent_reports/.cli-agent-team.conf`. The important fields are:

- `CODEX_ENABLED=true`: `codex` was found and is enabled.
- `AGY_ENABLED=true`: `agy` was found and is enabled.
- `CLAUDE_ENABLED=true`: Claude remains available as orchestrator and fallback.

## 4. Run the First Test Task

Create a task directory:

```bash
mkdir -p _agent_reports/T001
```

Create `_agent_reports/T001/TASK.md`:

```markdown
# T001: Documentation smoke test

## Goal

Confirm that the agent loop can read a task and produce a report without changing source code.

## Allowed Files

- _agent_reports/T001/REPORT.md

## Acceptance Criteria

- [ ] REPORT.md exists
- [ ] REPORT.md contains an AC checklist
```

Run directly with `dispatch.sh`:

```bash
bash skills/cli-agent-team/scripts/dispatch.sh codex T001 limited "$(pwd)" execute quality
```

If you use watcher mode, start the dashboard in another terminal:

```bash
bash skills/cli-agent-team/scripts/dashboard.sh --watch
```

Then trigger a watched agent:

```bash
bash skills/cli-agent-team/scripts/trigger.sh codex T001 execute "$(pwd)" quality
```

Use `agy` instead of `codex` only when `agy` is installed and enabled.

## 5. Troubleshooting

`bash: command not found` on Windows:

```powershell
winget install Git.Git
```

Then open Git Bash or use WSL.

Skill commands do not appear in Claude Code:

```powershell
Get-ChildItem $env:USERPROFILE\.claude\skills
```

Restart Claude Code after confirming the skill directory exists.

Korean text appears broken:

```powershell
chcp 65001
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8
```

`cli-agent-team` cannot find `codex` or `agy`:

```bash
which codex
which agy
bash skills/cli-agent-team/scripts/setup.sh --status
```

`agy` returns no output in a non-TTY environment:

```bash
node mcp-servers/pty-bridge/run.js -- agy --help
```

Use the pty bridge for `agy` worker execution on Windows when direct non-interactive output is empty.
