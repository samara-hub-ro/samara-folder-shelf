.pragma library

// The shelf file: the folders you put on the shelf, and where the shelf sits.
// Both live in one document because they are one thing to back up and one
// thing to hand to another machine.
//
// Everything in here is defensive. The file is meant to be hand-editable, so
// a missing key, a stray null or a hand-typed string where a number belongs
// has to degrade to a default rather than take the widget down with it.

var VERSION = 1

function defaultWindow() {
  return { x: 120, y: 120, width: 460, height: 340, screen: "", visible: true, raised: false }
}

// Anything that came out of the file and is going to be drawn. The file is
// meant to be hand-edited and is also written by us, so a control character
// in a label is either a typo or a paste accident — but a newline in a label
// still changes the height of a tile, and a name is not a place that needs
// them.
function clean(value, limit) {
  if (typeof value !== "string") return ""
  return value.replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, limit)
}

function normalizeFolder(entry) {
  if (!entry) return null
  var path = ""
  if (typeof entry === "string") path = entry
  else if (typeof entry === "object" && typeof entry.path === "string") path = entry.path
  path = path.replace(/\/+$/, "")
  if (!path || path.charAt(0) !== "/") return null
  var o = (typeof entry === "object" && entry) ? entry : {}
  return {
    path: path,
    label: clean(o.label, 60),
    icon: clean(o.icon, 8),
    accent: clean(o.accent, 32)
  }
}

function normalize(raw) {
  var doc = (raw && typeof raw === "object") ? raw : {}
  var out = { version: VERSION, folders: [], window: defaultWindow() }

  var list = Array.isArray(doc.folders) ? doc.folders : []
  var seen = ({})
  for (var i = 0; i < list.length; i++) {
    var f = normalizeFolder(list[i])
    if (!f || seen[f.path]) continue
    seen[f.path] = true
    out.folders.push(f)
  }

  var w = (doc.window && typeof doc.window === "object") ? doc.window : {}
  var d = out.window
  d.x = num(w.x, d.x, -20000, 20000)
  d.y = num(w.y, d.y, -20000, 20000)
  d.width = num(w.width, d.width, 220, 4000)
  d.height = num(w.height, d.height, 140, 4000)
  d.screen = typeof w.screen === "string" ? w.screen : ""
  d.visible = w.visible === undefined ? true : !!w.visible
  d.raised = !!w.raised
  return out
}

function num(value, fallback, min, max) {
  var n = Number(value)
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, Math.round(n)))
}

function serialize(doc) {
  return JSON.stringify({
    version: VERSION,
    folders: doc.folders.map(function (f) {
      var o = { path: f.path }
      if (f.label) o.label = f.label
      if (f.icon) o.icon = f.icon
      if (f.accent) o.accent = f.accent
      return o
    }),
    window: doc.window
  }, null, 2) + "\n"
}

function indexOfPath(folders, path) {
  var p = String(path || "").replace(/\/+$/, "")
  for (var i = 0; i < folders.length; i++) if (folders[i].path === p) return i
  return -1
}

// The label a folder shows when its owner has not renamed it.
function displayName(folder, home) {
  if (folder.label) return folder.label
  var p = folder.path
  if (home && p === home) return "Home"
  var i = p.lastIndexOf("/")
  var name = i < 0 ? p : p.slice(i + 1)
  return name || "/"
}

// Candidates for the first run. Only the ones that exist are offered; the
// caller filters against the filesystem, this just names the shortlist in the
// order they should land on the shelf.
function seedCandidates(home) {
  var h = String(home || "")
  return [
    h + "/Downloads",
    h + "/Documents",
    h + "/Pictures",
    h + "/Videos",
    h + "/Music",
    h + "/Desktop",
    h + "/Projects",
    h + "/Work"
  ]
}
