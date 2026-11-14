# AI usage counter in menu bar on macOS

SwiftBar plugin for Claude/Codex usage in the macOS menu bar (top right).

[![Watch demo](https://img.youtube.com/vi/dT2NoWe50r4/maxresdefault.jpg)](https://youtube.com/shorts/dT2NoWe50r4?feature=share)

![AI Usage Bar in the macOS menu bar](docs/menu-bar.png)

Usage data is collected via [ccusage](https://github.com/ryoppippi/ccusage).

## Setup

```sh
npx ai-usage-bar
```

No npm? Use:

```sh
curl -fsSL https://raw.githubusercontent.com/crearo/ai-usage-bar/main/install.sh | bash
```

The installer sets up Node.js and SwiftBar if needed (via Homebrew when available), puts the code in `~/.ai-usage-bar` (or uses your git clone if you run `./install.sh` from it), points SwiftBar at the plugin, and makes SwiftBar start at login. Re-run it any time to repair the install. Add `--dry-run` to see what it would do.

## What it shows

- The menu bar shows your estimated AI spend for today (via ccusage), e.g. `AI $39`. Other ranges (week, month, last 7/30 days) are in the menu, along with token details. The plugin always runs the latest ccusage via `npx` in the background, so there is nothing to keep updated.
- **Starts at login** in the menu turns starting at login on or off.
- The code updates itself with `git pull` when installed as a git clone.

## Configuration

Settings live in `swiftbar/.usage-counter.conf` (most are also editable from the menu bar dropdown):

- `MODE`: `claude`, `codex`, or `both`
- `RANGE`: `today`, `week`, `last7`, `month`, or `last30`
- `RESET_HOUR`: hour (0-23) the "today" range resets at
- `REFRESH_SECONDS`: `15`, `30`, `60`, or `300`
- `CLAUDE_CONFIG_DIR`: if you have more than one Claude account (work and personal, say), each one usually has its own `~/.claude*` folder. The menu shows a "Claude profiles" checklist and adds up usage from all of them by default. Untick any you don't want counted.

## Uninstall

```sh
npx ai-usage-bar uninstall
# or: bash ~/.ai-usage-bar/install.sh --uninstall
```

This turns off start at login and removes the plugin link. It tells you what's left (the code folder, SwiftBar itself) so you can delete those if you want.

## Troubleshooting

- Nothing in the menu bar: re-run the installer, then open SwiftBar.
- No cost numbers: check that ccusage runs with `npx ccusage@latest claude daily` or `npx ccusage@latest codex daily`.
