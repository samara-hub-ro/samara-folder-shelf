import QtQuick
import Quickshell.Io
import "Edit.js" as Edit

// Paste into a TextInput without Qt's own clipboard read.
//
// TextInput's native paste reads the whole clipboard synchronously on the
// shell's thread, with no limit on size or time, so whoever is serving the
// clipboard can stall the desktop. `handle(event, field)` does the
// editing of a read-only field, paste included (a MouseArea over it takes the middle-click
// primary-selection paste) and `paste.py` does the read instead: capped in bytes, capped in time, in its own
// process group, asynchronous to the shell.
//
// A paste is tied to the field that asked and to the request that asked: if
// another request has been made since, or the field has lost focus or gone,
// the answer is dropped instead of landing somewhere the user did not look.
Item {
  id: paster

  property int maxBytes: 2048
  property int deadline: 2
  readonly property string pythonBin: "/usr/bin/python3"
  readonly property string timeoutBin: "/usr/bin/timeout"
  readonly property string scriptPath: {
    var url = String(Qt.resolvedUrl("paste.py"))
    return decodeURIComponent(url.replace(/^file:\/\//, ""))
  }

  property int serial: 0
  property var target: null
  property int targetSerial: -1
  property int restartSerial: -1
  property var restartTarget: null

  function request(field) {
    if (!field) return
    paster.serial++
    if (proc.running) {
      // One read at a time: stop the old one, start the new when it is gone.
      paster.restartTarget = field
      paster.restartSerial = paster.serial
      proc.running = false
      return
    }
    paster.launch(field, paster.serial)
  }

  function launch(field, id) {
    paster.target = field
    paster.targetSerial = id
    proc.command = [paster.timeoutBin, "-k", "1", String(paster.deadline + 1),
                    paster.pythonBin, "-I", paster.scriptPath,
                    String(paster.maxBytes), String(paster.deadline)]
    proc.running = true
    guard.restart()
  }

  function deliver(text) {
    var field = paster.target
    paster.target = null
    if (!field || paster.targetSerial !== paster.serial) return
    if (!field.activeFocus || text.length === 0) return
    Edit.replaceSelection(field, text.slice(0, paster.maxBytes))
  }

  // Call from a field's Keys.onPressed. The field is `readOnly`, so this is
  // where typing, deleting, cutting and pasting happen (see Edit.js); true
  // when the key was one of those and has been taken.
  function handle(event, field) {
    return Edit.apply(event, field, function () { paster.request(field) })
  }

  Process {
    id: proc
    // The environment is inherited: wl-paste needs the Wayland socket.
    environment: ({ "LC_ALL": "C.UTF-8" })
    workingDirectory: "/"
    stdout: StdioCollector {
      id: out
      waitForEnd: true
      onStreamFinished: {
        guard.stop()
        paster.deliver(String(out.text || ""))
      }
    }
    onExited: {
      if (paster.restartTarget) {
        var f = paster.restartTarget
        var id = paster.restartSerial
        paster.restartTarget = null
        Qt.callLater(function () { paster.launch(f, id) })
      }
    }
  }

  // A read that never produced a stream at all (the helper missing, the
  // launch failing) has no event to say so; this is the one that does.
  Timer {
    id: guard
    interval: (paster.deadline + 3) * 1000
    repeat: false
    onTriggered: {
      paster.target = null
      proc.running = false
    }
  }

  Component.onDestruction: proc.running = false
}
