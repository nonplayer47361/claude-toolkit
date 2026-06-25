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

    [string]$SkillDir = (Join-Path $HOME ".claude\skills\cli-agent-team")
)

Set-Location $ProjectDir

$reportsDir   = "_agent_reports"
$pendingFile  = "$reportsDir\.pending_$Agent"
$daemonMarker = "$reportsDir\.daemon_$Agent"

New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null

# 데몬 실행 마커 등록 (trigger.sh가 이 파일로 데몬 존재 확인)
"RUNNING" | Set-Content $daemonMarker -Encoding UTF8

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

Write-Host "[$Agent] 🟢 대기 시작 (양방향 실시간 모드)"
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
            "IN_PROGRESS" | Set-Content $statusFile -Encoding UTF8

            Write-Host "[$Agent] 📥 수신: $taskId ($mode)"
            Write-Host "[$Agent] ▶  실행 중..."
            Write-Host ""

            # dispatch.sh를 스킬 절대경로로 호출 (프로젝트 폴더 기준 아님)
            bash "$dispatchScriptBash" $Agent $taskId $AuthMode $ProjectDir $mode

            "DONE" | Set-Content $statusFile -Encoding UTF8
            Write-Host ""
            Write-Host "[$Agent] ✅ 완료: $taskId"
            Write-Host "[$Agent] ── 다음 지시 대기 중 ──"
            Write-Host ""
        }
        Start-Sleep -Seconds 3
    }
}
finally {
    Remove-Item $daemonMarker -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "[$Agent] 🔴 종료됨"
}
