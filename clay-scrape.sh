#!/bin/sh
# Clay inbox scraper. Reads Sagar's logged-in Clay Global Inbox through Chrome
# and writes every reply plus its full thread to disk.
# Verified working 2026-09-06 against app.clay.com.
set -e
KIT="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HOME/clay-export}"
mkdir -p "$OUT"

say() { printf '%s\n' "$*"; }

# ---- 1. preflight -----------------------------------------------------------
if ! pgrep -f "MacOS/Google Chrome" >/dev/null 2>&1; then
  say "STOP: Google Chrome is not running. Open Chrome, log in to Clay, then rerun."; exit 1
fi

EXTRA=$(ps ax -o pid=,command= | grep "MacOS/Google Chrome" | grep -v grep | grep -c -- "--user-data-dir\|--remote-debugging-port" || true)
if [ "$EXTRA" -gt 0 ]; then
  say "WARNING: a second, automation-launched Chrome is running."
  say "AppleScript will talk to the wrong one. Quit it, then rerun."
  say "Find it with:  ps ax | grep 'MacOS/Google Chrome' | grep -- --user-data-dir"
  exit 1
fi

say "Finding the Clay tab..."
FOUND=$(osascript "$KIT/find_tab.applescript" "app.clay.com" 2>&1 || true)
case "$FOUND" in
  FOUND*) say "  $FOUND" ;;
  NOTFOUND) say "STOP: no Clay tab open. Open your Clay inbox in Chrome, then rerun."; exit 1 ;;
  *) say "STOP: could not talk to Chrome."
     say "  $FOUND"
     say "Fix: Chrome menu > View > Developer > Allow JavaScript from Apple Events (tick it),"
     say "then rerun and approve the macOS permission prompt when it appears."; exit 1 ;;
esac
sleep 2

# ---- 2. extract the reply list ---------------------------------------------
say "Reading the reply list..."
osascript "$KIT/run_js.applescript" "$KIT/extract_rows.js" > "$OUT/rows.json" 2>&1
COUNT=$(python3 -c "import json;print(len(json.load(open('$OUT/rows.json'))))" 2>/dev/null || echo 0)
if [ "$COUNT" -eq 0 ]; then
  say "STOP: found 0 replies. Either the inbox filter is hiding them, or Clay changed its markup."
  say "Scroll the reply list once so it renders, then rerun."; exit 1
fi
say "  found $COUNT replies"

# ---- 3. pick which threads to open -----------------------------------------
python3 - "$OUT" <<'PY'
import json, sys
out = sys.argv[1]
rows = json.load(open(f"{out}/rows.json"))
skip = {"Out of office", "Sender-originated bounce"}
live = [r for r in rows if r["category"] not in skip]
open(f"{out}/idx.txt", "w").write("".join(f"{r['i']}\n" for r in live))
print(f"  {len(live)} real replies to open ({len(rows) - len(live)} autoresponders skipped)")
PY

# ---- 4. walk every thread ---------------------------------------------------
say "Opening threads (about 2 seconds each)..."
: > "$OUT/threads.jsonl"
N=0
while IFS= read -r i; do
  [ -z "$i" ] && continue
  sed "s/__IDX__/$i/" "$KIT/click_row.js.tmpl" > "$OUT/_click.js"
  osascript "$KIT/run_js.applescript" "$OUT/_click.js" >/dev/null 2>&1
  sleep 1.6
  PANE=$(osascript "$KIT/run_js.applescript" "$KIT/read_pane.js" 2>&1 | tr -d '\r' | tr '\n' ' ')
  printf '{"i":%s,"pane":%s}\n' "$i" "$PANE" >> "$OUT/threads.jsonl"
  N=$((N+1))
  [ $((N % 10)) -eq 0 ] && say "  $N done"
done < "$OUT/idx.txt"
rm -f "$OUT/_click.js"

# ---- 5. join into one readable file -----------------------------------------
python3 - "$OUT" <<'PY'
import json, sys, csv, re
out = sys.argv[1]
rows = {r["i"]: r for r in json.load(open(f"{out}/rows.json"))}
merged = []
for line in open(f"{out}/threads.jsonl"):
    line = line.strip()
    if not line: continue
    try: rec = json.loads(line)
    except Exception: continue
    r = rows.get(rec["i"], {})
    pane = rec.get("pane")
    text = pane.get("t", "") if isinstance(pane, dict) else str(pane)
    merged.append({**r, "thread": text})
json.dump(merged, open(f"{out}/replies.json", "w"), indent=1)

with open(f"{out}/replies.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["email", "date", "campaign", "clay_category", "thread"])
    for m in merged:
        w.writerow([m.get("email",""), m.get("date",""), m.get("campaign",""),
                    m.get("category","") or "(uncategorised)",
                    re.sub(r"\n{2,}", "\n", m.get("thread",""))])

with open(f"{out}/replies.md", "w") as f:
    f.write("# Clay inbox export\n\n")
    for m in merged:
        f.write(f"\n---\n\n## {m.get('email','')}\n")
        f.write(f"- Date: {m.get('date','')}\n- Campaign: {m.get('campaign','')}\n")
        f.write(f"- Clay category: {m.get('category','') or '(uncategorised)'}\n\n")
        f.write("```\n" + re.sub(r"\n{2,}", "\n", m.get("thread","")).strip()[:4000] + "\n```\n")
print(f"  wrote {len(merged)} threads")
PY

say ""
say "Done. Files in $OUT :"
say "  replies.md    <- give this one to Claude or Perplexity"
say "  replies.csv   <- opens in Excel"
say "  replies.json  <- structured"
say "  rows.json     <- the raw reply list, nothing filtered"
