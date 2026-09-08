import QtQuick
import qs.Commons

// The bar mark: two folders standing on a shelf. Drawn rather than set as a
// glyph so it does not depend on which Nerd Font the user has, and so it
// stays legible at the 16-or-so pixels a bar actually gives it.
Item {
  id: mark

  property color color: Color.bar.text

  Rectangle {
    id: shelfLine
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: parent.height * 0.18
    width: parent.width * 0.86
    height: Math.max(1, parent.height * 0.10)
    radius: height / 2
    color: mark.color
  }

  // The taller folder, leaning upright.
  Rectangle {
    width: parent.width * 0.30
    height: parent.height * 0.46
    radius: Math.max(1, width * 0.22)
    color: "transparent"
    border.width: Math.max(1, parent.height * 0.09)
    border.color: mark.color
    anchors.left: shelfLine.left
    anchors.leftMargin: parent.width * 0.06
    anchors.bottom: shelfLine.top
  }

  // The shorter one beside it, filled, so the mark reads as two objects even
  // when the whole thing is 14 pixels across.
  Rectangle {
    width: parent.width * 0.30
    height: parent.height * 0.32
    radius: Math.max(1, width * 0.22)
    color: mark.color
    anchors.right: shelfLine.right
    anchors.rightMargin: parent.width * 0.08
    anchors.bottom: shelfLine.top
  }
}
