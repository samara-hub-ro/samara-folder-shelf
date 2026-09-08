.pragma library

// Category colours are derived from the theme accent rather than fixed, so a
// theme change moves them together instead of leaving a rainbow from someone
// else's palette sitting on a monochrome desktop. Each category is a fixed
// rotation away from the accent's own hue; a greyscale accent has no hue to
// rotate, so it borrows a floor of saturation and the rotations still spread
// the categories apart.
function categoryColor(accent, hueOffset, alpha) {
  var h = accent.hslHue
  if (!isFinite(h) || h < 0) h = 0.58
  var s = Math.max(0.42, accent.hslSaturation)
  var l = Math.min(0.68, Math.max(0.46, accent.hslLightness))
  var hue = (h + hueOffset / 360.0) % 1.0
  if (hue < 0) hue += 1.0
  return Qt.hsla(hue, s, l, alpha === undefined ? 1.0 : alpha)
}

function withAlpha(c, a) {
  return Qt.rgba(c.r, c.g, c.b, a)
}
