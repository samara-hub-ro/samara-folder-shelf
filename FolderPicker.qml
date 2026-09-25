import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Format.js" as Format

// Choosing a folder, without a portal.
//
// There is no zenity, kdialog or yad on a stock Omarchy install and no
// guarantee of an xdg-desktop-portal file chooser either, so the shelf brings
// its own: a directory listing, a breadcrumb, and a path you can type. It only
// ever lists directories, because a folder is the only thing it can return.
Item {
  id: picker

  property string home: ""
  property string startPath: ""
  property var alreadyOnShelf: []
  property bool showHidden: false

  signal chosen(string path)
  signal cancelled()

  property string current: ""
  property var entries: []
  property bool loading: false

  function open(path) {
    picker.current = String(path || picker.startPath || picker.home || "/")
    picker.reload()
    Qt.callLater(function () { pathField.text = picker.current; listView.forceActiveFocus() })
  }

  function reload() {
    picker.loading = true
    lister.command = ["bash", "-c",
                      'cd -- "$1" 2>/dev/null || exit 0; ' +
                      'find . -mindepth 1 -maxdepth 1 -type d -printf "%f\\n" 2>/dev/null | LC_ALL=C sort -f',
                      "bash", picker.current]
    lister.running = true
  }

  function navigate(path) {
    picker.current = String(path).replace(/\/+$/, "") || "/"
    pathField.text = picker.current
    picker.reload()
  }

  function parentOf(path) {
    var p = String(path).replace(/\/+$/, "")
    var i = p.lastIndexOf("/")
    if (i <= 0) return "/"
    return p.slice(0, i)
  }

  readonly property var visibleEntries: picker.entries.filter(function (name) {
    return picker.showHidden || name.charAt(0) !== "."
  })

  Process {
    id: lister
    environment: ({ "LC_ALL": "C" })
    stdout: StdioCollector {
      id: listerOut
      waitForEnd: true
      onStreamFinished: {
        picker.entries = String(listerOut.text || "").split("\n").filter(function (l) { return l.length > 0 })
        picker.loading = false
        listView.currentIndex = -1
      }
    }
  }

  implicitWidth: Style.space(420)
  implicitHeight: Style.space(380)

  // Everything under the picker is a dismissal surface, so the picker has to
  // stop the clicks that land on its own background — otherwise clicking a
  // gap between two controls closes the dialog you are using.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    onClicked: function (event) { event.accepted = true }
  }

  // Loading is driven by the picker's own visibility rather than by the
  // surface it sits on: the surface can already be up for a menu when the
  // picker opens, and then its visibility never changes to announce it.
  onVisibleChanged: if (visible) Qt.callLater(function () { picker.open(picker.startPath || picker.home) })

  GlassPanel {
    anchors.fill: parent
    radius: Style.space(14)
    backgroundOpacity: 0.94
    tint: Color.menu.background
    elevated: true
    showSpine: false
  }

  // Anchored in three bands rather than stacked in one column: the list has
  // to take whatever is left between the controls above it and the buttons
  // below, and a column that computes that from its own height gets it wrong
  // by exactly the height of the last row it has not laid out yet.
  Column {
    id: topBlock
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space(14)
    spacing: Style.space(10)

    Text {
      textFormat: Text.PlainText
      text: "Add a folder to the shelf"
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }

    // The path is editable, because typing `~/Proiecte-dev/whatever` beats
    // clicking down to it and everyone who reaches for a picker knows that.
    Rectangle {
      width: parent.width
      height: Style.spacing.controlHeight
      radius: Style.space(8)
      color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.06)
      border.width: 1
      border.color: pathField.activeFocus
        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.7)
        : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.16)

      TextInput {
        id: pathField
        anchors.fill: parent
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        verticalAlignment: TextInput.AlignVCenter
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        selectByMouse: true
        selectionColor: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.4)
        clip: true
        onAccepted: {
          var typed = String(text || "").trim().replace(/^~(?=\/|$)/, picker.home)
          if (typed.length > 0) picker.navigate(typed)
        }
        Keys.onEscapePressed: picker.cancelled()
      }
    }

    // Up, and the shortcuts worth having in a picker that opens over and over.
    Row {
      width: parent.width
      spacing: Style.space(6)

      PickerButton {
        text: "↑ Up"
        enabled: picker.current !== "/"
        onClicked: picker.navigate(picker.parentOf(picker.current))
      }

      PickerButton {
        text: "Home"
        onClicked: picker.navigate(picker.home)
      }

      PickerButton {
        text: picker.showHidden ? "Hiding none" : "Hiding dotfiles"
        onClicked: picker.showHidden = !picker.showHidden
      }
    }
  }

  Item {
    id: footer
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space(14)
    height: Style.spacing.controlHeight

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: footerButtons.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: Format.prettyPath(picker.current, picker.home, 40)
      color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
    }

    Row {
      id: footerButtons
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      PickerButton {
        text: "Cancel"
        onClicked: picker.cancelled()
      }

      PickerButton {
        text: "Add this folder"
        accented: true
        onClicked: picker.chosen(picker.current)
      }
    }
  }

  Rectangle {
    anchors.top: topBlock.bottom
    anchors.topMargin: Style.space(10)
    anchors.bottom: footer.top
    anchors.bottomMargin: Style.space(10)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(14)
    anchors.rightMargin: Style.space(14)
    radius: Style.space(10)
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.04)
    border.width: 1
    border.color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10)
    clip: true

    ListView {
      id: listView
      anchors.fill: parent
      anchors.margins: Style.space(4)
      model: picker.visibleEntries
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      currentIndex: -1

      delegate: Rectangle {
        required property string modelData
        required property int index
        readonly property string fullPath: (picker.current === "/" ? "" : picker.current) + "/" + modelData
        readonly property bool onShelf: picker.alreadyOnShelf.indexOf(fullPath) !== -1

        width: ListView.view.width
        height: Style.spacing.popupRowHeight
        radius: Style.space(7)
        color: entryMouse.containsMouse
          ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
          : "transparent"

        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.right: shelfMark.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: modelData
          color: Color.menu.text
          opacity: parent.onShelf ? 0.45 : 1.0
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideMiddle
        }

        Text {
          id: shelfMark
          textFormat: Text.PlainText
          anchors.right: addHere.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          visible: parent.onShelf
          text: "on the shelf"
          color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        // Double duty per row: the row walks into the folder, the button
        // takes it. Without the split you can only add folders you can also
        // enter, which is the wrong way round for a leaf you are standing on.
        PickerButton {
          id: addHere
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          visible: entryMouse.containsMouse && !parent.onShelf
          text: "Add"
          accented: true
          onClicked: picker.chosen(parent.fullPath)
        }

        MouseArea {
          id: entryMouse
          anchors.fill: parent
          anchors.rightMargin: Style.space(70)
          hoverEnabled: true
          onClicked: picker.navigate(parent.fullPath)
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      visible: !picker.loading && picker.visibleEntries.length === 0
      text: "No folders in here"
      color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }
}
