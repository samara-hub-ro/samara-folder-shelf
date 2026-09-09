import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
// Qualified as well as plain: this file is itself called BarWidget.qml, and a
// composite type from the plugin's own directory outranks an imported one, so
// the bare name would resolve to this file rather than to the shell's base
// component. Everything else in qs.Ui is unambiguous and stays unqualified.
import qs.Ui as Ui

// Folder Shelf — the bar half.
//
// The shelf lives in the service, which is loaded whether or not this widget
// is on the bar. What the widget adds is a switch and, more importantly, a
// home for the settings: the shell keeps a plugin's settings on its bar
// entry, so they arrive here and are pushed across. With no widget on the bar
// the shelf runs on the manifest defaults, which is documented rather than
// accidental — but it is also why the widget is worth having.
Ui.BarWidget {
  id: root

  moduleName: "samara-hub-ro.folder-shelf"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string barIcon: String(setting("icon", ""))

  // The shared link first, the documented lookup second. `bar.shell` is a
  // shell API scoped to whoever owns the bar, so under a third-party bar this
  // lookup runs in that bar's name rather than ours and comes back null.
  readonly property var service: {
    if (ShelfLink.service) return ShelfLink.service
    var sh = root.bar && root.bar.shell ? root.bar.shell : null
    if (!sh || typeof sh.serviceFor !== "function") return null
    return sh.serviceFor("samara-hub-ro.folder-shelf")
  }

  readonly property bool shelfVisible: root.service ? root.service.shelfVisible : false
  readonly property bool shelfRaised: root.service ? root.service.raised : false

  // The settings the shell handed this widget are the shelf's settings. They
  // are pushed rather than pulled because the service has no way to find its
  // own bar entry, and re-pushed on every change so editing a setting in the
  // shell's own UI moves the shelf without a restart.
  function pushSettings() {
    if (root.service) root.service.pushedSettings = root.settings || ({})
  }

  onSettingsChanged: root.pushSettings()
  onServiceChanged: root.pushSettings()
  Component.onCompleted: root.pushSettings()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barIcon
    iconComponent: root.barIcon.length > 0 ? null : shelfMark
    active: root.shelfVisible
    tooltipText: {
      if (!root.service) return "Folder Shelf"
      if (!root.shelfVisible) return "Show the folder shelf"
      return root.shelfRaised ? "Hide the shelf · right click to drop it back"
                              : "Hide the shelf · right click to lift it"
    }

    onPressed: function (b) {
      if (!root.service) return
      if (b === Qt.RightButton) {
        // Lifting an invisible shelf is not a thing anyone means, so the
        // right button shows it first and lifts it on the way.
        if (!root.shelfVisible) {
          root.service.setVisible(true)
          root.service.setRaised(true)
        } else {
          root.service.toggleRaised()
        }
        return
      }
      root.service.toggle()
    }
  }

  Component {
    id: shelfMark
    ShelfMark {
      color: button.active && button.useActiveColor ? button.activeColor : button.foreground
    }
  }
}
