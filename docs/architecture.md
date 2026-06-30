# cli-agent-team — Architecture Reference

This document describes how `cli-agent-team` works internally. It is intended for
contributors and advanced users who want to extend the system, debug unexpected
behavior, or understand the design decisions behind it.

---

## Table of Contents

1. [Overview](#overview)
2. [Full Execution Flow](#full-execution-flow)
3. [Modes of Operation](#modes-of-operation)
4. [Script Reference](#script-reference)
5. [Data Files Reference](#data-files-reference)
6. [Adaptive Scoring Algorithm](#adaptive-scoring-algorithm)
7. [pty-bridge (Windows agy Support)](#pty-bridge-windows-agy-support)
8. [Fallback Chain](#fallback-chain)
9. [ECC Pattern (Context Continuity)](#ecc-pattern-context-continuity)
10. [Security: AgentShield](#security-agentshield)
11. [Efficiency Tracking Pipeline](#efficiency-tracking-pipeline)
12. [Parallel Execution](#parallel-execution)
13. [Contributing to Internals](#contributing-to-internals)

---

## Overview

`cli-agent-team` puts Claude in the **orchestrator** role and treats external CLI
coding agents (`codex`, `agy`) as **workers**. Claude never writes production code
directly — it writes task specifications, dispatches them, reviews results, and
integrates approved changes.

```
                    ┌─────────────────────────────────┐
                    │   Claude Code (Orchestrator)     │
                    │                                 │
                    │  • plans tasks (PLAN.md)        │
                    │  • writes TASK.md               │
                    │  • reviews REPORT.md + diff     │
                    │  • commits approved work        │
                    │  • records scores               │
                    └───────────┬─────────────────────┘
                                │
               ┌────────────────┼────────────────┐
               ▼                ▼                ▼
         ┌──────────┐    ┌──────────┐    ┌──────────────┐
         │  codex   │    │   agy    │    │  (Claude     │
         │  (worker)│    │  (worker)│    │   fallback)  │
         └────┬─────┘    └────┬─────┘    └──────────────┘
              │               │
              └───────┬───────┘
                      ▼
              writes code / docs
              writes REPORT.md
```

Workers are **optional**. Claude operates alone if neither is installed.

---

## Full Execution Flow

```
User
 │
 ▼
Claude reads PLAN.md ──► selects next task ──► writes _agent_reports/<id>/TASK.md
                                                          │
                                            ┌─────────────▼─────────────┐
                                            │       dispatch.sh          │
                                            │                            │
                                            │  1. read .conf             │
                                            │  2. resolve CLI            │
                                            │  3. agy? → pty-bridge      │
                                            │  4. run worker headless    │
                                            │  5. write .task_meta.json  │
                                            └─────────────┬─────────────┘
                                                          │
                                              worker executes TASK.md
                                              writes REPORT.md
                                                          │
                                            ┌─────────────▼─────────────┐
                                            │        verify.sh           │
                                            │                            │
                                            │  check 1: scope            │
                                            │  check 2: AC checklist     │
                                            │  check 3: validation cmd   │
                                            │  check 4: evidence files   │
                                            │  check 5: AgentShield scan │
                                            └──────┬──────────┬──────────┘
                                                   │          │
                                                 PASS        FAIL
                                                   │          │
                                      ┌────────────┘          └───────────────┐
                                      ▼                                        ▼
                              record-score.sh                       Claude writes FEEDBACK.md
                              update .agent_scores.json                        │
                              append .agent_metrics.json              dispatch.sh (feedback mode)
                                      │
                                git commit
```

---

## Modes of Operation

### Direct Mode

Claude calls `dispatch.sh` directly via Bash. No daemon required. Suitable for
low-frequency tasks or single-agent setups.

```bash
bash ~/.claude/skills/cli-agent-team/scripts/dispatch.sh \
  codex T001 limited "$(pwd)" execute quality
```

### Daemon Mode

A persistent watcher process polls for work. Claude signals it via `trigger.sh`.
Best for active development sessions where tasks arrive frequently.

```
Terminal A ─── agent-watch.ps1 (codex)   # polls .pending_codex every 2s
Terminal B ─── agent-watch.ps1 (agy)     # polls .pending_agy every 2s
Terminal C ─── dashboard.sh --watch      # shows live status
Claude     ─── trigger.sh codex T001 ... # writes .pending_codex, waits for DONE
```

State files used in daemon mode:

```
.daemon_codex          marker: watcher is running
.pending_codex         trigger → watcher signal (contains task-id + mode)
.status_T001_codex     watcher writes: IN_PROGRESS → DONE / ERROR_*
```

### Loop Mode

For fully autonomous runs. Claude uses `ScheduleWakeup` to survive rate-limit
resets. `.session_state` is updated before each major step so the loop can resume
from exactly the right point after a restart.

---

## Script Reference

All scripts live in `skills/cli-agent-team/scripts/`.

### dispatch.sh

**Entry point for running a worker agent.**

```
dispatch.sh <cli> <task-id> <auth-mode> [project-dir] [mode] [model-tier]

cli        : codex | agy | auto
task-id    : matches _agent_reports/<task-id>/
auth-mode  : limited | full
mode       : execute (default) | review | feedback
model-tier : quality (default) | fast
```

Internal steps:

1. Source `.cli-agent-team.conf` to get `CODEX_ENABLED`, `AGY_ENABLED`, bin paths
2. Resolve the actual CLI (`auto` picks best available)
3. Record `_ORIGINAL_CLI` before any fallback overwrites it
4. For `agy` on Windows: prepend `node pty-bridge/run.js --`
5. Build the prompt from `TASK.md` + mode template
6. Run the worker headless (`run_in_background` or direct exec)
7. Write `.task_meta.json` with `{task_id, agent, task_type, date, started_ts, elapsed_sec, tokens_used, fallback_used}`

### verify.sh

**Five-point verification gate after a worker completes.**

Checks in order:

| # | Check | Failure code |
|---|-------|-------------|
| 1 | Scope — only allowed files were modified | `SCOPE_VIOLATION` |
| 2 | AC checklist — no `- [ ]` remaining in REPORT.md | `AC_INCOMPLETE` |
| 3 | Validation command — runs `syntax-check` from `AGENT_ROLES.md` | `VERIFY_CMD_FAIL` |
| 4 | Evidence files — each `## 완료 증거 파일` entry exists and changed | `FILE_MISSING` |
| 5 | Security — `agent-shield.sh` finds no violations | `SEC_PATTERN` |

On **pass**: updates `.task_meta.json` with LOC diff and AC counts, then calls
`record-score.sh` with the 6th `task-dir` argument so metrics are accumulated.

On **fail**: calls `record-score.sh` *without* `task-dir` (metrics stay unwritten
until a clean pass), sets `FAIL_REASON` env var, writes error to status file.

### record-score.sh

**Accumulates agent performance data.**

```
record-score.sh <agent> <task_type> <ac_pass> <ac_fail> [project-dir] [task-dir]
```

Two writes per call:

1. **`.agent_scores.json`** — aggregated AC pass/fail counts per `agent × task_type`.
   Protected by `flock` (Linux/macOS) or `mkdir` spin-lock (Windows/no-flock).
2. **`.agent_metrics.json`** — appends the raw `.task_meta.json` record as a new
   element. Only written when `task-dir` (6th arg) is provided, ensuring only
   verified tasks are counted.

Valid `task_type` values (14 total):
`shell_scripting`, `documentation`, `code_implementation`, `testing`, `refactoring`,
`ui_component`, `styling`, `api_backend`, `database`, `security`,
`devops`, `config`, `data_processing`, `analysis`

### agent-watch.ps1 / agent-watch.sh

**Daemon watcher — polls for work and fires dispatch.sh.**

Loop logic (every 2 seconds):

```
write .daemon_<agent>
loop:
  if .pending_<agent> exists:
    read task-id + mode from file
    rm .pending_<agent>
    write .status_<task-id>_<agent> = IN_PROGRESS
    dispatch.sh <agent> <task-id> ...
    write .status_<task-id>_<agent> = DONE | ERROR_*
  sleep 2
on exit:
  rm .daemon_<agent>
```

### trigger.sh

**Sends a task to the daemon watcher and waits for completion.**

```
trigger.sh <agent> <task-id> <mode> [project-dir] [model-tier]
```

1. Checks `.daemon_<agent>` exists (errors if not)
2. Writes `<task-id> <mode>` to `.pending_<agent>`
3. Polls `.status_<task-id>_<agent>` until `DONE` or `ERROR_*`
4. Exits with appropriate code

### dashboard.sh

**ASCII status display for daemons and tasks.**

```bash
dashboard.sh              # one-shot snapshot
dashboard.sh --verbose    # include task details
dashboard.sh --watch      # live: refresh clock every second, redraw on fs change
```

Reads `_agent_reports/` directly — no server required. Status inference:

- `.status_<id>_<agent>` file present → use its value
- `REPORT.md` present, no unchecked AC → `DONE`
- `TASK.md` present, no REPORT.md → `PENDING`

### parallel-check.sh

**Safety gate before dispatching two tasks simultaneously.**

```bash
parallel-check.sh <task-id-a> <task-id-b> [project-dir]
# exit 0 = safe to run in parallel
# exit 1 = conflict detected
```

Checks:
- Neither task has an incomplete prerequisite in PLAN.md
- The `## 허용 파일` (allowed files) sections of the two TASK.md files do not overlap
- `AGENT_ROLES.md` has `병렬 실행: 허용`

### worktree-dispatch.sh

**Runs a task in an isolated git worktree for parallel safety.**

Each parallel task gets its own branch and working directory. On completion,
changes are `rsync --delete`-merged back into the main tree. On failure or
interrupt, `trap EXIT` removes the worktree automatically.

### agent-shield.sh

**Security scanner — 7 categories.**

```bash
agent-shield.sh [project-dir] [task-id]
# exit 0 = clean
# exit 1 = violations found (printed to stdout for verify.sh to capture)
```

Categories:

| # | Category | Example patterns |
|---|----------|-----------------|
| 1 | Hardcoded secrets | `API_KEY=`, `PASSWORD=`, `token =` |
| 2 | Dangerous eval | `` eval $() ``, `eval "$(...)"`  |
| 3 | Destructive commands | `rm -rf /`, `git reset --hard` without guard |
| 4 | Overly permissive chmod | `chmod 777` |
| 5 | Hardcoded absolute paths | `/home/username/`, `C:\Users\specific` |
| 6 | Excessive permissions | `sudo` without necessity |
| 7 | Sensitive file patterns | `.env`, `id_rsa`, `credentials.json` written by worker |

### daily-review.sh

**Generates a daily efficiency report from accumulated metrics.**

```bash
daily-review.sh [project-dir] [YYYY-MM-DD]
# output: <project-dir>/daily/YYYY-MM-DD.md
```

Reads `.agent_metrics.json`, filters by date, produces:
- Summary table: agent × tasks, AC pass rate, total tokens, tokens/task, avg elapsed, LOC, tokens/LOC
- Task-type breakdown
- Individual task records
- Next-session routing recommendations

`agy` token counts show `—(미수집)` because agy does not emit a parseable token
usage line. A `_extract_tokens()` hook in `dispatch.sh` can be extended once agy
adds structured output.

### analyze-limits.sh

**Identifies rate-limit time-of-day patterns from LOG.md.**

Reads `_agent_reports/LOG.md` for `[LIMIT]` entries, groups by hour, and prints a
frequency table. Claude uses this at dispatch time to deprioritize agents that
historically hit limits in the current time window.

### probe-cli.sh

**Validates that a CLI agent actually works in headless mode.**

```bash
probe-cli.sh <cli-name> <auth-mode>
```

Two tests:
1. Trivial text response — checks exit code and that stdout contains a plausible answer
2. Trivial file write — confirms a file was actually created (stdout silence is normal for agy)

Run this before committing to an auth-mode assumption in a new environment.

### update-state.sh

**Updates a single field in `.session_state`.**

```bash
update-state.sh "루프 상태" "단계 5 완료 대기" [project-dir]
update-state.sh "다음 행동" "T003 배정 (codex)" [project-dir]
```

Called by Claude before and after each major loop step so that a new session can
resume from exactly the right point without re-reading the full conversation.

### hooks/session-start.sh

**ECC entry point — runs when a Claude Code session starts.**

Reads `.session_state` and emits it as a user-visible message so Claude's context
is immediately populated with the loop's current position, pending task, and
blocked items.

### hooks/pre-compact.sh

**ECC exit point — runs before Claude Code compacts the conversation.**

Saves the current loop state, active task, and any important notes to
`.session_state` before the context window shrinks.

---

## Data Files Reference

```
_agent_reports/
│
├── .cli-agent-team.conf        Agent configuration (auto-generated by setup.sh)
│                               CODEX_ENABLED, CODEX_BIN, AGY_ENABLED, AGY_BIN
│
├── .session_state              Loop resume file (plain text key: value)
│                               Fields: 갱신, 마일스톤, 다음 행동, 루프 상태,
│                                       BLOCKED, 루프 모드, 리셋 주기, 루프 프롬프트
│
├── .agent_scores.json          Aggregated AC scores (schema version 2)
│                               Structure: {agents: {agy|codex: {<task_type>:
│                                 {ac_pass, ac_fail, total}, fail_reasons: {...}}}}
│
├── .agent_metrics.json         Raw per-task records (flat JSON array)
│                               Each element mirrors .task_meta.json fields
│
├── .daemon_codex               Empty marker file; exists while watcher runs
├── .daemon_agy
│
├── .pending_codex              Signal file written by trigger.sh
│                               Content: "<task-id> <mode> <model-tier>"
├── .pending_agy
│
├── .status_<task-id>_<agent>   One-line status written by daemon watcher
│                               Values: IN_PROGRESS | DONE | ERROR_AC |
│                                       ERROR_TEST | ERROR_TIMEOUT
│
├── LOG.md                      Append-only event log
│                               log-event.sh writes tagged lines:
│                                 [LIMIT], [DISPATCH], [VERIFY], [COMMIT], [GATE]
│
├── SHARED_TASK_NOTES.md        Cross-iteration context bridge
│                               Workers append key decisions here after each task.
│                               Reads are prepended to the next worker's prompt.
│                               Write protected by flock to prevent concurrent corruption.
│
└── <task-id>/
    ├── TASK.md                 Written by Claude before dispatch
    │                           Required sections: 담당, 작업 지시, 완료 기준, 허용 파일, 완료 증거 파일
    │                           Optional frontmatter: task_type (enables adaptive scoring)
    │
    ├── TODO.md                 Written by worker immediately after reading TASK.md
    │                           Sub-task checklist; updated as work proceeds
    │
    ├── REPORT.md               Written by worker on completion
    │                           MUST contain "## AC 체크리스트" with all items checked [x]
    │
    ├── FEEDBACK.md             Written by Claude on verify failure
    │                           Lists specific deficiencies for the worker to address
    │
    ├── REVIEW.md               Written by worker in "review" mode
    │                           No code changes; observations and recommendations only
    │
    └── .task_meta.json         Written by dispatch.sh, updated by verify.sh
                                {task_id, agent, task_type, date,
                                 started_ts, elapsed_sec, tokens_used, fallback_used,
                                 loc_added, loc_deleted, ac_pass, ac_fail}
```

---

## Adaptive Scoring Algorithm

Claude runs this logic at **step 1.6** of the orchestrator loop, after step 1.5
selects an agent based on rate-limit window data.

```
Input : .agent_scores.json, current task_type, candidate agents A and B

1. If .agent_scores.json does not exist → no adjustment, use step 1.5 result
2. Look up task_type entry for both agents
3. If either agent has < 5 samples for this task_type → no adjustment
4. Compute win rates:
     rate_A = ac_pass_A / (ac_pass_A + ac_fail_A)
     rate_B = ac_pass_B / (ac_pass_B + ac_fail_B)
5. If |rate_A - rate_B| < 0.15 (15 percentage points) → no adjustment
6. Assign to the agent with the higher win rate
   Log: "[적응형] task_type=X: agent_A 91% > agent_B 72% (19%p) → agent_A로 보정"
```

This algorithm is conservative by design: it only overrides the default routing
when there is clear statistical evidence (5+ samples, 15%p+ gap).

---

## pty-bridge (Windows agy Support)

`agy` requires a TTY to produce output. In a non-interactive shell (e.g. when
Claude Code calls Bash headlessly), there is no TTY, so `agy` writes nothing to
stdout even when it completes the task successfully.

**Solution: node-pty virtual terminal**

```
dispatch.sh
  └─ detects: CLI=agy, platform=Windows or no TTY
       └─ prepends: node ~/.claude/mcp-servers/pty-bridge/run.js --
            └─ run.js spawns agy inside a node-pty pseudo-terminal
                 └─ captures agy stdout/stderr and re-emits to dispatch.sh
```

File: `mcp-servers/pty-bridge/run.js` (Node.js ESM, stdio transport)

Requirements:
- Node.js ≥ 18
- `npm install` in `mcp-servers/pty-bridge/` (installs `node-pty`)

The bridge is transparent: dispatch.sh sees normal stdout/stderr. If agy is
upgraded to support non-TTY mode natively, remove the pty-bridge prefix from
`dispatch.sh`'s agy execution block.

---

## Fallback Chain

When a worker fails to produce usable output, dispatch.sh cascades:

```
Step 1: Try assigned agent (e.g. agy)
        │
        ├─ exit 0 + REPORT.md present → SUCCESS
        │
        ├─ exit 2 (agy-specific "no output" signal) → Step 2
        │
        └─ exit other / timeout → Step 3

Step 2: Retry with codex
        │
        ├─ REPORT.md present → SUCCESS (fallback_used=true in .task_meta.json)
        │
        └─ fail → Step 3

Step 3: Claude handles the task directly
        (logged in .task_meta.json as agent="claude-direct")
```

The variable `_ORIGINAL_CLI` preserves the first-attempt agent before any fallback
overwrites `CLI`. This ensures `.task_meta.json` records the originally assigned
agent, not the fallback — important for accurate scoring.

---

## ECC Pattern (Context Continuity)

**ECC = External Context Continuity**. Inspired by error-correcting codes: inject
redundant state at known points so any single interruption can be recovered.

```
Session N:
  [session-start.sh fires]
      │
      └─► reads .session_state
          emits current loop position to Claude context
              │
              Claude works …
              update-state.sh called at each major step
              │
  [pre-compact.sh fires before context window shrinks]
      │
      └─► writes current state to .session_state

Session N+1 (after rate limit / restart):
  [session-start.sh fires]
      └─► reads .session_state → Claude continues from exact step
```

`.session_state` key fields:

```
갱신: 2026-06-30 14:23 (Asia/Seoul)
마일스톤: M2 — 인증 구현
다음 행동: T007 배정 (codex · 소형 · JWT 미들웨어 추가)
루프 상태: 단계 1 대기
BLOCKED: (없음)
루프 모드: manual
리셋 주기: 0
루프 프롬프트: cli-agent-team
```

Hook registration (done once per project by init.sh or setup.sh):

```json
// .claude/settings.json
{
  "hooks": {
    "PreToolUse": [{ "matcher": "", "hooks": [{ "type": "command",
      "command": "bash ~/.claude/skills/cli-agent-team/scripts/hooks/session-start.sh" }] }],
    "PreCompact":  [{ "matcher": "", "hooks": [{ "type": "command",
      "command": "bash ~/.claude/skills/cli-agent-team/scripts/hooks/pre-compact.sh" }] }]
  }
}
```

---

## Security: AgentShield

AgentShield runs as check #5 in `verify.sh`. It scans **only the diff introduced
by the current task** (files listed in TASK.md's allowed-files section), not the
entire repo.

Scan scope is intentionally narrow to avoid false positives from pre-existing code.
The 7 categories are designed around the most common ways a hallucinating or
prompt-injected worker agent causes damage:

1. **Secrets exposure** — accidentally committing API keys already in the codebase
2. **eval injection** — constructing executable strings from user input
3. **Destructive shell** — `rm -rf` or `git reset --hard` in scripts without safeguards
4. **Over-permissive files** — `chmod 777` making files world-writable
5. **Environment coupling** — hardcoded absolute paths that break on other machines
6. **Privilege escalation** — unnecessary `sudo` in automation scripts
7. **Sensitive file writes** — worker creating `.env`, private keys, or credential files

Exit code 0 = no violations. verify.sh treats exit 1 as `SEC_PATTERN` failure and
routes to FEEDBACK.md for the worker to fix.

---

## Efficiency Tracking Pipeline

```
dispatch.sh
    └─► writes .task_meta.json
        {task_id, agent, task_type, date, started_ts, elapsed_sec,
         tokens_used (codex only), fallback_used}

verify.sh (on pass)
    └─► updates .task_meta.json
        adds: loc_added, loc_deleted, ac_pass, ac_fail

record-score.sh (called by verify.sh on pass, with task-dir arg)
    └─► appends .task_meta.json → .agent_metrics.json

daily-review.sh (run manually or via cron)
    └─► reads .agent_metrics.json
        filters by date
        outputs daily/YYYY-MM-DD.md
```

Token extraction is agent-specific. `_extract_tokens()` in dispatch.sh currently
supports `codex` (parses "tokens used" lines) and returns `null` for `agy` (no
structured output). To add a new agent's token parsing, extend the `case` block
in `_extract_tokens()`.

---

## Parallel Execution

```
Claude selects T-A and T-B as independent tasks
            │
            ▼
parallel-check.sh T-A T-B
  checks: no file overlap, no unmet dependencies, AGENT_ROLES.md allows parallel
            │
         ┌──▼───┐
         │ pass │
         └──┬───┘
            │
   ┌─────────▼──────────┐
   │  worktree-dispatch  │   (one per task)
   │  creates branch     │
   │  isolates changes   │
   └──────┬──────────────┘
          │
   ┌──────▼──────┐   ┌──────▼──────┐
   │  codex/T-A  │   │  agy/T-B    │   ← run concurrently
   └──────┬──────┘   └──────┬──────┘
          │                 │
      REPORT.md         REPORT.md
          │                 │
   verify individually      │
          │                 │
   both pass ──────────────►│
          │
   rsync --delete → main tree
          │
   single git commit (both tasks)
```

The `rsync --delete` merge ensures that file deletions and renames made by the
worker are reflected in the main tree, not just additions (which a naive `cp`
would miss).

---

## Contributing to Internals

### Adding a new script

1. Place it in `skills/cli-agent-team/scripts/`.
2. Use `#!/usr/bin/env bash` and `set -euo pipefail`.
3. Use `command -v <tool>` not `which` for portability.
4. Write no intermediate `grep | grep | awk` chains — use `awk` alone to avoid
   pipefail exits on zero-match greps.
5. Every `jq -r '...' | while` pipeline must end with `|| true` for pipefail safety.
6. Accept `[project-dir]` as a positional argument (default: `$(pwd)`). Never
   use `../..` relative navigation — it breaks after `install-skill.ps1` copies
   the skill to `~/.claude/skills/`.
7. Add the script to `docs/architecture.md` (this file) Script Reference section.

### Adding a new agent

1. Add its name to `VALID_AGENTS` in `record-score.sh`.
2. Add initial schema entries for all 14 task types in `INITIAL_SCHEMA`.
3. Add a detection block in `setup.sh` and `setup.ps1`.
4. Add a token extraction case in `_extract_tokens()` in `dispatch.sh`.
5. Add pty-bridge handling in `dispatch.sh` if the agent needs TTY.
6. Document known quirks in `references/agent-characteristics.md`.

### Adding a new task_type

1. Add to `VALID_TASK_TYPES` in `record-score.sh`.
2. Add zero-initialized entries in `INITIAL_SCHEMA` for both `agy` and `codex`.
3. Document in `references/agent-characteristics.md` under routing recommendations.

### Modifying verify.sh checks

- Checks run in order 1–5. A failure in check N skips checks N+1 through 5
  (except security, which always runs).
- Each check sets `FAIL_REASON` and calls `record-score.sh` without `task-dir`
  so the failed task is not counted in metrics.
- The comment `# 실패 경로: task-dir(6번째 인수) 미전달 — 설계 의도` marks
  intentional omissions of the 6th arg. Do not add it to failure paths.

### File encoding

All shell scripts use UTF-8. On Windows, run `chcp 65001` before invoking Bash
scripts in a PowerShell terminal. PowerShell scripts use
`[System.Text.UTF8Encoding]::new($false)` (UTF-8 without BOM) for file writes.

### Lock file hygiene

`record-score.sh` uses `flock` when available, falls back to `mkdir` spin-lock.
Both mechanisms register an `EXIT` trap via `release_scores_lock`. Do not add
additional `EXIT` traps in scripts that call `record-score.sh` — they will
interfere. Use `trap - EXIT` to clear before returning if needed.

---

*Last updated: 2026-06-30*
