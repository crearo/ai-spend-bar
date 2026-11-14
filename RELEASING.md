# Releasing

Versions are date-based: `yyyyMMdd.patch.0`, e.g. `20261114.0.0`. A second release on the
same day bumps the middle number (`20261114.1.0`).

1. `scripts/release.sh [patch]` sets the version in `package.json` and the SwiftBar stub,
   then builds `dist/AI-Usage-Bar.zip` with `scripts/build-app.sh`.
2. Commit (don't push yet).
3. `npm publish` (`prepublishOnly` rebuilds the app so the zip is always fresh), then check
   from outside the repo: `cd /tmp && npx --yes ai-usage-bar@latest --dry-run`.
4. Push to `main`. Publish first: old SwiftBar installs update via `git pull`, and their
   "Install the new app" button runs `npx ai-usage-bar@latest`.

Signing: `DEVELOPER_ID="Developer ID Application: ..." scripts/build-app.sh` once there's a
Developer ID certificate. Notarization comes later.
