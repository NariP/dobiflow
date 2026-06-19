#!/usr/bin/env bash
# dobiflow 이벤트 훅 디스패처
# PostToolUse(Bash)로 호출됨. gh issue/pr create 를 감지하면
# 사용자 정의 훅 스크립트(전역 + 프로젝트)를 실행한다.
#
# 사용자 훅 위치 (있으면 실행, 없으면 무시):
#   전역    : ~/.dobiflow/hooks/on-<event>.sh
#   프로젝트: <cwd>/.claude/dobiflow-hooks/on-<event>.sh
# <event> = issue-created | pr-created
#
# 사용자 훅에 넘기는 정보 (환경변수):
#   DOBIFLOW_EVENT   : issue-created | pr-created
#   DOBIFLOW_URL     : 생성된 이슈/PR 전체 URL
#   DOBIFLOW_COMMAND : 실행된 gh 명령 전문
#   DOBIFLOW_CWD     : 작업 디렉토리
#
# 실패해도 dobiflow 본 작업을 막지 않도록 항상 exit 0.

set -uo pipefail

INPUT="$(cat)"

# jq 없으면 조용히 통과 (훅은 부가기능)
command -v jq >/dev/null 2>&1 || exit 0

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$COMMAND" ] && exit 0

# gh issue create / gh pr create 만 처리
EVENT=""
case "$COMMAND" in
  *"gh issue create"*) EVENT="issue-created" ;;
  *"gh pr create"*)    EVENT="pr-created" ;;
  *) exit 0 ;;
esac

# tool_response.content(=stdout)에서 첫 URL 추출
RESPONSE="$(printf '%s' "$INPUT" | jq -r '.tool_response.content // empty' 2>/dev/null)"
URL="$(printf '%s' "$RESPONSE" | grep -oE 'https://github\.com/[^ ]+' | head -1)"

CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$CWD" ] && CWD="$PWD"

export DOBIFLOW_EVENT="$EVENT"
export DOBIFLOW_URL="$URL"
export DOBIFLOW_COMMAND="$COMMAND"
export DOBIFLOW_CWD="$CWD"

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
run_if_exists "$CWD/.claude/dobiflow-hooks/on-${EVENT}.sh"

exit 0
