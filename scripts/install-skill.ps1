<#
.SYNOPSIS
  Claude Code 스킬을 글로벌 또는 특정 프로젝트에 설치한다.

.PARAMETER SkillName
  설치할 스킬 폴더명 (skills/ 하위)

.PARAMETER ProjectPath
  특정 프로젝트에 설치할 경로. 생략 시 글로벌(~/.claude/skills/)에 설치.

.PARAMETER Update
  업데이트 모드: scripts/ + SKILL.md만 덮어쓰고 references/ 등 커스터마이징은 보존.
  기존 설치가 없으면 일반 설치로 폴백.

.EXAMPLE
  .\install-skill.ps1 -SkillName git-helper
  .\install-skill.ps1 -SkillName git-helper -ProjectPath C:\projects\my-app
  .\install-skill.ps1 -SkillName cli-agent-team -Update
#>
param(
  [Parameter(Mandatory)][string]$SkillName,
  [string]$ProjectPath,
  [switch]$Update
)

$ErrorActionPreference = "Stop"

$toolkitRoot = Split-Path $PSScriptRoot -Parent
$skillSrc = Join-Path $toolkitRoot "skills\$SkillName"

if (-not (Test-Path $skillSrc)) {
  Write-Error "스킬을 찾을 수 없음: $skillSrc"
  exit 1
}

# 설치 대상 결정
if ($ProjectPath) {
  $dest = Join-Path $ProjectPath ".claude\skills\$SkillName"
} else {
  $dest = Join-Path $env:USERPROFILE ".claude\skills\$SkillName"
}

# 업데이트 모드 — scripts/ + SKILL.md만 교체, references/ 등 보존
if ($Update -and (Test-Path $dest)) {
  $scriptsDir = Join-Path $skillSrc "scripts"
  if (Test-Path $scriptsDir) {
    $destScripts = Join-Path $dest "scripts"
    New-Item -ItemType Directory -Force -Path $destScripts | Out-Null
    Copy-Item "$scriptsDir\*" $destScripts -Recurse -Force
    Write-Host "  scripts/ 업데이트 완료"
  }
  $skillMd = Join-Path $skillSrc "SKILL.md"
  if (Test-Path $skillMd) {
    Copy-Item $skillMd $dest -Force
    Write-Host "  SKILL.md 업데이트 완료"
  }
  Write-Host "✓ 스킬 '$SkillName' 업데이트 완료 (references/ 보존) → $dest"
  exit 0
}

# 일반 설치 — 기존 백업 후 전체 복사
if (Test-Path $dest) {
  $backup = "$dest.bak"
  Write-Host "기존 설치 백업: $backup"
  Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue
  Copy-Item $dest $backup -Recurse
}

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item "$skillSrc\*" $dest -Recurse -Force

Write-Host "✓ 스킬 '$SkillName' 설치 완료 → $dest"
if ($ProjectPath) {
  Write-Host "  프로젝트 CLAUDE.md에 트리거 설명을 추가하는 것을 잊지 마세요."
} else {
  Write-Host "  Claude Code를 재시작하면 스킬이 활성화됩니다."
}
