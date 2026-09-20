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
  property int petPreviewIndex: 0
  property string petIdDraft: ""
  property string petInstallStatus: ""
  property var installedPets: []

  function localFilePath(url) {
    var text = String(url || "")
    if (text.indexOf("file://") === 0) text = text.slice(7)
    try {
      return decodeURIComponent(text)
    } catch (exception) {
      return text
    }
  }

  function displayPetName(path) {
    for (var i = 0; i < root.installedPets.length; i++) {
      if (root.installedPets[i].path === path) return root.installedPets[i].name
    }
    return root.ready ? root.svc.petName(path) : "—"
  }

  Timer {
    interval: 120
    repeat: true
    running: root.opened && root.ready && root.svc.lcdPet
    onTriggered: root.petPreviewIndex = (root.petPreviewIndex + 1) % 8
  }
  Process {
    id: petFilePicker
    command: [
      "zenity", "--file-selection", "--title=Choose an OpenPets spritesheet",
      "--file-filter=Pet spritesheets | *.png *.webp *.jpg *.jpeg"
    ]
    stdout: SplitParser {
      onRead: function(line) {
        var path = String(line || "").trim()
        if (path && root.ready) root.svc.setLcdPetPath(path)
      }
    }
  }

  function refreshInstalledPets() {
    if (!root.ready || petCatalogScanner.running) return
    root.installedPets = []
    petCatalogScanner.running = true
  }

  Process {
    id: petCatalogScanner
    command: root.ready
      ? [root.svc.pluginDir + "/bin/rgbsync-pet-install", "--list"]
      : []
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var pet = JSON.parse(String(line || ""))
          if (!pet.path || !pet.name) return
          var next = root.installedPets.slice()
          next.push(pet)
          root.installedPets = next
        } catch (exception) {
          console.warn("rgbsync: bad installed pet record: " + line)
        }
      }
    }
  }

  Process {
    id: petCatalogInstaller
    command: root.ready
      ? [root.svc.pluginDir + "/bin/rgbsync-pet-install",
         root.petIdDraft.trim()]
      : []
    stdout: SplitParser {
      onRead: function(line) {
        var path = String(line || "").trim()
        if (!path || !root.ready) return
        root.svc.setLcdPetPath(path)
        root.svc.addFavoritePet(path)
        root.petInstallStatus = "Installed, selected, and added to favorites."
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var message = String(line || "").trim()
        if (message) root.petInstallStatus = message
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.petInstallStatus === "Installing…") {
        root.petInstallStatus = "OpenPets installation failed."
      }
      root.refreshInstalledPets()
    }
  }

  onOpenedChanged: {
    if (opened && ready) {
      titleDraft = svc.lcdTitle
      topDraft = svc.lcdTop
      bottomDraft = svc.lcdBottom
      root.refreshInstalledPets()
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
    if (svc.lcdPhase === "stream") parts.push("pet")
    else if (svc.busy) parts.push(svc.lcdPhase !== "idle" ? "LCD " + svc.lcdPhase + "…" : "working…")
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
        + " pet=" + root.svc.lcdPet
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
          label: "Animated pet overlay"
          description: "Walk an OpenPets sprite on the wallpaper (CAM stream)."
          checked: root.ready && root.svc.lcdPet
          foreground: root.fg
          fontFamily: root.family
          onClicked: if (root.ready) root.svc.toggleLcdPet()
        }

        Column {
          width: parent.width
          visible: root.ready && root.svc.lcdPet
          spacing: Style.spacing.sm

          PanelSectionHeader {
            width: parent.width
            text: "PET LIBRARY"
            foreground: root.fg
            fontFamily: root.family
          }

          Item {
            id: petPreviewBox
            width: 144
            height: 156
            anchors.horizontalCenter: parent.horizontalCenter

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              clip: true
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
              border.color: root.ready && root.svc.isFavoritePet(root.svc.resolvedPetPath())
                ? root.svc.themeAccent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)
              border.width: 2
              Image {
                id: petSheetPreview
                readonly property int sheetRows:
                  sourceSize.height > sourceSize.width ? 9 : 3
                source: root.ready ? "file://" + root.svc.resolvedPetPath() : ""
                cache: false
                asynchronous: true
                smooth: false
                width: petPreviewBox.width * 8
                height: petPreviewBox.height * sheetRows
                x: -root.petPreviewIndex * petPreviewBox.width
                y: -petPreviewBox.height
              }

              Text {
                anchors.centerIn: parent
                visible: petSheetPreview.status === Image.Error
                text: "Preview unavailable"
                color: Color.muted
                font.family: root.family
                font.pixelSize: Style.font.caption
              }
            }
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.displayPetName(root.ready ? root.svc.resolvedPetPath() : "")
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.font.body
            elide: Text.ElideMiddle
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacing.sm

            Button {
              bordered: true
              text: "Choose file…"
              foreground: root.fg
              fontFamily: root.family
              onClicked: if (!petFilePicker.running) petFilePicker.running = true
            }

            Button {
              bordered: true
              text: root.ready && root.svc.isFavoritePet(root.svc.resolvedPetPath())
                ? "★ Favorite" : "☆ Favorite"
              foreground: root.fg
              fontFamily: root.family
              onClicked: if (root.ready) root.svc.toggleFavoritePet()
            }
          }


          Button {
            visible: root.ready
              && root.svc.resolvedPetPath() !== root.svc.bundledPetPath()
            anchors.horizontalCenter: parent.horizontalCenter
            bordered: true
            text: "Use bundled pet"
            foreground: root.fg
            fontFamily: root.family
            onClicked: if (root.ready) root.svc.setLcdPetPath(
              root.svc.bundledPetPath())
          }
          Row {
            width: parent.width
            spacing: Style.spacing.sm

            TextField {
              width: parent.width - installPetButton.implicitWidth
                - parent.spacing
              text: root.petIdDraft
              placeholderText: "OpenPets ID, e.g. gpt-niang"
              onTextChanged: root.petIdDraft = text
            }

            Button {
              id: installPetButton
              bordered: true
              text: petCatalogInstaller.running ? "Installing…" : "Install"
              enabled: !petCatalogInstaller.running
                && /^[a-z0-9][a-z0-9_-]{0,63}$/.test(root.petIdDraft.trim())
              foreground: root.fg
              fontFamily: root.family
              onClicked: {
                root.petInstallStatus = "Installing…"
                petCatalogInstaller.running = true
              }
            }
          }

          Text {
            width: parent.width
            visible: root.petInstallStatus !== ""
            text: root.petInstallStatus
            color: Color.muted
            font.family: root.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }

          PanelSectionHeader {
            width: parent.width
            visible: root.installedPets.length > 0
            text: "INSTALLED OPENPETS"
            foreground: root.fg
            fontFamily: root.family
          }

          Repeater {
            model: root.installedPets

            Row {
              width: column.width
              spacing: Style.spacing.sm

              Text {
                width: parent.width - useInstalled.implicitWidth
                  - favoriteInstalled.implicitWidth - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name
                color: root.ready && modelData.path === root.svc.resolvedPetPath()
                  ? root.svc.themeAccent : root.fg
                font.family: root.family
                font.pixelSize: Style.font.body
                elide: Text.ElideMiddle
              }

              Button {
                id: useInstalled
                bordered: true
                text: root.ready && modelData.path === root.svc.resolvedPetPath()
                  ? "Active" : "Use"
                enabled: root.ready
                  && modelData.path !== root.svc.resolvedPetPath()
                foreground: root.fg
                fontFamily: root.family
                onClicked: if (root.ready) root.svc.setLcdPetPath(modelData.path)
              }

              Button {
                id: favoriteInstalled
                bordered: true
                text: root.ready && root.svc.isFavoritePet(modelData.path)
                  ? "★" : "☆"
                foreground: root.fg
                fontFamily: root.family
                onClicked: {
                  if (!root.ready) return
                  if (root.svc.isFavoritePet(modelData.path)) {
                    root.svc.removeFavoritePet(modelData.path)
                  } else {
                    root.svc.addFavoritePet(modelData.path)
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.ready && root.svc.lcdPetFavorites.length === 0
            text: "Choose any OpenPets 8-column spritesheet, then star it for one-click access."
            color: Color.muted
            font.family: root.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }

          Repeater {
            model: root.ready ? root.svc.lcdPetFavorites : []

            Row {
              width: column.width
              spacing: Style.spacing.sm

              Text {
                width: parent.width - useFavorite.implicitWidth
                  - removeFavorite.implicitWidth - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                text: root.displayPetName(modelData)
                color: root.ready && modelData === root.svc.resolvedPetPath()
                  ? root.svc.themeAccent : root.fg
                font.family: root.family
                font.pixelSize: Style.font.body
                elide: Text.ElideMiddle
              }

              Button {
                id: useFavorite
                bordered: true
                text: modelData === root.svc.resolvedPetPath() ? "Active" : "Use"
                enabled: modelData !== root.svc.resolvedPetPath()
                foreground: root.fg
                fontFamily: root.family
                onClicked: if (root.ready) root.svc.setLcdPetPath(modelData)
              }

              Button {
                id: removeFavorite
                bordered: true
                text: "Remove"
                foreground: root.fg
                fontFamily: root.family
                onClicked: if (root.ready) root.svc.removeFavoritePet(modelData)
              }
            }
          }
        }

        LabeledSlider {
          width: parent.width
          visible: root.ready && root.svc.lcdPet
          bar: root.bar
          label: "Pet size"
          minimum: 50
          maximum: 250
          step: 5
          value: root.ready ? root.svc.lcdPetScale * 100 : 100
          valueText: root.ready ? Math.round(root.svc.lcdPetScale * 100) + "%" : "100%"
          onMoved: function(value) {
            if (root.ready) root.svc.setLcdPetScale(value / 100, false)
          }
          onReleased: function(value) {
            if (root.ready) root.svc.setLcdPetScale(value / 100, true)
          }
        }

        LabeledSlider {
          width: parent.width
          visible: root.ready && root.svc.lcdPet
          bar: root.bar
          label: "Walk left/right"
          minimum: -220
          maximum: 220
          step: 5
          value: root.ready ? root.svc.lcdPetX : 0
          valueText: root.ready ? Math.round(root.svc.lcdPetX) + " px" : "0 px"
          onMoved: function(value) {
            if (root.ready) root.svc.setLcdPetX(value, false)
          }
          onReleased: function(value) {
            if (root.ready) root.svc.setLcdPetX(value, true)
          }
        }

        LabeledSlider {
          width: parent.width
          visible: root.ready && root.svc.lcdPet
          bar: root.bar
          label: "Walk height"
          minimum: 360
          maximum: 600
          step: 5
          value: root.ready ? root.svc.lcdPetY : 510
          valueText: root.ready ? Math.round(root.svc.lcdPetY) + " px" : "510 px"
          onMoved: function(value) {
            if (root.ready) root.svc.setLcdPetY(value, false)
          }
          onReleased: function(value) {
            if (root.ready) root.svc.setLcdPetY(value, true)
          }
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
