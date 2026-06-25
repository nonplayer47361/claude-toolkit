<#
.SYNOPSIS
  MCP 서버를 Claude Code 글로벌 settings.json에 등록한다.

.PARAMETER ServerName
  settings.json에 등록할 서버 키 이름

.PARAMETER ServerPath
  index.js 파일의 절대 경로

.PARAMETER ProjectPath
  특정 프로젝트에만 등록할 경우 해당 프로젝트 루트. 생략 시 글로벌 등록.

.EXAMPLE
  .\register-mcp.ps1 -ServerName notion-bridge -ServerPath "C:\...\mcp-servers\notion-bridge\index.js"
#>
param(
  [Parameter(Mandatory)][string]$ServerName,
  [Parameter(Mandatory)][string]$ServerPath,
  [string]$ProjectPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ServerPath)) {
  Write-Error "서버 파일을 찾을 수 없음: $ServerPath"
  exit 1
}

# 설정 파일 경로 결정
if ($ProjectPath) {
  $settingsPath = Join-Path $ProjectPath ".claude\settings.json"
} else {
  $settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
}

# 기존 설정 읽기 (없으면 빈 객체)
if (Test-Path $settingsPath) {
  $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
  New-Item -ItemType File -Force -Path $settingsPath | Out-Null
  $settings = [PSCustomObject]@{}
}

# mcpServers 섹션이 없으면 추가
if (-not $settings.PSObject.Properties["mcpServers"]) {
  $settings | Add-Member -NotePropertyName "mcpServers" -NotePropertyValue ([PSCustomObject]@{})
}

# 서버 등록
$serverConfig = [PSCustomObject]@{
  command = "node"
  args    = @($ServerPath)
}
$settings.mcpServers | Add-Member -NotePropertyName $ServerName -NotePropertyValue $serverConfig -Force

# 저장
$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding utf8

Write-Host "✓ MCP 서버 '$ServerName' 등록 완료 → $settingsPath"
Write-Host "  Claude Code를 재시작하면 서버가 활성화됩니다."
Write-Host ""
Write-Host "  등록된 설정:"
Write-Host "    `"$ServerName`": { command: `"node`", args: [`"$ServerPath`"] }"
