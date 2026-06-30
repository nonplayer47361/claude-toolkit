---
evaluator: codex
date: 2026-06-29
---

# cli-agent-team 외부 리뷰

## 평가 범위

직접 읽은 핵심 파일: `SKILL.md`, `scripts/agent-team.sh`, `scripts/dispatch.sh`, `scripts/verify.sh`, `scripts/record-score.sh`, `scripts/worktree-dispatch.sh`, `scripts/cross-review.sh`, `scripts/dashboard.sh`, `scripts/doctor.sh`, `scripts/parallel-check.sh`, `references/agents-template.md`.

`docs/quickstart.md`는 지정 경로에 존재하지 않았다. 대상 디렉터리 전체 목록에도 `docs/` 디렉터리와 `quickstart.md`가 없고, `Get-Content ... docs\quickstart.md`는 `Cannot find path`로 실패했다. 온보딩 평가는 이 누락을 포함해 판단했다.

추가 확인 파일: `scripts/setup.sh`, `scripts/init.sh`, `scripts/trigger.sh`, `scripts/update-state.sh`. 이유는 `agent-team.sh init`과 `SKILL.md`가 초기화/상태 갱신 흐름을 이 파일들에 의존하기 때문이다.

## 1. 아키텍처 설계 - 5/10

개념 설계는 일관된 편이다. `SKILL.md:10-14`는 Claude 오케스트레이터, 외부 CLI 서브 에이전트, `PLAN.md`, `AGENT_ROLES.md`, `_agent_reports/<task-id>/`를 핵심 컴포넌트로 분리한다. `SKILL.md:303-305`도 `.session_state`를 별도 상태 저장소로 두어 세션 재개를 단순화하려는 의도가 명확하다. 검증 루프도 `SKILL.md:729-755`에서 `verify.sh` 선실행, 실패 시 피드백 루프로 이동하는 흐름을 제시하고, `SKILL.md:803-841`은 재배정/차단 정책을 둔다.

문제는 이 설계가 실제 진입점과 맞지 않는다. `SKILL.md:335-342`는 `setup.sh`가 `PLAN.md`, `AGENT_ROLES.md`, `LOG.md`, `.gitignore`까지 생성한다고 설명하지만, 실제 `setup.sh:106-124`는 `_agent_reports/.cli-agent-team.conf`만 쓴다. 반대로 실제 초기화 기능은 `init.sh:100-145`와 `init.sh:159-200`에 있는데, `agent-team.sh:42`의 `init)`은 `setup.sh`만 호출한다. 즉 사용자가 래퍼의 `init`을 따르면 설계의 상태 저장소가 만들어지지 않는다.

컴포넌트 결합도도 높다. `dashboard.sh:21-24`와 `record-score.sh:16-18`은 실행 대상 프로젝트가 아니라 스크립트 위치 기준 `../../..`를 프로젝트 루트로 추정한다. 이 스킬을 다른 프로젝트에서 쓰는 구조라면 대시보드와 점수 파일이 엉뚱한 `claude-toolkit` 루트를 가리킬 수 있다.

교차 리뷰 API도 문서/래퍼/구현이 어긋난다. `agent-team.sh:25-26`은 `cross-review <task-id> <auth> [dir] [tier]`라고 안내하지만, 실제 `cross-review.sh:9-10`은 두 번째 인자를 `PROJECT_DIR`로 해석한다. 게다가 `cross-review.sh:24`와 `cross-review.sh:37`은 무조건 `full` 권한으로 `dispatch.sh`를 호출한다. 권한 수준을 프로젝트마다 확인한다는 `SKILL.md:245-255`와 정면 충돌한다.

설계상 좋은 결정: `SKILL.md:781-786`에서 커밋 주체를 Claude로 고정하고 에이전트가 커밋하지 못하게 한 점은 감사 추적 측면에서 타당하다. 그러나 이 장점도 `verify.sh`와 `worktree-dispatch.sh`의 구현 약점 때문에 실제 안전성으로 충분히 이어지지 않는다.

## 2. 코드 품질 - 4/10

대부분의 핵심 Bash 파일은 `set -euo pipefail`을 사용한다. 예: `dispatch.sh:26`, `verify.sh:17`, `record-score.sh:13`, `worktree-dispatch.sh:19`, `parallel-check.sh:19`. 하지만 `doctor.sh`에는 같은 안전 설정이 없고, `setup.sh:1`은 `#!/bin/sh`인데 `setup.sh:12`에서 `pipefail`을 쓴다. 직접 실행하면 POSIX `sh`에서 깨질 수 있는 shebang/문법 조합이다.

설정 바이너리 처리가 일관되지 않다. `dispatch.sh:129-134`는 `CODEX_BIN`과 `AGY_BIN`을 찾지만, 실제 실행은 `dispatch.sh:308-317`에서 리터럴 `codex`를 호출하고 `dispatch.sh:350`도 `agy` 문자열을 `pty-bridge`에 넘긴다. conf에 경로를 저장해도 실행 경로에는 반영되지 않는다.

상태/점수 갱신은 경쟁 상태에 취약하다. `record-score.sh:136-155`는 JSON을 읽어 변수에 담고 다시 전체 파일을 덮어쓴다. 락 파일이나 원자적 compare-and-swap이 없어 병렬 검증 시 마지막 writer가 이전 점수를 날릴 수 있다.

`worktree-dispatch.sh`는 변경 반영이 불완전하다. `worktree-dispatch.sh:83-88`은 변경 파일 목록을 만들지만, `worktree-dispatch.sh:95-99`에서 `src`가 파일일 때만 복사한다. 에이전트가 파일을 삭제한 변경, rename, 디렉터리 구조 변경, 권한 변경은 메인 프로젝트에 반영되지 않는다.

`dashboard.sh`의 변경 감지 구현은 주석과 다르다. `dashboard.sh:269-272`는 태스크 디렉터리 목록을 fingerprint에 넣겠다고 설명하지만, 실제 `dashboard.sh:274`는 `ls -d "${REPORTS_DIR}/"/`로 보고서 디렉터리 자체만 본다. 새 태스크 디렉터리 추가/삭제를 감지하지 못할 가능성이 크다.

검증 환경도 약하다. 이 Windows 환경에서 `bash -n`을 시도했지만 `bash` 자체가 PATH에 없어 모든 스크립트 문법 검사가 실행되지 않았다. Bash 스크립트 도구라면 `doctor.sh`가 Bash 존재 여부를 명시적으로 검사해야 하지만, `doctor.sh:76-93`은 codex/agy/node만 본다.

## 3. 보안 - 3/10

권한 모델이 문서상으로는 신중하지만 구현이 우회한다. `SKILL.md:245-255`는 프로젝트마다 권한 수준을 확인하고 기록하라고 한다. 그러나 `cross-review.sh:24`와 `cross-review.sh:37`은 항상 `full`로 실행한다. `init.sh:163-166`도 사용자 확인 없이 `수준: 완전자율`, `사유: init.sh 기본값`을 생성한다. 이는 기본값으로 완전자율을 가정하지 않는다는 원칙과 맞지 않는다.

`dispatch.sh:124-127`은 `_agent_reports/.cli-agent-team.conf`를 그대로 source한다. 프로젝트 파일을 실행 코드로 취급하는 패턴이다. 해당 파일을 에이전트나 공격자가 수정할 수 있으면 다음 dispatch에서 임의 셸 코드가 실행된다.

화이트리스트 기반 명령 실행은 실질적으로 약하다. `verify.sh:192-201`은 첫 번째 토큰만 `_wl`에 있는지 확인한다. 하지만 실제 실행은 `verify.sh:202`의 `bash -c "$cmd"`다. 예를 들어 첫 토큰이 `npm`이면 뒤의 셸 연산자, command substitution, 리다이렉션까지 `bash -c`가 해석한다. 화이트리스트가 "실행 파일 첫 단어"만 통제하고 전체 명령 문법은 통제하지 못한다.

스코프와 경로 입력 검증도 부족하다. `worktree-dispatch.sh:29-32`는 `TASK_ID`를 그대로 디렉터리명과 브랜치명에 넣고, `worktree-dispatch.sh:51-55`는 기존 worktree와 브랜치를 `--force`로 제거한다. `TASK_ID` 형식 검증이 없으므로 경로 traversal, 이상한 branch ref, 기존 브랜치 충돌 같은 입력을 방어하지 못한다.

보안 스캔도 제한적이다. `verify.sh:268`은 `git diff HEAD`만 본다. 새로 만든 untracked 파일의 내용은 `git diff HEAD`에 포함되지 않으므로, untracked 파일에 들어간 secret은 `verify.sh:275-284`의 시크릿 패턴 검사를 통과할 수 있다.

## 4. 실용성 - 3/10

5분 온보딩은 현재 상태로는 어렵다. 우선 요청 목록의 `docs/quickstart.md`가 없다. 스킬 내부 목록에도 `docs/` 디렉터리가 없고, 참고 문서는 `references/` 위주다. 사용자가 빠르게 따라 할 표준 진입 문서가 없는 상태다.

래퍼의 `init`도 실제 초기화가 아니다. `agent-team.sh:42`는 `setup.sh`를 호출하지만, `setup.sh:106-124`는 conf만 만든다. `PLAN.md`와 `AGENT_ROLES.md` 생성은 `init.sh:100-145`, `init.sh:159-200`에 있고 래퍼와 연결되지 않았다. `SKILL.md:335-342`의 안내대로 `setup.sh`를 실행하면 핵심 보드가 생길 것처럼 보이지만 실제로는 그렇지 않다.

Windows 안내도 깨져 있다. `setup.sh:168`은 `bash scripts/agent-watch.ps1`라고 출력한다. `.ps1`은 PowerShell 스크립트라 Bash로 실행하는 안내는 틀렸다. `SKILL.md:542-545`는 PowerShell 경로를 따로 안내하지만, setup 완료 메시지가 반대로 말한다.

실패 원인 파악은 일부 가능하지만 신뢰하기 어렵다. `verify.sh`는 스코프, AC, 검증 명령, 증거 파일, 보안 패턴을 출력한다. 그러나 `verify.sh:78-80`은 `## 허용 파일` 섹션이 없으면 건너뛰고, `verify.sh:167-178`은 `AGENT_ROLES.md`나 검증 명령이 없으면 건너뛴다. 필수 계약이 빠졌을 때 실패가 아니라 skip이 되므로 사용자에게 거짓 안정감을 줄 수 있다.

`dashboard.sh`도 실제 프로젝트 대시보드로 쓰기 어렵다. `dashboard.sh:21-24`가 스크립트 설치 위치를 프로젝트 루트로 계산하고, 인자로 프로젝트 경로를 받지 않는다. 여러 프로젝트에 스킬을 적용하는 사용 사례와 맞지 않는다.

## 5. 놓친 것 / 맹점 - 3/10

문서와 구현 불일치가 많다. `SKILL.md:589-597`은 병렬 배정이 `AGENT_ROLES.md`의 "병렬 실행: 허용" 조건일 때만 실행된다고 설명한다. `parallel-check.sh:5-6` 주석도 같은 말을 한다. 하지만 실제 `parallel-check.sh`는 `AGENT_ROLES.md`를 읽지 않고, `parallel-check.sh:111-112`의 선행 태스크 검사와 `parallel-check.sh:133-160`의 허용 파일 충돌만 본다.

dirty worktree 시나리오가 제대로 처리되지 않는다. `dispatch.sh:249-255`는 dispatch 전 변경 파일 목록만 저장한다. `verify.sh:90-99`는 현재 변경 파일에서 pre-dispatch 파일명을 빼고, 전부 기존 변경이면 범위 검사를 생략한다. 이미 dirty였던 파일을 에이전트가 추가로 수정해도 파일명만 같으면 검증에서 빠질 수 있다.

점수 학습도 통계 왜곡이 있다. `record-score.sh:148`은 `total = ac_pass + ac_fail`로 정의한다. 그런데 검증 실패 시 `verify.sh:349-350`은 `record-score.sh`를 `0 0`으로 호출한다. 실패 이유 카운트는 올라가도 total과 승률에는 반영되지 않는다. 완전히 실패한 태스크가 에이전트 라우팅의 승률을 낮추지 않는 구조다.

복잡한 프로젝트에서 무너질 지점은 파일 기반 프로토콜이다. 모든 상태가 `PLAN.md`, `AGENT_ROLES.md`, `_agent_reports/*`에 흩어져 있고, 락/트랜잭션이 없다. 병렬 배정, 대시보드, 점수 기록, 상태 파일 갱신이 동시에 일어나면 `record-score.sh:136-155` 같은 덮어쓰기와 `update-state.sh:33-42` 같은 단순 sed/mv 갱신이 충돌할 수 있다.

`parallel-check.sh`의 파일 충돌 판정도 과도하거나 부정확하다. `parallel-check.sh:146-148`은 문자열 접두사만 비교한다. `src/foo`와 `src/foobar`처럼 경로 경계가 아닌 접두사도 충돌로 볼 수 있고, glob 패턴이나 생성 파일 디렉터리 정책은 해석하지 못한다.

삭제/rename, 바이너리 파일, submodule, generated lockfile, DB migration 같은 실제 프로젝트 변경 유형도 명시적으로 다뤄지지 않는다. 특히 `worktree-dispatch.sh:95-99`가 파일 복사만 하기 때문에 삭제/rename이 누락되는 점은 큰 프로젝트에서 바로 문제가 된다.

## 6. 종합 판정 - 4/10

전체 점수: 4/10.

이 도구를 실제로 쓰겠는가? Conditional. 개인 실험 프로젝트에서 외부 CLI를 수동으로 감시하며 작은 태스크를 나누는 용도라면 제한적으로 쓸 수 있다. 하지만 현재 상태로 팀 프로젝트나 중요한 코드베이스에 바로 투입하지는 않겠다. 이유는 초기화 진입점이 깨져 있고, 권한 모델이 구현에서 우회되며, 검증/보안/점수 기록이 파일 기반 race와 셸 실행 취약점에 노출되어 있기 때문이다.

지금 당장 고쳐야 할 Top 3:

1. 초기화/문서 경로 정리: `agent-team init`이 `init.sh`를 호출하게 하거나 `setup.sh`와 `init.sh`를 합쳐야 한다. `docs/quickstart.md`를 실제로 추가하고, `SKILL.md:335-342`의 setup 설명을 구현과 맞춰야 한다.
2. 권한/명령 실행 보안 수정: `cross-review.sh`의 hardcoded `full` 제거, `init.sh`의 완전자율 기본값 제거, `.cli-agent-team.conf` source 제거, `verify.sh`의 `bash -c "$cmd"`를 안전한 명령 배열 또는 제한된 DSL로 교체해야 한다.
3. 프로젝트 경로/검증 신뢰성 수정: `dashboard.sh`와 `record-score.sh`가 항상 명시적 project dir을 받게 하고, `verify.sh`가 필수 섹션 누락을 skip이 아니라 실패로 처리하게 하며, dirty worktree/신규 untracked 파일 내용/삭제/rename까지 검증해야 한다.
