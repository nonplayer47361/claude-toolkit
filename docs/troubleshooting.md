# Troubleshooting — cli-agent-team

모든 문제의 첫 번째 단계:

```bash
bash ~/.claude/skills/cli-agent-team/scripts/agent-team.sh doctor
```

doctor.sh가 환경, 설치 상태, conf 파일, 스크립트 존재 여부를 한 번에 진단한다.

---

## 1. 설치 / 환경 문제

### 스킬 명령어가 Claude Code에 나타나지 않음

**원인**: 스킬 설치 후 Claude Code를 재시작하지 않음.

**해결**:
```bash
# 설치 확인
ls ~/.claude/skills/cli-agent-team/

# Claude Code 재시작 후 다시 시도
```

### `bash: command not found` (Windows)

**원인**: PowerShell에는 bash가 없음.

**해결**: Git Bash 또는 WSL 설치 후 Git Bash 터미널에서 실행.

```powershell
# Git Bash 설치
winget install Git.Git
```

설치 후 Git Bash 터미널(시작 메뉴 → Git Bash)에서 명령어 실행.

---

## 2. setup.sh 문제

### codex/agy가 설치됐는데 `❌ 미설치 → DISABLED` 표시

**원인**: 해당 CLI가 PATH에 없음. setup.sh는 `command -v <cli>`로 감지한다.

**해결**:
```bash
# 어디에 설치됐는지 확인
which codex
which agy

# PATH 확인
echo $PATH

# bash 세션의 PATH에 추가 (예시)
export PATH="$HOME/.local/bin:$PATH"
bash ~/.claude/skills/cli-agent-team/scripts/setup.sh
```

### conf 파일이 없다는 오류

**원인**: setup.sh를 아직 실행하지 않았거나, 다른 디렉토리에서 실행함.

**해결**:
```bash
# 프로젝트 루트에서 실행
cd /path/to/your/project
bash ~/.claude/skills/cli-agent-team/scripts/setup.sh

# conf 파일 위치 확인
cat _agent_reports/.cli-agent-team.conf
```

### CI 환경에서 setup.sh 실패 (에이전트 없음)

**해결**: `--skip-probe` 플래그 사용. probe-cli.sh가 실제 에이전트 실행을 건너뜀.

```bash
bash ~/.claude/skills/cli-agent-team/scripts/setup.sh --skip-probe
```

---

## 3. agy 관련 (Windows / 비-TTY 환경)

### agy가 실행되지만 출력이 없음

**원인**: agy는 TTY 환경이 필요하다. 비-TTY(헤드리스 Bash) 환경에서는 출력을 내지 않는다.

**해결**: pty-bridge를 통해 실행.

```bash
# pty-bridge 설치
cd mcp-servers/pty-bridge
npm install
cd ../..

# pty-bridge 테스트
node mcp-servers/pty-bridge/run.js -- agy --help
```

출력이 나오면 pty-bridge 경유 설정이 완료된 것이다. dispatch.sh는 자동으로 pty-bridge를 감지해 사용한다.

### agy 인증 오류 (`authentication required` 또는 로그인 필요)

**원인**: agy는 Google 계정 인증이 필요하다.

**해결**: 일반 터미널에서 agy를 한 번 대화형으로 실행해 로그인한다.

```bash
agy
# → Google 계정 로그인 프롬프트를 따라 완료
```

로그인 후 헤드리스 dispatch가 인증 정보를 재사용한다.

### agy `--print` 플래그가 없다는 오류

**원인**: agy 버전이 오래됨.

**해결**: [github.com/antigravity-dev/agy](https://github.com/antigravity-dev/agy) 에서 최신 버전으로 업데이트.

---

## 4. dispatch.sh / 태스크 실행

### REPORT.md가 생성되지 않음

**원인 1**: 에이전트 rate limit.

**감지 신호**: dispatch 로그에 아래 키워드가 있으면 rate limit:
```
rate limit  /  429  /  quota exceeded  /  usage limit  /  too many requests
```

**해결**: 잠시 기다린 뒤 재배정. 다른 에이전트로 우선 배정.

```bash
# codex rate limit이면 agy로 재배정
bash ~/.claude/skills/cli-agent-team/scripts/dispatch.sh agy T001 limited "$(pwd)" execute
```

**원인 2**: 에이전트가 비대화형 실행에 실패함.

**해결**:
```bash
# probe로 실제 동작 확인
bash ~/.claude/skills/cli-agent-team/scripts/probe-cli.sh codex limited "$(pwd)"
```

exit 0이면 정상, exit 1이면 헤드리스 실행 불가 → pty-bridge 필요하거나 인증 문제.

### `auto` 모드를 써도 항상 같은 에이전트가 선택됨

**원인**: `.agent_scores.json`에 데이터가 5건 미만이면 기본값(agy)을 사용한다.

**해결**: 몇 번 더 태스크를 실행해 데이터를 쌓으면 자동 선택이 활성화된다.

```bash
# 현재 점수 확인
cat _agent_reports/.agent_scores.json
```

### TASK.md를 작성했는데 적응형 배분이 안 됨

**원인**: TASK.md 최상단에 `task_type:` 필드가 없음.

**해결**: TASK.md 첫 줄에 추가:
```
task_type: code_implementation
```

지원 값: `shell_scripting` | `documentation` | `code_implementation` | `testing` | `refactoring`

---

## 5. verify.sh 실패

### "스코프 초과" 오류

**증상**: `[verify] FAIL: 허용 파일 외 변경 감지`

**원인**: 에이전트가 TASK.md의 `## 허용 파일` 목록 외의 파일을 수정했다.

**해결**: TASK.md의 허용 파일 목록을 확인하고, 에이전트가 수정한 파일을 되돌린다.

```bash
git diff --name-only          # 변경된 파일 목록
git checkout -- <파일>         # 허용 범위 밖 파일 되돌리기
```

### AC 체크리스트 미완료

**증상**: `[verify] FAIL: AC 미완료`

**원인**: REPORT.md의 `## AC 체크리스트` 섹션에 `- [ ]`(미완료)가 남아 있다.

**해결**: REPORT.md를 열어 미완료 항목 원인을 확인. 재배정 또는 수동 처리 후 체크를 `- [x]`로 변경.

### 보안 스캔 경고

**증상**: `[verify] WARN: 보안 패턴 감지`

경고만으로는 FAIL이 아니다. 경고 내용을 읽고 오탐인지 실제 문제인지 판단한다.

```bash
# AgentShield 단독 실행
bash ~/.claude/skills/cli-agent-team/scripts/agent-shield.sh <파일>
```

오탐이면 무시하고 수동으로 커밋해도 된다.

---

## 6. Windows 특이 사항

### 한글이 깨짐

```powershell
chcp 65001
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8
```

### PowerShell에서 bash 스크립트 실행 안 됨

PowerShell은 bash 문법을 해석하지 못한다. **Git Bash** 또는 **WSL** 터미널에서 실행해야 한다.

```powershell
# Git Bash에서 실행 (PowerShell 아님)
"C:\Program Files\Git\bin\bash.exe" ~/.claude/skills/cli-agent-team/scripts/setup.sh
```

### agent-watch.ps1 실행 정책 오류

**증상**: `cannot be loaded because running scripts is disabled`

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
```

---

## 7. CI / GitHub Actions

### CI에서 setup.sh가 에이전트 없어서 실패

**해결**: `--skip-probe` 사용. 이미 `.github/workflows/ci.yml`에 적용되어 있다.

```yaml
- name: Run setup.sh
  run: bash skills/cli-agent-team/scripts/setup.sh --skip-probe
```

### CI에서 `.cli-agent-team.conf`가 없다는 오류

setup.sh는 `_agent_reports/` 디렉토리를 자동 생성한다. CI에서 이 디렉토리가 없으면:

```bash
# setup.sh는 자동으로 생성하므로 별도 mkdir 불필요
bash skills/cli-agent-team/scripts/setup.sh --skip-probe
test -f "_agent_reports/.cli-agent-team.conf"  # 생성 확인
```

---

## 빠른 참조

| 증상 | 첫 시도 |
|------|---------|
| 뭔지 모르겠음 | `agent-team.sh doctor` |
| REPORT.md 없음 | 로그에서 rate limit 키워드 확인 |
| agy 출력 없음 | pty-bridge 설치 확인 |
| setup.sh가 에이전트 못 찾음 | `which codex && which agy` |
| verify FAIL | `git diff --name-only` 로 스코프 확인 |
| 한글 깨짐 | `chcp 65001` |
