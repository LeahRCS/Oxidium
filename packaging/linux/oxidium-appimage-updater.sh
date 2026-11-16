#!/bin/sh
# Oxidium AppImage update bridge.
#
# Horizon-Free is the upstream release clock. CI converts each launcher@X.Y.Z
# release into a tested Oxidium build and publishes it in LeahRCS/Oxidium.
# Installed AppImages update from that converted release, never from a raw
# upstream binary: replacing the launcher with an unmodified Horizon-Free
# executable would discard Oxidium's source-level overlay.
set -u

SELF="${APPIMAGE:-}"
BIN="${OXIDIUM_LAUNCHER_BIN:-}"
ASSET="${OXIDIUM_APPIMAGE_ASSET:-oxidium-linux-x86_64.AppImage}"
REPO="${OXIDIUM_UPDATE_REPO:-LeahRCS/Oxidium}"
API="${OXIDIUM_UPDATE_API:-https://api.github.com/repos/$REPO/releases/latest}"
SKIP="${OXIDIUM_SKIP_UPDATE:-0}"

log_dir=""
if [ -n "${XDG_STATE_HOME:-}" ]; then
  log_dir="$XDG_STATE_HOME/oxidium"
elif [ -n "${HOME:-}" ]; then
  log_dir="$HOME/.local/state/oxidium"
fi
if [ -n "$log_dir" ]; then
  mkdir -p "$log_dir" 2>/dev/null || true
fi
LOG="${OXIDIUM_UPDATE_LOG:-${log_dir:+$log_dir/appimage-update.log}}"

log() {
  line="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'unknown-time') $*"
  printf '%s\n' "Oxidium updater: $*" >&2
  if [ -n "$LOG" ]; then printf '%s\n' "$line" >>"$LOG" 2>/dev/null || true; fi
}

cleanup=""
unlock=""
finish() {
  [ -z "$cleanup" ] || rm -rf "$cleanup" 2>/dev/null || true
  [ -z "$unlock" ] || rm -rf "$unlock" 2>/dev/null || true
}
trap finish 0 HUP INT TERM

# The launcher itself handles these without needing a network check.
case "${1:-}" in
  --version|-V|--help|-h|desktop-entry) exit 0 ;;
esac

[ "$SKIP" != 1 ] || exit 0
[ -n "$SELF" ] || exit 0
[ -n "$BIN" ] || exit 0
[ -f "$SELF" ] || exit 0
[ -w "$SELF" ] || { log "AppImage is read-only; update skipped: $SELF"; exit 0; }

for tool in curl sha256sum sed awk chmod cp mv mkdir rm dirname head cat; do
  command -v "$tool" >/dev/null 2>&1 || { log "$tool is unavailable; update skipped"; exit 0; }
done

# A directory lock works without flock and disappears after a normal exit.
unlock="${SELF}.update.lock"
if ! mkdir "$unlock" 2>/dev/null; then
  owner="$(cat "$unlock/pid" 2>/dev/null || true)"
  if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
    rm -rf "$unlock" 2>/dev/null || true
    mkdir "$unlock" 2>/dev/null || {
      log "stale update lock could not be recovered; update skipped"
      unlock=""
      exit 0
    }
  else
    log "another updater owns $unlock; update skipped"
    unlock=""
    exit 0
  fi
fi
printf '%s\n' "$" >"$unlock/pid" 2>/dev/null || true

CURRENT="$("$BIN" --version 2>/dev/null | sed -n 's/^horizon-launcher[[:space:]]\+//p' | head -n1)"
[ -n "$CURRENT" ] || { log "could not read the embedded launcher version"; exit 0; }

META="$(curl -fsSL --connect-timeout 8 --max-time 20 \
  -H 'Accept: application/vnd.github+json' "$API" 2>/dev/null || true)"
TAG="$(printf '%s' "$META" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
case "$TAG" in
  launcher@*) LATEST=${TAG#launcher@} ;;
  launcher-v*) LATEST=${TAG#launcher-v} ;;
  *) LATEST="" ;;
esac

[ -n "$LATEST" ] || { log "release metadata did not contain a launcher tag; keeping $CURRENT"; exit 0; }

# Mirror releases are semver today. Never replace a newer/dev build with an older public release.
version_newer() {
  awk -v candidate="$1" -v current="$2" 'BEGIN {
    sub(/-.*/, "", candidate); sub(/-.*/, "", current);
    nc=split(candidate, c, "."); no=split(current, o, ".");
    n=(nc>no?nc:no);
    for (i=1; i<=n; i++) {
      cv=(i<=nc ? c[i]+0 : 0); ov=(i<=no ? o[i]+0 : 0);
      if (cv>ov) exit 0;
      if (cv<ov) exit 1;
    }
    exit 1;
  }'
}
version_newer "$LATEST" "$CURRENT" || exit 0

base="https://github.com/$REPO/releases/download/$TAG"
dir="$(dirname "$SELF")"
cleanup="$dir/.oxidium-update.$$"
rm -rf "$cleanup" 2>/dev/null || true
mkdir "$cleanup" || { log "cannot create update staging directory beside AppImage"; exit 0; }

candidate="$cleanup/$ASSET"
sums="$cleanup/SHA256SUMS"

log "updating $CURRENT -> $LATEST from $REPO"
if ! curl -fL --retry 2 --connect-timeout 10 --max-time 300 "$base/$ASSET" -o "$candidate"; then
  log "could not download $ASSET; keeping $CURRENT"
  exit 0
fi
if ! curl -fL --retry 2 --connect-timeout 10 --max-time 60 "$base/SHA256SUMS" -o "$sums"; then
  log "could not download SHA256SUMS; keeping $CURRENT"
  exit 0
fi

expected="$(awk -v asset="$ASSET" '$2 == asset || $2 == ("*" asset) { print $1; exit }' "$sums")"
[ -n "$expected" ] || { log "SHA256SUMS has no entry for $ASSET"; exit 0; }
actual="$(sha256sum "$candidate" | awk '{print $1}')"
[ "$actual" = "$expected" ] || { log "checksum mismatch for $ASSET"; exit 0; }

chmod 755 "$candidate" 2>/dev/null || true
GOT="$(OXIDIUM_SKIP_UPDATE=1 HORIZON_LAUNCHER_NO_SELF_UPDATE=1 \
  "$candidate" --appimage-extract-and-run --version 2>/dev/null \
  | sed -n 's/^horizon-launcher[[:space:]]\+//p' | head -n1)"
[ "$GOT" = "$LATEST" ] || {
  log "candidate reports '${GOT:-unknown}', expected $LATEST; keeping $CURRENT"
  exit 0
}

backup="${SELF}.previous"
backup_tmp="${backup}.tmp.$$"
if ! cp -p "$SELF" "$backup_tmp" 2>/dev/null; then
  log "could not create rollback copy; keeping $CURRENT"
  exit 0
fi
if ! mv -f "$backup_tmp" "$backup"; then
  rm -f "$backup_tmp" 2>/dev/null || true
  log "could not commit rollback copy; keeping $CURRENT"
  exit 0
fi

# Candidate is staged beside the target, so rename is atomic on the same filesystem.
target_tmp="${SELF}.new.$$"
if ! mv -f "$candidate" "$target_tmp" || ! mv -f "$target_tmp" "$SELF"; then
  rm -f "$target_tmp" 2>/dev/null || true
  if [ -f "$backup" ]; then cp -p "$backup" "$SELF" 2>/dev/null || true; fi
  log "atomic replacement failed; restored the previous AppImage"
  exit 0
fi
chmod 755 "$SELF" 2>/dev/null || true
log "installed $LATEST; rollback copy: $backup"

# Keep the exact path (important for GearLever and .desktop integrations) and restart.
trap - 0 HUP INT TERM
rm -rf "$cleanup" 2>/dev/null || true
rm -rf "$unlock" 2>/dev/null || true
cleanup=""
unlock=""
OXIDIUM_SKIP_UPDATE=1 HORIZON_LAUNCHER_NO_SELF_UPDATE=1 exec "$SELF" "$@"

# exec only returns when the new image cannot start. Restore the backup immediately.
if [ -f "$backup" ]; then
  cp -p "$backup" "$SELF" 2>/dev/null || true
  chmod 755 "$SELF" 2>/dev/null || true
  log "new AppImage failed to start; rollback restored"
  OXIDIUM_SKIP_UPDATE=1 HORIZON_LAUNCHER_NO_SELF_UPDATE=1 exec "$SELF" "$@"
fi
exit 1
