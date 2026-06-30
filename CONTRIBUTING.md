# Contributing to claude-toolkit

**환영합니다 / Welcome!**

Any contribution is appreciated — bug reports, documentation fixes, new skills, or script improvements. This project is built for the vibe-coding community; the more people shape it, the better it gets.

---

## Ways to Contribute / 기여 방법

- **Bug reports** — open a GitHub Issue and attach the output of `bash scripts/export-issue.sh`
- **Feature suggestions** — open an Issue describing the use case
- **Documentation** — fix typos, clarify steps, translate sections
- **New skills** — add a reusable Claude Code skill under `skills/`
- **Script fixes** — patch bugs in the Bash/PowerShell scripts
- **Tests** — extend `scripts/cli-agent-team/scripts/run_failure_tests.sh`

---

## Development Setup / 개발 환경

**Required:**

| Tool | Purpose |
|------|---------|
| Claude Code CLI | Running skills |
| Git + Bash | Version control; Git Bash on Windows |
| Node.js | `pty-bridge` for agy on Windows |
| jq | `record-score.sh` adaptive scoring |

**Optional (for multi-agent features):**

- `codex` — OpenAI Codex CLI worker
- `agy` — Antigravity CLI worker

**Clone:**

```bash
git clone https://github.com/nonplayer47361/claude-toolkit.git
cd claude-toolkit
```

**Install all skills locally for testing:**

```powershell
# Windows
.\scripts\setup.ps1
```

```bash
# macOS / Linux
bash scripts/setup.sh
```

---

## Project Structure / 프로젝트 구조

```
claude-toolkit/
├── skills/
│   ├── cli-agent-team/
│   │   ├── SKILL.md          # Skill entrypoint (Claude reads this)
│   │   ├── scripts/          # Bash scripts (dispatch, verify, etc.)
│   │   └── references/       # Reference docs for Claude
│   ├── git-helper/
│   └── code-review-ko/
├── mcp-servers/
│   └── pty-bridge/           # Node.js TTY bridge for agy on Windows
├── scripts/
│   ├── install.ps1           # One-liner installer (Windows)
│   ├── install.sh            # One-liner installer (macOS/Linux)
│   ├── install-skill.ps1     # Per-skill installer
│   └── setup.ps1             # Full install after git clone
└── docs/                     # Usage guides
```

---

## Adding a New Skill / 새 스킬 추가

1. Create `skills/<name>/SKILL.md` with frontmatter `name` and `description` fields.
2. Add any supporting scripts under `skills/<name>/scripts/`.
3. Test the install: `.\scripts\install-skill.ps1 -SkillName <name>`
4. Add a row to the skills table in `README.md`.
5. Open a PR.

Minimum `SKILL.md` structure:

```markdown
---
name: my-skill
description: One-line description shown in Claude Code
---

# My Skill

Describe what Claude should do when this skill is invoked.
```

---

## Script Guidelines / 스크립트 규칙

All Bash scripts must follow these rules:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

| Rule | Detail |
|------|--------|
| `command -v` not `which` | POSIX-portable tool detection |
| `\|\| true` on grep/awk pipes | Prevent pipefail on zero-match exits |
| `jq` optional | Check `command -v jq` before use; skip gracefully if absent |
| No hardcoded paths | Use function arguments or environment variables |
| No hardcoded secrets | API keys, tokens, passwords must never appear in source |
| No `eval` | Prevents code injection |

Run a syntax check before committing:

```bash
bash -n skills/cli-agent-team/scripts/<changed-file>.sh
```

---

## Pull Request Process / PR 절차

1. **Open an Issue first** for significant changes (new skill, architecture change).
2. Fork the repo and create a branch: `feat/`, `fix/`, or `docs/` prefix.
3. Make changes, run `bash -n` on any modified scripts.
4. Use Conventional Commit format for the PR title:
   - `feat: add X skill`
   - `fix: handle empty jq output in record-score.sh`
   - `docs: clarify pty-bridge setup for macOS`
5. In the PR description, explain **what** changed and **why**.

---

## Reporting Bugs / 버그 리포트

Open a [GitHub Issue](https://github.com/nonplayer47361/claude-toolkit/issues) and include the output of:

```bash
bash scripts/export-issue.sh
```

This generates an `issue-report-*.txt` with environment info and recent logs.

---

## Code of Conduct

Be respectful, constructive, and kind. Disagreements about approach are fine — personal attacks are not. We're here to build useful tools together.
