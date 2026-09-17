import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  required property var controller
  required property string directory
  required property string configurationError

  PanelWindow {
    id: panel
    visible: root.controller.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-todo"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Color.menu.scrim }

    MouseArea {
      anchors.fill: parent
      onClicked: root.controller.dismiss()
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.max(0, Math.min(Style.space(960), panel.width - Style.space(32)))
      height: Math.max(0, Math.min(Style.space(620), panel.height - Style.space(32)))
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)

      TodoPanel {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        controller: root.controller
        directory: root.directory
        configurationError: root.configurationError
        background: Color.menu.background
        foreground: Color.menu.text
        accent: Color.accent
        cornerRadius: Style.cornerRadius
        fontFamily: Style.font.menuFamily
        fontSize: Style.font.subtitle
        uiScale: Style.space(100) / 100
      }
    }
  }
}
