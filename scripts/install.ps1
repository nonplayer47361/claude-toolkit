#Requires -Version 5.1
# install.ps1 — claude-toolkit 원라이너 설치 스크립트 (Windows)
#
# 사용법 (git clone 불필요):
#   irm https://raw.githubusercontent.com/nonplayer47361/claude-toolkit/main/scripts/install.ps1 | iex
#
# 수행 작업:
#   1. GitHub에서 최신 소스 ZIP 다운로드
#   2. 스킬 3종 ~/.claude/skills/ 에 설치
#   3. pty-bridge npm install (Node.js 있을 때)
#   4. 설치 완료 안내

$ErrorActionPreference = "Stop"

$REPO       = "nonplayer47361/claude-toolkit"
$BRANCH     = "main"
$ZIP_URL    = "https://github.com/$REPO/archive/refs/heads/$BRANCH.zip"
$SEP        = "================================================="

Write-Host ""
Write-Host $SEP -ForegroundColor Cyan
Write-Host "  claude-toolkit 원라이너 설치" -ForegroundColor Cyan
Write-Host $SEP -ForegroundColor Cyan
Write-Host ""

# ── [1/4] 다운로드 ────────────────────────────────────────────────────────────

Write-Host "[1/4] GitHub에서 다운로드 중..." -ForegroundColor Cyan

$TmpDir  = Join-Path $env:TEMP "claude-toolkit-install-$(Get-Random)"
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null
$ZipPath = Join-Path $TmpDir "claude-toolkit.zip"

try {
    Invoke-WebRequest -Uri $ZIP_URL -OutFile $ZipPath -UseBasicParsing
    Write-Host "  ✅ 다운로드 완료" -ForegroundColor Green
} catch {
    Write-Host "  ❌ 다운로드 실패: $_" -ForegroundColor Red
    Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# ── [2/4] 압축 해제 ───────────────────────────────────────────────────────────

Write-Host "[2/4] 압축 해제 중..." -ForegroundColor Cyan

try {
    Expand-Archive -Path $ZipPath -DestinationPath $TmpDir -Force
} catch {
    Write-Host "  ❌ 압축 해제 실패: $_" -ForegroundColor Red
    Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

$Extracted = Get-ChildItem $TmpDir -Directory | Where-Object { $_.Name -like "claude-toolkit-*" } | Select-Object -First 1
if (-not $Extracted) {
    Write-Host "  ❌ 추출된 디렉터리를 찾을 수 없음" -ForegroundColor Red
    Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
$ProjectRoot = $Extracted.FullName
Write-Host "  ✅ 압축 해제 완료" -ForegroundColor Green

# ── [3/4] 스킬 설치 ───────────────────────────────────────────────────────────

Write-Host "[3/4] 스킬 설치 중..." -ForegroundColor Cyan

$ClaudeSkillsDir = Join-Path $env:USERPROFILE ".claude\skills"
New-Item -ItemType Directory -Force -Path $ClaudeSkillsDir | Out-Null

$Skills = @("git-helper", "code-review-ko", "cli-agent-team")
foreach ($Skill in $Skills) {
    $Src  = Join-Path $ProjectRoot "skills\$Skill"
    $Dest = Join-Path $ClaudeSkillsDir $Skill
    if (Test-Path $Src) {
        if (Test-Path $Dest) {
            Remove-Item $Dest -Recurse -Force -ErrorAction SilentlyContinue
        }
        Copy-Item -Path $Src -Destination $Dest -Recurse -Force
        Write-Host "  ✅ $Skill → $Dest" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  $Skill 소스 없음 — 건너뜀" -ForegroundColor Yellow
    }
}

# pty-bridge (Node.js 있을 때만)
$HaveNode = $null -ne (Get-Command "node" -ErrorAction SilentlyContinue)
if ($HaveNode) {
    $PtySrc  = Join-Path $ProjectRoot "mcp-servers\pty-bridge"
    $PtyDest = Join-Path $env:USERPROFILE ".claude\mcp-servers\pty-bridge"
    if (Test-Path $PtySrc) {
        New-Item -ItemType Directory -Force -Path $PtyDest | Out-Null
        Copy-Item "$PtySrc\*" $PtyDest -Recurse -Force
        Push-Location $PtyDest
        try {
            npm install --silent 2>$null
            Write-Host "  ✅ pty-bridge npm install 완료" -ForegroundColor Green
        } catch {
            Write-Host "  ⚠️  pty-bridge npm install 실패 (agy 없이는 무관)" -ForegroundColor Yellow
        } finally {
            Pop-Location
        }
    }
} else {
    Write-Host "  ⏭️  Node.js 미설치 — pty-bridge 건너뜀 (agy 없이는 무관)" -ForegroundColor Yellow
}

# ── [4/4] 정리 ────────────────────────────────────────────────────────────────

Write-Host "[4/4] 임시 파일 정리..." -ForegroundColor Cyan
Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  ✅ 완료" -ForegroundColor Green

# ── 완료 메시지 ───────────────────────────────────────────────────────────────

Write-Host ""
Write-Host $SEP -ForegroundColor Green
Write-Host "  설치 완료!" -ForegroundColor Green
Write-Host $SEP -ForegroundColor Green
Write-Host ""
Write-Host "설치된 스킬:" -ForegroundColor Cyan
Write-Host "  /git-commit, /git-pr, /git-branch   (git-helper)"
Write-Host "  /code-review-ko                     (code-review-ko)"
Write-Host "  cli-agent-team                      (멀티 에이전트 루프)"
Write-Host ""
Write-Host "다음 단계:" -ForegroundColor Cyan
Write-Host "  1. Claude Code 재시작 (스킬 인식)"
Write-Host "  2. 프로젝트에서 /git-commit 사용 가능"
Write-Host ""
Write-Host "cli-agent-team 초기화 (프로젝트별):" -ForegroundColor Cyan
Write-Host "  cd your-project"
Write-Host "  bash ~/.claude/skills/cli-agent-team/scripts/setup.sh"
Write-Host $SEP -ForegroundColor Green
