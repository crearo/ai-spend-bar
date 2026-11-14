#!/bin/zsh

# <xbar.title>AI Usage</xbar.title>
# <xbar.version>20261114.0.0</xbar.version>
# <xbar.author>local</xbar.author>
# <xbar.desc>Shows daily AI spend (Claude/Codex via ccusage) in the macOS menu bar.</xbar.desc>
# <xbar.dependencies>ccusage,node</xbar.dependencies>
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>

# SwiftBar uses this filename for polling; the hidden script keeps implementation out of the menu.
export USAGE_COUNTER_WRAPPER_PATH="${0:A}"
exec /bin/zsh "${0:A:h}/.ai-usage.implementation.zsh" "$@"
