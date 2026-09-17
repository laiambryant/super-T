pragma ComponentBehavior: Bound
import QtQuick

Rectangle {
  id: root
  required property var controller
  required property color background
  required property color foreground
  required property color accent
  required property color borderColor
  required property string fontFamily
  property int fontSize: 15
  property alias view: commands
  color: background
  border.color: borderColor
  border.width: 1
  radius: 8
  visible: controller && controller.mode === "help"

  Column {
    anchors.fill: parent
    anchors.margins: 16
    spacing: 12
    Text {
      id: heading
      text: "Keyboard commands"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize + 3
    }
    ListView {
      id: commands
      width: parent.width
      height: Math.max(0, parent.height - heading.height - hint.height - parent.spacing * 2)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: [
        ["h / ←", "Focus lists"],
        ["l / →", "Focus tasks"],
        ["j / ↓ · k / ↑", "Next / previous row in the focused pane"],
        ["Shift+j / Shift+↓ · Shift+k / Shift+↑", "Move task or selection down / up among siblings, including children"],
        ["g / Home · G / End", "First / last row (GG also goes to the last row)"],
        ["Page Up / Page Down", "Move 10 rows in the focused pane"],
        ["Shift+Tab", "Previous list"],
        ["v", "Start / clear a task range; j/k extends it"],
        ["Space / x", "Complete / reopen task or selection"],
        ["Enter / e", "Edit task or selection; enter tasks from lists"],
        ["n · Shift+n", "Add task · create list"],
        ["Tab / >", "Indent task or selection, including children"],
        ["<", "Promote one level, including children; repeat to detach"],
        ["m", "Move task or selection with children to another list"],
        ["d", "Delete task or selection, including children"],
        ["u", "Undo the whole last change"],
        ["t", "Edit current list tags"],
        ["/", "Filter tasks by text"],
        ["s", "Open progress summary"],
        ["r", "Reload lists and tasks"],
        ["?", "Open / close this command list"],
        ["Escape", "Clear selection, then filter, then close Todo"],
        ["While filtering", "Type to search; Backspace erases; ↑/↓ chooses a task; Enter keeps filter; Escape clears"],
        ["While editing", "Enter saves; Escape cancels"],
        ["Editing a range", "One line per task; Enter adds a line; Ctrl+Enter saves; Escape cancels"],
        ["Move picker", "j/k or ↑/↓ chooses; Enter moves; Escape cancels"],
        ["Summary", "r refreshes; s or Escape closes; ? shows commands"],
        ["Selection", "Visible rows only. Mixed selection completes all; an entirely completed selection reopens all"],
        ["Mouse", "Click list to focus it; click task to toggle; in selection mode, click to extend the range"]
      ]
      delegate: Item {
        id: commandRow
        required property var modelData
        width: commands.width
        height: Math.max(keys.implicitHeight, description.implicitHeight) + 16
        Text {
          id: keys
          width: parent.width * 0.34
          text: commandRow.modelData[0]
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
        }
        Text {
          id: description
          anchors.left: keys.right
          anchors.leftMargin: 12
          anchors.right: parent.right
          text: commandRow.modelData[1]
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
        }
      }
    }
    Text {
      id: hint
      width: parent.width
      text: "j/k or ↑/↓ scroll · ? / esc return"
      wrapMode: Text.WordWrap
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: root.fontSize - 2
    }
  }
  Connections {
    target: root.controller
    function onHelpScroll(delta, edge) {
      var limit = Math.max(0, commands.contentHeight - commands.height)
      commands.contentY = edge ? (delta > 0 ? limit : 0)
        : Math.max(0, Math.min(limit, commands.contentY + delta * (root.fontSize + 24)))
    }
  }
}
