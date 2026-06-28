# Skills Overview

## git-helper

Purpose: generate practical Git text from repository context.

Common scenarios:

- Draft a Conventional Commit message from staged changes.
- Draft a pull request description from commits and diff stats.
- Suggest short branch names for a task.

Trigger commands:

```text
/git-commit
/git-pr
/git-branch
```

Example output:

```text
docs(readme): add installation quick start

Explains basic skill installation and links to the detailed guide.
```

## code-review-ko

Purpose: review diffs or selected files in Korean, prioritizing bugs and actionable risk.

Common scenarios:

- Review the current branch before opening a PR.
- Review staged changes before committing.
- Review one sensitive file, such as authentication or deployment code.

Trigger command:

```text
/code-review-ko
```

Example output:

```text
## 코드 리뷰 - 현재 diff

### 필수 수정
- 버그/보안 이슈 없음.

### 권장 개선
- README의 설치 명령에 macOS/Linux 경로를 함께 표시하면 온보딩이 쉬워집니다.
```

## cli-agent-team

Purpose: let Claude coordinate external CLI coding agents through task files, reports, and verification.

Common scenarios:

- Split implementation and review work between Claude and `codex`.
- Run `agy` for documentation or repetitive report work through a TTY bridge.
- Track task status with `_agent_reports/<task-id>/TASK.md`, `TODO.md`, and `REPORT.md`.

Primary scripts:

```bash
bash skills/cli-agent-team/scripts/setup.sh
bash skills/cli-agent-team/scripts/setup.sh --status
bash skills/cli-agent-team/scripts/dispatch.sh codex T001 limited "$(pwd)" execute quality
bash skills/cli-agent-team/scripts/trigger.sh codex T001 execute "$(pwd)" quality
bash skills/cli-agent-team/scripts/dashboard.sh --watch
```

Example setup output:

```text
[cli-agent-team] setup
================================================================
감지 결과:
  codex   v /usr/local/bin/codex   ENABLED
  agy     x 미설치 -> DISABLED
  claude  v (항상 활성)

설정 파일 저장: _agent_reports/.cli-agent-team.conf
================================================================
```

Notes:

- `codex` and `agy` are optional workers, not mandatory dependencies.
- Node.js is required for the `agy` pty bridge on Windows.
- Claude Code remains the orchestrator even when no optional worker is enabled.
