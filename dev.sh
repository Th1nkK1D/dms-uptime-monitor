#!/usr/bin/env bash
set -euo pipefail
PLUGIN_ID=uptimeMonitor
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINK="$HOME/.config/DankMaterialShell/plugins/$PLUGIN_ID"

case "${1:-}" in
  link)   ln -sfn "$REPO" "$LINK" && echo "linked $LINK -> $REPO" ;;
  reload) dms ipc call plugins reload "$PLUGIN_ID" ;;
  status) dms ipc call plugins status "$PLUGIN_ID" ;;
  logs)   journalctl --user -fu dms ;;
  watch)  exec nix shell nixpkgs#watchexec -c watchexec -w "$REPO" -e qml,json,js \
            -- dms ipc call plugins reload "$PLUGIN_ID" ;;
  fmt)    qmlformat -i "$REPO"/*.qml && echo "formatted" ;;
  fmt-check)
    rc=0
    for f in "$REPO"/*.qml; do
      qmlformat "$f" | diff -u "$f" - || rc=1
    done
    [ $rc -eq 0 ] && echo "all formatted"
    exit $rc ;;
  *) echo "usage: $0 {link|watch|reload|status|logs|fmt|fmt-check}"; exit 1 ;;
esac
