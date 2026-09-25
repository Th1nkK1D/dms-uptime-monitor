# dms-uptime-monitor

DankMaterialShell (DMS) bar plugin: polls user-defined URLs, shows a signal-tower icon
with a status dot (none = no targets, green = all OK, red = some failing), sends a
desktop notification on unexpected HTTP status.

## Environment facts (NixOS, DMS 1.6.1)
- DMS QML source (read-only, canonical API reference): no longer in the Nix store; the running
  `dms` unpacks it to `/run/user/$UID/danklinux-shell/<hash>/` (only exists while DMS runs).
  Many `Widgets/*` and `Common/Proc.qml` are thin wrappers; the real code is under `DankCommon/`.
  - Plugin base classes: `Modules/Plugins/{PluginComponent,PluginSettings,PopoutComponent,ListSettingWithInput,...}.qml`
  - Theme colors: `Common/Theme.qml` (`Theme.success`, `Theme.error`, `Theme.primary`, `Theme.spacingM`, `Theme.cornerRadius`)
  - `Common/Proc.qml` → `Proc.runCommand(id, argv, (stdout, exitCode) => {}, debounceMs, timeoutMs)`; same `id` debounces calls
    *before* launch, but does **not** kill an already-running process — it only overwrites the stored callback, so a
    stale process delivers its output to the newest closure. Pass `null` as `id` for one entry per launch (auto-destroyed
    on completion). Timeout fires the callback with exit code 124 and kills the process.
  - Widgets: `Widgets/{DankIcon,StyledText,DankTextField,DankButton,DankDropdown,...}.qml`
- Reference plugins: `~/.config/DankMaterialShell/plugins/dockerManager` (Singleton service + popout),
  `.repos/*/DankBatteryAlerts` (notify-send), `.repos/*/DankGifSearch` (curl via Proc).
- Plugin settings are stored in `~/.config/DankMaterialShell/plugin_settings.json[pluginId]`;
  runtime state in `~/.local/state/DankMaterialShell/plugins/<pluginId>_state.json`.
- DMS runs as `systemctl --user dms.service`; logs: `journalctl --user -fu dms`.

## Dev commands
```bash
./dev.sh link      # symlink repo into ~/.config/DankMaterialShell/plugins/uptimeMonitor
./dev.sh watch     # auto-reload plugin on .qml/.json save (uses nix shell nixpkgs#watchexec)
./dev.sh reload    # dms ipc call plugins reload uptimeMonitor
./dev.sh status    # dms ipc call plugins status uptimeMonitor
./dev.sh logs      # journalctl --user -fu dms
./dev.sh fmt       # qmlformat -i *.qml
./dev.sh fmt-check # qmlformat -n *.qml (exit 1 if unformatted)
```
First time: Settings → Plugins → Scan for Plugins → enable → add "Uptime Monitor" to a bar section.

## Conventions
- No arbitrary comments. Only comment what the code cannot say itself: external quirks (curl flags,
  Qt/DMS behaviour), non-obvious framework contracts, or why a workaround exists. Never restate what
  the next line already reads as.
- Format QML with `qmlformat` (default settings, ships with `qt6.qtdeclarative`) — run `./dev.sh fmt`
  before committing. DMS's own source is qmlformat-clean, so defaults keep us identical to upstream style.
  `qmllint` is not used: it can't resolve DMS's `qs.*` imports (Quickshell aliases the shell root as `qs`
  at runtime), so every DMS singleton shows up as a false "unqualified access".
- HTTP via `curl -s -o /dev/null -w '%{http_code}' -X METHOD --connect-timeout 5 --max-time 15 --url URL`
  (no `-L`: expecting a 3xx must be possible; `--url` so a leading `-` isn't read as an option)
  (no XMLHttpRequest — matches ecosystem). Exit≠0 / code `000` = DOWN.
- Notifications: `Quickshell.execDetached(["notify-send","-a","Uptime Monitor","-u","critical",title,body])`.
- Poller lives in Singleton `UptimeService.qml` (registered in `qmldir`); widgets read it and call its
  actions (`checkAll`, `check`, `setPaused`). `results` is active endpoints only (drives the bar and
  offline detection); `displayResults` adds paused ones, in settings order, for the popout.
- Target schema: `{ id, label, url, method:"GET", expect:"2xx", headers:"", body:"", paused:false }` under settings
  key `targets`. `expect` is comma-separated codes or `x`-wildcard classes (`"200, 2xx"`), normalized by
  `UptimeService.normalizeExpect`. `headers` is newline-separated `Name: value`; headers/body are optional strings.
- Poll interval is global, not per-target: settings key `period` (seconds, min 5, default 60).
- Don't *re-declare* injected props (`pluginId`, `pluginService`, `pluginData`) in PluginComponent/PluginSettings.
  But `PluginSettings.pluginId` is `required` and the settings Loader does not set it — you must assign
  `pluginId: UptimeService.pluginId`, or the settings accordion silently loads nothing (height 0).
- Commits: a single conventional-commit subject line (`fix:`, `feat:`, `docs:`), no body. Name the concrete
  changes, not a vague summary — e.g. `fix: allow expecting 3xx, block offline refresh, keep new endpoint cards`.
