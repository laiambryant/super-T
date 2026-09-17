pragma ComponentBehavior: Bound
import QtQuick

Item {
  id: root

  required property var controller
  required property string directory
  required property string configurationError
  required property color background
  required property color foreground
  required property color accent
  required property string fontFamily
  property int fontSize: 13
  property real cornerRadius: 8
  property real uiScale: 1
  readonly property real padding: 24 * uiScale
  readonly property real rowHeight: Math.max(42 * uiScale, fontSize + 24)
  readonly property color lineColor: Qt.alpha(foreground, 0.09)
  readonly property color selectionColor: Qt.alpha(accent, 0.10)
  readonly property bool browsing: controller.mode === "normal" || controller.mode === "filter"
  readonly property int completed: controller.allTasks.filter(function(task) { return task.checked }).length
  readonly property int total: controller.allTasks.length
  readonly property bool hasLists: controller.lists.length > 0

  function focusKeyboard() {
    Qt.callLater(function() { keyboard.forceActiveFocus() })
  }

  function footerHint() {
    if (controller.mode === "input") return controller.multilineInput ? "Ctrl + Enter to save  ·  Esc to cancel" : "Enter to save  ·  Esc to cancel"
    if (controller.mode === "move") return "↑ ↓ to choose  ·  Enter to move  ·  Esc to cancel"
    if (controller.mode === "summary") return "s or Esc to return"
    if (controller.mode === "help") return "↑ ↓ to scroll  ·  Esc to return"
    if (controller.mode === "filter") return "Type to filter  ·  Enter to keep  ·  Esc to clear"
    if (controller.selecting) return controller.selectedIndices.length + " selected  ·  Space to complete  ·  v to clear"
    if (!hasLists) return "Shift + N to create a list"
    return "Space to complete  ·  Enter to edit"
  }

  component Action: TodoButton {
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    fontSize: root.fontSize - 1
    cornerRadius: root.cornerRadius
  }

  MouseArea { anchors.fill: parent }

  Item {
    id: keyboard
    anchors.fill: parent
    focus: root.visible && root.controller.mode !== "input"
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (root.controller.mode !== "input") root.controller.dispatchKey(event)
    }
    Keys.onTabPressed: function(event) {
      if (root.controller.mode !== "input") root.controller.dispatchKey(event)
    }
    Keys.onBacktabPressed: function(event) {
      if (root.controller.mode !== "input") root.controller.dispatchKey(event)
    }
  }

  Item {
    id: header
    width: parent.width
    height: 68 * root.uiScale

    Row {
      anchors.left: parent.left
      anchors.leftMargin: root.padding
      anchors.verticalCenter: parent.verticalCenter
      spacing: 10 * root.uiScale

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 8 * root.uiScale
        height: width
        radius: width / 2
        color: root.accent
      }

      Text {
        text: "Super T"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.fontSize + 2
        font.weight: Font.DemiBold
      }
    }

    Row {
      anchors.right: parent.right
      anchors.rightMargin: root.padding / 2
      anchors.verticalCenter: parent.verticalCenter
      spacing: 4 * root.uiScale

      Action {
        text: "Progress"
        shortcut: "s"
        visible: root.width > 560 * root.uiScale
        enabled: root.browsing || root.controller.mode === "summary"
        highlighted: root.controller.mode === "summary"
        onClicked: root.controller.toggleSummary()
      }

      Action {
        text: "Close"
        shortcut: "esc"
        onClicked: root.controller.dismiss()
      }
    }

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineColor }
  }

  Item {
    id: body
    anchors.top: header.bottom
    anchors.bottom: inputBar.visible ? inputBar.top : footer.top
    width: parent.width

    Item {
      anchors.fill: parent
      visible: root.hasLists
      enabled: root.browsing
      opacity: root.browsing || root.controller.mode === "input" ? 1 : 0.25

      Rectangle {
        id: sidebar
        width: Math.min(220 * root.uiScale, parent.width * 0.28)
        height: parent.height
        color: Qt.alpha(root.foreground, 0.025)

        Text {
          id: listsLabel
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.margins: root.padding
          text: "LISTS"
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: root.fontSize - 3
          font.letterSpacing: 1.5
        }

        TodoSidebar {
          anchors.top: listsLabel.bottom
          anchors.topMargin: 16 * root.uiScale
          anchors.bottom: newList.top
          anchors.bottomMargin: root.padding / 2
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: root.padding / 2
          anchors.rightMargin: root.padding / 2
          controller: root.controller
          foreground: root.foreground
          selectedBackground: root.selectionColor
          selectedText: root.accent
          rowHeight: root.rowHeight
          cornerRadius: root.cornerRadius
          fontFamily: root.fontFamily
          fontSize: root.fontSize
          interactive: root.browsing
        }

        Action {
          id: newList
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.margins: root.padding / 2
          text: "+ New list"
          shortcut: "N"
          onClicked: root.controller.beginInput("list")
        }

        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: root.lineColor }
      }

      Item {
        id: workspace
        anchors.left: sidebar.right
        anchors.right: parent.right
        height: parent.height
        anchors.margins: root.padding

        Text {
          id: listTitle
          anchors.top: parent.top
          anchors.topMargin: root.padding
          width: parent.width
          text: root.controller.currentList ? String(root.controller.currentList.name) : "Your tasks"
          textFormat: Text.PlainText
          elide: Text.ElideMiddle
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: root.fontSize + 13
          font.weight: Font.Medium
        }

        Text {
          id: listDetails
          anchors.top: listTitle.bottom
          anchors.topMargin: 10 * root.uiScale
          width: parent.width
          text: root.controller.documentError ? "Could not read this list"
            : (root.total - root.completed) + " remaining  ·  " + root.completed + " complete"
              + (root.controller.documentTags.length ? "  /  " + root.controller.documentTags.join(" · ") : "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.foreground
          opacity: 0.48
          font.family: root.fontFamily
          font.pixelSize: root.fontSize - 1
        }

        Rectangle {
          id: progress
          anchors.top: listDetails.bottom
          anchors.topMargin: 20 * root.uiScale
          width: parent.width
          height: 2 * root.uiScale
          color: root.lineColor

          Rectangle {
            width: root.total ? parent.width * root.completed / root.total : 0
            height: parent.height
            color: root.accent
            opacity: 0.7
          }
        }

        Item {
          id: filter
          anchors.top: progress.bottom
          anchors.topMargin: 12 * root.uiScale
          width: parent.width
          height: visible ? root.rowHeight : 0
          visible: root.controller.mode === "filter" || root.controller.filterText !== ""

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - clearFilter.width
            text: "/  " + (root.controller.filterText || "Type to filter…")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
          }

          Action {
            id: clearFilter
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Clear"
            onClicked: root.controller.clearFilter()
          }
        }

        TodoTaskList {
          anchors.top: filter.bottom
          anchors.bottom: addTask.top
          width: parent.width
          controller: root.controller
          foreground: root.foreground
          selectedBackground: root.selectionColor
          selectedText: root.foreground
          accent: root.accent
          rowHeight: root.rowHeight
          cornerRadius: root.cornerRadius
          fontFamily: root.fontFamily
          fontSize: root.fontSize + 1
          interactive: root.browsing
        }

        Text {
          anchors.top: filter.bottom
          anchors.bottom: addTask.top
          width: parent.width
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: Text.AlignHCenter
          visible: root.controller.tasks.length === 0
          text: root.controller.documentError || (root.controller.filterText
            ? "No matching tasks.\nTry a different search."
            : "A little space to think.\nAdd your first task below.")
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          lineHeight: 1.5
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
        }

        Action {
          id: addTask
          objectName: "addTaskButton"
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 12 * root.uiScale
          text: "+ New task"
          shortcut: "n"
          enabled: root.controller.dataReady && !root.controller.mutationBusy
          onClicked: root.controller.beginInput("add")
        }
      }
    }

    Column {
      anchors.centerIn: parent
      width: Math.max(0, Math.min(parent.width - root.padding * 2, 440 * root.uiScale))
      spacing: 20 * root.uiScale
      visible: !root.hasLists

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.configurationError ? "Let’s check your settings"
          : root.controller.scanOk ? "Make room for what matters." : "Your lists couldn’t be loaded"
        wrapMode: Text.WordWrap
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.fontSize + 10
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.configurationError || (root.controller.scanOk
          ? "Start with a list. Everything stays in your Markdown files."
          : "Check that your Markdown directory is available.\n" + root.directory)
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        lineHeight: 1.5
        color: root.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
      }

      Action {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !root.configurationError
        enabled: root.browsing
        text: "+ Create a list"
        shortcut: "N"
        highlighted: true
        onClicked: root.controller.beginInput("list")
      }
    }

    TodoMovePicker {
      anchors.centerIn: parent
      width: Math.max(0, Math.min(implicitWidth, parent.width - root.padding * 2))
      height: Math.max(0, Math.min(implicitHeight, parent.height - root.padding))
      controller: root.controller
      background: root.background
      foreground: root.foreground
      border: root.lineColor
      selectedBackground: root.selectionColor
      selectedText: root.accent
      accent: root.accent
      cornerRadius: root.cornerRadius
      fontFamily: root.fontFamily
      rowHeight: root.rowHeight
      fontSize: root.fontSize
    }

    TodoSummary {
      anchors.centerIn: parent
      width: Math.max(0, Math.min(implicitWidth, parent.width - root.padding * 2))
      height: Math.max(0, Math.min(implicitHeight, parent.height - root.padding))
      controller: root.controller
      background: root.background
      foreground: root.foreground
      borderColor: root.lineColor
      accent: root.accent
      cornerRadius: root.cornerRadius
      fontFamily: root.fontFamily
      fontSize: root.fontSize
    }

    TodoHelp {
      anchors.fill: parent
      anchors.margins: root.padding / 2
      controller: root.controller
      background: root.background
      foreground: root.foreground
      accent: root.accent
      borderColor: "transparent"
      fontFamily: root.fontFamily
      fontSize: root.fontSize
    }
  }

  TodoInputBar {
    id: inputBar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: footer.top
    anchors.margins: root.padding / 2
    height: visible ? implicitHeight : 0
    controller: root.controller
    background: root.background
    foreground: root.foreground
    selectedBackground: root.selectionColor
    selectedText: root.foreground
    accent: root.accent
    cornerRadius: root.cornerRadius
    fontFamily: root.fontFamily
    rowHeight: root.rowHeight
    fontSize: root.fontSize
  }

  Item {
    id: footer
    anchors.bottom: parent.bottom
    width: parent.width
    height: 52 * root.uiScale

    Rectangle { width: parent.width; height: 1; color: root.lineColor }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: root.padding
      anchors.right: footerActions.left
      anchors.rightMargin: root.padding / 2
      anchors.verticalCenter: parent.verticalCenter
      text: root.controller.statusText || root.footerHint()
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.controller.statusText ? root.accent : root.foreground
      opacity: root.controller.statusText ? 1 : 0.45
      font.family: root.fontFamily
      font.pixelSize: root.fontSize - 2
    }

    Row {
      id: footerActions
      anchors.right: parent.right
      anchors.rightMargin: root.padding / 2
      anchors.verticalCenter: parent.verticalCenter

      Action {
        objectName: "filterButton"
        text: "Filter"
        shortcut: "/"
        visible: root.width > 560 * root.uiScale && root.hasLists
        enabled: root.browsing
        onClicked: root.controller.beginFilter()
      }

      Action {
        objectName: "helpButton"
        text: "Commands"
        shortcut: "?"
        enabled: root.controller.mode !== "input"
        onClicked: root.controller.toggleHelp()
      }
    }
  }

  Connections {
    target: root.controller
    function onRequestKeyboardFocus() { root.focusKeyboard() }
  }
}
