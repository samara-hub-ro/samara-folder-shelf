pragma Singleton
import QtQuick

// The one object the bar widget and the service can both reach.
//
// A bar widget is supposed to find its service through `bar.shell.serviceFor`,
// and under the stock bar it does. Under a third-party bar it cannot: the host
// hands a full-bar plugin a shell API scoped to *that plugin's* id, and an
// older bar passes it straight to the widgets it hosts instead of asking for a
// per-entry one. The lookup then runs in the bar's name, not ours, and returns
// null — so the icon stops working and nothing says why.
//
// A singleton sidesteps the question. Both objects are built by the same QML
// engine from the same directory, so this is simply shared memory between
// them, and it does not care which bar is running.
QtObject {
  id: link

  // Set by Main.qml when the service starts, cleared when it goes away.
  property var service: null
}
