import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Store.js" as Store
import "Format.js" as Format

// The shelf itself, plus the two surfaces that have to escape its edges.
//
// A layer-shell surface clips its children, so a preview card that hangs off
// the side of the shelf and a menu that opens past its corner cannot live
// inside it. They get their own full-screen surfaces on the same output: the
// preview one is masked to nothing so it never takes a pointer event away
// from the tile being hovered, and the menu one takes the whole screen so a
// click anywhere outside closes it.
Scope {
  id: host

  property var targetScreen: null
  property var service: null
  property var scanner: null

  readonly property var winDoc: host.service ? host.service.doc.window : null
  readonly property string home: host.service ? host.service.home : ""
  readonly property var folders: host.service ? host.service.folders : []

  function setting(name, fallback) {
    return host.service ? host.service.setting(name, fallback) : fallback
  }

  // ------------------------------------------------------------- ownership
  //
  // The shelf remembers which monitor it was left on. If that monitor is not
  // here any more the first one takes it, rather than the shelf quietly not
  // existing on a machine that has been undocked.
  readonly property bool storedScreenPresent: {
    var name = host.winDoc ? host.winDoc.screen : ""
    if (!name) return false
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++) if (list[i].name === name) return true
    return false
  }

  readonly property bool ownsShelf: {
    if (!host.targetScreen || !host.winDoc) return false
    if (host.storedScreenPresent) return host.targetScreen.name === host.winDoc.screen
    var list = Quickshell.screens
    return list.length > 0 && list[0] === host.targetScreen
  }

  // -------------------------------------------------------------- settings
  readonly property bool listMode: String(host.setting("layout", "Grid")) === "List"
  readonly property int tileSize: Math.max(40, Math.min(160, Number(host.setting("tileSize", 64)) || 64))
  readonly property bool showLabels: host.setting("showLabels", true) === true
  readonly property real glassOpacity: Math.max(0.1, Math.min(1.0, (Number(host.setting("backgroundOpacity", 80)) || 80) / 100))
  readonly property bool previewEnabled: host.setting("showPreview", true) === true
  readonly property int previewDelay: Math.max(0, Math.min(2000, Number(host.setting("previewDelay", 320)) || 0))
  readonly property int thumbnailCount: Math.max(0, Math.min(8, Number(host.setting("thumbnailCount", 4)) || 0))
  readonly property int recentCount: Math.max(0, Math.min(12, Number(host.setting("recentCount", 6)) || 0))
  readonly property bool locked: host.setting("lockPosition", false) === true

  // -------------------------------------------------------------- geometry
  //
  // Live geometry is a plain property rather than a binding on the document:
  // a drag writes it on every frame, and a binding would be broken by the
  // first write and never restored. The document is the resting place, this
  // is the working copy, and `syncGeometry` moves one into the other whenever
  // nobody has hold of the window.
  property int posX: 120
  property int posY: 120
  property int shelfW: 460
  property int shelfH: 340
  property bool interacting: false

  function syncGeometry() {
    if (host.interacting || !host.winDoc) return
    host.posX = host.winDoc.x
    host.posY = host.winDoc.y
    host.shelfW = host.winDoc.width
    host.shelfH = host.winDoc.height
    host.clampToScreen()
  }

  function clampToScreen() {
    if (!host.targetScreen) return
    var sw = host.targetScreen.width
    var sh = host.targetScreen.height
    host.shelfW = Math.max(Style.space(220), Math.min(host.shelfW, sw))
    host.shelfH = Math.max(Style.space(140), Math.min(host.shelfH, sh))
    // A shelf is allowed to hang off an edge, but not so far that the header
    // you drag it back by is gone.
    host.posX = Math.max(-(host.shelfW - Style.space(80)), Math.min(host.posX, sw - Style.space(80)))
    host.posY = Math.max(0, Math.min(host.posY, sh - Style.space(40)))
  }

  function persistGeometry() {
    if (!host.service || !host.targetScreen) return
    host.service.saveGeometry(host.posX, host.posY, host.shelfW, host.shelfH, host.targetScreen.name)
  }

  Connections {
    target: host.service
    enabled: host.service !== null
    function onDocChanged() { host.syncGeometry() }
  }

  Component.onCompleted: host.syncGeometry()

  // ----------------------------------------------------------------- state
  property string filterText: ""
  property int dragIndex: -1
  property int dropIndex: -1
  property real dragX: 0
  property real dragY: 0
  property real dragGrabX: 0
  property real dragGrabY: 0

  property int previewIndex: -1
  property rect previewAnchor: Qt.rect(0, 0, 0, 0)

  // What the header says instead of "Shelf" while a button is under the
  // pointer. Cheaper than a tooltip surface and it never covers anything.
  property string hint: ""

  property int menuIndex: -1
  property real menuX: 0
  property real menuY: 0
  property bool pickerOpen: false

  readonly property bool modalOpen: host.menuIndex >= 0 || host.pickerOpen

  // The folders actually drawn, each carrying the index it has in the
  // document — a filtered shelf still has to remove and reorder the right one.
  readonly property var visibleFolders: {
    var q = String(host.filterText || "").trim().toLowerCase()
    var out = []
    for (var i = 0; i < host.folders.length; i++) {
      var f = host.folders[i]
      if (q.length > 0) {
        var name = (f.label || Format.baseName(f.path)).toLowerCase()
        if (name.indexOf(q) === -1 && f.path.toLowerCase().indexOf(q) === -1) continue
      }
      out.push({ folder: f, index: i })
    }
    return out
  }

  readonly property bool filtering: String(host.filterText || "").trim().length > 0
  readonly property var shelfPaths: host.folders.map(function (f) { return f.path })

  function closeTransients() {
    host.menuIndex = -1
    host.pickerOpen = false
    host.previewIndex = -1
    previewTimer.stop()
  }

  // ------------------------------------------------------------ the window

  PanelWindow {
    id: shelf

    screen: host.targetScreen
    visible: host.service !== null && host.service.shelfVisible && host.ownsShelf
    color: "transparent"

    WlrLayershell.namespace: "omarchy-folder-shelf"
    // Bottom is the desktop: below every window, above the wallpaper. Overlay
    // is the lift. Nothing in between is worth offering — Top still loses to
    // a fullscreen window, which is exactly when you reach for the lift.
    WlrLayershell.layer: (host.service && host.service.raised) ? WlrLayer.Overlay : WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; left: true }
    margins { left: host.posX; top: host.posY }
    implicitWidth: host.shelfW
    implicitHeight: host.shelfH

    GlassPanel {
      anchors.fill: parent
      radius: Style.space(18)
      backgroundOpacity: host.glassOpacity
      elevated: host.service ? host.service.raised : false
    }

    // Folders dragged in from a file manager. Whether a layer-shell surface
    // is offered a Wayland drag at all is the compositor's call, so this is
    // additive: if it never fires, the + button is still the way in.
    DropArea {
      anchors.fill: parent
      keys: ["text/uri-list"]

      onDropped: function (drop) {
        if (!drop.hasUrls || !host.service) { drop.accepted = false; return }
        var added = 0
        for (var i = 0; i < drop.urls.length; i++) {
          var u = String(drop.urls[i])
          if (u.indexOf("file://") !== 0) continue
          var path = decodeURIComponent(u.slice(7))
          if (host.service.addFolder(path)) added++
        }
        drop.accepted = added > 0
      }

      Rectangle {
        anchors.fill: parent
        anchors.margins: Style.space(4)
        visible: parent.containsDrag
        radius: Style.space(14)
        color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
        border.width: 2
        border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.6)
      }
    }

    // ------------------------------------------------------------- header
    Item {
      id: header
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: Style.space(10)
      height: Style.spacing.controlHeight

      // The whole header is the handle. A dedicated title bar strip would be
      // more discoverable and would also cost the shelf a quarter of its
      // height, which on a widget this size is the wrong trade.
      MouseArea {
        id: mover
        anchors.fill: parent
        enabled: !host.locked
        acceptedButtons: Qt.LeftButton
        cursorShape: host.locked ? Qt.ArrowCursor
                                 : (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

        property real grabX: 0
        property real grabY: 0

        onPressed: function (event) {
          host.closeTransients()
          host.interacting = true
          mover.grabX = event.x
          mover.grabY = event.y
        }

        // The window moves under the pointer, so the pointer's own local
        // coordinate springs back to where it was pressed. Feeding the
        // difference back into the margin is therefore self-correcting, and
        // it is the only way to do this without a pointer grab we do not have.
        onPositionChanged: function (event) {
          if (!mover.pressed) return
          host.posX += Math.round(event.x - mover.grabX)
          host.posY += Math.round(event.y - mover.grabY)
          host.clampToScreen()
        }

        onReleased: {
          host.interacting = false
          host.persistGeometry()
        }
        onCanceled: {
          host.interacting = false
          host.persistGeometry()
        }
      }

      Text {
        id: brand
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        visible: !searchBox.expanded
        text: host.hint.length > 0 ? host.hint : "Shelf"
        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, host.hint.length > 0 ? 0.8 : 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        anchors.left: brand.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        visible: brand.visible && host.hint.length === 0 && host.folders.length > 0
        text: host.folders.length + (host.folders.length === 1 ? " folder" : " folders")
        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.32)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Row {
        id: headerActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        // Search collapses to a glyph, because on a shelf of six folders it
        // is clutter and on a shelf of thirty it is the only way through.
        Item {
          id: searchBox
          property bool expanded: false
          width: expanded ? Math.min(Style.space(170), header.width - Style.space(120)) : Style.spacing.controlHeight
          height: Style.spacing.controlHeight
          anchors.verticalCenter: parent.verticalCenter

          Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

          Rectangle {
            anchors.fill: parent
            radius: Style.space(8)
            color: searchBox.expanded || searchMouse.containsMouse
              ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10)
              : "transparent"
            border.width: 1
            border.color: searchInput.activeFocus
              ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.6)
              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, searchBox.expanded ? 0.18 : 0.0)
            Behavior on color { ColorAnimation { duration: 140 } }
          }

          Text {
            id: searchGlyph
            anchors.left: parent.left
            anchors.leftMargin: Style.space(9)
            anchors.verticalCenter: parent.verticalCenter
            text: "⌕"
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
          }

          TextInput {
            id: searchInput
            anchors.left: searchGlyph.right
            anchors.leftMargin: Style.space(6)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            visible: searchBox.expanded
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            selectByMouse: true
            selectionColor: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.4)
            clip: true
            onTextChanged: host.filterText = text
            Keys.onEscapePressed: {
              searchInput.text = ""
              searchBox.expanded = false
              searchInput.focus = false
            }
          }

          MouseArea {
            id: searchMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !searchBox.expanded
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              searchBox.expanded = true
              // Typing needs keyboard focus, and a surface on the bottom
              // layer is not given any until it is asked for. Lifting the
              // shelf is the honest way to ask.
              if (host.service && !host.service.raised) host.service.setRaised(true)
              Qt.callLater(function () { searchInput.forceActiveFocus() })
            }
          }
        }

        GlyphButton {
          glyph: "+"
          onHoveredChanged: host.hint = hovered ? tip : ""
          tip: "Add a folder"
          onActivated: {
            host.closeTransients()
            host.pickerOpen = true
          }
        }

        GlyphButton {
          glyph: host.service && host.service.raised ? "▲" : "▽"
          onHoveredChanged: host.hint = hovered ? tip : ""
          tip: host.service && host.service.raised ? "Put it back on the desktop" : "Lift it above your windows"
          active: host.service ? host.service.raised : false
          onActivated: if (host.service) host.service.toggleRaised()
        }

        GlyphButton {
          glyph: "×"
          onHoveredChanged: host.hint = hovered ? tip : ""
          tip: "Hide the shelf"
          onActivated: if (host.service) host.service.setVisible(false)
        }
      }
    }

    // -------------------------------------------------------------- field
    Item {
      id: field
      anchors.top: header.bottom
      anchors.topMargin: Style.space(8)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      anchors.bottomMargin: Style.space(12)
      clip: true

      readonly property int gap: Style.space(8)
      readonly property int cellW: host.listMode
        ? width
        : Math.max(Style.space(52), host.tileSize + Style.space(16))
      readonly property int cellH: host.listMode
        ? Math.max(Style.space(38), host.tileSize * 0.62)
        : Math.round(host.tileSize * 0.82) + (host.showLabels ? Style.space(32) : Style.space(8))
      readonly property int columns: host.listMode
        ? 1
        : Math.max(1, Math.floor((width + gap) / (cellW + gap)))

      readonly property int rows: Math.ceil(host.visibleFolders.length / Math.max(1, columns))
      readonly property int contentHeight: rows * cellH + Math.max(0, rows - 1) * gap

      // Where a tile ends up once the one being dragged is taken out of the
      // order and put back somewhere else. Everything between the two indices
      // shifts by one; nothing outside them moves at all.
      function slotFor(displayIndex) {
        if (host.dragIndex < 0 || host.dropIndex < 0) return displayIndex
        var from = host.dragIndex
        var to = host.dropIndex
        if (from === to) return displayIndex
        if (displayIndex === from) return to
        if (from < to) return (displayIndex > from && displayIndex <= to) ? displayIndex - 1 : displayIndex
        return (displayIndex >= to && displayIndex < from) ? displayIndex + 1 : displayIndex
      }

      // Slots, drags and hit tests all live in the flickable's content item,
      // so none of them has to know how far the shelf is scrolled.
      function slotX(slot) { return (slot % columns) * (cellW + gap) }
      function slotY(slot) { return Math.floor(slot / columns) * (cellH + gap) }

      function slotAt(x, y) {
        var col = Math.max(0, Math.min(columns - 1, Math.floor(x / (cellW + gap))))
        var row = Math.max(0, Math.floor(y / (cellH + gap)))
        return Math.max(0, Math.min(host.visibleFolders.length - 1, row * columns + col))
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: field.contentHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: host.dragIndex < 0
        clip: true

        // The tiles are placed rather than laid out, because a positioner
        // cannot animate a reorder that has not been committed yet — and the
        // whole point of dragging one is watching the others get out of the way.
        Item {
          id: cluster
          width: field.width
          height: field.contentHeight

          Repeater {
            model: host.visibleFolders

            FolderTile {
              id: tile
              required property var modelData
              required property int index

              readonly property int docIndex: modelData.index
              readonly property bool isDragged: host.dragIndex === index

              folder: modelData.folder
              scan: host.scanner
                ? (host.scanner.revision >= 0 ? host.scanner.result(modelData.folder.path) : null)
                : null
              home: host.home
              tileSize: host.tileSize
              showLabel: host.showLabels
              listMode: host.listMode
              dragging: isDragged
              dropTarget: host.dragIndex >= 0 && host.dropIndex === index && !isDragged

              width: field.cellW
              height: field.cellH
              x: isDragged ? host.dragX : field.slotX(field.slotFor(index))
              y: isDragged ? host.dragY : field.slotY(field.slotFor(index))
              z: isDragged ? 10 : 1

              Behavior on x { enabled: !tile.isDragged; NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
              Behavior on y { enabled: !tile.isDragged; NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

              onActivated: if (host.service) host.service.openFolder(modelData.folder.path)
              onTerminalRequested: if (host.service) host.service.openTerminal(modelData.folder.path)

              onMenuRequested: function (sceneX, sceneY) {
                host.previewIndex = -1
                previewTimer.stop()
                host.menuIndex = tile.docIndex
                host.menuX = host.posX + sceneX
                host.menuY = host.posY + sceneY
              }

              onHoverStarted: {
                if (host.dragIndex >= 0 || !host.previewEnabled || host.modalOpen) return
                if (host.scanner) host.scanner.request(modelData.folder.path, true)
                previewTimer.pending = tile.docIndex
                previewTimer.pendingItem = tile
                previewTimer.restart()
              }

              onHoverEnded: {
                if (previewTimer.pending === tile.docIndex) previewTimer.stop()
                if (host.previewIndex === tile.docIndex) host.previewIndex = -1
              }

              onDragStarted: function (sceneX, sceneY) {
                if (host.filtering || host.locked) return
                host.previewIndex = -1
                previewTimer.stop()
                var local = cluster.mapFromItem(null, sceneX, sceneY)
                host.dragGrabX = local.x - tile.x
                host.dragGrabY = local.y - tile.y
                host.dragIndex = index
                host.dropIndex = index
                host.dragX = tile.x
                host.dragY = tile.y
              }

              onDragMoved: function (sceneX, sceneY) {
                if (host.dragIndex !== index) return
                var local = cluster.mapFromItem(null, sceneX, sceneY)
                host.dragX = local.x - host.dragGrabX
                host.dragY = local.y - host.dragGrabY
                host.dropIndex = field.slotAt(host.dragX + field.cellW / 2, host.dragY + field.cellH / 2)
              }

              onDragFinished: {
                if (host.dragIndex !== index) return
                var from = index
                var to = host.dropIndex
                host.dragIndex = -1
                host.dropIndex = -1
                if (to >= 0 && to !== from && host.service && !host.filtering)
                  host.service.moveFolder(host.visibleFolders[from].index, host.visibleFolders[to].index)
              }
            }
          }
        }
      }

      // ------------------------------------------------------- empty state
      Column {
        anchors.centerIn: parent
        width: parent.width - Style.space(30)
        spacing: Style.space(10)
        visible: host.folders.length === 0

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: "Nothing on the shelf yet.\nDrop a folder here, or add one."
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        PickerButton {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Add a folder"
          accented: true
          onClicked: {
            host.closeTransients()
            host.pickerOpen = true
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: host.folders.length > 0 && host.visibleFolders.length === 0
        text: "Nothing matches “" + host.filterText + "”"
        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    // --------------------------------------------------------- resize grip
    Item {
      id: grip
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      width: Style.space(18)
      height: Style.space(18)
      visible: !host.locked

      // Three diagonal ticks. A corner that says it can be pulled without
      // putting a chrome-heavy handle on a surface that is trying to be glass.
      Repeater {
        model: 3
        Rectangle {
          required property int index
          width: Style.space(2)
          height: Style.space(2) + index * Style.space(3)
          radius: width / 2
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b,
                         gripMouse.containsMouse ? 0.55 : 0.25)
          x: grip.width - Style.space(6) - index * Style.space(4)
          y: grip.height - Style.space(5) - height + Style.space(1)
          rotation: 0
        }
      }

      MouseArea {
        id: gripMouse
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.SizeFDiagCursor

        property real startX: 0
        property real startY: 0
        property int startW: 0
        property int startH: 0

        onPressed: function (event) {
          host.closeTransients()
          host.interacting = true
          gripMouse.startX = event.x
          gripMouse.startY = event.y
          gripMouse.startW = host.shelfW
          gripMouse.startH = host.shelfH
        }

        // Resizing keeps the top-left pinned, so unlike the move the local
        // coordinates do not spring back and a plain delta is correct.
        onPositionChanged: function (event) {
          if (!gripMouse.pressed) return
          host.shelfW = gripMouse.startW + Math.round(event.x - gripMouse.startX)
          host.shelfH = gripMouse.startH + Math.round(event.y - gripMouse.startY)
          host.clampToScreen()
        }

        onReleased: {
          host.interacting = false
          host.persistGeometry()
        }
        onCanceled: {
          host.interacting = false
          host.persistGeometry()
        }
      }
    }
  }

  // The hover delay lives here rather than in the tile so that moving across
  // the shelf re-aims one timer instead of starting one per folder.
  Timer {
    id: previewTimer
    property int pending: -1
    property var pendingItem: null
    interval: host.previewDelay
    repeat: false
    onTriggered: {
      if (previewTimer.pending < 0 || !previewTimer.pendingItem) return
      var item = previewTimer.pendingItem
      var origin = item.mapToItem(null, 0, 0)
      host.previewAnchor = Qt.rect(origin.x, origin.y, item.width, item.height)
      host.previewIndex = previewTimer.pending
    }
  }

  // ----------------------------------------------------------- preview surface
  PanelWindow {
    id: previewLayer

    screen: host.targetScreen
    visible: host.previewIndex >= 0 && host.ownsShelf && host.service && host.service.shelfVisible
    color: "transparent"

    WlrLayershell.namespace: "omarchy-folder-shelf-preview"
    WlrLayershell.layer: (host.service && host.service.raised) ? WlrLayer.Overlay : WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; left: true; right: true; bottom: true }

    // Masked to nothing. The card is a thing to look at, and a surface that
    // took pointer events would end the hover that summoned it the instant it
    // appeared underneath the cursor.
    mask: Region {}

    readonly property var folder: (host.previewIndex >= 0 && host.previewIndex < host.folders.length)
      ? host.folders[host.previewIndex] : null

    PreviewCard {
      id: previewCard

      readonly property real anchorX: host.posX + host.previewAnchor.x
      readonly property real anchorY: host.posY + host.previewAnchor.y
      readonly property real gap: Style.space(10)

      // Beside the shelf, not beside the tile. Anchoring to the tile is the
      // obvious reading of "next to the folder" and it puts the card straight
      // over the rest of the shelf — you lose sight of the folders while
      // reading about one of them. So the card clears the whole shelf: right
      // if it fits, left if it does not, and clamped into the screen either
      // way, because a preview off the edge is worse than one on the far side.
      x: {
        var right = host.posX + host.shelfW + gap
        if (right + width <= previewLayer.width - gap) return right
        var left = host.posX - width - gap
        if (left >= gap) return left
        return Math.max(gap, Math.min(previewLayer.width - width - gap, anchorX))
      }

      // Level with the folder, but never further from the shelf than the
      // shelf is tall: a card that drifts up into the bar or down past the
      // bottom edge stops reading as belonging to the folder under the cursor.
      y: {
        var preferred = anchorY + host.previewAnchor.height / 2 - height / 2
        var low = (height <= host.shelfH) ? host.posY : host.posY + host.shelfH - height
        var high = (height <= host.shelfH) ? host.posY + host.shelfH - height : host.posY
        var placed = Math.max(low, Math.min(high, preferred))
        return Math.max(gap, Math.min(previewLayer.height - height - gap, placed))
      }

      path: previewLayer.folder ? previewLayer.folder.path : ""
      title: previewLayer.folder ? Store.displayName(previewLayer.folder, host.home) : ""
      home: host.home
      thumbnailCount: host.thumbnailCount
      recentCount: host.recentCount
      backgroundOpacity: Math.min(0.96, host.glassOpacity + 0.1)
      scan: (host.scanner && previewLayer.folder && host.scanner.revision >= 0)
        ? host.scanner.result(previewLayer.folder.path) : null

      opacity: host.previewIndex >= 0 ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
    }
  }

  // ------------------------------------------------------------ modal surface
  PanelWindow {
    id: modalLayer

    screen: host.targetScreen
    visible: host.modalOpen && host.ownsShelf
    color: "transparent"

    WlrLayershell.namespace: "omarchy-folder-shelf-modal"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; left: true; right: true; bottom: true }

    readonly property var menuFolder: (host.menuIndex >= 0 && host.menuIndex < host.folders.length)
      ? host.folders[host.menuIndex] : null

    // The whole screen catches the dismissing click. Anything that opens over
    // the desktop and cannot be closed by clicking away from it is a trap.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: host.closeTransients()
    }

    ShelfMenu {
      id: contextMenu
      visible: host.menuIndex >= 0
      folder: modalLayer.menuFolder
      home: host.home

      x: Math.max(Style.space(6), Math.min(modalLayer.width - width - Style.space(6), host.menuX))
      y: Math.max(Style.space(6), Math.min(modalLayer.height - height - Style.space(6), host.menuY))

      onOpenRequested: {
        if (host.service && modalLayer.menuFolder) host.service.openFolder(modalLayer.menuFolder.path)
        host.closeTransients()
      }
      onTerminalRequested: {
        if (host.service && modalLayer.menuFolder) host.service.openTerminal(modalLayer.menuFolder.path)
        host.closeTransients()
      }
      onCopyRequested: {
        if (host.service && modalLayer.menuFolder) host.service.copyPath(modalLayer.menuFolder.path)
        host.closeTransients()
      }
      onRenamed: function (label) {
        if (host.service && modalLayer.menuFolder) host.service.renameFolder(modalLayer.menuFolder.path, label)
        host.closeTransients()
      }
      onRemoveRequested: {
        if (host.service && modalLayer.menuFolder) host.service.removeFolder(modalLayer.menuFolder.path)
        host.closeTransients()
      }
      onDismissed: host.closeTransients()
    }

    FolderPicker {
      id: folderPicker
      visible: host.pickerOpen
      home: host.home
      startPath: host.home
      alreadyOnShelf: host.shelfPaths

      // Centred on the screen rather than on the shelf. Over the shelf it
      // hides the folders you are about to compare against, and the picker is
      // the one surface here that is a dialog rather than a piece of the
      // widget.
      x: Math.round((modalLayer.width - width) / 2)
      y: Math.round((modalLayer.height - height) / 2)

      onChosen: function (path) {
        if (host.service) host.service.addFolder(path)
        host.pickerOpen = false
      }
      onCancelled: host.pickerOpen = false
    }

    onVisibleChanged: {
      if (visible && host.pickerOpen) Qt.callLater(function () { folderPicker.open(host.home) })
    }
  }
}
