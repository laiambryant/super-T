<div align="center">

# omarchy-todo

Browse and edit your markdown todo lists from anywhere on your desktop, without leaving what you were doing.

[![CI](https://github.com/laiambryant/omarchy-todo/actions/workflows/ci.yml/badge.svg)](https://github.com/laiambryant/omarchy-todo/actions/workflows/ci.yml)
[![Omarchy plugin](https://img.shields.io/badge/omarchy-shell%20plugin-8250df)](https://omarchy.org/)
[![Manifest](https://img.shields.io/badge/manifest-schemaVersion%201-0969da)](manifest.json)
![Written in QML](https://img.shields.io/badge/written%20in-QML-41cd52)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

</div>

---

An [Omarchy](https://omarchy.org/) shell plugin that turns a directory of
markdown files into a keyboard-driven todo app. Every `.md` file in that
directory is one list; every `- [ ]` line in it is one task. A pill in the
status bar shows how many tasks are still open, and one keystroke brings up a
fullscreen overlay to work through them.

The files stay yours. This plugin never reformats them: ticking a box rewrites
exactly the one checkbox character, editing a task rewrites exactly the text
after the checkbox, and everything else in the file — headings, prose, front
matter, code fences, indentation, bullet style, trailing newline — comes back
out byte for byte. Open the same file in Obsidian or `nvim` and it looks
untouched.

```
┌──────────────────────────────────────────────┐
│  Todo                    ~/Documents/todos   │
├───────────────┬──────────────────────────────┤
│  work       3 │  󰄱 Fix the deploy script     │
│  home       7 │  󰄱 Email the landlord        │
│  groceries  2 │  󰄲 Renew domain              │
│  someday   14 │  󰄱 Book flights              │
├───────────────┴──────────────────────────────┤
│ j/k move  space toggle  a add  d delete  ⋯   │
└──────────────────────────────────────────────┘
```

## Install

```
omarchy plugin add https://github.com/laiambryant/omarchy-todo --enable
```

Pick `right` when it asks which bar section the pill belongs in.

Or from a local clone:

```
git clone https://github.com/laiambryant/omarchy-todo
cd omarchy-todo
make install          # copies into ~/.config/omarchy/plugins/liambryant.todo
omarchy plugin enable liambryant.todo --section right
```

Requires Omarchy with the Quickshell-based shell, plus `jq`, `awk` and `find` —
all of which a stock Omarchy install already has.

### Keybinding

Nothing binds the overlay for you. Add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + T", "Todo", "omarchy-shell shell toggle liambryant.todo")
```

Clicking the bar pill opens the same overlay, so the keybinding is optional.

## Configuration

The todo directory is set in `~/.config/omarchy/shell.json`, which the shell
hot-reloads — no restart needed:

```json
{
  "plugins": [
    { "id": "liambryant.todo", "dir": "~/Documents/todos" }
  ]
}
```

| Key   | Default              | Description                                              |
| ----- | -------------------- | -------------------------------------------------------- |
| `dir` | `~/Documents/todos`  | Directory scanned for `.md` lists. `~` is expanded.       |

The directory is scanned recursively, so `projects/omarchy.md` shows up as the
list `projects/omarchy`. Point it at an existing vault if you already keep
todos somewhere:

```json
{ "id": "liambryant.todo", "dir": "~/Documents/vault-poste/todos" }
```

A `dir` set on the bar entry in `bar.layout` overrides the plugin entry, which
is only useful if you want a second pill watching a second directory.

## Keys

| Key             | Action                                        |
| --------------- | --------------------------------------------- |
| `j` / `k` / `↑` / `↓` | Move between tasks                      |
| `h` / `l` / `Tab`     | Move between lists                      |
| `g` / `G`       | Jump to first / last task                     |
| `space` / `x`   | Toggle done                                   |
| `a` / `o`       | Add a task                                    |
| `enter` / `e`   | Edit the selected task                        |
| `d`             | Delete the selected task                      |
| `u`             | Undo the last change                          |
| `/`             | Filter tasks, `esc` clears it                 |
| `r`             | Re-read from disk                             |
| `esc`           | Close                                         |

Mouse works too: click a list to switch to it, click a task to toggle it.

Undo keeps the last 40 changes for the session and restores the whole file, so
a mistaken `d` is always one keystroke away from being fixed.

## What counts as a task

A task is a bullet followed by a checkbox:

```markdown
- [ ] An open task
- [x] A done task
* [X] Also done — any of -, * or + works, and X may be upper-case
  - [ ] Indented tasks are shown indented
```

Lines inside fenced code blocks are ignored, so documentation about checkboxes
does not turn into todos. Everything that is not a task line is left alone and
simply not displayed.

## How it stays out of the way

- **Edits are single-line.** Each write rebuilds one line out of that line's own
  captured pieces, then rejoins the file. There is no round-trip through a
  markdown renderer, so there is nothing to lose in the round trip.
- **Writes are atomic**, and the open file is watched, so editing it in another
  editor while the overlay is open updates the overlay rather than fighting it.
- **The bar pill is pushed, not polled.** The overlay and the pill live in the
  same shell process, so a tick updates the count immediately; a 15-second poll
  is the fallback that catches edits made outside the plugin.

## Development

```
make test        # parser, write-back and scanner tests
make install     # copy into ~/.config/omarchy/plugins/
make link        # symlink instead, for editing in place
make validate    # omarchy plugin validate
make reload      # tell the running shell to rescan plugins
```

Saving any file under `~/.config/omarchy/plugins/` hot-reloads the plugin, so
`make link` plus an editor is the fastest loop. If a change does not take,
`make reload`.

`TodoDoc.js` holds all the markdown parsing and write-back and has no QML
dependencies, which is what makes it testable under plain `node`. The task
pattern is duplicated in `scan.sh` because the bar pill needs counts without
reading file bodies into the shell process — `test/scan.test.sh` exists to keep
the two definitions honest with each other.

## Contributing

Issues and pull requests are welcome. Keep commits small and follow
[Conventional Commits](https://www.conventionalcommits.org/).

## License

[MIT](LICENSE)
