import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Color.js" as RgbColor
import "ConfigStore.js" as ConfigStore

// Syncs local PC lighting to the Omarchy theme: OpenRGB devices follow the
// theme accent, and the NZXT Kraken LCD renders a theme-matched splash with
// live liquid/pump readings.
//
// Theme observation mirrors misza.hass: theme.name selects the per-theme
// intensity bucket, Color.accent provides the hue, intensity the saturation,
// brightness the value. Devices are addressed by enumerated OpenRGB index
// through argument arrays (never shell interpolation). A periodic refresh
// heals missed triggers and keeps LCD readings live.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/misza.rgbsync"
  readonly property string configDir: home + "/.config/omarchy/misza.rgbsync"
  readonly property string configPath: configDir + "/config.json"
  readonly property string themeNamePath: home + "/.local/state/omarchy/current/theme.name"
  readonly property string backgroundPath: home + "/.local/state/omarchy/current/background"
  readonly property string lcdImagePath: configDir + "/lcd.png"
  readonly property string openrgbBinary: "/usr/bin/openrgb"

  // The RTX 4090 Suprim X only holds the colour when its single zone is
  // addressed explicitly, and its reported mode stays [Off] either way, so
  // readback is never trusted. User deviceZones entries win over this.
  readonly property var defaultZones: ({ "rtx 4090": 0 })

  property bool enabled: false
  // Substrings matched (case-insensitively) against detected device names.
  // Empty means every detected device.
  property var devices: []
  property var deviceModes: ({})
  property var deviceZones: ({})
  property var intensity: ({})
  property real brightness: 100
  property int refreshInterval: 120
  property bool lcdEnabled: false
  property real lcdBrightness: 60
  property bool lcdWallpaper: true
  property real lcdDim: 0.5
  property bool lcdThemeName: true
  // Custom LCD texts (may carry {theme} {liquid} {pump} {fan}). Empty top /
  // bottom fall back to the defaults below; empty title falls back to the
  // theme name (or nothing when lcdThemeName is off).
  property string lcdTitle: ""
  property string lcdTop: ""
  property string lcdBottom: ""
  property real lcdZoom: 1
  property real lcdPanX: 0
  property real lcdPanY: 0
  // Live preview state for the wallpaper positioner: updated on every drag
  // move without touching the persisted values, committed on release.
  property real lcdViewZoom: 1
  property real lcdViewPanX: 0
  property real lcdViewPanY: 0
  property string liquidctlBinary: "liquidctl"
  property string currentThemeName: "current"

  readonly property color themeAccent: Color.accent

  // [{ index: int, name: string }] from the last enumeration.
  property var detected: []
  property string lastAppliedHex: ""
  property string lastError: ""
  property string lastErrorKind: ""
  property string lcdTemp: "--"
  property string lcdPump: "--"
  property string lcdFan: "--"
  property string lcdLastKey: ""
  // idle | brightness | query | render | push — surfaced in the UI so the
  // slow USB bulk push does not look like a hang.
  property string lcdPhase: "idle"
  readonly property bool busy: applyProcess.running || enumProcess.running
    || lcdStatusProcess.running || lcdRenderProcess.running
    || lcdPushProcess.running || lcdBrightnessProcess.running
  readonly property int deviceCount: root.detected.length
  readonly property int targetCount: root.resolveTargets().length

  function log(message) {
    console.log("rgbsync: " + message)
  }

  function fail(kind, message) {
    root.lastError = message
    root.lastErrorKind = kind
    console.warn("rgbsync: " + message)
  }

  function accentHex() {
    return RgbColor.accentHex(root.themeAccent.r, root.themeAccent.g,
                              root.themeAccent.b, root.intensityForTheme(),
                              root.brightness)
  }

  // ------------------------------------------------------------ theme watch

  property FileView themeNameFile: FileView {
    path: root.themeNamePath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyThemeName(text())
    onLoadFailed: root.applyThemeName("")
    onFileChanged: reload()
  }

  function normalizedThemeName(value) {
    var name = String(value || "").trim()
    return /^[A-Za-z0-9_.-]+$/.test(name) ? name : "current"
  }

  function applyThemeName(value) {
    var next = root.normalizedThemeName(value)
    if (root.currentThemeName === next) return
    root.currentThemeName = next
    root.log("theme -> " + next + " accent #" + root.accentHex())
    root.queueApply()
    root.queueLcd()
  }

  function themeDisplayName() {
    var words = root.currentThemeName.replace(/[_.-]+/g, " ").split(" ")
    for (var i = 0; i < words.length; i++) {
      if (words[i].length > 0) {
        words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1)
      }
    }
    return words.join(" ") || "Current"
  }

  onThemeAccentChanged: {
    root.log("accent changed (#" + root.accentHex() + ")")
    root.queueApply()
    root.queueLcd()
  }

  // ------------------------------------------------------------ config

  property FileView configFile: FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("")
    onFileChanged: reload()
  }

  function currentConfig() {
    return {
      enabled: root.enabled,
      devices: root.devices.slice(),
      deviceModes: root.deviceModes,
      deviceZones: root.deviceZones,
      intensity: root.intensity,
      brightness: root.brightness,
      refreshInterval: root.refreshInterval,
      lcdEnabled: root.lcdEnabled,
      lcdBrightness: root.lcdBrightness,
      lcdWallpaper: root.lcdWallpaper,
      lcdDim: root.lcdDim,
      lcdThemeName: root.lcdThemeName,
      lcdTitle: root.lcdTitle,
      lcdTop: root.lcdTop,
      lcdBottom: root.lcdBottom,
      lcdZoom: root.lcdZoom,
      lcdPanX: root.lcdPanX,
      lcdPanY: root.lcdPanY,
      liquidctlBinary: root.liquidctlBinary
    }
  }

  function saveConfig(patch) {
    var config = ConfigStore.merge(root.currentConfig(), patch)
    var text = ConfigStore.serialize(config)
    configFile.setText(text)
    // FileView does not re-emit onLoaded for its own write.
    root.applyConfig(text)
  }

  property string appliedConfigText: ""

  function applyConfig(text) {
    if (text && text === root.appliedConfigText) return
    root.appliedConfigText = text
    var parsed = ConfigStore.parse(text)
    var config = parsed.config
    if (parsed.error) {
      root.lastError = parsed.error
      root.lastErrorKind = "config"
    }
    root.enabled = config.enabled
    root.devices = config.devices
    root.deviceModes = config.deviceModes
    root.deviceZones = config.deviceZones
    root.intensity = config.intensity
    root.brightness = config.brightness
    root.refreshInterval = config.refreshInterval
    root.lcdEnabled = config.lcdEnabled
    root.lcdBrightness = config.lcdBrightness
    root.lcdWallpaper = config.lcdWallpaper
    root.lcdDim = config.lcdDim
    root.lcdThemeName = config.lcdThemeName
    root.lcdTitle = config.lcdTitle
    root.lcdTop = config.lcdTop
    root.lcdBottom = config.lcdBottom
    root.lcdZoom = config.lcdZoom
    root.lcdPanX = config.lcdPanX
    root.lcdPanY = config.lcdPanY
    root.syncLcdView()
    root.liquidctlBinary = config.liquidctlBinary
    root.queueApply()
    root.queueLcd()
  }

  property Process configDirProcess: Process {
    command: ["mkdir", "-p", root.configDir]
  }

  // ------------------------------------------------------------ controls

  function setEnabled(on) {
    if (root.enabled === on) return
    root.saveConfig({ enabled: on })
    root.log(on ? "sync enabled" : "sync disabled (LEDs keep last state)")
    if (on) root.queueApply()
  }

  function toggle() {
    root.setEnabled(!root.enabled)
  }

  function intensityForTheme() {
    var setting = root.intensity[root.currentThemeName]
    var value = setting && typeof setting.intensity === "number"
      ? setting.intensity : 100
    return Math.max(0, Math.min(100, value))
  }

  function saveIntensity() {
    intensitySaveDebounce.stop()
    root.saveConfig({ intensity: root.intensity })
  }

  property Timer intensitySaveDebounce: Timer {
    interval: 300
    onTriggered: root.saveIntensity()
  }

  function setIntensity(value, immediate) {
    var next = Math.round(Math.max(0, Math.min(100, Number(value))) * 100) / 100
    if (!isFinite(next)) return
    var key = root.currentThemeName
    var settings = {}
    for (var existing in root.intensity) settings[existing] = root.intensity[existing]
    settings[key] = { intensity: next }
    root.intensity = settings
    if (immediate === true) root.saveIntensity()
    else intensitySaveDebounce.restart()
    root.queueApply()
    root.queueLcd()
  }

  function setBrightness(value, immediate) {
    var next = Math.round(Math.max(0, Math.min(100, Number(value))))
    if (!isFinite(next)) return
    if (root.brightness === next) return
    root.brightness = next
    if (immediate === true) {
      brightnessSaveDebounce.stop()
      root.saveConfig({ brightness: root.brightness })
    } else brightnessSaveDebounce.restart()
    root.queueApply()
    root.queueLcd()
  }

  property Timer brightnessSaveDebounce: Timer {
    interval: 300
    onTriggered: root.saveConfig({ brightness: root.brightness })
  }

  function setRefreshInterval(seconds) {
    var next = Math.round(Math.max(0, Math.min(3600, Number(seconds))))
    if (!isFinite(next)) return
    if (root.refreshInterval === next) return
    root.saveConfig({ refreshInterval: next })
  }

  function isDeviceEnabled(name) {
    if (root.devices.length === 0) return true
    var lower = String(name).toLowerCase()
    for (var i = 0; i < root.devices.length; i++) {
      if (lower.indexOf(String(root.devices[i]).toLowerCase()) !== -1) return true
    }
    return false
  }

  function detectedNames() {
    var out = []
    for (var i = 0; i < root.detected.length; i++) out.push(root.detected[i].name)
    return out
  }

  function toggleDevice(name) {
    if (root.devices.length === 0) {
      if (!root.isDeviceEnabled(name)) return
      var rest = []
      for (var i = 0; i < root.detected.length; i++) {
        if (root.detected[i].name !== name) rest.push(root.detected[i].name)
      }
      root.saveConfig({ devices: rest })
    } else if (root.isDeviceEnabled(name)) {
      var lower = String(name).toLowerCase()
      var kept = []
      for (var k = 0; k < root.devices.length; k++) {
        if (lower.indexOf(String(root.devices[k]).toLowerCase()) === -1) {
          kept.push(root.devices[k])
        }
      }
      root.saveConfig({ devices: kept })
    } else {
      var added = root.devices.slice()
      added.push(name)
      root.saveConfig({ devices: added })
    }
    root.queueApply()
  }

  // ------------------------------------------------------------ LCD controls

  function setLcdEnabled(on) {
    if (root.lcdEnabled === on) return
    root.saveConfig({ lcdEnabled: on })
    root.log(on ? "lcd enabled" : "lcd disabled (screen keeps last image)")
    if (on) {
      root.lcdBrightnessDirty = true
      root.queueLcd()
    }
  }

  function toggleLcd() {
    root.setLcdEnabled(!root.lcdEnabled)
  }

  function setLcdBrightness(value, immediate) {
    var next = Math.round(Math.max(0, Math.min(100, Number(value))))
    if (!isFinite(next)) return
    if (root.lcdBrightness === next) return
    root.lcdBrightness = next
    if (immediate === true) {
      lcdBrightnessSaveDebounce.stop()
      root.saveConfig({ lcdBrightness: root.lcdBrightness })
    } else lcdBrightnessSaveDebounce.restart()
    root.lcdBrightnessDirty = true
    root.queueLcd()
  }

  property Timer lcdBrightnessSaveDebounce: Timer {
    interval: 300
    onTriggered: root.saveConfig({ lcdBrightness: root.lcdBrightness })
  }

  function setLcdWallpaper(on) {
    if (root.lcdWallpaper === on) return
    root.saveConfig({ lcdWallpaper: on })
    root.queueLcd()
  }

  function setLcdThemeName(on) {
    if (root.lcdThemeName === on) return
    root.saveConfig({ lcdThemeName: on })
    root.queueLcd()
  }

  function setLcdTexts(title, top, bottom) {
    root.saveConfig({ lcdTitle: title, lcdTop: top, lcdBottom: bottom })
    root.log("lcd texts updated")
    root.queueLcd()
  }

  function substituteLcd(template) {
    return String(template || "")
      .split("{theme}").join(root.themeDisplayName())
      .split("{liquid}").join(root.lcdTemp)
      .split("{pump}").join(root.lcdPump)
      .split("{fan}").join(root.lcdFan)
  }

  function resolvedLcdTitle() {
    var custom = root.lcdTitle.trim()
    if (custom !== "") return root.substituteLcd(custom)
    if (root.lcdThemeName) return root.themeDisplayName()
    return ""
  }

  function resolvedLcdTop() {
    var custom = root.lcdTop.trim()
    if (custom !== "") return root.substituteLcd(custom)
    return "LIQUID " + root.lcdTemp + "°C"
  }

  function resolvedLcdBottom() {
    var custom = root.lcdBottom.trim()
    if (custom !== "") return root.substituteLcd(custom)
    return "PUMP " + root.lcdPump + " RPM"
  }

  function syncLcdView() {
    root.lcdViewZoom = root.lcdZoom
    root.lcdViewPanX = root.lcdPanX
    root.lcdViewPanY = root.lcdPanY
  }

  // Preview-only update while positioning the wallpaper: no save, no render.
  function previewLcdView(zoom, x, y) {
    var z = Math.round(Math.max(1, Math.min(3, Number(zoom))) * 100) / 100
    if (!isFinite(z)) return
    var px = Math.round(Math.max(-2000, Math.min(2000, Number(x))))
    var py = Math.round(Math.max(-2000, Math.min(2000, Number(y))))
    if (!isFinite(px) || !isFinite(py)) return
    root.lcdViewZoom = z
    root.lcdViewPanX = px
    root.lcdViewPanY = py
  }

  function setLcdZoom(value) {
    var next = Math.round(Math.max(1, Math.min(3, Number(value))) * 100) / 100
    if (!isFinite(next)) return
    if (root.lcdZoom === next) return
    root.lcdZoom = next
    root.lcdViewZoom = next
    root.saveConfig({ lcdZoom: root.lcdZoom })
    root.queueLcd()
  }

  function setLcdPan(x, y) {
    var px = Math.round(Math.max(-2000, Math.min(2000, Number(x))))
    var py = Math.round(Math.max(-2000, Math.min(2000, Number(y))))
    if (!isFinite(px) || !isFinite(py)) return
    if (root.lcdPanX === px && root.lcdPanY === py) return
    root.lcdPanX = px
    root.lcdPanY = py
    root.lcdViewPanX = px
    root.lcdViewPanY = py
    root.saveConfig({ lcdPanX: root.lcdPanX, lcdPanY: root.lcdPanY })
    root.queueLcd()
  }

  function resetLcdView() {
    root.saveConfig({ lcdZoom: 1, lcdPanX: 0, lcdPanY: 0 })
    root.queueLcd()
  }

  function setLcdDim(percent) {
    var next = Math.round(Math.max(10, Math.min(100, Number(percent))) * 100) / 100
    if (!isFinite(next)) return
    var dim = next / 100
    if (root.lcdDim === dim) return
    root.lcdDim = dim
    lcdDimSaveDebounce.restart()
    root.queueLcd()
  }

  property Timer lcdDimSaveDebounce: Timer {
    interval: 300
    onTriggered: root.saveConfig({ lcdDim: root.lcdDim })
  }

  // ------------------------------------------------------------ targets

  function matchKey(map, name) {
    var lower = String(name).toLowerCase()
    for (var key in map) {
      if (lower.indexOf(String(key).toLowerCase()) !== -1) return key
    }
    return null
  }

  function modeFor(name) {
    var key = root.matchKey(root.deviceModes, name)
    return key !== null ? String(root.deviceModes[key]) : "Direct"
  }

  function zoneFor(name) {
    var key = root.matchKey(root.deviceZones, name)
    if (key !== null) return root.deviceZones[key]
    var fallback = root.matchKey(root.defaultZones, name)
    if (fallback !== null) return root.defaultZones[fallback]
    return -1
  }

  function resolveTargets() {
    var out = []
    for (var i = 0; i < root.detected.length; i++) {
      var device = root.detected[i]
      if (!root.isDeviceEnabled(device.name)) continue
      out.push({
        index: device.index,
        name: device.name,
        mode: root.modeFor(device.name),
        zone: root.zoneFor(device.name)
      })
    }
    return out
  }

  function parseDevices(text) {
    var found = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^(\d+):\s+(.+)$/)
      if (match) found.push({ index: parseInt(match[1], 10), name: match[2].trim() })
    }
    return found
  }

  // ------------------------------------------------------------ RGB apply

  property Timer applyDebounce: Timer {
    interval: 300
    onTriggered: root.applyNow()
  }

  // Coalesced request while a run is in flight.
  property string pendingHex: ""
  // Chain an apply after the running enumeration finishes.
  property bool applyAfterEnum: false
  // Hex of the in-flight run; committed to lastAppliedHex on success.
  property string appliedHex: ""
  property bool applyRetried: false
  property string applyStderr: ""

  function queueApply() {
    if (!root.enabled) return
    applyDebounce.restart()
  }

  function applyNow() {
    if (!root.enabled) return
    var hex = root.accentHex()
    if (hex === root.lastAppliedHex && root.detected.length > 0) return
    if (applyProcess.running) {
      root.pendingHex = hex
      return
    }
    if (root.detected.length === 0) {
      root.applyAfterEnum = true
      root.enumerate()
      return
    }
    var targets = root.resolveTargets()
    if (targets.length === 0) {
      root.fail("devices", "No OpenRGB devices match the selection.")
      return
    }
    var command = [root.openrgbBinary]
    for (var i = 0; i < targets.length; i++) {
      command.push("-d", String(targets[i].index))
      if (targets[i].zone >= 0) command.push("-z", String(targets[i].zone))
      command.push("-m", targets[i].mode, "-c", hex)
    }
    root.log("apply #" + hex + " to " + targets.length + " device(s)")
    root.appliedHex = hex
    root.applyRetried = false
    root.applyStderr = ""
    applyProcess.command = command
    applyProcess.running = true
  }

  property Process applyProcess: Process {
    stdout: SplitParser {
      onRead: function(value) {}
    }
    stderr: SplitParser {
      onRead: function(value) {
        root.applyStderr = (root.applyStderr + value + "\n").slice(-500)
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.fail("apply", "openrgb exited (code " + exitCode + ")."
          + (root.applyStderr ? " " + root.applyStderr.trim().split("\n").pop() : ""))
        if (!root.applyRetried) {
          root.applyRetried = true
          root.applyAfterEnum = true
          root.enumerate()
        }
        return
      }
      root.lastAppliedHex = root.appliedHex
      root.lastError = ""
      root.lastErrorKind = ""
      root.log("applied #" + root.lastAppliedHex)
      if (root.pendingHex !== "") {
        var next = root.pendingHex
        root.pendingHex = ""
        if (next !== root.lastAppliedHex) root.applyNow()
      }
    }
  }

  // ------------------------------------------------------------ enumerate

  property string enumOutput: ""

  function enumerate() {
    if (enumProcess.running) return
    root.enumOutput = ""
    enumProcess.command = [root.openrgbBinary, "--list-devices"]
    enumProcess.running = true
  }

  property Process enumProcess: Process {
    stdout: SplitParser {
      onRead: function(value) { root.enumOutput += value + "\n" }
    }
    stderr: SplitParser {
      onRead: function(value) {}
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.detected = root.parseDevices(root.enumOutput)
        root.log("detected " + root.detected.length + " OpenRGB device(s)")
        if (root.detected.length === 0) {
          root.fail("devices", "OpenRGB found no devices.")
        }
      } else {
        root.fail("devices", "OpenRGB device scan failed (code " + exitCode + ").")
      }
      if (root.applyAfterEnum) {
        root.applyAfterEnum = false
        root.applyNow()
      }
    }
  }

  // ------------------------------------------------------------ refresh

  property Timer refreshTimer: Timer {
    interval: Math.max(1, root.refreshInterval) * 1000
    repeat: true
    running: (root.enabled || root.lcdEnabled) && root.refreshInterval > 0
    onTriggered: {
      root.log("refresh tick")
      if (root.enabled) root.applyNow()
      if (root.lcdEnabled) root.lcdCycle()
    }
  }

  // ------------------------------------------------------------ LCD cycle

  property Timer lcdDebounce: Timer {
    interval: 500
    onTriggered: root.lcdCycle()
  }

  property bool lcdPending: false
  property bool lcdBrightnessDirty: false
  property string lcdStatusOutput: ""
  property string lcdStatusStderr: ""
  property string lcdPushStderr: ""

  function queueLcd() {
    if (!root.lcdEnabled) return
    lcdDebounce.restart()
  }

  function lcdBusy() {
    return lcdStatusProcess.running || lcdRenderProcess.running
      || lcdPushProcess.running || lcdBrightnessProcess.running
  }

  function lcdError(message) {
    root.fail("lcd", message)
    root.lcdPhase = "idle"
    // Drop coalesced work: the refresh tick retries later. Retrying here
    // would spin forever on a persistent failure (missing binary, no access).
    root.lcdPending = false
  }

  function lcdKey() {
    // Pump RPM jitters every read and fractional degrees drift constantly,
    // so those stay out of the key. But every render input MUST be in it:
    // omitting one makes its changes silently skip as "up to date". Fan is
    // bucketed to whole tens for the same jitter reason.
    var tempInt = parseInt(root.lcdTemp, 10)
    if (!isFinite(tempInt)) tempInt = root.lcdTemp
    var fanInt = parseInt(root.lcdFan, 10)
    fanInt = isFinite(fanInt) ? Math.round(fanInt / 50) * 50 : root.lcdFan
    return root.currentThemeName + "|" + root.accentHex() + "|" + tempInt
      + "|" + (root.lcdWallpaper ? "wp" : "plain")
      + "|" + root.lcdDim + "|" + (root.lcdThemeName ? "title" : "notitle")
      + "|" + root.lcdZoom + "|" + Math.round(root.lcdPanX)
      + "," + Math.round(root.lcdPanY)
      + "|" + root.lcdTitle + "|" + root.lcdTop + "|" + root.lcdBottom
      + "|" + fanInt
  }

  function lcdCycle() {
    if (!root.lcdEnabled) return
    if (root.lcdBusy()) {
      root.lcdPending = true
      return
    }
    root.lcdPending = false
    root.lcdPhase = root.lcdBrightnessDirty ? "brightness" : "query"
    if (root.lcdBrightnessDirty) {
      root.lcdBrightnessDirty = false
      root.log("lcd brightness " + root.lcdBrightness + "%")
      lcdBrightnessProcess.command = [root.liquidctlBinary, "--match", "Kraken",
        "set", "lcd", "screen", "brightness", String(Math.round(root.lcdBrightness))]
      lcdBrightnessProcess.running = true
      return
    }
    root.lcdStatusOutput = ""
    root.lcdStatusStderr = ""
    lcdStatusProcess.command = [root.liquidctlBinary, "--match", "Kraken", "status"]
    lcdStatusProcess.running = true
  }

  property Process lcdBrightnessProcess: Process {
    stdout: SplitParser {
      onRead: function(value) {}
    }
    stderr: SplitParser {
      onRead: function(value) {}
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.log("lcd brightness set failed (code " + exitCode + ")")
      }
      root.lcdStatusOutput = ""
      root.lcdStatusStderr = ""
      lcdStatusProcess.command = [root.liquidctlBinary, "--match", "Kraken", "status"]
      lcdStatusProcess.running = true
    }
  }

  property Process lcdStatusProcess: Process {
    stdout: SplitParser {
      onRead: function(value) { root.lcdStatusOutput += value + "\n" }
    }
    stderr: SplitParser {
      onRead: function(value) {
        root.lcdStatusStderr = (root.lcdStatusStderr + value + "\n").slice(-500)
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lcdError("Kraken status query failed (code " + exitCode + ")."
          + (root.lcdStatusStderr ? " " + root.lcdStatusStderr.trim().split("\n").pop() : ""))
        return
      }
      if (!root.lcdEnabled) return
      var temp = root.lcdStatusOutput.match(/Liquid temperature\s+([0-9]+(?:\.[0-9]+)?)/)
      var pump = root.lcdStatusOutput.match(/Pump speed\s+([0-9]+)/)
      var fan = root.lcdStatusOutput.match(/Fan speed\s+([0-9]+)/)
      if (temp) root.lcdTemp = temp[1]
      if (pump) root.lcdPump = pump[1]
      if (fan) root.lcdFan = fan[1]
      if (root.lcdKey() === root.lcdLastKey) {
        root.log("lcd up to date (" + root.lcdTemp + "C)")
        root.lcdPhase = "idle"
        if (root.lcdPending) {
          root.lcdPending = false
          root.lcdCycle()
        }
        return
      }
      var command = ["python3", root.pluginDir + "/bin/rgbsync-lcd",
        "--accent", root.accentHex(),
        "--title", root.resolvedLcdTitle(),
        "--top", root.resolvedLcdTop(),
        "--bottom", root.resolvedLcdBottom(),
        "--temp", root.lcdTemp, "--pump", root.lcdPump,
        "--out", root.lcdImagePath]
      if (root.lcdWallpaper) {
        command.push("--wallpaper", root.backgroundPath,
                     "--dim", String(root.lcdDim),
                     "--zoom", String(root.lcdZoom),
                     "--pan", String(Math.round(root.lcdPanX)) + ","
                       + String(Math.round(root.lcdPanY)))
      }
      root.lcdPhase = "render"
      lcdRenderProcess.command = command
      lcdRenderProcess.running = true
    }
  }

  property Process lcdRenderProcess: Process {
    stdout: SplitParser {
      onRead: function(value) { root.log("lcd render: " + value) }
    }
    stderr: SplitParser {
      onRead: function(value) { root.log("lcd render: " + value) }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lcdError("LCD image render failed (code " + exitCode + ").")
        return
      }
      lcdPushProcess.command = [root.liquidctlBinary, "--match", "Kraken",
        "set", "lcd", "screen", "static", root.lcdImagePath]
      root.lcdPhase = "push"
      lcdPushProcess.running = true
    }
  }

  property Process lcdPushProcess: Process {
    stdout: SplitParser {
      onRead: function(value) {}
    }
    stderr: SplitParser {
      onRead: function(value) {
        root.lcdPushStderr = (root.lcdPushStderr + value + "\n").slice(-500)
      }
    }
    onExited: function(exitCode) {
      root.lcdPhase = "idle"
      if (exitCode !== 0) {
        root.lcdError("LCD push failed (code " + exitCode + ")."
          + (root.lcdPushStderr ? " " + root.lcdPushStderr.trim().split("\n").pop() : ""))
        return
      }
      root.lcdLastKey = root.lcdKey()
      // A past LCD failure stays sticky otherwise: clears only its own kind.
      if (root.lastErrorKind === "lcd") {
        root.lastError = ""
        root.lastErrorKind = ""
      }
      root.log("lcd pushed (" + root.lcdTemp + "C, key " + root.lcdLastKey + ")")
      if (root.lcdPending) {
        root.lcdPending = false
        root.lcdCycle()
      }
    }
  }

  Component.onCompleted: {
    root.configDirProcess.running = true
    // Always chain: applyNow is a no-op while disabled, and this restores
    // lighting on session start when enabled. Config may load after this.
    root.applyAfterEnum = true
    root.enumerate()
  }
}
