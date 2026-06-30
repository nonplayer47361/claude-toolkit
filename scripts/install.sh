#!/usr/bin/env bash
# install.sh — claude-toolkit 원라이너 설치 스크립트 (macOS/Linux)
#
# 사용법 (git clone 불필요):
#   curl -fsSL https://raw.githubusercontent.com/nonplayer47361/claude-toolkit/main/scripts/install.sh | bash
#
# 수행 작업:
#   1. GitHub에서 최신 소스 ZIP 다운로드
#   2. 스킬 3종 ~/.claude/skills/ 에 설치
#   3. pty-bridge npm install (Node.js 있을 때)

set -euo pipefail

REPO="nonplayer47361/claude-toolkit"
BRANCH="main"
ZIP_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.zip"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
SEP="================================================="

echo ""
echo "$SEP"
echo "  claude-toolkit 원라이너 설치"
echo "$SEP"
echo ""

# ── [1/3] 다운로드 ────────────────────────────────────────────────────────────

echo "[1/3] GitHub에서 다운로드 중..."

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$ZIP_URL" -o "$TMP_DIR/claude-toolkit.zip"
elif command -v wget >/dev/null 2>&1; then
    wget -q "$ZIP_URL" -O "$TMP_DIR/claude-toolkit.zip"
else
    echo "  ❌ curl 또는 wget이 필요합니다." >&2
    exit 1
fi
echo "  ✅ 다운로드 완료"

# ── [2/3] 압축 해제 ───────────────────────────────────────────────────────────

echo "[2/3] 압축 해제 중..."

if ! command -v unzip >/dev/null 2>&1; then
    echo "  ❌ unzip이 필요합니다. (brew install unzip / apt install unzip)" >&2
    exit 1
fi

unzip -q "$TMP_DIR/claude-toolkit.zip" -d "$TMP_DIR"
PROJECT_ROOT=$(find "$TMP_DIR" -maxdepth 1 -type d -name "claude-toolkit-*" | head -1)

if [ -z "$PROJECT_ROOT" ]; then
    echo "  ❌ 추출된 디렉터리를 찾을 수 없음" >&2
    exit 1
fi
echo "  ✅ 압축 해제 완료"

# ── [3/3] 스킬 설치 ───────────────────────────────────────────────────────────

echo "[3/3] 스킬 설치 중..."

mkdir -p "$CLAUDE_SKILLS_DIR"

for skill in git-helper code-review-ko cli-agent-team; do
    src="$PROJECT_ROOT/skills/$skill"
    dest="$CLAUDE_SKILLS_DIR/$skill"
    if [ -d "$src" ]; then
        rm -rf "$dest"
        cp -R "$src" "$dest"
        echo "  ✅ $skill → $dest"
    else
        echo "  ⚠️  $skill 소스 없음 — 건너뜀"
    fi
done

# pty-bridge (Node.js 있을 때만)
PTY_SRC="$PROJECT_ROOT/mcp-servers/pty-bridge"
PTY_DEST="$HOME/.claude/mcp-servers/pty-bridge"
if [ -d "$PTY_SRC" ] && command -v node >/dev/null 2>&1; then
    mkdir -p "$PTY_DEST"
    cp -R "$PTY_SRC"/. "$PTY_DEST/"
    if (cd "$PTY_DEST" && npm install --silent 2>/dev/null); then
        echo "  ✅ pty-bridge npm install 완료"
    else
        echo "  ⚠️  pty-bridge npm install 실패 (agy 없이는 무관)"
    fi
else
    echo "  ⏭️  Node.js 미설치 또는 pty-bridge 없음 — 건너뜀"
fi

# ── 완료 메시지 ───────────────────────────────────────────────────────────────

echo ""
echo "$SEP"
echo "  설치 완료!"
echo "$SEP"
echo ""
echo "설치된 스킬:"
echo "  /git-commit, /git-pr, /git-branch   (git-helper)"
echo "  /code-review-ko                     (code-review-ko)"
echo "  cli-agent-team                      (멀티 에이전트 루프)"
echo ""
echo "다음 단계:"
echo "  1. Claude Code 재시작 (스킬 인식)"
echo "  2. 프로젝트에서 /git-commit 사용 가능"
echo ""
echo "cli-agent-team 초기화 (프로젝트별):"
echo "  cd your-project"
echo "  bash ~/.claude/skills/cli-agent-team/scripts/setup.sh"
echo "$SEP"
