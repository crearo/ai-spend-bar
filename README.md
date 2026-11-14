# AI Spend Bar

See how much you've spent on AI coding tools today, right in your Mac's menu bar.

<a href="https://youtu.be/Z_sH5Z3PNxg"><img src="https://raw.githubusercontent.com/crearo/ai-spend-bar/main/docs/demo.jpg" alt="Watch the 20-second demo of AI Spend Bar" width="720"></a>

▶ [Watch the 20-second demo](https://youtu.be/Z_sH5Z3PNxg)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/crearo/ai-spend-bar/main/docs/panel-dark.png">
  <img src="https://raw.githubusercontent.com/crearo/ai-spend-bar/main/docs/panel-light.png" alt="AI Spend Bar in the macOS menu bar, with its panel open" width="520">
</picture>

## Install

```sh
npx ai-spend-bar
```

That's it. It starts now and every time you log in.

No Node? Use `curl -fsSL https://raw.githubusercontent.com/crearo/ai-spend-bar/main/install.sh | bash`

## Uninstall

```sh
npx ai-spend-bar uninstall
```

---

Shows the API value of your usage today, this week or this month across Claude Code, Codex and the other tools [ccusage](https://github.com/ryoppippi/ccusage) supports; toggle tools in the panel. Requires macOS 13+ and Node.js (the installer sets up Node for you).
