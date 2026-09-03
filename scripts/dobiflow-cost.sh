#!/usr/bin/env bash
# dobiflow cost & time report — printed on request at the post-merge cleanup step.
# Reads the agent session transcript (JSONL) and aggregates tokens, cost and active
# working time.
#
# Two transcript formats are supported and told apart by sniffing the file content,
# never by its path — both are `.jsonl` and `--transcript` may point anywhere:
#   * Claude Code — usage on `type:"assistant"` lines, broken down per subagent, priced.
#   * Codex       — cumulative `token_count` events, one total row, no price (the rates
#                   are not published; Codex itself reports them as uncertain).
#
# Usage: dobiflow-cost [options]
#   --transcript <path>   transcript JSONL path (skips session/cwd resolution)
#   --session <id>        session id; resolved under ~/.claude/projects/<cwd-slug>/<id>.jsonl,
#                         or as a Codex rollout file whose name ends with that id
#   --since <ISO8601>     ignore lines before this timestamp (scope = this task, not the session)
#   --verbose             expand the table with input / cache write / cache read / output
#   --lang <ko|en>        output language (default: en)
#
# Add-on principle: unknown model, missing transcript, or broken JSON must never block
# the cleanup work — print nothing and always exit 0. No stderr.

set -u
exec 2>/dev/null

TRANSCRIPT=""
SESSION=""
SINCE=""
VERBOSE=0
LANG_OUT="en"

while [ $# -gt 0 ]; do
  case "$1" in
    --transcript) TRANSCRIPT="${2:-}"; shift 2 || exit 0 ;;
    --session)    SESSION="${2:-}"; shift 2 || exit 0 ;;
    --since)      SINCE="${2:-}"; shift 2 || exit 0 ;;
    --lang)       LANG_OUT="${2:-en}"; shift 2 || exit 0 ;;
    --verbose)    VERBOSE=1; shift ;;
    *)            shift ;;   # unknown option — ignore rather than fail
  esac
done

# True when a rollout was written by a `codex exec` spawn rather than a real user session.
#
# `codex exec` leaves its own rollout in the same tree, tagged
# `session_meta.originator == "codex_exec"` (a real session reads "Codex Desktop"). Those
# spawns are short and cheap — one measured at 20,985 tokens beside real sessions of 57M —
# so picking one by mtime alone would report a rounding error as "the session". dobiflow
# itself shells out to `codex exec`, so this is the common case, not an edge case.
#
# The marker sits on `session_meta`, which Codex writes first, so the head of the file is
# enough. Anything unreadable or unrecognised counts as NOT a spawn: skipping a real
# session by mistake means silence, which is the worse failure.
codex_is_exec_spawn() {
  head -5 "$1" 2>/dev/null | grep -q '"originator" *: *"codex_exec"'
}

# Newest Codex rollout that is not a `codex exec` spawn, printed on stdout (empty when
# there is none).
#
# Codex keeps sessions in two places and both are needed: `sessions/` holds the live and
# recent ones (the session running right now is only ever there), `archived_sessions/`
# the retired ones. Looking at just one of them would miss the current session.
#
# `sessions/` is a YYYY/MM/DD tree that grows without bound — thousands of files here —
# so walking it whole on every run is wasteful. Descend newest-first instead and stop at
# the first acceptable file; a rollout always lives under its own date. The spawn check
# adds one `head` per candidate and stops at the first non-spawn, so the scan stays a
# handful of reads rather than a walk of the tree.
codex_latest_rollout() {
  local root="${CODEX_HOME:-$HOME/.codex}"
  local newest="" y m d cand c

  for y in $(ls -1 "$root/sessions" 2>/dev/null | sort -r); do
    for m in $(ls -1 "$root/sessions/$y" 2>/dev/null | sort -r); do
      for d in $(ls -1 "$root/sessions/$y/$m" 2>/dev/null | sort -r); do
        for c in $(ls -t "$root/sessions/$y/$m/$d"/rollout-*.jsonl 2>/dev/null); do
          codex_is_exec_spawn "$c" && continue
          newest="$c"; break
        done
        [ -n "$newest" ] && break
      done
      [ -n "$newest" ] && break
    done
    [ -n "$newest" ] && break
  done

  # The archive is flat, so one `ls -t` covers it. The same spawn filter applies — a
  # finished `codex exec` run gets archived like any other session. Compare against the
  # live pick by mtime and keep whichever is newer.
  cand=""
  for c in $(ls -t "$root/archived_sessions"/rollout-*.jsonl 2>/dev/null); do
    codex_is_exec_spawn "$c" && continue
    cand="$c"; break
  done
  if [ -n "$cand" ]; then
    if [ -z "$newest" ] || [ "$cand" -nt "$newest" ]; then
      newest="$cand"
    fi
  fi

  [ -n "$newest" ] && printf '%s\n' "$newest"
}

# The Codex rollout whose filename ends with <session id>, printed on stdout.
# Codex names its files rollout-<ISO timestamp>-<session id>.jsonl, so the id alone
# identifies one. The flat archive is checked first, then the date tree newest-month-first;
# the glob does the matching per month, so this stays a handful of directory reads rather
# than a walk of every one of the thousands of files.
codex_rollout_by_session() {
  local id="$1"
  local root="${CODEX_HOME:-$HOME/.codex}"
  local hit y m

  hit="$(ls -1 "$root/archived_sessions"/rollout-*-"$id".jsonl 2>/dev/null | head -1)"
  [ -n "$hit" ] && { printf '%s\n' "$hit"; return; }

  for y in $(ls -1 "$root/sessions" 2>/dev/null | sort -r); do
    for m in $(ls -1 "$root/sessions/$y" 2>/dev/null | sort -r); do
      hit="$(ls -1 "$root/sessions/$y/$m"/*/rollout-*-"$id".jsonl 2>/dev/null | head -1)"
      [ -n "$hit" ] && { printf '%s\n' "$hit"; return; }
    done
  done
}

# Resolve the transcript: explicit path wins, else ~/.claude/projects/<cwd-slug>/<session>.jsonl
# where <cwd-slug> is the absolute cwd with every '/' and '.' replaced by '-'.
#
# Claude resolution is tried first and unchanged, so behaviour under Claude never shifts;
# Codex is only consulted once that has come up empty.
if [ -z "$TRANSCRIPT" ]; then
  PROJECTS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
  SLUG="$(printf '%s' "$PWD" | tr '/.' '--')"
  if [ -n "$SESSION" ]; then
    TRANSCRIPT="$PROJECTS_DIR/$SLUG/$SESSION.jsonl"
  else
    # No session id — fall back to the most recently modified transcript of this project.
    TRANSCRIPT="$(ls -t "$PROJECTS_DIR/$SLUG"/*.jsonl 2>/dev/null | head -1)"
  fi

  # Nothing under ~/.claude — we may be running under Codex, which stores sessions
  # elsewhere in a different shape. A session id there is a rollout id, not a filename.
  if [ ! -f "$TRANSCRIPT" ]; then
    if [ -n "$SESSION" ]; then
      CODEX_HIT="$(codex_rollout_by_session "$SESSION")"
      [ -n "$CODEX_HIT" ] || CODEX_HIT="$(codex_latest_rollout)"
    else
      CODEX_HIT="$(codex_latest_rollout)"
    fi
    [ -n "$CODEX_HIT" ] && TRANSCRIPT="$CODEX_HIT"
  fi
fi

[ -n "$TRANSCRIPT" ] || exit 0
[ -f "$TRANSCRIPT" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

python3 - "$TRANSCRIPT" "$SINCE" "$VERBOSE" "$LANG_OUT" <<'PY' || exit 0
import json, sys

transcript, since, verbose, lang = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4]

# --- Tunables ---------------------------------------------------------------
# Consecutive timestamps further apart than this are treated as away-from-desk and
# excluded, so the report shows active working time rather than the wall-clock span.
ACTIVE_GAP_SECONDS = 300  # 5 minutes

# USD per 1M tokens (input, output), matched by model-id prefix — FIRST match wins,
# so this list MUST stay ordered longest-prefix-first. "claude-fable-5-1" has to precede
# "claude-fable-5", or a 5.1 id would match the 5 row and lose its 0.025x cache-read rate.
# Model ids may carry a date suffix (claude-haiku-4-5-20251001).
#
# Source: https://www.anthropic.com/pricing — last verified 2026-09-03.
# Rates drift; re-check against that page before trusting an old figure. An id that
# matches no prefix is not an error: tokens are still reported, the cost is left blank.
RATES = [
    ("claude-fable-5-1",   10.00, 50.00),
    ("claude-fable-5",     10.00, 50.00),
    ("claude-opus-5",       5.00, 25.00),
    ("claude-opus-4-8",     5.00, 25.00),
    ("claude-opus-4-7",     5.00, 25.00),
    ("claude-opus-4-6",     5.00, 25.00),
    ("claude-sonnet-5",     2.00, 10.00),
    ("claude-sonnet-4-6",   3.00, 15.00),
    ("claude-haiku-4-5",    1.00,  5.00),
]

# Cache multipliers applied to the base input rate.
CACHE_READ_MULT = 0.1
CACHE_READ_MULT_OVERRIDE = {"claude-fable-5-1": 0.025}
CACHE_WRITE_5M_MULT = 1.25
CACHE_WRITE_1H_MULT = 2.0


def normalize_model(model):
    """Strip a trailing [..] context-tier suffix — it carries no price premium."""
    if not model:
        return ""
    if model.endswith("]") and "[" in model:
        model = model[: model.rindex("[")]
    return model.strip()


def rates_for(model):
    """(input, output, cache_read_mult) for a model id, or None when unknown."""
    m = normalize_model(model)
    for prefix, rin, rout in RATES:
        if m.startswith(prefix):
            return rin, rout, CACHE_READ_MULT_OVERRIDE.get(prefix, CACHE_READ_MULT)
    return None


def parse_ts(value):
    """ISO8601 (with trailing Z) -> epoch seconds; None when unparseable."""
    if not value:
        return None
    try:
        import datetime
        return datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


class Bucket:
    """Token counters plus accumulated cost for one source row."""

    def __init__(self, label):
        self.label = label
        self.inp = 0
        self.out = 0
        self.cache_read = 0
        self.cache_write = 0
        self.cost = 0.0
        self.cache_saved = 0.0   # what the cache reads would have cost at the full input rate
        self.unknown_model = False

    @property
    def tokens(self):
        return self.inp + self.out + self.cache_read + self.cache_write

    def add(self, usage, model):
        inp = usage.get("input_tokens") or 0
        out = usage.get("output_tokens") or 0
        read = usage.get("cache_read_input_tokens") or 0
        creation = usage.get("cache_creation") or {}
        w5 = creation.get("ephemeral_5m_input_tokens") or 0
        w1h = creation.get("ephemeral_1h_input_tokens") or 0
        if not (w5 or w1h):
            # Older lines only carry the lump sum — treat it as the 5m tier.
            w5 = usage.get("cache_creation_input_tokens") or 0

        self.inp += inp
        self.out += out
        self.cache_read += read
        self.cache_write += w5 + w1h

        r = rates_for(model)
        if r is None:
            # Unknown model — count the tokens, skip the money, keep going.
            self.unknown_model = True
            return
        rin, rout, read_mult = r
        self.cost += (
            inp * rin
            + out * rout
            + read * rin * read_mult
            + w5 * rin * CACHE_WRITE_5M_MULT
            + w1h * rin * CACHE_WRITE_1H_MULT
        ) / 1_000_000
        self.cache_saved += read * rin * (1 - read_mult) / 1_000_000


# One API response is written out as several assistant lines that all share one
# `message.id` (and one `requestId`) and all repeat the same usage figures. Summing
# them multiplies the bill — measured at 1.88x on a main transcript and 2.21x on agent
# transcripts. So each request must be counted exactly once.
#
# Which repeat to keep is NOT arbitrary. Measured over 406 requests of a real session:
# input, cache read and cache write are byte-identical across every repeat, but
# `output_tokens` differs in 53 of them — the early lines carry a placeholder that is
# still being streamed (e.g. 1, 1, 221) and only the LAST line holds the finished count.
# Taking the last (equivalently the max) reproduces `ccusage` exactly on all four
# metrics; taking the first understates output by ~12%. Hence: keep one record per
# request and let later lines supersede earlier ones.
#
# Keys are global across files: a message id identifies one request, and no id was ever
# observed in both a main transcript and an agent transcript, so a global set cannot
# over-merge. Verified: no requestId ever spans two message ids.
def usage_key(entry, message):
    """Dedupe key for one usage line, or None when the line carries no identity.

    Prefers message.id, falls back to requestId. A line with neither is always counted:
    dropping unidentifiable usage would understate the bill, which is the worse error.
    """
    if isinstance(message, dict):
        mid = message.get("id")
        if isinstance(mid, str) and mid:
            return "m:" + mid
    if isinstance(entry, dict):
        rid = entry.get("requestId")
        if isinstance(rid, str) and rid:
            return "r:" + rid
    return None


def usage_output(usage):
    """output_tokens as an int, 0 when absent/not numeric.

    Accepts floats too: this value picks the winner among repeated records, so a
    numeric-but-not-int final count must not collapse to 0 and lose to a placeholder.
    bool is excluded — it is an int subclass, and True would silently read as 1.
    """
    value = usage.get("output_tokens")
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0
    return int(value)


class Deduper:
    """Collects one usage record per request, keeping the most complete repeat.

    Records are held until the end rather than added on sight, because an earlier line
    may be superseded by a later one (see the note above on streamed output_tokens).
    """

    def __init__(self):
        self.records = []          # ordered list of [key, usage, model, bucket_name]
        self.index = {}            # dedupe key -> position in records

    def add(self, entry, message, usage, model, bucket_name):
        key = usage_key(entry, message)
        if key is None:
            # No identity — record it unconditionally rather than risk losing usage.
            self.records.append([key, usage, model, bucket_name])
            return
        pos = self.index.get(key)
        if pos is None:
            self.index[key] = len(self.records)
            self.records.append([key, usage, model, bucket_name])
            return
        # Repeat of a request already seen: keep whichever line reports more output,
        # so a finished count always beats a mid-stream placeholder.
        if usage_output(usage) > usage_output(self.records[pos][1]):
            self.records[pos][1] = usage
            self.records[pos][2] = model


def strip_plugin_prefix(name):
    """'dobiflow:code-reviewer' -> 'code-reviewer'. Bare and plugin-prefixed names
    appear in the same session, so both shapes must land in the same bucket."""
    name = str(name)
    if name.startswith("dobiflow:"):
        name = name[len("dobiflow:"):]
    return name


def read_async_usage(result, deduper, since_ts=None):
    """Record usage for a background-launched subagent into `deduper`.

    Async launches record no usage on the tool-result line — only a pointer to a
    JSONL transcript in `outputFile`. Walk that file and hand each assistant line's
    usage to the deduper, which collapses the repeats of one request.

    `since_ts` filters on each `.output` line's OWN timestamp, not the launch line's.
    An async agent commonly outlives the cutoff: it is launched before, and keeps
    working after. Filtering by the launch timestamp drops such an agent whole,
    including everything it did after the cutoff — measured at 52% of one agent's
    work, $3.10 reported as $0. The bias is systematic, because the longer an agent
    runs the likelier it straddles a cutoff, so the most expensive agents are exactly
    the ones that vanish. There is no over-counting to trade off against: across 15
    measured agents the launch line and the first `.output` line were at most 1s
    apart, so "launched after the cutoff but worked before it" does not occur.

    A line carrying no parseable timestamp is COUNTED, never skipped. The add-on
    principle of this script is that failures degrade toward over-reporting; a silent
    under-count is the worse error and is precisely the bug this filter fixes.

    Returns True when at least one usage line was found. Anything unusable
    (missing/unreadable/malformed file, no attributionAgent, no usage) yields False —
    a background agent we cannot measure must never break the report.
    """
    path = result.get("outputFile")
    if not path or not isinstance(path, str):
        return False
    fallback_model = result.get("resolvedModel")
    fallback_name = result.get("description")
    found = False
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except Exception:
                    continue  # broken line — skip it, never abort
                # These files mix bare ints/strings in with the objects.
                if not isinstance(entry, dict):
                    continue
                if since_ts is not None:
                    line_ts = parse_ts(entry.get("timestamp"))
                    # No timestamp -> keep the line (see the docstring).
                    if line_ts is not None and line_ts < since_ts:
                        continue
                if entry.get("type") != "assistant":
                    continue
                message = entry.get("message")
                if not isinstance(message, dict):
                    continue
                usage = message.get("usage")
                if not isinstance(usage, dict):
                    continue
                model = message.get("model") or fallback_model
                if not model or model == "<synthetic>":
                    continue
                # attributionAgent uses the same format as the sync path's agentType.
                name = entry.get("attributionAgent") or fallback_name
                if not name:
                    continue
                deduper.add(entry, message, usage, model, strip_plugin_prefix(name))
                found = True
    except Exception:
        return found  # unreadable partway through — keep what we already recorded
    return found


# --- Format detection -------------------------------------------------------
# Both formats are `.jsonl` and --transcript may point at either, so the file is
# recognised by what is inside it, never by where it sits or what it is called.
#
# Only the head is read: the marker of each format appears early (Codex opens with
# `session_meta`, Claude has assistant usage within the first few exchanges) and a
# rollout can run to tens of thousands of lines. A file matching neither marker is
# not an error — the caller gets silence and exit 0, as it always has.
SNIFF_MAX_LINES = 400

CODEX_LINE_TYPES = ("event_msg", "response_item", "session_meta", "turn_context", "world_state")


def detect_format(path):
    """'claude' | 'codex' | None, decided by the first recognisable line."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for idx, line in enumerate(fh):
                if idx >= SNIFF_MAX_LINES:
                    break
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except Exception:
                    continue
                if not isinstance(entry, dict):
                    continue
                # Claude: usage hangs off message on an assistant line.
                if entry.get("type") == "assistant":
                    message = entry.get("message")
                    if isinstance(message, dict) and isinstance(message.get("usage"), dict):
                        return "claude"
                # Codex: every line carries a `payload` under one of its own line types.
                if entry.get("type") in CODEX_LINE_TYPES and isinstance(entry.get("payload"), dict):
                    return "codex"
    except Exception:
        return None
    return None


def as_int(value):
    """Non-negative int from a JSON number, 0 for anything else.

    bool is rejected first — it is an int subclass, so True would read as 1.
    """
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0
    try:
        return max(0, int(value))
    except Exception:
        return 0


# --- Codex ------------------------------------------------------------------
# Codex reports usage as `token_count` events carrying two figures:
#   * `total_token_usage` — CUMULATIVE, but only within one SEGMENT of the session (see
#     below). The 42 such lines of a measured session rose monotonically to a final
#     2,446,362. Summing every line would multiply the total several-fold, so without a
#     cutoff only the last value of each segment is read.
#   * `last_token_usage`  — the delta for that one turn. Needed for `--since`, since a
#     cumulative figure cannot answer "how much since 10:00".
# (Claude's per-request dedupe has no counterpart here and is not involved.)
#
# THE COUNTER RESTARTS WHEN A SESSION IS RESUMED. `total_token_usage` is cumulative only
# until the session is picked up again later, at which point it counts from zero into the
# SAME file under the SAME thread_id — a measured session ran to 314,688, was resumed 9.5
# hours later, and its next line read 65,802. Reading only the final value therefore
# reports the last stretch alone: 141,369 of an actual 456,057, silently losing 69%.
#
# So the file is read as a sequence of segments: a `total_tokens` LOWER than the one
# before it means the counter restarted, so the previous segment's last value is banked
# and a new segment begins; at EOF the final segment is banked. The reported usage is the
# field-wise sum of the banked values, which ccusage independently confirms as 456,057.
# A session that was never resumed has exactly one segment, so its figure is unchanged —
# verified over 179 reset-free rollouts, byte-identical before and after.
#
# The restart is detected from `total_tokens` decreasing, not from the
# `thread_settings_applied` / `task_started` markers that accompany a resume: the decrease
# is the property actually being corrected for, and needs no marker vocabulary. Comparing
# on `total_tokens` (not `input_tokens`) keeps a turn that is pure output from reading as
# a reset. Resumes are uncommon but real — 6 of 185 local rollouts, one of them 3 times.
#
CODEX_USAGE_FIELDS = ("input_tokens", "cached_input_tokens",
                      "cache_write_input_tokens", "output_tokens")


class CodexSegments(object):
    """Field-wise sum of the last `total_token_usage` of each segment.

    Feed every `total_token_usage` dict in file order; a `total_tokens` below its
    predecessor starts a new segment (the counter restarted on session resume). `total()`
    banks the segment still open and returns the sum, or None when nothing usable arrived.
    """

    def __init__(self):
        self._banked = dict((f, 0) for f in CODEX_USAGE_FIELDS)
        self._current = None    # last usage dict of the segment in progress
        self._prev_total = None  # its `total_tokens`, for the decrease check
        self._found = False
        self.segments = 1       # segment number of the line last accepted, 1-based

    def add(self, usage):
        """Record one `total_token_usage`, opening a new segment if it restarted."""
        total = usage.get("total_tokens")
        if isinstance(total, bool) or not isinstance(total, (int, float)):
            # No usable counter to compare on: keep it as the segment's latest value
            # rather than dropping a real turn, but leave the reset baseline untouched.
            self._current = usage
            self._found = True
            return
        if self._prev_total is not None and total < self._prev_total:
            self._bank()
            self.segments += 1
        self._current = usage
        self._prev_total = total
        self._found = True

    def _bank(self):
        """Fold the open segment's last value into the running sum."""
        if self._current is None:
            return
        for field in CODEX_USAGE_FIELDS:
            self._banked[field] += as_int(self._current.get(field))
        self._current = None
        self._prev_total = None

    def total(self):
        self._bank()
        return dict(self._banked) if self._found else None


# `token_count` lines REPEAT VERBATIM — two consecutive lines were observed both reading
# last_in=77,476 / total_in=275,917. `total_token_usage` is monotonic and immune, but
# summing `last_token_usage` naively double-counts those repeats: measured over 14 live
# sessions, naive summing missed the cumulative total in 4, while de-duplicating on
# `total_token_usage.total_tokens` (which is unique per real turn, being a running sum)
# matched 14/14. So the slice path must de-duplicate before it sums.
#
# That uniqueness holds only WITHIN a segment. Once the counter restarts on resume it
# re-walks the low values it already passed, so a bare `total_tokens` could match a turn
# from the earlier segment and discard it as a "repeat" — dropping real usage, the exact
# failure this file is being fixed for. The key is therefore `(segment, total_tokens)`.
# Verbatim repeats always sit inside one segment, so they are still caught. (No collision
# occurs across the 185 local rollouts today; the pairing costs nothing and removes the
# possibility rather than relying on the counter never landing on a value twice.)
def codex_usage_from_slice(records):
    """Sum per-turn deltas over post-cutoff `token_count` lines, repeats removed.

    `records` is [((segment, total_tokens), last_token_usage)] in file order. The first
    occurrence of each key wins; later identical lines are the verbatim repeats.
    """
    seen = set()
    totals = {"input_tokens": 0, "cached_input_tokens": 0,
              "cache_write_input_tokens": 0, "output_tokens": 0}
    found = False
    for key, usage in records:
        if key is not None:
            if key in seen:
                continue
            seen.add(key)
        for field in totals:
            totals[field] += as_int(usage.get(field))
        found = True
    return totals if found else None


def read_codex(path, since_ts=None):
    """(bucket, timestamps, rate_limits, model) for a Codex rollout.

    `bucket` is None when the file carries no usable `token_count`, which is the
    normal state of a session that has not called the model yet.

    With `since_ts` the tokens are the sum of the post-cutoff turns; without it they are
    the sum of each segment's last cumulative total, which is the simpler and
    independently ccusage-verified path. The model is captured REGARDLESS of the cutoff:
    `turn_context` appears once per session, at the very start, so filtering it by
    timestamp would lose the model label on every cutoff past the first turn — and, when
    `token_count` was filtered along with it, made the entire report vanish silently.
    """
    bucket = None
    timestamps = []
    usage = None
    rate_limits = None
    model = None
    slice_records = []
    segments = CodexSegments()
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except Exception:
                    continue  # broken line — skip it, never abort
                if not isinstance(entry, dict):
                    continue

                ts = parse_ts(entry.get("timestamp"))
                before_cutoff = since_ts is not None and ts is not None and ts < since_ts

                payload = entry.get("payload")
                if not isinstance(payload, dict):
                    continue

                # The model id lives on turn_context. NOT on rate_limits.limit_name,
                # which names the plan tier ("GPT-5.3-Codex-Spark") and would be
                # reported as a model that does not exist.
                #
                # Read before the cutoff check on purpose — see the docstring.
                if entry.get("type") == "turn_context":
                    candidate = payload.get("model")
                    if isinstance(candidate, str) and candidate:
                        model = candidate
                    continue

                # Segments are tracked across the WHOLE file, cutoff or not. A resume that
                # happened before the cutoff still divides the lines after it, so skipping
                # the earlier ones here would number the segments wrong (and, under
                # `--since`, key the dedupe on the wrong segment).
                is_token_count = payload.get("type") == "token_count"
                info = payload.get("info") if is_token_count else None
                total = info.get("total_token_usage") if isinstance(info, dict) else None
                if isinstance(total, dict):
                    segments.add(total)

                if before_cutoff:
                    continue
                if ts is not None:
                    timestamps.append(ts)

                if not is_token_count:
                    continue
                if isinstance(total, dict) and since_ts is not None:
                    delta = info.get("last_token_usage")
                    if isinstance(delta, dict):
                        key = total.get("total_tokens")
                        if isinstance(key, bool) or not isinstance(key, (int, float)):
                            key = None   # unusable key -> count the line, never drop it
                        else:
                            # Paired with the segment: after a restart the counter
                            # repeats values the earlier segment already used.
                            key = (segments.segments, key)
                        slice_records.append((key, delta))
                limits = payload.get("rate_limits")
                if isinstance(limits, dict):
                    rate_limits = limits
    except Exception:
        pass  # unreadable partway through — report what was gathered so far

    if since_ts is not None:
        usage = codex_usage_from_slice(slice_records)
    else:
        # Sum of each segment's last value: identical to that single last value for a
        # session that was never resumed, and the whole of a session that was.
        usage = segments.total()

    if isinstance(usage, dict):
        raw_in = as_int(usage.get("input_tokens"))
        cached = as_int(usage.get("cached_input_tokens"))
        bucket = Bucket("codex")
        # `input_tokens` is the gross figure and already contains the cached reads;
        # counting both would inflate input roughly 12x (2,433,990 vs 195,270 on the
        # verified session). Floored at 0 so a malformed pair cannot go negative.
        bucket.inp = max(0, raw_in - cached)
        bucket.cache_read = cached
        bucket.cache_write = as_int(usage.get("cache_write_input_tokens"))
        # `reasoning_output_tokens` is already inside `output_tokens` — adding it
        # would double-count. (input + output == total holds exactly.)
        bucket.out = as_int(usage.get("output_tokens"))
        # No published rate for these models, so tokens are reported without money,
        # exactly as an unknown Claude model already is.
        bucket.unknown_model = True
        # A `token_count` whose figures are all unusable is the same as none at all —
        # a "0 tokens" report is noise. The Claude path likewise drops empty rows.
        if bucket.tokens <= 0:
            bucket = None

    return bucket, timestamps, rate_limits, model


since_ts = parse_ts(since) if since else None

fmt = detect_format(transcript)
if fmt is None:
    sys.exit(0)   # neither format — stay silent, as before

MAIN_BUCKET = None   # sentinel: records routed to the main row rather than an agent row

main = Bucket("main")
agents = {}          # normalized agent type -> Bucket
timestamps = []
saw_any = False
seen_output_files = set()   # async transcripts already consumed (see the isAsync branch)
deduper = Deduper()  # per-request usage, collapsed across repeated lines
codex_rate_limits = None
codex_model = None

if fmt == "codex":
    codex_bucket, timestamps, codex_rate_limits, codex_model = read_codex(transcript, since_ts)
    if codex_bucket is not None:
        main = codex_bucket
        saw_any = True


def claude_lines(fh):
    """The transcript's lines, or none at all when this is not a Claude transcript.

    Keeps the Claude walk below in one piece and untouched: a Codex file simply never
    enters it, so nothing about Claude's aggregation can shift.
    """
    return fh if fmt == "claude" else ()


with open(transcript, "r", encoding="utf-8", errors="replace") as fh:
    for line in claude_lines(fh):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except Exception:
            continue  # broken line — skip it, never abort
        if not isinstance(entry, dict):
            continue

        result = entry.get("toolUseResult")
        is_async_launch = isinstance(result, dict) and bool(result.get("isAsync"))

        ts = parse_ts(entry.get("timestamp"))
        before_cutoff = since_ts is not None and ts is not None and ts < since_ts

        # An async launch before the cutoff is the one thing --since must NOT drop here:
        # the agent it started may have kept working long past the cutoff, and only its
        # `.output` lines can say how much. Dropping it cost a straddling agent its entire
        # bill (measured: 52% of its work was post-cutoff, $0 counted).
        #
        # INVARIANT for anyone adding a branch below: a pre-cutoff line now survives this
        # point, so any new branch must re-check `before_cutoff` itself. Only the async
        # branch is exempt, because it filters per `.output` line instead.
        if before_cutoff and not is_async_launch:
            continue
        # Excluded from timestamps either way, so active working time is unaffected.
        if ts is not None and not before_cutoff:
            timestamps.append(ts)

        # Background-launched subagents carry no agentType and no usage here; their
        # numbers live in the transcript at result.outputFile. Exclusive with the
        # two branches below (a launch line has isAsync, never agentType, and is a
        # `user` line, never `assistant`) — hence the early `continue`.
        #
        # Two launch lines can point at the same outputFile (a resumed or retried
        # agent keeps its id). Reading it twice would count that agent twice, so
        # track the files already consumed and skip repeats.
        if is_async_launch:
            output_file = result.get("outputFile")
            if isinstance(output_file, str):
                if output_file in seen_output_files:
                    continue
                seen_output_files.add(output_file)
            if read_async_usage(result, deduper, since_ts):
                saw_any = True
            continue

        # Main-session usage: assistant lines carrying message.usage.
        message = entry.get("message")
        if entry.get("type") == "assistant" and isinstance(message, dict):
            usage = message.get("usage")
            model = message.get("model")
            if isinstance(usage, dict) and model and model != "<synthetic>":
                # Repeats of one request are collapsed by the deduper, not added here.
                deduper.add(entry, message, usage, model, MAIN_BUCKET)
                saw_any = True

        # Subagent usage: recorded on the Agent tool-call result line.
        if isinstance(result, dict) and result.get("agentType"):
            usage = result.get("usage")
            if isinstance(usage, dict):
                # Bare and plugin-prefixed names appear in the same session — merge them.
                name = str(result["agentType"])
                if name.startswith("dobiflow:"):
                    name = name[len("dobiflow:"):]
                bucket = agents.get(name)
                if bucket is None:
                    bucket = agents[name] = Bucket(name)
                bucket.add(usage, result.get("resolvedModel"))
                saw_any = True

# Fold the deduplicated records into their rows. Deferred to here because a later line
# can supersede an earlier one for the same request (see the Deduper note).
for _key, _usage, _model, _bucket_name in deduper.records:
    if _bucket_name is MAIN_BUCKET:
        main.add(_usage, _model)
    else:
        _bucket = agents.get(_bucket_name)
        if _bucket is None:
            _bucket = agents[_bucket_name] = Bucket(_bucket_name)
        _bucket.add(_usage, _model)

if not saw_any:
    sys.exit(0)

# Active time: sum only the gaps at or below the threshold (see ACTIVE_GAP_SECONDS).
timestamps.sort()
active_seconds = 0.0
for prev, cur in zip(timestamps, timestamps[1:]):
    gap = cur - prev
    if 0 < gap <= ACTIVE_GAP_SECONDS:
        active_seconds += gap

rows = [main] + sorted(agents.values(), key=lambda b: b.cost, reverse=True)
rows = [r for r in rows if r.tokens > 0]
total_cost = sum(r.cost for r in rows)
total_tokens = sum(r.tokens for r in rows)
any_unknown = any(r.unknown_model for r in rows)

# Accept whatever the caller passes for Korean: a BCP-47 tag (ko, ko-KR), an English
# language name, or the endonym. Callers are language models filling in "<user's language>",
# so normalize rather than trusting an exact token.
_lang = lang.strip().lower()
KO = _lang.startswith("ko") or _lang.startswith("kor") or "한국" in lang


def fmt_tokens(n):
    if n >= 1_000_000:
        return "%.1fM" % (n / 1_000_000)
    if n >= 1_000:
        return "%.0fK" % (n / 1_000)
    return str(n)


def fmt_cost(value, partial=False):
    """'+' marks a row whose cost covers only the models with a known rate."""
    if partial:
        return "-" if value <= 0 else "$%.2f+" % value
    return "$%.2f" % value


def fmt_duration(seconds):
    minutes = int(round(seconds / 60))
    if minutes < 60:
        return ("%d분" % minutes) if KO else ("%d min" % minutes)
    hours, rem = divmod(minutes, 60)
    if KO:
        return "%d시간 %d분" % (hours, rem) if rem else "%d시간" % hours
    return "%dh %dmin" % (hours, rem) if rem else "%dh" % hours


# Analogy tiers: (upper bound of the tier, unit price, ko name, en singular, en plural).
# The unit switches automatically with the magnitude so the count stays a small number.
# One unit for every magnitude: the Big Mac. It is the same object everywhere, so the
# reader converts without knowing local prices — unlike "lunch" or "team dinner", whose
# cost varies by country. Priced at the Big Mac Index (US, mid-2026); a stale price only
# shifts the count slightly, so this needs no upkeep.
BIG_MAC_USD = 6.0


def analogy(cost):
    """One short line putting the cost in Big Macs."""
    if cost < 0.01:   # rounds to $0.00 — an analogy would be noise
        return None
    if cost < BIG_MAC_USD / 2:
        # Below half a burger, rounding to "1" overstates it — say it plainly instead.
        return "빅맥 반 개도 안 돼요" if KO else "less than half a Big Mac"
    count = max(1, int(round(cost / BIG_MAC_USD)))
    if KO:
        return "빅맥 %d개쯤" % count
    if count == 1:
        return "about one Big Mac"
    return "about %d Big Macs" % count


# Plan usage is a Codex-only figure: it ships on every `token_count` line and Claude
# transcripts carry no equivalent (no used_percent, plan_type or quota anywhere), so the
# line below simply never renders under Claude.
def fmt_window(minutes):
    """A rate-limit window in words: 10080 -> 'this week'. None when unusable."""
    if minutes <= 0:
        return None
    if minutes >= 40320:      # 4 weeks or more
        return "이번 달" if KO else "this month"
    if minutes >= 10080:      # a week
        return "이번 주" if KO else "this week"
    if minutes >= 1440:       # a day
        return "오늘" if KO else "today"
    hours = int(round(minutes / 60.0))
    if hours >= 1:
        return ("최근 %d시간" % hours) if KO else ("in the last %dh" % hours)
    return ("최근 %d분" % int(minutes)) if KO else ("in the last %dmin" % int(minutes))


def fmt_reset(resets_at):
    """'3일 뒤 초기화' / 'resets in 3 days'. None when the epoch is missing or past."""
    if resets_at <= 0:
        return None
    try:
        import time
        remaining = resets_at - time.time()
    except Exception:
        return None
    if remaining <= 0:
        return None
    days = int(remaining // 86400)
    if days >= 1:
        return ("%d일 뒤 초기화" % days) if KO else ("resets in %d days" % days)
    hours = int(remaining // 3600)
    if hours >= 1:
        return ("%d시간 뒤 초기화" % hours) if KO else ("resets in %dh" % hours)
    minutes = max(1, int(remaining // 60))
    return ("%d분 뒤 초기화" % minutes) if KO else ("resets in %dmin" % minutes)


def plan_usage_line(rate_limits):
    """One line on how much of the plan quota is used, or None when unavailable.

    Reads `primary` — the window Codex itself surfaces first. `plan_type` and the reset
    time are decoration: when either is missing the line still prints without it.
    """
    if not isinstance(rate_limits, dict):
        return None
    primary = rate_limits.get("primary")
    if not isinstance(primary, dict):
        return None
    used = primary.get("used_percent")
    if isinstance(used, bool) or not isinstance(used, (int, float)):
        return None

    window = primary.get("window_minutes")
    window_text = fmt_window(window) if isinstance(window, (int, float)) and not isinstance(window, bool) else None

    parenthetical = []
    plan = rate_limits.get("plan_type")
    if isinstance(plan, str) and plan:
        parenthetical.append(plan.capitalize())
    resets_at = rate_limits.get("resets_at")
    if not isinstance(resets_at, (int, float)) or isinstance(resets_at, bool):
        resets_at = primary.get("resets_at")
    if isinstance(resets_at, (int, float)) and not isinstance(resets_at, bool):
        reset_text = fmt_reset(resets_at)
        if reset_text:
            parenthetical.append(reset_text)

    if KO:
        text = "- %s 플랜 사용량 %.0f%%" % (window_text, used) if window_text \
               else "- 플랜 사용량 %.0f%%" % used
    else:
        text = "- Plan quota %.0f%% used %s" % (used, window_text) if window_text \
               else "- Plan quota %.0f%% used" % used
    if parenthetical:
        text += " (" + ", ".join(parenthetical) + ")"
    return text


def display_width(text):
    """Terminal width — CJK / fullwidth characters occupy two columns."""
    import unicodedata
    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in str(text))


def render(table):
    """Markdown table from a list of rows (first row is the header)."""
    widths = [max(display_width(row[i]) for row in table) for i in range(len(table[0]))]
    out = []
    for idx, row in enumerate(table):
        cells = [str(c) + " " * (widths[i] - display_width(c)) for i, c in enumerate(row)]
        out.append("| " + " | ".join(cells) + " |")
        if idx == 0:
            out.append("|" + "|".join("-" * (w + 2) for w in widths) + "|")
    return out


IS_CODEX = fmt == "codex"

lines = []
if IS_CODEX:
    # Tokens instead of money: Codex publishes no rates, and inventing one would be
    # a made-up bill. The Big Mac analogy is derived from cost, so it goes too.
    headline = "🧦 %s · %s %s" % (fmt_duration(active_seconds), fmt_tokens(total_tokens),
                                  "토큰" if KO else "tokens")
else:
    headline = "🧦 %s · %s" % (fmt_duration(active_seconds), fmt_cost(total_cost, any_unknown))
    note = analogy(total_cost)
    if note:
        headline += " · " + note
lines.append(headline)

# State what the figures cover. The table lists agent names, which reads as if those
# agents spent the whole amount; without --since this is the entire session, other
# skills and ordinary conversation included. Say so rather than let the reader guess.
if since:
    # Both time and tokens are now genuinely scoped to the slice on either format, so
    # Codex needs no separate wording. (It used to claim the tokens were a session
    # running total; they are summed per-turn deltas since the cutoff — see read_codex.)
    lines.append("- 이 시점 이후 작업 기준이에요." if KO else
                 "- Covers the work done since that point.")
else:
    lines.append("- 이 세션 전체 기준이에요 — 다른 스킬과 일반 대화도 포함돼 있어요."
                 if KO else
                 "- Covers this whole session, other skills and ordinary conversation included.")

if IS_CODEX:
    plan_line = plan_usage_line(codex_rate_limits)
    if plan_line:
        lines.append(plan_line)

lines.append("")

label_source = "구분" if KO else "Source"
label_tokens = "토큰" if KO else "Tokens"
label_cost = "비용" if KO else "Cost"
label_main = "메인" if KO else "Main"
label_total = "합계" if KO else "Total"

if IS_CODEX:
    # One row, and no cost column: Codex reports a single total that already contains
    # every in-session agent turn (they share this rollout file, so there is nothing to
    # split), and there is no rate to price it with. A `codex exec` spawn is a separate
    # session in a file of its own and is not in this figure. The row is labelled with
    # the model so the reader can see what actually ran.
    label_codex = codex_model if codex_model else label_total
    if verbose:
        table = [[
            label_source,
            "입력" if KO else "Input",
            "캐시 쓰기" if KO else "Cache write",
            "캐시 읽기" if KO else "Cache read",
            "출력" if KO else "Output",
        ], [
            label_codex,
            fmt_tokens(main.inp),
            fmt_tokens(main.cache_write),
            fmt_tokens(main.cache_read),
            fmt_tokens(main.out),
        ]]
    else:
        table = [[label_source, label_tokens], [label_codex, fmt_tokens(total_tokens)]]
    lines += render(table)

    lines.append("")
    # Say this outright: a reader used to the Claude table would otherwise read the
    # single row as "no agents ran", when in truth their usage is folded into it.
    #
    # Scoped to agents running INSIDE the session on purpose. A `codex exec` spawn gets
    # its own rollout file, so it is not in this total at all — claiming otherwise would
    # be the opposite error.
    lines.append("- Codex는 세션 안에서 도는 에이전트 사용량이 이 기록에 합쳐져 있어 에이전트별로 나눌 수 없어요."
                 if KO else
                 "- Codex folds in-session agent usage into this one record, so it cannot be broken down per agent.")
    lines.append("- 공개된 단가가 없어 금액은 계산하지 않고 토큰만 보여드려요."
                 if KO else
                 "- No published rate for these models, so tokens are shown without a cost.")
elif verbose:
    header = [
        label_source,
        "입력" if KO else "Input",
        "캐시 쓰기" if KO else "Cache write",
        "캐시 읽기" if KO else "Cache read",
        "출력" if KO else "Output",
        label_cost,
    ]
    table = [header]
    for r in rows:
        table.append([
            label_main if r is main else r.label,
            fmt_tokens(r.inp),
            fmt_tokens(r.cache_write),
            fmt_tokens(r.cache_read),
            fmt_tokens(r.out),
            fmt_cost(r.cost, r.unknown_model),
        ])
    table.append([
        label_total,
        fmt_tokens(sum(r.inp for r in rows)),
        fmt_tokens(sum(r.cache_write for r in rows)),
        fmt_tokens(sum(r.cache_read for r in rows)),
        fmt_tokens(sum(r.out for r in rows)),
        fmt_cost(total_cost, any_unknown),
    ])
    lines += render(table)

    # Cache savings: what those cache reads would have cost without prompt caching.
    saved = sum(r.cache_saved for r in rows)
    if saved > 0:
        lines.append("")
        lines.append(("- 캐시 덕분에 %s 아꼈어요 (캐시 없이 다시 읽었다면 %s)."
                      % (fmt_cost(saved), fmt_cost(total_cost + saved)))
                     if KO else
                     ("- Prompt caching saved %s (it would have been %s without it)."
                      % (fmt_cost(saved), fmt_cost(total_cost + saved))))
else:
    table = [[label_source, label_tokens, label_cost]]
    for r in rows:
        table.append([
            label_main if r is main else r.label,
            fmt_tokens(r.tokens),
            fmt_cost(r.cost, r.unknown_model),
        ])
    table.append([label_total, fmt_tokens(total_tokens), fmt_cost(total_cost, any_unknown)])
    lines += render(table)

# Codex prints no cost at all, so the note about partial `+` amounts would refer to
# figures that are not on screen.
if any_unknown and not IS_CODEX:
    lines.append("")
    lines.append("- 단가를 모르는 모델이 섞여 있어 `+` 표시 금액은 일부만 반영된 값이에요."
                 if KO else
                 "- A model with no known rate is mixed in, so `+` amounts cover only part of the usage.")

print("\n".join(lines))
PY

exit 0
