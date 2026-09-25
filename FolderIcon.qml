import QtQuick
import QtQuick.Effects
import qs.Commons
import "Format.js" as Format
import "Palette.js" as Palette

// A folder drawn rather than themed from an icon set, for two reasons: an
// icon theme is one more thing that can be missing on someone else's machine,
// and a drawn folder can take the theme accent and the folder's own contents
// into itself. The sliver of a photograph showing above the flap is the whole
// idea of the shelf in miniature — you can see what is in there without
// opening it.
Item {
  id: icon

  property real size: Style.space(64)
  property string thumbnail: ""
  property string dominant: ""
  property color accent: Color.accent
  property bool hovered: false
  property bool missing: false

  implicitWidth: size
  implicitHeight: size * 0.82

  readonly property color tone: {
    if (icon.missing) return Color.urgent
    if (!icon.dominant) return icon.accent
    for (var i = 0; i < Format.CATEGORIES.length; i++)
      if (Format.CATEGORIES[i].key === icon.dominant)
        return Palette.categoryColor(icon.accent, Format.CATEGORIES[i].hue, 1.0)
    return icon.accent
  }

  readonly property real radius: Math.max(2, icon.size * 0.10)

  // Back panel, and the tab that makes it read as a folder at 24px as well as
  // at 96px.
  Rectangle {
    id: back
    anchors.fill: parent
    radius: icon.radius
    color: Palette.withAlpha(icon.tone, icon.hovered ? 0.34 : 0.24)
    border.width: 1
    border.color: Palette.withAlpha(icon.tone, icon.hovered ? 0.65 : 0.42)

    Rectangle {
      width: parent.width * 0.42
      height: icon.radius * 1.6
      radius: height / 2
      color: parent.color
      anchors.left: parent.left
      anchors.leftMargin: icon.radius
      anchors.bottom: parent.top
      anchors.bottomMargin: -height * 0.55
    }
  }

  // The contents, peeking. Clipped to a slab that sits between the back panel
  // and the front flap, and nudged off-square so it reads as a loose sheet
  // rather than as a tile with a picture in it.
  Item {
    id: peek
    visible: icon.thumbnail.length > 0 && !icon.missing
    width: parent.width * 0.74
    height: parent.height * 0.62
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: icon.size * 0.03
    y: parent.height * 0.10
    rotation: -3

    Rectangle {
      anchors.fill: parent
      radius: Math.max(1, icon.radius * 0.5)
      color: Qt.rgba(1, 1, 1, 0.10)
      clip: true

      Image {
        id: peekImage
        anchors.fill: parent
        source: icon.thumbnail.length > 0 ? Util.fileUrl(icon.thumbnail) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        // Decode at tile size. A 40-megapixel photograph decoded at full size
        // for a 60px sliver is how a widget like this eats a gigabyte.
        sourceSize.width: Math.round(icon.size * 1.5)
        sourceSize.height: Math.round(icon.size * 1.5)
        smooth: true
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
      }

      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.16)
    }
  }

  // Front flap, over the sheet.
  Rectangle {
    id: flap
    width: parent.width
    height: parent.height * 0.66
    anchors.bottom: parent.bottom
    radius: icon.radius
    color: Palette.withAlpha(icon.tone, icon.hovered ? 0.62 : 0.48)
    border.width: 1
    border.color: Palette.withAlpha(icon.tone, 0.75)

    // Same lit-from-above shading as the shelf itself, so the folders look
    // like they are made of the surface they are sitting on.
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.20) }
        GradientStop { position: 0.6; color: Qt.rgba(1, 1, 1, 0.02) }
        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.10) }
      }
    }
  }

  // A folder that has gone away still holds its place on the shelf — you put
  // it there, and an unplugged drive is not a reason to silently drop it.
  Text {
    textFormat: Text.PlainText
    visible: icon.missing
    anchors.centerIn: flap
    text: "?"
    color: Color.urgent
    font.family: Style.font.family
    font.pixelSize: Math.max(10, Math.round(icon.size * 0.34))
    font.bold: true
  }

  Behavior on implicitWidth { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
}
