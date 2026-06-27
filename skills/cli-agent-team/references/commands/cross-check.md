---
name: cross-check
description: "중요 작업을 codex와 agy에 동시에 배정해 결과를 독립 비교하고 불일치를 ambiguity signal로 보고합니다."
---

# /cross-check

`/cross-check`는 영향이 큰 작업을 두 에이전트에게 독립적으로 맡기고 결과를 비교하는 커맨드입니다. 같은 `TASK.md`를 `codex`와 `agy`가 각각 별도 작업 트리에서 수행하게 하며, Claude는 두 결과를 비교해 채택, 병합, 재검토 여부를 결정합니다.

## 입력

- `TASK_ID`: 예: `T010`
- 선택 입력: `auth-mode` (`limited` 기본값)
- 선택 입력: 기준 브랜치 또는 기준 커밋 (`HEAD` 기본값)

## 비용 경고

이 커맨드는 같은 작업을 두 에이전트에 동시에 배정하므로 토큰과 실행 시간이 일반 실행의 약 2배 이상 듭니다. 작은 문서 수정이나 명확한 단일 파일 변경에는 사용하지 않습니다.

## 실행 절차

1. `_agent_reports/{TASK_ID}/TASK.md`가 존재하고 완료 기준과 허용 파일 목록이 명확한지 확인한다.
2. 작업 트리가 깨끗한지 확인한다. 기존 사용자 변경이 있으면 중단하고 사용자에게 기준점을 확인한다.
3. 두 개의 별도 worktree를 만든다.

```bash
git worktree add ../<repo>-codex-<TASK_ID> -b agent/codex-<TASK_ID> <base>
git worktree add ../<repo>-agy-<TASK_ID> -b agent/agy-<TASK_ID> <base>
```

4. 각 worktree에 동일한 `TASK.md`를 기준으로 dispatch한다.

```bash
bash skills/cli-agent-team/scripts/dispatch.sh codex <TASK_ID> <auth-mode> ../<repo>-codex-<TASK_ID> execute
bash skills/cli-agent-team/scripts/dispatch.sh agy <TASK_ID> <auth-mode> ../<repo>-agy-<TASK_ID> execute
```

5. 두 에이전트의 `_agent_reports/{TASK_ID}/REPORT.md`와 `git diff`를 각각 수집한다.
6. 다음 항목을 비교한다.
   - 완료 기준 충족 여부
   - 허용 파일 준수 여부
   - 구현 접근 방식 차이
   - 테스트 또는 검증 결과
   - 한쪽에만 있는 버그 수정 또는 회귀 위험
7. 결과가 실질적으로 같으면 더 작고 명확한 diff를 우선 채택한다.
8. 결과가 다르면 `ambiguity signal`로 표시하고 사람 검토를 요청한다.
9. 채택한 diff만 메인 작업 트리에 적용하고, 채택하지 않은 worktree는 보존 여부를 사용자에게 확인한 뒤 정리한다.

## ambiguity signal 기준

아래 중 하나라도 해당하면 불일치로 처리한다.

- 두 에이전트가 서로 다른 공개 API나 파일 구조를 제안함
- 한쪽은 완료 기준을 충족하고 다른 한쪽은 일부 미충족
- 테스트 결과가 다르거나 한쪽에서만 실패가 재현됨
- 보안, 데이터 손실, 마이그레이션, 인증 흐름 같은 고위험 판단이 갈림
- 어느 결과가 더 안전한지 Claude가 TASK.md만으로 판단할 수 없음

## 비교 보고 형식

```markdown
## Cross-check 결과: <TASK_ID>

결론: 채택 / 부분 병합 / ambiguity signal

### codex 결과
- 요약:
- 검증:
- 위험:

### agy 결과
- 요약:
- 검증:
- 위험:

### 판단
- 채택한 쪽:
- 이유:
- 추가 검토 필요:
```

## 정리 절차

1. 채택한 변경을 메인 작업 트리에 적용한다.
2. `_agent_reports/{TASK_ID}/REPORT.md`에 두 결과 비교와 최종 판단을 기록한다.
3. 필요하면 사용하지 않는 worktree를 제거한다.

```bash
git worktree remove ../<repo>-codex-<TASK_ID>
git worktree remove ../<repo>-agy-<TASK_ID>
```

## 주의사항

- 두 에이전트가 서로의 결과를 보지 않도록 독립 worktree를 사용한다.
- 같은 파일을 동시에 메인 작업 트리에서 수정하지 않는다.
- 불일치가 설계 모호성에서 비롯되면 구현을 계속하지 말고 TASK.md 또는 요구사항을 먼저 명확히 한다.
