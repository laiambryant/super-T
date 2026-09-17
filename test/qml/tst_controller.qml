import QtQuick
import QtTest
import "../.." as App
TestCase {
  id: testCase
  name: "TodoController"
  when: true
  visible: true
  width: 900
  height: 500

  property var fixture: null

  Component {
    id: fixtureComponent

    Item {
      id: fixtureRoot
      width: 900
      height: 500

      property int nextRequestId: 1
      property var calls: []
      property alias controller: controllerObject
      property alias taskList: taskListObject
      property alias inputBar: inputBarObject
      property alias keyCatcher: keyCatcherObject
      property alias help: helpObject

      signal succeeded(string op, int requestId, var data)
      signal failed(string op, int requestId, string error)

      function request(op, payload) {
        var id = nextRequestId++
        calls = calls.concat([{ op: op, id: id, payload: payload }])
        return id
      }

      function requestFor(op) {
        for (var i = calls.length - 1; i >= 0; --i) {
          if (calls[i].op === op) return calls[i]
        }
        return null
      }

      App.TodoController {
        id: controllerObject
        backend: fixtureRoot
        autoStartBackend: false
        directory: "/tmp/super-t-qml-test"
      }

      App.TodoTaskList {
        id: taskListObject
        width: parent.width
        height: 160
        controller: controllerObject
        foreground: "#eeeeee"
        selectedBackground: "#234567"
        selectedText: "#ffffff"
        accent: "#99dd66"
        rowHeight: 24
        cornerRadius: 2
        fontFamily: "sans-serif"
        fontSize: 14
        interactive: false
      }

      App.TodoInputBar {
        id: inputBarObject
        width: parent.width
        controller: controllerObject
        background: "#fffaf0"
        foreground: "#eeeeee"
        selectedBackground: "#234567"
        selectedText: "#ffffff"
        accent: "#99dd66"
        cornerRadius: 2
        fontFamily: "sans-serif"
        rowHeight: 24
        fontSize: 14
      }

      App.TodoHelp {
        id: helpObject
        width: 700
        height: 360
        controller: controllerObject
        background: "#202020"
        foreground: "#eeeeee"
        accent: "#99dd66"
        borderColor: "#888888"
        fontFamily: "sans-serif"
      }

      Item {
        id: keyCatcherObject
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { controllerObject.dispatchKey(event) }
        Keys.onTabPressed: function(event) { controllerObject.dispatchKey(event) }
        Keys.onBacktabPressed: function(event) { controllerObject.dispatchKey(event) }
      }
    }
  }

  function init() {
    fixture = fixtureComponent.createObject(testCase)
    verify(fixture !== null, "could not create TodoController fixture")
  }

  function cleanup() {
    if (fixture) fixture.destroy()
    fixture = null
  }

  function key(keyCode, modifiers, text) {
    return {
      key: keyCode,
      modifiers: modifiers === undefined ? Qt.NoModifier : modifiers,
      text: text === undefined ? "" : text,
      accepted: false
    }
  }

  function list(path, name) {
    return { path: path, name: name, total: 0, done: 0, tags: [] }
  }

  function taskDocument(count) {
    var lines = []
    for (var i = 0; i < count; ++i) lines.push("- [ ] task " + i)
    return lines.join("\n") + "\n"
  }

  function loadListsAndDocument(lists, selectedPath, text) {
    fixture.controller.applyScan({ lists: lists })
    var path = selectedPath || fixture.controller.currentPath
    fixture.controller.applyRead({ path: path, text: text, tags: [] }, path)
  }

  function test_large_model_navigation_and_recycling() {
    var path = "/tmp/super-t-qml-test/a.md"
    loadListsAndDocument([list(path, "A")], path, taskDocument(1000))
    compare(fixture.controller.allTasks.length, 1000)
    compare(fixture.controller.tasks.length, 1000)

    fixture.controller.dispatchKey(key(Qt.Key_End))
    compare(fixture.controller.taskIndex, 999)
    fixture.controller.dispatchKey(key(Qt.Key_Home))
    compare(fixture.controller.taskIndex, 0)
    fixture.controller.dispatchKey(key(Qt.Key_G, Qt.ShiftModifier))
    compare(fixture.controller.taskIndex, 999)
    fixture.controller.dispatchKey(key(Qt.Key_G))
    compare(fixture.controller.taskIndex, 0)
    wait(0)
    var fullModelDelegates = fixture.taskList.view.contentItem.children.length
    console.log("TodoTaskList delegates for 1000 rows: " + fullModelDelegates)
    verify(fullModelDelegates < 80, "task ListView instantiated too many full-model delegates")

    fixture.controller.filterText = "task 99"
    compare(fixture.controller.tasks.length, 11)
    fixture.controller.dispatchKey(key(Qt.Key_Home))
    compare(fixture.controller.taskIndex, 99)
    fixture.controller.dispatchKey(key(Qt.Key_End))
    compare(fixture.controller.taskIndex, 999)
    fixture.controller.dispatchKey(key(Qt.Key_G))
    compare(fixture.controller.taskIndex, 99)
    fixture.controller.dispatchKey(key(Qt.Key_G, Qt.ShiftModifier))
    compare(fixture.controller.taskIndex, 999)
    compare(fixture.controller.selectedVisibleIndex, 10)

    fixture.controller.clearFilter()
    fixture.controller.dispatchKey(key(Qt.Key_End))
    wait(0)
    var endDelegates = fixture.taskList.view.contentItem.children.length
    console.log("TodoTaskList delegates after scrolling 1000 rows: " + endDelegates)
    verify(endDelegates < 80, "task ListView instantiated too many delegates after scrolling")
  }

  function test_input_selection_inverts_editor_colors() {
    compare(fixture.inputBar.editor.color, fixture.inputBar.selectedText)
    compare(fixture.inputBar.editor.selectionColor, fixture.inputBar.selectedText)
    compare(fixture.inputBar.editor.selectedTextColor, fixture.inputBar.background)
  }

  function test_navigation_uses_focused_pane_and_retains_shortcuts() {
    var controller = fixture.controller
    var first = "/tmp/super-t-qml-test/first.md"
    var second = "/tmp/super-t-qml-test/second.md"
    loadListsAndDocument([list(first, "A"), list(second, "B")], first, taskDocument(30))
    controller.dispatchKey(key(Qt.Key_H))
    compare(controller.activePane, "lists")
    compare(controller.listIndex, 0)
    controller.dispatchKey(key(Qt.Key_J))
    compare(controller.listIndex, 1)
    controller.applyRead({ path: second, text: taskDocument(30) }, second)
    controller.dispatchKey(key(Qt.Key_Right))
    compare(controller.activePane, "tasks")
    controller.dispatchKey(key(Qt.Key_Down))
    compare(controller.taskIndex, 1)
    compare(controller.listIndex, 1)
    controller.dispatchKey(key(Qt.Key_PageDown))
    compare(controller.taskIndex, 11)
    controller.dispatchKey(key(Qt.Key_G, Qt.ShiftModifier))
    compare(controller.taskIndex, 29)
    controller.dispatchKey(key(Qt.Key_G))
    compare(controller.taskIndex, 0)
    controller.dispatchKey(key(Qt.Key_Left))
    controller.dispatchKey(key(Qt.Key_Up))
    compare(controller.listIndex, 0)
    controller.dispatchKey(key(Qt.Key_Backtab))
    compare(controller.listIndex, 1)
    controller.dispatchKey(key(Qt.Key_R))
    verify(fixture.requestFor("scan") !== null)
  }

  function test_shift_movement_reorders_and_follows_task_data() {
    return [
      { tag: "arrow up", code: Qt.Key_Up, action: "up", line: 0 },
      { tag: "vim up", code: Qt.Key_K, action: "up", line: 0 },
      { tag: "arrow down", code: Qt.Key_Down, action: "down", line: 2 },
      { tag: "vim down", code: Qt.Key_J, action: "down", line: 2 }
    ]
  }

  function test_shift_movement_reorders_and_follows_task(data) {
    var controller = fixture.controller
    var path = "/tmp/super-t-qml-test/reorder.md"
    var document = "- [ ] first\n- [ ] selected\n- [ ] last\n"
    loadListsAndDocument([list(path, "Reorder")], path, document)
    controller.setTaskIndex(1)
    fixture.keyCatcher.forceActiveFocus()
    keyClick(data.code, Qt.ShiftModifier)
    var request = fixture.requestFor("batch")
    verify(request !== null)
    compare(request.payload.action, data.action)
    compare(request.payload.lines, [1])
    compare(request.payload.expected, document)
    compare(controller.taskIndex, 1)
    keyClick(data.code, Qt.ShiftModifier)
    compare(fixture.requestFor("batch").id, request.id)
    compare(controller.taskIndex, 1)
    var text = data.action === "up"
      ? "- [ ] selected\n- [ ] first\n- [ ] last\n"
      : "- [ ] first\n- [ ] last\n- [ ] selected\n"
    controller.handleSuccess("batch", request.id, {
      path: path, text: text, lineMapping: { "1": data.line }, undoToken: "reorder-token"
    })
    compare(controller.taskIndex, data.line)
    compare(controller.selectedTask().text, "selected")
    controller.undo()
    compare(fixture.requestFor("undo").payload.token, "reorder-token")
  }

  function test_reorder_filtered_selection_and_changed_list() {
    var controller = fixture.controller
    var path = "/tmp/super-t-qml-test/filtered.md"
    var other = "/tmp/super-t-qml-test/other.md"
    var document = "- [ ] match one\n- [ ] hidden\n- [ ] match two\n"
    loadListsAndDocument([list(path, "Filtered"), list(other, "Other")], path, document)
    controller.filterText = "match"
    controller.toggleSelection()
    controller.moveTask(1)
    controller.dispatchKey(key(Qt.Key_Up, Qt.ShiftModifier))
    var request = fixture.requestFor("batch")
    compare(request.payload.lines, [0, 2])
    controller.selectList(1)
    controller.applyRead({ path: other, text: taskDocument(5) }, other)
    controller.setTaskIndex(4)
    controller.handleSuccess("batch", request.id, {
      path: path, text: "- [ ] match one\n- [ ] match two\n- [ ] hidden\n",
      lineMapping: { "0": 0, "1": 2, "2": 1 }, undoToken: "reorder-token"
    })
    compare(controller.currentPath, other)
    compare(controller.taskIndex, 4)
  }

  function test_shift_movement_only_reorders_in_tasks_pane() {
    var controller = fixture.controller
    var first = "/tmp/super-t-qml-test/first.md"
    var second = "/tmp/super-t-qml-test/second.md"
    loadListsAndDocument([list(first, "First"), list(second, "Second")], first, taskDocument(3))
    controller.focusPane("lists")
    controller.dispatchKey(key(Qt.Key_J, Qt.ShiftModifier))
    compare(controller.listIndex, 1)
    compare(fixture.requestFor("batch"), null)
    controller.applyRead({ path: second, text: taskDocument(3) }, second)
    controller.focusPane("tasks")
    controller.beginFilter()
    controller.dispatchKey(key(Qt.Key_Down, Qt.ShiftModifier))
    compare(controller.taskIndex, 1)
    compare(fixture.requestFor("batch"), null)
    controller.finishFilter()
    controller.toggleHelp()
    controller.dispatchKey(key(Qt.Key_K, Qt.ShiftModifier))
    compare(fixture.requestFor("batch"), null)
  }

  function test_help_is_modal_scrollable_and_preserves_selection() {
    var controller = fixture.controller
    var path = "/tmp/super-t-qml-test/help.md"
    loadListsAndDocument([list(path, "Help")], path, taskDocument(10))
    controller.dispatchKey(key(Qt.Key_V))
    controller.dispatchKey(key(Qt.Key_J))
    controller.dispatchKey(key(Qt.Key_Question))
    compare(controller.mode, "help")
    wait(0)
    verify(fixture.help.visible)
    controller.dispatchKey(key(Qt.Key_J))
    verify(fixture.help.view.contentY > 0)
    controller.dispatchKey(key(Qt.Key_D))
    compare(fixture.requestFor("batch"), null)
    compare(controller.taskIndex, 1)
    controller.dispatchKey(key(Qt.Key_Escape))
    compare(controller.mode, "normal")
    compare(controller.selectedIndices, [0, 1])
    controller.dispatchKey(key(Qt.Key_V))
    verify(!controller.selecting)
    fixture.keyCatcher.forceActiveFocus()
    keyClick(Qt.Key_Question)
    compare(controller.mode, "help")
    keyClick(Qt.Key_Question)
    compare(controller.mode, "normal")
  }

  function test_filtered_selection_targets_visible_rows_and_bulk_undo() {
    var controller = fixture.controller
    var path = "/tmp/super-t-qml-test/selection.md"
    var document = "- [ ] match one\n- [ ] hidden\n- [ ] match two\n"
    loadListsAndDocument([list(path, "Selection")], path, document)
    controller.filterText = "match"
    controller.dispatchKey(key(Qt.Key_V))
    controller.dispatchKey(key(Qt.Key_J))
    compare(controller.selectedIndices, [0, 2])
    controller.dispatchKey(key(Qt.Key_Space))
    var batch = fixture.requestFor("batch")
    compare(batch.payload.lines, [0, 2])
    compare(batch.payload.action, "toggle")
    controller.handleSuccess("batch", batch.id, {
      path: path, text: document.replace(/match/g, "done match"), undoToken: "range-token"
    })
    verify(!controller.selecting)
    controller.undo()
    compare(fixture.requestFor("undo").payload.token, "range-token")
  }

  function test_bulk_editor_snapshots_lines_and_requires_matching_count() {
    var controller = fixture.controller
    var path = "/tmp/super-t-qml-test/edit.md"
    loadListsAndDocument([list(path, "Edit")], path, "- [ ] one\n- [ ] two\n- [ ] three\n")
    controller.dispatchKey(key(Qt.Key_V))
    controller.dispatchKey(key(Qt.Key_J))
    controller.dispatchKey(key(Qt.Key_E))
    compare(controller.mode, "input")
    verify(controller.multilineInput)
    compare(controller.inputLines, [0, 1])
    compare(controller.inputText, "one\ntwo")
    controller.inputText = "just one"
    controller.commitInput()
    verify(controller.inputError.indexOf("2 lines") >= 0)
    compare(fixture.requestFor("batch"), null)
    controller.inputText = "first\nsecond"
    controller.setTaskIndex(2)
    var enter = key(Qt.Key_Return)
    controller.dispatchInputKey(enter)
    verify(!enter.accepted)
    var save = key(Qt.Key_Return, Qt.ControlModifier)
    controller.dispatchInputKey(save)
    verify(save.accepted)
    var batch = fixture.requestFor("batch")
    compare(batch.payload.lines, [0, 1])
    compare(batch.payload.bodies, ["first", "second"])
    compare(batch.payload.action, "edit")
  }

  function test_real_bulk_editor_keys_save_each_text_line() {
    var controller = fixture.controller
    var path = "/tmp/super-t-qml-test/typing.md"
    loadListsAndDocument([list(path, "Typing")], path, "- [ ] one\n- [ ] two\n")
    controller.toggleSelection()
    controller.moveTask(1)
    controller.beginInput("edit")
    tryVerify(function() { return fixture.inputBar.editor.activeFocus })
    fixture.inputBar.editor.selectAll()
    keyClick(Qt.Key_A)
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_B)
    compare(controller.inputText, "a\nb")
    compare(fixture.requestFor("batch"), null)
    keyClick(Qt.Key_Return, Qt.ControlModifier)
    compare(fixture.requestFor("batch").payload.bodies, ["a", "b"])
  }

  function test_move_selection_snapshots_and_escape_clears_range_first() {
    var controller = fixture.controller
    var path = "/tmp/super-t-qml-test/source.md"
    var target = "/tmp/super-t-qml-test/target.md"
    loadListsAndDocument([list(path, "Source"), list(target, "Target")], path, taskDocument(5))
    controller.filterText = "task"
    controller.dispatchKey(key(Qt.Key_V))
    controller.dispatchKey(key(Qt.Key_J))
    controller.dispatchKey(key(Qt.Key_M))
    compare(controller.mode, "move")
    controller.dispatchKey(key(Qt.Key_Question))
    compare(controller.mode, "help")
    controller.dispatchKey(key(Qt.Key_Escape))
    compare(controller.mode, "move")
    controller.setTaskIndex(4)
    controller.confirmMove()
    compare(fixture.requestFor("move").payload.lines, [0, 1])
    controller.handleFailure("move", fixture.requestFor("move").id, "Failed")
    controller.cancelMove()
    controller.dispatchKey(key(Qt.Key_Escape))
    verify(!controller.selecting)
    compare(controller.filterText, "task")
    controller.dispatchKey(key(Qt.Key_Escape))
    compare(controller.filterText, "")
    controller.dispatchKey(key(Qt.Key_Less))
    compare(fixture.requestFor("batch").payload.action, "outdent")
  }

  function test_selection_clears_when_document_or_pane_changes() {
    var controller = fixture.controller
    var path = "/tmp/super-t-qml-test/selection.md"
    loadListsAndDocument([list(path, "Selection")], path, taskDocument(3))
    controller.toggleSelection()
    controller.moveTask(1)
    controller.applyRead({ path: path, text: taskDocument(4) }, path)
    verify(!controller.selecting)
    controller.toggleSelection()
    controller.focusPane("lists")
    verify(!controller.selecting)
    controller.dispatchKey(key(Qt.Key_D))
    compare(fixture.requestFor("batch"), null)
  }

  function test_tab_makes_selected_task_a_subtask() {
    var path = "/tmp/super-t-qml-test/nested.md"
    var controller = fixture.controller
    loadListsAndDocument([list(path, "Nested")], path, "- [ ] parent\n* [X] child\n")
    controller.setTaskIndex(1)

    var event = key(Qt.Key_Tab)
    controller.dispatchKey(event)
    verify(event.accepted)
    var write = fixture.requestFor("batch")
    verify(write !== null)
    compare(write.payload.action, "indent")
    compare(write.payload.lines, [1])
    compare(write.payload.expected, "- [ ] parent\n* [X] child\n")
  }

  function test_real_tab_event_reaches_the_dedicated_handler() {
    var path = "/tmp/super-t-qml-test/real-tab.md"
    var controller = fixture.controller
    loadListsAndDocument([list(path, "Real tab")], path, "- [ ] parent\n- [ ] child\n")
    controller.setTaskIndex(1)
    fixture.keyCatcher.forceActiveFocus()
    verify(fixture.keyCatcher.activeFocus)

    keyClick(Qt.Key_Tab)
    var write = fixture.requestFor("batch")
    verify(write !== null)
    compare(write.payload.action, "indent")
    compare(write.payload.lines, [1])
  }

  function test_tab_on_first_task_does_not_write() {
    var path = "/tmp/super-t-qml-test/first-task.md"
    var controller = fixture.controller
    loadListsAndDocument([list(path, "First task")], path, "- [ ] only\n")

    controller.dispatchKey(key(Qt.Key_Tab))
    compare(fixture.requestFor("write"), null)
    verify(controller.statusText.indexOf("above") >= 0)
  }

  function test_restored_second_list_survives_followup_scan() {
    var first = "/tmp/super-t-qml-test/first.md"
    var second = "/tmp/super-t-qml-test/second.md"
    var lists = [list(first, "First"), list(second, "Second")]
    var controller = fixture.controller
    controller.opened = true
    controller.sessionLoaded = true
    controller.savedPosition = { path: second, taskIndex: 0 }

    controller.applyScan({ lists: lists })
    compare(controller.currentPath, second)
    controller.applyRead({ path: second, text: "- [ ] restored\n", tags: [] }, second)
    verify(controller.restoreApplied)
    compare(controller.listIndex, 1)

    controller.selectList(0)
    controller.applyRead({ path: first, text: "- [ ] first\n", tags: [] }, first)
    compare(controller.listIndex, 0)
    controller.applyScan({ lists: lists })
    compare(controller.currentPath, first)
    compare(controller.listIndex, 0)
  }

  function test_stale_scan_after_directory_switch_is_ignored() {
    var controller = fixture.controller
    controller.autoStartBackend = true
    controller.directory = "/tmp/super-t-qml-test/one"
    controller.open()
    var oldScan = fixture.requestFor("scan")
    verify(oldScan !== null)

    controller.directory = "/tmp/super-t-qml-test/two"
    controller.handleSuccess("scan", oldScan.id, {
      lists: [list("/tmp/super-t-qml-test/one/old.md", "Old")]
    })

    compare(controller.lists.length, 0)
    compare(controller.currentPath, "")
  }

  function test_startup_read_failure_finishes_restoration() {
    var controller = fixture.controller
    controller.autoStartBackend = true
    controller.directory = "/tmp/super-t-qml-test"
    controller.open()
    var scan = fixture.requestFor("scan")
    var session = fixture.requestFor("session")
    verify(scan !== null)
    verify(session !== null)

    controller.handleSuccess("session", session.id, {
      position: { path: "/tmp/super-t-qml-test/b.md", taskIndex: 0 }
    })
    controller.handleSuccess("scan", scan.id, {
      lists: [list("/tmp/super-t-qml-test/a.md", "A"), list("/tmp/super-t-qml-test/b.md", "B")]
    })
    var read = fixture.requestFor("read")
    verify(read !== null)
    controller.handleFailure("read", read.id, "Could not read the restored list")

    verify(controller.initialReadReady)
    verify(controller.restoreApplied)
    verify(controller.statusText.indexOf("Could not read") >= 0)
  }

  function test_create_move_and_tag_failures_keep_recoverable_ui() {
    var controller = fixture.controller

    controller.beginInput("list")
    controller.inputText = "New list"
    controller.commitInput()
    var create = fixture.requestFor("create")
    verify(create !== null)
    controller.handleFailure("create", create.id, "A list with that name already exists")
    compare(controller.mode, "input")
    compare(controller.inputText, "New list")
    compare(controller.inputError, "A list with that name already exists")
    verify(!controller.mutationBusy)
    controller.cancelInput()

    var first = "/tmp/super-t-qml-test/a.md"
    var second = "/tmp/super-t-qml-test/b.md"
    loadListsAndDocument([list(first, "A"), list(second, "B")], first, "- [ ] move me\n")
    controller.beginMove()
    compare(controller.mode, "move")
    controller.confirmMove()
    var move = fixture.requestFor("move")
    verify(move !== null)
    controller.handleFailure("move", move.id, "The source list changed; reload and try again")
    compare(controller.mode, "move")
    verify(controller.moveTaskSnapshot !== null)
    verify(!controller.mutationBusy)
    verify(controller.statusText.indexOf("changed") >= 0)
    controller.cancelMove()

    controller.beginInput("tags")
    controller.inputText = "work, urgent"
    controller.commitInput()
    var tags = fixture.requestFor("tags")
    verify(tags !== null)
    controller.handleFailure("tags", tags.id, "Unsupported tags in this list")
    compare(controller.mode, "input")
    compare(controller.inputText, "work, urgent")
    compare(controller.inputError, "Unsupported tags in this list")
    verify(!controller.mutationBusy)
  }

  function test_close_saves_loaded_position_before_immediate_reopen() {
    var path = "/tmp/super-t-qml-test/close.md"
    var controller = fixture.controller
    loadListsAndDocument([list(path, "Close")], path, "- [ ] first\n- [ ] second\n")
    controller.opened = true
    controller.restoreApplied = true
    controller.setTaskIndex(1)

    controller.close()
    var save = fixture.requestFor("save_session")
    verify(save !== null)
    compare(save.payload.position.path, path)
    compare(save.payload.position.taskIndex, 1)
    compare(save.payload.position.line, 1)
    controller.open()
    verify(fixture.requestFor("save_session").id === save.id)
  }

  function test_undo_rereads_tags_for_current_document() {
    var path = "/tmp/super-t-qml-test/tags.md"
    var controller = fixture.controller
    loadListsAndDocument([list(path, "Tags")], path, "---\ntags: [old]\n---\n- [ ] task\n")
    controller.documentTags = ["old"]
    controller.undoTokens = ["undo-token"]
    controller.undo()
    var undo = fixture.requestFor("undo")
    verify(undo !== null)

    controller.handleSuccess("undo", undo.id, {
      restored: [{ path: path, text: "---\ntags: [new]\n---\n- [ ] task\n" }]
    })
    var reread = fixture.requestFor("read")
    verify(reread !== null)
    verify(reread.id > undo.id)
    controller.handleSuccess("read", reread.id, {
      path: path, text: "---\ntags: [new]\n---\n- [ ] task\n", tags: ["new"]
    })
    compare(controller.documentTags.length, 1)
    compare(controller.documentTags[0], "new")
  }
}
