.pragma library

// Editing for a TextInput that is permanently read-only to Qt.
//
// Qt reads the clipboard by itself, on the shell's thread and without a limit,
// whenever a writable TextInput exists and the clipboard changes (it asks
// whether it could paste). The only way to stop that is for the field never to
// be writable, so the fields here are `readOnly` and the keys that would edit
// them are handled below instead, by setting `text` and `cursorPosition`
// directly. Cursor movement, selection, mouse selection and copy stay native;
// they do not read the clipboard. Paste goes to the bounded helper.

function selRange(field) {
  var s = Math.min(field.selectionStart, field.selectionEnd)
  var e = Math.max(field.selectionStart, field.selectionEnd)
  if (s === e) { s = field.cursorPosition; e = s }
  return [s, e]
}

function splice(field, s, e, ins) {
  var t = String(field.text)
  var room = field.maximumLength - (t.length - (e - s))
  if (ins.length > room) ins = ins.slice(0, Math.max(0, room))
  if (e === s && ins.length === 0) return false
  field.text = t.slice(0, s) + ins + t.slice(e)
  field.cursorPosition = s + ins.length
  return true
}

function replaceSelection(field, ins) {
  var r = selRange(field)
  return splice(field, r[0], r[1], String(ins))
}

function wordStart(t, pos) {
  var i = pos
  while (i > 0 && /\s/.test(t.charAt(i - 1))) i--
  while (i > 0 && !/\s/.test(t.charAt(i - 1))) i--
  return i
}

function wordEnd(t, pos) {
  var i = pos
  while (i < t.length && /\s/.test(t.charAt(i))) i++
  while (i < t.length && !/\s/.test(t.charAt(i))) i++
  return i
}

// True when the key was an editing key and has been dealt with.
function apply(event, field, requestPaste) {
  var ctrl = (event.modifiers & 0x04000000) !== 0   // Qt.ControlModifier
  var alt = (event.modifiers & 0x08000000) !== 0    // Qt.AltModifier
  var meta = (event.modifiers & 0x10000000) !== 0   // Qt.MetaModifier
  var shift = (event.modifiers & 0x02000000) !== 0  // Qt.ShiftModifier
  var key = event.key
  var r = selRange(field)
  var t = String(field.text)

  if ((ctrl && key === 0x56) || (shift && key === 0x01000006)) {   // V, Insert
    event.accepted = true
    requestPaste()
    return true
  }
  if (ctrl && key === 0x58) {                                      // X
    event.accepted = true
    if (r[0] !== r[1]) { field.select(r[0], r[1]); field.copy(); splice(field, r[0], r[1], "") }
    return true
  }
  if (key === 0x01000003) {                                        // Backspace
    event.accepted = true
    if (r[0] !== r[1]) splice(field, r[0], r[1], "")
    else splice(field, ctrl ? wordStart(t, r[0]) : Math.max(0, r[0] - 1), r[0], "")
    return true
  }
  if (key === 0x01000007) {                                        // Delete
    event.accepted = true
    if (r[0] !== r[1]) splice(field, r[0], r[1], "")
    else splice(field, r[0], ctrl ? wordEnd(t, r[0]) : Math.min(t.length, r[0] + 1), "")
    return true
  }
  if (key === 0x01000004 || key === 0x01000005) {                  // Return, Enter
    event.accepted = true
    field.accepted()
    return true
  }
  var text = String(event.text || "")
  if (text.length > 0 && !ctrl && !alt && !meta) {
    var c = text.charCodeAt(0)
    if (c >= 32 && c !== 127) {
      event.accepted = true
      replaceSelection(field, text)
      return true
    }
  }
  return false
}
