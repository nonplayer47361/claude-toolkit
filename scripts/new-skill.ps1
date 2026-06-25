<#
.SYNOPSIS
  _template을 복사해서 새 스킬 폴더를 만든다.

.PARAMETER Name
  새 스킬 이름 (kebab-case)

.EXAMPLE
  .\new-skill.ps1 -Name git-helper
#>
param([Parameter(Mandatory)][string]$Name)

$ErrorActionPreference = "Stop"

$toolkitRoot = Split-Path $PSScriptRoot -Parent
$template = Join-Path $toolkitRoot "skills\_template"
$dest = Join-Path $toolkitRoot "skills\$Name"

if (Test-Path $dest) {
  Write-Error "이미 존재함: $dest"
  exit 1
}

Copy-Item $template $dest -Recurse

# SKILL.md의 name 필드를 자동으로 채운다
$skillMd = Join-Path $dest "SKILL.md"
(Get-Content $skillMd) -replace "name: skill-name", "name: $Name" | Set-Content $skillMd -Encoding utf8

Write-Host "✓ 새 스킬 생성: $dest"
Write-Host "  다음 단계: $skillMd 를 편집하세요."
