pragma ComponentBehavior: Bound
import QtQuick

Item {
  id: root

  required property var controller
  required property color background
  required property color foreground
  required property color border
  required property color selectedBackground
  required property color selectedText
  required property color accent
  required property real cornerRadius
  required property string fontFamily
  required property int rowHeight
  property int fontSize: 15
  property alias view: targetView

  visible: root.controller && root.controller.mode === "move"
  implicitWidth: 360
  implicitHeight: Math.min(420, header.implicitHeight + targetView.contentHeight + footer.implicitHeight + 42)

  Rectangle {
    anchors.fill: parent
    radius: root.cornerRadius
    color: root.background
    border.color: root.border
    border.width: 1

    Column {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 10

      Text {
        id: header
        width: parent.width
        text: "Move " + (root.controller.moveTaskSnapshot ? root.controller.moveTaskSnapshot.lines.length : 1)
          + " selected task(s) and children to"
        wrapMode: Text.WordWrap
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.fontSize + 2
      }

      ListView {
        id: targetView
        width: parent.width
        height: Math.max(root.rowHeight, parent.height - header.implicitHeight - footer.implicitHeight - parent.spacing * 2)
        clip: true
        model: root.controller ? root.controller.moveTargets : []
        currentIndex: root.controller ? root.controller.moveTargetIndex : -1
        boundsBehavior: Flickable.StopAtBounds
        reuseItems: true
        cacheBuffer: Math.max(root.rowHeight * 6, 120)

        delegate: Rectangle {
          id: targetRow
          required property int index
          required property var modelData

          readonly property bool isCurrent: root.controller && index === root.controller.moveTargetIndex
          width: targetView.width
          height: root.rowHeight
          radius: root.cornerRadius
          color: targetRow.isCurrent ? root.selectedBackground : "transparent"

          Text {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            verticalAlignment: Text.AlignVCenter
            text: String(targetRow.modelData.name || "")
            textFormat: Text.PlainText
            color: targetRow.isCurrent ? root.selectedText : root.foreground
            elide: Text.ElideMiddle
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.controller.selectMoveTarget(targetRow.index)
            onDoubleClicked: root.controller.confirmMove()
          }
        }
      }

      Text {
        id: footer
        width: parent.width
        text: "j/k or ↑/↓ choose   enter move   esc cancel"
        color: root.foreground
        opacity: 0.56
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Math.max(11, root.fontSize - 3)
      }
    }
  }

  Connections {
    target: root.controller
    function onRequestMoveTargetReveal(index) {
      if (root.visible && index >= 0 && index < targetView.count)
        targetView.positionViewAtIndex(index, ListView.Contain)
    }
    function onRequestKeyboardFocus() {
      var index = root.controller.moveTargetIndex
      if (root.visible && index >= 0 && index < targetView.count)
        targetView.positionViewAtIndex(index, ListView.Contain)
    }
  }
}
