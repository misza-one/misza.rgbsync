// Persisted configuration normalization and serialization.
// Mirrors the ConfigStore.js pattern from misza.hass.

var KEYS = [
  "enabled", "devices", "deviceModes", "deviceZones", "intensity",
  "brightness", "refreshInterval",
  "lcdEnabled", "lcdBrightness", "lcdWallpaper", "lcdDim", "lcdThemeName",
  "lcdTitle", "lcdTop", "lcdBottom",
  "lcdZoom", "lcdPanX", "lcdPanY", "lcdPet", "lcdPetPath",
  "lcdPetFavorites", "lcdPetScale", "lcdPetX", "lcdPetY",
  "lcdPetReactToOmaherd", "liquidctlBinary"
]

function stringList(value, fallback) {
  if (!Array.isArray(value)) return fallback.slice()
  var out = []
  var seen = {}
  for (var i = 0; i < value.length; i++) {
    if (typeof value[i] === "string" && value[i].length >= 3
        && value[i].length <= 64 && !seen[value[i]]) {
      seen[value[i]] = true
      out.push(value[i])
    }
  }
  return out
}

// Substring -> mode name, e.g. { "RTX 4090": "Direct" }.
function stringMap(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {}
  var out = {}
  for (var key in value) {
    if (key === "__proto__" || key === "constructor" || key === "prototype") continue
    if (key.length < 3 || key.length > 64) continue
    if (typeof value[key] === "string" && value[key].length > 0
        && value[key].length <= 32) out[key] = value[key]
  }
  return out
}

// Substring -> zone index, e.g. { "RTX 4090": 0 }.
function zoneMap(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {}
  var out = {}
  for (var key in value) {
    if (key === "__proto__" || key === "constructor" || key === "prototype") continue
    if (key.length < 3 || key.length > 64) continue
    var zone = Number(value[key])
    if (isFinite(zone) && Math.floor(zone) === zone && zone >= 0 && zone <= 16) {
      out[key] = zone
    }
  }
  return out
}

function clampNumber(value, low, high) {
  return Math.min(Math.max(value, low), high)
}

function percent(value, fallback) {
  var number = Number(value)
  if (!isFinite(number)) return fallback
  return Math.round(clampNumber(number, 0, 100))
}

// Theme name -> { intensity }. Same key rules as misza.hass so both plugins
// accept the same theme.name values.
function intensityMap(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {}
  var out = {}
  for (var key in value) {
    if (key === "__proto__" || key === "constructor" || key === "prototype") continue
    if (!/^[A-Za-z0-9_.-]+$/.test(key)) continue
    var raw = value[key]
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue
    var intensity = Number(raw.intensity)
    if (!isFinite(intensity)) continue
    out[key] = {
      intensity: Math.round(clampNumber(intensity, 0, 100) * 100) / 100
    }
  }
  return out
}

function seconds(value, fallback) {
  var number = Number(value)
  if (!isFinite(number)) return fallback
  return Math.round(clampNumber(number, 0, 3600))
}

function fraction(value, fallback) {
  var number = Number(value)
  if (!isFinite(number)) return fallback
  return Math.round(clampNumber(number, 0.1, 1) * 100) / 100
}

function zoomFactor(value, fallback) {
  var number = Number(value)
  if (!isFinite(number)) return fallback
  return Math.round(clampNumber(number, 1, 3) * 100) / 100
}

function panCoord(value) {
  var number = Number(value)
  if (!isFinite(number)) return 0
  return Math.round(clampNumber(number, -2000, 2000))
}

function petScale(value, fallback) {
  var number = Number(value)
  if (!isFinite(number)) return fallback
  return Math.round(clampNumber(number, 0.5, 2.5) * 100) / 100
}

function petWalkX(value) {
  var number = Number(value)
  if (!isFinite(number)) return 0
  return Math.round(clampNumber(number, -220, 220))
}

function petWalkY(value, fallback) {
  var number = Number(value)
  if (!isFinite(number)) return fallback
  return Math.round(clampNumber(number, 360, 600))
}

function petPath(value) {
  if (typeof value !== "string") return ""
  var path = value.trim()
  if (path.length > 1024 || path.charAt(0) !== "/") return ""
  if (!/\.(png|webp|jpe?g)$/i.test(path)) return ""
  return path
}

function petPathList(value) {
  if (!Array.isArray(value)) return []
  var out = []
  var seen = {}
  for (var i = 0; i < value.length && out.length < 32; i++) {
    var path = petPath(value[i])
    if (path && !seen[path]) {
      seen[path] = true
      out.push(path)
    }
  }
  return out
}

// Single-line LCD text: no newlines/tabs, trimmed, capped. Placeholders
// ({theme} {liquid} {pump} {fan}) survive untouched for the renderer.
function lcdText(value) {
  if (typeof value !== "string") return ""
  return value.replace(/[\r\n\t]+/g, " ").trim().slice(0, 40)
}

function parse(text) {
  var raw = {}
  var error = ""
  try {
    raw = text ? JSON.parse(text) : {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      raw = {}
      error = "config.json must contain a JSON object"
    }
  } catch (exception) {
    raw = {}
    error = "config.json is not valid JSON"
  }

  return {
    error: error,
    config: {
      enabled: raw.enabled === true,
      // Substrings matched against OpenRGB device names. Empty = all
      // detected devices. openrgb -d needs 3+ characters per term.
      devices: stringList(raw.devices, []),
      deviceModes: stringMap(raw.deviceModes),
      deviceZones: zoneMap(raw.deviceZones),
      intensity: intensityMap(raw.intensity),
      brightness: percent(raw.brightness, 100),
      refreshInterval: seconds(raw.refreshInterval, 30),
      lcdEnabled: raw.lcdEnabled === true,
      lcdBrightness: percent(raw.lcdBrightness, 60),
      lcdWallpaper: raw.lcdWallpaper !== false,
      lcdDim: fraction(raw.lcdDim, 0.5),
      lcdThemeName: raw.lcdThemeName !== false,
      lcdTitle: lcdText(raw.lcdTitle),
      lcdTop: lcdText(raw.lcdTop),
      lcdBottom: lcdText(raw.lcdBottom),
      lcdZoom: zoomFactor(raw.lcdZoom, 1),
      lcdPanX: panCoord(raw.lcdPanX),
      lcdPanY: panCoord(raw.lcdPanY),
      lcdPet: raw.lcdPet === true,
      lcdPetPath: petPath(raw.lcdPetPath),
      lcdPetFavorites: petPathList(raw.lcdPetFavorites),
      lcdPetScale: petScale(raw.lcdPetScale, 1),
      lcdPetX: petWalkX(raw.lcdPetX),
      lcdPetY: petWalkY(raw.lcdPetY, 510),
      lcdPetReactToOmaherd: raw.lcdPetReactToOmaherd !== false,
      liquidctlBinary: typeof raw.liquidctlBinary === "string"
        && raw.liquidctlBinary.length > 0
        && raw.liquidctlBinary.length <= 128
        ? raw.liquidctlBinary : "liquidctl"
    }
  }
}

function merge(current, patch) {
  var result = {}
  for (var i = 0; i < KEYS.length; i++) {
    var key = KEYS[i]
    result[key] = current[key]
  }
  for (var p = 0; p < KEYS.length; p++) {
    var patchKey = KEYS[p]
    if (Object.prototype.hasOwnProperty.call(patch || {}, patchKey)) {
      result[patchKey] = patch[patchKey]
    }
  }
  return result
}

function serialize(config) {
  return JSON.stringify(config, null, 2) + "\n"
}
