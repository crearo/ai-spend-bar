#!/usr/bin/env bash
# AI Usage Bar installer. Safe to re-run (re-running repairs the install).
#   curl -fsSL https://raw.githubusercontent.com/crearo/ai-usage-bar/main/install.sh | bash
#   bash install.sh [--dry-run] [--uninstall]
set -euo pipefail

REPO_URL="https://github.com/crearo/ai-usage-bar"
TARBALL_URL="https://codeload.github.com/crearo/ai-usage-bar/tar.gz/refs/heads/main"
DEFAULT_DIR="$HOME/.ai-usage-bar"
PLUGIN_NAME="ai-usage.15s.sh"
SB_DOMAIN="com.ameba.SwiftBar"

DRY_RUN=0
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n '2,4p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null; echo "Options: --dry-run, --uninstall"; exit 0 ;;
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

[[ "$(uname -s)" == Darwin ]] || die "AI Usage Bar only works on macOS."
(( DRY_RUN )) && echo "Dry run: nothing will be changed."

find_swiftbar() {
  local p
  for p in /Applications/SwiftBar.app "$HOME/Applications/SwiftBar.app"; do
    [[ -d "$p" ]] && { echo "$p"; return 0; }
  done
  p="$(mdfind "kMDItemCFBundleIdentifier == '$SB_DOMAIN'" 2>/dev/null | head -n 1 || true)"
  [[ -n "$p" && -d "$p" ]] && { echo "$p"; return 0; }
  return 1
}

git_usable() {
  command -v git >/dev/null 2>&1 || return 1
  # /usr/bin/git is a stub that pops up the Xcode tools dialog unless tools are installed.
  [[ "$(command -v git)" != /usr/bin/git ]] && return 0
  xcode-select -p >/dev/null 2>&1
}

# Is this script running from inside a git clone of this repo? (Not via curl|bash or the npm cache.)
detect_clone() {
  local src="${BASH_SOURCE[0]:-}" dir top remote
  [[ -n "$src" && -f "$src" ]] || return 1
  dir="$(cd "$(dirname "$src")" && pwd -P)"
  [[ -d "$dir/.git" && -f "$dir/swiftbar/$PLUGIN_NAME" ]] || return 1
  git_usable || return 1
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$top" && "$(cd "$top" && pwd -P)" == "$dir" ]] || return 1
  remote="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
  [[ "$remote" == *crearo/ai-usage-bar* ]] || return 1
  echo "$dir"
}

plugin_dir_pref() { defaults read "$SB_DOMAIN" PluginDirectory 2>/dev/null || true; }
abspath() { (cd "$1" 2>/dev/null && pwd -P) || echo "$1"; }

# ---------------------------------------------------------------- uninstall
if (( UNINSTALL )); then
  REPO="$(detect_clone || echo "$DEFAULT_DIR")"
  step "Turning off start at login"
  if [[ -f "$REPO/swiftbar/.ai-usage-login.zsh" ]]; then
    run zsh "$REPO/swiftbar/.ai-usage-login.zsh" disable
  else
    plist="$HOME/Library/LaunchAgents/com.verycuteapps.ai-usage-bar.plist"
    run launchctl bootout "gui/$(id -u)/com.verycuteapps.ai-usage-bar" 2>/dev/null || true
    run rm -f "$plist"
  fi

  step "Removing plugin link"
  pd="$(plugin_dir_pref)"
  link="${pd/#\~/$HOME}/$PLUGIN_NAME"
  if [[ -n "$pd" && -L "$link" && "$(readlink "$link")" == *"/swiftbar/$PLUGIN_NAME" ]]; then
    run rm -f "$link"
  else
    info "No symlink of ours in the SwiftBar plugin folder."
  fi

  step "Left in place"
  info "Code: $REPO (delete it with: rm -rf \"$REPO\")"
  [[ -n "$pd" ]] && info "SwiftBar plugin folder setting: $pd (change it in SwiftBar's preferences)"
  if sb="$(find_swiftbar)"; then
    info "SwiftBar itself: $sb (remove with 'brew uninstall --cask swiftbar' or drag it to the Trash)"
  fi
  info "Node.js (if you installed it for this)"
  echo; echo "AI Usage Bar is uninstalled."
  exit 0
fi

# ---------------------------------------------------------------- install
HAS_BREW=0; command -v brew >/dev/null 2>&1 && HAS_BREW=1

step "1/6 Node.js"
if command -v node >/dev/null 2>&1; then
  info "Found node $(node --version)"
elif (( HAS_BREW )); then
  info "Installing Node.js with Homebrew"
  run brew install node
else
  die "Node.js is required. Install it from https://nodejs.org (or install Homebrew and re-run), then run this again."
fi

step "2/6 SwiftBar"
if SB_APP="$(find_swiftbar)"; then
  info "Found $SB_APP"
elif (( HAS_BREW )); then
  info "Installing SwiftBar with Homebrew"
  run brew install --cask swiftbar
  SB_APP="/Applications/SwiftBar.app"
else
  info "Downloading the latest SwiftBar release from github.com/swiftbar/SwiftBar"
  if (( DRY_RUN )); then
    info "[dry-run] would download the release zip into ~/Applications and unzip it"
  else
    zip_url="$(curl -fsSL https://api.github.com/repos/swiftbar/SwiftBar/releases/latest \
      | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -n 1 | sed 's/.*"\(https[^"]*\)"/\1/')"
    [[ -n "$zip_url" ]] || die "Couldn't find a SwiftBar download. Install it from https://github.com/swiftbar/SwiftBar/releases"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/SwiftBar.zip" "$zip_url"
    mkdir -p "$HOME/Applications"
    ditto -x -k "$tmp/SwiftBar.zip" "$HOME/Applications"
    rm -rf "$tmp"
  fi
  SB_APP="$HOME/Applications/SwiftBar.app"
fi

step "3/6 AI Usage Bar code"
if REPO="$(detect_clone)"; then
  info "Using this git clone: $REPO"
elif [[ -d "$DEFAULT_DIR/.git" ]] && git_usable; then
  REPO="$DEFAULT_DIR"
  info "Updating $REPO"
  run git -C "$REPO" pull --ff-only
elif git_usable && [[ ! -e "$DEFAULT_DIR" ]]; then
  REPO="$DEFAULT_DIR"
  info "Cloning into $REPO"
  run git clone "$REPO_URL" "$REPO"
else
  REPO="$DEFAULT_DIR"
  if [[ -e "$DEFAULT_DIR" && ! -d "$DEFAULT_DIR/.git" ]]; then
    info "Refreshing $REPO from the latest download"
  else
    info "git isn't available; downloading a copy into $REPO (automatic updates won't work)"
  fi
  if (( DRY_RUN )); then
    info "[dry-run] would download $TARBALL_URL and extract it into $REPO"
  else
    mkdir -p "$REPO"
    curl -fsSL "$TARBALL_URL" | tar -xz -C "$REPO" --strip-components 1
  fi
fi
PLUGIN_DIR="$REPO/swiftbar"

step "4/6 SwiftBar plugin folder"
SB_WAS_RUNNING=0; pgrep -xq SwiftBar && SB_WAS_RUNNING=1
current="$(plugin_dir_pref)"
if [[ -z "$current" ]]; then
  info "Pointing SwiftBar at $PLUGIN_DIR"
  run defaults write "$SB_DOMAIN" PluginDirectory -string "$PLUGIN_DIR"
elif [[ "$(abspath "${current/#\~/$HOME}")" == "$(abspath "$PLUGIN_DIR")" ]]; then
  info "Already set to $PLUGIN_DIR"
else
  target="${current/#\~/$HOME}"
fi
if [[ -n "${target:-}" && -f "$target/.ai-usage.implementation.zsh" && ! -L "$target/$PLUGIN_NAME" ]]; then
  # The plugin folder is another copy of this repo (e.g. a developer clone): use that one.
  info "SwiftBar already uses another copy of AI Usage Bar at $current; keeping it"
  PLUGIN_DIR="$target"; REPO="$(dirname "$target")"
elif [[ -n "${target:-}" ]]; then
  info "SwiftBar already uses $current; adding a link to our plugin there"
  if [[ -e "$target/$PLUGIN_NAME" && ! -L "$target/$PLUGIN_NAME" ]]; then
    die "$target/$PLUGIN_NAME exists and isn't our link. Move it away and re-run."
  fi
  run mkdir -p "$target"
  run ln -sfn "$PLUGIN_DIR/$PLUGIN_NAME" "$target/$PLUGIN_NAME"
fi

step "5/6 Start at login"
run zsh "$PLUGIN_DIR/.ai-usage-login.zsh" enable

step "6/6 Starting SwiftBar"
if (( SB_WAS_RUNNING )); then
  info "SwiftBar is running; refreshing plugins"
  run open -g "swiftbar://refreshallplugins"
else
  run open -a "$SB_APP"
fi

cat <<EOF

Done. AI Usage Bar is installed.
  Code:   $REPO
  Plugin: $PLUGIN_DIR/$PLUGIN_NAME
  SwiftBar now starts at login (toggle it with "Starts at login" in the menu).

Uninstall: npx ai-usage-bar uninstall   (or: bash "$REPO/install.sh" --uninstall)
EOF
