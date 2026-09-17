import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui as Ui
import "Config.js" as Config

Ui.BarWidget {
  id: root
  moduleName: "liambryant.todo"

  property string home: Quickshell.env("HOME")
  property var pluginDir: undefined
  property string configError: ""
  property bool configReady: false
  readonly property var rawDir: settings && settings.dir !== undefined ? settings.dir : pluginDir
  readonly property var resolved: Config.resolve(rawDir, home)
  readonly property string todoDir: resolved.ok ? resolved.path : ""
  readonly property string validationError: configError || (resolved.ok ? "" : resolved.error)
  property string scanError: ""
  readonly property string errorText: validationError || scanError
  property int openCount: 0
  property int doneCount: 0
  property int scanRequest: -1
  property string scanDirectory: ""
  property bool refreshPending: false
  readonly property string glyph: "󰝕"

  function refresh() {
    if (!configReady) return
    if (validationError) {
      openCount = 0
      doneCount = 0
      return
    }
    if (backend.busy) { refreshPending = true; return }
    refreshPending = false
    scanDirectory = todoDir
    scanRequest = backend.request("scan", {})
  }

  function applyScan(data) {
    var open = 0, done = 0
    var lists = Array.isArray(data.lists) ? data.lists : []
    for (var i = 0; i < lists.length; i++) {
      open += Number(lists[i].total || 0) - Number(lists[i].done || 0)
      done += Number(lists[i].done || 0)
    }
    openCount = open
    doneCount = done
    scanError = ""
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onTodoDirChanged: { scanError = ""; refresh() }
  onValidationErrorChanged: refresh()

  BackendBridge {
    id: backend
    directory: root.todoDir
    servicePath: decodeURIComponent(String(Qt.resolvedUrl("service.py")).replace(/^file:\/\//, ""))
    onSucceeded: function(op, requestId, data) {
      if (op === "scan" && requestId === root.scanRequest && root.scanDirectory === root.todoDir)
        root.applyScan(data)
    }
    onFailed: function(op, requestId, error) {
      if (requestId === root.scanRequest && root.scanDirectory === root.todoDir) {
        root.scanError = error
        root.openCount = 0
        root.doneCount = 0
      }
    }
    onBusyChanged: if (!busy && root.refreshPending) Qt.callLater(root.refresh)
  }

  Timer { running: true; interval: 15000; repeat: true; onTriggered: root.refresh() }
  Timer { id: settleTimer; interval: 700; onTriggered: root.refresh() }

  FileView {
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var result = Config.fromShell(text(), root.moduleName)
      root.configReady = false
      root.configError = result.ok ? "" : result.error
      root.pluginDir = result.value
      root.configReady = true
      root.refresh()
    }
    onLoadFailed: function(error) {
      root.configReady = false
      root.configError = error === FileViewError.FileNotFound ? "" : "Cannot read shell.json: " + FileViewError.toString(error)
      root.pluginDir = undefined
      root.configReady = true
      root.refresh()
    }
  }

  Ui.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.openCount > 0 || !!root.errorText
    useActiveColor: false
    text: root.errorText ? (root.vertical ? "!" : root.glyph + "  !")
      : (root.vertical ? String(root.openCount) : root.glyph + "  " + root.openCount)
    tooltipText: root.errorText || (root.openCount + " open, " + root.doneCount + " done — " + root.todoDir)
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else if (b === Qt.RightButton && !root.errorText)
        Quickshell.execDetached(["omarchy-launch-editor", root.todoDir])
      else {
        Quickshell.execDetached(["omarchy-shell", "-q", "shell", "toggle", root.moduleName])
        settleTimer.restart()
      }
    }
  }
}
