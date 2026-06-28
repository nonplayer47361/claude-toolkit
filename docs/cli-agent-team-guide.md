# CLI Agent Team 사용 가이드

`cli-agent-team`은 Claude가 오케스트레이터가 되고 codex, agy 같은 외부 CLI
에이전트가 작업자로 움직이는 프로젝트 운영 방식이다. Claude는 계획, 배정, 검토, 통합을
담당하고 작업자는 허용된 파일만 수정한 뒤 `_agent_reports/<task-id>/REPORT.md`로
결과를 보고한다.

이 문서는 처음 사용하는 사람이 설치부터 실제 운영까지 한 파일만 보고 진행할 수 있도록
전체 흐름을 정리한다.

## 1. 개념: How It Works

```text
User -> Claude (Orchestrator)
             |
             +--> codex (worker) -> REPORT.md
             |
             +--> agy   (worker) -> REPORT.md
             |
             +--> Claude (Review & Integrate)
```

- Claude = 뇌. 작업을 고르고, TASK.md를 쓰고, 에이전트를 배정하고, REPORT.md와 diff를
  검토한 뒤 통합한다.
- codex / agy = 손. 실제 코드 작성, 문서 작성, 파일 수정, 검증 실행, REPORT.md 작성을
  담당한다.
- codex와 agy는 선택 사항이다. 둘 중 하나만 있어도 되고, 둘 다 없어도 Claude 단독으로
  운영할 수 있다.
- 초기에는 작업을 균등하게 배정해도 된다. 이후 REPORT.md와 점수 파일의 결과가 쌓이면
  성공률이 높은 에이전트에 더 많이 배정한다.

## 2. 에이전트 옵션

| 구성 | 필요 도구 | 특징 |
| --- | --- | --- |
| Claude 단독 | Claude Code | 외부 CLI 없이 Claude가 직접 계획과 작업을 수행한다. |
| Claude + codex | Claude Code, codex | 코드 구현, 테스트, Bash 스크립트, 리팩터링에 적합하다. |
| Claude + agy | Claude Code, agy, Node.js | 문서, 주석, TODO, REPORT 작업에 적합하다. Windows에서는 TTY 브리지가 필요하다. |
| Claude + codex + agy | Claude Code, codex, agy, Node.js | 병렬 배정과 폴백 운영이 가능하다. codex 1개 + agy 1개까지만 병렬 실행한다. |

권장 역할은 프로젝트마다 `AGENT_ROLES.md`에 기록한다. 일반적으로 codex는 복잡한 구현과
테스트에, agy는 문서와 반복적인 정리 작업에 배정한다.

## 3. 설정: setup.sh

프로젝트 루트에서 실행한다.

```bash
bash ~/.claude/skills/cli-agent-team/scripts/setup.sh
```

이 스크립트는 codex와 agy 설치 여부를 감지하고 다음 설정 파일을 만든다.

```text
_agent_reports/.cli-agent-team.conf
```

출력 예시:

```text
[cli-agent-team] setup
================================================================
감지 결과:
  codex   ✅ /usr/local/bin/codex   ENABLED
  agy     ❌ 미설치 → DISABLED
  claude  ✅ (항상 활성)

설정 파일 저장: _agent_reports/.cli-agent-team.conf
================================================================
```

주요 플래그:

- `--status`: 현재 설정을 출력한다. 파일은 변경하지 않는다.
- `--disable-codex`: codex가 설치되어 있어도 비활성화한다.
- `--disable-agy`: agy가 설치되어 있어도 비활성화한다.
- `--enable-codex`: 기존 설정에서 codex를 다시 활성화한다.
- `--enable-agy`: 기존 설정에서 agy를 다시 활성화한다.

권한 모드는 setup과 별개다. `full`은 승인/샌드박스 우회가 필요한 모드이므로 현재
프로젝트에 대해 사용자가 명시적으로 동의한 경우에만 쓴다. 기본은 `limited`다.

## 4. 워크플로우: 직접 모드

직접 모드는 데몬 없이 한 번의 명령으로 작업자를 실행한다.

```text
1. Claude가 TASK.md 작성
   _agent_reports/T001/TASK.md

2. Claude가 dispatch.sh 실행
   bash ~/.claude/skills/cli-agent-team/scripts/dispatch.sh codex T001 limited . execute quality

3. codex가 TASK.md를 읽고 TODO.md, 작업 결과, REPORT.md 작성

4. Claude가 REPORT.md와 diff를 검토하고 검증 후 통합
```

명령 형식:

```bash
bash ~/.claude/skills/cli-agent-team/scripts/dispatch.sh <cli> <task-id> <auth-mode> [project-dir] [mode] [model-tier]
```

인자:

- `<cli>`: `codex`, `agy`, `auto`.
- `<task-id>`: `_agent_reports/<task-id>/` 디렉터리 이름.
- `<auth-mode>`: `full` 또는 `limited`.
- `[project-dir]`: 프로젝트 루트. 생략하면 현재 디렉터리.
- `[mode]`: `review`, `execute`, `feedback`. 기본값은 `execute`.
- `[model-tier]`: `fast` 또는 `quality`. 기본값은 `quality`.

모드별 의미:

- `review`: 작업자가 코드나 문서를 수정하지 않고 REVIEW.md만 작성한다.
- `execute`: 작업자가 TODO.md를 만들고 실제 작업을 수행한 뒤 REPORT.md를 작성한다.
- `feedback`: Claude가 작성한 FEEDBACK.md의 지적 사항만 반영한다.

## 5. 워크플로우: 데몬 모드

데몬 모드는 터미널 패널에 에이전트 watcher를 켜 두고, Claude가 `trigger.sh`로 작업을
전달하는 방식이다.

```text
1. 터미널 A: agent-watch.ps1 실행 후 대기
2. 터미널 B: dashboard.sh --watch 실행
3. Claude가 trigger.sh 실행
4. watcher가 즉시 작업을 수신하고 dispatch.sh 실행
5. 대시보드에서 PENDING -> IN_PROGRESS -> DONE 전환 확인
6. Claude가 REPORT.md 검토 및 검증
```

Windows에서 watcher 시작:

```powershell
cd "C:\path\to\project"
~\.claude\skills\cli-agent-team\scripts\agent-watch.ps1 -Agent codex -AuthMode limited
~\.claude\skills\cli-agent-team\scripts\agent-watch.ps1 -Agent agy -AuthMode limited
```

다른 디렉터리에서 실행해야 하면 `-ProjectDir`를 명시한다.

```powershell
~\.claude\skills\cli-agent-team\scripts\agent-watch.ps1 -Agent codex -AuthMode limited -ProjectDir "C:\path\to\project"
```

Claude가 데몬에 작업 전달:

```bash
bash ~/.claude/skills/cli-agent-team/scripts/trigger.sh codex T001 execute . quality
```

명령 형식:

```bash
bash ~/.claude/skills/cli-agent-team/scripts/trigger.sh <agent> <task-id> <mode> [project-dir] [model-tier]
```

데몬 모드의 상태 파일:

- `_agent_reports/.daemon_<agent>`: watcher 실행 중임을 나타내는 마커.
- `_agent_reports/.pending_<agent>`: `trigger.sh`가 쓰는 작업 요청 파일.
- `_agent_reports/.status_<task-id>_<agent>`: `IN_PROGRESS`, `DONE`, `ERROR_AC`,
  `ERROR_TEST`, `ERROR_TIMEOUT` 같은 상태.

대시보드 시작:

```bash
bash ~/.claude/skills/cli-agent-team/scripts/dashboard.sh --watch
```

## 6. TASK.md 형식

모든 작업은 `_agent_reports/<task-id>/TASK.md`에 작성한다.

최소 구조:

```markdown
# T001 작업 지시

작업 디렉토리: C:\path\to\project
담당: codex
배정일: 2026-06-28

## 시작 전 필독
- AGENTS.md
- PLAN.md
- AGENT_ROLES.md

## 진행 방식
1. 착수 직후 TODO.md에 하위작업 체크리스트를 작성한다.
2. 진행하며 체크박스를 갱신한다.
3. 완료 후 REPORT.md를 작성한다.

## 구체적 작업 지시
docs/example.md를 작성한다.

## 완료 기준 (Acceptance Criteria)
- [ ] THE document SHALL include a How It Works section.
- [ ] WHEN the worker finishes, THE worker SHALL write REPORT.md with an AC checklist.
- [ ] 허용 파일 외 파일을 건드리지 않았다

## 허용 파일
- docs/example.md

## 완료 증거 파일
- docs/example.md 생성됨
```

완료 기준은 검증 가능한 문장으로 쓴다. EARS 또는 Given-When-Then 형식을 권장한다.

```text
WHEN 사용자가 저장 버튼을 클릭하면 THE app SHALL write settings.json.
WHILE 요청이 진행 중이면 THE screen SHALL show a loading state.
IF DB 연결에 실패하면 THEN THE API SHALL return HTTP 503.
Given: valid config exists / When: setup runs / Then: .cli-agent-team.conf is written.
```

작업자의 REPORT.md에는 반드시 다음 섹션이 있어야 한다.

```markdown
## AC 체크리스트
- [x] THE document SHALL include a How It Works section.
- [x] WHEN the worker finishes, THE worker SHALL write REPORT.md with an AC checklist.
- [x] 허용 파일 외 파일을 건드리지 않았다
```

`verify.sh`는 `## AC 체크리스트`를 파싱한다. 항목이 `- [ ]`로 남아 있으면 검증 실패로
처리된다.

## 7. 병렬 dispatch

병렬 실행은 서로 독립적인 작업일 때만 허용한다. 두 작업을 동시에 배정하기 전 다음 명령으로
충돌 여부를 확인한다.

```bash
bash ~/.claude/skills/cli-agent-team/scripts/parallel-check.sh T001 T002 .
```

통과 조건:

- 두 TASK.md의 선행 작업이 없거나 PLAN.md에서 이미 DONE이다.
- 두 TASK.md의 `## 허용 파일` 목록이 겹치지 않는다.

검토 순서:

```text
1. 먼저 끝난 작업부터 REPORT.md를 읽는다.
2. 단, 같은 릴리스나 같은 판단에 영향을 주면 즉시 통합하지 않는다.
3. 둘 다 끝나면 고정 순서로 검토한다: agy 먼저, codex 다음.
4. 각 작업마다 검증 명령을 실행한다.
5. 통과한 작업만 통합하고, 실패한 작업은 FEEDBACK.md로 되돌린다.
```

동시에 실행하더라도 에이전트별 작업은 하나만 둔다. 기본 병렬 한도는 codex 1개 + agy
1개다.

## 8. 적응형 에이전트 배분

처음에는 균등 배정으로 시작한다. 이후 `_agent_reports/.agent_scores.json`과 REPORT.md
결과를 기준으로 task type별 성공률을 반영한다.

점수 파일은 다음 구조를 가진다.

```text
agent -> task_type -> ac_pass, ac_fail, total
```

유효한 task type:

- `shell_scripting`
- `documentation`
- `code_implementation`
- `testing`
- `refactoring`

점수 기록:

```bash
bash ~/.claude/skills/cli-agent-team/scripts/record-score.sh codex documentation 9 0
```

배분 기준:

```text
1. 데이터가 없으면 균등 배정한다.
2. task type별 샘플이 5건 미만이면 기본 라우팅을 유지한다.
3. 5건 이상이고 성공률 차이가 15%p 이상이면 성공률이 높은 에이전트를 우선한다.
4. 우선 에이전트가 rate limit에 걸리면 폴백 에이전트로 배정한다.
5. 완료 후 반드시 점수를 기록해 다음 판단에 반영한다.
```

부하 분산은 `_agent_reports/LOG.md`의 window 값으로 관리한다. 리밋이 발생하면 해당
에이전트의 window를 줄이고, 성공 세션이 반복되면 조금씩 늘린다.

## 9. 대시보드

대시보드는 데몬 상태와 태스크 상태를 보여준다.

```bash
bash ~/.claude/skills/cli-agent-team/scripts/dashboard.sh
bash ~/.claude/skills/cli-agent-team/scripts/dashboard.sh --verbose
bash ~/.claude/skills/cli-agent-team/scripts/dashboard.sh --watch
```

ASCII 출력 예시:

```text
+--------------------------------------------------+
|        Agent Dashboard - 2026-06-28 11:30:00     |
+--------------------------------------------------+

[Daemons]
  codex   RUNNING
  agy     RUNNING

[Tasks]
  TASK_ID        STATUS                 AGENT    UPDATED
  -------------- --------------------   -------- --------
  T003           IN_PROGRESS            codex    06-28 11:28
  T002           DONE                   agy      06-28 11:15
  T001           DONE                   codex    06-28 10:50
```

상태 판단 기준:

- `.status_<task-id>_<agent>` 파일이 있으면 그 값을 우선한다.
- REPORT.md가 있고 미완료 AC가 없으면 DONE으로 본다.
- TASK.md만 있으면 PENDING으로 본다.

`--watch`는 1초마다 시계를 갱신하고 `_agent_reports/` 변경이 있을 때만 전체 목록을 다시
그린다.

## 10. 트러블슈팅

| 증상 | 원인 | 해결 |
| --- | --- | --- |
| 데몬 마커가 없음 | watcher가 실행 중이 아니거나 다른 디렉터리에서 실행됨 | 프로젝트 루트에서 `agent-watch.ps1`을 다시 실행하거나 `-ProjectDir`를 지정한다. |
| `trigger.sh`가 데몬 미실행 오류를 냄 | `_agent_reports/.daemon_<agent>` 파일이 없음 | 해당 에이전트 watcher를 먼저 켠다. |
| agy 출력이 없음 | TTY가 없으면 agy stdout이 비어 보일 수 있음 | pty-bridge를 경유한다. 완료 여부는 REPORT.md와 diff로 판단한다. |
| agy 브리지가 실패함 | `mcp-servers/pty-bridge` 의 Node 의존성이 없음 | `mcp-servers/pty-bridge`에서 `npm install`을 실행한다. |
| 한글이 깨짐 | Windows 터미널 코드페이지가 UTF-8이 아님 | `chcp 65001` 실행 후 명령을 다시 실행한다. |
| `trigger.sh` pickup timeout | watcher가 pending 파일을 가져가지 않음 | watcher를 재시작하고 `trigger.sh`를 다시 실행한다. |
| `ERROR_AC` | REPORT.md의 AC 체크리스트가 없거나 미완료 항목이 있음 | REPORT.md를 보완하거나 FEEDBACK.md로 재배정한다. |
| `ERROR_TEST` | 문법, lint, test, 자동 검증 명령 중 하나가 실패함 | 로그와 검증 출력을 보고 FEEDBACK.md를 작성한다. |
| `ERROR_TIMEOUT` | 작업 시간이 제한을 초과함 | 태스크를 더 작게 나누거나 타임아웃을 의도적으로 늘린다. |
| 병렬 검사 실패 | 선행 작업이 미완료이거나 허용 파일이 겹침 | 순차 실행하거나 TASK.md의 허용 파일 범위를 좁힌다. |

마지막 원칙: exit code만 믿지 않는다. 작업자가 exit 0으로 끝나도 실제 변경이 없을 수 있고,
agy는 stdout이 거의 없어도 파일 작업을 완료했을 수 있다. 항상 diff, REPORT.md,
AC 체크리스트, 완료 증거 파일을 함께 확인한다.
