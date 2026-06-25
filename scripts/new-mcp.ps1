<#
.SYNOPSIS
  _template을 복사해서 새 MCP 서버 폴더를 만든다.

.PARAMETER Name
  새 서버 이름 (kebab-case)

.EXAMPLE
  .\new-mcp.ps1 -Name notion-bridge
#>
param([Parameter(Mandatory)][string]$Name)

$ErrorActionPreference = "Stop"

$toolkitRoot = Split-Path $PSScriptRoot -Parent
$template = Join-Path $toolkitRoot "mcp-servers\_template"
$dest = Join-Path $toolkitRoot "mcp-servers\$Name"

if (Test-Path $dest) {
  Write-Error "이미 존재함: $dest"
  exit 1
}

Copy-Item $template $dest -Recurse

# package.json의 name 필드 업데이트
$pkgPath = Join-Path $dest "package.json"
$pkg = Get-Content $pkgPath | ConvertFrom-Json
$pkg.name = "@yourname/mcp-$Name"
$pkg.description = "$Name MCP 서버"
$pkg | ConvertTo-Json -Depth 5 | Set-Content $pkgPath -Encoding utf8

# index.js의 SERVER_NAME 업데이트
$indexPath = Join-Path $dest "index.js"
(Get-Content $indexPath) -replace 'const SERVER_NAME = "mcp-server-name"', "const SERVER_NAME = `"mcp-$Name`"" | Set-Content $indexPath -Encoding utf8

Write-Host "✓ 새 MCP 서버 생성: $dest"
Write-Host "  다음 단계:"
Write-Host "    1. cd mcp-servers\$Name"
Write-Host "    2. npm install"
Write-Host "    3. index.js의 TOOLS 배열과 핸들러를 수정"
Write-Host "    4. .\scripts\register-mcp.ps1 -ServerName $Name -ServerPath `"$(Resolve-Path $dest)\index.js`""
