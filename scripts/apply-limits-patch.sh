#!/bin/sh
# Re-applies cth-hook-limits.patch to Munder Difflin's statusline hook, so the Notch Limits card stays live.
# Munder Difflin rewrites the hook on start, agent spawn and task writes; a LaunchAgent runs this on each rewrite.
# Idempotent: exits quietly when the patch is already in. Refuses (exit 1, logged) if the hook isn't the stock shim.
# Env: NOTCH_HIVE_ROOT (default ~/office/hive), NOTCH_LIMITS_LOG (default ~/Library/Logs/notch-limits-patch.log).
HIVE="${NOTCH_HIVE_ROOT:-$HOME/office/hive}"
HOOK="$HIVE/bin/cth-hook.cjs"
PATCH="$(cd "$(dirname "$0")" && pwd)/cth-hook-limits.patch"
LOG="${NOTCH_LIMITS_LOG:-$HOME/Library/Logs/notch-limits-patch.log}"
log() { /bin/mkdir -p "$(dirname "$LOG")"; echo "$(/bin/date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

[ -f "$HOOK" ] || { log "REFUSED: no hook at $HOOK"; exit 1; }
/usr/bin/grep -q 'Notch (OFF-18)' "$HOOK" && exit 0   # already patched: no log, so our own write is a silent no-op
/usr/bin/grep -q -- "--status" "$HOOK" || { log "REFUSED: $HOOK is not the stock shim (no --status mode)"; exit 1; }

TMP="$HOOK.notch-tmp.$$"
trap '/bin/rm -f "$TMP" "$TMP.orig" "$TMP.rej"' EXIT
/bin/cp -p "$HOOK" "$TMP" || { log "FAILED: copy $HOOK"; exit 1; }   # -p keeps the mode
# Exact context only (-F 0): if the anchor lines changed, refuse and leave the hook alone.
if ! /usr/bin/patch -s -f -F 0 --dry-run "$TMP" "$PATCH" >/dev/null 2>&1; then
    log "REFUSED: anchor not found in $HOOK (Munder Difflin changed the shim?); hook untouched"
    exit 1
fi
[ -e "$HOOK.bak" ] || /bin/cp -p "$HOOK" "$HOOK.bak"
/usr/bin/patch -s -f -F 0 "$TMP" "$PATCH" >/dev/null 2>&1 || { log "FAILED: patch $TMP"; exit 1; }
/bin/mv -f "$TMP" "$HOOK" || { log "FAILED: replace $HOOK"; exit 1; }
log "APPLIED: limits patch to $HOOK"
