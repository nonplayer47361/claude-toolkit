---
name: review
description: "지정한 TASK_ID를 agy에 review 모드로 전달하고 REVIEW.md 결과를 요약한 뒤 필요하면 FEEDBACK.md 재작업 루프를 준비합니다."
---

# /review

`/review`는 구현 결과를 독립 에이전트에게 검토시키는 커맨드입니다. 기본 대상은 `agy`이며, 검토 에이전트는 코드를 수정하지 않고 `_agent_reports/{TASK_ID}/REVIEW.md`만 작성해야 합니다.

## 입력

- `TASK_ID`: 예: `T003`
- 선택 입력: review agent (`agy` 기본값)
- 선택 입력: `auth-mode` (`limited` 기본값)

## 실행 절차

1. `_agent_reports/{TASK_ID}/TASK.md`가 존재하는지 확인한다.
2. 작업 트리에 의도하지 않은 변경이 있는지 `git status --short`로 확인하고, 검토 대상과 무관한 변경은 보고에서 분리한다.
3. review dispatch 명령을 실행한다.

```bash
bash skills/cli-agent-team/scripts/dispatch.sh <agent> <TASK_ID> <auth-mode> . review
```

예:

```bash
bash skills/cli-agent-team/scripts/dispatch.sh agy T003 limited . review
```

4. `_agent_reports/{TASK_ID}/REVIEW.md`가 생성될 때까지 기다린다.
5. `REVIEW.md`를 읽고 다음 기준으로 요약한다.
   - 실제 버그 또는 완료 기준 미충족 여부
   - 허용 파일 범위 위반 여부
   - 테스트, 빌드, 문서 누락 여부
   - 검토자가 제기한 질문 또는 막힘
6. 주요 이슈가 없으면 사용자에게 통과 요약을 제공한다.
7. 주요 이슈가 있으면 `_agent_reports/{TASK_ID}/FEEDBACK.md`를 작성한다.
8. feedback 재작업이 필요하면 아래 명령을 준비하거나, 사용자가 요청한 경우 실행한다.

```bash
bash skills/cli-agent-team/scripts/dispatch.sh <original-agent> <TASK_ID> <auth-mode> . feedback
```

## REVIEW.md 요약 형식

- `결론`: 통과, 수정 필요, 확인 필요 중 하나
- `주요 이슈`: 파일/라인 단위로 구체화
- `재작업 지시`: 에이전트가 판단 없이 수행할 수 있는 명령형 문장
- `남은 질문`: 사용자 판단이 필요한 항목

## FEEDBACK.md 작성 원칙

- 무엇이 문제인지 파일과 증거를 기준으로 적는다.
- TASK.md의 어느 완료 기준과 충돌하는지 명시한다.
- 수정 방법은 구체적으로 적되 허용 파일 밖을 건드리지 않도록 제한한다.
- 검토자의 선택적 개선 제안은 필수 수정과 분리한다.

## 주의사항

- review 모드에서는 소스 코드를 수정하지 않는다.
- `REVIEW.md`의 모든 의견을 그대로 수용하지 말고, TASK.md 완료 기준과 실제 diff를 기준으로 Claude가 최종 판단한다.
- FEEDBACK 루프는 같은 작업에서 최대 3회까지만 반복하고, 이후에도 해결되지 않으면 BLOCKED로 보고한다.
