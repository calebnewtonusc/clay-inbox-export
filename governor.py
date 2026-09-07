#!/usr/bin/env python3
"""Read budget governor and audit log.

Keeps browser-driven page reads inside a human-scale budget and writes an
append-only record of every read. This is the opposite of evasion tooling: it
exists so the volume stays defensible and so you can show exactly what was
read, when, and why.

  governor.py check <target>     exit 0 if a read is allowed, 1 if not
  governor.py log <target> [note]  record a completed read
  governor.py status             budget remaining, today and this hour
  governor.py report [--csv]     the full audit trail
"""
import json, sys, os, time, csv, datetime as dt

STATE = os.path.expanduser("~/clay-kit/read-log.jsonl")
DAILY_MAX  = 40    # profile reads per rolling 24h
HOURLY_MAX = 12    # per rolling hour
MIN_GAP_S  = 25    # minimum seconds between reads

def load():
    if not os.path.exists(STATE): return []
    out = []
    for line in open(STATE):
        line = line.strip()
        if line:
            try: out.append(json.loads(line))
            except Exception: pass
    return out

def recent(rows, seconds):
    cut = time.time() - seconds
    return [r for r in rows if r.get("ts", 0) >= cut]

def check(target):
    rows = load()
    day, hour = recent(rows, 86400), recent(rows, 3600)
    reasons = []
    if len(day) >= DAILY_MAX:
        reasons.append(f"daily budget spent ({len(day)}/{DAILY_MAX} in 24h)")
    if len(hour) >= HOURLY_MAX:
        reasons.append(f"hourly budget spent ({len(hour)}/{HOURLY_MAX} in 1h)")
    if rows:
        gap = time.time() - max(r.get("ts", 0) for r in rows)
        if gap < MIN_GAP_S:
            reasons.append(f"too soon, wait {MIN_GAP_S - int(gap)}s")
    if reasons:
        print("BLOCKED: " + "; ".join(reasons)); return 1
    print(f"OK  day {len(day)}/{DAILY_MAX}  hour {len(hour)}/{HOURLY_MAX}  -> {target}")
    return 0

def log(target, note=""):
    rec = {"ts": time.time(),
           "at": dt.datetime.now().isoformat(timespec="seconds"),
           "target": target, "note": note}
    with open(STATE, "a") as f: f.write(json.dumps(rec) + "\n")
    print("logged", target)
    return 0

def status():
    rows = load()
    day, hour = recent(rows, 86400), recent(rows, 3600)
    print(f"reads in last 24h : {len(day)}/{DAILY_MAX}")
    print(f"reads in last 1h  : {len(hour)}/{HOURLY_MAX}")
    print(f"total logged      : {len(rows)}")
    if rows:
        last = max(rows, key=lambda r: r.get("ts", 0))
        print(f"last read         : {last['at']}  {last['target']}")
    return 0

def report(as_csv=False):
    rows = sorted(load(), key=lambda r: r.get("ts", 0))
    if as_csv:
        w = csv.writer(sys.stdout); w.writerow(["at", "target", "note"])
        for r in rows: w.writerow([r.get("at",""), r.get("target",""), r.get("note","")])
    else:
        for r in rows: print(f"{r.get('at',''):20} {r.get('target',''):50} {r.get('note','')}")
        print(f"\n{len(rows)} reads logged")
    return 0

if __name__ == "__main__":
    a = sys.argv[1:]
    if not a: print(__doc__); sys.exit(0)
    cmd = a[0]
    if   cmd == "check"  and len(a) > 1: sys.exit(check(a[1]))
    elif cmd == "log"    and len(a) > 1: sys.exit(log(a[1], " ".join(a[2:])))
    elif cmd == "status":                sys.exit(status())
    elif cmd == "report":                sys.exit(report("--csv" in a))
    else: print(__doc__); sys.exit(2)
