import QtQuick
import QtQuick.Effects
import qs.Commons
import "Format.js" as Format
import "Palette.js" as Palette

// What a folder looks like from the outside, without opening it.
//
// The order is deliberate: pictures first, because that is what identifies a
// folder at a glance; then what changed most recently, because that is what
// you came back for; then the numbers, which are the slowest to read and the
// least often the reason you hovered.
Item {
  id: card

  property var scan: null
  property string path: ""
  property string title: ""
  property string home: ""
  property int thumbnailCount: 4
  property int recentCount: 6
  property real backgroundOpacity: 0.86

  readonly property bool ready: card.scan && card.scan.ok
  readonly property bool failed: card.scan && !card.scan.ok && card.scan.error.length > 0
  readonly property var thumbs: (card.scan && card.scan.thumbs) ? card.scan.thumbs.slice(0, card.thumbnailCount) : []
  readonly property var recents: (card.scan && card.scan.recent) ? card.scan.recent.slice(0, card.recentCount) : []

  readonly property int totalCategoryCount: {
    if (!card.scan) return 0
    var n = 0
    for (var i = 0; i < card.scan.categories.length; i++) n += card.scan.categories[i].count
    return n
  }

  implicitWidth: Style.space(340)
  implicitHeight: body.implicitHeight + Style.space(28)

  GlassPanel {
    anchors.fill: parent
    radius: Style.space(14)
    backgroundOpacity: card.backgroundOpacity
    tint: Color.tooltip.background
    elevated: true
    showSpine: false
    accentBloom: 0.07
  }

  Column {
    id: body
    anchors.fill: parent
    anchors.margins: Style.space(14)
    spacing: Style.space(10)

    // ------------------------------------------------------------- heading
    Column {
      width: parent.width
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: card.title
        color: Color.tooltip.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideMiddle
      }

      Text {
        width: parent.width
        text: Format.prettyPath(card.path, card.home, 52)
        color: Qt.rgba(Color.tooltip.text.r, Color.tooltip.text.g, Color.tooltip.text.b, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }
    }

    // ------------------------------------------------------------- failure
    Text {
      visible: card.failed
      width: parent.width
      wrapMode: Text.WordWrap
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      text: {
        if (!card.scan) return ""
        if (card.scan.error === "missing") return "This folder is not there any more."
        if (card.scan.error === "unreadable") return "No permission to read this folder."
        return "Could not read this folder."
      }
    }

    // ---------------------------------------------------------- thumbnails
    Row {
      visible: card.thumbs.length > 0
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: card.thumbs

        Item {
          required property string modelData
          required property int index
          readonly property real cell: (body.width - Style.space(6) * (card.thumbs.length - 1)) / Math.max(1, card.thumbs.length)
          width: cell
          height: cell * 0.72

          Rectangle {
            anchors.fill: parent
            radius: Style.space(6)
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)
            clip: true

            Image {
              anchors.fill: parent
              anchors.margins: 1
              source: Util.fileUrl(modelData)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              sourceSize.width: Math.round(parent.width * 2)
              sourceSize.height: Math.round(parent.height * 2)
              smooth: true
              opacity: status === Image.Ready ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: 200 } }
            }
          }
        }
      }
    }

    // -------------------------------------------------------- recent files
    Column {
      visible: card.recents.length > 0
      width: parent.width
      spacing: Style.space(3)

      Repeater {
        model: card.recents

        Item {
          required property var modelData
          width: body.width
          height: Style.space(15)

          Text {
            id: entryName
            anchors.left: parent.left
            anchors.right: entryMeta.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: (modelData.isDir ? "▸ " : "") + modelData.name
            color: modelData.isDir
              ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.9)
              : Qt.rgba(Color.tooltip.text.r, Color.tooltip.text.g, Color.tooltip.text.b, 0.82)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }

          Text {
            id: entryMeta
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.isDir ? Format.since(modelData.mtime)
                                  : Format.bytes(modelData.size) + " · " + Format.since(modelData.mtime)
            color: Qt.rgba(Color.tooltip.text.r, Color.tooltip.text.g, Color.tooltip.text.b, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    // ------------------------------------------------------- composition
    Column {
      visible: card.ready && card.totalCategoryCount > 0
      width: parent.width
      spacing: Style.space(6)

      Row {
        width: parent.width
        height: Style.space(6)
        spacing: 1

        Repeater {
          model: card.scan ? card.scan.categories : []

          Rectangle {
            required property var modelData
            required property int index
            height: parent.height
            width: Math.max(2, (body.width - card.scan.categories.length)
                               * (modelData.count / Math.max(1, card.totalCategoryCount)))
            radius: height / 2
            color: {
              for (var i = 0; i < Format.CATEGORIES.length; i++)
                if (Format.CATEGORIES[i].key === modelData.key)
                  return Palette.categoryColor(Color.accent, Format.CATEGORIES[i].hue, 0.85)
              return Qt.rgba(Color.tooltip.text.r, Color.tooltip.text.g, Color.tooltip.text.b, 0.3)
            }
          }
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(10)

        Repeater {
          model: card.scan ? card.scan.categories : []

          Row {
            required property var modelData
            spacing: Style.space(4)

            Rectangle {
              width: Style.space(6)
              height: Style.space(6)
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: {
                for (var i = 0; i < Format.CATEGORIES.length; i++)
                  if (Format.CATEGORIES[i].key === modelData.key)
                    return Palette.categoryColor(Color.accent, Format.CATEGORIES[i].hue, 0.9)
                return Qt.rgba(Color.tooltip.text.r, Color.tooltip.text.g, Color.tooltip.text.b, 0.3)
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: Format.categoryLabel(modelData.key) + " " + Format.count(modelData.count)
              color: Qt.rgba(Color.tooltip.text.r, Color.tooltip.text.g, Color.tooltip.text.b, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }

    // -------------------------------------------------------------- facts
    Grid {
      visible: card.ready
      width: parent.width
      columns: 2
      columnSpacing: Style.space(12)
      rowSpacing: Style.space(4)

      Fact {
        label: "Here"
        value: card.scan ? (Format.plural(card.scan.topFiles, "file") + ", " + Format.plural(card.scan.topDirs, "folder")) : ""
      }

      Fact {
        label: "Size"
        value: card.scan ? (Format.bytes(card.scan.bytes) + (card.scan.partial ? "+" : "")) : ""
        dimmed: card.scan ? card.scan.partial : false
      }

      Fact {
        label: "In all"
        value: card.scan ? Format.plural(card.scan.files, "file") : ""
      }

      Fact {
        label: "Changed"
        value: card.scan ? Format.since(card.scan.mtime) : ""
      }

      Fact {
        label: "Owner"
        value: card.scan ? (card.scan.owner + ":" + card.scan.group) : ""
      }

      Fact {
        label: "Access"
        value: card.scan ? (card.scan.mode.slice(1) + " " + Format.permissionOctal(card.scan.mode)) : ""
      }
    }

    Text {
      visible: card.ready && card.scan && card.scan.partial
      width: parent.width
      wrapMode: Text.WordWrap
      text: "Still counting — the walk hit its time limit, so the totals are a floor."
      color: Qt.rgba(Color.tooltip.text.r, Color.tooltip.text.g, Color.tooltip.text.b, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.italic: true
    }

    Text {
      visible: !card.scan
      width: parent.width
      text: "Reading…"
      color: Qt.rgba(Color.tooltip.text.r, Color.tooltip.text.g, Color.tooltip.text.b, 0.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
