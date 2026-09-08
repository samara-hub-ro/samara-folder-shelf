import QtQuick
import qs.Commons

// A round glass button for the shelf header. It carries a `tip` but does not
// draw one: a tooltip window over a desktop widget is a third surface to
// position and dismiss, and the header already has a line of text doing
// nothing that can say it instead.
Rectangle {
  id: button

  property string glyph: ""
  property string tip: ""
  property bool active: false
  readonly property bool hovered: mouse.containsMouse

  signal activated()

  implicitWidth: Style.spacing.controlHeight
  implicitHeight: Style.spacing.controlHeight
  radius: width / 2

  color: {
    var base = button.active ? Color.accent : Color.foreground
    var a = mouse.pressed ? 0.30 : (mouse.containsMouse ? 0.18 : (button.active ? 0.12 : 0.06))
    return Qt.rgba(base.r, base.g, base.b, a)
  }

  border.width: 1
  border.color: {
    var base = button.active ? Color.accent : Color.foreground
    return Qt.rgba(base.r, base.g, base.b, mouse.containsMouse ? 0.45 : (button.active ? 0.35 : 0.14))
  }

  Behavior on color { ColorAnimation { duration: 130 } }

  Text {
    anchors.centerIn: parent
    text: button.glyph
    color: button.active ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.85)
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: button.activated()
  }
}
