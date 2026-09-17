pragma ComponentBehavior: Bound
import QtQuick

Item {
  id: root

  required property var controller
  required property color foreground
  required property color selectedBackground
  required property color selectedText
  required property int rowHeight
  required property real cornerRadius
  required property string fontFamily
  property int fontSize: 15
  property bool interactive: true
  property alias view: listView

  ListView {
    id: listView
    anchors.fill: parent
    clip: true
    model: root.controller ? root.controller.lists : []
    currentIndex: root.controller ? root.controller.listIndex : -1
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: true
    cacheBuffer: Math.max(root.rowHeight * 8, 160)

    delegate: Rectangle {
      id: listRow
      required property int index
      required property var modelData

      readonly property bool isCurrent: root.controller && index === root.controller.listIndex
      readonly property int openCount: Number(listRow.modelData.total || 0) - Number(listRow.modelData.done || 0)
      readonly property bool complete: Number(listRow.modelData.total || 0) > 0 && listRow.openCount === 0

      width: listView.width
      height: root.rowHeight
      radius: root.cornerRadius
      color: listRow.isCurrent ? root.selectedBackground : pointer.containsMouse ? Qt.alpha(root.foreground, 0.04) : "transparent"
      border.width: listRow.isCurrent && root.controller.activePane === "lists" ? 1 : 0
      border.color: Qt.alpha(root.selectedText, 0.35)

      Row {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8

        Text {
          width: parent.width - countLabel.width - parent.spacing
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          text: String(listRow.modelData.name || "")
          textFormat: Text.PlainText
          color: listRow.isCurrent ? root.selectedText : root.foreground
          opacity: listRow.complete ? 0.55 : 1
          elide: Text.ElideMiddle
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
        }

        Text {
          id: countLabel
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          text: listRow.openCount
          textFormat: Text.PlainText
          color: listRow.isCurrent ? root.selectedText : root.foreground
          opacity: listRow.openCount > 0 ? 0.72 : 0.35
          font.family: root.fontFamily
          font.pixelSize: Math.max(11, root.fontSize - 2)
        }
      }

      MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.controller.focusPane("lists")
          root.controller.selectList(listRow.index)
        }
      }
    }
  }

  Connections {
    target: root.controller
    function onRequestListReveal(index) {
      if (index >= 0 && index < listView.count)
        listView.positionViewAtIndex(index, ListView.Contain)
    }
  }
}
