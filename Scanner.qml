import QtQuick
import Quickshell
import Quickshell.Io

// Runs scan.sh, one folder at a time, and remembers what came back.
//
// Hovering across a shelf of ten folders would otherwise start ten recursive
// walks nobody is waiting for any more, so requests go on a stack rather than
// a queue: the folder the pointer is on now is the one that gets the disk.
// Results are cached until they go stale, which is what makes the second
// hover over a big folder instant.
Item {
  id: scanner

  property string scriptPath: ""
  property bool deep: true
  property int timeoutSeconds: 12
  property int thumbnails: 4
  property int recents: 6

  // Seconds a result stays good. Long enough that browsing the shelf does not
  // re-walk anything, short enough that a download you just finished shows up.
  property int freshness: 45

  // path -> result. Replaced rather than mutated, so bindings on `results`
  // re-evaluate; `revision` is there for the ones that read through a function.
  property var results: ({})
  property int revision: 0

  signal scanned(string path)

  property var pending: []
  property string active: ""

  function fresh(path) {
    var r = scanner.results[path]
    if (!r) return false
    return (Date.now() - r.at) < scanner.freshness * 1000
  }

  function result(path) {
    return scanner.results[path] || null
  }

  // `urgent` puts the folder at the top of the stack — that is the hover
  // path. Background refreshes go underneath and get whatever is left.
  function request(path, urgent) {
    var p = String(path || "")
    if (!p || !scanner.scriptPath) return
    if (scanner.fresh(p) && scanner.active !== p) return
    if (scanner.active === p) return
    var i = scanner.pending.indexOf(p)
    if (i !== -1) {
      if (!urgent) return
      scanner.pending.splice(i, 1)
    }
    if (urgent) scanner.pending.unshift(p)
    else scanner.pending.push(p)
    scanner.pump()
  }

  // Drop everything remembered. Called when a setting that changes what a
  // scan even means — the depth, the number of thumbnails — is edited.
  function invalidate() {
    scanner.results = ({})
    scanner.revision++
  }

  function forget(path) {
    var next = ({})
    for (var k in scanner.results) if (k !== path) next[k] = scanner.results[k]
    scanner.results = next
    scanner.revision++
  }

  function pump() {
    if (scanner.active || scanner.pending.length === 0) return
    var p = scanner.pending.shift()
    scanner.active = p
    proc.command = ["bash", scanner.scriptPath, p,
                    scanner.deep ? "1" : "0",
                    String(scanner.timeoutSeconds),
                    String(scanner.thumbnails),
                    String(scanner.recents)]
    proc.running = true
    watchdog.restart()
  }

  function blank(path) {
    return {
      path: path, ok: false, error: "", at: Date.now(), deep: scanner.deep,
      mode: "", owner: "", group: "", mtime: 0,
      topFiles: 0, topDirs: 0,
      files: 0, dirs: 0, bytes: 0, partial: false,
      recent: [], categories: [], thumbs: []
    }
  }

  function parse(path, text) {
    var out = scanner.blank(path)
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (!line) continue
      var f = line.split("\t")
      switch (f[0]) {
      case "ERR":
        out.error = f[1] || "unknown"
        break
      case "STAT":
        var s = String(f[1] || "").split("|")
        out.mode = s[0] || ""
        out.owner = s[1] || ""
        out.group = s[2] || ""
        out.mtime = parseInt(s[3], 10) || 0
        break
      case "TOP":
        out.topFiles = parseInt(f[1], 10) || 0
        out.topDirs = parseInt(f[2], 10) || 0
        out.ok = true
        break
      case "RECENT":
        out.recent.push({
          mtime: parseFloat(f[1]) || 0,
          isDir: f[2] === "d",
          size: parseInt(f[3], 10) || 0,
          // A name may legitimately contain a tab; the name is the last
          // field, so anything split off it gets joined back on.
          name: f.slice(4).join("\t")
        })
        break
      case "DEEP":
        out.files = parseInt(f[1], 10) || 0
        out.dirs = parseInt(f[2], 10) || 0
        out.bytes = parseInt(f[3], 10) || 0
        break
      case "CAT":
        out.categories.push({
          key: f[1] || "other",
          count: parseInt(f[2], 10) || 0,
          bytes: parseInt(f[3], 10) || 0
        })
        break
      case "THUMB":
        out.thumbs.push(f.slice(1).join("\t"))
        break
      case "PARTIAL":
        out.partial = true
        break
      }
    }
    out.categories.sort(function (a, b) { return b.count - a.count })
    return out
  }

  function store(path, text) {
    var next = ({})
    for (var k in scanner.results) next[k] = scanner.results[k]
    next[path] = scanner.parse(path, text)
    scanner.results = next
    scanner.revision++
    scanner.scanned(path)
  }

  Process {
    id: proc
    // `find` and `du` on a foreign locale sort differently and print
    // differently; C is the only one whose output the parser was written for.
    environment: ({ "LC_ALL": "C" })
    stdout: StdioCollector {
      id: collector
      waitForEnd: true
      onStreamFinished: {
        watchdog.stop()
        var path = scanner.active
        scanner.active = ""
        if (path) scanner.store(path, collector.text)
        scanner.pump()
      }
    }
  }

  // The failure this guards against is a scan that never produces a stream at
  // all — bash missing, the script gone. `exited` looks like the obvious hook
  // and is the wrong one: it can arrive before the collector has finished,
  // and a scanner that finalises there records a failure for a folder whose
  // output is about to land, then drops that output because the slot it
  // belonged to has already been cleared. That is what left folders on the
  // shelf with no numbers under them. A watchdog only ever fires when nothing
  // arrived, which is the case actually worth handling.
  Timer {
    id: watchdog
    interval: (scanner.timeoutSeconds + 8) * 1000
    repeat: false
    onTriggered: {
      if (!scanner.active) return
      var path = scanner.active
      scanner.active = ""
      proc.running = false
      scanner.store(path, "ERR\tfailed")
      scanner.pump()
    }
  }

  onDeepChanged: scanner.invalidate()
  onThumbnailsChanged: scanner.invalidate()
  onRecentsChanged: scanner.invalidate()

  Component.onDestruction: {
    scanner.pending = []
    watchdog.stop()
    proc.running = false
  }
}
