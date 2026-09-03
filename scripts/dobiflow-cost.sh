#!/usr/bin/env bash
# dobiflow cost & time report — printed on request at the post-merge cleanup step.
# Reads the Claude Code session transcript (JSONL) and aggregates tokens, cost and
# active working time per source (main session + each subagent type).
#
# Usage: dobiflow-cost [options]
#   --transcript <path>   transcript JSONL path (skips session/cwd resolution)
#   --session <id>        session id; resolved under ~/.claude/projects/<cwd-slug>/<id>.jsonl
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

# Resolve the transcript: explicit path wins, else ~/.claude/projects/<cwd-slug>/<session>.jsonl
# where <cwd-slug> is the absolute cwd with every '/' and '.' replaced by '-'.
if [ -z "$TRANSCRIPT" ]; then
  PROJECTS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
  SLUG="$(printf '%s' "$PWD" | tr '/.' '--')"
  if [ -n "$SESSION" ]; then
    TRANSCRIPT="$PROJECTS_DIR/$SLUG/$SESSION.jsonl"
  else
    # No session id — fall back to the most recently modified transcript of this project.
    TRANSCRIPT="$(ls -t "$PROJECTS_DIR/$SLUG"/*.jsonl 2>/dev/null | head -1)"
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


def read_async_usage(result, deduper):
    """Record usage for a background-launched subagent into `deduper`.

    Async launches record no usage on the tool-result line — only a pointer to a
    JSONL transcript in `outputFile`. Walk that file and hand each assistant line's
    usage to the deduper, which collapses the repeats of one request.

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


since_ts = parse_ts(since) if since else None

MAIN_BUCKET = None   # sentinel: records routed to the main row rather than an agent row

main = Bucket("main")
agents = {}          # normalized agent type -> Bucket
timestamps = []
saw_any = False
seen_output_files = set()   # async transcripts already consumed (see the isAsync branch)
deduper = Deduper()  # per-request usage, collapsed across repeated lines

with open(transcript, "r", encoding="utf-8", errors="replace") as fh:
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
        if since_ts is not None and ts is not None and ts < since_ts:
            continue
        if ts is not None:
            timestamps.append(ts)

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
        result = entry.get("toolUseResult")
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

        # Background-launched subagents carry no agentType and no usage here; their
        # numbers live in the transcript at result.outputFile. Exclusive with the
        # branch above (a launch line has isAsync, never agentType).
        #
        # Two launch lines can point at the same outputFile (a resumed or retried
        # agent keeps its id). Reading it twice would count that agent twice, so
        # track the files already consumed and skip repeats.
        elif isinstance(result, dict) and result.get("isAsync"):
            output_file = result.get("outputFile")
            if isinstance(output_file, str):
                if output_file in seen_output_files:
                    continue
                seen_output_files.add(output_file)
            if read_async_usage(result, deduper):
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


lines = []
headline = "🧦 %s · %s" % (fmt_duration(active_seconds), fmt_cost(total_cost, any_unknown))
note = analogy(total_cost)
if note:
    headline += " · " + note
lines.append(headline)

# State what the figures cover. The table lists agent names, which reads as if those
# agents spent the whole amount; without --since this is the entire session, other
# skills and ordinary conversation included. Say so rather than let the reader guess.
if since:
    lines.append("- 이 시점 이후 작업 기준이에요." if KO else
                 "- Covers the work done since that point.")
else:
    lines.append("- 이 세션 전체 기준이에요 — 다른 스킬과 일반 대화도 포함돼 있어요."
                 if KO else
                 "- Covers this whole session, other skills and ordinary conversation included.")

lines.append("")

label_source = "구분" if KO else "Source"
label_tokens = "토큰" if KO else "Tokens"
label_cost = "비용" if KO else "Cost"
label_main = "메인" if KO else "Main"
label_total = "합계" if KO else "Total"

if verbose:
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

if any_unknown:
    lines.append("")
    lines.append("- 단가를 모르는 모델이 섞여 있어 `+` 표시 금액은 일부만 반영된 값이에요."
                 if KO else
                 "- A model with no known rate is mixed in, so `+` amounts cover only part of the usage.")

print("\n".join(lines))
PY

exit 0
