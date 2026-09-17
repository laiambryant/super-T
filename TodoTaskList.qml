pragma ComponentBehavior: Bound
import QtQuick

Item {
  id: root

  required property var controller
  required property color foreground
  required property color selectedBackground
  required property color selectedText
  required property color accent
  required property int rowHeight
  required property real cornerRadius
  required property string fontFamily
  property int fontSize: 16
  property bool interactive: true
  property alias view: taskView

  ListView {
    id: taskView
    anchors.fill: parent
    clip: true
    model: root.controller ? root.controller.tasks : []
    currentIndex: root.controller ? root.controller.selectedVisibleIndex : -1
    boundsBehavior: Flickable.StopAtBounds
    reuseItems: true
    cacheBuffer: Math.max(root.rowHeight * 8, 240)

    Rectangle {
      parent: root
      anchors.right: parent.right
      width: 2
      y: taskView.visibleArea.yPosition * taskView.height
      height: taskView.visibleArea.heightRatio * taskView.height
      visible: taskView.contentHeight > taskView.height
      color: Qt.alpha(root.foreground, taskView.moving ? 0.3 : 0.12)
      z: 1
    }

    delegate: Rectangle {
      id: taskRow
      required property int index
      required property var modelData

      readonly property bool isCurrent: root.controller
        && taskRow.modelData.sourceIndex === root.controller.taskIndex
      readonly property bool isSelected: root.controller && root.controller.selecting
        && root.controller.selectedIndices.indexOf(taskRow.modelData.sourceIndex) >= 0
      width: taskView.width
      height: root.rowHeight
      radius: root.cornerRadius
      color: taskRow.isCurrent || taskRow.isSelected ? root.selectedBackground : pointer.containsMouse ? Qt.alpha(root.foreground, 0.04) : "transparent"
      Accessible.role: Accessible.CheckBox
      Accessible.name: String(taskRow.modelData.text || "")
      Accessible.checked: Boolean(taskRow.modelData.checked)
      Accessible.onToggleAction: if (root.interactive && !root.controller.mutationBusy) root.controller.toggleTaskAt(taskRow.modelData.sourceIndex)

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: 16
        radius: 1
        visible: taskRow.isCurrent && root.controller.activePane === "tasks"
        color: root.accent
      }

      Row {
        anchors.fill: parent
        anchors.leftMargin: 12 + Number(taskRow.modelData.indent || 0) * 8
        anchors.rightMargin: 12
        spacing: 14

        Rectangle {
          id: checkbox
          anchors.verticalCenter: parent.verticalCenter
          width: root.fontSize + 2
          height: width
          radius: 4
          color: taskRow.modelData.checked ? Qt.alpha(root.accent, 0.14) : "transparent"
          border.width: 1
          border.color: taskRow.modelData.checked ? Qt.alpha(root.accent, 0.5) : Qt.alpha(root.foreground, 0.28)

          Canvas {
            id: checkmark
            anchors.fill: parent
            visible: Boolean(taskRow.modelData.checked)
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              ctx.strokeStyle = root.accent
              ctx.lineWidth = 1.5
              ctx.lineCap = "round"
              ctx.lineJoin = "round"
              ctx.beginPath()
              ctx.moveTo(width * 0.25, height * 0.50)
              ctx.lineTo(width * 0.43, height * 0.68)
              ctx.lineTo(width * 0.75, height * 0.32)
              ctx.stroke()
            }
            Connections {
              target: root
              function onAccentChanged() { checkmark.requestPaint() }
            }
          }
        }

        Text {
          width: Math.max(0, parent.width - checkbox.width - parent.spacing)
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          text: String(taskRow.modelData.text || "")
          textFormat: Text.PlainText
          color: taskRow.isCurrent || taskRow.isSelected ? root.selectedText : root.foreground
          opacity: taskRow.modelData.checked ? 0.5 : 1
          font.strikeout: Boolean(taskRow.modelData.checked)
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
        }
      }

      MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: root.interactive && !root.controller.mutationBusy
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(mouse) {
          if (root.controller.activePane === "tasks" && !root.controller.selecting)
            root.controller.setTaskIndex(taskRow.modelData.sourceIndex)
        }
        onClicked: root.controller.toggleTaskAt(taskRow.modelData.sourceIndex)
      }
    }
  }

  Connections {
    target: root.controller
    function onRequestTaskReveal(index) {
      if (index >= 0 && index < taskView.count)
        taskView.positionViewAtIndex(index, ListView.Contain)
    }
  }
}
