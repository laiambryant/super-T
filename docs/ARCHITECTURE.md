# Architecture and maintenance

Markdown files are the source of truth. The QML interface requests reads and
mutations through a serialized JSON service; Python owns filesystem access and
durable state. Keep each responsibility in its existing module when extending
the plugin.

## Interface

| Module | Responsibility |
| --- | --- |
| `Todo.qml` | Shell entry point, configuration, file observation and wiring |
| `TodoOverlay.qml` | Wayland surface and Omarchy theme integration |
| `TodoPanel.qml` | Desktop-independent layout, focus and visual composition |
| `TodoButton.qml` | Shared mouse action and accessible button |
| `TodoController.qml` | Public UI state, signals and helper entry points |
| `TodoKeymap.js` | Keyboard dispatch for each interaction mode |
| `TodoNavigation.js` | List/task selection, filtering and document application |
| `TodoSelection.js` | Pane focus, visible task ranges and help navigation |
| `TodoHelp.qml` | Scrollable keyboard command reference |
| `TodoSession.js` | Restoring and saving the last viewed position |
| `TodoMutations.js` | Editing, reordering, moving, tags, creation and undo UI transitions |
| `TodoRequests.js` | Requests, response routing and stale-response guards |
| `TodoTaskList.qml` | Recycled task delegates and viewport navigation |
| `TodoSidebar.qml`, `TodoMovePicker.qml` | List and destination selection |
| `TodoInputBar.qml`, `TodoSummary.qml` | Text input and progress presentation |
| `TodoDoc.js` | Pure Markdown parsing and task-line edits |
| `Config.js` | Shared configuration parsing and upfront validation |
| `BackendBridge.qml` | Ordered JSON requests over a Quickshell process |
| `BarWidget.qml` | Open-task count, refresh and configuration errors |

Visual components use explicit controller properties and signals. They do not
write files or depend on IDs in their parent components. Task selection uses an
unfiltered source index; filtering and recycled delegates must preserve it.
Directory changes invalidate pending response IDs. Session restoration waits for
the initial scan, read and saved position before selecting a task.

## Storage

| Module | Responsibility |
| --- | --- |
| `service.py` | Request validation, operation dispatch and orchestration |
| `todo_store.py` | Directory/path validation, scanning and atomic file writes |
| `todo_tasks.py` | Markdown task parsing and exact task-line transfers |
| `todo_selection.py` | Range edits, sibling reordering, subtree transfers and line mappings |
| `todo_tags.py` | Supported YAML tags syntax and surgical frontmatter changes |
| `todo_state.py` | Directory-scoped locking, position, completion history and undo |
| `todo_transaction.py` | Document/state journal, conflict checks and recovery |
| `scan.sh`, `newlist.sh` | Compatibility wrappers for the Python service |

Each process consumes one JSON line from stdin and returns one JSON object on
stdout. Document contents never go through shell arguments. Mutations include
the document text the user saw; conflicting disk edits produce a recoverable UI
error. Moves write the destination before removing the source, and undo uses the
reverse order. The journal coordinates document changes with history and undo
state; recovery stops when it encounters an external edit.

State lives beneath `$XDG_STATE_HOME/super-t` (or `~/.local/state/super-t`), keyed
by the canonical todo directory. Markdown remains free of internal task IDs.
Completion dates cover changes observed through the plugin. Percentage complete
also includes existing checked tasks.

## Tests and packaging

- `make test`: parser parity, configuration, creation, safe mutations, tags,
  session state, history, undo and interrupted-write recovery.
- `make test-qml`: real controller behavior, process/service integration and
  virtual scrolling. The large-list fixture checks that a 1,000-task model
  creates only a bounded number of delegates.
- `WAYLAND_SMOKE=1 make test-qml`: additionally loads the full hidden overlay
  against Wayland after probing socket connection and runtime-directory creation
  under the same permissions as Quickshell. Access failures are nonzero and
  actionable; run with permitted desktop access. Fixtures isolate HOME, task
  files, configuration, data, cache and state, with cleanup on either outcome.
- `make validate`: Omarchy manifest and Python runtime requirements.
- `make install PLUGINS_DIR=/tmp/super-t-plugins RELOAD=0`: inspect a complete
  package without changing the running shell.
- `make test-dist`: verify archive reproducibility and run the extracted plugin.
- `make dist`: build the versioned source archive and SHA-256 checksum.

`make install` copies every root QML, JavaScript, Python and shell module plus the
manifest. Adding a runtime module requires no duplicate hand-maintained file
list. Tests and documentation stay outside the installed plugin.

The source archive also includes the Makefile, tests, documentation, and license.
See [release steps](RELEASING.md) for validation and publication.
