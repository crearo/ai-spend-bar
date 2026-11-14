#!/bin/zsh
# Manage a LaunchAgent that opens SwiftBar at login.
# Usage: .ai-usage-login.zsh status|enable|disable
# SwiftBar's own "Launch at Login" can't be read/set from a script, so we keep our own.
# Set AI_USAGE_LOGIN_SKIP_LAUNCHCTL=1 to skip launchctl (for testing).

LABEL="com.verycuteapps.ai-usage-bar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

find_swiftbar() {
  local p
  for p in /Applications/SwiftBar.app "$HOME/Applications/SwiftBar.app"; do
    [[ -d "$p" ]] && { print -r -- "$p"; return 0; }
  done
  (( ${+AI_USAGE_LOGIN_NO_MDFIND} )) && return 1
  p="$(mdfind "kMDItemCFBundleIdentifier == 'com.ameba.SwiftBar'" 2>/dev/null | head -n 1)"
  [[ -n "$p" && -d "$p" ]] && { print -r -- "$p"; return 0; }
  return 1
}

run_launchctl() {
  [[ "${AI_USAGE_LOGIN_SKIP_LAUNCHCTL:-}" == 1 ]] && return 0
  launchctl "$@" >/dev/null 2>&1
}

case "${1:-status}" in
  status)
    if [[ -f "$PLIST" ]] && find_swiftbar >/dev/null; then
      echo enabled
    else
      echo disabled
    fi
    ;;
  enable)
    app="$(find_swiftbar)" || app="SwiftBar"
    mkdir -p "${PLIST:h}"
    cat > "$PLIST.tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>${app//&/&amp;}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF
    mv -f "$PLIST.tmp" "$PLIST" || exit 1
    # Re-bootstrap so an edited plist takes effect; "already loaded" errors are ignored.
    # RunAtLoad runs `open -a SwiftBar`, which is a no-op if SwiftBar is already running.
    run_launchctl bootout "gui/$(id -u)/$LABEL"
    run_launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo enabled
    ;;
  disable)
    run_launchctl bootout "gui/$(id -u)/$LABEL"
    rm -f "$PLIST"
    echo disabled
    ;;
  *)
    echo "usage: ${0:t} status|enable|disable" >&2
    exit 2
    ;;
esac
exit 0
