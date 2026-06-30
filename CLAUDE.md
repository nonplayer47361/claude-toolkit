# claude-toolkit

Claude Code용 스킬·에이전트·MCP 서버를 개발하고 배포하는 작업 공간.

## 목표

- 여러 프로젝트에서 재사용 가능한 **스킬**과 **에이전트** 제작
- 기능을 확장하는 **MCP 서버** 개발
- 친구·팀원에게 배포 가능한 형태로 패키징

## 폴더 구조

```
claude-toolkit/
├── skills/          # Claude Code 스킬 (SKILL.md 단위)
│   └── _template/  # 새 스킬 시작점
├── agents/          # 재사용 에이전트 정의 (.md 단위)
│   └── _template/  # 새 에이전트 시작점
├── mcp-servers/     # MCP 서버 (Node.js 기반)
│   └── _template/  # 새 MCP 서버 시작점
├── scripts/         # 설치·배포 스크립트
└── docs/            # 작성 가이드 및 배포 문서
```

## 포함된 스킬

| 스킬 | 설명 | 설치 |
|------|------|------|
| `git-helper` | git diff 기반 커밋 메시지 자동 생성·PR 초안 작성 | `.\scripts\install-skill.ps1 -SkillName git-helper` |
| `code-review-ko` | 한국어 코드 리뷰 — diff 분석 후 지적사항 목록 생성 | `.\scripts\install-skill.ps1 -SkillName code-review-ko` |
| `cli-agent-team` | Claude를 오케스트레이터로, Codex·agy를 서브 에이전트로 하는 다중 에이전트 루프. 아이디어 회의부터 배포까지 커버 | `.\scripts\install-skill.ps1 -SkillName cli-agent-team` |

## 주요 명령어

```powershell
# 스킬을 현재 유저 전체에 설치
.\scripts\install-skill.ps1 -SkillName <폴더명>

# 스킬을 특정 프로젝트에 설치
.\scripts\install-skill.ps1 -SkillName <폴더명> -ProjectPath <경로>

# MCP 서버 의존성 설치
cd mcp-servers\<서버명>; npm install

# MCP 서버를 Claude Code 글로벌 설정에 등록
.\scripts\register-mcp.ps1 -ServerName <이름> -ServerPath <경로>
```

## 개발 원칙

- **스킬**: `skills/<이름>/SKILL.md` — 프론트매터 `name`·`description` 필수
- **에이전트**: `agents/<이름>.md` — 프론트매터 `name`·`description`·`tools` 필수
- **MCP 서버**: `mcp-servers/<이름>/` — `package.json` + `index.js` (ESM, stdio transport)
- 배포 단위는 GitHub 레포. 스킬은 harness marketplace 호환 구조로 작성.

## 네이밍 컨벤션

| 타입 | 컨벤션 | 예시 |
|------|--------|------|
| 스킬 | kebab-case | `git-helper`, `code-review-ko` |
| 에이전트 | kebab-case | `planner`, `security-auditor` |
| MCP 서버 | kebab-case | `file-manager`, `notion-bridge` |
