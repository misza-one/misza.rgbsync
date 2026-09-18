// Colour math for theme sync. Ported from misza.hass Model.js so both
// plugins mean the same thing by "intensity": hue comes from the Omarchy
// accent, saturation is the per-theme intensity, value stays at full.

function clampNumber(value, low, high) {
  return Math.min(Math.max(value, low), high)
}

function rgbToHs(rgb) {
  var red = clampNumber(rgb[0], 0, 255) / 255
  var green = clampNumber(rgb[1], 0, 255) / 255
  var blue = clampNumber(rgb[2], 0, 255) / 255
  var high = Math.max(red, green, blue)
  var low = Math.min(red, green, blue)
  var delta = high - low

  var hue = 0
  if (delta > 0) {
    if (high === red) hue = 60 * (((green - blue) / delta) % 6)
    else if (high === green) hue = 60 * ((blue - red) / delta + 2)
    else hue = 60 * ((red - green) / delta + 4)
  }
  if (hue < 0) hue += 360

  return {
    hue: Math.round(hue * 100) / 100,
    saturation: Math.round((high === 0 ? 0 : delta / high) * 10000) / 100
  }
}

function hsToRgb(hue, saturation) {
  var h = (((hue % 360) + 360) % 360) / 60
  var s = clampNumber(saturation, 0, 100) / 100
  var chroma = s
  var second = chroma * (1 - Math.abs((h % 2) - 1))
  var rgb = [0, 0, 0]
  if (h < 1) rgb = [chroma, second, 0]
  else if (h < 2) rgb = [second, chroma, 0]
  else if (h < 3) rgb = [0, chroma, second]
  else if (h < 4) rgb = [0, second, chroma]
  else if (h < 5) rgb = [second, 0, chroma]
  else rgb = [chroma, 0, second]
  var offset = 1 - chroma
  return [
    Math.round((rgb[0] + offset) * 255),
    Math.round((rgb[1] + offset) * 255),
    Math.round((rgb[2] + offset) * 255)
  ]
}

function channelToHex(value) {
  var text = Math.round(clampNumber(value, 0, 255)).toString(16)
  return text.length === 1 ? "0" + text : text
}

// "e09355" style hex (no leading #) for `openrgb -c`.
function rgbToHex(rgb) {
  return channelToHex(rgb[0]) + channelToHex(rgb[1]) + channelToHex(rgb[2])
}

// Accent (0-1 floats from QML color) + intensity (0-100 saturation) and
// brightness (0-100 value) -> hex.
function accentHex(red, green, blue, intensity, brightness) {
  var hs = rgbToHs([
    Math.round(red * 255),
    Math.round(green * 255),
    Math.round(blue * 255)
  ])
  var rgb = hsToRgb(hs.hue, clampNumber(intensity, 0, 100))
  var scale = clampNumber(typeof brightness === "number" ? brightness : 100,
                          0, 100) / 100
  return rgbToHex([rgb[0] * scale, rgb[1] * scale, rgb[2] * scale])
}
