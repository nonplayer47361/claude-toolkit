# Agent Scores Schema

Claude 오케스트레이터가 에이전트(agy, codex)의 태스크 성능을 추적하고
다음 dispatch 결정에 활용하기 위한 `.agent_scores.json` 스키마 문서입니다.

---

## 스키마 버전

| 필드 | 타입 | 설명 |
|------|------|------|
| `version` | integer | 스키마 버전 번호 (현재: `1`) |
| `last_updated` | string (ISO 8601) | 마지막 점수 업데이트 시각 (UTC) |
| `agents` | object | 에이전트별 성능 데이터 맵 |

---

## 필드 설명

### `agents.<agent>.<task_type>`

각 에이전트(`agy`, `codex`)와 태스크 유형별로 다음 3개의 카운터를 가집니다:

| 필드 | 타입 | 설명 |
|------|------|------|
| `ac_pass` | integer | 누적 AC(Acceptance Criteria) 통과 수 |
| `ac_fail` | integer | 누적 AC 실패 수 |
| `total` | integer | `ac_pass + ac_fail` (자동 계산) |

---

## task_type 목록

| task_type | 설명 |
|-----------|------|
| `shell_scripting` | Bash/Shell 스크립트 작성 및 자동화 |
| `documentation` | 문서 작성 (README, schema docs, guides 등) |
| `code_implementation` | 기능 구현 (Python, JS, TS 등) |
| `testing` | 테스트 작성 및 검증 |
| `refactoring` | 기존 코드 리팩터링 및 개선 |

---

## 스키마 예시

```json
{
  "version": 1,
  "last_updated": "2026-06-28T11:00:00Z",
  "agents": {
    "agy": {
      "shell_scripting":      { "ac_pass": 6, "ac_fail": 1, "total": 7 },
      "documentation":        { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "code_implementation":  { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "testing":              { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "refactoring":          { "ac_pass": 0, "ac_fail": 0, "total": 0 }
    },
    "codex": {
      "shell_scripting":      { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "documentation":        { "ac_pass": 5, "ac_fail": 0, "total": 5 },
      "code_implementation":  { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "testing":              { "ac_pass": 0, "ac_fail": 0, "total": 0 },
      "refactoring":          { "ac_pass": 0, "ac_fail": 0, "total": 0 }
    }
  }
}
```

---

## `record-score.sh` 사용 예시

```bash
# 형식
bash record-score.sh <agent> <task_type> <ac_pass> <ac_fail>

# 예시 1: agy가 shell_scripting 태스크에서 6개 통과, 1개 실패
bash record-score.sh agy shell_scripting 6 1
# 출력: [scores] agy / shell_scripting: pass=6 fail=1 total=7 (승률 85.7%)

# 예시 2: codex가 documentation 태스크에서 5개 통과, 0개 실패
bash record-score.sh codex documentation 5 0
# 출력: [scores] codex / documentation: pass=5 fail=0 total=5 (승률 100.0%)
```

### 오류 케이스

```bash
# jq 미설치 시
bash record-score.sh agy shell_scripting 3 1
# ERROR: jq 가 설치되지 않았습니다. brew install jq / apt install jq 로 설치하세요.

# 유효하지 않은 agent
bash record-score.sh unknown shell_scripting 3 1
# ERROR: 유효하지 않은 agent 'unknown'. 유효한 값: agy codex

# 유효하지 않은 task_type
bash record-score.sh agy invalid_type 3 1
# ERROR: 유효하지 않은 task_type 'invalid_type'. 유효한 값: shell_scripting documentation code_implementation testing refactoring
```

---

## Claude 오케스트레이터가 읽는 방법

dispatch 전 `best_agent()` 판단 시 `.agent_scores.json`을 참조하여 가장 적합한 에이전트를 선택합니다.

### 승률(win_rate) 기반 선택 로직

```bash
# jq를 사용한 승률 계산
TASK_TYPE="shell_scripting"
SCORES_FILE="_agent_reports/.agent_scores.json"

for agent in agy codex; do
  pass=$(jq ".agents.${agent}.${TASK_TYPE}.ac_pass" "$SCORES_FILE")
  total=$(jq ".agents.${agent}.${TASK_TYPE}.total" "$SCORES_FILE")
  if [[ "$total" -gt 0 ]]; then
    win_rate=$(awk "BEGIN { printf \"%.3f\", $pass / $total }")
  else
    win_rate="0.500"  # 데이터 없으면 기본값 50%
  fi
  echo "$agent: $win_rate"
done | sort -t: -k2 -rn | head -1 | cut -d: -f1
```

### 판단 기준

1. **total >= 3**: 데이터가 충분할 때 승률로 판단
2. **total < 3**: 데이터 부족 → 기본값 50% 적용 (두 에이전트 동등 처리)
3. **승률 동일 시**: `agy` 우선 (기본값)

### 스키마 파일 위치

```
<project_root>/_agent_reports/.agent_scores.json
```

오케스트레이터(`dispatch.sh` 등)는 이 경로를 `$PROJECT_ROOT/_agent_reports/.agent_scores.json`으로 참조합니다.