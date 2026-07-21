#!/usr/bin/env bash
# dobiflow — Claude Code + Codex CLI 전역 설치 스크립트
# 클론 후 `./install.sh` 한 번이면 설치된 CLI(claude/codex)를 자동 감지해 각 홈에 설치한다.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"   # Codex 신규 canonical 스킬 경로
DOBIFLOW_HOME="${DOBIFLOW_HOME:-$HOME/.dobiflow}"   # 이벤트 발행기 + 사용자 훅 홈

DO_CLAUDE=auto
DO_CODEX=auto
DRY=no
LINK=no

usage() {
  cat <<EOF
dobiflow 설치 스크립트

사용법: ./install.sh [옵션]
  (옵션 없음)      설치된 CLI(claude/codex) 자동 감지해 둘 다 설치
  --claude-only    Claude Code만
  --codex-only     Codex CLI만
  --link           복사 대신 심링크로 설치 — 이후 클론에서 git pull/수정만 하면 즉시 반영.
                   클론을 지우면 설치가 깨지니, 클론을 계속 둘 머신에서만 사용
  --dry-run        실제 복사 없이 무엇을 할지 출력만
  -h, --help       도움말

설치 위치:
  Claude: $CLAUDE_HOME/skills/{work,triage-fix,task-run,triage-status,triage-init,triage-help}
          $CLAUDE_HOME/agents/{issue-triage,policy-checker,code-reviewer,implementer,git-writer}.md
  Codex : 스킬은 플러그인으로 설치(자동 시도) — codex plugin marketplace add <클론> + codex plugin add
          $CODEX_HOME/agents/<name>.toml  (서브에이전트는 플러그인 미지원이라 여기서 복사)
  공용  : $DOBIFLOW_HOME/bin/dobiflow-emit  (작업 생명주기 이벤트 발행기)

환경변수: CLAUDE_HOME(기본 ~/.claude), CODEX_HOME(기본 ~/.codex), AGENTS_HOME(기본 ~/.agents),
          DOBIFLOW_HOME(기본 ~/.dobiflow)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --claude-only) DO_CLAUDE=yes; DO_CODEX=no ;;
    --codex-only)  DO_CLAUDE=no; DO_CODEX=yes ;;
    --link)        LINK=yes ;;
    --dry-run)     DRY=yes ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "알 수 없는 옵션: $1"; usage; exit 1 ;;
  esac
  shift
done

run() {
  if [ "$DRY" = yes ]; then echo "  [dry] $*"; else "$@"; fi
}

# put_dir/put_file: LINK=yes면 심링크, 아니면 복사. 기존 설치물(디렉토리/파일/링크)은 먼저 제거.
put_dir() {  # <원본 디렉토리> <설치 경로>
  run rm -rf "$2"
  if [ "$LINK" = yes ]; then run ln -s "$1" "$2"; else run cp -R "$1" "$2"; fi
}
put_file() {  # <원본 파일> <설치 경로>
  if [ "$LINK" = yes ]; then run ln -sfn "$1" "$2"; else run rm -f "$2" && run cp "$1" "$2"; fi
}

SKILLS="work milestone triage-fix task-run triage-status triage-init triage-help"
AGENTS_MD="issue-triage planner qa policy-checker code-reviewer implementer git-writer"
MODE_LABEL=$([ "$LINK" = yes ] && echo "심링크" || echo "복사")

# ---- 공용: 이벤트 발행기 (CLI 무관 — 스킬들이 ~/.dobiflow/bin/dobiflow-emit 으로 호출) ----
echo "== 공용 =="
run mkdir -p "$DOBIFLOW_HOME/bin"
put_file "$REPO/scripts/dobiflow-emit.sh" "$DOBIFLOW_HOME/bin/dobiflow-emit"
[ "$LINK" = yes ] || run chmod +x "$DOBIFLOW_HOME/bin/dobiflow-emit"
echo "  → 이벤트 발행기 설치: $DOBIFLOW_HOME/bin/dobiflow-emit ($MODE_LABEL)"

# ---- Claude Code ----
if [ "$DO_CLAUDE" != no ] && { [ "$DO_CLAUDE" = yes ] || command -v claude >/dev/null 2>&1; }; then
  echo "== Claude Code =="
  run mkdir -p "$CLAUDE_HOME/skills" "$CLAUDE_HOME/agents" "$CLAUDE_HOME/docs"
  for s in $SKILLS; do
    put_dir "$REPO/skills/$s" "$CLAUDE_HOME/skills/$s"
  done
  for a in $AGENTS_MD; do
    put_file "$REPO/agents/$a.md" "$CLAUDE_HOME/agents/$a.md"
  done
  # 스킬이 ${CLAUDE_PLUGIN_ROOT}/docs/*.md 로 참조하는 공용 문서 (dobi-persona 등)
  for d in "$REPO"/docs/*.md; do
    [ -e "$d" ] && put_file "$d" "$CLAUDE_HOME/docs/$(basename "$d")"
  done
  echo "  → Claude 스킬 7개 + 에이전트 7개 + 공용 문서 설치 ($MODE_LABEL)"
else
  echo "== Claude Code 건너뜀 (미설치 또는 --codex-only) =="
fi

# ---- Codex CLI ----
if [ "$DO_CODEX" != no ] && { [ "$DO_CODEX" = yes ] || command -v codex >/dev/null 2>&1; }; then
  echo "== Codex CLI =="
  # 서브에이전트(toml)만 복사 — Codex 플러그인 매니페스트가 agents를 지원하지 않는다
  # (skills·mcpServers·apps·hooks만 지원, 에이전트는 config 레이어 $CODEX_HOME/agents/ 전용).
  run mkdir -p "$CODEX_HOME/agents"
  for a in $AGENTS_MD; do
    put_file "$REPO/codex/agents/$a.toml" "$CODEX_HOME/agents/$a.toml"
  done
  echo "  → Codex 에이전트 7개(toml) 설치 ($MODE_LABEL)"

  # 구버전(≤0.13)이 홈에 복사해 둔 스킬 제거 — 플러그인 스킬과 중복 방지
  for s in $SKILLS; do
    if [ -e "$AGENTS_HOME/skills/$s" ] || [ -e "$CODEX_HOME/skills/$s" ]; then
      run rm -rf "$AGENTS_HOME/skills/$s" "$CODEX_HOME/skills/$s"
      echo "  → 구버전 홈 스킬 복사본 제거: $s"
    fi
  done

  # 스킬은 플러그인으로 (0.14.0+, dobiflow: 네임스페이스로 노출)
  if command -v codex >/dev/null 2>&1 && codex plugin --help >/dev/null 2>&1; then
    if codex plugin list 2>/dev/null | grep -q "dobiflow@dobiflow"; then
      echo "  → Codex 플러그인 이미 설치됨 (dobiflow@dobiflow)"
      echo "     갱신: .codex-plugin/plugin.json 버전을 올리면 다음 세션에서 자동 반영."
      echo "     버전 그대로 강제 갱신: codex plugin remove dobiflow@dobiflow && codex plugin add dobiflow@dobiflow"
    else
      run codex plugin marketplace add "$REPO"
      run codex plugin add dobiflow@dobiflow
      echo "  → Codex 플러그인 설치 (스킬 7개, dobiflow: 네임스페이스)"
    fi
  else
    echo "  ⚠️  codex plugin 미지원 버전 — Codex CLI 업데이트 후 다음을 실행:"
    echo "      codex plugin marketplace add \"$REPO\" && codex plugin add dobiflow@dobiflow"
  fi
  echo "  ℹ️  Serena LSP 쓰려면 $CODEX_HOME/config.toml 에 [mcp_servers.serena] 등록 필요"
else
  echo "== Codex CLI 건너뜀 (미설치 또는 --claude-only) =="
fi

echo ""
echo "✅ 설치 완료. 새 세션에서 /triage-init → /work 로 사용."
if [ "$LINK" = yes ]; then
  echo "🔗 심링크 모드 — 이 클론($REPO)을 지우면 설치가 깨진다. 업데이트는 git pull(또는 파일 수정)만으로 반영."
fi
