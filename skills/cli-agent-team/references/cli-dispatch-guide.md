# CLI 디스패치 가이드 — 알려진 함정과 정확한 사용법

Tarkov Market KO 프로젝트에서 Codex CLI와 Antigravity CLI(agy)를 실제로 자동화하며
발견한 것들. 새 CLI를 추가할 때도 이 절차를 그대로 따라 검증한다.

## 목차
- [핵심 원칙](#핵심-원칙)
- [Codex CLI](#codex-cli)
- [Antigravity CLI (agy)](#antigravity-cli-agy)
- [일반 함정](#일반-함정-cli-비종속)
- [PTY/pexpect를 시도하기 전에](#ptypexpect를-시도하기-전에)

## 핵심 원칙

**"프로세스가 exit 0으로 끝났다" ≠ "작업이 완료됐다."** 항상 산출물(파일 존재, git diff,
REPORT.md 내용)로 판단한다. CLI의 stdout 텍스트가 비어 있어도 실제 작업은 수행됐을 수
있고, 반대로 exit 0이어도 아무것도 안 했을 수 있다.

**완전자율(승인 우회) 플래그는 프로젝트별로 명시적 동의를 받은 뒤에만 쓴다.** SKILL.md
Phase 1에서 매번 확인하는 이유가 이것이다 — 한 프로젝트의 승인이 다른 프로젝트에
전이되지 않는다.

## Codex CLI

- 비대화형 실행: `codex exec [PROMPT]`
- 완전자율(승인됐을 때만 사용): `--dangerously-bypass-approvals-and-sandbox`
- 제한된 자율(기본 권장): 플래그 없이 실행하면 CLI가 승인이 필요한 시점에 멈춘다 —
  비대화형(`exec`)에서는 이게 곧 "막힘"이 되므로, 제한된 자율을 선택한 프로젝트에서는
  `-a on-request`(모델이 필요할 때만 승인 요청)나 `-s read-only`처럼 더 좁은 권한으로
  시작해 점진적으로 넓히는 편이 낫다. 완전 자동화가 필요하면 결국 완전자율 동의가
  필요하다는 점을 사용자에게 설명한다.
- 작업 디렉토리: `-C <절대경로>`
- 마지막 응답만 파일로: `-o <파일경로>` — **디렉토리가 미리 존재해야 한다.** 없으면
  저장이 조용히 실패한다 (`mkdir -p`로 작업 디렉토리를 먼저 만들 것).
- **세션 이어가기(검증됨)**: `codex exec resume --last "<후속 메시지>"` — 별도 프로세스
  호출 사이에도 대화 맥락이 완벽히 보존된다 (세션 id 동일). `FEEDBACK.md` 재배정 시
  새 세션보다 이걸 우선 사용.
- stdout으로 결과가 그대로 출력되므로 `run_in_background` + 완료 알림으로 충분하다.
  추가 디코딩 작업이 필요 없다.

## Antigravity CLI (agy)

- 비대화형 실행: `agy --print "<메시지>" --add-dir <경로> --print-timeout <시간>`
- 완전자율(승인됐을 때만 사용): `--dangerously-skip-permissions`
- **알려진 버그(검증됨)**: 이 헤드리스 모드에서 **stdout에 채팅 텍스트가 안 보일 수
  있다** (tty 미감지로 인한 출력 억제로 추정 — Go 기반 CLI에서 흔함). 그러나 **실제
  파일 쓰기 작업은 정상 수행된다** — 트리비얼 파일 생성 요청으로 직접 확인했다.
  결론: stdout이 비어 있어도 패닉하지 말고, 산출물(REPORT.md, git diff)로 완료를
  판단한다. 응답 텍스트 자체는 사라지지 않고 `~/.gemini/antigravity-cli/conversations/
  <id>.db`(SQLite, protobuf)에 저장되어 있다 — 필요하면 Python `sqlite3`로 열어 텍스트
  문자열을 그렙할 수 있지만, 보통은 불필요하다(파일 기반 프로토콜이면 stdout이 필요 없음).
- **세션 이어가기(검증됨)**: `agy --continue --print "<후속 메시지>" ...` (또는 `-c`) —
  별도 호출 사이 컨텍스트 보존을 직접 확인했다 (먼저 알려준 정보를 정확히 기억).
- 타임아웃: `--print-timeout`(기본 5m) — 코드 작성 작업은 15~20m 이상으로 늘릴 것.

## 실시간으로 작업 지켜보기 (Windows, 검증됨 — 사용자가 원할 때만, 자동 실행 금지)

**Claude가 디스패치할 때 자동으로 새 터미널 창/탭을 띄우지 않는다.** 새 OS 창이 매번
뜨는 게 사용자에게 더 불편하다는 피드백을 받았다(IDE 통합 터미널 안에 표시하는 것도
검토했으나, IDE 내부 터미널 패널은 그 IDE 프로세스 내부 UI라 외부에서 새 탭을 주입할
방법이 없다 — Windows Terminal의 탭 재사용(`wt -w 0 new-tab`)도 테스트는 됐지만 결국
사용자가 수동으로 보는 쪽을 선호함). 대신 디스패치 시 로그 경로만 알려주고, 사용자가
보고 싶을 때 직접 다음을 실행하게 한다:

- 새 창으로: `powershell -File scripts/watch-log.ps1 -LogFile <로그경로>`
- 또는 직접: `Get-Content -Path <로그경로> -Wait` (PowerShell) / `tail -f <로그경로>` (bash)

**Codex에는 효과가 있다** (stdout에 실시간 텍스트가 흐름). **Antigravity(agy)에는
효과가 없다** (헤드리스 stdout이 침묵 — 위 "알려진 버그" 참고). agy 작업을 실시간으로
보고 싶다면 시도해볼 만한 대안(미검증): Antigravity IDE.exe를 해당 프로젝트 폴더로
직접 띄워서, CLI가 쓰고 있는 같은 대화 저장소(`~/.gemini/antigravity-cli/conversations/`)를
IDE GUI가 같은 대화로 인식해 보여주는지 확인. 이것도 사용자가 원할 때 사용자가 직접
시도하게 안내한다 — Claude가 임의로 무거운 GUI 앱을 띄우지 않는다.

## 일반 함정 (CLI 비종속)

1. **`git add a b c`는 경로 하나라도 없으면 전체가 스테이징 안 된다.** 존재 확인 안 된
   경로를 한 커맨드에 같이 넘기지 말 것 — 따로 확인 후 추가.
2. **Windows 경로 끝 백슬래시 + 닫는 따옴표 조합이 bash 인용을 깨뜨린다**
   (`"...\Tarkov\"` 의 `\"`가 escaped quote로 해석됨). 경로 끝에 슬래시를 안 붙이거나,
   forward slash를 쓴다.
2-1. 한글이 포함된 Windows 경로는 git-bash에서 `/c/Users/.../바탕 화면/...` 형태로
   써야 안전하다.
3. **완전자율 플래그 이름이 CLI마다 다르다** — 새 CLI를 추가할 때 반드시 `--help`로
   정확한 이름을 확인한다 (`--dangerously-bypass-approvals-and-sandbox` vs
   `--dangerously-skip-permissions`는 같은 의도지만 다른 이름).
4. **`-o`/`--output` 류의 "결과를 파일로 저장" 플래그는 대상 디렉토리를 미리 만들어야
   하는 경우가 많다.** 디스패치 전 `_agent_reports/<task-id>/`를 항상 먼저 만든다.

## PTY/pexpect를 시도하기 전에

"CLI가 입력을 요구하며 멈춘다"는 문제는 보통 **완전자율 플래그를 안 썼기 때문**이거나
**stdout 캡처 문제**(agy 사례)이지, 진짜 인터랙티브 TTY가 필요해서가 아니다. PTY
오케스트레이터(Python pexpect 등)를 만들기 전에 먼저 확인할 것:

1. 그 CLI에 완전자율/승인우회 플래그가 있는가? (대부분의 코딩 에이전트 CLI는 있다)
2. 세션 이어가기(`resume`, `--continue` 등) 기능이 있는가? — 있으면 "대화형처럼" 유지하는
   데 PTY가 필요 없다.
3. 실제로 헤드리스 모드에서 파일 쓰기 작업이 되는지 트리비얼 테스트로 확인했는가?
   (`scripts/probe-cli.sh`)

세 가지가 다 된다면 PTY는 불필요하다. 추가로 **`pexpect`는 Windows를 지원하지 않고**,
`winpty` 대체도 비대화형 하니스 환경(이 스킬이 동작하는 환경 자체)에서는 stdin이 tty가
아니라 막힌다 — Windows 환경에서는 애초에 시도할 가치가 낮다.
