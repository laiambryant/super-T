pragma ComponentBehavior: Bound
import QtQuick

Rectangle {
  id: root

  required property var controller
  required property color background
  required property color foreground
  required property color borderColor
  required property color accent
  required property real cornerRadius
  required property string fontFamily
  property int fontSize: 16

  visible: controller && controller.mode === "summary"
  implicitWidth: 500
  implicitHeight: 280
  color: background
  radius: cornerRadius
  border.color: borderColor
  border.width: 1
  clip: true

  Column {
    anchors.fill: parent
    anchors.margins: 28
    spacing: 18

    Text {
      text: "A little progress, every day."
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize + 5
    }

    Text {
      text: root.controller.summaryLoading ? "Loading…" : Number(root.controller.summary.percent || 0) + "%"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: root.fontSize + 30
      font.weight: Font.Light
    }

    Rectangle {
      width: parent.width
      height: 3
      color: Qt.alpha(root.foreground, 0.08)
      Rectangle {
        width: parent.width * Math.max(0, Math.min(100, Number(root.controller.summary.percent || 0))) / 100
        height: parent.height
        color: root.accent
      }
    }

    Row {
      id: stats
      width: parent.width
      spacing: 16
      Repeater {
        model: [
          { value: Number(root.controller.summary.done || 0) + " / " + Number(root.controller.summary.total || 0), label: "tasks complete" },
          { value: Number(root.controller.summary.closedToday || 0), label: "closed today" },
          { value: Number(root.controller.summary.streak || 0), label: "day streak" }
        ]
        delegate: Column {
          id: metric
          required property var modelData
          width: (stats.width - stats.spacing * 2) / 3
          spacing: 6
          Text {
            text: metric.modelData.value
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.fontSize + 3
          }
          Text {
            text: metric.modelData.label
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: root.fontSize - 2
          }
        }
      }
    }

    Text {
      width: parent.width
      text: "Today and streak count completions made in Super T."
      wrapMode: Text.WordWrap
      color: root.foreground
      opacity: 0.45
      font.family: root.fontFamily
      font.pixelSize: root.fontSize - 3
    }
  }
}
