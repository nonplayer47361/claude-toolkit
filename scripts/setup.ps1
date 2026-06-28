#Requires -Version 5.1
# setup.ps1 — claude-toolkit 전체 설치 스크립트 (Windows)
#
# 사용법:
#   .\scripts\setup.ps1
#
# 수행 작업:
#   Step 1: 필수 도구 확인 (claude, git, node)
#   Step 2: 스킬 3종 ~/.claude/skills/ 에 복사
#   Step 3: pty-bridge npm install (Node.js 있을 때)
#   Step 4: Memory / Sequential Thinking MCP 선택 설치
#   Step 5: 에이전트 감지 및 .cli-agent-team.conf 생성
#   Step 6: 완료 메시지 출력

$ErrorActionPreference = "Stop"

$SEP = "================================================="

# 스크립트 위치 기반으로 프로젝트 루트 결정
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# ── 헬퍼 함수 ─────────────────────────────────────────────────────────────────

function Test-Command {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Write-Step {
    param([int]$Num, [string]$Title)
    Write-Host ""
    Write-Host "[$Num/6] $Title" -ForegroundColor Cyan
}

# ── Step 1: 필수 도구 확인 ────────────────────────────────────────────────────

Write-Step 1 "필수 도구 확인"

if (-not (Test-Command "git")) {
    Write-Host "  ✅ git: 설치 필요 (계속 진행)" -ForegroundColor Yellow
} else {
    Write-Host "  ✅ git: $(git --version)" -ForegroundColor Green
}

$HaveNode = Test-Command "node"
if (-not $HaveNode) {
    Write-Host "  ⚠️  Node.js 미설치 — agy pty-bridge는 Node.js가 필요합니다." -ForegroundColor Yellow
} else {
    Write-Host "  ✅ node: $(node --version)" -ForegroundColor Green
}

$HaveClaude = Test-Command "claude"
if (-not $HaveClaude) {
    Write-Host "  ⚠️  Claude Code CLI 미설치: https://claude.ai/code" -ForegroundColor Yellow
} else {
    Write-Host "  ✅ claude: $(claude --version 2>$null)" -ForegroundColor Green
}

# ── Step 2: 스킬 설치 ─────────────────────────────────────────────────────────

Write-Step 2 "스킬 3종 설치 → ~/.claude/skills/"

$ClaudeSkillsDir = "$env:USERPROFILE\.claude\skills"
if (-not (Test-Path "$ClaudeSkillsDir")) {
    New-Item -ItemType Directory -Force -Path "$ClaudeSkillsDir" | Out-Null
    Write-Host "  📁 디렉터리 생성: $ClaudeSkillsDir"
}

$Skills = @("git-helper", "code-review-ko", "cli-agent-team")
foreach ($Skill in $Skills) {
    $Src  = Join-Path "$ProjectRoot" "skills\$Skill"
    $Dest = Join-Path "$ClaudeSkillsDir" "$Skill"
    if (-not (Test-Path "$Src")) {
        Write-Host "  ⚠️  스킬 소스 없음: $Src (건너뜀)" -ForegroundColor Yellow
        continue
    }
    Copy-Item -Path "$Src" -Destination "$Dest" -Recurse -Force
    Write-Host "  ✅ $Skill → $Dest" -ForegroundColor Green
}

# ── Step 3: pty-bridge npm install ───────────────────────────────────────────

Write-Step 3 "pty-bridge npm 패키지 설치"

if (-not $HaveNode) {
    Write-Host "  ⏭️  Node.js 미설치 — 건너뜀" -ForegroundColor Yellow
} else {
    $PtyBridgeDir = Join-Path "$ProjectRoot" "mcp-servers\pty-bridge"
    if (-not (Test-Path "$PtyBridgeDir")) {
        Write-Host "  ⚠️  mcp-servers/pty-bridge 디렉터리 없음 — 건너뜀" -ForegroundColor Yellow
    } else {
        Write-Host "  📦 npm install 실행 중..." -ForegroundColor Gray
        Push-Location "$PtyBridgeDir"
        try {
            npm install
            Write-Host "  ✅ pty-bridge npm install 완료" -ForegroundColor Green
        } catch {
            Write-Host "  ⚠️  npm install 실패: $_" -ForegroundColor Yellow
        } finally {
            Pop-Location
        }
    }
}

# ── Step 4: MCP 선택 설치 ────────────────────────────────────────────────────

Write-Step 4 "MCP 서버 선택 설치 (선택사항)"

if (-not $HaveClaude) {
    Write-Host "  ⏭️  claude CLI 미설치 — MCP 설치 단계 건너뜀" -ForegroundColor Yellow
} else {
    $Answer = Read-Host "  Memory MCP 설치하시겠습니까? (knowledge graph, 기억 관리) [y/N]"
    if ($Answer -match "^[Yy]$") {
        Write-Host "  📦 Memory MCP 설치 중..." -ForegroundColor Gray
        claude mcp add memory npx @modelcontextprotocol/server-memory
        Write-Host "  ✅ Memory MCP 설치 완료" -ForegroundColor Green
    } else {
        Write-Host "  ⏭️  Memory MCP 건너뜀"
    }

    $Answer2 = Read-Host "  Sequential Thinking MCP 설치하시겠습니까? (단계별 추론) [y/N]"
    if ($Answer2 -match "^[Yy]$") {
        Write-Host "  📦 Sequential Thinking MCP 설치 중..." -ForegroundColor Gray
        claude mcp add sequentialthinking npx @modelcontextprotocol/server-sequential-thinking
        Write-Host "  ✅ Sequential Thinking MCP 설치 완료" -ForegroundColor Green
    } else {
        Write-Host "  ⏭️  Sequential Thinking MCP 건너뜀"
    }
}

# ── Step 5: 에이전트 감지 및 .conf 생성 ─────────────────────────────────────

Write-Step 5 "에이전트 감지 및 설정 파일 생성"

$AgentReportsDir = Join-Path "$ProjectRoot" "_agent_reports"
if (-not (Test-Path "$AgentReportsDir")) {
    Write-Host "  ⏭️  _agent_reports/ 없음 — 에이전트 설정 건너뜀" -ForegroundColor Yellow
    Write-Host "  (프로젝트 디렉터리에서 실행 시 setup.sh --detect-agents 로 설정 가능)"
} else {
    $ConfFile = Join-Path "$AgentReportsDir" ".cli-agent-team.conf"

    $CodexBin = $(if ($c = Get-Command "codex" -ErrorAction SilentlyContinue) { $c.Source } else { "" })
    $AgyBin   = $(if ($c = Get-Command "agy" -ErrorAction SilentlyContinue) { $c.Source } else { "" })

    $CodexEnabled = if ($CodexBin) { "true" } else { "false" }
    $AgyEnabled   = if ($AgyBin)   { "true" } else { "false" }
    $SetupDate    = (Get-Date -Format "yyyy-MM-dd")

    $ConfContent = @"
# cli-agent-team 에이전트 설정 (setup.ps1 자동 생성)
CODEX_ENABLED=$CodexEnabled
CODEX_BIN=$CodexBin
AGY_ENABLED=$AgyEnabled
AGY_BIN=$AgyBin
CLAUDE_ENABLED=true
SETUP_DATE=$SetupDate
"@
    # 기존 파일 백업
    if (Test-Path "$ConfFile") {
        Copy-Item -Path "$ConfFile" -Destination "$ConfFile.bak" -Force
        Write-Host "  📋 기존 conf 백업: $ConfFile.bak"
    }

    [System.IO.File]::WriteAllText("$ConfFile", $ConfContent, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  ✅ 설정 파일 생성: $ConfFile" -ForegroundColor Green

    if ($CodexBin)  { Write-Host "  🤖 codex  ✅ $CodexBin (ENABLED)" -ForegroundColor Green }
    else            { Write-Host "  🤖 codex  ❌ 미설치 → DISABLED" -ForegroundColor Yellow }
    if ($AgyBin)    { Write-Host "  🤖 agy    ✅ $AgyBin (ENABLED)" -ForegroundColor Green }
    else            { Write-Host "  🤖 agy    ❌ 미설치 → DISABLED" -ForegroundColor Yellow }
    Write-Host "  🤖 claude ✅ (항상 활성)"
}

# ── Step 6: 완료 메시지 ───────────────────────────────────────────────────────

Write-Host ""
Write-Host $SEP -ForegroundColor Green
Write-Host "claude-toolkit 설치 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "설치된 스킬:" -ForegroundColor Cyan
Write-Host "  ✅ git-helper      → /git-commit, /git-pr, /git-branch"
Write-Host "  ✅ code-review-ko  → /code-review-ko"
Write-Host "  ✅ cli-agent-team  → 멀티 에이전트 팀워크"
Write-Host ""
Write-Host "다음 단계:" -ForegroundColor Cyan
Write-Host "  1. Claude Code 재시작 (스킬 인식)"
Write-Host "  2. 프로젝트에서 /git-commit 또는 /code-review-ko 사용"
Write-Host ""
Write-Host "cli-agent-team 프로젝트 설정:"
Write-Host "  cd your-project"
Write-Host "  bash ~/.claude/skills/cli-agent-team/scripts/setup.sh"
Write-Host $SEP -ForegroundColor Green