#Requires -Version 5.1
# start-daemons.ps1 - start codex/agy watchers and dashboard together
#
# Usage:
#   .\scripts\start-daemons.ps1
#   .\scripts\start-daemons.ps1 -AuthMode full -ProjectDir "C:\projects\my-app"
#
# Opens three tabs when Windows Terminal (wt.exe) is available.
# Otherwise, opens three separate PowerShell windows.

param(
    [string]$AuthMode = "full",
    [string]$ProjectDir = (Get-Location).Path,
    [string]$SkillDir = ""
)

$ErrorActionPreference = "Stop"

if (-not $SkillDir) {
    $SkillDir = "$env:USERPROFILE\.claude\skills\cli-agent-team"
}

function Quote-PowerShellSingle {
    param([string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

$ProjectDirArg = Quote-PowerShellSingle $ProjectDir
$SkillDirArg = Quote-PowerShellSingle $SkillDir

$WatchScript = Join-Path $SkillDir "scripts\agent-watch.ps1"
$DashScript = Join-Path $SkillDir "scripts\dashboard.sh"

$WatchScriptArg = Quote-PowerShellSingle $WatchScript
$DashScriptArg = Quote-PowerShellSingle $DashScript

$WtCmd = Get-Command "wt" -ErrorAction SilentlyContinue
$WtExe = if ($WtCmd) { $WtCmd.Source } else { "" }

$CodexCommand = "Set-Location $ProjectDirArg; & $WatchScriptArg -Agent codex -AuthMode '$AuthMode' -ProjectDir $ProjectDirArg"
$AgyCommand = "Set-Location $ProjectDirArg; & $WatchScriptArg -Agent agy -AuthMode '$AuthMode' -ProjectDir $ProjectDirArg"
$DashboardCommand = "bash $DashScriptArg --watch"

if ($WtExe) {
    $WtArgs = @(
        "new-tab --title `"codex-watch`" pwsh -NoExit -Command `"$CodexCommand`"",
        "; new-tab --title `"agy-watch`" pwsh -NoExit -Command `"$AgyCommand`"",
        "; new-tab --title `"dashboard`" pwsh -NoExit -Command `"$DashboardCommand`""
    ) -join " "

    Start-Process "wt" -ArgumentList $WtArgs
    Write-Host "Started Windows Terminal tabs: codex-watch / agy-watch / dashboard" -ForegroundColor Green
} else {
    Start-Process "pwsh" -ArgumentList "-NoExit", "-Command", $CodexCommand -WindowStyle Normal
    Start-Process "pwsh" -ArgumentList "-NoExit", "-Command", $AgyCommand -WindowStyle Normal
    Start-Process "pwsh" -ArgumentList "-NoExit", "-Command", $DashboardCommand -WindowStyle Normal
    Write-Host "Started three PowerShell windows: codex-watch / agy-watch / dashboard" -ForegroundColor Green
}

Write-Host ""
Write-Host "Usage: .\scripts\start-daemons.ps1 -AuthMode full -ProjectDir 'C:\projects\my-app'" -ForegroundColor Gray
