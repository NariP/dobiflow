#!/usr/bin/env bash
# dobiflow — Claude Code + Codex CLI 전역 설치 스크립트
# 클론 후 `./install.sh` 한 번이면 설치된 CLI(claude/codex)를 자동 감지해 각 홈에 설치한다.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"   # Codex 신규 canonical 스킬 경로

DO_CLAUDE=auto
DO_CODEX=auto
DRY=no

usage() {
  cat <<EOF
dobiflow 설치 스크립트

사용법: ./install.sh [옵션]
  (옵션 없음)      설치된 CLI(claude/codex) 자동 감지해 둘 다 설치
  --claude-only    Claude Code만
  --codex-only     Codex CLI만
  --dry-run        실제 복사 없이 무엇을 할지 출력만
  -h, --help       도움말

설치 위치:
  Claude: $CLAUDE_HOME/skills/{work,triage-fix,task-run,triage-status,triage-init,triage-help}
          $CLAUDE_HOME/agents/{issue-triage,policy-checker,code-reviewer}.md
  Codex : $AGENTS_HOME/skills/<name>  +  $CODEX_HOME/skills/<name>  (양쪽 — 버전 호환)
          $CODEX_HOME/agents/<name>.toml

환경변수: CLAUDE_HOME(기본 ~/.claude), CODEX_HOME(기본 ~/.codex), AGENTS_HOME(기본 ~/.agents)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --claude-only) DO_CLAUDE=yes; DO_CODEX=no ;;
    --codex-only)  DO_CLAUDE=no; DO_CODEX=yes ;;
    --dry-run)     DRY=yes ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "알 수 없는 옵션: $1"; usage; exit 1 ;;
  esac
  shift
done

run() {
  if [ "$DRY" = yes ]; then echo "  [dry] $*"; else "$@"; fi
}

SKILLS="work triage-fix task-run triage-status triage-init triage-help"
AGENTS_MD="issue-triage policy-checker code-reviewer"

# ---- Claude Code ----
if [ "$DO_CLAUDE" != no ] && { [ "$DO_CLAUDE" = yes ] || command -v claude >/dev/null 2>&1; }; then
  echo "== Claude Code =="
  run mkdir -p "$CLAUDE_HOME/skills" "$CLAUDE_HOME/agents"
  for s in $SKILLS; do
    run rm -rf "$CLAUDE_HOME/skills/$s"
    run cp -R "$REPO/skills/$s" "$CLAUDE_HOME/skills/$s"
  done
  for a in $AGENTS_MD; do
    run cp "$REPO/agents/$a.md" "$CLAUDE_HOME/agents/$a.md"
  done
  echo "  → Claude 스킬 6개 + 에이전트 3개 설치"
else
  echo "== Claude Code 건너뜀 (미설치 또는 --codex-only) =="
fi

# ---- Codex CLI ----
if [ "$DO_CODEX" != no ] && { [ "$DO_CODEX" = yes ] || command -v codex >/dev/null 2>&1; }; then
  echo "== Codex CLI =="
  # 스킬: 신규(~/.agents/skills) + 레거시(~/.codex/skills) 양쪽 (버전 호환)
  run mkdir -p "$AGENTS_HOME/skills" "$CODEX_HOME/skills" "$CODEX_HOME/agents"
  for s in $SKILLS; do
    run rm -rf "$AGENTS_HOME/skills/$s" "$CODEX_HOME/skills/$s"
    run cp -R "$REPO/codex/skills/$s" "$AGENTS_HOME/skills/$s"
    run cp -R "$REPO/codex/skills/$s" "$CODEX_HOME/skills/$s"
  done
  for a in $AGENTS_MD; do
    run cp "$REPO/codex/agents/$a.toml" "$CODEX_HOME/agents/$a.toml"
  done
  echo "  → Codex 스킬 6개(신규+레거시 경로) + 에이전트 3개(toml) 설치"
  echo "  ℹ️  Serena LSP 쓰려면 $CODEX_HOME/config.toml 에 [mcp_servers.serena] 등록 필요"
else
  echo "== Codex CLI 건너뜀 (미설치 또는 --claude-only) =="
fi

echo ""
echo "✅ 설치 완료. 새 세션에서 /triage-init → /work 로 사용."
