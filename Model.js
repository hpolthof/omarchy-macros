// Pure helpers shared by the bar widget and its panel: reading what
// bin/macros emits, and the strings both sides render.

var GLYPH = {
  keyboard: "󰌌",
  record: "󰑊",
  stop: "󰓛",
  play: "󰐊",
  save: "󰆓",
  discard: "󰅖",
  rename: "󰑕",
  shortcut: "󰌋",
  fast: "󰓅",
  real: "󰔛",
  trash: "󰆴",
  warn: "󰀪"
}

// Every command that the panel reads answers in JSON on stdout. A command
// that failed says so on stderr and exits non-zero, so a parse failure here
// is a bug rather than an expected path.
function parse(text, fallback) {
  try {
    var value = JSON.parse(String(text || ""))
    return value === null ? fallback : value
  } catch (e) {
    return fallback
  }
}

// stderr from a failed command, trimmed to the one line worth showing.
function clean(text) {
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() !== "") return lines[i].trim()
  }
  return ""
}

function pad(n) {
  return n < 10 ? "0" + n : String(n)
}

function clock(seconds) {
  var s = Math.max(0, Math.floor(seconds))
  return Math.floor(s / 60) + ":" + pad(s % 60)
}

// Macro lengths are short enough that seconds with one decimal say more than
// a rounded count of whole seconds.
function duration(ms) {
  var seconds = Math.max(0, ms) / 1000
  if (seconds < 10) return seconds.toFixed(1) + "s"
  return clock(seconds)
}

function keyCount(n) {
  return n === 1 ? "1 key" : n + " keys"
}

// Size and timing only. The shortcut has a field of its own on the row, and
// saying it twice made the row read as two competing lines of detail.
function rowDetail(row) {
  return [keyCount(row.keys), duration(row.durationMs),
          row.speed === "real" ? "recorded timing" : "fast"].join("  ·  ")
}

// What the bar's tooltip says. The widget has one glyph to work with, so the
// tooltip carries the state that the glyph can only hint at.
function tooltip(state, rows, problems) {
  if (problems && problems.length > 0) return problems[0]
  // The key that starts and stops a recording belongs in the tooltip too:
  // it is the one thing you want to know without opening the panel first.
  var key = state.recordShortcut || ""
  if (state.recording)
    return "Recording — " + clock(state.seconds) + ", " + keyCount(state.keys)
           + "\n" + (key ? key + " or click to stop" : "Click to stop")
  if (state.pending)
    return "Recorded " + keyCount(state.pendingKeys) + ", not saved yet"
           + "\nClick to name it"
  var line
  if (!rows || rows.length === 0) {
    line = "Macros — nothing recorded yet"
  } else {
    var withKeys = 0
    for (var i = 0; i < rows.length; i++) if (rows[i].shortcut) withKeys++
    line = rows.length === 1 ? "1 macro" : rows.length + " macros"
    if (withKeys > 0) line += ", " + withKeys + " with a shortcut"
  }
  return key ? line + "\n" + key + " to record" : line
}

// ------------------------------------------------------------- shortcuts

var MOD_ORDER = ["SUPER", "CTRL", "ALT", "SHIFT"]

// Qt hands back a key code and a modifier mask; Hyprland wants names. Only
// the keys that Hyprland names the same way are accepted, so a capture can
// never produce a binding that silently fails to load.
var NAMED_KEYS = {
  0x01000000: "Escape",
  0x01000001: "Tab",
  0x01000004: "Return",
  0x01000005: "Return",
  0x01000006: "Insert",
  0x01000007: "Delete",
  0x01000010: "Home",
  0x01000011: "End",
  0x01000012: "Left",
  0x01000013: "Up",
  0x01000014: "Right",
  0x01000015: "Down",
  0x01000016: "Prior",
  0x01000017: "Next",
  0x01000003: "BackSpace",
  0x20: "space",
  0x2c: "comma",
  0x2e: "period",
  0x2f: "slash",
  0x3b: "semicolon",
  0x27: "apostrophe",
  0x2d: "minus",
  0x3d: "equal",
  0x5b: "bracketleft",
  0x5d: "bracketright",
  0x5c: "backslash",
  0x60: "grave"
}

// The modifiers themselves, which are a prefix and never the key.
function isModifierKey(code) {
  return code === 0x01000020 || code === 0x01000021 || code === 0x01000022
      || code === 0x01000023 || code === 0x01000024 || code === 0x01000025
      || code === 0x01001103
}

function keyName(code) {
  if (code >= 0x41 && code <= 0x5a) return String.fromCharCode(code)
  if (code >= 0x30 && code <= 0x39) return String.fromCharCode(code)
  if (code >= 0x01000030 && code <= 0x0100003b)
    return "F" + (code - 0x01000030 + 1)
  return NAMED_KEYS[code] || ""
}

// SUPER on its own is a valid Hyprland binding, but a macro bound to a bare
// letter would fire while typing, so at least one modifier is required.
function shortcutFrom(code, modifiers) {
  var name = keyName(code)
  if (name === "") return ""
  var mods = []
  if (modifiers & 0x10000000) mods.push("SUPER")
  if (modifiers & 0x04000000) mods.push("CTRL")
  if (modifiers & 0x08000000) mods.push("ALT")
  if (modifiers & 0x02000000) mods.push("SHIFT")
  if (mods.length === 0) return ""
  mods.sort(function(a, b) {
    return MOD_ORDER.indexOf(a) - MOD_ORDER.indexOf(b)
  })
  return mods.join(" + ") + " + " + name
}
