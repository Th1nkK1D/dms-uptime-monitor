# dms-uptime-monitor

DankMaterialShell (DMS) bar plugin: polls user-defined URLs, shows a signal-tower icon
with a status dot (none = no targets, green = all OK, red = some failing), sends a
desktop notification on unexpected HTTP status. Full design: `PLAN.md`.

## Environment facts (NixOS, DMS 1.5.3)
- DMS QML source (read-only, canonical API reference):
  `$(dirname $(readlink -f $(which dms)))/../share/quickshell/dms/`
  - Plugin base classes: `Modules/Plugins/{PluginComponent,PluginSettings,PopoutComponent,ListSettingWithInput,...}.qml`
  - Theme colors: `Common/Theme.qml` (`Theme.success`, `Theme.error`, `Theme.primary`, `Theme.spacingM`, `Theme.cornerRadius`)
  - `Common/Proc.qml` → `Proc.runCommand(id, argv, (stdout, exitCode) => {}, debounceMs, timeoutMs)`; same `id` debounces/cancels previous call
  - Widgets: `Widgets/{DankIcon,StyledText,DankTextField,DankButton,DankDropdown,...}.qml`
- Reference plugins: `~/.config/DankMaterialShell/plugins/dockerManager` (Singleton service + popout),
  `.repos/*/DankBatteryAlerts` (notify-send), `.repos/*/DankGifSearch` (curl via Proc).
- Plugin settings are stored in `~/.config/DankMaterialShell/plugin_settings.json[pluginId]`;
  runtime state in `~/.config/DankMaterialShell/<pluginId>_state.json`.
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
- Format QML with `qmlformat` (default settings, ships with `qt6.qtdeclarative`) — run `./dev.sh fmt`
  before committing. DMS's own source is qmlformat-clean, so defaults keep us identical to upstream style.
  `qmllint` is not used: it can't resolve DMS's `qs.*` imports (Quickshell aliases the shell root as `qs`
  at runtime), so every DMS singleton shows up as a false "unqualified access".
- HTTP via `curl -s -o /dev/null -w '%{http_code}' -X METHOD --connect-timeout 5 --max-time 15 URL`
  (no XMLHttpRequest — matches ecosystem). Exit≠0 / code `000` = DOWN.
- Notifications: `Quickshell.execDetached(["notify-send","-a","Uptime Monitor","-u","critical",title,body])`.
- Poller lives in Singleton `UptimeService.qml` (registered in `qmldir`), widgets only read it.
- Target schema: `{ id, label, url, method:"GET", period:60, expect:200, headers:"", body:"" }`
  under settings key `targets`. `headers` is newline-separated `Name: value`; both are optional strings.
- Don't *re-declare* injected props (`pluginId`, `pluginService`, `pluginData`) in PluginComponent/PluginSettings.
  But `PluginSettings.pluginId` is `required` and the settings Loader does not set it — you must assign
  `pluginId: UptimeService.pluginId`, or the settings accordion silently loads nothing (height 0).
