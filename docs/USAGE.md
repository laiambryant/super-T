# Using Super T

Click the bar’s task count to open the overlay. Middle-click refreshes the count;
right-click opens your task directory in the configured editor. The default
folder is `~/Documents/todos`.

## Lists and files

Every `.md` file is a list, including files in subdirectories. `Shift+N` creates
a list; `projects/website` creates any missing parent directories too. `t`
edits the current list’s YAML tags. Separate tags with spaces or commas;
nested tags such as `work/website` are supported.

Task bullets can be `-`, `*`, or `+`, and checked boxes can use `x` or `X`.
Checkboxes inside initial YAML frontmatter or fenced code blocks are ignored.
Edits preserve task formatting and unrelated note content.

## Keyboard reference

Arrow keys and `h/j/k/l` work. Press `?` for the in-app command list.

| Key | Action |
| --- | --- |
| `h` / `←`, `l` / `→` | Focus lists, focus tasks |
| `j` / `↓`, `k` / `↑` | Next row, previous row |
| `Shift+↓` / `J`, `Shift+↑` / `K` | Move task down, move task up |
| `g` / `Home`, `G` / `End` | First row, last row |
| `PageUp`, `PageDown` | Move ten rows |
| `Shift+Tab` | Previous list |
| `Space` / `x` | Complete or reopen |
| `Enter` / `e` | Edit task; enter tasks from the list pane |
| `n`, `N` | Add task, create list |
| `v` | Start or clear a selection |
| `Tab` / `>`, `<` | Indent, outdent |
| `m` | Move to another list |
| `d` | Delete |
| `u` | Undo |
| `t` | Edit list tags |
| `/` | Filter tasks |
| `s` | Show progress |
| `r` | Reload |
| `Esc` | Clear selection, clear filter, then close |

Clicking a task toggles its checkbox. During selection, clicking extends the
range instead. Scroll either pane independently for long lists.

## Selections and editing

Press `v`, then move to select a range. Complete, delete, move, indent, and
outdent apply to the selection. Editing a range gives you one line per task;
use **Ctrl+Enter** to save. Single-task edits save with Enter. Escape cancels.
An entirely completed selection reopens all selected tasks; a mixed selection
completes them all.

## Reordering and moving

Hold Shift and press Up/Down or k/j to reorder. Tasks move past one sibling at
a time, keeping their children and indented notes. Movement stops at the
parent or section boundary. The cursor follows the task.

Press `m`, choose a destination, then Enter to move between lists. Children
and indented notes move with their parent. Moved tasks become top-level tasks
in the destination; children keep their relative indentation. Click a
possible destination to select it, or double-click it to move.

## Filtering

Press `/` and type. Enter keeps the filter; Escape clears it. Selections
include visible rows only. Moving, deleting, or changing indentation also
includes their children, even if hidden. Reordering follows file order,
including siblings hidden by the filter.

## Undo and external editors

`u` undoes a task change, a whole selection, or a move between lists. Creating
a list cannot be undone. Edits and undo refuse to overwrite changes made by
another editor. Reload with `r` after resolving a conflict.

## Progress and saved state

The progress view shows completion percentage, tasks closed today, and a daily
streak. Percentage includes all checked tasks. Dates and streaks count only
completions made through Super T.

Your last list and task are restored when you reopen the overlay. Position,
completion history, and undo data live in `~/.local/state/super-t` (or under
`$XDG_STATE_HOME` if set). Removing the plugin preserves both this state and
your Markdown directory.
