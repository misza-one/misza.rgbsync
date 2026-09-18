import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import qs.Ui
import qs.Commons

// Bar button plus popup: RGB sync toggle, intensity/brightness, per-device
// selection, LCD section, refresh interval.
Panel {
  id: root
  moduleName: "misza.rgbsync"
  ipcTarget: "misza.rgbsync"
  manageIpc: false

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("misza.rgbsync") : null
  // serviceFor yields undefined (not null) while the plugin reloads; a bare
  // `!== null` check would call that ready and walk into svc.* reads.
  readonly property bool ready: svc !== null && svc !== undefined
  // Theme foreground, not the bar's: bar text colours can go dark-on-dark
  // against the popup background on some themes (e.g. muted descriptions
  // on Osaka Jade), while Color.foreground is built for theme surfaces.
  readonly property color fg: Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  // LCD text drafts, loaded from the service every time the popup opens.
  property string titleDraft: ""
  property string topDraft: ""
  property string bottomDraft: ""

  onOpenedChanged: {
    if (opened && ready) {
      titleDraft = svc.lcdTitle
      topDraft = svc.lcdTop
      bottomDraft = svc.lcdBottom
    }
  }

  function statusLine() {
    if (!ready) return "Service unavailable"
    if (svc.lastError !== "") return svc.lastError
    var parts = []
    parts.push(svc.enabled ? "RGB on" : "RGB off")
    parts.push(svc.themeDisplayName() + " #" + svc.accentHex())
    parts.push(svc.targetCount + "/" + svc.deviceCount + " devices")
    if (svc.lcdEnabled) parts.push("LCD " + svc.lcdTemp + "C")
    if (svc.busy) parts.push(svc.lcdPhase !== "idle" ? "LCD " + svc.lcdPhase + "…" : "working…")
    return parts.join(" · ")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "misza.rgbsync"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }

    function status(): string {
      if (!root.ready) return "service: UNREACHABLE"
      return "enabled=" + root.svc.enabled
        + " theme=" + root.svc.currentThemeName
        + " hex=" + root.svc.accentHex()
        + " devices=" + root.svc.deviceCount
        + " targets=" + root.svc.targetCount
        + " lcd=" + root.svc.lcdEnabled
        + " liquid=" + root.svc.lcdTemp + "C pump=" + root.svc.lcdPump
        + " fan=" + root.svc.lcdFan
        + " deps=" + (!root.svc.depsProbed ? "probing"
          : root.svc.depsMissing.length === 0 ? "ok"
          : root.svc.depsMissing.join(","))
        + (root.svc.lastError ? " error=" + root.svc.lastError : "")
    }

    function lcdPreviewTest(): string {
      if (!root.ready) return "service unavailable"
      root.svc.previewLcdView(2, 50, -30)
      return "view=" + root.svc.lcdViewZoom + "," + root.svc.lcdViewPanX
        + "," + root.svc.lcdViewPanY
    }

    function refresh(): string {
      if (!root.ready) return "service unavailable"
      root.svc.applyNow()
      root.svc.lcdCycle()
      return "ok"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "RGB"
    foreground: root.fg
    active: root.ready && root.svc.enabled
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(
      Math.min(column.implicitHeight, Style.space(600)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

      Column {
        id: column
        width: scroll.availableWidth
        spacing: Style.spacing.panelGap

        PanelHero {
          width: parent.width
          title: "RGB Sync"
          meta: root.statusLine()
          foreground: root.fg
          fontFamily: root.family
        }

        PanelSeparator { width: parent.width; foreground: root.fg }

        PanelSectionHeader {
          width: parent.width
          text: "THEME · " + (root.ready ? root.svc.themeDisplayName().toUpperCase() : "—")
          foreground: root.fg
          fontFamily: root.family
        }

        Toggle {
          width: parent.width
          label: "Sync PC lighting"
          description: "Follow the Omarchy accent on all selected devices."
          checked: root.ready && root.svc.enabled
          foreground: root.fg
          fontFamily: root.family
          onClicked: if (root.ready) root.svc.toggle()
        }

        LabeledSlider {
          width: parent.width
          bar: root.bar
          label: "Intensity"
          value: root.ready ? root.svc.intensityForTheme() : 100
          valueText: root.ready ? Math.round(root.svc.intensityForTheme()) + "%" : "100%"
          onMoved: function(value) { if (root.ready) root.svc.setIntensity(value, false) }
          onReleased: function(value) { if (root.ready) root.svc.setIntensity(value, true) }
        }

        LabeledSlider {
          width: parent.width
          bar: root.bar
          label: "Brightness"
          value: root.ready ? root.svc.brightness : 100
          valueText: root.ready ? Math.round(root.svc.brightness) + "%" : "100%"
          onMoved: function(value) { if (root.ready) root.svc.setBrightness(value, false) }
          onReleased: function(value) { if (root.ready) root.svc.setBrightness(value, true) }
        }

        PanelSectionHeader {
          width: parent.width
          text: "DEVICES"
          foreground: root.fg
          fontFamily: root.family
        }

        Text {
          width: parent.width
          visible: root.ready && root.svc.deviceCount === 0
          text: "No OpenRGB devices detected."
          color: Color.muted
          font.family: root.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: root.ready ? root.svc.deviceCount : 0
          Toggle {
            width: column.width
            label: root.svc.detected[index].name
            description: root.svc.isDeviceEnabled(root.svc.detected[index].name)
              ? "Synced" : "Skipped"
            checked: root.svc.isDeviceEnabled(root.svc.detected[index].name)
            foreground: root.fg
            fontFamily: root.family
            onClicked: root.svc.toggleDevice(root.svc.detected[index].name)
          }
        }

        PanelSectionHeader {
          width: parent.width
          text: "KRAKEN LCD"
          foreground: root.fg
          fontFamily: root.family
        }

        Toggle {
          width: parent.width
          label: "Theme splash screen"
          description: root.ready
            ? ("Liquid " + root.svc.lcdTemp + "°C · pump " + root.svc.lcdPump + " RPM")
            : "NZXT Kraken Elite LCD"
          checked: root.ready && root.svc.lcdEnabled
          foreground: root.fg
          fontFamily: root.family
          onClicked: if (root.ready) root.svc.toggleLcd()
        }

        LabeledSlider {
          width: parent.width
          bar: root.bar
          label: "LCD brightness"
          value: root.ready ? root.svc.lcdBrightness : 60
          valueText: root.ready ? Math.round(root.svc.lcdBrightness) + "%" : "60%"
          onMoved: function(value) { if (root.ready) root.svc.setLcdBrightness(value, false) }
          onReleased: function(value) { if (root.ready) root.svc.setLcdBrightness(value, true) }
        }

        Toggle {
          width: parent.width
          label: "Theme wallpaper backdrop"
          description: "Use the current theme background behind the splash."
          checked: root.ready && root.svc.lcdWallpaper
          foreground: root.fg
          fontFamily: root.family
          onClicked: if (root.ready) root.svc.setLcdWallpaper(!root.svc.lcdWallpaper)
        }

        Toggle {
          width: parent.width
          label: "Theme name title"
          description: "Show the theme name above the readings."
          checked: root.ready && root.svc.lcdThemeName
          foreground: root.fg
          fontFamily: root.family
          onClicked: if (root.ready) root.svc.setLcdThemeName(!root.svc.lcdThemeName)
        }

        TextField {
          width: parent.width
          text: root.titleDraft
          placeholderText: "Title (empty = theme name)"
          onTextChanged: root.titleDraft = text
        }

        TextField {
          width: parent.width
          text: root.topDraft
          placeholderText: "Top line, e.g. LIQUID {liquid}°C"
          onTextChanged: root.topDraft = text
        }

        TextField {
          width: parent.width
          text: root.bottomDraft
          placeholderText: "Bottom line, e.g. PUMP {pump} RPM"
          onTextChanged: root.bottomDraft = text
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Placeholders: {theme} {liquid} {pump} {fan}"
          color: Color.muted
          font.family: root.family
          font.pixelSize: Style.font.caption
        }

        Button {
          anchors.horizontalCenter: parent.horizontalCenter
          bordered: true
          text: "Apply texts"
          foreground: root.fg
          fontFamily: root.family
          onClicked: {
            if (root.ready) {
              root.svc.setLcdTexts(root.titleDraft, root.topDraft,
                                   root.bottomDraft)
            }
          }
        }

        LabeledSlider {
          width: parent.width
          bar: root.bar
          label: "Wallpaper dim"
          value: root.ready ? root.svc.lcdDim * 100 : 50
          valueText: root.ready ? Math.round(root.svc.lcdDim * 100) + "%" : "50%"
          onMoved: function(value) { if (root.ready) root.svc.setLcdDim(value) }
          onReleased: function(value) { if (root.ready) root.svc.setLcdDim(value) }
        }

        // Round wallpaper positioner: drag the photo, zoom with the slider.
        // Moves only update the preview; releasing commits to the pump LCD.
        Column {
          id: wpPositioner
          width: parent.width
          visible: root.ready && root.svc.lcdWallpaper
          spacing: Style.spacing.xs

          property real viewSize: 200
          property real toPx: 640 / viewSize
          property real iw: Math.max(1, wpImage.sourceSize.width)
          property real ih: Math.max(1, wpImage.sourceSize.height)
          property real cover: Math.max(viewSize / iw, viewSize / ih)

          Item {
            id: wpWrap
            width: wpPositioner.viewSize
            height: wpPositioner.viewSize
            anchors.horizontalCenter: parent.horizontalCenter

            Item {
              id: wpFrame
              anchors.fill: parent
              clip: true
              layer.enabled: true
              layer.effect: OpacityMask {
                maskSource: Rectangle {
                  width: wpFrame.width
                  height: wpFrame.height
                  radius: wpFrame.width / 2
                  visible: false
                }
              }

              Image {
                id: wpImage
                source: root.ready
                  ? "file://" + root.svc.backgroundPath + "?theme=" + root.svc.currentThemeName
                  : ""
                cache: false
                asynchronous: true
                fillMode: Image.Stretch
                width: wpPositioner.iw * wpPositioner.cover
                  * (root.ready ? root.svc.lcdViewZoom : 1)
                height: wpPositioner.ih * wpPositioner.cover
                  * (root.ready ? root.svc.lcdViewZoom : 1)
                x: wpPositioner.viewSize / 2 - width / 2
                   - (root.ready ? root.svc.lcdViewPanX : 0) / wpPositioner.toPx
                y: wpPositioner.viewSize / 2 - height / 2
                   - (root.ready ? root.svc.lcdViewPanY : 0) / wpPositioner.toPx
              }

              Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: root.ready ? 1 - root.svc.lcdDim : 0.5
              }

              Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.color: root.ready ? root.svc.themeAccent : Color.accent
                border.width: 4
              }
            }

            MouseArea {
              anchors.fill: parent
              // The surrounding ScrollView must not steal the gesture:
              // without this, vertical drags scroll the popup instead of
              // panning the photo and the press feels "not held".
              preventStealing: true
              property real lastX: 0
              property real lastY: 0
              function commitPan(where) {
                if (!root.ready) return
                console.log("rgbsync: wallpaper " + where
                  + " pan=" + Math.round(root.svc.lcdViewPanX)
                  + "," + Math.round(root.svc.lcdViewPanY))
                root.svc.setLcdPan(root.svc.lcdViewPanX, root.svc.lcdViewPanY)
              }
              onPressed: function(mouse) {
                console.log("rgbsync: wallpaper press")
                lastX = mouse.x
                lastY = mouse.y
              }
              onPositionChanged: function(mouse) {
                if (!pressed || !root.ready) return
                root.svc.previewLcdView(
                  root.svc.lcdViewZoom,
                  root.svc.lcdViewPanX - (mouse.x - lastX) * wpPositioner.toPx,
                  root.svc.lcdViewPanY - (mouse.y - lastY) * wpPositioner.toPx)
                lastX = mouse.x
                lastY = mouse.y
              }
              onReleased: function(mouse) { commitPan("release") }
              onCanceled: function() { commitPan("canceled") }
            }
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Drag to position · sliders work too · release applies"
            color: Color.muted
            font.family: root.family
            font.pixelSize: Style.font.caption
          }
        }

        LabeledSlider {
          width: parent.width
          visible: root.ready && root.svc.lcdWallpaper
          bar: root.bar
          label: "Wallpaper zoom"
          minimum: 100
          maximum: 300
          step: 5
          value: root.ready ? root.svc.lcdViewZoom * 100 : 100
          valueText: root.ready ? Math.round(root.svc.lcdViewZoom * 100) + "%" : "100%"
          onMoved: function(value) {
            if (root.ready) {
              root.svc.previewLcdView(value / 100, root.svc.lcdViewPanX,
                                      root.svc.lcdViewPanY)
            }
          }
          onReleased: function(value) {
            if (root.ready) root.svc.setLcdZoom(value / 100)
          }
        }

        LabeledSlider {
          width: parent.width
          visible: root.ready && root.svc.lcdWallpaper
          bar: root.bar
          label: "Position X"
          minimum: -300
          maximum: 300
          step: 5
          value: root.ready ? root.svc.lcdViewPanX : 0
          valueText: root.ready ? Math.round(root.svc.lcdViewPanX) + " px" : "0 px"
          onMoved: function(value) {
            if (root.ready) {
              root.svc.previewLcdView(root.svc.lcdViewZoom, value,
                                      root.svc.lcdViewPanY)
            }
          }
          onReleased: function(value) {
            if (root.ready) root.svc.setLcdPan(value, root.svc.lcdViewPanY)
          }
        }

        LabeledSlider {
          width: parent.width
          visible: root.ready && root.svc.lcdWallpaper
          bar: root.bar
          label: "Position Y"
          minimum: -300
          maximum: 300
          step: 5
          value: root.ready ? root.svc.lcdViewPanY : 0
          valueText: root.ready ? Math.round(root.svc.lcdViewPanY) + " px" : "0 px"
          onMoved: function(value) {
            if (root.ready) {
              root.svc.previewLcdView(root.svc.lcdViewZoom, root.svc.lcdViewPanX,
                                      value)
            }
          }
          onReleased: function(value) {
            if (root.ready) root.svc.setLcdPan(root.svc.lcdViewPanX, value)
          }
        }

        Button {
          visible: root.ready && root.svc.lcdWallpaper
          anchors.horizontalCenter: parent.horizontalCenter
          bordered: true
          text: "Reset wallpaper view"
          foreground: root.fg
          fontFamily: root.family
          onClicked: if (root.ready) root.svc.resetLcdView()
        }

        LabeledSlider {
          width: parent.width
          bar: root.bar
          label: "Refresh"
          minimum: 0
          maximum: 30
          step: 1
          value: root.ready ? root.svc.refreshInterval : 30
          valueText: root.ready
            ? (root.svc.refreshInterval <= 0 ? "Off" : root.svc.refreshInterval + " s")
            : "30 s"
          onReleased: function(value) { if (root.ready) root.svc.setRefreshInterval(value) }
          onMoved: function(value) {}
        }
      }
      }
    }
  }
}
