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


since_ts = parse_ts(since) if since else None

main = Bucket("main")
agents = {}          # normalized agent type -> Bucket
timestamps = []
saw_any = False

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
                main.add(usage, model)
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
ANALOGY_TIERS = [
    (1.0, 0.8, "사탕", "candy", "candies"),
    (4.0, 2.0, "삼각김밥", "onigiri", "onigiri"),
    (15.0, 5.0, "커피", "coffee", "coffees"),
    (60.0, 12.0, "점심", "lunch", "lunches"),
    (300.0, 25.0, "치킨", "fried chicken", "fried chickens"),
    (float("inf"), 120.0, "회식", "team dinner", "team dinners"),
]


def analogy(cost):
    """One short line whose unit switches with the magnitude."""
    if cost < 0.01:   # rounds to $0.00 — an analogy would be noise
        return None
    for limit, unit_price, name_ko, singular, plural in ANALOGY_TIERS:
        if cost < limit:
            count = max(1, int(round(cost / unit_price)))
            if KO:
                return "%s %d개쯤" % (name_ko, count)
            if count == 1:
                return "about one %s" % singular
            return "about %d %s" % (count, plural)
    return None


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
