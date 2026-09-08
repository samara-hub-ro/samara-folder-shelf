.pragma library

// Presentation helpers shared by the shelf and its preview card. Kept out of
// QML so the same rounding shows up in a tile, a row and a tooltip.

// The categories a scanned file can fall into. The order here is the order
// they are drawn in the composition bar, and `hue` is an offset applied to the
// theme accent rather than a fixed colour — the bar has to survive a theme
// change without turning into someone else's palette.
var CATEGORIES = [
  { key: "image",   label: "Images",    hue:   0 },
  { key: "video",   label: "Video",     hue:  38 },
  { key: "audio",   label: "Audio",     hue:  76 },
  { key: "doc",     label: "Documents", hue: 152 },
  { key: "code",    label: "Code",      hue: 208 },
  { key: "archive", label: "Archives",  hue: 268 },
  { key: "other",   label: "Other",     hue: 310 }
]

function categoryLabel(key) {
  for (var i = 0; i < CATEGORIES.length; i++)
    if (CATEGORIES[i].key === key) return CATEGORIES[i].label
  return "Other"
}

// Binary units, because this is a disk figure and every file manager on the
// machine reports the same folder the same way.
function bytes(n) {
  var v = Number(n)
  if (!isFinite(v) || v < 0) return "—"
  if (v < 1024) return v + " B"
  var units = ["KB", "MB", "GB", "TB", "PB"]
  var i = -1
  do { v /= 1024; i++ } while (v >= 1024 && i < units.length - 1)
  return (v >= 100 ? Math.round(v) : v.toFixed(v >= 10 ? 1 : 2)) + " " + units[i]
}

function count(n) {
  var v = Number(n)
  if (!isFinite(v) || v < 0) return "—"
  if (v < 1000) return String(v)
  if (v < 1000000) return (v / 1000).toFixed(v < 10000 ? 1 : 0) + "k"
  return (v / 1000000).toFixed(1) + "M"
}

// Relative for anything inside a year, absolute past that: "3 days ago" stops
// being useful long before "2024-11-02" starts being ambiguous.
function since(epochSeconds) {
  var t = Number(epochSeconds)
  if (!isFinite(t) || t <= 0) return "—"
  var d = Math.floor(Date.now() / 1000) - Math.floor(t)
  if (d < 0) d = 0
  if (d < 60) return "just now"
  if (d < 3600) { var m = Math.floor(d / 60); return m + (m === 1 ? " minute ago" : " minutes ago") }
  if (d < 86400) { var h = Math.floor(d / 3600); return h + (h === 1 ? " hour ago" : " hours ago") }
  if (d < 604800) { var dd = Math.floor(d / 86400); return dd + (dd === 1 ? " day ago" : " days ago") }
  if (d < 2629800) { var w = Math.floor(d / 604800); return w + (w === 1 ? " week ago" : " weeks ago") }
  if (d < 31557600) { var mo = Math.floor(d / 2629800); return mo + (mo === 1 ? " month ago" : " months ago") }
  var date = new Date(t * 1000)
  return Qt.formatDateTime(date, "yyyy-MM-dd")
}

function baseName(path) {
  var p = String(path || "").replace(/\/+$/, "")
  var i = p.lastIndexOf("/")
  return i < 0 ? p : p.slice(i + 1)
}

// `~` for the home prefix, and an ellipsis in the middle for anything still
// too long — the head and the tail are the parts that identify a path.
function prettyPath(path, home, maxLength) {
  var p = String(path || "")
  if (home && p.indexOf(home + "/") === 0) p = "~" + p.slice(home.length)
  else if (home && p === home) p = "~"
  var max = maxLength || 44
  if (p.length <= max) return p
  var keepTail = Math.floor((max - 1) / 2)
  var keepHead = max - 1 - keepTail
  return p.slice(0, keepHead) + "…" + p.slice(p.length - keepTail)
}

// stat's `%A` is what `ls -l` prints. Splitting it into the three triads is
// what makes it readable at a glance in the preview.
function permissionTriads(mode) {
  var m = String(mode || "")
  if (m.length < 10) return null
  return { user: m.slice(1, 4), group: m.slice(4, 7), other: m.slice(7, 10) }
}

function permissionOctal(mode) {
  var t = permissionTriads(mode)
  if (!t) return ""
  function digit(triad) {
    var n = 0
    if (triad[0] === "r") n += 4
    if (triad[1] === "w") n += 2
    if (triad[2] === "x" || triad[2] === "s" || triad[2] === "t") n += 1
    return n
  }
  return String(digit(t.user)) + digit(t.group) + digit(t.other)
}
