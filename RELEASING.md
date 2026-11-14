# Releasing

Versions are date-based: `yyyyMMdd.patch.0`, e.g. `20261114.0.0`. A second release on the
same day bumps the middle number (`20261114.1.0`). npm needs three numbers, so the last one
is always `0`.

1. Set the version everywhere it appears (`package.json` and the `<xbar.version>` header in
   `swiftbar/ai-usage.15s.sh` and `swiftbar/.ai-usage.implementation.zsh`):

   ```sh
   v=$(date +%Y%m%d).0.0
   npm version "$v" --no-git-tag-version
   sed -i '' "s|<xbar.version>[^<]*</xbar.version>|<xbar.version>$v</xbar.version>|" \
     swiftbar/ai-usage.15s.sh swiftbar/.ai-usage.implementation.zsh
   ```

2. Commit and push to `main`. Existing installs pick up plugin changes through the built-in
   updater; npm only needs a new release when the installer (`install.sh`, `bin/`) changes.
3. `npm publish`, then check from outside the repo (inside it, npx runs the local copy):

   ```sh
   cd /tmp && npx --yes ai-usage-bar@latest --dry-run
   ```
