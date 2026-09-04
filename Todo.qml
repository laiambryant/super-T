import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "TodoDoc.js" as TodoDoc

// Fullscreen todo overlay. Lists are markdown files under a configurable
// directory; the file on disk stays the source of truth, and every edit is a
// single-line rewrite so anything that is not a task line survives verbatim.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) ? String(manifest.id) : "liambryant.todo"
  readonly property string sourceDir: (manifest && manifest.__sourceDir) ? String(manifest.__sourceDir) : ""
  property string home: Quickshell.env("HOME")

  // ------------------------------------------------------------- config

  // Set in ~/.config/omarchy/shell.json under plugins[] and hot-reloaded:
  //   { "id": "liambryant.todo", "dir": "~/Documents/todos" }
  property string configuredDir: ""
  readonly property string todoDir: expandPath(configuredDir || (home + "/Documents/todos"))

  // -------------------------------------------------------------- state

  property bool opened: false
  property var lists: []
  property int listIndex: 0
  property string docText: ""
  property var tasks: []
  property int taskIndex: 0
  property string filterText: ""
  property string mode: "normal"     // normal | filter | input
  property string inputPurpose: ""   // add | edit
  property int inputLine: -1
  property var undoStack: []
  property string statusText: ""
  property bool scanOk: true

  readonly property var currentList: (listIndex >= 0 && listIndex < lists.length) ? lists[listIndex] : null
  readonly property string currentPath: currentList ? String(currentList.path) : ""

  // --------------------------------------------------------------- theme

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color accent: Color.accent
  // Nerd Font glyphs, not the Unicode ballot characters: those get resolved to
  // the colour emoji font and stop following the theme foreground.
  readonly property string glyphUnchecked: "󰄱"
  readonly property string glyphChecked: "󰄲"
  readonly property string glyphAdd: "󰐕"
  readonly property string glyphEdit: "󰲶"

  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int rowHeight: Math.max(Style.space(28), Style.font.subtitle + Style.spacing.controlPaddingY * 2)
  property int headerHeight: Math.max(Style.space(30), Style.font.heading + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Math.max(Style.space(20), Style.font.caption + Style.spacing.sm * 2)

  // ------------------------------------------------------------ helpers

  function expandPath(path) {
    var value = String(path || "").trim()
    if (value.charAt(0) === "~") value = root.home + value.slice(1)
    return value.replace(/\/+$/, "")
  }

  function scriptPath(name) {
    return String(Qt.resolvedUrl(name)).replace(/^file:\/\//, "")
  }

  function notifyBarWidget() {
    var bar = root.shell ? root.shell.bar : null
    if (!bar || typeof bar.moduleWidgets !== "function") return
    var widgets = bar.moduleWidgets(root.pluginId)
    for (var i = 0; i < widgets.length; i++) {
      if (widgets[i] && typeof widgets[i].refresh === "function") widgets[i].refresh()
    }
  }

  function flash(message) {
    root.statusText = String(message || "")
    statusTimer.restart()
  }

  // ------------------------------------------------------- open / close

  function open(payloadJson) {
    root.opened = true
    root.mode = "normal"
    root.filterText = ""
    root.statusText = ""
    root.rescan()
    if (root.currentPath) docFile.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.mode = "normal"
    root.inputPurpose = ""
    root.inputLine = -1
    inputField.text = ""
    root.notifyBarWidget()
  }

  function dismiss() {
    root.opened = false
    root.mode = "normal"
    root.inputPurpose = ""
    root.inputLine = -1
    inputField.text = ""
    root.notifyBarWidget()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ------------------------------------------------------------ scanning

  function rescan() {
    if (scanProc.running) return
    scanProc.command = [root.scriptPath("scan.sh"), root.todoDir]
    scanProc.running = true
  }

  function applyScan(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || "{}"))
    } catch (e) {
      root.scanOk = false
      root.lists = []
      return
    }

    var keepPath = root.currentPath
    root.scanOk = parsed.ok === true
    root.lists = Array.isArray(parsed.lists) ? parsed.lists : []

    var next = 0
    for (var i = 0; i < root.lists.length; i++) {
      if (String(root.lists[i].path) === keepPath) { next = i; break }
    }
    root.listIndex = root.lists.length ? Math.min(next, root.lists.length - 1) : 0
  }

  // Keep the sidebar counts truthful the instant we write, without waiting for
  // the next scan to come back.
  function refreshLocalCounts() {
    if (!root.currentList) return
    var c = TodoDoc.counts(root.docText)
    var copy = root.lists.slice()
    copy[root.listIndex] = {
      path: root.currentList.path,
      name: root.currentList.name,
      total: c.total,
      done: c.done
    }
    root.lists = copy
  }

  // -------------------------------------------------------------- tasks

  function rebuildTasks() {
    var all = TodoDoc.parse(root.docText)
    var out = []
    for (var i = 0; i < all.length; i++) {
      if (TodoDoc.matches(all[i], root.filterText)) out.push(all[i])
    }
    root.tasks = out
    if (root.taskIndex >= out.length) root.taskIndex = Math.max(0, out.length - 1)
    if (root.taskIndex < 0) root.taskIndex = 0
    Qt.callLater(function() {
      if (root.tasks.length) taskList.positionViewAtIndex(root.taskIndex, ListView.Contain)
    })
  }

  onDocTextChanged: rebuildTasks()
  onFilterTextChanged: rebuildTasks()

  function selectedTask() {
    if (root.taskIndex < 0 || root.taskIndex >= root.tasks.length) return null
    return root.tasks[root.taskIndex]
  }

  function moveTask(delta) {
    if (!root.tasks.length) return
    root.taskIndex = Math.max(0, Math.min(root.tasks.length - 1, root.taskIndex + delta))
    taskList.positionViewAtIndex(root.taskIndex, ListView.Contain)
  }

  function moveList(delta) {
    if (!root.lists.length) return
    root.listIndex = (root.listIndex + delta + root.lists.length) % root.lists.length
    root.taskIndex = 0
    root.filterText = ""
    listColumn.positionViewAtIndex(root.listIndex, ListView.Contain)
  }

  // ------------------------------------------------------------- writing

  function commit(nextText, message) {
    if (nextText === null || nextText === undefined) return false
    if (!root.currentPath) return false

    root.undoStack = root.undoStack.concat([{ path: root.currentPath, text: root.docText }]).slice(-40)
    root.docText = nextText
    docFile.setText(nextText)
    root.refreshLocalCounts()
    notifyTimer.restart()
    if (message) root.flash(message)
    return true
  }

  function toggleSelected() {
    var task = root.selectedTask()
    if (!task) return
    root.commit(TodoDoc.setChecked(root.docText, task.line, !task.checked), "")
  }

  function deleteSelected() {
    var task = root.selectedTask()
    if (!task) return
    var index = root.taskIndex
    if (root.commit(TodoDoc.removeTask(root.docText, task.line), "Deleted — press u to undo")) {
      root.taskIndex = Math.max(0, Math.min(index, root.tasks.length - 1))
    }
  }

  function undo() {
    if (!root.undoStack.length) {
      root.flash("Nothing to undo")
      return
    }
    var stack = root.undoStack.slice()
    var entry = stack.pop()
    root.undoStack = stack

    if (entry.path !== root.currentPath) {
      for (var i = 0; i < root.lists.length; i++) {
        if (String(root.lists[i].path) === entry.path) { root.listIndex = i; break }
      }
    }
    root.docText = entry.text
    docFile.setText(entry.text)
    root.refreshLocalCounts()
    notifyTimer.restart()
    root.flash("Undone")
  }

  // -------------------------------------------------------------- input

  function beginAdd() {
    if (!root.currentPath) {
      root.flash("No list selected")
      return
    }
    root.mode = "input"
    root.inputPurpose = "add"
    root.inputLine = -1
    inputField.text = ""
    Qt.callLater(function() { inputField.forceActiveFocus() })
  }

  function beginEdit() {
    var task = root.selectedTask()
    if (!task) return
    root.mode = "input"
    root.inputPurpose = "edit"
    root.inputLine = task.line
    inputField.text = task.text
    Qt.callLater(function() {
      inputField.forceActiveFocus()
      inputField.selectAll()
    })
  }

  function cancelInput() {
    root.mode = "normal"
    root.inputPurpose = ""
    root.inputLine = -1
    inputField.text = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function commitInput() {
    var body = inputField.text
    if (root.inputPurpose === "add") {
      var result = TodoDoc.appendTask(root.docText, body)
      if (result && root.commit(result.text, "Added")) {
        // Land the cursor on the task that was just created.
        for (var i = 0; i < root.tasks.length; i++) {
          if (root.tasks[i].line === result.line) { root.taskIndex = i; break }
        }
      }
    } else if (root.inputPurpose === "edit") {
      root.commit(TodoDoc.setTaskText(root.docText, root.inputLine, body), "Saved")
    }
    root.cancelInput()
  }

  // ----------------------------------------------------------- processes

  Process {
    id: scanProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyScan(text)
    }
  }

  Timer {
    id: notifyTimer
    interval: 250
    onTriggered: root.notifyBarWidget()
  }

  Timer {
    id: statusTimer
    interval: 2500
    onTriggered: root.statusText = ""
  }

  // A rescan while the overlay is open catches lists added or edited from an
  // editor. The open file itself is watched directly by docFile.
  Timer {
    running: root.opened
    interval: 5000
    repeat: true
    onTriggered: root.rescan()
  }

  FileView {
    id: docFile
    path: root.currentPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.docText = text()
    onFileChanged: reload()
    onLoadFailed: root.docText = ""
  }

  // Config lives in the user's shell.json so it hot-reloads like every other
  // Omarchy shell setting.
  FileView {
    id: configFile
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
          if (entries[i] && String(entries[i].id) === root.pluginId) {
            dir = String(entries[i].dir || "")
            break
          }
        }
      } catch (e) {
        dir = ""
      }
      root.configuredDir = dir
    }
  }

  onTodoDirChanged: root.rescan()
  Component.onCompleted: root.rescan()

  // ---------------------------------------------------------------- view

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-todo"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(900), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.mode !== "input"

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.mode === "input") return

          var shift = (event.modifiers & Qt.ShiftModifier) !== 0

          if (event.key === Qt.Key_Escape) {
            if (root.filterText || root.mode === "filter") {
              root.filterText = ""
              root.mode = "normal"
            } else {
              root.dismiss()
            }
            event.accepted = true
            return
          }

          // Filter mode swallows printable keys so list names and task text
          // can be searched for without colliding with the command keys.
          if (root.mode === "filter") {
            if (event.key === Qt.Key_Backspace) {
              root.filterText = root.filterText.slice(0, -1)
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.mode = "normal"
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Up) { root.moveTask(-1); event.accepted = true; return }
            if (event.key === Qt.Key_Down) { root.moveTask(1); event.accepted = true; return }
            if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                && event.text.charCodeAt(0) !== 127) {
              root.filterText += event.text
              event.accepted = true
              return
            }
            return
          }

          switch (event.key) {
          case Qt.Key_Down:
          case Qt.Key_J:
            root.moveTask(1); event.accepted = true; return
          case Qt.Key_Up:
          case Qt.Key_K:
            root.moveTask(-1); event.accepted = true; return
          case Qt.Key_Left:
          case Qt.Key_H:
            root.moveList(-1); event.accepted = true; return
          case Qt.Key_Right:
          case Qt.Key_L:
            root.moveList(1); event.accepted = true; return
          case Qt.Key_Tab:
            root.moveList(1); event.accepted = true; return
          case Qt.Key_Backtab:
            root.moveList(-1); event.accepted = true; return
          case Qt.Key_PageDown:
            root.moveTask(10); event.accepted = true; return
          case Qt.Key_PageUp:
            root.moveTask(-10); event.accepted = true; return
          case Qt.Key_Home:
            root.taskIndex = 0; event.accepted = true; return
          case Qt.Key_End:
            root.taskIndex = Math.max(0, root.tasks.length - 1); event.accepted = true; return
          case Qt.Key_G:
            root.taskIndex = shift ? Math.max(0, root.tasks.length - 1) : 0
            taskList.positionViewAtIndex(root.taskIndex, ListView.Contain)
            event.accepted = true; return
          case Qt.Key_Space:
          case Qt.Key_X:
            root.toggleSelected(); event.accepted = true; return
          case Qt.Key_Return:
          case Qt.Key_Enter:
          case Qt.Key_E:
            root.beginEdit(); event.accepted = true; return
          case Qt.Key_A:
          case Qt.Key_O:
            root.beginAdd(); event.accepted = true; return
          case Qt.Key_D:
            root.deleteSelected(); event.accepted = true; return
          case Qt.Key_U:
            root.undo(); event.accepted = true; return
          case Qt.Key_R:
            root.rescan()
            if (root.currentPath) docFile.reload()
            root.flash("Reloaded")
            event.accepted = true; return
          case Qt.Key_Slash:
            root.mode = "filter"; event.accepted = true; return
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        // ------------------------------------------------------- header
        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.mode === "filter" ? ("/" + root.filterText) : "Todo"
            color: root.mode === "filter" ? root.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          Text {
            anchors.right: parent.right
            anchors.left: title.right
            anchors.leftMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: root.filterText && root.mode !== "filter"
              ? ("filter: " + root.filterText)
              : root.todoDir
            color: root.foreground
            opacity: 0.5
            elide: Text.ElideLeft
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // --------------------------------------------------------- body
        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.footerHeight
                  - (inputRow.visible ? inputRow.height + Style.spacing.md : 0)
                  - Style.spacing.md * 2

          Row {
            anchors.fill: parent
            spacing: Style.spacing.lg
            visible: root.lists.length > 0

            // ------------------------------------------------- sidebar
            ListView {
              id: listColumn
              width: Math.min(Style.space(240), parent.width * 0.32)
              height: parent.height
              model: root.lists
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              currentIndex: root.listIndex

              delegate: Rectangle {
                required property int index
                required property var modelData

                readonly property bool isCurrent: index === root.listIndex
                readonly property bool complete: modelData.total > 0 && modelData.done === modelData.total

                width: listColumn.width
                height: root.rowHeight
                radius: root.cornerRadius
                color: isCurrent ? root.selectedBackground : "transparent"

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.spacing.controlPaddingX
                  anchors.rightMargin: Style.spacing.controlPaddingX
                  spacing: Style.spacing.sm

                  Text {
                    width: parent.width - countLabel.width - Style.spacing.sm
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.name
                    color: isCurrent ? root.selectedText : root.foreground
                    opacity: complete ? 0.55 : 1
                    elide: Text.ElideMiddle
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                  }

                  Text {
                    id: countLabel
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.total - modelData.done
                    color: isCurrent ? root.selectedText : root.foreground
                    opacity: (modelData.total - modelData.done) > 0 ? 0.75 : 0.35
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.listIndex = index
                    root.taskIndex = 0
                    root.filterText = ""
                  }
                }
              }
            }

            Rectangle {
              width: Math.max(1, Style.space(1))
              height: parent.height
              color: root.foreground
              opacity: 0.12
            }

            // --------------------------------------------------- tasks
            Item {
              width: parent.width - listColumn.width - Style.spacing.lg * 2 - Style.space(1)
              height: parent.height

              ListView {
                id: taskList
                anchors.fill: parent
                model: root.tasks
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: root.tasks.length > 0

                delegate: Rectangle {
                  required property int index
                  required property var modelData

                  readonly property bool isCurrent: index === root.taskIndex

                  width: taskList.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: isCurrent ? root.selectedBackground : "transparent"

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.spacing.controlPaddingX + modelData.indent * Style.space(8)
                    anchors.rightMargin: Style.spacing.controlPaddingX
                    spacing: Style.spacing.lg

                    Text {
                      id: box
                      height: parent.height
                      verticalAlignment: Text.AlignVCenter
                      text: modelData.checked ? root.glyphChecked : root.glyphUnchecked
                      color: modelData.checked ? root.accent
                        : (isCurrent ? root.selectedText : root.foreground)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                    }

                    Text {
                      width: parent.width - box.width - Style.spacing.lg
                      height: parent.height
                      verticalAlignment: Text.AlignVCenter
                      text: modelData.text
                      color: isCurrent ? root.selectedText : root.foreground
                      opacity: modelData.checked ? 0.5 : 1
                      font.strikeout: modelData.checked
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.subtitle
                      elide: Text.ElideRight
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: if (containsMouse) root.taskIndex = index
                    onClicked: {
                      root.taskIndex = index
                      root.toggleSelected()
                    }
                  }
                }
              }

              Text {
                anchors.centerIn: parent
                visible: root.tasks.length === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.filterText
                  ? ("No tasks matching “" + root.filterText + "”")
                  : "No tasks yet — press a to add one"
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }
            }
          }

          // --------------------------------------------- empty directory
          Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: Style.spacing.lg
            visible: root.lists.length === 0

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.scanOk ? "No markdown lists found in" : "Directory not found"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.todoDir
              color: root.accent
              elide: Text.ElideMiddle
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: "Add a .md file there, or set a different path in\n"
                + "~/.config/omarchy/shell.json under plugins[]:\n"
                + "{ \"id\": \"" + root.pluginId + "\", \"dir\": \"~/todos\" }"
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // -------------------------------------------------------- input
        Rectangle {
          id: inputRow
          width: parent.width
          height: root.rowHeight
          radius: root.cornerRadius
          visible: root.mode === "input"
          color: root.selectedBackground

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.controlPaddingX
            spacing: Style.spacing.lg

            Text {
              id: inputBox
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              text: root.inputPurpose === "add" ? root.glyphAdd : root.glyphEdit
              color: root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            TextInput {
              id: inputField
              width: parent.width - inputBox.width - Style.spacing.lg
              height: parent.height
              verticalAlignment: TextInput.AlignVCenter
              color: root.selectedText
              selectionColor: root.accent
              selectedTextColor: root.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              clip: true
              activeFocusOnPress: true

              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelInput()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitInput()
                  event.accepted = true
                }
              }
            }
          }
        }

        // ------------------------------------------------------- footer
        Item {
          width: parent.width
          height: root.footerHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.mode === "input"
              ? "enter save   esc cancel"
              : "j/k move   h/l list   space toggle   a add   enter edit   d delete   u undo   / filter   esc close"
            color: root.foreground
            opacity: 0.45
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusText
            color: root.accent
            opacity: root.statusText ? 0.9 : 0
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            Behavior on opacity { NumberAnimation { duration: 120 } }
          }
        }
      }
    }
  }
}
