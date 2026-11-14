#!/usr/bin/env bash
# AI Spend Bar installer. Safe to re-run (re-running repairs the install).
#   curl -fsSL https://raw.githubusercontent.com/crearo/ai-spend-bar/main/install.sh | bash
#   bash install.sh [--dry-run] [--uninstall]
set -euo pipefail

APP_NAME="AI Spend Bar.app"
# The internal app ID keeps its original name so settings and the login item carry over.
APP_ID="com.verycuteapps.ai-usage-bar"
APP_DIR="$HOME/Applications"
APP_PATH="$APP_DIR/$APP_NAME"
APP_BIN="$APP_PATH/Contents/MacOS/AISpendBar"
# The app was called "AI Usage Bar" before the rename.
OLD_APP_PATH="$APP_DIR/AI Usage Bar.app"
OLD_APP_BIN="$OLD_APP_PATH/Contents/MacOS/AIUsageBar"
PLUGIN_NAME="ai-usage.15s.sh"
SB_DOMAIN="com.ameba.SwiftBar"
OLD_PLIST="$HOME/Library/LaunchAgents/com.verycuteapps.ai-usage-bar.plist"
OLD_CLONE="$HOME/.ai-usage-bar"

DRY_RUN=0
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) echo "Usage: bash install.sh [--dry-run] [--uninstall]"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\nError: %s\n' "$*" >&2; exit 1; }
# Run a state-changing command, or just print it in dry-run mode.
run() {
  if (( DRY_RUN )); then printf '    [dry-run] %s\n' "$*"; else "$@"; fi
}
# Same, but ignore output and errors.
runq() {
  if (( DRY_RUN )); then printf '    [dry-run] %s\n' "$*"; else "$@" >/dev/null 2>&1 || true; fi
}

[[ "$(uname -s)" == Darwin ]] || die "AI Spend Bar only works on macOS."
(( DRY_RUN )) && echo "Dry run: nothing will be changed."

SCRIPT_DIR=""
src="${BASH_SOURCE[0]:-}"
[[ -n "$src" && -f "$src" ]] && SCRIPT_DIR="$(cd "$(dirname "$src")" && pwd -P)"
ZIP="${SCRIPT_DIR:+$SCRIPT_DIR/dist/AI-Spend-Bar.zip}"

quit_app() {
  if pgrep -f "/Contents/MacOS/AI(Spend|Usage)Bar" >/dev/null 2>&1; then
    info "Quitting the running app"
    runq osascript -e "quit app id \"$APP_ID\""
    (( DRY_RUN )) || sleep 1
  fi
}

# Is this directory a copy of our old swiftbar plugin folder?
is_our_plugin_dir() {
  local d="$1"
  [[ -f "$d/.ai-usage-git-update.zsh" ]] && return 0
  [[ -f "$d/$PLUGIN_NAME" && ! -L "$d/$PLUGIN_NAME" ]] && grep -qE "AI Usage|AI Spend Bar" "$d/$PLUGIN_NAME" 2>/dev/null
}

# Clean up the old SwiftBar plugin version, if present.
# Remove the app from before the rename ("AI Usage Bar.app"). Its login item points at the old
# path, so turn that off and let the new app register itself again on first launch.
remove_old_app() {
  [[ -e "$OLD_APP_PATH" ]] || return 0
  info "Replacing the old AI Usage Bar app"
  [[ -x "$OLD_APP_BIN" ]] && runq "$OLD_APP_BIN" --unregister-login
  run rm -rf "$OLD_APP_PATH"
  runq defaults delete "$APP_ID" didAutoRegisterLogin
}

migrate_swiftbar() {
  local found=0 pd dir
  if [[ -f "$OLD_PLIST" ]] || launchctl print "gui/$(id -u)/$APP_ID" >/dev/null 2>&1; then
    found=1
    info "Removing the old start-at-login LaunchAgent"
    runq launchctl bootout "gui/$(id -u)" "$OLD_PLIST"
    run rm -f "$OLD_PLIST"
  fi
  pd="$(defaults read "$SB_DOMAIN" PluginDirectory 2>/dev/null || true)"
  if [[ -n "$pd" ]]; then
    dir="${pd/#\~/$HOME}"
    if [[ -L "$dir/$PLUGIN_NAME" && "$(readlink "$dir/$PLUGIN_NAME")" == *"/swiftbar/$PLUGIN_NAME" ]]; then
      found=1
      info "Removing our plugin link from SwiftBar's plugin folder ($pd)"
      run rm -f "$dir/$PLUGIN_NAME"
    elif is_our_plugin_dir "$dir"; then
      found=1
      info "SwiftBar's plugin folder is the old AI Usage Bar plugin folder ($pd); resetting it and quitting SwiftBar"
      run defaults delete "$SB_DOMAIN" PluginDirectory
      runq osascript -e 'quit app "SwiftBar"'
    fi
  fi
  if (( found )); then
    info "SwiftBar is no longer needed. Remove it if you don't use it for anything else."
  else
    info "Nothing to clean up."
  fi
  [[ -d "$OLD_CLONE" ]] && info "The old code at $OLD_CLONE isn't used anymore; you can delete it: rm -rf \"$OLD_CLONE\""
  return 0
}

# ---------------------------------------------------------------- uninstall
if (( UNINSTALL )); then
  step "Turning off start at login"
  if [[ -x "$APP_BIN" ]]; then
    runq "$APP_BIN" --unregister-login
  else
    info "App not found at $APP_PATH"
  fi
  [[ -x "$OLD_APP_BIN" ]] && runq "$OLD_APP_BIN" --unregister-login
  step "Removing the app"
  quit_app
  if [[ -e "$APP_PATH" ]]; then run rm -rf "$APP_PATH"; else info "Already removed."; fi
  [[ -e "$OLD_APP_PATH" ]] && run rm -rf "$OLD_APP_PATH"
  # Settings and cache too, so a later reinstall starts fresh (and turns start at login on again).
  info "Removing settings and cache"
  runq defaults delete "$APP_ID"
  run rm -rf "$HOME/Library/Caches/$APP_ID"
  step "Cleaning up the old SwiftBar version"
  migrate_swiftbar
  step "Left in place"
  info "Node.js (if you installed it for this)"
  echo; echo "AI Spend Bar is uninstalled."
  exit 0
fi

# ---------------------------------------------------------------- install
step "1/5 macOS version"
ver="$(sw_vers -productVersion)"
(( ${ver%%.*} >= 13 )) || die "AI Spend Bar needs macOS 13 (Ventura) or newer. This Mac has $ver."
info "macOS $ver"

step "2/5 Node.js"
if command -v node >/dev/null 2>&1; then
  info "Found node $(node --version)"
elif command -v brew >/dev/null 2>&1; then
  info "Installing Node.js with Homebrew"
  run brew install node
else
  die "Node.js is required. Install it from https://nodejs.org (or install Homebrew and re-run), then run this again."
fi

step "3/5 Installing the app"
if [[ -z "$ZIP" || ! -f "$ZIP" ]]; then
  info "Getting the latest release with npx"
  if (( DRY_RUN )); then
    run npx --yes ai-spend-bar@latest
    exit 0
  fi
  exec npx --yes ai-spend-bar@latest
fi
quit_app
remove_old_app
run mkdir -p "$APP_DIR"
[[ -e "$APP_PATH" ]] && { info "Replacing $APP_PATH"; run rm -rf "$APP_PATH"; }
run ditto -x -k "$ZIP" "$APP_DIR"
info "Installed $APP_PATH"

step "4/5 Cleaning up the old SwiftBar version"
migrate_swiftbar

step "5/5 Starting AI Spend Bar"
run open "$APP_PATH"

cat <<MSG

Done. AI Spend Bar is installed at $APP_PATH
  Look for "AI \$…" in your menu bar.
  It starts at login (toggle it in the panel). macOS may show a "Login item added" notice.

Uninstall: npx ai-spend-bar uninstall
MSG
