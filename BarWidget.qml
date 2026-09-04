import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar pill showing how many tasks are still open across every list. Left click
// opens the todo overlay; the two share no state, so the pill re-scans on a
// timer and immediately after a click closes the overlay.
BarWidget {
  id: root
  moduleName: "liambryant.todo"

  property string home: Quickshell.env("HOME")

  // The directory can be set either on this bar entry or on the plugin entry
  // in shell.json; the bar entry wins so a second pill could watch a second
  // directory if that is ever wanted.
  property string pluginDir: ""
  readonly property string configuredDir: String(setting("dir", "") || pluginDir)
  readonly property string todoDir: expandPath(configuredDir || (home + "/Documents/todos"))

  property int openCount: 0
  property int doneCount: 0
  property bool scanned: false

  readonly property string glyph: "󰝕"

  function expandPath(path) {
    var value = String(path || "").trim()
    if (value.charAt(0) === "~") value = root.home + value.slice(1)
    return value.replace(/\/+$/, "")
  }

  function scriptPath(name) {
    return String(Qt.resolvedUrl(name)).replace(/^file:\/\//, "")
  }

  function refresh() {
    if (scanProc.running) return
    scanProc.command = [root.scriptPath("scan.sh"), root.todoDir]
    scanProc.running = true
  }

  function applyScan(raw) {
    var open = 0
    var done = 0
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      var lists = Array.isArray(parsed.lists) ? parsed.lists : []
      for (var i = 0; i < lists.length; i++) {
        open += Number(lists[i].total || 0) - Number(lists[i].done || 0)
        done += Number(lists[i].done || 0)
      }
    } catch (e) {
      open = 0
      done = 0
    }
    root.openCount = open
    root.doneCount = done
    root.scanned = true
  }

  // Hidden until the first scan lands so the bar does not flash a zero on
  // startup, and hidden afterwards only if the directory has no lists at all.
  visible: scanned && (openCount > 0 || doneCount > 0)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onTodoDirChanged: refresh()
  Component.onCompleted: refresh()

  Process {
    id: scanProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyScan(text)
    }
  }

  Timer {
    running: true
    interval: 15000
    repeat: true
    onTriggered: root.refresh()
  }

  // Catches edits made in the overlay (or an editor) shortly after they happen
  // without polling hard.
  Timer {
    id: settleTimer
    interval: 700
    repeat: false
    onTriggered: root.refresh()
  }

  FileView {
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var dir = ""
      try {
        var config = JSON.parse(text())
        var entries = Array.isArray(config.plugins) ? config.plugins : []
        for (var i = 0; i < entries.length; i++) {
          if (entries[i] && String(entries[i].id) === root.moduleName) {
            dir = String(entries[i].dir || "")
            break
          }
        }
      } catch (e) {
        dir = ""
      }
      root.pluginDir = dir
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.openCount > 0
    useActiveColor: false
    text: root.vertical ? String(root.openCount) : (root.glyph + "  " + root.openCount)
    tooltipText: root.openCount + " open, " + root.doneCount + " done — " + root.todoDir

    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        root.refresh()
      } else if (b === Qt.RightButton) {
        Quickshell.execDetached(["omarchy-launch-editor", root.todoDir])
      } else {
        Quickshell.execDetached(["omarchy-shell", "-q", "shell", "toggle", root.moduleName])
        settleTimer.restart()
      }
    }
  }
}
