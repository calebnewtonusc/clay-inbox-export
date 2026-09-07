# Clay inbox export

Pull every reply out of a Clay campaign inbox, with the full email thread
attached, by driving the Chrome you are already logged into.

Clay's Global Inbox will not export thread bodies and its API does not cover the
inbox, so the replies are only readable inside an authenticated browser session.
This reads them and writes Markdown, CSV and JSON to disk. Nothing leaves the
machine.

## Use it

Hand [CLAY-INBOX-SKILL.md](CLAY-INBOX-SKILL.md) to Claude or Perplexity and say
"set this up and run it". The file contains every script inline, the three
things you have to click yourself, and the traps.

If you would rather run it directly:

```
git clone https://github.com/calebnewtonusc/clay-inbox-export.git ~/clay-kit
chmod +x ~/clay-kit/clay-scrape.sh
cd ~/clay-kit && ./clay-scrape.sh ~/clay-export
```

Then read `~/clay-export/replies.md`.

## Before the first run

1. Chrome: **View > Developer > Allow JavaScript from Apple Events**, ticked.
2. Your Clay inbox open in a normal Chrome tab, scrolled once so every row renders.
3. Approve the macOS "wants to control Google Chrome" prompt.

macOS and Google Chrome only. Read-only against Clay: it opens threads, it never
sends anything.

## Tested

107-reply inbox, 68 real replies, 0 failures, on 2026-09-06. Verified by
rebuilding the kit from the markdown alone and rerunning it clean.
