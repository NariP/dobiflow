#!/usr/bin/env bash
# dobiflow 업데이트 확인 (SessionStart 훅)
# 하루 1회 원격 최신 태그와 로컬 플러그인 버전을 비교해 신버전 안내를 stdout으로 낸다.
# 모든 실패(네트워크·파싱)는 조용히 통과, stderr 금지, 항상 exit 0 — 세션 시작을 막지 않는다.
# macOS(bash 3.2)·Linux 호환 — timeout 명령 대신 git http.lowSpeed·curl --max-time으로 가드.
#
# 테스트용 오버라이드 (일반 사용 시 불필요):
#   DOBIFLOW_UPDATE_CHECK_LOCAL_VERSION  로컬 버전 강제
#   DOBIFLOW_UPDATE_CHECK_REMOTE         원격 레포 URL 교체
#   DOBIFLOW_UPDATE_CHECK_CACHE_FILE     캐시 파일 경로 교체

set -u
exec 2>/dev/null

REMOTE="${DOBIFLOW_UPDATE_CHECK_REMOTE:-https://github.com/NariP/dobiflow.git}"
CACHE="${DOBIFLOW_UPDATE_CHECK_CACHE_FILE:-$HOME/.dobiflow/update-check}"
TTL=86400
CHANGELOG_URL="https://github.com/NariP/dobiflow/blob/main/CHANGELOG.md"
CHANGELOG_RAW="https://raw.githubusercontent.com/NariP/dobiflow/main/CHANGELOG.md"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -n "$PLUGIN_ROOT" ] || exit 0

if [ -n "${DOBIFLOW_UPDATE_CHECK_LOCAL_VERSION:-}" ]; then
  LOCAL="$DOBIFLOW_UPDATE_CHECK_LOCAL_VERSION"
else
  LOCAL=""
  for manifest in "$PLUGIN_ROOT/.claude-plugin/plugin.json" "$PLUGIN_ROOT/.codex-plugin/plugin.json"; do
    LOCAL="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([0-9][^"]*\)".*/\1/p' \
      "$manifest" | head -1)"
    [ -n "$LOCAL" ] && break
  done
fi
[ -n "$LOCAL" ] || exit 0

# $1 < $2 (semver x.y.z 숫자 비교 — sort -V는 macOS BSD sort에 없음)
version_lt() {
  [ "$1" = "$2" ] && return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$1" ]
}

notify() {
  printf '[dobiflow 업데이트 있음] v%s → v%s — Claude: /plugin 마켓플레이스에서 dobiflow 업데이트 / Codex: 클론 git pull(에이전트 변경 시 install.sh --codex-only). 변경 내역: %s\n' \
    "$LOCAL" "$1" "$CHANGELOG_URL"
}

now="$(date +%s)" || exit 0

# 캐시: <epoch> <원격버전> — TTL 내면 재조회 없이 마지막 결과만 재출력
if [ -f "$CACHE" ]; then
  IFS=' ' read -r last cached < "$CACHE" || true
  case "${last:-}" in ''|*[!0-9]*) last=0 ;; esac
  if [ $((now - last)) -lt "$TTL" ]; then
    case "${cached:-}" in
      *[!0-9.]*) ;; # 캐시 손상 — 아래 재조회로
      *)
        if [ -n "${cached:-}" ] && version_lt "$LOCAL" "$cached"; then
          notify "$cached"
        fi
        exit 0 ;;
    esac
  fi
fi

tags="$(GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=3 \
  ls-remote --tags "$REMOTE" 'v*')" || tags=""
latest="$(printf '%s\n' "$tags" | sed -n 's|.*refs/tags/v\([0-9][0-9.]*\)$|\1|p' \
  | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"

mkdir -p "$(dirname "$CACHE")" || exit 0
printf '%s %s\n' "$now" "$latest" > "$CACHE"

[ -n "$latest" ] || exit 0
if version_lt "$LOCAL" "$latest"; then
  notify "$latest"
  headline="$(curl -fsS --max-time 3 "$CHANGELOG_RAW" | awk '
    /^## \[Unreleased\]/ { next }
    /^## \[/ { if (t != "") exit; t = substr($0, 4); next }
    t != "" && /^- / { i = substr($0, 3); exit }
    END { if (t != "" && i != "") print t " — " i }')"
  [ -n "$headline" ] && printf '새 소식: %s\n' "$headline"
fi
exit 0
