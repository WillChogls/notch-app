#!/bin/sh
# install-limits-watcher.sh install|uninstall
# Loads (or removes) a LaunchAgent that re-applies the Limits hook patch whenever Munder Difflin rewrites the hook.
# Env: NOTCH_HIVE_ROOT (default ~/office/hive), NOTCH_WATCHER_LABEL (default dev.notch.limits-patch; set one for test copies).
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="${NOTCH_WATCHER_LABEL:-dev.notch.limits-patch}"
HIVE="${NOTCH_HIVE_ROOT:-$HOME/office/hive}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
case "${1:-}" in
install)
    [ -f "$HIVE/bin/cth-hook.cjs" ] || { echo "No hook at $HIVE/bin/cth-hook.cjs" >&2; exit 1; }
    mkdir -p "$HOME/Library/LaunchAgents"
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    sed -e "s#__LABEL__#$LABEL#g" -e "s#__SCRIPT__#$DIR/apply-limits-patch.sh#g" -e "s#__HIVE__#$HIVE#g" \
        "$DIR/dev.notch.limits-patch.plist" > "$PLIST"
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "Installed $LABEL, watching $HIVE/bin/cth-hook.cjs"
    ;;
uninstall)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "Removed $LABEL"
    ;;
*) echo "usage: $0 install|uninstall" >&2; exit 2 ;;
esac
