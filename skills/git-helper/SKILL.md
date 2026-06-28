---
name: git-helper
description: "git 작업 보조 — 커밋 메시지 생성, PR 설명 작성, 브랜치 이름 제안. '/git-commit', '/git-pr', '/git-branch' 요청 또는 '커밋해줘', 'PR 설명 써줘', '브랜치 이름 추천해줘' 요청 시 사용."
---

# git-helper

`git diff`, `git log`, `git status`를 읽어 커밋 메시지·PR 설명·브랜치 이름을 자동 생성한다.
실제 git 명령 실행 전에 사용자가 결과물을 검토·수정할 수 있도록 초안을 먼저 제시한다.

## 언제 사용하나

- `/git-commit` 또는 "커밋 메시지 써줘", "커밋해줘"
- `/git-pr` 또는 "PR 설명 써줘", "PR 만들어줘"
- `/git-branch` 또는 "브랜치 이름 추천해줘", "브랜치 뭐로 할까"
- "git 작업 도와줘", "변경사항 정리해줘"

---

## /git-commit — 커밋 메시지 생성

### Phase 0: 변경사항 파악

```bash
git status
git diff --staged    # 스테이징된 변경
git diff             # 미스테이징 변경
git log --oneline -5 # 최근 커밋 스타일 파악
```

스테이징된 파일이 없으면 사용자에게 알리고 중단한다.

### Phase 1: 커밋 메시지 초안 작성

Conventional Commits 형식을 따른다:

```
<type>(<scope>): <subject>

<body (선택)>

<footer (선택)>
```

**type 선택 기준:**

| type | 사용 상황 |
|------|-----------|
| `feat` | 새 기능 추가 |
| `fix` | 버그 수정 |
| `refactor` | 동작 변경 없는 코드 개선 |
| `docs` | 문서만 변경 |
| `test` | 테스트 추가/수정 |
| `chore` | 빌드·도구·설정 변경 |
| `perf` | 성능 개선 |
| `style` | 포맷·공백 등 로직 무관 변경 |

**규칙:**
- subject는 50자 이내, 현재형 동사, 마침표 없음
- body는 "왜"를 설명 (무엇이 아닌 이유)
- 영문과 한글 모두 허용 — 기존 커밋 스타일을 따름

### Phase 2: 검토 및 실행

초안을 사용자에게 보여주고 수정 의견을 받는다.
승인 후 실행:

```bash
git commit -m "<확정된 메시지>"
```

`Co-Authored-By` 라인은 사용자가 명시적으로 요청할 때만 추가한다.

---

## /git-pr — PR 설명 생성

### Phase 0: 변경사항 파악

```bash
git log main..HEAD --oneline          # base 브랜치와의 커밋 목록
git diff main...HEAD --stat           # 변경 파일 요약
git diff main...HEAD                  # 전체 diff (큰 경우 핵심만 발췌)
```

base 브랜치가 `main`이 아닌 경우 사용자에게 확인한다.

### Phase 1: PR 설명 초안

```markdown
## Summary
- <변경 이유 / 해결하는 문제>
- <주요 변경 내용 2~3줄>

## Changes
- <파일/모듈별 변경 요약>

## Test plan
- [ ] <검증 방법 1>
- [ ] <검증 방법 2>
```

### Phase 2: 생성 및 확인

초안 확인 후 사용자가 원하면 `gh pr create` 실행:

```bash
gh pr create --title "<제목>" --body "<설명>"
```

---

## /git-branch — 브랜치 이름 제안

### Phase 0: 컨텍스트 파악

현재 작업 내용 또는 사용자 설명을 바탕으로 파악한다.

### Phase 1: 이름 제안

`<type>/<짧은-설명>` 형식으로 3개 제안:

```
feat/add-user-auth
fix/login-redirect-bug
refactor/split-auth-middleware
```

**규칙:**
- 소문자 kebab-case
- 50자 이내
- 현재 브랜치 이름 스타일을 참고해 일관성 유지

---

## 에러 핸들링

| 상황 | 대응 |
|------|------|
| git 저장소 아님 | "git 저장소가 아닙니다. `git init`을 먼저 실행하세요." 안내 |
| 스테이징 파일 없음 | "스테이징된 변경이 없습니다. `git add`로 파일을 추가하세요." 안내 |
| diff가 매우 큰 경우 | `--stat`으로 요약 먼저 파악, 핵심 파일만 전체 diff 확인 |
| gh CLI 없음 | PR 생성 대신 설명 텍스트만 출력 |
| main 브랜치 직접 커밋 | 경고 표시 후 사용자 확인 요청 |

## 예시

**입력:** 사용자가 "커밋해줘"라고 말한 경우  
**동작:**
1. `git diff --staged` 로 변경사항 파악
2. `fix(auth): 로그인 실패 시 리다이렉트 URL 누락 수정` 초안 제시
3. 사용자 확인 후 `git commit` 실행

**입력:** 사용자가 "PR 설명 써줘"라고 말한 경우  
**동작:**
1. `git log main..HEAD` + `git diff main...HEAD --stat` 분석
2. Summary/Changes/Test plan 초안 제시
3. 사용자 확인 후 선택적으로 `gh pr create` 실행
