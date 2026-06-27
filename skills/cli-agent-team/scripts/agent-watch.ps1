<#
.SYNOPSIS
  CLI 에이전트를 "Claude 지시 대기" 모드로 실행한다.
  VS Code 전용 터미널 패널에서 실행하면, Claude가 TASK 파일을 업데이트할 때마다
  자동으로 감지해 작업을 수행하고 완료 신호를 남긴다.

.DESCRIPTION
  - 이 스크립트를 실행하는 터미널 패널 1개 = 에이전트 1개.
  - Claude가 _agent_reports/.pending_<agent> 파일을 쓰면 3초 내 감지 → 작업 실행.
  - 완료 시 _agent_reports/.status_<task-id>_<agent> = DONE 기록.
  - Claude의 trigger.sh 가 이 신호를 감지해 다음 단계로 진행.

.PARAMETER Agent
  codex | agy

.PARAMETER AuthMode
  full    → 승인/샌드박스 우회 (사용자가 이 프로젝트에 명시적으로 동의한 경우만)
  limited → CLI 기본 승인 모드

.PARAMETER ProjectDir
  프로젝트 루트 절대경로 (기본: 현재 폴더)

.PARAMETER SkillDir
  cli-agent-team 스킬 루트 (기본: ~/.claude/skills/cli-agent-team)
  dispatch.sh를 찾는 데 사용된다.

.EXAMPLE
  # 프로젝트 루트로 이동 후 실행 (권장):
  cd "C:\projects\my-app"
  ~\.claude\skills\cli-agent-team\scripts\agent-watch.ps1 -Agent codex -AuthMode full

  # 또는 -ProjectDir 명시:
  ~\.claude\skills\cli-agent-team\scripts\agent-watch.ps1 -Agent agy -AuthMode full -ProjectDir "C:\projects\my-app"
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet("codex", "agy")]
    [string]$Agent,

    [Parameter(Mandatory)]
    [ValidateSet("full", "limited")]
    [string]$AuthMode,

    [string]$ProjectDir = (Get-Location).Path,

    [string]$SkillDir = ""
)

# SkillDir 자동 감지: 이 스크립트는 <SkillDir>/scripts/agent-watch.ps1 위치에 있음
# $HOME이 빈 문자열로 resolve되는 PS 5.1 엣지케이스 우회
if (-not $SkillDir) {
    $SkillDir = Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent
}

Set-Location $ProjectDir

$reportsDir   = "_agent_reports"
$pendingFile  = "$reportsDir\.pending_$Agent"
$daemonMarker = "$reportsDir\.daemon_$Agent"

New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null

# 데몬 실행 마커 등록 (trigger.sh가 이 파일로 데몬 존재 확인)
"RUNNING" | Set-Content $daemonMarker -Encoding UTF8

# 이전 세션에서 중단된 IN_PROGRESS 상태 파일 정리
# (컴퓨터 강제 종료 등으로 데몬이 죽으면 상태 파일이 IN_PROGRESS에 멈춤)
Get-ChildItem "$reportsDir" -Filter ".status_*_$Agent" -ErrorAction SilentlyContinue | ForEach-Object {
    $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match "IN_PROGRESS") {
        [System.IO.File]::WriteAllText($_.FullName, "STALE`n")
        Write-Host "[$Agent] [RECOVER] 잔류 IN_PROGRESS 정리: $($_.Name) → STALE"
    }
}

Write-Host ""
$dispatchScript = Join-Path $SkillDir "scripts/dispatch.sh"
if (-not (Test-Path $dispatchScript)) {
    Write-Error "dispatch.sh 를 찾을 수 없습니다: $dispatchScript`n  -SkillDir 파라미터로 스킬 경로를 명시하세요."
    exit 1
}
# bash에서 쓸 수 있도록 Unix 경로로 변환 (PS 5.1 호환 — script block replace는 PS 7+ 전용)
$dispatchScriptBash = $dispatchScript -replace '\\', '/'
if ($dispatchScriptBash -match '^([A-Za-z]):(.+)$') {
    $dispatchScriptBash = "/$($Matches[1].ToLower())$($Matches[2])"
}
# bash 실행 파일 자동 탐지 (PowerShell PATH에 bash가 없는 경우 대비)
$bashExe = "bash"
$bashCandidates = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files\Git\usr\bin\bash.exe",
    "C:\Windows\System32\bash.exe"
)
foreach ($c in $bashCandidates) {
    if (Test-Path $c) { $bashExe = $c; break }
}

Write-Host "[$Agent] [START] 대기 시작 (양방향 실시간 모드)"
Write-Host "[$Agent] 프로젝트 : $ProjectDir"
Write-Host "[$Agent] 권한     : $AuthMode"
Write-Host "[$Agent] 트리거   : $pendingFile"
Write-Host "[$Agent] 종료     : Ctrl+C"
Write-Host ""

try {
    while ($true) {
        if (Test-Path $pendingFile) {
            $lines  = Get-Content $pendingFile -Encoding UTF8
            $taskId = $lines[0].Trim()
            $mode   = if ($lines.Count -gt 1) { $lines[1].Trim() } else { "execute" }

            Remove-Item $pendingFile -Force

            $statusFile = "$reportsDir\.status_${taskId}_$Agent"
            [System.IO.File]::WriteAllText("$ProjectDir\$statusFile", "IN_PROGRESS`n")

            Write-Host "[$Agent] [RECV] 수신: $taskId ($mode)"
            Write-Host "[$Agent] >> 실행 중..."
            Write-Host ""

            # dispatch.sh를 스킬 절대경로로 호출 (프로젝트 폴더 기준 아님)
            & $bashExe "$dispatchScriptBash" $Agent $taskId $AuthMode $ProjectDir $mode
            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0) {
                [System.IO.File]::WriteAllText("$ProjectDir\$statusFile", "DONE`n")
                Write-Host ""
                Write-Host "[$Agent] [DONE] 완료: $taskId"
            } else {
                [System.IO.File]::WriteAllText("$ProjectDir\$statusFile", "ERROR`n")
                Write-Host ""
                Write-Host "[$Agent] [ERROR] 실패 (exit $exitCode): $taskId"
            }
            Write-Host "[$Agent] ── 다음 지시 대기 중 ──"
            Write-Host ""
        }
        Start-Sleep -Seconds 3
    }
}
finally {
    Remove-Item $daemonMarker -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "[$Agent] [STOP] 종료됨"
}


