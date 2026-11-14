#!/bin/zsh

# <xbar.title>AI Usage</xbar.title>
# <xbar.version>20261114.0.0</xbar.version>
# <xbar.author>local</xbar.author>
# <xbar.desc>Shows daily AI spend (Claude/Codex via ccusage) in the macOS menu bar.</xbar.desc>
# <xbar.dependencies>ccusage,node</xbar.dependencies>
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>

# Hidden implementation file: SwiftBar should expose only ai-usage.15s.sh as the menu item.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

impl_path="${0:A}"
script_path="${USAGE_COUNTER_WRAPPER_PATH:-${0:A}}"
plugin_dir="${0:A:h}"
repo_root="${plugin_dir:h}"
config_file="$plugin_dir/.usage-counter.conf"
stderr_dir="${TMPDIR:-/tmp}/swiftbar-agent-usage"
cache_output_file="$stderr_dir/menu.out"
cache_meta_file="$stderr_dir/menu.meta"

mode="both"
range="today"
reset_hour="0"
refresh_seconds="60"
do_refresh=0
claude_config_dir=""
claude_config_dir_set=0

read_config() {
  [[ -f "$config_file" ]] || return

  while IFS='=' read -r key value; do
    case "$key" in
      MODE) mode="$value" ;;
      RESET_HOUR) reset_hour="$value" ;;
      REFRESH_SECONDS) refresh_seconds="$value" ;;
      RANGE) range="$value" ;;
      CLAUDE_CONFIG_DIR) claude_config_dir="$value"; claude_config_dir_set=1 ;;
    esac
  done < "$config_file"

  case "$mode" in
    claude|codex|both) ;;
    *) mode="both" ;;
  esac

  case "$range" in
    today|week|last7|month|last30) ;;
    *) range="today" ;;
  esac

  if [[ "$reset_hour" != <-> ]] || (( reset_hour < 0 || reset_hour > 23 )); then
    reset_hour="0"
  fi

  case "$refresh_seconds" in
    15|30|60|300) ;;
    *) refresh_seconds="60" ;;
  esac
}

write_config() {
  {
    echo "MODE=$mode"
    echo "RANGE=$range"
    echo "RESET_HOUR=$reset_hour"
    echo "REFRESH_SECONDS=$refresh_seconds"
    echo "CLAUDE_CONFIG_DIR=$claude_config_dir"
  } > "$config_file"
}


lock_dir="$stderr_dir/refresh.lock"
login_helper="$plugin_dir/.ai-usage-login.zsh"
# SwiftBar's plugin name is the filename up to the first dot ("ai-usage").
plugin_name="${${script_path:t}%%.*}"

# Keep the cached menu visible (old numbers + "Refreshing…") instead of
# blanking it: just flag it stale so the next run refreshes in the background.
mark_stale() {
  [[ -f "$cache_meta_file" ]] || return
  grep -v '^STALE=' "$cache_meta_file" > "$cache_meta_file.$$" 2>/dev/null
  echo "STALE=1" >> "$cache_meta_file.$$"
  mv -f "$cache_meta_file.$$" "$cache_meta_file"
}

# A refresh is running if the lock dir exists, its pid is alive, and it is
# younger than ~180s (anything older is a wedged/dead job).
refresh_running() {
  [[ -d "$lock_dir" ]] || return 1
  local pid="" mtime now_s
  [[ -f "$lock_dir/pid" ]] && pid="$(<"$lock_dir/pid")"
  zmodload -F zsh/stat b:zstat 2>/dev/null
  mtime="$(zstat +mtime "$lock_dir" 2>/dev/null)" || mtime=0
  now_s="$EPOCHSECONDS"
  if (( now_s - mtime > 180 )); then
    return 1
  fi
  [[ -z "$pid" ]] && return 0   # just created, pid not written yet
  kill -0 "$pid" 2>/dev/null
}

acquire_lock() {
  mkdir -p "$stderr_dir"
  if ! mkdir "$lock_dir" 2>/dev/null; then
    refresh_running && return 1
    rm -rf "$lock_dir"
    mkdir "$lock_dir" 2>/dev/null || return 1
  fi
  print -r -- "$$" > "$lock_dir/pid"
  return 0
}

release_lock() {
  [[ -f "$lock_dir/pid" && "$(<"$lock_dir/pid")" == "$$" ]] && rm -rf "$lock_dir"
}

start_refresh_bg() {
  refresh_running && return 1
  mkdir -p "$stderr_dir"
  USAGE_COUNTER_WRAPPER_PATH="$script_path" \
    nohup /bin/zsh "$impl_path" refresh-bg >/dev/null 2>"$stderr_dir/refresh.err" </dev/null &!
  return 0
}

notify() {
  # Message is passed as argv (not interpolated into AppleScript source).
  osascript -e 'on run argv
    display notification (item 1 of argv) with title "AI Usage"
  end run' "$1" >/dev/null 2>&1
}

toggle_claude_config_dir() {
  local target="$1"
  [[ -z "$target" ]] && return
  local -a dirs
  if [[ -n "$claude_config_dir" ]]; then
    dirs=("${(@s:,:)claude_config_dir}")
  fi
  if (( ${dirs[(Ie)$target]} )); then
    dirs=("${(@)dirs:#$target}")
  else
    dirs+=("$target")
  fi
  claude_config_dir="${(j:,:)dirs}"
  write_config
}

run_git_update_bg() {
  local op="$1" notify_result="$2"
  [[ -d "$repo_root/.git" ]] || return
  mkdir -p "$stderr_dir"
  nohup zsh "$plugin_dir/.ai-usage-git-update.zsh" "$op" "$repo_root" "$stderr_dir" "$notify_result" >/dev/null 2>&1 </dev/null &
}

# Run a command with a wall-clock timeout (returns 124 on timeout).
run_with_timeout() {
  local timeout_seconds="$1"; shift
  local ticks=$(( timeout_seconds * 5 ))
  "$@" &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null && (( waited < ticks )); do
    sleep 0.2
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    pkill -TERM -P "$pid" 2>/dev/null
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 124
  fi
  wait "$pid"
}

zmodload zsh/datetime 2>/dev/null

read_config

detect_claude_config_dirs() {
  local dir
  for dir in "$HOME"/.claude*(N/); do
    [[ -f "$dir/settings.json" || -d "$dir/projects" ]] && print -r -- "$dir"
  done
}

claude_config_dir_candidates=()
while IFS= read -r dir; do
  [[ -n "$dir" ]] && claude_config_dir_candidates+=("$dir")
done < <(detect_claude_config_dirs)

# No explicit choice saved yet: default to using every detected profile.
if (( ! claude_config_dir_set )) && (( ${#claude_config_dir_candidates} > 1 )); then
  claude_config_dir="${(j:,:)claude_config_dir_candidates}"
fi

date_days_ago() {
  local days="$1"
  local format="$2"

  if (( days == 0 )); then
    date +"$format"
  else
    date -v-"${days}"d +"$format" 2>/dev/null || date -d "$days days ago" +"$format"
  fi
}

date_hours_ago() {
  local hours="$1"
  local format="$2"

  if (( hours == 0 )); then
    date +"$format"
  else
    date -v-"${hours}"H +"$format" 2>/dev/null || date -d "$hours hours ago" +"$format"
  fi
}

date_month_start() {
  local format="$1"
  date -v1d +"$format" 2>/dev/null || date -d "$(date +%Y-%m-01)" +"$format"
}

timezone_name=""
timezone_args=()
display_date="$(date +%F)"
since_display_date="$display_date"
until_display_date="$display_date"
since_date="$(date +%Y%m%d)"
until_date="$since_date"
range_label="Today"

case "$range" in
  today)
    display_date="$(date_hours_ago "$reset_hour" "%F")"
    since_display_date="$display_date"
    until_display_date="$display_date"
    since_date="$(date_hours_ago "$reset_hour" "%Y%m%d")"
    until_date="$since_date"
    range_label="Today"

    # KNOWN LIMITATION: this builds Etc/GMT±N from the whole-hour part of
    # the UTC offset, so in half/quarter-hour zones (e.g. +05:30) a non-zero
    # reset hour is off by 30/45 min. Etc/GMT zones can't express those, and
    # ccusage (20.0.50) only accepts IANA names for --timezone (offsets like
    # "+01:30" are rejected) and has no hourly/per-entry JSON report to bucket
    # exactly ourselves, so there's no clean exact fix here.
    if (( reset_hour > 0 )); then
      offset_raw="$(date +%z)"
      offset_sign="${offset_raw[1,1]}"
      offset_hour="${offset_raw[2,3]}"
      local_offset=$((10#$offset_hour))
      if [[ "$offset_sign" == "-" ]]; then
        local_offset=$((-local_offset))
      fi

      shifted_offset=$((local_offset - reset_hour))
      if (( shifted_offset == 0 )); then
        timezone_name="UTC"
      elif (( shifted_offset > 0 )); then
        timezone_name="Etc/GMT-${shifted_offset}"
      else
        timezone_name="Etc/GMT+$((-shifted_offset))"
      fi
      timezone_args=(--timezone "$timezone_name")
    fi
    ;;
  week)
    days_since_monday=$(($(date +%u) - 1))
    since_date="$(date_days_ago "$days_since_monday" "%Y%m%d")"
    since_display_date="$(date_days_ago "$days_since_monday" "%F")"
    range_label="Since Monday"
    ;;
  last7)
    since_date="$(date_days_ago 6 "%Y%m%d")"
    since_display_date="$(date_days_ago 6 "%F")"
    range_label="Last 7 days"
    ;;
  month)
    since_date="$(date_month_start "%Y%m%d")"
    since_display_date="$(date_month_start "%F")"
    range_label="Since month start"
    ;;
  last30)
    since_date="$(date_days_ago 29 "%Y%m%d")"
    since_display_date="$(date_days_ago 29 "%F")"
    range_label="Last 30 days"
    ;;
esac

cache_key="$mode|$range|$reset_hour|$refresh_seconds|$since_date|$until_date|$timezone_name|$claude_config_dir"

# ---------------------------------------------------------------------------
# Actions: change settings, keep the old menu visible, refresh in background.
# ---------------------------------------------------------------------------
settings_changed() {
  write_config
  mark_stale
  start_refresh_bg
}

case "$1" in
  set-mode)
    case "$2" in
      claude|codex|both) mode="$2"; settings_changed ;;
    esac
    exit 0
    ;;
  set-range)
    case "$2" in
      today|week|last7|month|last30) range="$2"; settings_changed ;;
    esac
    exit 0
    ;;
  set-reset-hour)
    if [[ "$2" == <-> ]] && (( $2 >= 0 && $2 <= 23 )); then
      reset_hour="$2"; settings_changed
    fi
    exit 0
    ;;
  set-refresh-seconds)
    case "$2" in
      15|30|60|300) refresh_seconds="$2"; settings_changed ;;
    esac
    exit 0
    ;;
  toggle-claude-config-dir)
    toggle_claude_config_dir "$2"
    mark_stale
    start_refresh_bg
    exit 0
    ;;
  force-refresh)
    mark_stale
    start_refresh_bg
    exit 0
    ;;
  git-pull)
    run_git_update_bg pull true
    mark_stale
    exit 0
    ;;
  check-updates)
    run_git_update_bg check true
    mark_stale
    exit 0
    ;;
  login-enable)
    if [[ -f "$login_helper" ]] && [[ "$(zsh "$login_helper" enable 2>/dev/null)" == "enabled" ]]; then
      notify "AI Usage will now start when you log in"
    else
      notify "Could not set up start at login"
    fi
    exit 0
    ;;
  login-disable)
    [[ -f "$login_helper" ]] && zsh "$login_helper" disable >/dev/null 2>&1
    exit 0
    ;;
  refresh-bg)
    do_refresh=1
    ;;
esac

mkdir -p "$stderr_dir"

if (( ! do_refresh )); then
  # -------------------------------------------------------------------------
  # Fast path (every SwiftBar poll / click): print cache, maybe kick off a
  # detached refresh, exit. No node, no ccusage, no network here.
  # -------------------------------------------------------------------------
  now="$EPOCHSECONDS"

  # Never do the actual git fetch here; just read what a background check
  # last found and, if due, kick off a detached check.
  update_meta_file="$stderr_dir/update.meta"
  update_available="false"
  if [[ -d "$repo_root/.git" ]]; then
    update_last_check="0"
    update_behind_count="0"
    if [[ -f "$update_meta_file" ]]; then
      while IFS='=' read -r key value; do
        case "$key" in
          LAST_CHECK) update_last_check="$value" ;;
          BEHIND_COUNT) update_behind_count="$value" ;;
        esac
      done < "$update_meta_file"
    fi
    [[ "$update_last_check" == <-> ]] || update_last_check="0"
    [[ "$update_behind_count" == <-> ]] || update_behind_count="0"
    if (( now - update_last_check >= 86400 )); then
      # Bump the timestamp first so rapid polls don't each spawn a fetch.
      {
        echo "LAST_CHECK=$now"
        echo "BEHIND_COUNT=$update_behind_count"
      } > "$update_meta_file.$$"
      mv -f "$update_meta_file.$$" "$update_meta_file"
      run_git_update_bg check false
    fi
    (( update_behind_count > 0 )) && update_available="true"
  fi

  cache_key_saved=""
  cache_last_run="0"
  cache_stale_flag="0"
  if [[ -f "$cache_meta_file" ]]; then
    while IFS='=' read -r key value; do
      case "$key" in
        CACHE_KEY) cache_key_saved="$value" ;;
        LAST_RUN) cache_last_run="$value" ;;
        STALE) cache_stale_flag="$value" ;;
      esac
    done < "$cache_meta_file"
  fi
  [[ "$cache_last_run" == <-> ]] || cache_last_run="0"

  have_cache=0
  [[ -s "$cache_output_file" ]] && have_cache=1

  refreshing=0
  if refresh_running; then
    refreshing=1
  elif (( ! have_cache )) || [[ "$cache_key_saved" != "$cache_key" || "$cache_stale_flag" == "1" ]] \
      || (( now - cache_last_run >= refresh_seconds )); then
    start_refresh_bg && refreshing=1
  fi

  age_label() {
    local s=$1
    if (( s < 60 )); then print -r -- "${s}s"
    elif (( s < 3600 )); then print -r -- "$((s / 60))m"
    elif (( s < 86400 )); then print -r -- "$((s / 3600))h $((s % 3600 / 60))m"
    else print -r -- "$((s / 86400))d"
    fi
  }

  print_dynamic_lines() {
    local action_base="bash=$script_path terminal=false refresh=true"
    if (( have_cache && cache_last_run > 0 )); then
      local status_line="Updated $(age_label $(( now - cache_last_run ))) ago"
      (( refreshing )) && status_line+=" · Refreshing…"
      print -r -- "$status_line | color=gray"
    elif (( refreshing )); then
      print -r -- "Refreshing… | color=gray"
    fi
    if [[ -f "$login_helper" ]]; then
      if [[ "$(zsh "$login_helper" status 2>/dev/null)" == "enabled" ]]; then
        print -r -- "✓ Starts at login"
        print -r -- "--Turn off start at login | $action_base param1=login-disable"
      else
        print -r -- "⚠️ Won't start after restart — click to fix | $action_base param1=login-enable"
        print -r -- "Adds a login item so the menu bar comes back after a reboot | size=11 color=gray"
      fi
    fi
  }

  if (( have_cache )); then
    # Cache layout: title line, "---", body. Dynamic lines go right after "---".
    {
      IFS= read -r title_line
      local_suffix=""; [[ "$update_available" == "true" ]] && local_suffix=" •"
      print -r -- "$title_line$local_suffix"
      IFS= read -r sep_line
      print -r -- "---"
      print_dynamic_lines
      [[ "$sep_line" == "---" ]] || print -r -- "$sep_line"
      cat
    } < "$cache_output_file"
  else
    print -r -- "AI …"
    print -r -- "---"
    print -r -- "Loading usage…"
    print_dynamic_lines
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Background refresh job (hidden subcommand: refresh-bg).
# ---------------------------------------------------------------------------
acquire_lock || exit 0
run_dir="$(mktemp -d "$stderr_dir/run.XXXXXX")"
cleanup_run_dir() {
  [[ -n "$run_dir" && -d "$run_dir" ]] && rm -rf "$run_dir"
  release_lock
}
trap cleanup_run_dir EXIT
trap 'exit 1' HUP INT TERM

now="$EPOCHSECONDS"
update_behind_count="0"
if [[ -f "$stderr_dir/update.meta" ]]; then
  while IFS='=' read -r key value; do
    [[ "$key" == BEHIND_COUNT ]] && update_behind_count="$value"
  done < "$stderr_dir/update.meta"
fi
[[ "$update_behind_count" == <-> ]] || update_behind_count="0"
update_available="false"
(( update_behind_count > 0 )) && update_available="true"

render_output_file="$run_dir/menu.out"

if [[ -n "$claude_config_dir" ]]; then
  export CLAUDE_CONFIG_DIR="$claude_config_dir"
fi

# Prefer the latest ccusage (online pricing, new models); fall back to a
# global install, then bunx. Never --prefer-offline: it pins a stale version.
ccusage_cmds=()
command -v npx >/dev/null 2>&1 && ccusage_cmds+=("npx --yes ccusage@latest")
command -v ccusage >/dev/null 2>&1 && ccusage_cmds+=("ccusage")
command -v bunx >/dev/null 2>&1 && ccusage_cmds+=("bunx ccusage@latest")
ccusage_timeout=60

# Writes "<source>\t<status>\t<command>\t<stdout>\t<stderr>" to $run_dir/<source>.spec
collect_report() {
  local source="$1"
  local stdout_file="$run_dir/$source.out"
  local stderr_file="$run_dir/$source.err"
  local spec_file="$run_dir/$source.spec"
  local rstatus="error" command_text="ccusage unavailable" cmd_str
  local -a cmd

  if (( ${#ccusage_cmds} == 0 )); then
    print -r -- "Missing dependency: install Node.js/npm (for npx), ccusage, or Bun." >"$stderr_file"
  fi

  for cmd_str in "${ccusage_cmds[@]}"; do
    cmd=(${(z)cmd_str} "$source" daily --json --since "$since_date" --until "$until_date" "${timezone_args[@]}")
    command_text="${cmd[*]}"
    run_with_timeout "$ccusage_timeout" "${cmd[@]}" >"$stdout_file" 2>"$stderr_file" </dev/null
    local exit_code=$?
    if (( exit_code == 0 )); then
      rstatus="ok"; break
    fi
    if cat "$stderr_file" "$stdout_file" 2>/dev/null | grep -q "No valid .* data directories found"; then
      rstatus="missing_data"; break
    fi
    (( exit_code == 124 )) && print -r -- "Timed out after ${ccusage_timeout}s: $command_text" >>"$stderr_file"
    rstatus="error"
  done
  printf '%s\t%s\t%s\t%s\t%s\n' "$source" "$rstatus" "$command_text" "$stdout_file" "$stderr_file" > "$spec_file"
}

jobs_pids=()
case "$mode" in
  claude) collect_report claude & jobs_pids+=($!) ;;
  codex)  collect_report codex & jobs_pids+=($!) ;;
  both)   collect_report claude & jobs_pids+=($!); collect_report codex & jobs_pids+=($!) ;;
esac
for pid in "${jobs_pids[@]}"; do wait "$pid"; done

report_specs=()
for spec_file in "$run_dir"/*.spec(N); do
  report_specs+=("$(<"$spec_file")")
done
# Keep Claude before Codex regardless of glob order.
report_specs=(${(M)report_specs:#claude*} ${(M)report_specs:#codex*})

REPORT_SPECS="${(F)report_specs}" \
MODE="$mode" \
RANGE="$range" \
RANGE_LABEL="$range_label" \
RESET_HOUR="$reset_hour" \
REFRESH_SECONDS="$refresh_seconds" \
DISPLAY_DATE="$display_date" \
SINCE_DATE="$since_date" \
UNTIL_DATE="$until_date" \
SINCE_DISPLAY_DATE="$since_display_date" \
UNTIL_DISPLAY_DATE="$until_display_date" \
TIMEZONE_NAME="$timezone_name" \
SCRIPT_PATH="$script_path" \
CLAUDE_CONFIG_DIR_VALUE="$claude_config_dir" \
CLAUDE_CONFIG_DIR_CANDIDATES="${(F)claude_config_dir_candidates}" \
HOME_DIR="$HOME" \
UPDATE_AVAILABLE="$update_available" \
UPDATE_BEHIND_COUNT="$update_behind_count" \
/usr/bin/env node <<'NODE_RENDER' > "$render_output_file"
const fs = require("fs");

function readMaybe(path) {
  try {
    return path && fs.existsSync(path) ? fs.readFileSync(path, "utf8") : "";
  } catch {
    return "";
  }
}

// Single node process: build the payload straight from env + report files.
const payload = {
  mode: process.env.MODE || "both",
  range: process.env.RANGE || "today",
  rangeLabel: process.env.RANGE_LABEL || "Today",
  resetHour: Number.parseInt(process.env.RESET_HOUR || "0", 10),
  refreshSeconds: Number.parseInt(process.env.REFRESH_SECONDS || "60", 10),
  displayDate: process.env.DISPLAY_DATE || "",
  sinceDate: process.env.SINCE_DATE || "",
  untilDate: process.env.UNTIL_DATE || "",
  sinceDisplayDate: process.env.SINCE_DISPLAY_DATE || "",
  untilDisplayDate: process.env.UNTIL_DISPLAY_DATE || "",
  timezoneName: process.env.TIMEZONE_NAME || "",
  scriptPath: process.env.SCRIPT_PATH || "",
  claudeConfigDir: process.env.CLAUDE_CONFIG_DIR_VALUE || "",
  claudeConfigDirCandidates: (process.env.CLAUDE_CONFIG_DIR_CANDIDATES || "")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean),
  homeDir: process.env.HOME_DIR || "",
  updateAvailable: process.env.UPDATE_AVAILABLE === "true",
  updateBehindCount: Number.parseInt(process.env.UPDATE_BEHIND_COUNT || "0", 10),
  reports: [],
};

for (const spec of (process.env.REPORT_SPECS || "").split("\n")) {
  if (!spec.trim()) continue;
  const [source, status, command, stdoutPath, stderrPath] = spec.split("\t");
  payload.reports.push({ source, status, command, stdout: readMaybe(stdoutPath), stderr: readMaybe(stderrPath) });
}



const mode = payload.mode || "both";
const range = payload.range || "today";
const rangeLabel = payload.rangeLabel || "Today";
const resetHour = Number.isFinite(payload.resetHour) ? payload.resetHour : 0;
const refreshSeconds = Number.isFinite(payload.refreshSeconds) ? payload.refreshSeconds : 60;
const displayDate = payload.displayDate || "";
const sinceDate = payload.sinceDate || "";
const untilDate = payload.untilDate || "";
const sinceDisplayDate = payload.sinceDisplayDate || displayDate;
const untilDisplayDate = payload.untilDisplayDate || displayDate;
const timezoneName = payload.timezoneName || "system timezone";
const scriptPath = payload.scriptPath || "";
const homeDir = payload.homeDir || "";
const claudeConfigDirCandidates = payload.claudeConfigDirCandidates || [];
const selectedConfigDirs = new Set(
  (payload.claudeConfigDir || "").split(",").map((dir) => dir.trim()).filter(Boolean)
);

const updateAvailable = Boolean(payload.updateAvailable);
const updateBehindCount = Number.isFinite(payload.updateBehindCount) ? payload.updateBehindCount : 0;

function shortDir(dir) {
  return homeDir && dir.startsWith(homeDir) ? `~${dir.slice(homeDir.length)}` : dir;
}

function numberValue(...values) {
  for (const value of values) {
    if (typeof value === "number" && Number.isFinite(value)) return value;
  }
  return 0;
}

function compactNumber(value) {
  const abs = Math.abs(value);
  if (abs >= 1_000_000_000) return `${(value / 1_000_000_000).toFixed(1)}B`;
  if (abs >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
  if (abs >= 1_000) return `${(value / 1_000).toFixed(1)}K`;
  return String(Math.round(value));
}

function fullNumber(value) {
  return Math.round(value).toLocaleString("en-US");
}

function money(value) {
  const rounded = Math.round(value);
  return `$${Object.is(rounded, -0) ? 0 : rounded.toLocaleString("en-US")}`;
}

function parseJson(raw, label) {
  try {
    return JSON.parse((raw || "{}").trim() || "{}");
  } catch (error) {
    return { parseError: `${label}: ${error.message}` };
  }
}

function modelNames(row) {
  if (Array.isArray(row.models)) return row.models;
  if (row.models && typeof row.models === "object") return Object.keys(row.models);
  if (Array.isArray(row.modelsUsed)) return row.modelsUsed;
  return [];
}

function emptyUsage(label, status = "missing_data", error = "") {
  return {
    label,
    status,
    error,
    input: 0,
    output: 0,
    cacheCreate: 0,
    cacheRead: 0,
    reasoning: 0,
    total: 0,
    cost: 0,
    models: [],
  };
}

function usageFromRows(label, rows) {
  const usage = emptyUsage(label, "ok");
  const models = new Set();

  for (const row of rows) {
    const input = numberValue(row.inputTokens);
    const output = numberValue(row.outputTokens);
    const cacheCreate = numberValue(row.cacheCreationTokens);
    const cacheRead = numberValue(row.cacheReadTokens, row.cachedInputTokens);
    const reasoning = numberValue(row.reasoningOutputTokens);
    const total = numberValue(row.totalTokens, input + output + cacheCreate + cacheRead + reasoning);
    const cost = numberValue(row.costUSD, row.totalCost);

    usage.input += input;
    usage.output += output;
    usage.cacheCreate += cacheCreate;
    usage.cacheRead += cacheRead;
    usage.reasoning += reasoning;
    usage.total += total;
    usage.cost += cost;
    for (const model of modelNames(row)) models.add(model);
  }

  usage.models = [...models];
  return usage;
}

function usageFromSummary(label, summary) {
  const input = numberValue(summary.inputTokens, summary.totalInputTokens);
  const output = numberValue(summary.outputTokens, summary.totalOutputTokens);
  const cacheCreate = numberValue(summary.cacheCreationTokens, summary.totalCacheCreationTokens);
  const cacheRead = numberValue(summary.cacheReadTokens, summary.cachedInputTokens, summary.totalCacheReadTokens, summary.totalCachedInputTokens);
  const reasoning = numberValue(summary.reasoningOutputTokens, summary.totalReasoningOutputTokens);
  const total = numberValue(summary.totalTokens, input + output + cacheCreate + cacheRead + reasoning);
  const cost = numberValue(summary.costUSD, summary.totalCost, summary.totalCostUSD);

  return {
    label,
    status: "ok",
    input,
    output,
    cacheCreate,
    cacheRead,
    reasoning,
    total,
    cost,
    models: modelNames(summary),
  };
}

function normalizeReport(report) {
  const label = report.source === "claude" ? "Claude" : report.source === "codex" ? "Codex" : report.source;

  if (report.status === "missing_data") return emptyUsage(label, "missing_data");
  if (report.status === "error") {
    const detail = (report.stderr || report.stdout || "Unknown error").trim().split("\n").slice(0, 3).join(" ");
    return emptyUsage(label, "error", detail || "Unknown error");
  }

  const parsed = parseJson(report.stdout, label);
  if (parsed.parseError) return emptyUsage(label, "error", parsed.parseError);

  const rows = Array.isArray(parsed.daily) ? parsed.daily : Array.isArray(parsed.data) ? parsed.data : [];
  const summary = parsed.totals || parsed.summary || {};
  const datedRows = rows.filter((item) => typeof item.date === "string" && item.date >= sinceDisplayDate && item.date <= untilDisplayDate);
  const rowsToUse = datedRows.length > 0 ? datedRows : rows;

  if (rowsToUse.length > 0) return usageFromRows(label, rowsToUse);
  return usageFromSummary(label, summary);
}

function addReports(reports) {
  const total = { input: 0, output: 0, cacheCreate: 0, cacheRead: 0, reasoning: 0, total: 0, cost: 0, models: new Set() };
  for (const report of reports) {
    total.input += report.input;
    total.output += report.output;
    total.cacheCreate += report.cacheCreate;
    total.cacheRead += report.cacheRead;
    total.reasoning += report.reasoning;
    total.total += report.total;
    total.cost += report.cost;
    for (const model of report.models) total.models.add(model);
  }
  return total;
}

function modeLabel(value = mode) {
  if (value === "claude") return "Claude";
  if (value === "both") return "AI";
  return "Codex";
}

function selected(current, value) {
  return current === value ? "[x]" : "[ ]";
}

function refreshLabel(seconds) {
  return `${seconds}s`;
}

function action(command, value) {
  return `bash=${scriptPath} param1=${command} param2=${value} terminal=false refresh=true`;
}


const reports = payload.reports.map(normalizeReport);
const total = addReports(reports);
const models = [...total.models].length > 0 ? [...total.models].join(", ") : "No model data";
const resetLabel = `${String(resetHour).padStart(2, "0")}:00`;
const hasErrors = reports.some((report) => report.status === "error");

// " •" (update available) is appended by the fast path, so it stays current.
console.log(`${modeLabel()} ${money(total.cost)}${hasErrors ? " !" : ""}`);
console.log("---");
console.log(`Mode: ${modeLabel()}`);
console.log(`Range: ${rangeLabel}`);
console.log(`Refresh: ${refreshLabel(refreshSeconds)}`);
if (range === "today") {
  console.log(`Usage day: ${displayDate}`);
  console.log(`Reset time: ${resetLabel}`);
  if (resetHour > 0) console.log(`Grouping timezone: ${timezoneName}`);
} else {
  console.log(`Usage dates: ${sinceDisplayDate} to ${untilDisplayDate}`);
}
console.log(`Cost: ${money(total.cost)}`);
console.log(`Total tokens: ${fullNumber(total.total)}`);
console.log(`Input: ${fullNumber(total.input)}`);
console.log(`Output: ${fullNumber(total.output)}`);
if (total.reasoning > 0) console.log(`Reasoning output: ${fullNumber(total.reasoning)}`);
if (total.cacheCreate > 0) console.log(`Cache create: ${fullNumber(total.cacheCreate)}`);
if (total.cacheRead > 0) console.log(`Cache read: ${fullNumber(total.cacheRead)}`);
console.log(`Models: ${models}`);

if (reports.length > 1) {
  console.log("---");
  for (const report of reports) {
    if (report.status === "missing_data") {
      console.log(`${report.label}: no data`);
    } else if (report.status === "error") {
      console.log(`${report.label}: error`);
    } else {
      console.log(`${report.label}: ${money(report.cost)} ${compactNumber(report.total)}`);
    }
  }
}

const errorReports = reports.filter((report) => report.status === "error");
if (errorReports.length > 0) {
  console.log("---");
  console.log("Errors");
  for (const report of errorReports) {
    console.log(`${report.label}: ${report.error || "Unknown error"}`);
  }
}

console.log("---");
console.log("Range");
for (const option of [
  ["today", "Today"],
  ["week", "Since Monday"],
  ["last7", "Last 7 days"],
  ["month", "Since month start"],
  ["last30", "Last 30 days"],
]) {
  console.log(`${selected(range, option[0])} ${option[1]} | ${action("set-range", option[0])}`);
}

console.log("---");
console.log("Mode");
console.log(`${selected(mode, "codex")} Codex only | ${action("set-mode", "codex")}`);
console.log(`${selected(mode, "claude")} Claude only | ${action("set-mode", "claude")}`);
console.log(`${selected(mode, "both")} Claude + Codex | ${action("set-mode", "both")}`);

if (claudeConfigDirCandidates.length > 1) {
  console.log("---");
  console.log("Claude profiles");
  for (const dir of claudeConfigDirCandidates) {
    const mark = selectedConfigDirs.has(dir) ? "[x]" : "[ ]";
    console.log(`${mark} ${shortDir(dir)} | ${action("toggle-claude-config-dir", dir)}`);
  }
  if (selectedConfigDirs.size === 0) {
    console.log("Using ccusage default (none checked above)");
  }
}

console.log("---");
console.log("Refresh interval");
for (const seconds of [15, 30, 60, 300]) {
  console.log(`${selected(refreshSeconds, seconds)} ${refreshLabel(seconds)} | ${action("set-refresh-seconds", seconds)}`);
}

if (range === "today") {
  console.log("---");
  console.log("Reset time");
  for (const hour of [0, 4, 8, 12]) {
    const label = `${String(hour).padStart(2, "0")}:00`;
    console.log(`${selected(resetHour, hour)} ${label} | ${action("set-reset-hour", hour)}`);
  }
}

console.log("---");
if (updateAvailable) {
  console.log(`Update available (${updateBehindCount} commit${updateBehindCount === 1 ? "" : "s"} behind) | ${action("git-pull", "1")}`);
}
console.log(`Check for updates | ${action("check-updates", "1")}`);
console.log(`Refresh now | ${action("force-refresh", "1")}`);
console.log("Made with <3 by crearo | href=https://github.com/crearo/ai-usage-bar");
console.log(`Config: ${range} ${sinceDate}-${untilDate}`);
NODE_RENDER
node_exit=$?

if (( node_exit == 0 )) && [[ -s "$render_output_file" ]]; then
  mv -f "$render_output_file" "$cache_output_file"
  {
    echo "CACHE_KEY=$cache_key"
    echo "LAST_RUN=$now"
  } > "$run_dir/menu.meta"
  mv -f "$run_dir/menu.meta" "$cache_meta_file"
elif [[ ! -s "$cache_output_file" ]]; then
  { echo "AI ?"; echo "---"; echo "Could not render usage output."; } > "$run_dir/menu.err.out"
  mv -f "$run_dir/menu.err.out" "$cache_output_file"
  { echo "CACHE_KEY=$cache_key"; echo "LAST_RUN=$now"; } > "$cache_meta_file"
fi

# Ask SwiftBar to redraw now. The cache is fresh, so that run just prints it
# (no new refresh → no loop).
release_lock
if [[ -n "$plugin_name" ]]; then
  open -g "swiftbar://refreshplugin?name=$plugin_name" >/dev/null 2>&1
fi
exit 0
