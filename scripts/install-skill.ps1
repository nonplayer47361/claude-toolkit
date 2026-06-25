<#
.SYNOPSIS
  Claude Code 스킬을 글로벌 또는 특정 프로젝트에 설치한다.

.PARAMETER SkillName
  설치할 스킬 폴더명 (skills/ 하위)

.PARAMETER ProjectPath
  특정 프로젝트에 설치할 경로. 생략 시 글로벌(~/.claude/skills/)에 설치.

.EXAMPLE
  .\install-skill.ps1 -SkillName git-helper
  .\install-skill.ps1 -SkillName git-helper -ProjectPath C:\projects\my-app
#>
param(
  [Parameter(Mandatory)][string]$SkillName,
  [string]$ProjectPath
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

# 기존 설치 백업
if (Test-Path $dest) {
  $backup = "$dest.bak"
  Write-Host "기존 설치 백업: $backup"
  Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue
  Copy-Item $dest $backup -Recurse
}

# 복사
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item "$skillSrc\*" $dest -Recurse -Force

Write-Host "✓ 스킬 '$SkillName' 설치 완료 → $dest"
if ($ProjectPath) {
  Write-Host "  프로젝트 CLAUDE.md에 트리거 설명을 추가하는 것을 잊지 마세요."
} else {
  Write-Host "  Claude Code를 재시작하면 스킬이 활성화됩니다."
}
