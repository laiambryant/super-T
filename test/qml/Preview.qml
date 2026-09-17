import QtQuick
import "../.." as App

Rectangle {
  id: preview
  readonly property bool light: Qt.application.arguments.indexOf("--light") >= 0
  readonly property bool compact: Qt.application.arguments.indexOf("--compact") >= 0
  readonly property string mode: Qt.application.arguments.indexOf("--summary") >= 0 ? "summary"
    : Qt.application.arguments.indexOf("--input") >= 0 ? "input"
    : Qt.application.arguments.indexOf("--help-view") >= 0 ? "help" : "normal"
  width: compact ? 640 : 960
  height: compact ? 480 : 620
  color: light ? "#f8f9f6" : "#171a19"

  App.TodoController {
    id: demo
    autoStartBackend: false
    backend: QtObject {
      function request(op, payload) { return 1 }
      signal succeeded(string op, int requestId, var data)
      signal failed(string op, int requestId, string error)
    }
    directory: "/tmp/super-t-preview"
    Component.onCompleted: {
      applyScan({ ok: true, lists: [
        { name: "Today", path: directory + "/today.md", total: 7, done: 2 },
        { name: "Projects", path: directory + "/projects.md", total: 8, done: 3 },
        { name: "Personal", path: directory + "/personal.md", total: 4, done: 1 },
        { name: "Someday", path: directory + "/someday.md", total: 3, done: 0 }
      ] })
      listIndex = 0
      applyRead({ ok: true, path: currentPath, tags: ["focus"], text:
        "# Today\n\n- [x] Make a little room to think\n- [x] Plan the week ahead\n- [ ] Design something with care\n  - [ ] Find the simplest version\n  - [ ] Give the details some attention\n- [ ] Take a walk, leave the phone\n- [ ] Read a few pages\n"
      }, currentPath)
      taskIndex = 2
      dataReady = true
      mode = preview.mode
      if (mode === "input") { inputPurpose = "add"; inputText = "A new idea" }
      if (Qt.application.arguments.indexOf("--empty") >= 0) { lists = []; allTasks = []; tasks = [] }
      summary = { total: 22, done: 6, percent: 27, closedToday: 2, streak: 4 }
    }
  }

  App.TodoPanel {
    anchors.fill: parent
    controller: demo
    directory: demo.directory
    configurationError: ""
    background: preview.color
    foreground: preview.light ? "#282f2b" : "#e1e6e1"
    accent: preview.light ? "#426a4e" : "#adcaad"
    fontFamily: "Inter"
    fontSize: 14
    cornerRadius: 6
  }

  Timer {
    interval: 800
    running: true
    onTriggered: {
      preview.grabToImage(function(result) {
        var destination = Qt.application.arguments.indexOf("--output")
        var path = destination >= 0 ? Qt.application.arguments[destination + 1]
          : Qt.resolvedUrl("../../docs/preview.png").toString().replace("file://", "")
        if (!result.saveToFile(path)) throw new Error("Could not save preview: " + path)
        Qt.quit()
      })
    }
  }
}
