import QtQuick
import qs.Commons
import "Format.js" as Format

// One folder on the shelf, in grid layout.
//
// The gestures are the ones a folder already has everywhere else on the
// desktop: double click opens it, middle click drops a terminal into it,
// right click asks what else. A press that turns into a movement is a
// reorder, which is why plain single click is deliberately left doing
// nothing — it is the first half of both a double click and a drag.
Item {
  id: tile

  property var folder: null
  property var scan: null
  property string home: ""
  property real tileSize: Style.space(64)
  property bool showLabel: true
  property bool listMode: false
  property bool dragging: false
  property bool dropTarget: false
  property bool interactive: true

  signal activated()
  signal terminalRequested()
  signal menuRequested(real sceneX, real sceneY)
  signal hoverStarted()
  signal hoverEnded()
  signal dragStarted(real sceneX, real sceneY)
  signal dragMoved(real sceneX, real sceneY)
  signal dragFinished()

  readonly property bool hovered: mouse.containsMouse
  readonly property bool missing: tile.scan && !tile.scan.ok && tile.scan.error === "missing"
  readonly property string label: tile.folder
    ? (tile.folder.label && tile.folder.label.length > 0
       ? tile.folder.label
       : Format.baseName(tile.folder.path) || "/")
    : ""

  readonly property string firstThumb: (tile.scan && tile.scan.thumbs.length > 0) ? tile.scan.thumbs[0] : ""

  readonly property string itemsLine: tile.scan
    ? Format.count(tile.scan.topFiles + tile.scan.topDirs) + " items"
    : ""

  readonly property color labelColor: tile.missing
    ? Color.urgent
    : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, tile.hovered ? 1.0 : 0.82)

  readonly property string dominant: {
    if (!tile.scan || !tile.scan.categories || tile.scan.categories.length === 0) return ""
    // "other" wins by count in most folders and says nothing; the first
    // category that means something is the one worth colouring the folder by.
    for (var i = 0; i < tile.scan.categories.length; i++)
      if (tile.scan.categories[i].key !== "other") return tile.scan.categories[i].key
    return "other"
  }

  opacity: tile.dragging ? 0.85 : 1.0
  scale: tile.dragging ? 1.06 : (mouse.pressed ? 0.98 : 1.0)
  Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

  // ------------------------------------------------------------ grid face
  Column {
    visible: !tile.listMode
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    spacing: Style.space(5)

    FolderIcon {
      anchors.horizontalCenter: parent.horizontalCenter
      size: tile.tileSize
      thumbnail: tile.firstThumb
      dominant: tile.dominant
      hovered: tile.hovered || tile.dragging
      missing: tile.missing
    }

    Text {
      visible: tile.showLabel
      width: tile.width
      horizontalAlignment: Text.AlignHCenter
      text: tile.label
      color: tile.labelColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
      maximumLineCount: 1
    }

    Text {
      visible: tile.showLabel && tile.scan && tile.scan.ok
      width: tile.width
      horizontalAlignment: Text.AlignHCenter
      text: tile.itemsLine
      color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  // ------------------------------------------------------------ list face
  //
  // The list is not a second design, it is the same folder with its numbers
  // moved from behind the hover to onto the row — which is the whole reason
  // somebody switches to it.
  Item {
    visible: tile.listMode
    anchors.fill: parent

    Rectangle {
      anchors.fill: parent
      radius: Style.space(9)
      color: tile.hovered
        ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.07)
        : "transparent"
      Behavior on color { ColorAnimation { duration: 120 } }
    }

    FolderIcon {
      id: rowIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      size: Math.min(tile.tileSize, parent.height - Style.space(8))
      thumbnail: tile.firstThumb
      dominant: tile.dominant
      hovered: tile.hovered || tile.dragging
      missing: tile.missing
    }

    Text {
      id: rowName
      anchors.left: rowIcon.right
      anchors.leftMargin: Style.space(10)
      anchors.right: rowStats.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: tile.label
      color: tile.labelColor
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideMiddle
    }

    Text {
      id: rowStats
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: {
        if (!tile.scan) return ""
        if (!tile.scan.ok) return tile.scan.error === "missing" ? "gone" : "no access"
        return tile.itemsLine + " · " + Format.bytes(tile.scan.bytes) + (tile.scan.partial ? "+" : "")
      }
      color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, tile.missing ? 0.7 : 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  // The slot a dragged tile would land in, drawn under it.
  Rectangle {
    anchors.fill: parent
    anchors.margins: -Style.space(3)
    visible: tile.dropTarget
    radius: Style.space(10)
    color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.10)
    border.width: 1
    border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.45)
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: tile.interactive
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: tile.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

    property real pressX: 0
    property real pressY: 0
    property bool armed: false

    onEntered: tile.hoverStarted()
    onExited: tile.hoverEnded()

    onPressed: function (event) {
      if (event.button !== Qt.LeftButton) return
      mouse.pressX = event.x
      mouse.pressY = event.y
      mouse.armed = true
    }

    onPositionChanged: function (event) {
      if (!mouse.armed || !mouse.pressed) return
      var moved = Math.abs(event.x - mouse.pressX) + Math.abs(event.y - mouse.pressY)
      var scene = mouse.mapToItem(null, event.x, event.y)
      if (!tile.dragging) {
        // A few pixels of slack, or a double click with an unsteady hand
        // turns into a reorder nobody asked for.
        if (moved < Style.space(8)) return
        tile.dragStarted(scene.x, scene.y)
      }
      tile.dragMoved(scene.x, scene.y)
    }

    onReleased: function (event) {
      mouse.armed = false
      if (tile.dragging) tile.dragFinished()
    }

    onCanceled: {
      mouse.armed = false
      if (tile.dragging) tile.dragFinished()
    }

    onDoubleClicked: function (event) {
      if (event.button === Qt.LeftButton) tile.activated()
    }

    onClicked: function (event) {
      if (event.button === Qt.MiddleButton) {
        tile.terminalRequested()
      } else if (event.button === Qt.RightButton) {
        var scene = mouse.mapToItem(null, event.x, event.y)
        tile.menuRequested(scene.x, scene.y)
      }
    }
  }
}
