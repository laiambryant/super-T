import QtQuick
import Quickshell
import Quickshell.Io
import "Config.js" as Config

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property string home: Quickshell.env("HOME")
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "liambryant.todo"
  readonly property string sourceDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""

  property var rawDir: undefined
  property string configError: ""
  property bool configReady: false
  readonly property var resolvedDirectory: Config.resolve(rawDir, home)
  readonly property string todoDir: resolvedDirectory.ok ? resolvedDirectory.path : ""
  readonly property string validationError: configError || (resolvedDirectory.ok ? "" : resolvedDirectory.error)
  readonly property string controllerDirectory: configReady && !validationError ? todoDir : ""
  readonly property string controllerError: configReady ? validationError : "Loading todo settings…"
  property alias opened: todoController.opened

  function scriptPath(name) {
    return decodeURIComponent(String(Qt.resolvedUrl(name)).replace(/^file:\/\//, ""))
  }

  function notifyBarWidget() {
    var bar = shell ? shell.bar : null
    if (!bar || typeof bar.moduleWidgets !== "function") return
    var widgets = bar.moduleWidgets(pluginId)
    for (var i = 0; i < widgets.length; i++) {
      if (widgets[i] && typeof widgets[i].refresh === "function") widgets[i].refresh()
    }
  }

  function hideShell() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  function open(payloadJson) { todoController.open() }
  function close() { todoController.close() }
  function dismiss() { todoController.dismiss() }
  function toggle() { todoController.toggle() }

  function startAfterConfig() {
    if (todoController.opened && configReady && !validationError) todoController.startOpenLoad()
  }

  onConfigReadyChanged: Qt.callLater(startAfterConfig)
  onValidationErrorChanged: Qt.callLater(startAfterConfig)

  BackendBridge {
    id: serviceBridge
    directory: root.controllerDirectory
    servicePath: root.scriptPath("service.py")
  }

  TodoController {
    id: todoController
    directory: root.controllerDirectory
    configurationError: root.controllerError
    backend: serviceBridge
    onBarRefreshRequested: root.notifyBarWidget()
    onDismissed: root.hideShell()
  }

  TodoOverlay {
    controller: todoController
    directory: root.todoDir
    configurationError: root.controllerError
  }
  FileView {
    id: documentWatch
    path: todoController.currentPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      if (path === todoController.currentPath && todoController.opened) todoController.reloadCurrentFromDisk()
    }
  }
  Timer {
    running: todoController.opened && todoController.directory !== "" && todoController.configurationError === ""
    interval: 5000
    repeat: true
    onTriggered: todoController.refreshLists()
  }

  FileView {
    id: configFile
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var result = Config.fromShell(text(), root.pluginId)
      root.rawDir = result.ok ? result.value : undefined
      root.configError = result.ok ? "" : result.error
      root.configReady = true
    }
    onLoadFailed: function(error) {
      root.rawDir = undefined
      root.configError = error === FileViewError.FileNotFound ? ""
        : "Cannot read shell.json: " + FileViewError.toString(error)
      root.configReady = true
    }
  }
}
