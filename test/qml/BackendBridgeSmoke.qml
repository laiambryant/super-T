import QtQuick
import Quickshell
ShellRoot {
  id: root

  readonly property string todoDirectory: String(Quickshell.env("SUPER_T_SMOKE_DIR") || "")
  readonly property string servicePath: String(Quickshell.env("SUPER_T_SERVICE_PATH") || "")
  property int scanId: -1
  property int readId: -1
  property int missingReadId: -1
  property bool scanGood: false
  property bool readGood: false
  property bool missingReadGood: false
  property bool finished: false

  function fail(message) {
    if (finished) return
    finished = true
    console.error("BackendBridge smoke failed: " + message)
  }

  function finishIfReady() {
    if (scanGood && readGood && missingReadGood && !finished) {
      finished = true
      console.log("BackendBridge smoke passed: queued scan/read/error round trip")
    }
  }

  BackendBridge {
    id: bridge
    directory: root.todoDirectory
    servicePath: root.servicePath

    onSucceeded: function(op, requestId, data) {
      if (requestId === root.scanId && op === "scan") {
        root.scanGood = Array.isArray(data.lists) && data.lists.length === 2
        if (!root.scanGood) root.fail("scan reply did not contain two lists")
      } else if (requestId === root.readId && op === "read") {
        root.readGood = String(data.path || "") === root.todoDirectory + "/alpha.md"
          && String(data.text || "").indexOf("bridge smoke") >= 0
        if (!root.readGood) root.fail("read reply did not contain alpha.md text")
      } else {
        root.fail("unexpected successful reply " + op + "#" + requestId)
      }
      root.finishIfReady()
    }

    onFailed: function(op, requestId, error) {
      if (requestId === root.missingReadId && op === "read" && String(error || "") !== "") {
        root.missingReadGood = true
        root.finishIfReady()
      } else {
        root.fail("unexpected failed reply " + op + "#" + requestId + ": " + error)
      }
    }
  }

  Component.onCompleted: {
    if (!todoDirectory || !servicePath) {
      fail("SUPER_T_SMOKE_DIR or SUPER_T_SERVICE_PATH is not set")
      return
    }
    scanId = bridge.request("scan", {})
    readId = bridge.request("read", { path: todoDirectory + "/alpha.md" })
    missingReadId = bridge.request("read", { path: todoDirectory + "/missing.md" })
  }

  Timer {
    interval: 5000
    running: !root.finished
    onTriggered: root.fail("timed out waiting for service replies")
  }
}
