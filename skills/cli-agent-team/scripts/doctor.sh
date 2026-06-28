#!/usr/bin/env bash
# doctor.sh [project-dir]
#
# Diagnose whether the current project is ready to run cli-agent-team.

PROJECT_DIR="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$PROJECT_DIR/_agent_reports/.cli-agent-team.conf"
AGENT_ROLES="$PROJECT_DIR/AGENT_ROLES.md"

OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

print_result() {
  local status="$1"
  local message="$2"

  case "$status" in
    OK)
      OK_COUNT=$((OK_COUNT + 1))
      printf '[OK]   %s\n' "$message"
      ;;
    WARN)
      WARN_COUNT=$((WARN_COUNT + 1))
      printf '[WARN] %s\n' "$message"
      ;;
    FAIL)
      FAIL_COUNT=$((FAIL_COUNT + 1))
      printf '[FAIL] %s\n' "$message"
      ;;
  esac
}

conf_value() {
  local key="$1"
  [ -f "$CONF_FILE" ] || return 0
  grep -E "^${key}=" "$CONF_FILE" 2>/dev/null | head -1 | sed "s/^${key}=//; s/[[:space:]]#.*$//"
}

detect_test_command() {
  if [ -f "$PROJECT_DIR/package.json" ] && grep -q '"test"[[:space:]]*:' "$PROJECT_DIR/package.json" 2>/dev/null; then
    printf 'npm test'
    return 0
  fi

  if command -v pytest >/dev/null 2>&1; then
    printf 'pytest'
    return 0
  fi

  if [ -f "$PROJECT_DIR/Makefile" ] && grep -qE '^test:' "$PROJECT_DIR/Makefile" 2>/dev/null; then
    printf 'make test'
    return 0
  fi

  if [ -f "$PROJECT_DIR/Cargo.toml" ] || [ -f "$PROJECT_DIR/cargo.toml" ]; then
    printf 'cargo test'
    return 0
  fi

  return 1
}

echo ""
echo "[cli-agent-team] doctor"
echo "Project: $PROJECT_DIR"
echo "----------------------------------------"

if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  print_result OK "Git repository detected"
else
  print_result FAIL "Git repository not detected"
fi

if command -v codex >/dev/null 2>&1; then
  print_result OK "codex CLI found ($(command -v codex))"
else
  print_result WARN "codex CLI not found"
fi

if command -v agy >/dev/null 2>&1; then
  print_result OK "agy CLI found ($(command -v agy))"
else
  print_result WARN "agy CLI not found"
fi

if command -v node >/dev/null 2>&1; then
  NODE_VERSION="$(node --version 2>/dev/null || true)"
  print_result OK "Node.js found (${NODE_VERSION:-version unknown})"
else
  print_result WARN "Node.js not found (required for agy pty-bridge)"
fi

PTY_BRIDGE_CANDIDATE="${PTY_BRIDGE_PATH:-}"
if [ -z "$PTY_BRIDGE_CANDIDATE" ]; then
  PTY_BRIDGE_CANDIDATE="$(conf_value PTY_BRIDGE_PATH)"
fi
if [ -z "$PTY_BRIDGE_CANDIDATE" ]; then
  PTY_BRIDGE_CANDIDATE="$SCRIPT_DIR/../../../mcp-servers/pty-bridge/run.js"
fi

if [ -f "$PTY_BRIDGE_CANDIDATE" ]; then
  print_result OK "pty-bridge found at $PTY_BRIDGE_CANDIDATE"
else
  print_result WARN "pty-bridge not found (required for reliable agy headless output)"
fi

if printf '%s\n' "$PROJECT_DIR" | grep -qP '[^\x00-\x7F ]' 2>/dev/null || printf '%s\n' "$PROJECT_DIR" | grep -q ' '; then
  print_result WARN "Project path contains spaces or non-ASCII characters"
else
  print_result OK "Project path has no spaces or non-ASCII characters"
fi

if [ -f "$CONF_FILE" ]; then
  print_result OK ".cli-agent-team.conf exists"
else
  print_result WARN ".cli-agent-team.conf not found (run setup.sh first)"
fi

if [ -f "$AGENT_ROLES" ]; then
  print_result OK "AGENT_ROLES.md exists"
else
  print_result WARN "AGENT_ROLES.md not found"
fi

TEST_COMMAND="$(detect_test_command || true)"
if [ -n "$TEST_COMMAND" ]; then
  print_result OK "Test command detected: $TEST_COMMAND"
else
  print_result WARN "Test command not detected (define it in AGENT_ROLES.md)"
fi

echo ""
echo "[토큰 최적화 인프라]"

if command -v rtk >/dev/null 2>&1; then
  _RTK_VER="$(rtk --version 2>/dev/null | head -1 || true)"
  print_result OK "RTK found${_RTK_VER:+ ($_RTK_VER)} — CLI 출력 압축 활성"
else
  print_result WARN "RTK not found — 설치하면 토큰 60-90% 절감 (rtk gain으로 확인)"
fi

_CBM_BIN="$(ls "${APPDATA:-$HOME/AppData/Roaming}/../Local/Programs/codebase-memory-mcp/codebase-memory-mcp.exe" 2>/dev/null || true)"
_CBM_MCP="${HOME}/.claude/.mcp.json"
if [ -n "$_CBM_BIN" ] || ([ -f "$_CBM_MCP" ] && grep -q "codebase-memory-mcp" "$_CBM_MCP" 2>/dev/null); then
  print_result OK "codebase-memory-mcp 등록됨 — 코드 그래프 검색 활성"
else
  print_result WARN "codebase-memory-mcp 미설치 — ~/.claude/.mcp.json에 등록하면 코드 탐색 효율 향상"
fi

if command -v serena-hooks >/dev/null 2>&1; then
  print_result OK "Serena (serena-hooks) found — LSP 심볼 탐색 활성"
else
  print_result WARN "Serena 미설치 — 심볼 기반 편집 효율 향상 가능"
fi

echo "----------------------------------------"
if [ "$FAIL_COUNT" -eq 0 ]; then
  printf 'doctor result: all checks passed - cli-agent-team is ready (OK %s / WARN %s / FAIL %s)\n' "$OK_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
else
  printf 'doctor result: OK %s / WARN %s / FAIL %s\n' "$OK_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
  echo "Fix FAIL items before using cli-agent-team."
fi
