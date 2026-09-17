import QtQuick

Rectangle {
  id: root

  required property string text
  required property color foreground
  required property color accent
  required property string fontFamily
  property string shortcut: ""
  property int fontSize: 12
  property real cornerRadius: 6
  property bool highlighted: false
  property string accessibleName: text
  signal clicked()

  implicitWidth: content.implicitWidth + 24
  implicitHeight: fontSize + 22
  radius: cornerRadius
  color: Qt.alpha(highlighted ? accent : foreground, pointer.pressed ? 0.16 : pointer.containsMouse || highlighted ? 0.09 : 0)
  opacity: enabled ? 1 : 0.35
  Accessible.role: Accessible.Button
  Accessible.name: accessibleName
  Accessible.onPressAction: if (enabled) clicked()

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 12

    Text {
      text: root.text
      textFormat: Text.PlainText
      color: root.highlighted ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }

    Text {
      visible: root.shortcut !== ""
      text: root.shortcut
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.45
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
