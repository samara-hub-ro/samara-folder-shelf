import QtQuick
import qs.Commons
import "Format.js" as Format

// Right-click on a folder. Rename happens in place rather than in a second
// dialog, because renaming is the only entry here that needs an answer and
// making the user chase a new window for one text field is worse than making
// the menu a little taller.
Item {
  id: menu

  property var folder: null
  property string home: ""

  signal openRequested()
  signal terminalRequested()
  signal copyRequested()
  signal renamed(string label)
  signal removeRequested()
  signal dismissed()

  property bool renaming: false

  function beginRename() {
    menu.renaming = true
    renameField.text = menu.folder ? (menu.folder.label || Format.baseName(menu.folder.path)) : ""
    Qt.callLater(function () { renameField.selectAll(); renameField.forceActiveFocus() })
  }

  implicitWidth: Style.space(230)
  implicitHeight: column.implicitHeight + Style.space(16)

  // As in the picker: the surface underneath dismisses, so the menu has to
  // keep the clicks that land between its rows.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    onClicked: function (event) { event.accepted = true }
  }

  GlassPanel {
    anchors.fill: parent
    radius: Style.space(12)
    backgroundOpacity: 0.95
    tint: Color.menu.background
    elevated: true
    showSpine: false
    accentBloom: 0.06
  }

  Column {
    id: column
    anchors.fill: parent
    anchors.margins: Style.space(8)
    spacing: Style.space(1)

    Text {
      width: parent.width
      leftPadding: Style.space(8)
      bottomPadding: Style.space(4)
      text: menu.folder ? Format.prettyPath(menu.folder.path, menu.home, 30) : ""
      color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
    }

    Rectangle {
      visible: menu.renaming
      width: parent.width
      height: Style.spacing.controlHeight
      radius: Style.space(7)
      color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.08)
      border.width: 1
      border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.6)

      TextInput {
        id: renameField
        anchors.fill: parent
        anchors.leftMargin: Style.space(9)
        anchors.rightMargin: Style.space(9)
        verticalAlignment: TextInput.AlignVCenter
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        selectByMouse: true
        selectionColor: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.4)
        clip: true
        onAccepted: menu.renamed(String(text || "").trim())
        Keys.onEscapePressed: menu.renaming = false
      }
    }

    MenuRow {
      width: parent.width
      label: "Open"
      hint: "double click"
      visible: !menu.renaming
      onTriggered: menu.openRequested()
    }

    MenuRow {
      width: parent.width
      label: "Open in terminal"
      hint: "middle click"
      visible: !menu.renaming
      onTriggered: menu.terminalRequested()
    }

    MenuRow {
      width: parent.width
      label: "Copy path"
      visible: !menu.renaming
      onTriggered: menu.copyRequested()
    }

    MenuRow {
      width: parent.width
      label: menu.folder && menu.folder.label ? "Rename…" : "Give it a name…"
      visible: !menu.renaming
      onTriggered: menu.beginRename()
    }

    MenuRow {
      width: parent.width
      label: "Use the folder's own name"
      visible: !menu.renaming && menu.folder && menu.folder.label.length > 0
      onTriggered: menu.renamed("")
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10)
    }

    MenuRow {
      width: parent.width
      label: "Take off the shelf"
      danger: true
      onTriggered: menu.removeRequested()
    }
  }
}
