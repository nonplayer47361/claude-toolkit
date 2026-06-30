# E2E Walkthrough — 첫 태스크 완주하기

> **참고:** 이 문서의 터미널 출력은 실제 실행 결과를 기반으로 작성된 예시입니다.
> 환경에 따라 경로, 시간, 버전 번호가 다를 수 있습니다.

**시나리오:** `my-app` 프로젝트에서 `utils/formatter.js`에 날짜 포맷 함수를 추가하는 작업을
codex에게 배정하고 검증 후 커밋하는 한 사이클을 처음부터 끝까지 완주합니다.

---

## 0. 전제조건 확인

```bash
claude --version
# claude 1.x.x
```

환경 진단 스크립트로 한 번에 확인합니다.

```bash
bash ~/.claude/skills/cli-agent-team/scripts/doctor.sh
```

출력 예시 (codex 있음, agy 없음):

```
[doctor] Claude Code  : ✅
[doctor] Git          : ✅
[doctor] Bash         : ✅
[doctor] codex        : ✅  /usr/local/bin/codex
[doctor] agy          : ❌  미설치 (선택사항 — codex만으로 동작 가능)
[doctor] jq           : ✅
[doctor] Node.js      : ✅  v20.11.0
[doctor] conf         : ✅  _agent_reports/.cli-agent-team.conf
모든 필수 도구 확인 완료. codex 모드로 실행 가능.
```

agy가 없어도 괜찮습니다. codex 하나만 있으면 모든 핵심 기능이 동작합니다.

---

## 1. 프로젝트 초기화 (최초 1회)

프로젝트 루트에서 `setup.sh`를 실행합니다. 에이전트 설치 여부를 자동 감지하고
설정 파일을 생성합니다.

```bash
cd ~/my-app
bash ~/.claude/skills/cli-agent-team/scripts/setup.sh
```

출력 예시:

```
[cli-agent-team] setup
================================================================
감지 결과:
  codex   ✅ /usr/local/bin/codex   ENABLED
  agy     ❌ 미설치 → DISABLED
  claude  ✅ (항상 활성)

설정 파일 저장: _agent_reports/.cli-agent-team.conf
================================================================
완료. 모니터를 시작하려면:
  bash ~/.claude/skills/cli-agent-team/scripts/dashboard.sh --watch
```

생성된 conf 파일 확인:

```bash
cat _agent_reports/.cli-agent-team.conf
# CODEX_ENABLED=true
# CODEX_BIN=/usr/local/bin/codex
# AGY_ENABLED=false
# AGY_BIN=
# CLAUDE_ENABLED=true
# SETUP_DATE=2026-06-30
```

---

## 2. TASK.md 작성

태스크 디렉터리를 만들고 작업 지시서를 작성합니다.

```bash
mkdir -p _agent_reports/T001
```

`_agent_reports/T001/TASK.md` 내용:

```markdown
---
task_type: code_implementation
---
# T001: utils/formatter.js — 날짜 포맷 함수 추가

작업 디렉토리: ~/my-app
담당: codex
배정일: 2026-06-30

## 시작 전 필독
- AGENTS.md

## 구체적 작업 지시

`utils/formatter.js`에 `formatDate(date, format)` 함수를 추가한다.

- `format` 인자 지원 값:
  - `'YYYY-MM-DD'` : 2026-06-30
  - `'MM/DD/YYYY'` : 06/30/2026
  - `'relative'`   : "3분 전", "2시간 전", "어제" 등 한국어 상대 시간

## 완료 기준 (AC 체크리스트)

- [ ] `formatDate` 함수가 `utils/formatter.js`에 추가됨
- [ ] 세 가지 format 모두 동작함
- [ ] 기존 코드 변경 없음
- [ ] REPORT.md의 ## AC 체크리스트 항목이 모두 [x]로 처리됨

## 허용 파일

- utils/formatter.js

## 완료 증거 파일

- utils/formatter.js (formatDate 함수 포함)
```

**핵심 규칙 두 가지:**
- `## 허용 파일` — 에이전트는 이 목록 밖의 파일을 수정하면 verify 실패
- `## AC 체크리스트` — REPORT.md에서 `- [ ]`가 하나라도 남으면 verify 실패

---

## 3. 에이전트 배정 (dispatch)

```bash
bash ~/.claude/skills/cli-agent-team/scripts/dispatch.sh \
  codex T001 limited . execute quality
```

인자 설명:
- `codex` — 사용할 에이전트
- `T001` — 태스크 ID (`_agent_reports/T001/` 폴더명)
- `limited` — 권한 모드 (limited = codex 기본 승인 모드 / full = bypass)
- `.` — 프로젝트 루트 경로
- `execute` — 실행 모드 (execute / review / feedback)
- `quality` — 모델 티어 (quality / fast)

터미널 출력 예시:

```
[dispatch] T001 → codex (execute · limited · quality)
[dispatch] TASK.md 확인: ✅  _agent_reports/T001/TASK.md
[dispatch] 실행 중... (codex headless mode)
.....................................
[dispatch] 완료 (47초)
[dispatch] REPORT.md 수신: ✅
```

codex가 작업하는 동안 `.` 단위로 진행 표시가 찍힙니다. 작업 규모에 따라
10초~수분 소요됩니다.

---

## 4. REPORT.md 확인

dispatch가 끝나면 `_agent_reports/T001/REPORT.md`가 생성되어 있습니다.

```bash
cat _agent_reports/T001/REPORT.md
```

예시 내용:

```markdown
# T001 완료 보고

## 작업 요약

`utils/formatter.js`에 `formatDate(date, format)` 함수를 추가했습니다.

## 변경 파일

- `utils/formatter.js`: formatDate 함수 추가 (+45줄)

## AC 체크리스트

- [x] `formatDate` 함수가 `utils/formatter.js`에 추가됨
- [x] 세 가지 format 모두 동작함
- [x] 기존 코드 변경 없음
- [x] REPORT.md의 ## AC 체크리스트 항목이 모두 [x]로 처리됨

## 구현 노트

YYYY-MM-DD, MM/DD/YYYY는 Date 객체에서 연·월·일을 추출해 직접 포맷.
'relative'는 현재 시각과의 차이(초 단위)를 계산해
60초 미만 → "N초 전", 3600초 미만 → "N분 전",
86400초 미만 → "N시간 전", 그 이상 → "N일 전" 형태로 반환.
```

모든 AC 항목이 `[x]`인지 눈으로 먼저 확인합니다. 다음 단계에서 자동으로도 검증됩니다.

---

## 5. 자동 검증 (verify)

5개 항목을 자동으로 검증합니다.

```bash
bash ~/.claude/skills/cli-agent-team/scripts/verify.sh T001 . codex
```

**통과 시 출력:**

```
[verify] T001 — codex
[verify] 1/5 스코프 검사......... ✅  허용 파일만 변경됨
[verify] 2/5 AC 체크리스트....... ✅  4/4 항목 통과
[verify] 3/5 보안 스캔 (AgentShield)... ✅  이상 없음
[verify] 4/5 완료 증거 파일....... ✅  utils/formatter.js 존재·변경됨
[verify] 5/5 자동 검증 명령....... ✅  (없음 — 건너뜀)
[verify] ✅ 검증 통과 — 커밋 진행 가능
[scores] codex/code_implementation: pass=4 fail=0 (승률 100.0%)
[metrics] .agent_metrics.json 레코드 추가: T001
```

**실패 케이스 — AC 미완료:**

```
[verify] T001 — codex
[verify] 1/5 스코프 검사......... ✅
[verify] 2/5 AC 체크리스트....... ❌  미완료 항목 1개
  - [ ] 세 가지 format 모두 동작함
[verify] ❌ 검증 실패: AC_INCOMPLETE
→ FEEDBACK.md를 작성하고 재배정하세요 (아래 7단계 참고)
```

**실패 케이스 — 스코프 위반 (허용 파일 외 변경):**

```
[verify] 1/5 스코프 검사......... ❌  허용 범위 외 파일 변경 감지
  ! utils/dateHelper.js (허용 목록에 없음)
[verify] ❌ 검증 실패: SCOPE_VIOLATION
```

---

## 6. 커밋

검증을 통과하면 커밋합니다.

```bash
git add utils/formatter.js
git commit -m "feat(T001): formatDate 함수 추가 — YYYY-MM-DD, MM/DD/YYYY, relative 지원"
```

---

## 7. 실패 시 재배정 흐름

verify가 실패하면 `FEEDBACK.md`를 작성해 codex에게 재배정합니다.

`_agent_reports/T001/FEEDBACK.md` 예시:

```markdown
# T001 피드백

## 문제점

`'relative'` format이 영어로 반환되고 있습니다 ("3 minutes ago").
요구사항은 한국어 ("3분 전")입니다.

## 수정 지시

`formatDate`의 'relative' 분기를 한국어로 수정하세요.
다른 코드는 수정하지 않습니다.
```

재배정:

```bash
bash ~/.claude/skills/cli-agent-team/scripts/dispatch.sh \
  codex T001 limited . feedback quality
```

feedback 모드는 FEEDBACK.md의 지적 사항만 반영하도록 codex에게 지시합니다.
완료 후 다시 `verify.sh`를 실행합니다.

---

## 8. 다음 태스크로 — 적응형 배정

태스크가 쌓일수록 `.agent_scores.json`에 승률 데이터가 누적됩니다.

```json
{
  "agents": {
    "codex": {
      "code_implementation": { "ac_pass": 12, "ac_fail": 1, "total": 13 },
      "shell_scripting":     { "ac_pass": 8,  "ac_fail": 0, "total": 8  },
      "documentation":       { "ac_pass": 3,  "ac_fail": 2, "total": 5  }
    }
  }
}
```

다음 배정 시 Claude는 이 데이터를 읽어 자동으로 최적 에이전트를 선택합니다.

- `code_implementation` → codex 승률 92.3% → codex 우선 배정
- `documentation` → codex 승률 60% → 샘플 5건 이상, 차이 15%p 미만이면 기본 라우팅 유지

agy가 추가되면 같은 task_type에서 두 에이전트의 승률을 비교해 차이가 15%p 이상일 때
자동으로 더 잘하는 쪽으로 배정이 기울어집니다.

---

## 요약

```
setup.sh 실행 (최초 1회)
  └─ TASK.md 작성
       └─ dispatch.sh → codex 실행 (자동)
            └─ REPORT.md 생성
                 └─ verify.sh (5항목 자동 검증)
                      ├─ ✅ 통과 → git commit
                      └─ ❌ 실패 → FEEDBACK.md → dispatch feedback → verify 재실행
```

다음 단계:
- 데몬 모드 (실시간 대시보드): [cli-agent-team-guide.md](cli-agent-team-guide.md#5-워크플로우-데몬-모드)
- 병렬 배정 (codex + agy 동시): [cli-agent-team-guide.md](cli-agent-team-guide.md#7-병렬-dispatch)
- 전체 아키텍처: [architecture.md](architecture.md)
