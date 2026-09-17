import QtQuick
import Quickshell.Io

Item {
  id: bridge
  visible: false
  width: 0
  height: 0

  required property string servicePath
  property string directory: ""
  readonly property bool busy: active !== null || completing || queue.length > 0 || process.running
  readonly property int queuedCount: queue.length + (active ? 1 : 0)

  property int nextRequestId: 1
  property var queue: []
  property var active: null
  property bool completing: false

  signal succeeded(string op, int requestId, var data)
  signal failed(string op, int requestId, string error)
  signal started(string op, int requestId)
  function request(op, payload) {
    var request = { op: String(op), dir: String(directory || "") }
    var values = payload || {}
    for (var key in values) {
      if (Object.prototype.hasOwnProperty.call(values, key)) request[key] = values[key]
    }

    var id = nextRequestId++
    queue = queue.concat([{ id: id, op: request.op, payload: request }])
    startNext()
    return id
  }

  function startNext() {
    if (active !== null || process.running || queue.length === 0) return
    active = queue[0]
    queue = queue.slice(1)
    completing = false
    process.stdinEnabled = true
    process.command = ["python3", "-B", servicePath]
    process.running = true
  }

  function sendActiveRequest() {
    if (active === null) return
    started(active.op, active.id)
    process.write(JSON.stringify(active.payload) + "\n")
    process.stdinEnabled = false
  }

  function complete(raw, exitCode) {
    if (active === null || completing) return
    completing = true

    var job = active
    active = null
    var reply = null
    try {
      reply = JSON.parse(String(raw || ""))
    } catch (error) {
      failed(job.op, job.id, "Todo service returned invalid JSON"
        + (exitCode === 0 ? "" : " (exit " + exitCode + ")"))
      completing = false
      if (!process.running) startNext()
      return
    }

    if (!reply || reply.ok !== true) {
      failed(job.op, job.id, String(reply && reply.error ? reply.error : "Todo service request failed"))
    } else {
      succeeded(job.op, job.id, reply)
    }
    completing = false
    if (!process.running) startNext()
  }

  Process {
    id: process
    stdinEnabled: false
    stdout: StdioCollector {
      id: response
      waitForEnd: true
    }
    onStarted: bridge.sendActiveRequest()
    onExited: bridge.complete(response.text, 0)
    onRunningChanged: if (!running) bridge.startNext()
  }
}
