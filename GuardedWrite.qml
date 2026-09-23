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

  readonly property bool busy: proc.running || hasPending

  property bool hasPending: false
  property string pendingText: ""
  property string pendingPath: ""
  property string activeText: ""

  function write(text) {
    writer.pendingText = String(text)
    writer.pendingPath = String(writer.path || "")
    writer.hasPending = true
    if (!proc.running) writer.startNext()
  }

  function startNext() {
    if (!writer.hasPending) return
    writer.hasPending = false
    if (writer.pendingPath.length === 0) {
      writer.written(false)
      return
    }
    writer.activeText = writer.pendingText
    writer.pendingText = ""
    proc.command = [writer.timeoutBin, "-k", "1", String(writer.deadline),
                    writer.pythonBin, "-I", writer.scriptPath,
                    writer.pendingPath, String(writer.limit)]
    proc.running = true
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
    onExited: function (exitCode) {
      proc.stdinEnabled = true
      writer.written(exitCode === 0)
      // Not from inside this process's own handler.
      Qt.callLater(writer.startNext)
    }
  }

  Component.onDestruction: proc.running = false
}
