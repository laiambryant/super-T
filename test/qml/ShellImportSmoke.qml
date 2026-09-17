import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
ShellRoot {
  id: root

  readonly property var smokeBorder: Border.flat("#112233", 1)
  readonly property int smokeSpace: Style.space(1)

  BorderSurface {
    id: surface
    width: 1
    height: 1
    borderSpec: root.smokeBorder
  }
}
