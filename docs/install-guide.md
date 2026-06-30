# Install Guide

This guide installs `claude-toolkit` skills for Claude Code. Windows PowerShell is the primary path; macOS/Linux commands are included where they differ.

## 0. One-liner Install (Recommended)

Skip cloning entirely — run one command and restart Claude Code.

**Windows:**
```powershell
irm https://raw.githubusercontent.com/nonplayer47361/claude-toolkit/main/scripts/install.ps1 | iex
```

**macOS / Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/nonplayer47361/claude-toolkit/main/scripts/install.sh | bash
```

The rest of this guide covers manual installation and advanced setup.

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

## 2.5. pty-bridge 의존성 설치 (agy 사용 시 필수)

`agy`를 Windows에서 사용하려면 pty-bridge의 Node.js 의존성을 설치해야 한다.

```bash
cd mcp-servers/pty-bridge
npm install
cd ../..
```

`npm install`이 완료되면 `mcp-servers/pty-bridge/node_modules/node-pty/` 디렉터리가 생성된다.
`scripts/setup.ps1`(또는 `setup.sh`)을 사용하면 이 단계가 자동으로 처리된다.

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

## 3.5 (선택) ECC 세션 연속성 훅 등록

ECC(Extended Context Continuity) 패턴은 세션이 새로 시작될 때와 컨텍스트 압축 직전에
`.session_state`를 자동으로 Claude에 주입한다. 이를 활성화하려면 `~/.claude/settings.json`에
훅을 등록해야 한다.

**등록 방법 (수동)**

`~/.claude/settings.json`을 열어 아래를 추가한다:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/skills/cli-agent-team/scripts/hooks/session-start.sh"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/skills/cli-agent-team/scripts/hooks/pre-compact.sh"
          }
        ]
      }
    ]
  }
}
```

기존 `settings.json`에 다른 설정이 있으면 `"hooks"` 블록만 병합한다.
등록 후 Claude Code를 재시작하면 다음 세션부터 `.session_state`가 자동으로 주입된다.

> ECC 훅 없이도 cli-agent-team은 정상 동작한다. 훅은 세션 재개 시 이전 상태를
> 자동으로 불러오는 편의 기능이며, 등록하지 않으면 새 세션마다 수동으로 "계속"을 입력해야 한다.

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

**다른 프로젝트에서 watcher를 실행하는 경우** `-ProjectDir`를 명시한다:

```powershell
~\.claude\skills\cli-agent-team\scripts\agent-watch.ps1 `
  -Agent codex `
  -AuthMode limited `
  -ProjectDir "C:\path\to\my-project"
```

`-ProjectDir`를 생략하면 PowerShell의 **현재 작업 디렉터리**를 프로젝트 루트로 인식한다.
claude-toolkit 디렉터리가 아닌 실제 프로젝트 디렉터리에서 실행하거나, `-ProjectDir`를 명시해야 한다.

## 5. 설치 후 첫 5분

설치가 완료됐으면 아래 순서로 동작을 확인한다.

### git-helper 확인

임의의 git 저장소에서 Claude Code를 열고:
```
커밋 메시지 써줘
```
Claude가 `git diff --staged`를 읽고 커밋 메시지 초안을 제시하면 정상이다.

### code-review-ko 확인

```
코드 리뷰해줘
```
Claude가 현재 diff를 한국어로 리뷰하면 정상이다.

### cli-agent-team 첫 실행 (선택)

```bash
# 1. 에이전트 설정 확인
bash ~/.claude/skills/cli-agent-team/scripts/setup.sh --status

# 2. 대시보드 시작
bash ~/.claude/skills/cli-agent-team/scripts/dashboard.sh --watch
```

다중 에이전트 루프는 [cli-agent-team 가이드](cli-agent-team-guide.md)를 참고한다.

## 6. Troubleshooting

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
