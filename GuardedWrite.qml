import QtQuick
import Quickshell
import Quickshell.Io

// The write half of BoundedFile: an atomic replace of a file whose path this
// plugin does not control.
//
// FileView's own atomic write resolves the path like any open does, so a
// symlink at the file or at any directory above it redirects the write. QML
// has no openat, no O_NOFOLLOW and no descriptor to hold, so the write is done
// by write.py, which walks the path from `/` with no-follow directory
// descriptors, refuses a directory that is not owned and private, and renames
// a fresh temporary into place relative to the directory it checked. See the
// top of write.py for the exact rules.
//
// The contents go over stdin, never argv. The interpreter runs isolated (`-I`:
// no PYTHON* variables, no user site, no current directory on the path) with a
// built environment, under `timeout`, and is stopped when this object goes.
//
// Writes are coalesced rather than queued: only the latest contents matter, so
// a write asked for while one is running replaces whatever was waiting and
// goes out when the running one ends.
Item {
  id: writer

  property string path: ""
  property int limit: 262144
  property int deadline: 5
  property bool printErrors: true

  // Emitted when a write has finished, whether or not it succeeded.
  signal written(bool ok)

  readonly property string pythonBin: "/usr/bin/python3"
  readonly property string timeoutBin: "/usr/bin/timeout"
  readonly property string scriptPath: {
    var url = String(Qt.resolvedUrl("write.py"))
    return decodeURIComponent(url.replace(/^file:\/\//, ""))
  }

  readonly property bool busy: inFlight || hasPending

  // A write is in flight from the moment the helper is asked for until it
  // exits or the guard gives up on it. Quickshell reports no event for a
  // launch that fails outright, so `exited` alone cannot be the only way out.
  property bool inFlight: false

  property bool hasPending: false
  property string pendingText: ""
  property string pendingPath: ""
  property string activeText: ""

  function write(text) {
    writer.pendingText = String(text)
    writer.pendingPath = String(writer.path || "")
    writer.hasPending = true
    if (!writer.inFlight) writer.startNext()
  }

  // Ends the write in flight exactly once, whichever of the exit, the guard
  // or a failed start gets there first.
  function finish(ok) {
    if (!writer.inFlight) return
    writer.inFlight = false
    guard.stop()
    proc.stdinEnabled = true
    writer.written(ok)
    // Not from inside this process's own handler.
    Qt.callLater(writer.startNext)
  }

  function startNext() {
    if (!writer.hasPending) return
    writer.hasPending = false
    if (writer.pendingPath.length === 0) {
      writer.written(false)
      Qt.callLater(writer.startNext)
      return
    }
    writer.activeText = writer.pendingText
    writer.pendingText = ""
    proc.command = [writer.timeoutBin, "-k", "1", String(writer.deadline),
                    writer.pythonBin, "-I", writer.scriptPath,
                    writer.pendingPath, String(writer.limit)]
    writer.inFlight = true
    guard.restart()
    proc.running = true
  }

  // The helper is under `timeout`, so it is over by deadline + 1 second; this
  // fires only when it was never started or its exit was never reported.
  Timer {
    id: guard
    interval: (writer.deadline + 3) * 1000
    repeat: false
    onTriggered: {
      if (!writer.inFlight) return
      if (writer.printErrors) console.warn("folder-shelf write: helper did not finish")
      proc.running = false
      writer.finish(false)
    }
  }

  Process {
    id: proc
    clearEnvironment: true
    environment: ({ "PATH": "/usr/bin:/bin", "LC_ALL": "C.UTF-8" })
    workingDirectory: "/"
    stdinEnabled: true
    onStarted: {
      proc.write(writer.activeText)
      writer.activeText = ""
      // Closing stdin is what ends the helper's read.
      proc.stdinEnabled = false
    }
    // The helper says why on stderr and nothing otherwise, so this is the
    // error report whichever order it arrives in relative to `exited`.
    stderr: StdioCollector {
      id: errOut
      waitForEnd: true
      onStreamFinished: {
        var why = String(errOut.text || "").trim()
        if (why.length > 0 && writer.printErrors) console.warn(why)
      }
    }
    onExited: function (exitCode) { writer.finish(exitCode === 0) }
  }

  Component.onDestruction: proc.running = false
}
