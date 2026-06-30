# 5분 안에 첫 태스크 실행하기

관련: [[skills/cli-agent-team/SKILL.md]] | [[PLAN.md]]

---

## 전제 조건

- cli-agent-team 스킬 설치됨 (`.\scripts\install-skill.ps1 -SkillName cli-agent-team`)
- codex 또는 agy CLI 중 하나 이상 설치됨
- 프로젝트 루트에 git 저장소 존재

---

## 1단계 — 프로젝트 초기화 (1분)

```bash
cd /path/to/your/project
bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh init
```

대화형으로 묻는 사항에 답하면 `PLAN.md`, `AGENT_ROLES.md`, `_agent_reports/` 구조가 생성된다.

---

## 2단계 — TASK.md 작성 (1분)

`_agent_reports/T001/TASK.md` 파일을 만든다:

```markdown
---
task_type: code_implementation
---

## 태스크 설명
README.md 파일에 설치 방법 섹션을 추가하라.

## 완료 기준 (AC 체크리스트)
- [ ] ## 설치 방법 섹션이 README.md에 추가됨
- [ ] npm install 명령어가 포함됨

## 허용 파일
- README.md

## 완료 증거 파일
- README.md 수정됨
```

`task_type` 필드가 있어야 적응형 에이전트 배정이 활성화된다.

---

## 3단계 — 에이전트 배정 (1분)

```bash
bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh dispatch codex T001 full . execute
```

Claude Code 채팅에서도 가능:

```
codex로 T001 태스크를 execute 모드로 배정해줘
```

에이전트 선택 기준:
| 에이전트 | 적합한 작업 |
|----------|------------|
| `codex`  | 코드 버그 수정, 짧은 구현, 진단 |
| `agy`    | 복잡한 구현, 리팩토링, 문서 작성 |
| `auto`   | `.agent_scores.json` 기반 자동 선택 |

---

## 4단계 — 결과 검증 (30초)

에이전트가 완료(REPORT.md 작성)하면:

```bash
bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh verify T001
```

검증 항목 5가지:
1. 스코프 초과 여부 (`허용 파일` 외 변경 없음)
2. AC 체크리스트 완료 여부
3. 자동 검증 명령어 통과 (`AGENT_ROLES.md` 기준)
4. 완료 증거 파일 존재/변경 확인
5. 보안 패턴 스캔

---

## 5단계 — 커밋 또는 재배정

**✅ 통과 시:**
```bash
git add README.md
git commit -m "feat: T001 — README 설치 방법 추가"
```

**❌ 실패 시:**

`_agent_reports/T001/FEEDBACK.md`를 작성한 뒤:

```bash
bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh dispatch codex T001 full . feedback
```

---

## 자주 쓰는 명령어

```bash
AGENT_TEAM="bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh"

# 환경 진단
$AGENT_TEAM doctor

# 태스크 상태 대시보드
$AGENT_TEAM dashboard

# 두 에이전트 독립 리뷰 후 통합 결정
$AGENT_TEAM cross-review T001 full

# 병렬 실행 안전성 체크
$AGENT_TEAM parallel-check T001 T002

# 점수 수동 기록
$AGENT_TEAM score codex code_implementation 3 0
```

---

## 토큰 절약 팁

RTK가 설치된 경우 에이전트가 자동으로 압축된 출력을 받는다 (60-90% 절약).

```bash
rtk gain          # 누적 절약량 확인
rtk gain --history # 명령어별 사용 이력
```

Serena MCP가 활성화된 경우 코드 탐색 시 Grep/Read 대신 심볼 검색 도구를 사용한다.
