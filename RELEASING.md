# Releasing

Versions are date-based: `yyyyMMdd.N`, e.g. `20261114.0`, then `20261114.1`, `20261114.2` for
more releases the same day. npm only accepts three-part versions, so `package.json` carries
`yyyyMMdd.N.0`; the app, docs and everything else show `yyyyMMdd.N`.

1. `scripts/release.sh [N]` sets the version in `package.json` and the SwiftBar stub,
   then builds `dist/AI-Spend-Bar.zip` with `scripts/build-app.sh`.
2. Commit (don't push yet).
3. `npm publish` (`prepublishOnly` rebuilds the app so the zip is always fresh), then check
   from outside the repo: `cd /tmp && npx --yes ai-spend-bar@latest --dry-run`.
4. Push to `main`. Publish first: old SwiftBar installs update via `git pull`, and their
   "Install the new app" button runs `npx ai-spend-bar@latest`.

The old package name, `ai-usage-bar`, lives in `npm/ai-usage-bar/` and only forwards to
`npx ai-spend-bar`. It rarely needs a release; when it does, bump its version and run
`npm publish` from that folder.

Signing: `DEVELOPER_ID="Developer ID Application: ..." scripts/build-app.sh` once there's a
Developer ID certificate. Notarization comes later.
