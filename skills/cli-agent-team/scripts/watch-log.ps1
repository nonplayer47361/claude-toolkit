# watch-log.ps1 <log-file-path>
#
# Opens a new, visible PowerShell window that live-tails the given log file.
# Use this right after dispatching a CLI agent in the background, so the user
# can watch its real-time stdout without typing anything themselves.
#
# Verified on Windows: Start-Process spawns a separate, independent console
# window; the dispatching session does not need to stay open for it to work.
#
# Only useful for CLIs whose stdout actually carries live progress text
# (Codex does). Some CLIs are silent on stdout in headless mode even while
# successfully doing real work (Antigravity/agy is a known example) — tailing
# their log will show nothing. See cli-dispatch-guide.md before relying on
# this for a new CLI; verify with probe-cli.sh first.

param(
    [Parameter(Mandatory = $true)]
    [string]$LogFile
)

if (-not (Test-Path $LogFile)) {
    New-Item -ItemType File -Path $LogFile -Force | Out-Null
}

Start-Process powershell -ArgumentList '-NoExit', '-Command', "Get-Content -Path `"$LogFile`" -Wait"
