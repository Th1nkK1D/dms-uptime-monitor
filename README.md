# DMS Uptime Monitor

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) bar plugin that polls
your URLs on a schedule and tells you when one stops answering the way it should.

The bar shows a signal-tower icon with a status dot:

| Dot         | Meaning                                        |
| ----------- | ---------------------------------------------- |
| none        | no targets configured                          |
| green       | every target returned its expected status      |
| yellow      | a target failed and is being retried           |
| red + count | that many targets are confirmed down           |

A failed check does not mean down yet: the target turns yellow and is retried a configured number
of times first. A critical desktop notification fires only once those retries are exhausted, and an
optional one when it recovers.

## Requirements

- DankMaterialShell >= 1.5.0
- `curl`

## Install

```bash
git clone https://github.com/Th1nkK1D/dms-uptime-monitor.git
ln -s "$PWD/dms-uptime-monitor" ~/.config/DankMaterialShell/plugins/uptimeMonitor
```

Then in DMS: **Settings → Plugins → Scan for Plugins**, enable _Uptime Monitor_, and add it to a
bar section under **Settings → Dank Bar**.

## Configure

**Settings → Plugins → Uptime Monitor** opens the endpoint editor. Each endpoint has:

| Field      | Meaning                               | Default |
| ---------- | ------------------------------------- | ------- |
| Label      | shown in notifications and the popout | —       |
| URL        | what to request                       | —       |
| Method     | GET, HEAD, POST, PUT, DELETE          | GET     |
| Expect     | the HTTP status that means healthy    | 200     |

**Test** runs the check immediately using the values currently in the card — including unsaved
ones — and reports `HTTP 200 · 143 ms` or `HTTP 500, expected 200` inline.

The tune button on each card opens optional **request headers** and a **request body**. Headers are
one `Name: value` per line; lines that are blank or have no colon are ignored. The button turns
accent-coloured when an endpoint has either set.

Both are sent as typed, with no content type guessed for you — curl defaults to
`application/x-www-form-urlencoded`, so add `Content-Type: application/json` yourself when posting
JSON. A body is allowed on any method except HEAD, including GET — the method is always passed
explicitly, so curl won't silently rewrite a GET-with-body into a POST.

Each card also has up/down arrows to set the order endpoints appear in, and a delete button.

**Check interval** (seconds between checks, minimum 5), **Request timeout** (3–300 s), **Retries
before down** (extra attempts after a failed check, 0 disables retrying) and **Retry delay**
(seconds between those retries) sit above the list and apply to every endpoint. Below it: **Show URL in popout** (on by default), **Failing
endpoints first** (on by default — lifts failing endpoints to the top of the popout, keeping your
manual order within each group) and **Notify on recovery** (on by default).

Click the bar icon for a popout listing every target with its last status code and latency. The
header carries the shared cadence and freshness — `every 1m · checked 12s ago` — since all
endpoints run on one interval. The header's refresh button rechecks everything.

## How it works

Checks run through `curl -s -o /dev/null -w '%{http_code} %{time_total}'`, so nothing but the
status line is downloaded (`HEAD` uses `--head`). A non-zero curl exit or a `000` status is
treated as unreachable, and exit 124 as a timeout.

A failing target enters the warning state and is rechecked every **Retry delay** seconds, off the
shared poll cycle, until it either answers as expected — back to green, no notification — or uses
up its retries and is declared down. While it is down it is no longer retried out of band; the
normal poll cycle picks it back up.

The poller lives in a QML singleton (`UptimeService.qml`) rather than in the widget, so it runs
once no matter how many monitors show the bar. Results persist to
`~/.local/state/DankMaterialShell/plugins/uptimeMonitor_state.json`, which is how a restart
avoids re-notifying you about a target that was already down.

## Development

```bash
./dev.sh link       # symlink this repo into the DMS plugins directory
./dev.sh watch      # reload the plugin on save
./dev.sh reload     # reload once
./dev.sh status     # is it loaded?
./dev.sh logs       # journalctl --user -fu dms
./dev.sh fmt        # qmlformat -i *.qml
./dev.sh fmt-check  # fail if anything is unformatted
```

Editing `UptimeService.qml` needs a full `systemctl --user restart dms` — QML caches singletons
per engine, so `plugins reload` only picks up widget and settings changes.

See `CLAUDE.md` for API notes and `PLAN.md` for the design.

## License

MIT — see [LICENSE](LICENSE).
