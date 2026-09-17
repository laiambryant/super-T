# Behavior checks

These are the main behaviors to preserve when changing the plugin. The module
map and test commands are in [ARCHITECTURE.md](ARCHITECTURE.md).

## Tasks

- Checkbox and text edits preserve the task's bullet style and indentation.
  Frontmatter and fenced code blocks are excluded from task parsing.
- Selection uses visible rows. Structural operations include the selected
  tasks' children and indented notes, even when hidden by a filter. Selecting
  both a parent and a child must not process the child twice.
- Shift+Up/Down and Shift+K/J reorder sibling blocks in document order, without
  crossing parent or prose boundaries. The cursor follows the moved task.
  First and last siblings do not wrap or add an undo step when they cannot move.
- Moving to another list detaches the selected roots from their old parents.
  Children keep their relative indentation, and notes travel with the task.
- Each selection operation is one save and one undo step. Editing a selection
  requires one non-empty text line per selected task.

## Files

- Mutations check the file contents against what the interface last read.
  A conflict leaves the external edit intact and displays an error.
- Moves and undo coordinate all affected documents with completion history.
  Interrupted writes recover through the transaction journal.
- List creation works when the todo directory is missing, creates subdirectories,
  rejects paths outside the configured directory, and never replaces a list.
- Tag edits preserve unrelated frontmatter. Unsupported YAML tag syntax produces
  an error rather than rewriting the header.

## Navigation and state

- Task selection refers to the unfiltered source index. Filtering and recycled
  rows must not change which document line gets edited.
- Restoring the last position waits for the initial scan, document read, and
  saved session. Missing lists or tasks fall back to a valid position.
- Responses from a previous directory are ignored. A late mutation response for
  another list must not move the current list's cursor.
- Completion percentage includes all checked tasks. Daily counts and streaks
  use completions recorded through the plugin. Reopening or undoing a task must
  update its own history, including when tasks have identical text.
- Long lists create delegates for the viewport and a small buffer, rather than
  one delegate per task.

## Configuration

Omitting `dir` uses `~/Documents/todos`. Explicit empty, non-string, relative,
control-character, file, or unreadable paths produce an error. Invalid settings
must not silently select another directory. A missing directory is allowed so
that the first list can create it.
