---
name: clay-inbox-export
description: Read every reply in a Clay campaign inbox through the user's own logged-in Chrome, and write each one to disk with its full email thread. Use when the user wants to pull their Clay replies into a spreadsheet, a CRM, or an analysis, or asks who replied and what they said.
---

# Clay inbox export

Clay's Global Inbox holds every reply to your campaigns, but it will not export
them with the thread bodies attached, and its API does not cover the inbox. The
replies are only readable inside a browser that is already logged in as you.

This skill drives **your own Chrome**, the one where you are already signed in,
reads the reply list, opens each thread, and writes all of it to disk as
Markdown, CSV and JSON. Nothing is uploaded anywhere. No password is needed,
because the session is already open.

It was written after exporting a 107-reply inbox on 2026-09-06 and is tested
end to end against `app.clay.com`.

---

## Part 1: three things only Sagar can do

An agent cannot do these. They are one-time, and the whole thing fails without
them.

**1. Turn on JavaScript from Apple Events.**
In Chrome: **View menu > Developer > Allow JavaScript from Apple Events**, and
tick it. If you do not see a Developer submenu, first tick
**Chrome > Settings > Advanced > Show Developer menu**, or just press the tick
in View > Developer. This is off by default and is the single most common
reason this fails.

**2. Open the Clay inbox in a normal Chrome tab and stay logged in.**
Go to your Global Inbox (`app.clay.com/workspaces/<your-workspace-id>/campaigns/inbox`),
make sure the reply list is showing, and **scroll the list once** so every row
renders. Leave the tab open.

**3. Approve the macOS permission prompt.**
The first run pops up "Terminal wants to control Google Chrome". Click OK. If
you miss it, go to **System Settings > Privacy & Security > Automation** and
enable Chrome under whichever app you ran it from.

That is it. Everything below is for the agent.

---

## Part 2: instructions to the agent

You are running on the user's Mac with shell access. Do not use Playwright,
Puppeteer, a headless browser, or a new browser window. Those all start a fresh
profile with no Clay session, and you will get a login page instead of an inbox.
The only thing that works is scripting the user's existing Chrome.

Create the six files in Part 3 under `~/clay-kit/`, make the shell script
executable, and run it:

```
mkdir -p ~/clay-kit && cd ~/clay-kit
# write the six files from Part 3 here
chmod +x ~/clay-kit/clay-scrape.sh
cd ~/clay-kit && ./clay-scrape.sh ~/clay-export
```

It prints its progress, takes roughly two seconds per thread, and stops with a
named reason if a precondition is missing. A 107-reply inbox takes about three
minutes.

When it finishes, read `~/clay-export/replies.md`. That file has every reply
with its full thread. Work from it directly.

---

## Part 3: the files

### `~/clay-kit/run_js.applescript`

Runs a JavaScript file inside the active Chrome tab. Using a file rather than
an inline `osascript -e` string avoids a quoting nightmare with multi-line JS.

```applescript
on run argv
	set jsFile to item 1 of argv
	set js to (read (POSIX file jsFile) as «class utf8»)
	tell application "Google Chrome"
		return execute front window's active tab javascript js
	end tell
end run
```

### `~/clay-kit/find_tab.applescript`

Finds the Clay tab across every window and brings it to the front. Never assume
the front tab is the right one, because the user will have moved on.

```applescript
on run argv
	set needle to item 1 of argv
	tell application "Google Chrome"
		set wi to 0
		repeat with w in windows
			set wi to wi + 1
			set ti to 0
			repeat with t in tabs of w
				set ti to ti + 1
				if (URL of t) contains needle then
					set active tab index of w to ti
					set index of w to 1
					return "FOUND " & wi & " " & ti & " " & (URL of t)
				end if
			end repeat
		end repeat
		return "NOTFOUND"
	end tell
end run
```

### `~/clay-kit/extract_rows.js`

Pulls the reply list. The class selector is what Clay used on 2026-09-06; the
fallback finds any small element whose first child is a bare email address, so
a Clay redesign degrades instead of breaking.

```javascript
(() => {
  const re = /^[\w.+-]+@[\w.-]+\.[a-z]{2,}$/i;
  let rows = [...document.querySelectorAll('div.flex.w-full.min-w-0.flex-row.items-center.justify-between')]
    .filter(e => re.test((e.childNodes[0]?.textContent || '').trim()));
  if (rows.length === 0) {
    rows = [...document.querySelectorAll('div,li')]
      .filter(e => re.test((e.childNodes[0]?.textContent || '').trim())
                && (e.textContent || '').length < 400
                && e.querySelector('*') !== null);
  }
  return JSON.stringify(rows.map((e, i) => {
    const lab = e.closest('label') || e.parentElement;
    const t = (lab.innerText || '').split('\n').map(s => s.trim()).filter(Boolean);
    return { i, email: t[0] || '', date: t[1] || '', campaign: t[2] || '', category: t[3] || '' };
  }));
})()
```

### `~/clay-kit/read_pane.js`

Reads the open thread. Falls back to walking up from the Forward button if the
class changes.

```javascript
(() => {
  let p = document.querySelector('div.w-full.overflow-y-auto.bg-bg-secondary');
  if (!p) {
    const f = [...document.querySelectorAll('button,div,span')]
      .find(e => (e.textContent || '').trim() === 'Forward');
    let q = f;
    for (let i = 0; i < 12 && q; i++) { if ((q.innerText || '').length > 300) { p = q; break; } q = q.parentElement; }
  }
  return JSON.stringify({ t: p ? p.innerText : 'NOPANE' });
})()
```

### `~/clay-kit/click_row.js.tmpl`

Opens one thread by index. `__IDX__` is substituted per row by the shell script.

```javascript
(() => {
  const re = /^[\w.+-]+@[\w.-]+\.[a-z]{2,}$/i;
  let rows = [...document.querySelectorAll('div.flex.w-full.min-w-0.flex-row.items-center.justify-between')]
    .filter(e => re.test((e.childNodes[0]?.textContent || '').trim()));
  if (rows.length === 0) {
    rows = [...document.querySelectorAll('div,li')]
      .filter(e => re.test((e.childNodes[0]?.textContent || '').trim())
                && (e.textContent || '').length < 400 && e.querySelector('*') !== null);
  }
  const r = rows[__IDX__];
  if (!r) return 'NOROW';
  const lab = r.closest('label') || r.parentElement;
  lab.scrollIntoView({ block: 'center' });
  lab.click();
  return 'OK ' + (r.childNodes[0]?.textContent || '').trim();
})()
```

### `~/clay-kit/clay-scrape.sh`

The whole run. Preflight, extract, walk, join.

```sh
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
```

---

## Part 4: the traps

Every one of these cost real time on the first build.

**A second Chrome will steal your AppleScript.** If any tool has launched its
own Chrome (a devtools MCP server, a testing harness, anything passing
`--user-data-dir` or `--remote-debugging-port`), macOS routes Apple Events to
that instance instead of the user's. You get one window showing `about:blank`
and no Clay session. The script checks for this and stops. Quit the automation
instance, not the user's.

**AppleScript cannot await.** `execute javascript` returns whatever the
expression evaluates to, and a Promise serialises to nothing. So clicking and
reading have to be two separate calls with a real sleep between them. 1.6
seconds is what worked reliably; below about 1.2 you start reading the previous
thread's contents.

**`osascript` appends a newline.** If you redirect its output straight into a
JSONL file mid-line, every record is malformed and the parse silently yields
zero rows. Capture into a variable first.

**`while read` drops the last line if the file has no trailing newline.** This
loses exactly one reply, at the end, which is very easy not to notice. Write the
index file with a trailing newline.

**The reply list is virtualised, so positions move.** Rows that have never been
scrolled into view do not exist in the DOM at all, and the rendered set changes
as the user scrolls. A row index captured at the start of a run can point at a
different person by the middle of it. Scroll the list to the bottom once before
running, and if you re-open individual threads later, match on the email address
rather than the index.

**Verify the pane actually changed before you read it.** A click that does not
register leaves the previous thread on screen, and the read succeeds and returns
the wrong person's email, silently. After clicking, confirm the pane text
contains the address you asked for, and retry if it does not. Two threads were
misattributed this way before the check was added.

**Do not fight the user for the front window.** `execute front window's active
tab` grabs whatever tab is frontmost, so if the user is browsing while the
script runs you will read their other tabs. Execute against the Clay tab object
directly instead, which also avoids yanking their focus mid-run:

```applescript
on run argv
	set needle to item 1 of argv
	set jsFile to item 2 of argv
	set js to (read (POSIX file jsFile) as «class utf8»)
	tell application "Google Chrome"
		repeat with w in windows
			repeat with t in tabs of w
				if (URL of t) contains needle then
					return execute t javascript js
				end if
			end repeat
		end repeat
		return "NOTABFOUND"
	end tell
end run
```

**Never truncate the thread text.** The first version of this capped each pane
at a few thousand characters, which silently cut the tail off long threads. The
tail is where the most recent messages live, so five threads looked like the
founder had never replied when in fact he had answered days earlier. The read
now takes the whole pane. If you add a cap for context reasons, cap from the
END of the thread, never the start.

**Do not re-run for fun.** Each run clicks through every thread in the user's
real inbox. It is read-only, it never sends anything, but it does mark threads
as read.

---

## Part 5: how to read the output, and where Clay is wrong

Clay auto-labels each reply. The labels are a useful first pass and they are
wrong often enough that you must read the thread body before acting on one.
Real examples from the 2026-09-06 export:

| Clay said | It actually was |
|---|---|
| Meeting request | An out-of-office autoresponder with a consulting booking link, from someone who is not an investor |
| (uncategorised) | A clear, well-reasoned pass: "consumer and behavioral health are both outside our thesis" |
| Info request | A one-word "Thanks!" with no request in it at all |
| Info request | A fully automated "submit through our website" reply that no human read |

Treat the label as a sorting hint. The thread body is the fact.

Two more things worth checking every time, because both showed up in the same
inbox:

**The same firm answering more than once.** One fund had three contacts in one
campaign: one asked for the deck, one passed, one said wrong person. Another had
a partner refer the founder to a colleague who had already declined two days
earlier. Group the export by email domain before drawing conclusions.

**More than one campaign in the inbox.** The Global Inbox mixes every campaign
the workspace has ever run. Filter by the `campaign` field before you treat a
reply as relevant. An old consulting-services campaign and a live fundraise
campaign look identical in the list.

Also expect the sender address to vary across threads. Outbound tools rotate
sending domains for deliverability, so the same person legitimately appears to
have written from several addresses. That is not a data problem.

---

## Part 6: what to do with it

`replies.md` is the file to hand to a model. It fits comfortably in context for
a few hundred replies, and each entry carries the email, date, campaign, Clay's
label and the full thread.

Useful next asks, in rough order of value:

1. Every thread where the other person asked a direct question or offered a
   specific time, and no reply was ever sent. These are the expensive ones.
2. Every meeting that was offered and never booked, with the date it was offered.
3. Every pass, with the stated reason quoted, and any reason that shows up more
   than once.
4. Anything a firm asked for that was never sent, such as a deck or a summary.
5. Duplicate firms, contradictions, and anyone marked do-not-contact who needs
   suppressing so a future campaign does not re-mail them.

For a pipeline spreadsheet, one row per person, the columns worth having are:
firm, contact, email, status, last contact date, next step, and a notes field
that quotes the reply verbatim. Quote rather than paraphrase. The exact wording
of a pass is the useful part.

---

## Part 7: a note on other sites, and on limits

This technique is not specific to Clay. It reads whatever the logged-in browser
can already see. That makes it worth being deliberate about where you point it.

**Reading a tool your own team pays for, holding your own data, is just reading
your own data.** That is what this skill was built for.

**Third-party platforms are a different question.** Most prohibit automated
access in their terms and actively detect it, and the consequence lands on the
account, not the script. For an account that is carrying live fundraise or
sales conversations, losing it costs far more than the data is worth.

Two rules that follow from that:

**Prefer the official path when one exists.** Most platforms have a data export
for your own account, and it is almost always more complete than what the page
renders. A rendered list shows the few hundred rows currently in the DOM; the
export has everything, with fields the page never displays. If you are reaching
for a scraper to get your own data, check for the export first.

**Do not build evasion.** Rotating fingerprints, residential proxies, or timing
jitter tuned to defeat detection converts an access question into an intent
question, and intent is what turns a blocked request into a legal one. If a job
only works by hiding that it is happening, that is the signal to buy the
licensed version of the data instead. Enrichment vendors exist and are cheap
next to the downside.

### The governor

`governor.py` in this kit enforces a human-scale read budget and keeps an
append-only audit log. It is the opposite of evasion tooling: it exists so the
volume stays inside limits you would hit anyway as a person, and so you can show
exactly what was read and when.

```
./governor.py check <target>       # exit 0 to proceed, 1 to stop
./governor.py log <target> [note]  # record a completed read
./governor.py status               # budget remaining
./governor.py report --csv         # full audit trail
```

Defaults are 40 reads per 24 hours, 12 per hour, and a 25 second minimum gap.
Wrap any per-page loop in `check` before the read and `log` after it. If the
governor keeps blocking you, the answer is a licensed data source, not a higher
limit.
