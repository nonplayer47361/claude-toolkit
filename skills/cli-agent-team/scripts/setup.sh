#!/bin/sh
# setup.sh — cli-agent-team 에이전트 자동 감지 & 설정 파일 생성
#
# 사용법:
#   bash setup.sh                    # 자동 감지 후 conf 생성
#   bash setup.sh --disable-codex    # codex 감지해도 CODEX_ENABLED=false
#   bash setup.sh --disable-agy      # agy  감지해도 AGY_ENABLED=false
#   bash setup.sh --enable-codex     # 기존 conf에서 codex를 다시 활성화
#   bash setup.sh --enable-agy       # 기존 conf에서 agy를 다시 활성화
#   bash setup.sh --status           # 현재 conf 내용 출력 (변경 없음)

set -euo pipefail

# ── 상수 ──────────────────────────────────────────────────────────────────────
CONF_FILE="_agent_reports/.cli-agent-team.conf"
CONF_BAK="${CONF_FILE}.bak"
SEP="================================================================"

# ── 플래그 파싱 ───────────────────────────────────────────────────────────────
DISABLE_CODEX=false
DISABLE_AGY=false
ENABLE_CODEX=false
ENABLE_AGY=false
STATUS_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --disable-codex) DISABLE_CODEX=true ;;
    --disable-agy)   DISABLE_AGY=true   ;;
    --enable-codex)  ENABLE_CODEX=true  ;;
    --enable-agy)    ENABLE_AGY=true    ;;
    --status)        STATUS_ONLY=true   ;;
    *)
      echo "[setup] 알 수 없는 옵션: $arg" >&2
      echo "사용법: bash setup.sh [--disable-codex] [--disable-agy] [--enable-codex] [--enable-agy] [--status]" >&2
      exit 1
      ;;
  esac
done

# ── --status 모드 ─────────────────────────────────────────────────────────────
if [ "$STATUS_ONLY" = true ]; then
  if [ ! -f "$CONF_FILE" ]; then
    echo "[cli-agent-team] 설정 파일을 찾을 수 없습니다."
    echo "  → setup.sh를 먼저 실행하세요."
    exit 0
  fi
  echo "[cli-agent-team] 현재 설정 ($CONF_FILE):"
  echo "$SEP"
  cat "$CONF_FILE"
  echo "$SEP"
  exit 0
fi

# ── --enable 모드: 기존 conf 수정 ────────────────────────────────────────────
if [ "$ENABLE_CODEX" = true ] || [ "$ENABLE_AGY" = true ]; then
  if [ ! -f "$CONF_FILE" ]; then
    echo "[setup] 오류: 기존 conf 파일이 없습니다. 먼저 'bash setup.sh'를 실행하세요." >&2
    exit 1
  fi
  # 백업
  cp "$CONF_FILE" "$CONF_BAK"
  if [ "$ENABLE_CODEX" = true ]; then
    sed -i.tmp 's/^CODEX_ENABLED=.*/CODEX_ENABLED=true/' "$CONF_FILE"
    rm -f "${CONF_FILE}.tmp"
    echo "[setup] CODEX_ENABLED=true 로 설정했습니다."
  fi
  if [ "$ENABLE_AGY" = true ]; then
    sed -i.tmp 's/^AGY_ENABLED=.*/AGY_ENABLED=true/' "$CONF_FILE"
    rm -f "${CONF_FILE}.tmp"
    echo "[setup] AGY_ENABLED=true 로 설정했습니다."
  fi
  echo "[setup] 백업: $CONF_BAK"
  exit 0
fi

# ── 에이전트 감지 ─────────────────────────────────────────────────────────────
CODEX_BIN=""
AGY_BIN=""

if which codex 2>/dev/null 1>/dev/null; then
  CODEX_BIN=$(which codex 2>/dev/null)
fi
if which agy 2>/dev/null 1>/dev/null; then
  AGY_BIN=$(which agy 2>/dev/null)
fi

# CODEX 활성화 여부 결정
if [ "$DISABLE_CODEX" = true ]; then
  CODEX_ENABLED=false
elif [ -n "$CODEX_BIN" ]; then
  CODEX_ENABLED=true
else
  CODEX_ENABLED=false
fi

# AGY 활성화 여부 결정
if [ "$DISABLE_AGY" = true ]; then
  AGY_ENABLED=false
elif [ -n "$AGY_BIN" ]; then
  AGY_ENABLED=true
else
  AGY_ENABLED=false
fi

# ── conf 파일 생성 ────────────────────────────────────────────────────────────
mkdir -p "_agent_reports"

# 기존 conf 백업
if [ -f "$CONF_FILE" ]; then
  cp "$CONF_FILE" "$CONF_BAK"
fi

SETUP_DATE=$(date +%Y-%m-%d)

cat > "$CONF_FILE" << EOF
# cli-agent-team 에이전트 설정 (setup.sh 자동 생성)
CODEX_ENABLED=${CODEX_ENABLED}          # codex 발견 시 true, 미발견 시 false
CODEX_BIN=${CODEX_BIN}
AGY_ENABLED=${AGY_ENABLED}
AGY_BIN=${AGY_BIN}
CLAUDE_ENABLED=true         # 항상 true (fallback)
SETUP_DATE=${SETUP_DATE}
EOF

# ── 출력 ─────────────────────────────────────────────────────────────────────
echo "[cli-agent-team] setup"
echo "$SEP"
echo "감지 결과:"

# codex 상태
if [ -n "$CODEX_BIN" ]; then
  CODEX_STATUS="ENABLED"
  if [ "$CODEX_ENABLED" = false ]; then
    CODEX_STATUS="DISABLED (--disable-codex 지정)"
  fi
  printf "  codex   v %s   %s\n" "$CODEX_BIN" "$CODEX_STATUS"
else
  printf "  codex   x 미설치 -> DISABLED\n"
fi

# agy 상태
if [ -n "$AGY_BIN" ]; then
  AGY_STATUS="ENABLED"
  if [ "$AGY_ENABLED" = false ]; then
    AGY_STATUS="DISABLED (--disable-agy 지정)"
  fi
  printf "  agy     v %s   %s\n" "$AGY_BIN" "$AGY_STATUS"
else
  printf "  agy     x 미설치 -> DISABLED\n"
fi

printf "  claude  v (항상 활성)\n"

echo ""
echo "설정 파일 저장: $CONF_FILE"
if [ -f "$CONF_BAK" ]; then
  echo "이전 설정 백업: $CONF_BAK"
fi
echo "$SEP"

# 모든 에이전트가 없는 경우 안내
if [ "$CODEX_ENABLED" = false ] && [ "$AGY_ENABLED" = false ]; then
  echo "  ※ codex/agy 미설치 -> Claude-direct 모드로 작동합니다"
  echo ""
fi

echo "완료. 'bash scripts/agent-watch.ps1' 로 모니터를 시작하세요."