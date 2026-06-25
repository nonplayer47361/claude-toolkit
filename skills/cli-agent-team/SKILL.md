---
name: cli-agent-team
description: "외부 CLI 코딩 에이전트(Codex CLI, Antigravity CLI(agy) 등)를 서브 에이전트로 부려, Claude를 메인 오케스트레이터로 하는 다중 에이전트 개발 루프를 프로젝트에 구성한다. '멀티에이전트 구성해줘', 'codex랑 agy 오케스트레이션 세팅해줘', '서브 에이전트로 codex/antigravity 부려줘', '다중 에이전트 루프 만들어줘', '이 프로젝트에도 에이전트 협업 구조 적용해줘' 요청 시 사용. 새 프로젝트 아이디어 구상부터 함께 하고 싶을 때('아이디어 회의해줘', '새 프로젝트 구상해줘', '프로젝트 기획부터 같이하자')도 이 스킬로 시작한다. 기존 구성의 점검·역할 재배정·마일스톤 게이트 조정·새 작업 배정 등 후속 운영 요청에도 사용한다. Claude Code 내부 서브에이전트(Agent 도구, Task tool)를 쓰는 멀티에이전트 팀 구성은 `harness` 스킬의 영역이므로 이 스킬과 다르다 — 이 스킬은 codex/agy처럼 별도 프로세스로 실행되는 외부 CLI를 Bash로 직접 호출하는 경우에만 쓴다."
---

# CLI Agent Team — 외부 CLI를 서브 에이전트로 부리는 오케스트레이터

Claude가 메인 오케스트레이터(뇌)가 되어, Codex CLI·Antigravity CLI(agy) 같은 **별도
프로세스로 실행되는 외부 코딩 에이전트**를 서브 에이전트로 부리는 구조를 프로젝트에
세팅한다. 핵심 설계: 상태 저장소(PLAN.md), 명확한 역할+피드백 루프(AGENT_ROLES.md +
`_agent_reports/<task-id>/` 파일 세트), 오케스트레이터 루프, 마일스톤 게이트(인간 개입
지점).

**왜 MCP 서버가 아니라 스킬인가**: 외부 CLI 호출은 Bash로 충분하고(`codex exec`,
`agy --print`), 완료 감지는 하니스의 `run_in_background` 자동 알림으로 충분하다. MCP
서버를 만들면 이미 있는 기능을 감싸는 순수 인다이렉션이 된다. 진짜 재사용 가치는 워크플로우
지식(파일 구조, 각 CLI의 정확한 플래그, 잘 알려진 함정)이고, 이건 스킬 + 번들 스크립트로
충분히 담긴다.

**성숙도 메모**: 이 패턴은 1개 프로젝트(Tarkov Market KO)에서 검증됐다 — 설계 조사
태스크 2건, 실제 코드 구현 태스크 1건(서버+클라이언트 분담)이 헤드리스 자동 배정으로
깨끗하게 완료됐다. 새 프로젝트에 처음 적용할 때는 작은 작업부터 시작해 패턴이 맞는지
확인할 것을 권장한다.

**권한 수준은 프로젝트마다 새로 확인한다 — 절대 기본값으로 가정하지 않는다.** 한
프로젝트에서 완전자율(승인 우회) 모드를 승인받았다고 해서 다른 프로젝트에도 자동 적용
하지 않는다. Phase 1에서 매번 명시적으로 묻는다.

## Phase 0: 현황 확인

1. 프로젝트 루트에 `PLAN.md` + `AGENT_ROLES.md`가 이미 있는지 확인한다.
   - **있으면**: 운영 모드. `_agent_reports/.session_state` 파일을 가장 먼저 읽는다.
     파일이 없으면 `PLAN.md`의 `SESSION_STATE` 블록으로 폴백 (구 버전 프로젝트 호환).
     - 루프 상태 = `단계 N 대기` (1·3·5·8) → 해당 단계부터 바로 재개 (사용자 설명 없이)
     - 루프 상태 = `마일스톤 게이트` → 게이트 보고서를 다시 출력하고 사용자 응답 대기
       (loop 모드 wakeup이 자동으로 이 상태에 도달했을 때도 동일 — 자동 승인 없음)
     - 사용자 요청이 "새 작업 배정"이면 → Phase 5 단계 1
     - "역할/게이트 조정"이면 → 해당 섹션 수정 후 LOG.md 기록
     - "전체 재점검"이면 → Phase 1부터 다시 실행
   - **없으면**: 신규 구축. 두 가지 경로 중 하나 — 사용자에게 확인한다:
     - 만들 것이 이미 정해진 프로젝트에 루프를 추가하는 경우 → **Phase 1**
     - 아이디어·구상 단계부터 함께 잡고 싶은 경우 → **Phase 0-A** (아이디어 회의)
2. `_agent_reports/` 디렉토리와 `.gitignore`의 `_agent_reports/` 항목 존재 여부도 함께 확인한다.

## Phase 0-A: 아이디어 회의 (선택 — 구상 단계부터 시작할 때만)

아이디어가 이미 명확하면 이 Phase를 건너뛰고 Phase 1로 간다.

### 0-A.0: 컨텍스트 자동 감지

프로젝트 루트에서 다음을 확인한다:

```bash
ls -la                         # 파일 존재 여부
git log --oneline -5 2>/dev/null  # 커밋 이력 (있으면 기존 프로젝트)
```

판단 기준:
- `CLAUDE.md` / `README.md` / `package.json` / `*.py` / `src/` 등 **의미 있는 파일이 있으면** → 기존 프로젝트 (0-A.2 트랙)
- `.git`만 있거나 **완전히 빈 폴더이면** → 신규 프로젝트 (0-A.1 트랙)

---

### 0-A.1: 신규 프로젝트 트랙

**Step 1: 프로젝트 유형 선택** (AskUserQuestion, 단일 선택)

선택지:
- 웹 앱 (프론트엔드/백엔드/풀스택)
- CLI 도구 / 스크립트 / 자동화
- 봇 (Discord, Telegram, Slack 등)
- 라이브러리 / SDK / 패키지
- 기타

**Step 2: 유형별 핵심 질문** (AskUserQuestion, 유형에 따라 다른 세트 사용)

| 유형 | 질문 세트 |
|------|-----------|
| 웹앱 | 인증 필요 여부 / DB 유형(없음·SQL·NoSQL) / 배포 환경 |
| CLI/자동화 | 대화형·비대화형 / 대상 OS / 배포 방식(로컬·패키지) |
| 봇 | 플랫폼 / 명령어 기반·대화형 / 외부 API 연동 여부 |
| 라이브러리 | 언어·런타임 / 배포 방식(npm·pypi 등) / 주요 사용자(개발자 유형) |
| 기타 | 어떤 문제를 푸는가 / 누가 쓰는가 / 기술 환경 |

**Step 3: 자유 대화 — Claude가 리드**

"만들고 싶은 것을 편하게 말씀해 주세요. 아이디어 단계라도 괜찮습니다." 라고 열어준다.

사용자가 말하면 Claude는 다음 중 **아직 불명확한 것 하나를 골라 한 번에 하나씩만 묻는다**:

- 핵심 사용자/상황이 모호한가? → "주로 어떤 상황에서 쓸 것 같으세요?"
- 기존 해결책 대비 차별점이 없는가? → "비슷한 도구를 이미 써보셨나요? 뭐가 아쉬웠나요?"
- v1 범위가 불명확한가? → "처음 버전에서 반드시 있어야 할 것 한 가지를 고른다면요?"
- 기술 스택이 미결정인가? → 선호를 묻거나, 없으면 유형+규모 기반으로 Claude가 추천한다

**충분히 구체화된 기준** (아래 세 가지가 답해지면 Step 4로):
1. 한 줄 정의를 쓸 수 있는가 (누가 / 무엇을 / 왜)
2. v1 범위가 명확한가 (넣을 것 vs 나중에 할 것)
3. 기술 스택이 결정됐는가

**Step 4: 정리본 제시 + 확인**

Claude가 다음을 정리해서 보여주고 사용자가 수정·확인한다:
- 한 줄 정의
- 기술 스택
- 첫 번째 마일스톤 (MVP, 목표 기간 포함)
- 에픽 3~5개 + 권장 빌드 순서
- 열린 질문 (아직 결정 안 된 것)

**Step 5: 파일 저장**

확인 후 프로젝트 루트에 두 파일을 생성한다:
- **`BRIEF.md`** — 정리본을 아래 형식으로 저장. git 추적 대상 (프로젝트의 "왜"를 영구 보존)
- **`PLAN.md`** 초안 — 에픽에서 분해한 초기 작업 목록을 "대기" 열에 채운 상태로 생성

`BRIEF.md` 형식:

```markdown
# [프로젝트명] — Project Brief

## 한 줄 정의
[누구]가 [무엇]을 할 수 있는 [종류] 도구

## 배경 / 동기
왜 만드는가. 기존 해결책이 왜 부족한가.

## 목표 (Scope In)
- ...

## 비목표 (Scope Out)
- ...

## 기술 스택
- 언어: ...
- 프레임워크/라이브러리: ...
- 배포: ...

## 첫 번째 마일스톤 (MVP)
[N주 내] 최소 동작 버전: ...

## 에픽 (빌드 순서)
1. [에픽명] — 설명
2. ...

## 열린 질문
- [ ] 아직 결정하지 못한 것
```

---

### 0-A.2: 기존 프로젝트 트랙 (기능 추가)

**Step 1: 기존 컨텍스트 읽기**

`CLAUDE.md`, `README.md`, 폴더 구조, `git log --oneline -5`를 읽어 프로젝트를 파악한다.
`BRIEF.md`가 있으면 함께 읽는다.

**Step 2: 변경 의도 파악**

"어떤 기능을 추가하거나 변경하고 싶으신가요?" 하나만 묻는다.

사용자가 답하면 필요한 경우에만 후속 질문을 한다 (한 번에 하나):
- 기존 기능과 어떻게 다른가? (유사 기능이 이미 있어 보일 때)
- 이번 범위에 포함할 것 vs 나중에 할 것은?
- 영향 받는 파일/모듈 범위는?

**Step 3: 결과**

- `PLAN.md`에 새 에픽/작업 추가 (기존 내용 보존)
- 변경 배경 기록이 필요하면 `BRIEF.md`에 `## 변경 이력 — [날짜]` 섹션 추가

Phase 1로 진행한다.

## Phase 1: CLI 탐지 + 권한 수준 확인 (이 프로젝트 전용)

사용자가 어떤 CLI를 쓸지 명시하지 않았다면, 먼저 후보를 찾는다:

```bash
for c in codex agy claude gemini aider cursor-agent; do command -v "$c" >/dev/null 2>&1 && echo "found: $c"; done
```

**권한 수준을 이 프로젝트에 한해 명시적으로 확인한다** (AskUserQuestion 사용, 2지선다):
1. **완전자율** — `codex exec --dangerously-bypass-approvals-and-sandbox`,
   `agy --print --dangerously-skip-permissions` 등 승인/샌드박스를 우회한다. 속도가
   빠르지만 위험도가 높다는 트레이드오프를 사용자에게 설명한다.
2. **제한된 자율(기본 권장)** — CLI의 기본 승인 모드를 그대로 쓴다. 작업이 파일 시스템/
   네트워크 변경을 요구할 때마다 CLI 자체가 승인을 요청한다(또는 비대화형 실행이 막힐 수
   있음 — 이 경우 사용자가 그때그때 직접 그 CLI 세션을 열어 승인해야 함을 미리 안내한다).

답변을 `AGENT_ROLES.md`에 "이 프로젝트의 권한 수준" 섹션으로 기록한다. 완전자율을
선택했다면 그 이유(사용자가 명시한 근거)도 함께 적어, 다음 세션에서 왜 이 모드인지
추론하지 않고 읽을 수 있게 한다.

각 CLI에 대해 **반드시 비대화형 실행 가능 여부를 실측 검증**한다 — `--help`만 보고
넘어가지 않는다. 검증 절차와 알려진 함정(완전자율 플래그 이름이 CLI마다 다름, 일부 CLI는
헤드리스 모드에서 stdout이 침묵하지만 실제 작업은 수행함, Windows에서 pexpect/winpty가
거의 항상 막힘)은 `references/cli-dispatch-guide.md`를 반드시 읽고 따른다. 검증 없이
"이 CLI는 자동화 가능하다"고 단정하지 않는다.

`scripts/probe-cli.sh <cli-name> <auth-mode>`로 두 가지를 한 번에 확인한다 (auth-mode는
위에서 사용자가 고른 값 그대로 전달 — 스크립트가 임의로 완전자율을 켜지 않는다):
1. 트리비얼 텍스트 응답 요청에 대한 exit code와 실제 응답 전달 여부
2. 트리비얼 파일 쓰기 요청에 대한 실제 파일 생성 여부 (stdout이 비어 있어도 이게 진짜
   판단 기준)

## Phase 2: 역할 분담 설계

기본 원칙: **역할 분담은 프로젝트마다 다르다.** 고정 규칙을 강요하지 않는다.

1. 프로젝트 구조를 분석한다 (`package.json`, 디렉토리 구조, 주요 언어/프레임워크).
2. 자연스러운 분할 축을 찾는다 — 흔한 패턴:
   - 백엔드/프론트엔드 (풀스택 웹 앱)
   - 라이브러리 코어/CLI 인터페이스
   - 구현/테스트 (한쪽이 코드를 쓰고, 한쪽이 검증)
   - 기능 도메인별 (모듈 A 담당, 모듈 B 담당)
3. 분석 결과를 사용자에게 **추천안으로 제시**하고 확인받는다. 강요하지 않는다 — 사용자가
   다르게 정의하면 그대로 따른다.
4. 애매하거나 결과물의 품질이 중요한 작업을 위한 **"비교 검증 병렬 배정"** 규칙도
   설계한다: 같은 작업을 두 에이전트에게 동시에 시켜 결과를 비교 채택하는 경로(git worktree로
   격리, `references/task-templates.md`의 병렬 검증 패턴 참고).
   > 이것은 Phase 5 단계 1의 **"독립 태스크 병렬 배정"**(서로 다른 태스크를 다른 에이전트에
   > 동시 배정)과 다른 개념이다 — 이 단계에서는 "같은 작업을 여러 에이전트가 경쟁"하는 경우를 설계한다.
5. **토큰 경제 + 부하 분산 설계** — 에이전트마다 토큰 소모량과 리셋 주기가 다르다.
   한 에이전트에 작업이 몰리면 리밋으로 전체 진행이 멈춘다. `references/agent-characteristics.md`를
   읽고 다음을 AGENT_ROLES.md에 명시한다:
   - **작업 규모 기준 (소형/중형/대형/분석)**: 범위에 따라 우선 에이전트 결정
   - **기본 라우팅 테이블**: 작업 유형 → 1순위 에이전트 → 폴백 체인
   - **동시 실행 조합**: Codex + agy 병렬은 권장, 같은 공급사 병렬은 주의
   - **리밋 감지 신호 목록**: 로그에서 볼 수 있는 키워드, 비정상 종료 패턴
   - **Claude 토큰 보존 원칙**: Claude는 오케스트레이터(검토·승인·커밋)로만 쓰고,
     코드 직접 구현은 모든 하위 에이전트가 리밋에 걸린 최후 수단으로만 한다

## Phase 3: 상태 저장소 + 역할 문서 생성

프로젝트 루트에 다음을 생성한다 (`references/task-templates.md`의 템플릿을 프로젝트에
맞게 채워서 사용):

- **`PLAN.md`** — 진행 중/대기/완료/보류 섹션을 가진 단일 작업 보드. 모든 작업은 ID를
  가진다. Phase 0-A에서 초안이 이미 있으면 그 내용을 기반으로 보완한다.
- **`_agent_reports/.session_state`** — 루프 상태를 저장하는 별도 파일 (PLAN.md와 분리).
  Claude가 Phase 5 각 주요 단계 전·후에 `scripts/update-state.sh`로 자동 갱신하며,
  새 세션이 시작될 때 이 파일 하나만 읽어도 즉시 재개할 수 있게 한다.

  ```
  갱신: YYYY-MM-DD HH:MM (Asia/Seoul)
  마일스톤: M1 — <마일스톤 이름>
  다음 행동: <task-id> 배정 (<agent> · <규모> · <한 줄 설명>)
  루프 상태: 단계 1 대기
  BLOCKED: (없음)
  루프 모드: manual
  리셋 주기: 0
  루프 프롬프트: cli-agent-team
  ```

  `루프 상태` 가능한 값:
  - `단계 1 대기` — 다음 태스크 선택 전
  - `단계 3 완료 대기` — 검토 디스패치 후 REVIEW.md 대기 중
  - `단계 5 완료 대기` — 실행 디스패치 후 REPORT.md 대기 중
  - `단계 8 피드백 대기 (N회차)` — FEEDBACK.md 재배정 후 REPORT.md 대기 중
  - `마일스톤 게이트` — 사용자 검토 대기

  `루프 모드` 값:
  - `manual` — rate limit 시 사용자가 수동으로 재개 (일반 세션)
  - `loop` — rate limit 후 자동 재개 (`/loop` 모드, ScheduleWakeup 사용)

  `리셋 주기`: loop 모드일 때만 사용. 사용자 rate limit 리셋 주기를 초 단위로 저장.
  예: 5시간 = 18000, 5시간 5분 여유 포함 = 18300.

  `루프 프롬프트`: loop 모드일 때 ScheduleWakeup에 전달할 prompt 값.
  사용자가 `/loop cli-agent-team`으로 시작했으면 `cli-agent-team` 저장.

  생성 방법 (Phase 3에서 한 번) — `setup.sh`를 사용하면 이 파일을 포함해 PLAN.md·
  AGENT_ROLES.md·LOG.md·.gitignore 항목이 한 번에 생성된다:
  ```bash
  bash ~/.claude/skills/cli-agent-team/scripts/setup.sh
  # 프로젝트 경로가 현재 디렉토리와 다를 경우:
  bash ~/.claude/skills/cli-agent-team/scripts/setup.sh /abs/path/to/project
  ```
  생성 후 각 파일의 `<...>` 플레이스홀더를 채운다.
- **`AGENT_ROLES.md`** — Phase 1에서 정한 이 프로젝트의 권한 수준(+사유), Phase 2에서 정한
  역할 분담, **작업 라우팅 테이블 + 폴백 체인 + 리밋 감지 기준** (Phase 2 토큰 경제 설계 결과),
  TASK/TODO/REPORT/FEEDBACK 파일 프로토콜, 도메인별 코딩 규칙, 검토 체크리스트,
  마일스톤 게이트(Phase 4), 디렉토리 규칙.
  라우팅 테이블 초안은 `references/agent-characteristics.md`의 "기본 라우팅 규칙"을
  복사해서 이 프로젝트 특성에 맞게 조정한다.
- **`_agent_reports/`** — 작업별 산출물 디렉토리. `.gitignore`에 추가한다 (영구 보존
  대상이 아닌 작업 로그이기 때문 — 단, 사용자가 감사 추적용으로 보존을 원하면 추적 대상으로
  둔다. 이 경우 LOG.md가 git 히스토리에 그대로 남는다는 점을 사용자에게 알린다).

## Phase 4: 마일스톤 게이트 설계

**권한 수준(Phase 1)**과 **인간 개입 마일스톤**은 별개의 축이다 — 제한된 자율이든
완전자율이든 둘 다 게이트는 필요하다 (게이트는 "오케스트레이터가 다음 작업을 스스로 고를
자유"를 통제하는 것이고, 권한 수준은 "CLI 한 번 실행이 승인 없이 도는가"를 통제하는 것이라
다른 문제다). 사용자에게 다음을 확인한다:

1. **구조적 결정 게이트**: 새 의존성 추가, 외부 서비스/OAuth 연동, 데이터 스키마 변경,
   아키텍처 변경 등이 나오면 항상 멈추고 승인받는다 (기본, 끄지 않는 것을 권장).
2. **완료 개수 게이트**: 완료 작업이 N개(기본 3, 사용자 조정 가능) 쌓일 때마다 멈추고
   지금까지 요약 + 다음 후보를 제시한다.
3. 게이트에 도달하면 진행 중인 백그라운드 작업은 완료까지 두고, **검토·커밋까지는
   수행한 뒤** 다음 작업을 스스로 배정하지 않고 사용자 응답을 기다린다.

## Phase 4.5: 루프 재개 방식 설정

사용자에게 두 가지 방식 중 하나를 선택받는다:

```
루프 재개 방식을 선택해 주세요:

[1] 일반 세션 (기본)
    rate limit으로 루프가 끊기면 멈춤.
    재개할 때 "계속" 입력 → SESSION_STATE 읽고 즉시 이어서 진행.

[2] /loop 자동 재개
    rate limit 리셋 후 자동으로 루프를 재개.
    컴퓨터만 켜져 있으면 프로젝트 완성까지 자율 동작.
    단, 에이전트 데몬(agent-watch.ps1)도 계속 실행 중이어야 함.
```

**[2] 선택 시 추가 질문 (두 가지):**

```
Q1. Claude rate limit 전체 사이클이 얼마나 되나요?
    (리셋부터 다음 리셋까지의 간격 — 보통 5시간)
    예: "5시간", "4시간 30분"

Q2. 지금 당장 rate limit이 걸려 있나요?
    [예] → 리셋 후 /loop 를 시작하는 것을 권장합니다
           (리셋 직후 시작하면 Q1의 전체 사이클을 온전히 씁니다)
    [아니오] → 지금 바로 시작 가능합니다
```

Q1 답변을 초 단위로 계산하고 5분(300초) 여유를 더한다.
예: "5시간" → (5 × 3600) + 300 = 18300초.

계산 결과를 SESSION_STATE에 저장한다:
- `루프 모드: loop`
- `리셋 주기: <계산된 초>` (모든 사이클에서 이 값을 안전망 간격으로 사용)
- `루프 프롬프트: cli-agent-team` (사용자가 `/loop cli-agent-team`으로 시작한 경우)

그 다음 시작 명령을 안내한다:

```
설정 완료. 아래 명령으로 자율 루프를 시작하세요:

  /loop cli-agent-team

주의:
  - 반드시 /loop 로 시작해야 자동 재개가 작동합니다
  - 에이전트 데몬이 실행 중이어야 합니다:
      Windows: VS Code 터미널 패널에서 agent-watch.ps1 실행
      Linux/macOS: tmux 세션에서 bash agent-watch.sh 실행
  - 컴퓨터가 켜져 있어야 합니다 (절전 모드이면 타이머 정지)
  - 마일스톤 게이트에서 "계속" 입력은 여전히 필요합니다 (BLOCKED 없는 경우 자동 통과)
```

## (선택) IDE 멀티터미널 셋업 — 양방향 실시간 모드

> 이 단계는 선택사항이다. 설정하면 Claude가 작업을 배정할 때마다 각 에이전트가 **자동으로
> 실행**되고, VS Code 터미널 패널에서 실시간으로 진행 상황을 볼 수 있다.
>
> 설정하지 않으면(직접 모드) Claude가 `dispatch.sh`를 직접 실행하며, 각 CLI 프로세스는
> Claude Code 세션 내부에서 run_in_background로 돈다 — 터미널 패널에서 별도로 볼 수 없다.

### 두 가지 운영 모드

| | 직접 모드 (기본) | 데몬 모드 (권장) |
|---|---|---|
| **에이전트 시작** | Claude가 dispatch.sh 실행 | 에이전트가 터미널 패널에서 항상 대기 |
| **실시간 확인** | Claude Code 로그만 | 각 에이전트 전용 패널에서 출력 확인 |
| **배정 방식** | `dispatch.sh` | `trigger.sh` (데몬에 신호 전달) |
| **완료 감지** | harness 프로세스 종료 알림 | 데몬이 status 파일 기록 → trigger.sh가 감지 |

### 데몬 모드 시작 방법

**VS Code에서 터미널 패널을 분할해서 각 에이전트를 켠다.**

```
┌──────────────────────────────────────────────────┐
│  패널 1: Claude Code (메인 — 이 스킬 실행)         │
│  $ claude                                        │
├───────────────────┬──────────────────────────────┤
│  패널 2: Codex 데몬│  패널 3: agy 데몬             │
│  $ pwsh           │  $ pwsh                      │
│  > .\scripts\     │  > .\scripts\                │
│    agent-watch.ps1│    agent-watch.ps1           │
│    -Agent codex   │    -Agent agy                │
│    -AuthMode full │    -AuthMode full            │
└───────────────────┴──────────────────────────────┘
```

`-ProjectDir`를 지정하지 않으면 실행 위치(pwd)가 프로젝트 루트가 된다. 프로젝트 루트에서
실행하거나 절대경로를 지정한다:

```powershell
# 프로젝트 루트가 다른 폴더일 때
.\scripts\agent-watch.ps1 -Agent codex -AuthMode full -ProjectDir "C:\projects\my-app"
```

데몬이 켜지면 `_agent_reports/.daemon_codex`, `_agent_reports/.daemon_agy` 마커 파일이
생긴다. Claude는 이 파일로 데몬 실행 여부를 판단한다.

### Claude가 배정할 때 — 자동 분기

Phase 5 단계 3·5에서 CLI를 실행할 때:

```bash
# 데몬 파일 존재 확인
ls _agent_reports/.daemon_codex  # 있으면 데몬 모드

# 데몬 모드
bash scripts/trigger.sh codex T001 review

# 직접 모드 (데몬 없을 때)
bash scripts/dispatch.sh codex T001 full . review
```

`trigger.sh`는 데몬이 없으면 명확한 오류를 낸다(무한 대기 없음).

### 상태 파일 구조 (데몬 모드 전용)

```
_agent_reports/
  .daemon_codex            ← codex 데몬 실행 중 마커 (데몬이 기록·제거)
  .daemon_agy              ← agy 데몬 실행 중 마커
  .pending_codex           ← Claude→Codex 트리거 (task-id + mode)
  .pending_agy             ← Claude→agy 트리거
  .status_T001_codex       ← IN_PROGRESS | DONE (데몬이 기록, trigger.sh가 감지)
  .status_T001_agy
  .log_codex.txt           ← 데몬이 기록하는 실행 로그
  .log_agy.txt
```

---

## Phase 5: 오케스트레이터 루프 (운영)

신규 구축이 끝났거나, 기존 구성에서 새 작업을 배정할 때 이 루프를 실행한다.

**자율 루프 원칙**: 마일스톤 게이트를 제외한 모든 태스크는 Claude가 자동으로
선택·디스패치·검증·커밋·다음 태스크 진행한다. 사용자와의 대화는
초기 아이디어 구체화(Phase 0~4)와 마일스톤 게이트에서만 이루어진다.
Claude rate limit으로 루프가 끊겨도 새 세션이 SESSION_STATE를 읽어 즉시 재개한다.

각 작업은 에이전트 검토(REVIEW.md) → Claude 자체 승인 → 실행 순서를 거친다.
에이전트가 REVIEW.md를 제출하면 Claude가 직접 판단해 진행 여부를 결정한다.
태스크별 사용자 승인은 필요하지 않다 (중대한 우려사항이 있을 때만 게이트 발동).

**[단계 0] 루프 초기화 (루프 시작 시 항상)**

**/loop 모드 안전망 예약 (loop 모드일 때만):**

SESSION_STATE의 `루프 모드`가 `loop`이면, 루프 시작 직후 아래를 호출한다:

```
ScheduleWakeup(
  delaySeconds = SESSION_STATE.리셋_주기,
  reason       = "rate limit 안전망 — 끊겨도 자동 재개",
  prompt       = SESSION_STATE.루프_프롬프트
)
```

이 호출이 안전망이다: 이번 반복이 정상 완료되면 단계 7에서 10초짜리로 덮어쓴다.
Claude가 rate limit으로 중간에 끊기면 이 5시간짜리 예약이 발동해 자동 재개된다.

**에이전트 데몬 상태 확인:**

`_agent_reports/.daemon_codex`, `_agent_reports/.daemon_agy` 파일 존재 여부를 확인한다.

- **두 파일 모두 있음** → 데몬 실행 중, 루프 계속
- **하나라도 없음** → 데몬 미실행. 루프 모드에 따라 분기한다:

  **manual 모드 (또는 직접 선택 시):**
  ```
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  에이전트 데몬을 터미널에서 실행해주세요.

  [Windows — VS Code 터미널 패널]
    cd "<이 프로젝트 경로>"
    ~\.claude\skills\cli-agent-team\scripts\agent-watch.ps1 -Agent codex -AuthMode full
    (agy도 동일, -Agent agy)

  [Linux / macOS / WSL — tmux 또는 별도 터미널]
    cd "<이 프로젝트 경로>"
    bash ~/.claude/skills/cli-agent-team/scripts/agent-watch.sh codex full
    (agy도 동일, 첫 번째 인수를 agy로)

  실행 후 "완료"라고 말씀해 주세요.
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ```

  **loop 모드 (자동 재개로 깨어난 경우):**
  데몬이 꺼져 있으면 5분 후 재확인을 예약하고 대기한다:
  ```
  ⏸️ 에이전트 데몬이 감지되지 않습니다.
  Windows: VS Code에서 scripts\agent-watch.ps1 패널을 다시 실행해 주세요.
  Linux/macOS: tmux 세션에서 bash scripts/agent-watch.sh <agent> <auth-mode> 를 실행해 주세요.
  5분 후 자동으로 재확인합니다.
  ```
  ```
  ScheduleWakeup(
    delaySeconds = 300,
    reason       = "데몬 재시작 확인",
    prompt       = SESSION_STATE.루프_프롬프트
  )
  ```
  → 5분 후 다시 단계 0부터 시작. 데몬이 켜져 있으면 루프 계속, 없으면 재반복.

데몬 없이 직접 모드로 진행하길 원하면 사용자에게 묻는다 (manual 모드 한정).
직접 모드에서는 `dispatch.sh`를 `run_in_background`로 호출한다.

**[단계 1] 작업 선택 (자동)**

`PLAN.md` "진행 대기" 섹션에서 다음 태스크를 **사용자 입력 없이** 자동으로 선택한다.
우선순위: ① 마일스톤 순서 ② 의존성 충족 여부 ③ 배정 순서.

의존성 규칙:
- 선행 태스크가 DONE이어야 선택 가능
- 선행 태스크가 BLOCKED이면 해당 태스크도 건너뛰고 "⏸️ 선행 BLOCKED" 메모를 달아
  PLAN.md "보류" 섹션으로 이동한다 (마일스톤 게이트에서 사용자에게 보고)

"진행 대기" 태스크가 없고 현재 마일스톤의 모든 태스크가 DONE/BLOCKED이면
→ 단계 9(마일스톤 게이트)로 즉시 이동한다.

**[선택적] 병렬 배정 — AGENT_ROLES.md에 "병렬 실행: 허용"인 경우에만:**

1순위 태스크(T-A) 선택 후, 대기 목록에 후보 태스크(T-B)가 있으면:
```bash
bash scripts/parallel-check.sh <T-A> <T-B> <project-dir>
```
- **exit 0** → T-A는 1순위 에이전트에, T-B는 다른 공급사 에이전트에 동시 dispatch
  (step 3 검토는 각각 진행, step 5는 동시 dispatch, step 7은 둘 다 통과 후 하나의 커밋)
- **exit 1** → 순차 실행 (기존 흐름 유지)

병렬 dispatch 시 두 태스크의 완료 알림을 **모두** 기다린 뒤 step 6으로 진행한다.
어느 한쪽이 실패해도 다른 쪽 커밋은 정상 처리하고, 실패 쪽만 step 8로 넘긴다.

**[단계 1.5] 에이전트 선택 — 적응형 배분**

TASK.md를 작성하기 전에 어느 에이전트에 배정할지 결정한다.
배분 비율은 고정이 아니라 LOG.md에 쌓인 리밋 이벤트 기록을 보고 동적으로 결정한다.

```
1. LOG.md 상단 "현재 배정 창" 표 읽기
   → 에이전트별 window 값과 현재 세션 작업 수 확인

1.5. 시간대 패턴 확인 (선택적, 데이터가 쌓인 경우)
   bash scripts/analyze-limits.sh <project-dir>
   → 현재 시간대 리밋 빈도가 높은 에이전트는 우선순위를 한 단계 낮춘다:
     - 리밋 2회↑: 해당 에이전트 우선순위 -1단계 (이번 배정 한정)
     - 리밋 4회↑: 해당 에이전트 건너뛰고 폴백부터 시작

2. 작업 규모 판단 (소형/중형/대형/분석) → AGENT_ROLES.md 라우팅에서 1순위 에이전트(E) 확인

3. E의 현재 세션 작업 수 < window[E] → E 배정 가능
   E의 현재 세션 작업 수 ≥ window[E] → 다음 우선순위 에이전트로 이동 (2번 반복)

4. 모든 에이전트가 window 초과 상태이면:
   도메인 1순위 에이전트 배정, LOG.md에 "⏭️ 창 초과 배정" 기록

5. 배정 결정 후 LOG.md의 해당 에이전트 "현재 세션 작업 수" +1
```

**리밋 감지 신호** (배정 후 이 신호가 오면 단계 6에서 window 조정):
- dispatch.sh 완료 후 REPORT.md 없음/비어 있음 + 로그에:
  `rate limit` / `429` / `quota exceeded` / `usage limit` / `too many requests`
- 정상 작업 시간보다 훨씬 빠른 종료 (실질적 작업 없이 exit 0)
- agy: `--print-timeout` 초과 (지나치게 큰 작업이거나 리밋)

**[단계 2] TASK.md 작성**

`_agent_reports/<task-id>/TASK.md`를 작성한다 (`references/task-templates.md` 형식).
두 에이전트가 맞물리는 작업(예: 서버+클라이언트)이면 `_agent_reports/<task-id>-CONTRACT.md`로
인터페이스 계약을 먼저 고정하고 양쪽 TASK.md가 참조하게 한다.

**[단계 3] 검토 디스패치**

디스패치 직전 `.session_state`를 갱신한다 (중간 단계 끊김 후에도 정확히 재개 가능):
```bash
bash scripts/update-state.sh "루프 상태" "단계 3 완료 대기" <project-dir>
bash scripts/update-state.sh "다음 행동" "<task-id> 검토 대기 (<agent>)" <project-dir>
```

`scripts/dispatch.sh <cli> <task-id> <auth-mode> [dir] review` 로 실행한다 (`run_in_background: true`).
에이전트는 `BRIEF.md` + `TASK.md`를 읽고 **코드를 건드리지 않고** `REVIEW.md`만 작성한다.

검토 단계를 생략해도 되는 경우 (AGENT_ROLES.md에 명시할 것):
- 오타·설정값·주석 수정처럼 의도가 100% 명확한 단순 작업

**[단계 4] 검토 결과 판단 — Claude 자체 승인**

완료 알림이 오면 `REVIEW.md`를 읽고 Claude가 직접 판단한다:

**자동 진행 조건 (모두 해당하면 단계 5로 즉시 이동):**
- 에이전트가 TASK.md 의도를 올바르게 이해함
- "우려사항" 없음 또는 경미한 수준 (스타일·선택적 개선 등)
- "질문/막힌 점" 없음
- 예상 영향 범위가 TASK.md에 명시된 스코프를 벗어나지 않음

**게이트 발동 조건 (사용자에게 보고 후 대기):**
- 에이전트가 TASK.md 의도를 잘못 이해함 → TASK.md 수정 후 단계 3 재검토
- 아키텍처 변경·새 의존성·스코프 확장 같은 중대한 우려사항 → 사용자 확인
- 선행 태스크 완료 전 구현 불가 → 태스크를 BLOCKED 처리

게이트 발동 시 출력 형식:
```
⚠️ [에이전트명] REVIEW.md — <task-id> 게이트 발동

이유: <구체적 우려사항>
에이전트 이해: <요약>
필요한 결정: <사용자에게 묻는 것>
```

**[단계 5] 실행 디스패치**

디스패치 직전 `.session_state`를 갱신한다:
```bash
bash scripts/update-state.sh "루프 상태" "단계 5 완료 대기" <project-dir>
bash scripts/update-state.sh "다음 행동" "<task-id> 실행 대기 (<agent>)" <project-dir>
```

`scripts/dispatch.sh <cli> <task-id> <auth-mode> [dir] execute` 로 실행한다 (`run_in_background: true`).
stdout → `_agent_reports/<task-id>/_<cli>_stdout.log`. **폴링하지 않는다.**

Claude가 임의로 새 터미널 창을 띄우지 않는다. 실시간 로그 확인 방법은
`references/cli-dispatch-guide.md` 참고.

**[단계 6] 완료 검증 (자동 + 수동)**

완료 알림이 오면 `verify.sh`를 먼저 실행한다:

```bash
bash scripts/verify.sh <task-id> <project-dir>
```

verify.sh가 자동으로 네 가지를 검사한다:
1. **스코프 초과** — TASK.md `## 허용 파일` 외 변경 여부 (`git diff --name-only HEAD`)
2. **AC 체크리스트** — REPORT.md `## AC 체크리스트` 미완료 항목([ ]) 여부
3. **자동 검증 명령어** — AGENT_ROLES.md `## 자동 검증 명령어` 실행 (lint/test/build)
4. **완료 증거 파일** — TASK.md `## 완료 증거 파일` 목록의 파일 존재·변경 여부 (agy stdout 침묵 대응)

**결과에 따른 처리:**

- **exit 0 (통과)** →
  - REPORT.md "의견 및 제안", "질문/막힌 점" 읽기 (구조적 사안은 PLAN.md에 기록)
  - `git diff` 최종 코드 확인 (품질 검토 목적)
  - 단계 6.5로

- **exit 1 (실패)** →
  - verify.sh 출력에 실패 항목이 이미 정리됨 → 그대로 FEEDBACK.md에 포함
  - 단계 6.5 건너뜀 → 단계 8(재배정)으로 바로 이동

**"exit 0" ≠ "완료"** 원칙 유지 — verify.sh는 기계적 검사. 의미 있는 git diff가 없거나
REPORT.md가 비어 있으면 verify.sh 자체가 exit 1을 반환한다.

**[단계 6.5] LOG.md 업데이트 — 배분 학습**

검증 결과를 LOG.md에 기록하고 window를 조정한다:

**성공한 경우:**
- 이벤트 이력에 `✅ 완료` 행 추가 → `bash scripts/log-event.sh <task-id> <agent> <size> "✅ 완료" <count>`
- "현재 세션 작업 수"는 이미 단계 1.5에서 +1 됐으므로 유지
- 연속 성공 세션 카운터는 세션이 끝날 때(다음 리밋 발생 전) 집계

**리밋이 감지된 경우:**
- 이벤트 이력에 `⚠️ 리밋` 행 추가 → `bash scripts/log-event.sh <task-id> <agent> <size> "⚠️ 리밋" <count>`
- window 조정: `window[에이전트] = max(1, 현재_세션_작업수 - 1)`
- "현재 세션 작업 수" → 0 리셋, "연속 성공 세션" → 0 리셋
- 폴백 에이전트에 같은 TASK.md 재배정, LOG.md에 `🔁 폴백` 행 추가
- 모든 폴백 실패 →
  - **manual 모드**: PLAN.md "보류" + 사용자 알림 (루프 일시 정지)
  - **loop 모드**: 단계 8의 3회 초과와 동일하게 자동 BLOCKED 처리 후 단계 1로 이동
    (마일스톤 게이트에서 사용자에게 일괄 보고)

**세션 종료 판단 + window 성장:**
한 작업 배정 직전에 "현재 세션 작업 수 = 0이고 연속 성공 세션 ≥ 2"이면:
- `window[에이전트] = min(window + 1, 10)` 로 늘림
- "연속 성공 세션" → 0 리셋

**[단계 7] 커밋 + SESSION_STATE 갱신 + 다음 반복 예약**

통과하면 다음 순서로 진행한다:
1. `PLAN.md` 태스크 상태를 DONE으로 갱신
2. **Claude가 직접** 커밋한다 — 에이전트는 절대 커밋하지 않는다
3. 커밋 직후 `_agent_reports/.session_state`를 갱신 (PLAN.md가 아닌 별도 파일):
   ```bash
   bash scripts/update-state.sh "루프 상태" "단계 1 대기" <project-dir>
   bash scripts/update-state.sh "마일스톤" "M<N> — <마일스톤 이름>" <project-dir>
   bash scripts/update-state.sh "다음 행동" "<next-task-id> 배정 (<agent> · <규모> · <설명>)" <project-dir>
   bash scripts/update-state.sh "BLOCKED" "<없음 또는 태스크 목록>" <project-dir>
   ```
4. **/loop 모드일 때:** 즉시 다음 반복을 예약해 단계 0의 안전망을 덮어쓴다:
   ```
   ScheduleWakeup(
     delaySeconds = 10,
     reason       = "다음 태스크 즉시 시작",
     prompt       = SESSION_STATE.루프_프롬프트
   )
   ```
   → 10초 후 harness가 Claude를 다시 호출 → SESSION_STATE 읽고 단계 0부터 재개

**[단계 8] 피드백 작성 + 재배정 (Claude는 코드를 직접 수정하지 않는다)**

미흡하면 **규모와 관계없이 항상** 에이전트에게 돌려보낸다.
오타·1~3줄 수정도 예외 없이 재배정한다 — Claude가 직접 건드리면 토큰 소모 대비 효율이 낮고,
모든 코드 변경이 에이전트로부터 나와야 감사 추적이 깔끔하다.

**Claude가 하는 것 (코드가 아닌 지시):**

1. `_agent_reports/<task-id>/FEEDBACK.md` 작성 — 다음을 반드시 포함:
   - **무엇이 문제인가**: 파일명:라인 수준으로 구체적으로 지목
   - **왜 문제인가**: BRIEF.md의 의도와 어떻게 어긋나는가
   - **어떻게 수정할 것인가**: 에이전트가 판단 없이 실행 가능한 수준으로 기술
   - **건드리지 말아야 할 것**: 수정 범위 명시 (스코프 초과 방지)

2. 재배정 방식 결정:
   - **세션 이어가기 지원 CLI** → 우선 사용 (에이전트가 이전 컨텍스트를 기억하므로 효율적)
     `codex exec resume --last "FEEDBACK.md 읽고 지적 사항만 수정해줘"`
     `agy --continue --print "FEEDBACK.md 읽고 지적 사항만 수정해줘" --add-dir <dir>`
   - **세션이 만료됐거나 이어가기 불가** →
     `dispatch.sh <cli> <task-id> <auth-mode> [dir] feedback`

3. 재배정 직전 `.session_state` 갱신:
   ```bash
   bash scripts/update-state.sh "루프 상태" "단계 8 피드백 대기 (N회차)" <project-dir>
   bash scripts/update-state.sh "다음 행동" "<task-id> 재배정 (<agent> · N회차)" <project-dir>
   ```
4. LOG.md에 재배정 이벤트 기록 (task-id, 회차 N, 에이전트, 타임스탬프)

**재배정 횟수 상한 — 3회 초과 → 자동 BLOCKED 처리 후 루프 유지:**
같은 task-id에 FEEDBACK 재배정이 3회를 넘으면 루프를 멈추지 않고 자동 처리한다:
1. 태스크를 PLAN.md `BLOCKED` 섹션으로 이동 (사유: "3회 피드백 미해결")
2. **의존성 연쇄 처리**: 이 태스크를 선행으로 가진 다른 태스크도
   "⏸️ 선행 BLOCKED" 메모를 달아 보류 섹션으로 이동시킨다
3. `.session_state` 갱신 후 단계 1로 돌아가 다음 태스크를 선택한다:
   ```bash
   bash scripts/update-state.sh "BLOCKED" "<task-id> (3회 피드백 미해결)" <project-dir>
   bash scripts/update-state.sh "루프 상태" "단계 1 대기" <project-dir>
   ```
4. BLOCKED 항목 전체는 단계 9 마일스톤 게이트에서 사용자에게 일괄 보고한다

**[단계 9] 게이트 확인 + 마일스톤 완료 자동 감지**

**자동 마일스톤 완료 감지**: 현재 마일스톤의 모든 태스크가 DONE 또는 BLOCKED이면
(단계 1에서 "진행 대기 없음" 감지 시 여기로 이미 이동했을 수 있음)
→ 아래 게이트 보고서를 작성한다.

**[loop 모드 자동 통과 판정]** — 보고서 작성 후 다음을 검사:

| 조건 | 통과 기준 |
|------|---------|
| BLOCKED 태스크 | 0개 |
| 마지막 verify.sh | exit 0 |
| 구조적 결정 게이트 | 미발동 (새 의존성·스키마 변경·OAuth 없음) |

**모두 해당** → 자동 통과:
1. 게이트 보고서를 `_agent_reports/.milestone_M<N>_report.md`에 저장 (사용자가 나중에 확인 가능)
2. `.session_state`를 다음 마일스톤으로 갱신:
   ```bash
   bash scripts/update-state.sh "마일스톤" "M<N+1> — <다음 마일스톤 이름>" <project-dir>
   bash scripts/update-state.sh "루프 상태" "단계 1 대기" <project-dir>
   ```
3. 단계 1로 즉시 진행 (사용자 입력 없음)

**하나라도 미해당** → loop 모드라도 사용자 게이트 발동 (아래 형식 출력 후 대기):

```
🏁 마일스톤 게이트 — <마일스톤명>

완료 태스크 (<N>개):
  ✅ T001 — <설명> (커밋: <해시>)
  ...

BLOCKED 태스크 (<M>개):
  🚫 T003 — <설명> (사유: <이유>)
  ⏸️ T004 — 선행 BLOCKED (T003)
  ...

의도 달성 여부: <현재 상태 요약>
다음 마일스톤: M2 — <마일스톤명> (<태스크 수>개 대기)

→ 확인 후 "계속"이라고 말씀해 주시면 M2를 시작합니다.
  BLOCKED 항목 처리 지시가 있으면 반영 후 재개합니다.
```

Phase 4의 "구조적 결정 게이트" (새 의존성·스키마 변경·OAuth 등)에 걸리면:
loop 모드 여부 관계없이 위 형식으로 보고하고 사용자 응답을 기다린다.

사용자가 "계속"을 확인하면 `.session_state`를 다음 마일스톤으로 갱신하고 단계 1로 돌아간다.

## Phase 6: CLAUDE.md 포인터 등록

`harness` 스킬과 동일한 원칙 — CLAUDE.md에는 포인터만 남긴다 (전체 내용은 PLAN.md/
AGENT_ROLES.md가 단일 출처):

```markdown
## 다중 에이전트 개발 루프

**구성:** Claude(오케스트레이터) + {탐지된 CLI 목록}(서브 에이전트). 권한 수준·역할
분담 상세는 AGENT_ROLES.md, 작업 현황은 PLAN.md 참고.

**새 세션 시작 시:** `_agent_reports/.session_state` 파일을 가장 먼저 읽는다
(없으면 PLAN.md의 `SESSION_STATE` 블록 폴백).
"루프 상태: 단계 N 대기"가 있으면 설명 없이 그 단계부터 즉시 재개한다.

**트리거:** 새 기능/버그 작업 요청 시 `cli-agent-team` 스킬로 PLAN.md를 확인하고 루프를
이어간다. 구성 변경(역할/게이트/권한 조정)도 동일 스킬 사용.
```

## 검증

신규 구축 완료 후, 작은 실제 작업(설계 조사처럼 코드 변경 없는 것이 안전) 하나를 실제로
배정해서 전체 루프(배정→백그라운드 실행→완료 알림→검토→PLAN.md 갱신)가 끊김 없이
도는지 확인한다. 첫 실행에서 문제가 생기면 `references/cli-dispatch-guide.md`의 알려진
함정 목록에 추가한다.

## 참고

- 에이전트 특성·토큰 경제·라우팅 전략: `references/agent-characteristics.md`
- CLI별 정확한 플래그, 알려진 함정, 세션 이어가기 방법: `references/cli-dispatch-guide.md`
- TASK/REVIEW/TODO/REPORT/FEEDBACK/CONTRACT 파일 템플릿: `references/task-templates.md`
- BRIEF.md 빈 템플릿: `references/brief-template.md`
- 번들 스크립트:
  **초기화·설정**
  - `scripts/setup.sh` — 신규 프로젝트 구조 한 번에 생성 (Phase 3 진입 시 실행)
  - `scripts/probe-cli.sh` — Phase 1 CLI 비대화형 실행 가능 여부 검증

  **에이전트 데몬**
  - `scripts/agent-watch.ps1` — Windows 에이전트 데몬 (VS Code 터미널 패널)
  - `scripts/agent-watch.sh` — Linux/macOS/WSL 에이전트 데몬 (tmux/screen)
  - `scripts/watch-log.ps1` — Windows 실시간 로그 보기 (사용자 직접 실행)

  **루프 실행**
  - `scripts/dispatch.sh` — CLI 직접 배정 (review | execute | feedback 모드)
  - `scripts/trigger.sh` — 데몬 모드에서 .pending 파일로 신호 전달
  - `scripts/parallel-check.sh` — 두 태스크의 병렬 배정 안전 여부 판정

  **상태 관리**
  - `scripts/update-state.sh` — .session_state 특정 필드 업데이트 (Phase 5 각 단계)

  **검증·학습**
  - `scripts/verify.sh` — Phase 5 단계 6 자동 검증 (스코프·AC·테스트·증거파일 4종)
  - `scripts/log-event.sh` — LOG.md 이벤트 행 추가 (리밋 시 [HOUR:XX] 태그 자동 포함)
  - `scripts/analyze-limits.sh` — 시간대별 리밋 패턴 분석 → 배정 에이전트 우선순위 조정
