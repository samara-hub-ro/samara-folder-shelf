import QtQuick
import qs.Commons

// A small glass button. The shelf has one style of button and it is this one,
// so the picker, the header and the context menu do not each invent their own.
Rectangle {
  id: button

  property string text: ""
  property bool accented: false
  property bool enabled: true
  signal clicked()

  implicitWidth: label.implicitWidth + Style.space(20)
  implicitHeight: Style.spacing.controlHeight
  radius: Style.space(8)
  opacity: button.enabled ? 1.0 : 0.4

  color: {
    var base = button.accented ? Color.accent : Color.foreground
    var a = !button.enabled ? 0.05 : (mouse.pressed ? 0.30 : (mouse.containsMouse ? 0.20 : 0.09))
    return Qt.rgba(base.r, base.g, base.b, a)
  }

  border.width: 1
  border.color: {
    var base = button.accented ? Color.accent : Color.foreground
    return Qt.rgba(base.r, base.g, base.b, mouse.containsMouse ? 0.5 : 0.2)
  }

  Behavior on color { ColorAnimation { duration: 120 } }

  Text {
    id: label
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: button.text
    color: button.accented ? Color.accent : Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: button.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}
