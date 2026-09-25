import QtQuick
import qs.Commons

// One line of a menu. Kept separate so every menu row in the shelf has the
// same hit area, the same hover wash and the same place for its shortcut hint.
Rectangle {
  id: row

  property string label: ""
  property string hint: ""
  property bool danger: false
  signal triggered()

  implicitHeight: visible ? Style.spacing.popupRowHeight : 0
  radius: Style.space(7)
  color: mouse.containsMouse
    ? (row.danger
       ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.18)
       : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16))
    : "transparent"

  Text {
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.leftMargin: Style.space(9)
    anchors.verticalCenter: parent.verticalCenter
    text: row.label
    color: row.danger ? Color.urgent : Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    textFormat: Text.PlainText
    anchors.right: parent.right
    anchors.rightMargin: Style.space(9)
    anchors.verticalCenter: parent.verticalCenter
    text: row.hint
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.35)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.triggered()
  }
}
