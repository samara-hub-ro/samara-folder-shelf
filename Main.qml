import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Store.js" as Store

// The shelf's service half: it owns the document, the scanner and the window,
// and it outlives the bar widget that toggles it.
//
// A desktop widget has to be a `service` rather than a `panel` — panels are
// loaded when they are summoned and unloaded after, and a shelf that only
// exists while you are looking at it is not a shelf. `keepLoaded` in the
// manifest is what keeps this instance alive across the shell's own churn.
Item {
  id: shelfService

  // Injected by the shell host.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string home: Quickshell.env("HOME")

  // Pushed in by the bar widget, which is where the shell puts a plugin's
  // settings. With no widget on the bar the shelf still runs — on the
  // manifest defaults, which is the documented state rather than an accident.
  property var settings: ({})
  function setting(name, fallback) {
    var v = shelfService.settings ? shelfService.settings[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  readonly property string configPath: {
    var custom = String(shelfService.setting("configPath", "") || "").trim()
    if (custom.length > 0) return custom.replace(/^~(?=\/|$)/, shelfService.home)
    return shelfService.home + "/.config/omarchy/folder-shelf.json"
  }

  // The plugin's own directory, recovered from a resolved URL because a
  // plugin is not told where it was installed.
  readonly property string scriptPath: {
    var url = String(Qt.resolvedUrl("scan.sh"))
    return decodeURIComponent(url.replace(/^file:\/\//, ""))
  }

  // ------------------------------------------------------------- document

  property var doc: Store.normalize(null)
  property bool documentLoaded: false
  property bool saving: false
  property bool seedAttempted: false

  readonly property var folders: doc.folders
  readonly property bool empty: doc.folders.length === 0

  function commit(next) {
    shelfService.doc = next
    shelfService.saving = true
    saveGuard.restart()
    configFile.setText(Store.serialize(next))
  }

  function cloneDoc() {
    return {
      version: Store.VERSION,
      folders: shelfService.doc.folders.map(function (f) {
        return { path: f.path, label: f.label, icon: f.icon, accent: f.accent }
      }),
      window: {
        x: shelfService.doc.window.x, y: shelfService.doc.window.y,
        width: shelfService.doc.window.width, height: shelfService.doc.window.height,
        screen: shelfService.doc.window.screen, visible: shelfService.doc.window.visible,
        raised: shelfService.doc.window.raised
      }
    }
  }

  function addFolder(path) {
    var p = String(path || "").replace(/\/+$/, "")
    if (!p || p.charAt(0) !== "/") return false
    var next = shelfService.cloneDoc()
    if (Store.indexOfPath(next.folders, p) !== -1) return false
    next.folders.push({ path: p, label: "", icon: "", accent: "" })
    shelfService.commit(next)
    shelfScanner.request(p, true)
    return true
  }

  function removeFolder(path) {
    var next = shelfService.cloneDoc()
    var i = Store.indexOfPath(next.folders, path)
    if (i === -1) return
    next.folders.splice(i, 1)
    shelfService.commit(next)
    shelfScanner.forget(path)
  }

  function renameFolder(path, label) {
    var next = shelfService.cloneDoc()
    var i = Store.indexOfPath(next.folders, path)
    if (i === -1) return
    next.folders[i].label = String(label || "").slice(0, 60)
    shelfService.commit(next)
  }

  function moveFolder(from, to) {
    if (from === to || from < 0 || to < 0) return
    var next = shelfService.cloneDoc()
    if (from >= next.folders.length || to >= next.folders.length) return
    var item = next.folders.splice(from, 1)[0]
    next.folders.splice(to, 0, item)
    shelfService.commit(next)
  }

  // Geometry is saved on the same document as the folders, but it changes on
  // every frame of a drag, so it goes through the same debounce and never
  // touches the disk mid-gesture.
  function saveGeometry(x, y, w, h, screenName) {
    var next = shelfService.cloneDoc()
    next.window.x = Math.round(x)
    next.window.y = Math.round(y)
    next.window.width = Math.round(w)
    next.window.height = Math.round(h)
    if (screenName) next.window.screen = String(screenName)
    shelfService.commit(next)
  }

  // ------------------------------------------------------------ visibility

  readonly property bool shelfVisible: doc.window.visible
  readonly property bool raised: doc.window.raised

  function setVisible(on) {
    if (shelfService.doc.window.visible === !!on) return
    var next = shelfService.cloneDoc()
    next.window.visible = !!on
    shelfService.commit(next)
  }

  function setRaised(on) {
    if (shelfService.doc.window.raised === !!on) return
    var next = shelfService.cloneDoc()
    next.window.raised = !!on
    shelfService.commit(next)
  }

  function toggle() { shelfService.setVisible(!shelfService.shelfVisible) }
  function toggleRaised() { shelfService.setRaised(!shelfService.raised) }

  // ---------------------------------------------------------------- launch

  // xdg-open is the whole point of "the file manager you set as default": it
  // reads the same association the desktop does, so the shelf never has an
  // opinion about which file manager you run.
  function openFolder(path) {
    if (!path) return
    Util.execArgv(["xdg-open", String(path)])
  }

  function openTerminal(path) {
    if (!path) return
    // xdg-terminal-exec is how Omarchy itself opens a terminal somewhere; it
    // honours ~/.config/xdg-terminals.list, which is what `omarchy default
    // terminal` writes.
    Util.execArgv(["xdg-terminal-exec", "--dir=" + String(path)])
  }

  function copyPath(path) {
    Quickshell.clipboardText = String(path || "")
  }

  // ------------------------------------------------------------------ wiring

  Scanner {
    id: shelfScanner
    scriptPath: shelfService.scriptPath
    deep: shelfService.setting("deepStats", true) === true
    timeoutSeconds: Math.max(2, Math.min(60, Number(shelfService.setting("scanTimeout", 12)) || 12))
    thumbnails: Math.max(0, Math.min(8, Number(shelfService.setting("thumbnailCount", 4)) || 0))
    recents: Math.max(0, Math.min(12, Number(shelfService.setting("recentCount", 6)) || 0))
  }

  FileView {
    id: configFile
    path: shelfService.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    blockAllReads: true
    onFileChanged: if (!shelfService.saving) configReader.reload()
  }

  BoundedFile {
    id: configReader
    path: shelfService.configPath
    limit: 262144
    printErrors: true
    onLoaded: function (text) {
      var parsed = null
      try { parsed = JSON.parse(text) } catch (e) { parsed = null }
      if (parsed === null && String(text).trim().length > 0) {
        console.warn("folder-shelf: " + shelfService.configPath + " is not valid JSON; leaving it alone")
        shelfService.documentLoaded = true
        return
      }
      shelfService.doc = Store.normalize(parsed)
      shelfService.documentLoaded = true
      shelfService.ensureSeeded()
      shelfService.refreshAll()
    }
    onFailed: function (reason) {
      shelfService.documentLoaded = true
      if (reason === "missing") shelfService.ensureSeeded()
    }
  }

  // The guard exists because our own atomic write fires the same watcher a
  // foreign edit does. Without it every save reloads the file we just wrote
  // and fights whatever the user is dragging.
  Timer {
    id: saveGuard
    interval: 700
    repeat: false
    onTriggered: shelfService.saving = false
  }

  // ------------------------------------------------------------------ seed

  function ensureSeeded() {
    if (shelfService.seedAttempted) return
    if (!shelfService.documentLoaded || !shelfService.empty) return
    if (shelfService.setting("seedOnFirstRun", true) !== true) return
    shelfService.seedAttempted = true
    seedProbe.command = ["bash", "-c",
                         'for p in "$@"; do [ -d "$p" ] && printf "%s\\n" "$p"; done',
                         "bash"].concat(Store.seedCandidates(shelfService.home))
    seedProbe.running = true
  }

  Process {
    id: seedProbe
    environment: ({ "LC_ALL": "C" })
    stdout: StdioCollector {
      id: seedOut
      waitForEnd: true
      onStreamFinished: {
        var found = String(seedOut.text || "").split("\n").filter(function (l) { return l.length > 0 })
        if (found.length === 0) return
        var next = shelfService.cloneDoc()
        for (var i = 0; i < found.length; i++) {
          if (Store.indexOfPath(next.folders, found[i]) === -1)
            next.folders.push({ path: found[i], label: "", icon: "", accent: "" })
        }
        shelfService.commit(next)
        shelfService.refreshAll()
      }
    }
  }

  // A quiet pass over the shelf so the tiles carry numbers before anyone
  // hovers anything. Scans are stacked, so a hover still jumps the queue.
  function refreshAll() {
    for (var i = 0; i < shelfService.doc.folders.length; i++)
      shelfScanner.request(shelfService.doc.folders[i].path, false)
  }

  Timer {
    interval: 5 * 60 * 1000
    repeat: true
    running: true
    onTriggered: shelfService.refreshAll()
  }

  // ----------------------------------------------------------- the surface

  // One window per screen, but only the screen the shelf was left on draws
  // it. Variants is what survives a monitor being unplugged: the delegate for
  // that screen goes away instead of the shelf ending up at a coordinate that
  // no longer exists.
  Variants {
    model: Quickshell.screens

    ShelfWindow {
      required property var modelData
      targetScreen: modelData
      service: shelfService
      scanner: shelfScanner
    }
  }

  // Lets a keybinding reach the shelf:
  //   qs -c omarchy ipc call folderShelf toggle
  IpcHandler {
    target: "folderShelf"
    function toggle(): void { shelfService.toggle() }
    function show(): void { shelfService.setVisible(true) }
    function hide(): void { shelfService.setVisible(false) }
    function raise(): void { shelfService.setRaised(true) }
    function lower(): void { shelfService.setRaised(false) }
    function refresh(): void { shelfScanner.invalidate(); shelfService.refreshAll() }
  }
}
