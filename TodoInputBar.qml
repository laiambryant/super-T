pragma ComponentBehavior: Bound
import QtQuick

Item {
  id: root

  required property var controller
  required property color background
  required property color foreground
  required property color selectedBackground
  required property color selectedText
  required property color accent
  required property real cornerRadius
  required property string fontFamily
  required property int rowHeight
  property int fontSize: 16
  property alias editor: editor

  visible: root.controller && root.controller.mode === "input"
  implicitHeight: fieldBackground.height + (errorLabel.visible ? errorLabel.implicitHeight + 6 : 0)
  height: implicitHeight

  function caption() {
    if (controller.inputPurpose === "list") return "New list"
    if (controller.inputPurpose === "tags") return "List tags"
    if (controller.inputPurpose === "edit") return controller.multilineInput ? "Edit " + controller.inputLines.length + " tasks" : "Edit task"
    return "New task"
  }

  function placeholder() {
    if (controller.inputPurpose === "list") return "e.g. Work or projects/website"
    if (controller.inputPurpose === "tags") return "tags separated by commas or spaces"
    return "What needs to get done?"
  }

  function focusInput() {
    Qt.callLater(function() {
      editor.forceActiveFocus()
      if (controller.inputPurpose === "edit") editor.selectAll()
    })
  }

  Rectangle {
    id: fieldBackground
    width: parent.width
    height: root.controller.multilineInput ? root.rowHeight * 4 : root.rowHeight
    radius: root.cornerRadius
    color: root.selectedBackground
    border.width: 1
    border.color: Qt.alpha(root.accent, 0.3)

    Row {
      anchors.fill: parent
      anchors.leftMargin: 12
      anchors.rightMargin: 12
      spacing: 14

      Text {
        id: label
        width: Math.min(92, implicitWidth)
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        text: root.caption()
        color: root.selectedText
        font.family: root.fontFamily
        font.pixelSize: Math.max(12, root.fontSize - 2)
      }

      Flickable {
        id: editorViewport
        width: Math.max(0, parent.width - label.width - parent.spacing)
        height: parent.height
        contentWidth: width
        contentHeight: Math.max(height, editor.contentHeight)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        TextEdit {
          id: editor
          width: editorViewport.width
          height: Math.max(editorViewport.height, contentHeight)
          verticalAlignment: root.controller.multilineInput ? TextEdit.AlignTop : TextEdit.AlignVCenter
          text: root.controller.inputText
          textFormat: TextEdit.PlainText
          wrapMode: TextEdit.Wrap
          color: root.selectedText
          selectionColor: root.selectedText
          selectedTextColor: root.background
          selectByMouse: true
          activeFocusOnPress: true
          font.family: root.fontFamily
          font.pixelSize: root.fontSize

          onTextChanged: {
            if (activeFocus && root.controller.inputText !== text) root.controller.inputText = text
          }
          onCursorRectangleChanged: {
            if (cursorRectangle.y < editorViewport.contentY)
              editorViewport.contentY = cursorRectangle.y
            else if (cursorRectangle.y + cursorRectangle.height > editorViewport.contentY + editorViewport.height)
              editorViewport.contentY = cursorRectangle.y + cursorRectangle.height - editorViewport.height
          }
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) { root.controller.dispatchInputKey(event) }

          Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: editor.text === ""
            text: root.placeholder()
            textFormat: Text.PlainText
            color: root.selectedText
            opacity: 0.45
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
          }
        }
      }
    }
  }

  Text {
    id: errorLabel
    anchors.top: fieldBackground.bottom
    anchors.topMargin: 6
    width: parent.width
    visible: root.controller && root.controller.inputError !== ""
    text: root.controller ? root.controller.inputError : ""
    textFormat: Text.PlainText
    color: root.accent
    wrapMode: Text.WordWrap
    font.family: root.fontFamily
    font.pixelSize: Math.max(11, root.fontSize - 3)
  }

  Connections {
    target: root.controller
    function onRequestInputFocus() { root.focusInput() }
  }
}
