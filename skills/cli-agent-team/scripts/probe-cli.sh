#!/usr/bin/env bash
# probe-cli.sh <cli> <auth-mode> [project-dir]
#
# Run this ONCE per CLI per project, before relying on it for real work.
# Verifies two things that --help cannot tell you:
#   1. Does a trivial non-interactive call actually return text on stdout?
#   2. Does a trivial non-interactive call actually write a file to disk?
# Completion must be judged by artifact #2, not by stdout or exit code alone
# (agy is known to stay silent on stdout while still writing files correctly
# in headless mode — see references/cli-dispatch-guide.md).
#
#   <cli>         codex | agy
#   <auth-mode>   full | limited  (passed through as-is, never assumed)
#   [project-dir] defaults to the current directory

set -euo pipefail

CLI="${1:?usage: probe-cli.sh <cli> <auth-mode> [project-dir]}"
AUTH_MODE="${2:?auth-mode required: full|limited}"
DIR="${3:-$(pwd)}"

PROBE_FILE="_agent_reports/_probe_${CLI}.txt"
mkdir -p "_agent_reports"
rm -f "$PROBE_FILE"

TEXT_PROMPT="Reply with exactly: PROBE_OK"
FILE_PROMPT="현재 작업 디렉토리에 ${PROBE_FILE} 파일을 만들고 내용은 정확히 'PROBE_OK'라고만 써줘."

echo "=== [1/2] text-reply probe ($CLI, auth=$AUTH_MODE) ==="
case "$CLI" in
  codex)
    case "$AUTH_MODE" in
      full) codex exec --dangerously-bypass-approvals-and-sandbox -C "$DIR" "$TEXT_PROMPT" || true ;;
      limited) codex exec -C "$DIR" "$TEXT_PROMPT" || true ;;
    esac
    ;;
  agy)
    case "$AUTH_MODE" in
      full) agy --print "$TEXT_PROMPT" --add-dir "$DIR" --dangerously-skip-permissions --print-timeout 60s || true ;;
      limited) agy --print "$TEXT_PROMPT" --add-dir "$DIR" --print-timeout 60s || true ;;
    esac
    ;;
  *)
    echo "ERROR: unknown cli '$CLI'" >&2; exit 1 ;;
esac
echo "(stdout above may be empty for some CLIs even on success — that's expected, see step 2)"

echo "=== [2/2] file-write probe ($CLI, auth=$AUTH_MODE) ==="
case "$CLI" in
  codex)
    case "$AUTH_MODE" in
      full) codex exec --dangerously-bypass-approvals-and-sandbox -C "$DIR" "$FILE_PROMPT" || true ;;
      limited) codex exec -C "$DIR" "$FILE_PROMPT" || true ;;
    esac
    ;;
  agy)
    case "$AUTH_MODE" in
      full) agy --print "$FILE_PROMPT" --add-dir "$DIR" --dangerously-skip-permissions --print-timeout 60s || true ;;
      limited) agy --print "$FILE_PROMPT" --add-dir "$DIR" --print-timeout 60s || true ;;
    esac
    ;;
esac

echo "=== RESULT ==="
if [ -f "$PROBE_FILE" ] && grep -q "PROBE_OK" "$PROBE_FILE"; then
  echo "PASS: $CLI ($AUTH_MODE) can perform real file-writing tasks headlessly."
  rm -f "$PROBE_FILE"
  exit 0
else
  echo "FAIL: $PROBE_FILE was not created with expected content."
  echo "Do not assume $CLI is automatable in this mode until this passes."
  exit 1
fi
