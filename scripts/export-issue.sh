#!/usr/bin/env bash

REPORTS_DIR="_agent_reports"
ERROR_LOG="${REPORTS_DIR}/error.log"
CONF_FILE="${REPORTS_DIR}/.cli-agent-team.conf"
ISSUES_URL="https://github.com/nonplayer47361/claude-toolkit/issues"

timestamp="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date '+%Y%m%d-%H%M%S')"
created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ')"
out_file="issue-report-${timestamp}.txt"

redact_stream() {
  sed -E \
    -e 's#/Users/[^/]+/#<HOME>/#g' \
    -e 's#C:[\\/]+Users[\\/]+[^\\/[:space:]]+#C:\\Users\\<USER>#g' \
    -e 's#sk-[A-Za-z0-9]+#<REDACTED>#g' \
    -e 's#ghp_[A-Za-z0-9]+#<REDACTED>#g'
}

append_section() {
  local title="$1" file_path="$2"

  {
    printf '\n=== %s ===\n' "$title"
    if [ -f "$file_path" ]; then
      redact_stream < "$file_path"
    else
      printf '(missing: %s)\n' "$file_path"
    fi
  } >> "$out_file"
}

collect_task_ids() {
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@"
  elif [ -f "$ERROR_LOG" ]; then
    sed -n 's/^\[[^]]*\] \[\([^]]*\)\].*/\1/p' "$ERROR_LOG" | tail -5
  fi
}

version="$(git log --oneline -1 2>/dev/null || printf 'unknown')"
os_name="$(uname -s 2>/dev/null || printf 'Windows')"

{
  printf '=== claude-toolkit issue report ===\n'
  printf 'created: %s\n' "$created_at"
  printf 'version: %s\n' "$version"
  printf 'OS: %s\n' "$os_name"
} > "$out_file"

append_section "error.log" "$ERROR_LOG"

task_ids="$(collect_task_ids "$@")"
if [ -n "$task_ids" ]; then
  printf '%s\n' "$task_ids" | while IFS= read -r task_id; do
    [ -z "$task_id" ] && continue
    append_section "${task_id}/TASK.md" "${REPORTS_DIR}/${task_id}/TASK.md"
    append_section "${task_id}/REPORT.md" "${REPORTS_DIR}/${task_id}/REPORT.md"
  done
fi

append_section ".cli-agent-team.conf" "$CONF_FILE"

{
  printf '\n=== Sharing ===\n'
  printf 'Attach this file to a GitHub Issue or send it by email.\n'
  printf '%s\n' "$ISSUES_URL"
} >> "$out_file"

printf '%s\n' "$out_file"
