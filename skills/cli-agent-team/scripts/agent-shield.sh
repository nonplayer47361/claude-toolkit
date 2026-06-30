#!/usr/bin/env bash
# agent-shield.sh <project-dir>
# 7카테고리 보안 스캔. exit 0=clean, exit 1=warning, exit 2=critical
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
SHIELD_EXIT=0
SEP="────────────────────────────────────────"

emit() {
  local level="$1" msg="$2"
  echo "  [${level}] ${msg}"
  if [ "$level" = "CRITICAL" ]; then
    SHIELD_EXIT=2
  elif [ "$level" = "WARNING" ] && [ "$SHIELD_EXIT" -lt 1 ]; then
    SHIELD_EXIT=1
  fi
}

SEC_DIFF=$(cd "$PROJECT_DIR" && git diff HEAD 2>/dev/null || true)
UNTRACKED=$(cd "$PROJECT_DIR" && git ls-files --others --exclude-standard 2>/dev/null || true)
ADDED_DIFF=$(printf '%s\n' "$SEC_DIFF" | grep '^+[^+]' 2>/dev/null || true)

echo ""; echo "[AgentShield] 보안 스캔"; echo "$SEP"

# ① secrets — diff + untracked 모두 스캔
SECRET_PAT='(api[_-]?key|aws_access_key|aws_secret|GITHUB_TOKEN|GH_TOKEN|private_key|client_secret|auth_token|-----BEGIN (RSA|EC|OPENSSH)|password[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"']{8,}|token[[:space:]]*[=:][[:space:]]*["'"'"'][A-Za-z0-9_\-]{16,})'
hit=$(printf '%s\n' "$ADDED_DIFF" | \
  grep -v '^+SECRET_PAT=' | grep -iE "$SECRET_PAT" 2>/dev/null || true)
if [ -n "$hit" ]; then
  emit CRITICAL "secrets 패턴 탐지 (diff)"
else
  echo "  ✅ ① secrets (diff) 이상 없음"
fi
if [ -n "$UNTRACKED" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$PROJECT_DIR/$f" ] || continue
    uhit=$(grep -inE "$SECRET_PAT" "$PROJECT_DIR/$f" 2>/dev/null | grep -v 'SECRET_PAT=' || true)
    [ -n "$uhit" ] && emit CRITICAL "secrets 패턴 탐지 (untracked: $f)"
  done <<< "$UNTRACKED"
fi

# ② hook injection — 실제 settings.json/hooks.json 파일 변경 여부만 감지
if printf '%s\n' "$SEC_DIFF" | grep -qE '^diff --git.*(settings\.json|hooks\.json)'; then
  bad=$(printf '%s\n' "$SEC_DIFF" | grep '^+' | \
    grep -E '"command"[[:space:]]*:[[:space:]]*"[^~].*(tmp|AppData/Local/Temp|/var/tmp)' || true)
  [ -n "$bad" ] && emit CRITICAL "hook injection 의심 경로" || emit WARNING "settings.json 변경 — 검토 권장"
else
  echo "  ✅ ② hook injection 변경 없음"
fi

# ③ MCP risk
if printf '%s\n' "$SEC_DIFF" | grep -q 'claude_desktop_config\|mcpServers'; then
  bad=$(printf '%s\n' "$SEC_DIFF" | grep '^+' | \
    grep -E '"url"[[:space:]]*:[[:space:]]*"http://' || true)
  [ -n "$bad" ] && emit WARNING "비암호화 http:// MCP 서버 추가" || echo "  ✅ ③ MCP risk 이상 없음"
else
  echo "  ✅ ③ MCP risk 변경 없음"
fi

# ④ agent config
AGENT_CONFIG_PAT='auth.?mode.*full|dangerously.bypass.*approvals'
bad=$(printf '%s\n' "$ADDED_DIFF" | grep -v '^+AGENT_CONFIG_PAT=' | \
  grep -E "$AGENT_CONFIG_PAT" || true)
[ -n "$bad" ] && emit WARNING "agent config 위험 설정 탐지" || echo "  ✅ ④ agent config 이상 없음"

# ⑤ permissions — 주석·마크다운 목록 행 제외하여 false positive 방지
PERMISSION_PAT='(chmod[[:space:]]+777|sudo[[:space:]]+rm|sudo[[:space:]]+chmod|--dangerously-skip-permissions)'
bad=$(printf '%s\n' "$ADDED_DIFF" | grep -v '^+PERMISSION_PAT=' | \
  grep -v '^+[[:space:]]*#' | \
  grep -v '^+[[:space:]]*[-*]' | \
  grep -E "$PERMISSION_PAT" || true)
[ -n "$bad" ] && emit CRITICAL "위험 권한 명령 탐지" || echo "  ✅ ⑤ permissions 이상 없음"

# ⑥ 검증 명령 메타문자 (AGENTS.md·AGENT_ROLES.md 검증 명령란)
META_FOUND=0
for cfg in "$PROJECT_DIR/AGENTS.md" "$PROJECT_DIR/AGENT_ROLES.md"; do
  [ ! -f "$cfg" ] && continue
  meta=$(grep -n -E 'bash[[:space:]]+-c[[:space:]]+.*[;&|]|\$\(' "$cfg" 2>/dev/null || true)
  if [ -n "$meta" ]; then
    emit CRITICAL "검증 명령 메타문자 탐지: $(basename "$cfg")"
    META_FOUND=1
  fi
done
[ "$META_FOUND" -eq 0 ] && echo "  ✅ ⑥ 검증 명령 메타문자 이상 없음"

# ⑦ untracked 파일 secrets (①에서 처리)
echo "  ✅ ⑦ untracked 파일 스캔 완료"

echo "$SEP"
case "$SHIELD_EXIT" in
  0) echo "  ✅ AgentShield: 전체 통과" ;;
  1) echo "  ⚠  AgentShield: Warning (통과, 검토 권장)" ;;
  2) echo "  ❌ AgentShield: Critical — 커밋 차단" ;;
esac
exit "$SHIELD_EXIT"
