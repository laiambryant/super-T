import QtQuick
import QtTest
import "../.." as App

TestCase {
  id: suite
  name: "TodoPanel"
  when: windowShown
  width: 960
  height: 620
  visible: true
  property var fixture: null

  Component {
    id: fixtureComponent
    Item {
      id: fixtureRoot
      width: 960
      height: 620
      property var calls: []
      property alias controller: controller
      property alias panel: panel
      signal succeeded(string op, int requestId, var data)
      signal failed(string op, int requestId, string error)
      function request(op, payload) {
        calls = calls.concat([{ op: op, payload: payload }])
        return calls.length
      }

      App.TodoController {
        id: controller
        backend: fixtureRoot
        autoStartBackend: false
        directory: "/tmp/super-t-panel-test"
      }

      App.TodoPanel {
        id: panel
        anchors.fill: parent
        controller: controller
        directory: controller.directory
        configurationError: ""
        background: "#171a19"
        foreground: "#e1e6e1"
        accent: "#adcaad"
        fontFamily: "sans-serif"
      }
    }
  }

  function init() {
    fixture = createTemporaryObject(fixtureComponent, suite)
    verify(fixture)
    var controller = fixture.controller
    controller.applyScan({ ok: true, lists: [{ name: "Inbox", path: controller.directory + "/inbox.md", total: 2, done: 0 }] })
    controller.listIndex = 0
    controller.applyRead({ ok: true, path: controller.currentPath, tags: [], text: "- [ ] First task\n- [ ] Second task\n" }, controller.currentPath)
    controller.dataReady = true
    fixture.panel.focusKeyboard()
    wait(20)
  }

  function test_mouse_editor_returns_to_keyboard_navigation() {
    var button = findChild(fixture.panel, "addTaskButton")
    verify(button)
    mouseClick(button)
    compare(fixture.controller.mode, "input")
    wait(20)
    keyClick(Qt.Key_A)
    compare(fixture.controller.inputText, "a")
    compare(fixture.controller.taskIndex, 0)
    keyClick(Qt.Key_Escape)
    compare(fixture.controller.mode, "normal")
    wait(20)
    keyClick(Qt.Key_J)
    compare(fixture.controller.taskIndex, 1)
  }

  function test_filter_button_routes_typing_to_filter() {
    mouseClick(findChild(fixture.panel, "filterButton"))
    compare(fixture.controller.mode, "filter")
    wait(20)
    keyClick(Qt.Key_S)
    compare(fixture.controller.filterText, "s")
    compare(fixture.controller.mode, "filter")
    keyClick(Qt.Key_Escape)
    compare(fixture.controller.filterText, "")
    compare(fixture.controller.mode, "normal")
  }

  function test_modal_blocks_underlying_actions() {
    fixture.controller.toggleSummary()
    var button = findChild(fixture.panel, "addTaskButton")
    verify(!button.enabled)
    mouseClick(button)
    compare(fixture.controller.mode, "summary")
    keyClick(Qt.Key_Escape)
    compare(fixture.controller.mode, "normal")
  }
}
