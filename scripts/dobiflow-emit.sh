#!/usr/bin/env bash
# dobiflow 이벤트 발행기 — 스킬이 작업 생명주기 시점마다 직접 호출한다.
# (PostToolUse 자동 감지 훅(dobiflow-hook.sh)과 짝 — 이쪽은 스킬 주도 발행)
#
# 사용법: dobiflow-emit <event> [key=value ...]
#   <event>   = work-started | iteration-completed | work-finished | work-stopped (자유 확장 가능)
#   key=value = DOBIFLOW_<KEY>(대문자, `-`는 `_`로) 환경변수로 사용자 훅에 전달
#
# 사용자 훅 위치 (있으면 실행, 없으면 무시) — dobiflow-hook.sh와 동일:
#   전역    : ~/.dobiflow/hooks/on-<event>.sh
#   프로젝트: <cwd>/.claude/dobiflow-hooks/on-<event>.sh
#
# 항상 전달되는 환경변수: DOBIFLOW_EVENT, DOBIFLOW_CWD
# 실패해도 dobiflow 본 작업을 막지 않도록 항상 exit 0.

set -uo pipefail

EVENT="${1:-}"
[ -z "$EVENT" ] && exit 0
shift || true

export DOBIFLOW_EVENT="$EVENT"
export DOBIFLOW_CWD="$PWD"

for kv in "$@"; do
  case "$kv" in
    *=*)
      key="${kv%%=*}"
      val="${kv#*=}"
      key="$(printf '%s' "$key" | tr '[:lower:]-' '[:upper:]_' | tr -cd 'A-Z0-9_')"
      [ -n "$key" ] && export "DOBIFLOW_${key}=${val}"
      ;;
  esac
done

run_if_exists() {
  local script="$1"
  if [ -f "$script" ] && [ -x "$script" ]; then
    "$script" || true   # 사용자 훅 실패가 본 작업을 막지 않게
  elif [ -f "$script" ]; then
    bash "$script" || true   # 실행권한 없어도 bash로
  fi
}

# 전역 → 프로젝트 순으로 실행 (둘 다 있으면 둘 다)
run_if_exists "$HOME/.dobiflow/hooks/on-${EVENT}.sh"
run_if_exists "$PWD/.claude/dobiflow-hooks/on-${EVENT}.sh"

exit 0
