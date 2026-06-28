# AGENT_ROLES.md — claude-toolkit 개선 작업

> 프로젝트: claude-toolkit 자체 버그 픽스 + 기능 강화
> 개선 계획 출처: docs/improvement-plan.md
> 권한 수준: **완전자율** (사용자 명시 확인 2026-06-28)
> 근거: verify.sh로 스코프·AC 자동 검증, git diff로 최종 확인 후 Claude가 직접 커밋

---

## 에이전트 역할

| 에이전트 | 담당 | 이유 |
|---------|------|------|
| **Claude** | 오케스트레이터, TASK.md 작성, verify, 커밋 | 전체 개선계획 숙지, 아키텍처 판단 |
| **Codex** | dispatch.sh 외과적 수정 (정밀 라인 수준 버그픽스) | 소·중형 코드 수정 강점 |
| **agy** | verify.sh 수정, update-state.sh 원자적 쓰기 구현 | bash 스크립트 구조 이해, 새 로직 구현 |

Claude는 코드를 직접 수정하지 않는다. 1~3줄 수정도 반드시 에이전트에게 재배정.

---

## 작업 라우팅 테이블

| task_type | 1순위 | 폴백 |
|-----------|-------|------|
| shell_scripting.bug_fix | codex | agy |
| shell_scripting.new_logic | agy | codex |
| documentation | agy | codex |
| analysis | agy | codex |

## 자동 검증 명령어

```
syntax-check-dispatch: bash -n skills/cli-agent-team/scripts/dispatch.sh
syntax-check-verify: bash -n skills/cli-agent-team/scripts/verify.sh
```

---

## 병렬 실행 정책

- **허용**: codex 1개 + agy 1개 동시 실행 (서로 다른 파일 대상)
- **금지**: 같은 에이전트 2개 동시, 같은 파일 동시 수정

---

## 허용 스코프 (전체)

- `skills/cli-agent-team/scripts/dispatch.sh`
- `skills/cli-agent-team/scripts/verify.sh`
- `skills/cli-agent-team/scripts/update-state.sh`
- `skills/cli-agent-team/references/agent-characteristics.md`
- `_agent_reports/` (TASK.md, REPORT.md 등 작업 파일)

---

## 마일스톤 게이트

- **M1 (P0 버그 픽스)**: T-FIX-P0-A + T-FIX-P0-B 모두 DONE → 게이트 → M2
- **M2 (P1 안정성)**: T-FIX-P1-ATOMIC + T-FIX-P1-FEEDBACK DONE → 게이트 → M3
- **M3 (P2 기능)**: doctor/init/diff-summary 등
- 완료 3개마다 중간 게이트 발동

---

## TASK/REPORT 프로토콜

- TASK.md: `_agent_reports/<task-id>/TASK.md`
- REPORT.md: AC 체크리스트(`## AC 체크리스트`) 필수, `- [x]` 형식
- FEEDBACK.md: 실패 시 라인 수준 구체적 지적 + 수정 방법 + 건드리지 말 것
- CONTRACT.md: 병렬 작업 시 필수 (현재 Round 1은 독립 파일이므로 불필요)
