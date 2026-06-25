# 새 프로젝트에 다중 에이전트 세팅하는 방법

> 빠른 시작: `claude-toolkit` 폴더에서 Claude Code를 열고
> `/multi-agent-setup` 을 입력하면 Claude가 대화하면서 자동으로 세팅해준다.

---

## 수동 세팅 (단계별)

### 1단계 — 프로젝트 구조 파악

세팅 전에 답해야 할 질문들:

```
Q1. 주요 기술 스택은? (React, Node.js, Python, etc.)
Q2. 도메인 분할 축은? 
    예) 프론트/백엔드, 기능 도메인 A/B/C, 라이브러리/CLI
Q3. 반복되는 작업 유형은?
    예) UI 컴포넌트 추가, API 라우트 추가, 명령어 추가
Q4. 검증이 필요한 경계면은?
    예) API URL↔fetch URL, DB 스키마↔모델, 환경변수↔코드
```

### 2단계 — 에이전트 역할 설계

**최소 구성 (3명)**

| 역할 | 이름 | 책임 |
|------|------|------|
| 설계 | planner | 코드베이스 분석 + 설계서 작성 |
| 구현 | impl-dev | 실제 코드 구현 |
| 검증 | qa | 결과 검증 + 버그 분석 |

**일반 구성 (4~5명)**

도메인이 2개 이상이면 구현 에이전트를 분리:

| 역할 | 이름 | 책임 |
|------|------|------|
| 설계 | planner | 전체 설계 |
| 구현 A | frontend-dev | 프론트엔드 구현 |
| 구현 B | backend-dev | 백엔드/API 구현 |
| 검증 | qa | 경계면 교차 검증 |
| 빌드 | build-agent | 패키징, 배포 |

### 3단계 — 파일 생성

**프로젝트 루트에:**

```
your-project/
└── .claude/
    ├── agents/
    │   ├── planner.md
    │   ├── frontend-dev.md
    │   ├── backend-dev.md
    │   └── qa.md
    └── skills/
        └── {project-name}-dev/
            └── SKILL.md
```

**에이전트 파일 작성 요령:**

1. `claude-toolkit/agents/_template/agent.md` 복사
2. `name`, `description` 수정
3. **프로젝트 컨텍스트** 섹션에 핵심 파일 경로 목록 작성
   - 이 섹션이 에이전트 품질을 결정한다
   - 에이전트가 "어디를 봐야 하는지"를 미리 알려주는 것
4. **입력/출력 프로토콜** — `_workspace/` 파일명 패턴 고정

**스킬 파일 작성 요령:**

1. `claude-toolkit/skills/_template/SKILL.md` 복사
2. 워크플로우 유형별 에이전트 조합 표 작성
3. `Agent()` 호출 방식 (병렬/순차) 명시
4. 자율 실행 키워드 정의 (예: "자면서", "자동으로")

### 4단계 — CLAUDE.md 등록

```markdown
## 다중 에이전트 개발

**트리거:** 기능 추가, 버그 수정 등 개발 작업 → `{project-name}-dev` 스킬 사용

**에이전트:**
- planner: 설계
- frontend-dev: React/UI 구현
- backend-dev: API/서버 구현  
- qa: 검증

**작업 디렉토리:** `_workspace/` (임시, gitignore 권장)
```

### 5단계 — 검증 (첫 실행)

세팅 후 가장 단순한 작업부터 실행해본다:

```
예시: "로그인 버튼 색깔 바꿔줘"
→ planner → frontend-dev → qa 흐름이 정상 동작하는지 확인
→ 각 에이전트가 올바른 파일을 읽고 수정하는지 확인
→ qa가 의미 있는 검증 결과를 내는지 확인
```

---

## 프로젝트 유형별 권장 구성

### React + Node.js 웹앱

```
planner (설계)
├── ui-dev (React, src/)
├── api-dev (Express, routes/, lib/)
└── qa (URL↔fetch, props↔컴포넌트 경계면 검증)
```

### Python CLI 도구

```
planner (설계)
├── core-dev (lib/, 핵심 로직)
├── cli-dev (cli.py, 인터페이스)
└── qa (CLI 인수↔내부 함수 시그니처 검증)
```

### Discord 봇

```
planner (설계)
├── command-dev (명령어 핸들러)
├── service-dev (비즈니스 로직, DB)
└── qa (명령어 라우팅↔핸들러, prefix 순서 검증)
```

### Electron 데스크톱 앱

```
planner (설계)
├── renderer-dev (React, 렌더러 프로세스)
├── main-dev (Electron main, IPC)
└── qa (IPC 채널명 일치, preload 브릿지 검증)
```

---

## 흔한 실수와 해결법

| 실수 | 증상 | 해결 |
|------|------|------|
| 에이전트 컨텍스트가 너무 넓음 | 에이전트가 무관한 파일 수정 | 프로젝트 컨텍스트 섹션에 담당 파일 목록 명시 |
| planner 없이 바로 구현 | 구현 에이전트가 잘못된 파일 수정 | 반드시 planner를 첫 단계로 |
| qa가 코드 수정 | 역할 혼재, 책임 불명확 | qa 에이전트 정의에 "수정 안 함" 명시 |
| 에이전트가 커밋 | 검증 없이 코드 반영 | 모든 에이전트 파일에 "커밋 금지" 규칙 고정 |
| _workspace 번호 혼재 | 실행 순서 파악 불가 | 01/02/03 번호 규칙 엄수 |
