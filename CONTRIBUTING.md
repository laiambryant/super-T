# Contributing to Super T

Use an Omarchy desktop with Python 3.10+, Node.js, `jq`, ShellCheck,
Quickshell, and Qt Quick Test (`qt6-declarative` on Arch).

## Development

```sh
make test
make test-qml
make validate
make lint
make test-dist
```

Use `make link` to develop against this checkout. It refuses to replace a real
plugin directory. User plugin files reload automatically. For an isolated
installation, run:

```sh
make install PLUGINS_DIR=/tmp/super-t-plugins RELOAD=0
```

`WAYLAND_SMOKE=1 make test-qml` additionally checks the full hidden overlay
against a live compositor. It isolates task files, configuration, cache, and
state. The ordinary headless tests run in CI; the compositor check is local.

## Interface previews

Render the real panel with sample data, without opening the desktop overlay:

```sh
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_STYLE_OVERRIDE=Fusion \
  QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qml test/qml/Preview.qml
```

This writes `docs/preview.png`. Arguments after `--` select `--light`,
`--compact`, `--empty`, `--input`, `--summary`, or `--help-view`.
Use `--output /tmp/super-t-preview.png` for a disposable capture.

## Changes

Keep visual components independent of filesystem operations. Route actions
through the controller and keep writes in the Python service. Preserve exact
Markdown formatting, the configured directory, conflict detection, and
recovery behavior. See [architecture](docs/ARCHITECTURE.md).

Prefer clear names and small functions. Keep explanatory notes here or in
`docs/`, and keep code free of comments. Add regression coverage for behavior
changes; visually inspect UI changes in light and dark themes and at a smaller
window size.

Before submitting a change, run the checks above and describe the behavior
change and relevant validation. Update `CHANGELOG.md` for user-visible changes.
See [releasing](docs/RELEASING.md) for versioning and publication.
