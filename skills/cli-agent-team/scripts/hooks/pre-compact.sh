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
