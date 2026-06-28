#!/usr/bin/env bash
# setup.sh — claude-toolkit 전체 설치 스크립트 (Linux/macOS)
#
# 사용법:
#   bash scripts/setup.sh
#
# 수행 작업:
#   Step 1: 필수 도구 확인 (claude, git, node)
#   Step 2: 스킬 3종 $HOME/.claude/skills/ 에 복사
#   Step 3: pty-bridge npm install (Node.js 있을 때)
#   Step 4: Memory / Sequential Thinking MCP 선택 설치
#   Step 5: 에이전트 감지 및 .cli-agent-team.conf 생성
#   Step 6: 완료 메시지 출력

set -uo pipefail

SEP="================================================="

# 스크립트 위치 기반으로 프로젝트 루트 결정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── 헬퍼 함수 ─────────────────────────────────────────────────────────────────

check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

print_step() {
    echo ""
    echo "[$1/6] $2"
}

# ── Step 1: 필수 도구 확인 ────────────────────────────────────────────────────

print_step 1 "필수 도구 확인"

if check_cmd git; then
    echo "  ✅ git: $(git --version)"
else
    echo "  ⚠️  git: 미설치 (계속 진행)"
fi

HAVE_NODE=false
if check_cmd node; then
    HAVE_NODE=true
    echo "  ✅ node: $(node --version)"
else
    echo "  ⚠️  Node.js 미설치 — agy pty-bridge는 Node.js가 필요합니다."
fi

HAVE_CLAUDE=false
if check_cmd claude; then
    HAVE_CLAUDE=true
    echo "  ✅ claude: $(claude --version 2>/dev/null || echo '버전 확인 불가')"
else
    echo "  ⚠️  Claude Code CLI 미설치: https://claude.ai/code"
fi

# ── Step 2: 스킬 설치 ─────────────────────────────────────────────────────────

print_step 2 "스킬 3종 설치 → \$HOME/.claude/skills/"

CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
mkdir -p "$CLAUDE_SKILLS_DIR"

SKILLS=("git-helper" "code-review-ko" "cli-agent-team")
for SKILL in "${SKILLS[@]}"; do
    SRC="$PROJECT_ROOT/skills/$SKILL"
    DEST="$CLAUDE_SKILLS_DIR/$SKILL"
    if [ ! -d "$SRC" ]; then
        echo "  ⚠️  스킬 소스 없음: $SRC (건너뜀)"
        continue
    fi
    cp -R "$SRC" "$DEST"
    echo "  ✅ $SKILL → $DEST"
done

# ── Step 3: pty-bridge npm install ───────────────────────────────────────────

print_step 3 "pty-bridge npm 패키지 설치"

if [ "$HAVE_NODE" = false ]; then
    echo "  ⏭️  Node.js 미설치 — 건너뜀"
else
    PTY_BRIDGE_DIR="$PROJECT_ROOT/mcp-servers/pty-bridge"
    if [ ! -d "$PTY_BRIDGE_DIR" ]; then
        echo "  ⚠️  mcp-servers/pty-bridge 디렉터리 없음 — 건너뜀"
    else
        echo "  📦 npm install 실행 중..."
        cd "$PTY_BRIDGE_DIR"
        npm install
        cd "$PROJECT_ROOT"
        echo "  ✅ pty-bridge npm install 완료"
    fi
fi

# ── Step 4: MCP 선택 설치 ────────────────────────────────────────────────────

print_step 4 "MCP 서버 선택 설치 (선택사항)"

if [ "$HAVE_CLAUDE" = false ]; then
    echo "  ⏭️  claude CLI 미설치 — MCP 설치 단계 건너뜀"
else
    read -r -p "  Memory MCP 설치하시겠습니까? (knowledge graph, 기억 관리) [y/N]: " ANSWER
    case "$ANSWER" in
        [Yy])
            echo "  📦 Memory MCP 설치 중..."
            claude mcp add memory npx @modelcontextprotocol/server-memory
            echo "  ✅ Memory MCP 설치 완료"
            ;;
        *)
            echo "  ⏭️  Memory MCP 건너뜀"
            ;;
    esac

    read -r -p "  Sequential Thinking MCP 설치하시겠습니까? (단계별 추론) [y/N]: " ANSWER2
    case "$ANSWER2" in
        [Yy])
            echo "  📦 Sequential Thinking MCP 설치 중..."
            claude mcp add sequentialthinking npx @modelcontextprotocol/server-sequential-thinking
            echo "  ✅ Sequential Thinking MCP 설치 완료"
            ;;
        *)
            echo "  ⏭️  Sequential Thinking MCP 건너뜀"
            ;;
    esac
fi

# ── Step 5: 에이전트 감지 및 .conf 생성 ─────────────────────────────────────

print_step 5 "에이전트 감지 및 설정 파일 생성"

AGENT_REPORTS_DIR="$PROJECT_ROOT/_agent_reports"
if [ ! -d "$AGENT_REPORTS_DIR" ]; then
    echo "  ⏭️  _agent_reports/ 없음 — 에이전트 설정 건너뜀"
    echo "  (프로젝트 디렉터리에서 실행 시 setup.sh --detect-agents 로 설정 가능)"
else
    CONF_FILE="$AGENT_REPORTS_DIR/.cli-agent-team.conf"
    CONF_BAK="${CONF_FILE}.bak"

    CODEX_BIN=""
    AGY_BIN=""
    if check_cmd codex; then
        CODEX_BIN="$(command -v codex)"
    fi
    if check_cmd agy; then
        AGY_BIN="$(command -v agy)"
    fi

    CODEX_ENABLED="false"
    AGY_ENABLED="false"
    [ -n "$CODEX_BIN" ] && CODEX_ENABLED="true"
    [ -n "$AGY_BIN"   ] && AGY_ENABLED="true"

    SETUP_DATE="$(date +%Y-%m-%d)"

    # 기존 파일 백업
    if [ -f "$CONF_FILE" ]; then
        cp "$CONF_FILE" "$CONF_BAK"
        echo "  📋 기존 conf 백업: $CONF_BAK"
    fi

    cat > "$CONF_FILE" <<EOF
# cli-agent-team 에이전트 설정 (setup.sh 자동 생성)
CODEX_ENABLED=${CODEX_ENABLED}
CODEX_BIN=${CODEX_BIN}
AGY_ENABLED=${AGY_ENABLED}
AGY_BIN=${AGY_BIN}
CLAUDE_ENABLED=true
SETUP_DATE=${SETUP_DATE}
EOF

    echo "  ✅ 설정 파일 생성: $CONF_FILE"

    if [ -n "$CODEX_BIN" ]; then
        echo "  🤖 codex  ✅ $CODEX_BIN (ENABLED)"
    else
        echo "  🤖 codex  ❌ 미설치 → DISABLED"
    fi
    if [ -n "$AGY_BIN" ]; then
        echo "  🤖 agy    ✅ $AGY_BIN (ENABLED)"
    else
        echo "  🤖 agy    ❌ 미설치 → DISABLED"
    fi
    echo "  🤖 claude ✅ (항상 활성)"
fi

# ── Step 6: 완료 메시지 ───────────────────────────────────────────────────────

echo ""
echo "$SEP"
echo "claude-toolkit 설치 완료!"
echo ""
echo "설치된 스킬:"
echo "  ✅ git-helper      → /git-commit, /git-pr, /git-branch"
echo "  ✅ code-review-ko  → /code-review-ko"
echo "  ✅ cli-agent-team  → 멀티 에이전트 팀워크"
echo ""
echo "다음 단계:"
echo "  1. Claude Code 재시작 (스킬 인식)"
echo "  2. 프로젝트에서 /git-commit 또는 /code-review-ko 사용"
echo ""
echo "cli-agent-team 프로젝트 설정:"
echo "  cd your-project"
echo "  bash $HOME/.claude/skills/cli-agent-team/scripts/setup.sh"
echo "$SEP"