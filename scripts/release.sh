#!/usr/bin/env bash
# Usage: scripts/release.sh [patch]   -> version yyyyMMdd.<patch>.0
set -euo pipefail
cd "$(dirname "$0")/.."
v="$(date +%Y%m%d).${1:-0}.0"
npm version "$v" --no-git-tag-version --allow-same-version >/dev/null
sed -i '' "s|<xbar.version>[^<]*</xbar.version>|<xbar.version>$v</xbar.version>|" swiftbar/ai-usage.15s.sh
echo "Version set to $v"
if [[ -x scripts/build-app.sh ]]; then scripts/build-app.sh; else echo "scripts/build-app.sh not found; skipping build"; fi
cat <<MSG

Next:
  git commit -am "Release $v"
  npm publish            (prepublishOnly rebuilds the app)
  cd /tmp && npx --yes ai-usage-bar@latest --dry-run
  git push               (after npm has the new version: old installs' "Install the new app" runs npx @latest)
Signing: DEVELOPER_ID="Developer ID Application: ..." scripts/build-app.sh (once there's a cert).
Notarization: not set up yet.
MSG
