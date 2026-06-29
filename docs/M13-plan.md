# M13 계획 — ECC 패턴 적용 + 에이전트 효율 추적

> 작성: 2026-06-29  
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
   새 컨텍스트 창이 열려도 "지금까지 무슨 일이 있었는가"를 보존.

4. **AgentShield (ECC 보안 모듈)**  
   Attacker → Defender → Auditor 3-에이전트 적대적 파이프라인.  
   5개 카테고리(secrets·hook injection·MCP risk·agent config·permissions) 스캔.  
   Critical 발견 시 exit 2 → verify.sh 커밋 차단.

5. **에이전트 효율 추적 (신규 아이디어)**  
   토큰 소모 / 소요 시간 / LOC 변경량을 수집해 일별 리뷰 파일 생성.  
   Claude가 배정 결정 시 "어떤 에이전트가 어떤 작업에서 토큰 효율이 좋은가"를 객관 지표로 활용.

---

## 현황 갭 분석

| 항목 | 현재 상태 | 문제점 |
|------|-----------|--------|
| `AGENT_ROLES.md` | Claude만 읽음 | Codex/agy는 TASK.md 프롬프트에만 의존, 역할 컨텍스트 매번 중복 |
| `dispatch.sh` MSG | TASK.md만 언급 | 역할·규칙·금지 패턴 컨텍스트 없음 |
| `.session_state` | `update-state.sh` 수동 갱신 | compaction/rate-limit 전 자동 저장 없음 |
| SessionStart 훅 | `cbm-session-reminder`만 있음 | `.session_state` 자동 주입 없음 |
| 이터레이션 컨텍스트 | 없음 | rate limit 후 "지금까지 무슨 일" 소실 |
| 보안 검사 | grep 2종 (secrets + 위험 명령어) | hook injection·MCP risk·권한 탐지 없음 |
| 에이전트 성능 데이터 | AC 통과율만 (`agent_scores.json`) | 토큰·시간·LOC 수집 없음, 효율 비교 불가 |
| 배정 결정 근거 | AC 통과율 15%p 차이만 | 토큰 효율·소요 시간·부하 현황 미반영 |

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

**`init.sh`** — AGENT_ROLES.md 생성 블록(line ~200) 이후에 AGENTS.md 생성 블록 추가:

```bash
# AGENTS.md 생성 — Codex/agy/Claude 공통 읽기용
AGENTS_FILE="$PROJECT_DIR/AGENTS.md"
if [ ! -f "$AGENTS_FILE" ]; then
  cat > "$AGENTS_FILE" << AGENTS_EOF
# AGENTS.md — ${PROJECT_NAME}
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
  echo "[init] AGENTS.md 생성 완료: $AGENTS_FILE"
fi
```

**`dispatch.sh`** — execute MSG 앞(line ~289)에 AGENTS.md 힌트 주입:

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

- `skills/cli-agent-team/scripts/install-skill.ps1` — `--Update` 시 `hooks/` 폴더도 동기화

### `session-start.sh` 구현

```bash
#!/usr/bin/env bash
# ECC session-start 패턴: .session_state + 진행 중 태스크 → stdout 주입
# Claude Code가 SessionStart 이벤트에서 이 출력을 컨텍스트 앞에 삽입함
# 등록: settings.json SessionStart > startup/resume matcher

PROJECT_DIR="${PROJECT_ROOT:-$(pwd)}"
SESSION_STATE="$PROJECT_DIR/_agent_reports/.session_state"
[ ! -f "$SESSION_STATE" ] && exit 0

# 진행 중 태스크: TASK.md 있고 REPORT.md 없는 디렉토리
IN_PROGRESS=""
for d in "$PROJECT_DIR"/_agent_reports/T-*/; do
  [ -f "$d/TASK.md" ] && [ ! -f "$d/REPORT.md" ] && \
    IN_PROGRESS="$IN_PROGRESS $(basename "$d")"
done

# SHARED_TASK_NOTES 최근 3줄
NOTES=""
NOTES_FILE="$PROJECT_DIR/_agent_reports/SHARED_TASK_NOTES.md"
[ -f "$NOTES_FILE" ] && NOTES="$(tail -6 "$NOTES_FILE")"

cat << CONTEXT_EOF
[HISTORICAL REFERENCE ONLY — 이전 세션 요약. 재실행 금지. 참고만 할 것]
$(cat "$SESSION_STATE")
진행 중 태스크:${IN_PROGRESS:-없음}
$([ -n "$NOTES" ] && printf '\n최근 완료 컨텍스트:\n%s' "$NOTES")
[END HISTORICAL REFERENCE]
CONTEXT_EOF
```

### `pre-compact.sh` 구현

```bash
#!/usr/bin/env bash
# ECC pre-compact 패턴: compaction 직전 .session_state 강제 갱신
# 등록: settings.json PreCompact > * matcher

PROJECT_DIR="${PROJECT_ROOT:-$(pwd)}"
STATE_FILE="$PROJECT_DIR/_agent_reports/.session_state"
[ ! -f "$STATE_FILE" ] && exit 0

# compaction 발생 마커 추가
TS="$(date '+%Y-%m-%d %H:%M')"
printf '\n[compaction: %s]\n' "$TS" >> "$STATE_FILE"

# 수정 중인 파일 목록 스냅샷 (최대 10개)
CHANGED=$(cd "$PROJECT_DIR" && \
  git diff --name-only HEAD 2>/dev/null | head -10 | tr '\n' ', ' | sed 's/,$//')
[ -n "$CHANGED" ] && printf '수정 중 파일: %s\n' "$CHANGED" >> "$STATE_FILE"
```

### `settings.json` 등록 방법 (install-skill.ps1 --Update 후 수동 추가)

```json
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
```

### 완료 기준 (AC)

- [ ] `session-start.sh` 존재, `.session_state` 없을 때 조용히 exit 0
- [ ] `session-start.sh` 출력에 `[HISTORICAL REFERENCE ONLY]` 태그 포함
- [ ] `pre-compact.sh` 실행 시 `.session_state`에 compaction 마커 추가
- [ ] `install-skill.ps1` `--Update` 시 `hooks/` 폴더 동기화
- [ ] `bash -n` 문법 검사 통과 (두 파일 모두)

---

## T-M13-C: SHARED_TASK_NOTES.md 컨텍스트 브리지

**목적**: 이터레이션 간 에이전트 결정사항 보존 (ECC autonomous-loops 패턴)  
**크기**: 소형  
**에이전트**: codex  
**의존**: T-M13-A 완료 후 (dispatch.sh 수정 충돌 방지)

### 변경 파일

- `skills/cli-agent-team/scripts/dispatch.sh`
- `skills/cli-agent-team/scripts/verify.sh`
- `skills/cli-agent-team/scripts/init.sh`

### `dispatch.sh` — execute MSG에 NOTES 힌트 추가

```bash
_notes_hint=""
NOTES_FILE="$PROJECT_DIR/_agent_reports/SHARED_TASK_NOTES.md"
if [ -f "$NOTES_FILE" ] && [ -s "$NOTES_FILE" ]; then
  _notes_hint="

【컨텍스트 브리지】 _agent_reports/SHARED_TASK_NOTES.md를 읽어 이전 태스크의 핵심 결정사항을 파악해줘. 이 태스크 완료 후 핵심 결정(변경 파일·이유·다음 주의사항)을 NOTES 하단에 추가해줘."
fi
```

### `verify.sh` — 검증 통과 후 NOTES 자동 append

```bash
# SHARED_TASK_NOTES.md 업데이트 (검증 통과 시에만)
_NOTES_FILE="$PROJECT_DIR/_agent_reports/SHARED_TASK_NOTES.md"
if [ -f "$_NOTES_FILE" ] && [ "$FAILED" -eq 0 ]; then
  _CHANGED=$(cd "$PROJECT_DIR" && \
    git diff --name-only HEAD 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
  printf '\n## [%s] %s (%s) 완료\n- 변경: %s\n' \
    "$(date '+%Y-%m-%d %H:%M')" "$TASK_ID" "${_AGENT:-unknown}" \
    "${_CHANGED:-없음}" >> "$_NOTES_FILE"
fi
```

### `init.sh` — 초기화 시 SHARED_TASK_NOTES.md 생성

```bash
NOTES_FILE="$PROJECT_DIR/_agent_reports/SHARED_TASK_NOTES.md"
if [ ! -f "$NOTES_FILE" ]; then
  cat > "$NOTES_FILE" << 'NOTES_EOF'
# SHARED_TASK_NOTES.md — 이터레이션 간 컨텍스트 브리지
# 각 에이전트가 태스크 시작 시 읽고 완료 후 핵심 결정을 추가합니다.
# rate limit / compaction 후에도 "지금까지 무슨 일" 맥락을 보존합니다.

NOTES_EOF
  echo "[init] SHARED_TASK_NOTES.md 생성: $NOTES_FILE"
fi
```

### 완료 기준 (AC)

- [ ] `init.sh` 실행 시 `SHARED_TASK_NOTES.md` 생성됨
- [ ] `dispatch.sh` execute MSG가 NOTES 파일 존재 시 읽기/쓰기 지시 포함
- [ ] `verify.sh` 검증 통과 후 NOTES에 `[날짜] TASK_ID (agent) 완료` 라인 append
- [ ] NOTES 파일 없을 때 verify.sh 오류 없이 건너뜀
- [ ] `bash -n` 문법 검사 통과

---

## T-M13-D: AgentShield 보안 스캐너

**목적**: verify.sh 보안 검사 5/5를 5카테고리 스캐너로 강화 (ECC AgentShield 패턴)  
**크기**: 중형  
**에이전트**: agy  
**의존**: 없음 (verify.sh 수정 부위가 T-M13-C와 다름)

### 신규 파일

- `skills/cli-agent-team/scripts/agent-shield.sh`

### 변경 파일

- `skills/cli-agent-team/scripts/verify.sh` — 검사 5/5 교체
- `skills/cli-agent-team/scripts/doctor.sh` — agent-shield.sh 체크 추가

### `agent-shield.sh` 구조

```
exit 0 = clean (이상 없음)
exit 1 = warning (verify.sh 통과, 로그만 남김)
exit 2 = critical (verify.sh FAILED 처리, 커밋 차단)
```

| 카테고리 | 탐지 대상 | 판정 |
|---------|----------|------|
| ① secrets | `api_key=`, `aws_access_key`, `GITHUB_TOKEN`, `-----BEGIN`, Bearer 토큰 등 14종 패턴 | critical |
| ② hook injection | `settings.json` 변경 + 알 수 없는 command 경로 포함 여부 | critical |
| ③ MCP risk | `claude_desktop_config.json` 변경 + `http://` MCP 신규 추가 | warning |
| ④ agent config | TASK.md `## 허용 파일` 누락, `auth-mode full` 하드코딩 | warning |
| ⑤ permissions | `chmod 777`, `sudo`, `--dangerously-skip-permissions` 하드코딩 | critical |

```bash
#!/usr/bin/env bash
# agent-shield.sh <project-dir>
# exit 0=clean / 1=warning / 2=critical

set -euo pipefail
PROJECT_DIR="${1:-$(pwd)}"
SHIELD_EXIT=0
SEP="────────────────────────────────────────"

emit() { local level="$1" msg="$2"
  echo "  [${level}] ${msg}"
  [ "$level" = "CRITICAL" ] && SHIELD_EXIT=2
  [ "$level" = "WARNING"  ] && [ "$SHIELD_EXIT" -lt 1 ] && SHIELD_EXIT=1
}

SEC_DIFF=$(cd "$PROJECT_DIR" && git diff HEAD 2>/dev/null || true)
[ -z "$SEC_DIFF" ] && echo "  ⏭️  변경 없음 — 건너뜀" && exit 0

echo ""; echo "[AgentShield] 5카테고리 보안 스캔"; echo "$SEP"

# ① secrets (14종)
SECRET_PATTERNS='(api[_-]?key|aws_access_key|aws_secret|GITHUB_TOKEN|GH_TOKEN|
  private_key|client_secret|auth_token|bearer\s+[A-Za-z0-9]{20,}|
  -----BEGIN (RSA|EC|OPENSSH)|password\s*=\s*["'"'"'][^"'"'"']{8,}|
  token\s*[=:]\s*["'"'"'][A-Za-z0-9_\-]{16,})'
hit=$(echo "$SEC_DIFF" | grep '^+[^+]' | grep -iE "$SECRET_PATTERNS" 2>/dev/null || true)
[ -n "$hit" ] && emit CRITICAL "secrets 패턴 탐지 (하드코딩 금지)" || echo "  ✅ ① secrets 이상 없음"

# ② hook injection
if echo "$SEC_DIFF" | grep -q 'settings.json\|hooks.json'; then
  bad=$(echo "$SEC_DIFF" | grep '^+' | grep -E '"command"\s*:\s*"[^~].*/(tmp|AppData/Local/Temp|/var/tmp)' || true)
  [ -n "$bad" ] && emit CRITICAL "hook injection 의심 경로 포함" || emit WARNING "settings.json/hooks.json 변경 — 검토 권장"
else
  echo "  ✅ ② hook injection 변경 없음"
fi

# ③ MCP risk
if echo "$SEC_DIFF" | grep -q 'claude_desktop_config\|mcpServers'; then
  bad=$(echo "$SEC_DIFF" | grep '^+' | grep -E '"url"\s*:\s*"http://' || true)
  [ -n "$bad" ] && emit WARNING "비암호화 http:// MCP 서버 추가" || echo "  ✅ ③ MCP risk 이상 없음"
else
  echo "  ✅ ③ MCP risk 변경 없음"
fi

# ④ agent config
bad=$(echo "$SEC_DIFF" | grep '^+' | grep -E 'auth.?mode.*full|dangerously.bypass.*approvals' || true)
[ -n "$bad" ] && emit WARNING "auth-mode full 하드코딩 탐지" || echo "  ✅ ④ agent config 이상 없음"

# ⑤ permissions
bad=$(echo "$SEC_DIFF" | grep '^+[^+]' | grep -E '(chmod\s+777|sudo\s+rm|sudo\s+chmod|--dangerously-skip-permissions\b)' || true)
[ -n "$bad" ] && emit CRITICAL "위험 권한 명령 탐지" || echo "  ✅ ⑤ permissions 이상 없음"

echo "$SEP"
case "$SHIELD_EXIT" in
  0) echo "  ✅ AgentShield: 전체 통과" ;;
  1) echo "  ⚠  AgentShield: Warning (통과, 검토 권장)" ;;
  2) echo "  ❌ AgentShield: Critical — 커밋 차단" ;;
esac
exit "$SHIELD_EXIT"
```

### `verify.sh` — 검사 5/5 교체 (line ~263)

```bash
# ── 5. AgentShield 보안 스캔 ─────────────────────────────────────────
echo ""; echo "[검사 5/5] AgentShield 보안 스캔"

SHIELD_EXIT=0
if [ -f "$SCRIPT_DIR/agent-shield.sh" ]; then
  bash "$SCRIPT_DIR/agent-shield.sh" "$PROJECT_DIR" || SHIELD_EXIT=$?
else
  # fallback: 기존 grep 방식
  # (기존 secrets + danger 패턴 코드 유지)
fi

if [ "$SHIELD_EXIT" -eq 2 ]; then
  FAILED=1
  FAIL_REASON="${FAIL_REASON:-SEC_PATTERN}"
elif [ "$SHIELD_EXIT" -eq 1 ]; then
  echo "  ⚠ Warning 발생 — 커밋은 허용, 검토 권장"
fi
```

### 완료 기준 (AC)

- [ ] `agent-shield.sh` 5개 카테고리 모두 구현
- [ ] Critical 입력 시 exit 2, Warning 입력 시 exit 1, clean 입력 시 exit 0
- [ ] `verify.sh` 검사 5/5가 agent-shield.sh 호출로 교체됨
- [ ] agent-shield.sh 없을 때 기존 grep fallback 동작
- [ ] `doctor.sh`에 agent-shield.sh 존재 체크 추가
- [ ] `bash -n` 문법 검사 통과

---

## T-M13-E: 에이전트 효율 추적 시스템

**목적**: 토큰·시간·LOC 수집 → 일별 리뷰 → Claude 배정 결정 객관화  
**크기**: 중형  
**에이전트**: codex  
**의존**: 없음

### 데이터 흐름

```
dispatch.sh 완료 직전
  └─ 로그에서 토큰 추출 (codex: "tokens used\nNNN" / agy: "N input+output tokens")
  └─ 경과 시간 = date +%s - DISPATCH_START_TS
  └─ _agent_reports/<task-id>/.task_meta.json 저장

verify.sh 검증 통과 후
  └─ git diff --stat → LOC(추가/삭제) 집계
  └─ .task_meta.json에 loc_added, loc_deleted, ac_pass, ac_fail 추가

record-score.sh (기존 호출 시 TASK_ID env 추가)
  └─ .task_meta.json 읽기
  └─ _agent_reports/.agent_metrics.json에 누적

daily-review.sh (수동 호출 또는 Stop 훅)
  └─ .agent_metrics.json에서 오늘 날짜 필터
  └─ 집계·비교·권고 생성
  └─ _agent_reports/daily/YYYY-MM-DD.md 출력
```

### 신규 파일: `_agent_reports/<task-id>/.task_meta.json`

```json
{
  "task_id": "T-M13-A",
  "agent": "codex",
  "task_type": "shell_scripting",
  "task_size": "small",
  "date": "2026-06-29",
  "started_ts": 1751190000,
  "elapsed_sec": 142,
  "tokens_used": 38200,
  "loc_added": 45,
  "loc_deleted": 12,
  "ac_pass": 3,
  "ac_fail": 0,
  "fallback_used": false
}
```

### 신규 파일: `_agent_reports/.agent_metrics.json`

```json
{
  "version": 1,
  "records": [
    {
      "date": "2026-06-29",
      "task_id": "T-M13-A",
      "agent": "codex",
      "task_type": "shell_scripting",
      "task_size": "small",
      "tokens": 38200,
      "elapsed_sec": 142,
      "loc_added": 45,
      "loc_deleted": 12,
      "ac_pass": 3,
      "ac_fail": 0,
      "fallback_used": false
    }
  ],
  "daily": {
    "2026-06-29": {
      "codex": { "tasks": 6, "tokens": 240000, "elapsed_sec": 980,  "loc": 320, "ac_pass": 18, "ac_fail": 0 },
      "agy":   { "tasks": 5, "tokens": 380000, "elapsed_sec": 1490, "loc": 280, "ac_pass": 14, "ac_fail": 1 }
    }
  }
}
```

### 신규 파일: `_agent_reports/daily/YYYY-MM-DD.md` (daily-review.sh 출력)

```markdown
# 에이전트 효율 리뷰 — 2026-06-29

## 오늘 요약

| 에이전트 | 태스크 | AC 통과율 | 총 토큰 | 토큰/태스크 | 평균 소요 | 총 LOC | 토큰/LOC |
|---------|-------|---------|--------|-----------|--------|------|--------|
| codex   | 6건   | 100% (18/18) | 240,000 | 40,000 | 163초 | 320 | 750 |
| agy     | 5건   | 93% (14/15)  | 380,000 | 76,000 | 298초 | 280 | 1,357 |

## 태스크 유형별 효율 비교

| 유형 | codex 토큰/AC | agy 토큰/AC | 차이 | 권고 |
|------|------------|-----------|-----|-----|
| shell_scripting | 12,700 | 18,000 | codex -31% | **codex 우선** |
| refactoring     | 15,000 | 11,200 | agy -25%   | **agy 우선** |
| documentation   | 8,200  | 9,400  | -13%       | 차이 미미 |

## 개별 태스크 기록

| 태스크 | 에이전트 | 유형 | 토큰 | 소요 | +LOC/-LOC | AC | fallback |
|--------|---------|-----|-----|----|-----------|----|---------|
| T-M13-A | codex | shell_scripting | 38,200 | 142s | +45/-12 | 3/3 | - |
| T-M13-B | agy   | shell_scripting | 72,100 | 298s | +89/-23 | 4/4 | - |
| T-M13-D | agy   | security        | 68,400 | 310s | +120/-8 | 5/5 | - |

## 다음 세션 Claude 배정 참고

```
[효율 우위 (토큰/AC 20%+ 차이)]
  shell_scripting → codex 우선 (31%↓, 속도 2.1배)
  refactoring     → agy 우선  (25%↓)

[부하 현황]
  codex 오늘 총: 240,000 토큰 (임계값 500,000 미만 — 여유 있음)
  agy   오늘 총: 380,000 토큰 (임계값 500,000 미만 — 여유 있음)

[fallback 발생]
  없음
```
```

### 변경 파일별 구체적 작업

**`dispatch.sh`** — 완료 직전(line ~425 이후) 토큰 추출 + `.task_meta.json` 저장:

```bash
_extract_tokens() {
  local log="$1" agent="$2"
  case "$agent" in
    codex)
      # "tokens used\nNNN" 패턴 (codex 네이티브 출력)
      grep -A1 -iE "^tokens used$" "$log" 2>/dev/null \
        | grep -E "^[0-9,]+" | tr -d ',' | tail -1 || \
      grep -oE "[0-9,]+ tokens" "$log" 2>/dev/null \
        | grep -oE "^[0-9,]+" | tr -d ',' | tail -1 || echo 0
      ;;
    agy)
      # "N input tokens, M output tokens" → 합산
      grep -oE "[0-9,]+ (input|output) tokens" "$log" 2>/dev/null \
        | grep -oE "^[0-9,]+" | tr -d ',' \
        | awk '{s+=$1} END {print s+0}' || echo 0
      ;;
    *) echo 0 ;;
  esac
}

_ELAPSED=$(( $(date +%s 2>/dev/null || echo 0) - ${DISPATCH_START_TS:-0} ))
_TOKENS=$(_extract_tokens "${LOG_FILE:-/dev/null}" "$CLI")
_META_FILE="${TASK_DIR}/.task_meta.json"
_FALLBACK=$( [ "${CLI}" = "codex" ] && [ -f "${TASK_DIR}/_codex_fallback.log" ] && echo true || echo false )

command -v jq >/dev/null 2>&1 && jq -n \
  --arg task_id   "$TASK_ID" \
  --arg agent     "$CLI" \
  --arg task_type "${_TASK_TYPE:-unknown}" \
  --arg date      "$(date +%Y-%m-%d)" \
  --argjson elapsed  "${_ELAPSED:-0}" \
  --argjson tokens   "${_TOKENS:-0}" \
  --argjson start_ts "${DISPATCH_START_TS:-0}" \
  --argjson fallback "$_FALLBACK" \
  '{task_id:$task_id, agent:$agent, task_type:$task_type, date:$date,
    started_ts:$start_ts, elapsed_sec:$elapsed, tokens_used:$tokens,
    loc_added:0, loc_deleted:0, ac_pass:0, ac_fail:0, fallback_used:$fallback
   }' > "$_META_FILE" 2>/dev/null || true
```

**`verify.sh`** — 검증 통과 후(AC 점수 기록 블록 근처) LOC + AC 추가:

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
    "$_META" > "${_META}.tmp" && mv "${_META}.tmp" "$_META"
fi
```

**`record-score.sh`** — 릴리스 락 해제 후 `.agent_metrics.json` 누적:

```bash
# .task_meta.json → .agent_metrics.json 누적
_META_FILE="${PROJECT_ROOT}/_agent_reports/${TASK_ID:-}/.task_meta.json"
if [ -f "$_META_FILE" ] && command -v jq >/dev/null 2>&1; then
  METRICS_FILE="${PROJECT_ROOT}/_agent_reports/.agent_metrics.json"
  [ ! -f "$METRICS_FILE" ] && echo '{"version":1,"records":[],"daily":{}}' > "$METRICS_FILE"
  _TODAY="$(date +%Y-%m-%d)"
  jq \
    --slurpfile meta "$_META_FILE" \
    --arg today "$_TODAY" \
    --arg agent "$AGENT" \
    '.records += [$meta[0]] |
     .daily[$today][$agent] //= {"tasks":0,"tokens":0,"elapsed_sec":0,"loc":0,"ac_pass":0,"ac_fail":0} |
     .daily[$today][$agent].tasks       += 1 |
     .daily[$today][$agent].tokens      += ($meta[0].tokens_used // 0) |
     .daily[$today][$agent].elapsed_sec += ($meta[0].elapsed_sec // 0) |
     .daily[$today][$agent].loc         += (($meta[0].loc_added // 0) + ($meta[0].loc_deleted // 0)) |
     .daily[$today][$agent].ac_pass     += ($meta[0].ac_pass // 0) |
     .daily[$today][$agent].ac_fail     += ($meta[0].ac_fail // 0)
    ' "$METRICS_FILE" > "${METRICS_FILE}.tmp" \
    && mv "${METRICS_FILE}.tmp" "$METRICS_FILE" || true
fi
```

**`scripts/daily-review.sh`** (신규):

```
Usage: bash daily-review.sh [YYYY-MM-DD] [project-dir]
       날짜 생략 시 오늘 날짜 사용

입력: _agent_reports/.agent_metrics.json
출력: _agent_reports/daily/YYYY-MM-DD.md

내용:
  1. 에이전트별 일별 요약 테이블 (태스크수·AC통과율·총토큰·토큰/태스크·평균소요·LOC·토큰/LOC)
  2. 태스크 유형별 효율 비교 (codex vs agy 토큰/AC, 차이 %)
  3. 개별 태스크 기록 테이블
  4. "다음 세션 Claude 배정 참고" 섹션 (효율 우위 20%+ 시 명시, 부하 현황, fallback 발생)
```

**`SKILL.md` 단계 1.6 (적응형 스코어 보정) 추가 항목**:

```
기존: .agent_scores.json AC 통과율 15%p 차이 → 에이전트 보정

추가 보정 기준 (daily-review.md 존재 시):
  1. 태스크 유형별 토큰/AC 차이 20%+ → 효율 우위 에이전트로 보정
     로그: "[효율] task_type=shell_scripting: codex 12,700 < agy 18,000 (29%) → codex로 보정"
  2. 오늘 에이전트 총 토큰 임계값 초과 (기본: 500,000)
     → 임계 초과 에이전트 우선순위 -1, 상대 에이전트로 분산
     로그: "[효율] agy 오늘 480k/500k (96%) — 다음 배정 codex 우선"
  3. fallback_used=true 빈도 높은 에이전트 → 해당 task_type 우선순위 하락
```

**`dashboard.sh`** — 헤더에 오늘 효율 요약 1줄 추가:

```
에이전트 효율 (오늘): codex 6태스크/240k토큰/163s평균  agy 5태스크/380k토큰/298s평균
```

### 완료 기준 (AC)

- [ ] `dispatch.sh` 완료 시 `.task_meta.json` 생성 (tokens/elapsed/fallback 포함)
- [ ] `verify.sh` 통과 시 `.task_meta.json`에 loc/ac 추가됨
- [ ] `record-score.sh` 호출 시 `.agent_metrics.json`에 레코드 누적
- [ ] `daily-review.sh` 실행 시 `daily/YYYY-MM-DD.md` 생성
- [ ] daily-review.md에 4개 섹션 (요약·유형별·개별·배정 참고) 모두 포함
- [ ] jq 미설치 환경에서 오류 없이 건너뜀
- [ ] `bash -n` 문법 검사 통과

---

## 태스크 배정 계획

| ID | 설명 | 에이전트 | 크기 | 의존 |
|----|------|---------|-----|------|
| T-M13-A | AGENTS.md 통합 — init.sh + dispatch.sh | codex | 소형 | — |
| T-M13-B | 세션 연속성 훅 — session-start + pre-compact | agy | 중형 | — |
| T-M13-C | SHARED_TASK_NOTES 브리지 — dispatch + verify + init | codex | 소형 | T-M13-A 후 |
| T-M13-D | AgentShield 5카테고리 스캐너 | agy | 중형 | — |
| T-M13-E | 에이전트 효율 추적 + daily-review.sh | codex | 중형 | — |

**병렬 1라운드**: T-M13-A(codex) + T-M13-B(agy)  
**병렬 2라운드**: T-M13-C(codex) + T-M13-D(agy)  
**단독 3라운드**: T-M13-E(codex)

> T-M13-D와 T-M13-E는 verify.sh 수정 부위가 달라 병렬 가능하나  
> dispatch.sh를 모두 수정하는 T-M13-A·C·E는 순차 처리 필요.

---

## 파일 생성·수정 요약

| 파일 | 작업 | 태스크 |
|------|------|--------|
| `scripts/init.sh` | AGENTS.md 생성 + SHARED_TASK_NOTES.md 생성 블록 추가 | A, C |
| `scripts/dispatch.sh` | AGENTS.md 힌트 + NOTES 힌트 + 토큰 추출 + `.task_meta.json` 저장 | A, C, E |
| `scripts/verify.sh` | NOTES append + LOC 집계 + AgentShield 연동 | C, D, E |
| `scripts/record-score.sh` | `.agent_metrics.json` 누적 추가 | E |
| `scripts/doctor.sh` | agent-shield.sh 존재 체크 추가 | D |
| `scripts/dashboard.sh` | 오늘 효율 요약 1줄 추가 | E |
| `SKILL.md` | 단계 1.6 효율 보정 기준 추가 | E |
| `scripts/agent-shield.sh` | **신규** — 5카테고리 보안 스캐너 | D |
| `scripts/daily-review.sh` | **신규** — 일별 효율 리뷰 생성 | E |
| `scripts/hooks/session-start.sh` | **신규** — SessionStart 훅 | B |
| `scripts/hooks/pre-compact.sh` | **신규** — PreCompact 훅 | B |
| `scripts/install-skill.ps1` | `--Update` 시 `hooks/` 동기화 추가 | B |
