---
name: start-task
description: "PLAN.md의 대기 작업을 TASK.md로 구체화하고 적절한 CLI 에이전트 dispatch 명령을 준비합니다."
---

# /start-task

`/start-task`는 `cli-agent-team` 루프에서 새 작업을 시작할 때 쓰는 커맨드입니다. 사용자가 `TASK_ID`와 대상 에이전트(`codex` 또는 `agy`)를 지정하면, Claude는 프로젝트 문맥을 읽고 작업 지시서와 dispatch 명령을 준비합니다.

## 입력

- `TASK_ID`: 예: `T003`
- `agent`: `codex` 또는 `agy`
- 선택 입력: `auth-mode` (`limited` 기본값, 프로젝트에서 명시 승인된 경우에만 `full` 사용)

## 실행 절차

1. 프로젝트 루트에서 `BRIEF.md`, `PLAN.md`, `AGENT_ROLES.md`가 있는지 확인한다.
2. `PLAN.md`에서 `TASK_ID`에 해당하는 요구사항, 선행 작업, 완료 기준, 허용 파일 범위를 추출한다.
3. `BRIEF.md`가 있으면 제품 목적, 범위, 제약을 요약해 작업 배경에 반영한다.
4. `_specs/{TASK_ID}/requirements.md`가 없으면 추출한 요구사항으로 생성한다. 이미 있으면 내용을 보존하고 누락된 제약만 보강한다.
5. `_agent_reports/{TASK_ID}/` 디렉터리를 만들고 `TASK.md`를 작성한다.
6. `TASK.md`에는 다음 항목을 반드시 포함한다.
   - 시작 전 읽을 문서
   - 담당 영역과 작업 범위
   - 진행 방식: `TODO.md` 작성, 진행 중 체크, 완료 후 `REPORT.md` 작성
   - 구체적 작업 지시
   - 완료 기준
   - 허용 파일
   - 금지 파일 또는 범위 제한
7. 작업 성격과 `AGENT_ROLES.md`의 라우팅 규칙을 기준으로 모델 계열을 정한다.
   - 단순 문서, 좁은 수정, 반복 작업: `fast`
   - 구조 판단, 위험한 변경, 큰 설계 영향: `quality`
8. dispatch 전에 `_agent_reports/{TASK_ID}/TASK.md`가 존재하고 비어 있지 않은지 확인한다.
9. 실행할 명령을 출력한다. 직접 실행이 요청된 경우에만 실행한다.

## dispatch 명령 형식

```bash
bash skills/cli-agent-team/scripts/dispatch.sh <agent> <TASK_ID> <auth-mode> . execute
```

예:

```bash
bash skills/cli-agent-team/scripts/dispatch.sh codex T003 limited . execute
```

## 결과물

- `_specs/{TASK_ID}/requirements.md`
- `_agent_reports/{TASK_ID}/TASK.md`
- 사용자가 실행하거나 검토할 dispatch 명령

## 주의사항

- 허용 파일 목록은 가능한 한 좁게 작성한다.
- `full` 권한 모드는 사용자가 프로젝트 단위로 명시 승인한 경우에만 사용한다.
- `TASK.md` 작성 단계에서는 소스 코드를 수정하지 않는다.
