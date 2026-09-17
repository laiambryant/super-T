# Changelog

## 1.1.0

- Refine the interface with a quieter sidebar, clear list headings, native
  checkboxes, progress indicators, and contextual keyboard hints.
- Add mouse controls for lists, tasks, filtering, help, and progress.
- Separate the desktop surface from the renderable panel and keep source code
  free of explanatory comments; maintenance notes live in the documentation.
- Automate tested, reproducible release archives and checksums on version tags.

- Reorder tasks with Shift+Up/Down or Shift+K/J. Children and notes move with
  their parent, and the cursor follows the moved task.
- Select a range with `v` to edit, complete, delete, move, or change indentation
  for several tasks at once.
- Move tasks between lists with `m`, including their children and notes.
- Create lists with `N`, including in a directory that does not exist yet.
- Edit YAML list tags with `t` and view completion progress with `s`.
- Restore the last viewed list and task when reopening the overlay.
- Extend undo to selections and moves; check for external edits and recover
  interrupted writes.
- Handle long lists with recycled rows and add a scrollable `?` command list.
- Share Markdown parsing and directory validation between the bar and overlay.
- Package the Python backend and list-creation helper with the plugin.
- Use `n` to add tasks (previously `a` / `o`), `h` / `l` to focus panes, and
  `Tab` to indent a task. `Shift+Tab` selects the previous list.

Requires Python 3.10 or newer. Existing Markdown lists and the plugin ID are
unchanged.

## 1.0.0

- Initial Markdown task view and open-task bar widget.
