---
name: rdny-browser
description: rdny browser automation CLI. Use when automating Chrome, Chromium, or Helium from the terminal with rdny for navigation, screenshots, scraping, forms, logs, cookies, viewports, tabs, or video capture.
---

# rdny Browser Automation

Use `rdny` for small, scriptable browser checks from the terminal.

## Session basics

- Start an isolated managed browser: `rdny start --label agent`.
- Attach to a browser already launched with CDP: `rdny connect <host:port>` or `rdny connect <name>`.
- Check and clean up state: `rdny status`, `rdny list`, `rdny cleanup`, `rdny stop`.
- Use `rdny --state-dir <dir> ...` when you need a separate browser session.

## Common commands

```bash
rdny open https://example.com
rdny title
rdny url
rdny html 'main'
rdny text 'h1'
rdny click 'button[type=submit]'
rdny input 'input[name=q]' 'search terms'
rdny wait '.loaded'
rdny screenshot page.png
rdny logs --follow
```

`rdny js -` reads JavaScript from stdin, which is usually safer than shell-quoting
multi-line scripts.

## Config and environment

- Config file: `~/.config/rdny/config.toml` unless `RDNY_CONFIG` points elsewhere.
- Browser path: `RDNY_CHROME` > `[binaries].chrome` > built-in discovery.
- Video encoder: `RDNY_FFMPEG` > `[binaries].ffmpeg` > `ffmpeg` on `PATH`.
- Extra browser flags for managed starts: `RDNY_CHROME_ARGS`.

For a personal browser target, launch the browser with a remote debugging port,
then connect to it:

```bash
open -na Helium --args --remote-debugging-port=9333 --user-data-dir=/tmp/rdny-helium
rdny connect helium
```

Detached personal-browser sessions do not get killed by `rdny stop`; rdny only
clears its own session state.
