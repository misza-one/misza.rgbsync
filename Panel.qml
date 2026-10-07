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
  property string petSearchDraft: ""
  property string petInstallStatus: ""
  property string petRemoveId: ""
  property var installedPets: []
  property var catalogPets: []
  property bool petSearchPending: false
  property bool installedPetsExpanded: false
  property bool petActionsExpanded: false

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

  function installedPetPath(id) {
    for (var i = 0; i < root.installedPets.length; i++) {
      if (root.installedPets[i].id === id) return root.installedPets[i].path
    }
    return ""
  }

  function isInstalledPetPath(path) {
    for (var i = 0; i < root.installedPets.length; i++) {
      if (root.installedPets[i].path === path) return true
    }
    return false
  }

  function localFavoritePets() {
    var out = []
    if (!root.ready) return out
    for (var i = 0; i < root.svc.lcdPetFavorites.length; i++) {
      var path = root.svc.lcdPetFavorites[i]
      if (!root.isInstalledPetPath(path)) out.push(path)
    }
    return out
  }

  function orderedInstalledPets() {
    var pets = root.installedPets.slice()
    if (!root.ready) return pets
    var active = root.svc.resolvedPetPath()
    var recent = root.svc.lcdPetFavorites
    pets.sort(function(a, b) {
      if (a.path === active) return -1
      if (b.path === active) return 1
      var ai = recent.indexOf(a.path)
      var bi = recent.indexOf(b.path)
      if (ai === -1) ai = 100000
      if (bi === -1) bi = 100000
      if (ai !== bi) return ai - bi
      return String(a.name).localeCompare(String(b.name))
    })
    return pets
  }


  function previewPetRow() {
    if (!root.ready || root.svc.lcdPetMood === "idle") return 1
    if (root.svc.lcdPetMood === "blocked") return 6
    if (root.svc.lcdPetMood === "done") return 3
    if (root.svc.lcdPetMood === "working") return 8
    return 1
  }

  function previewPetFrameCount() {
    if (!root.ready) return 8
    if (root.svc.lcdPetMood === "done") return 5
    if (root.svc.lcdPetMood === "blocked") return 6
    return 8
  }

  function searchPets() {
    if (!root.ready) return
    if (petCatalogSearch.running) {
      root.petSearchPending = true
      return
    }
    root.petSearchPending = false
    root.catalogPets = []
    root.petInstallStatus = root.petSearchDraft.trim() === ""
      ? "Loading featured pets…" : "Searching OpenPets…"
    petCatalogSearch.command = [
      root.svc.pluginDir + "/bin/rgbsync-pet-install",
      "--search", root.petSearchDraft.trim()
    ]
    petCatalogSearch.running = true
  }

  Timer {
    id: petSearchDebounce
    interval: 280
    onTriggered: root.searchPets()
  }

  Timer {
    interval: 120
    repeat: true
    running: root.opened && root.ready && root.svc.lcdPet
    onTriggered: root.petPreviewIndex =
      (root.petPreviewIndex + 1) % root.previewPetFrameCount()
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
    id: petCatalogSearch
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var pet = JSON.parse(String(line || ""))
          if (!pet.id || !pet.name) return
          var next = root.catalogPets.slice()
          next.push(pet)
          root.catalogPets = next
        } catch (exception) {
          console.warn("rgbsync: bad catalog pet record: " + line)
        }
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var message = String(line || "").trim()
        if (message) root.petInstallStatus = message
      }
    }
    onExited: function(exitCode) {
      if (root.petSearchPending) {
        root.searchPets()
        return
      }
      if (exitCode === 0) {
        root.petInstallStatus = root.catalogPets.length > 0
          ? "" : "No pets match that search."
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
      root.searchPets()
    }
  }

  Process {
    id: petCatalogRemover
    command: root.ready
      ? [root.svc.pluginDir + "/bin/rgbsync-pet-install",
         "--remove", root.petRemoveId]
      : []
    stdout: SplitParser {
      onRead: function(line) {}
    }
    stderr: SplitParser {
      onRead: function(line) {
        var message = String(line || "").trim()
        if (message) root.petInstallStatus = message
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.petInstallStatus = "Pet removed."
      root.petRemoveId = ""
      root.refreshInstalledPets()
      root.searchPets()
    }
  }

  onOpenedChanged: {
    if (opened && ready) {
      titleDraft = svc.lcdTitle
      topDraft = svc.lcdTop
      bottomDraft = svc.lcdBottom
      root.refreshInstalledPets()
      root.searchPets()
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

    function pets(): void {
      root.open()
      Qt.callLater(function() {
        scroll.contentItem.contentY = Math.max(0, petLibrary.y - Style.space(8))
      })
    }


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
          id: petLibrary
          width: parent.width
          visible: root.ready
          spacing: Style.spacing.sm

          PanelSectionHeader {
            width: parent.width
            text: "PET"
            foreground: root.fg
            fontFamily: root.family
          }

          Rectangle {
            width: parent.width
            height: 116
            radius: Style.cornerRadius
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.055)
            border.color: Qt.rgba(root.svc.themeAccent.r, root.svc.themeAccent.g,
                                  root.svc.themeAccent.b, 0.45)

            Row {
              anchors.fill: parent
              anchors.margins: Style.spacing.sm
              spacing: Style.spacing.sm

              Rectangle {
                id: petPreviewBox
                width: 88
                height: 96
                anchors.verticalCenter: parent.verticalCenter
                radius: Style.cornerRadius
                clip: true
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)

                Image {
                  id: petSheetPreview
                  readonly property int sheetRows:
                    sourceSize.height > sourceSize.width ? 9 : 3
                  readonly property real frameWidth: 72
                  readonly property real frameHeight: 96
                  source: "file://" + root.svc.resolvedPetPath()
                  cache: false
                  asynchronous: true
                  smooth: false
                  width: frameWidth * 8
                  height: frameHeight * sheetRows
                  x: (petPreviewBox.width - frameWidth) / 2
                    - root.petPreviewIndex * frameWidth
                  y: -(sheetRows >= 9 ? root.previewPetRow() : 1) * frameHeight
                }

                Text {
                  anchors.centerIn: parent
                  visible: petSheetPreview.status === Image.Error
                  text: "No preview"
                  color: Color.muted
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                }
              }

              Column {
                width: parent.width - petPreviewBox.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xs

                Text {
                  width: parent.width
                  text: root.displayPetName(root.svc.resolvedPetPath())
                  color: root.fg
                  font.family: root.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: root.svc.lcdPetReactToOmaherd
                    ? root.svc.lcdPetMoodLabel : "Walking"
                  color: root.svc.lcdPetMood === "blocked"
                    ? Color.urgent : Color.muted
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                Button {
                  bordered: false
                  text: root.petActionsExpanded ? "Hide options" : "More…"
                  foreground: root.fg
                  fontFamily: root.family
                  onClicked: root.petActionsExpanded = !root.petActionsExpanded
                }

                Row {
                  visible: root.petActionsExpanded
                  spacing: Style.spacing.xs

                  Button {
                    bordered: true
                    text: "Choose file…"
                    foreground: root.fg
                    fontFamily: root.family
                    onClicked: if (!petFilePicker.running) petFilePicker.running = true
                  }

                  Button {
                    visible: !root.isInstalledPetPath(root.svc.resolvedPetPath())
                      && root.svc.resolvedPetPath() !== root.svc.bundledPetPath()
                    bordered: true
                    text: root.svc.isFavoritePet(root.svc.resolvedPetPath())
                      ? "Saved" : "Save"
                    foreground: root.fg
                    fontFamily: root.family
                    onClicked: root.svc.toggleFavoritePet()
                  }

                  Button {
                    visible: root.svc.resolvedPetPath() !== root.svc.bundledPetPath()
                    bordered: true
                    text: "Reset pet"
                    foreground: root.fg
                    fontFamily: root.family
                    onClicked: {
                      root.svc.setLcdPetPath(root.svc.bundledPetPath())
                      root.petActionsExpanded = false
                    }
                  }
                }
              }
            }
          }

          Button {
            width: parent.width
            visible: root.installedPets.length > 0
            bordered: false
            text: (root.installedPetsExpanded ? "▾  " : "›  ")
              + "MY PETS · " + root.installedPets.length
            foreground: root.fg
            fontFamily: root.family
            onClicked: root.installedPetsExpanded = !root.installedPetsExpanded
          }

          Repeater {
            model: root.installedPetsExpanded ? root.orderedInstalledPets() : []

            Rectangle {
              width: column.width
              height: 54
              radius: Style.cornerRadius
              color: modelData.path === root.svc.resolvedPetPath()
                ? Qt.rgba(root.svc.themeAccent.r, root.svc.themeAccent.g,
                          root.svc.themeAccent.b, 0.10)
                : "transparent"

              Row {
                anchors.fill: parent
                anchors.margins: Style.spacing.xs
                spacing: Style.spacing.xs

                Rectangle {
                  id: installedPreview
                  width: 44
                  height: 44
                  anchors.verticalCenter: parent.verticalCenter
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)

                  Image {
                    anchors.fill: parent
                    anchors.margins: 2
                    source: modelData.thumbnail
                      ? "file://" + modelData.thumbnail : ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    smooth: false
                  }
                }

                Text {
                  width: parent.width - installedPreview.width
                    - useInstalled.implicitWidth - deleteInstalled.implicitWidth
                    - parent.spacing * 3
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.name
                  color: modelData.path === root.svc.resolvedPetPath()
                    ? root.svc.themeAccent : root.fg
                  font.family: root.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Button {
                  id: useInstalled
                  anchors.verticalCenter: parent.verticalCenter
                  bordered: true
                  text: modelData.path === root.svc.resolvedPetPath() ? "Active" : "Use"
                  enabled: modelData.path !== root.svc.resolvedPetPath()
                  foreground: root.fg
                  fontFamily: root.family
                  onClicked: root.svc.setLcdPetPath(modelData.path)
                }

                Button {
                  id: deleteInstalled
                  anchors.verticalCenter: parent.verticalCenter
                  bordered: true
                  text: "Delete"
                  enabled: !petCatalogRemover.running
                  foreground: root.fg
                  fontFamily: root.family
                  onClicked: {
                    if (petCatalogRemover.running) return
                    if (modelData.path === root.svc.resolvedPetPath()) {
                      root.svc.setLcdPetPath(root.svc.bundledPetPath())
                    }
                    root.svc.removeFavoritePet(modelData.path)
                    root.petRemoveId = modelData.id
                    root.petInstallStatus = "Removing " + modelData.name + "…"
                    petCatalogRemover.running = true
                  }
                }
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.spacing.xs

            PanelSectionHeader {
              width: parent.width - openPetsLink.implicitWidth - parent.spacing
              text: "FIND A PET"
              foreground: root.fg
              fontFamily: root.family
            }

            Button {
              id: openPetsLink
              bordered: false
              text: "openpets.dev ↗"
              foreground: root.svc.themeAccent
              fontFamily: root.family
              onClicked: Qt.openUrlExternally("https://openpets.dev")
            }
          }

          TextField {
            width: parent.width
            text: root.petSearchDraft
            placeholderText: "Search by name, character, or style…"
            onTextChanged: {
              root.petSearchDraft = text
              petSearchDebounce.restart()
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
          }

          Repeater {
            model: root.catalogPets

            Rectangle {
              width: column.width
              height: 58
              radius: Style.cornerRadius
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.035)

              Row {
                anchors.fill: parent
                anchors.margins: Style.spacing.xs
                spacing: Style.spacing.sm

                Image {
                  width: 44
                  height: 44
                  anchors.verticalCenter: parent.verticalCenter
                  source: modelData.thumbnail
                  asynchronous: true
                  fillMode: Image.PreserveAspectFit
                  smooth: false
                }

                Column {
                  width: parent.width - 44 - catalogInstall.implicitWidth
                    - parent.spacing * 2
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 1

                  Text {
                    width: parent.width
                    text: modelData.name
                    color: root.fg
                    font.family: root.family
                    font.pixelSize: Style.font.body
                    font.bold: modelData.featured === true
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: (root.installedPetPath(modelData.id) !== ""
                        ? "Installed · " : "")
                      + (modelData.original ? "Original · " : "")
                      + (modelData.subcategory || modelData.category || "OpenPets")
                    color: Color.muted
                    font.family: root.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Button {
                  id: catalogInstall
                  anchors.verticalCenter: parent.verticalCenter
                  bordered: true
                  readonly property string installedPath:
                    root.installedPetPath(modelData.id)
                  text: installedPath !== ""
                    ? (installedPath === root.svc.resolvedPetPath() ? "Active" : "Use")
                    : (petCatalogInstaller.running
                        && root.petIdDraft === modelData.id ? "Installing…" : "Install")
                  enabled: !petCatalogInstaller.running
                    && installedPath !== root.svc.resolvedPetPath()
                  foreground: root.fg
                  fontFamily: root.family
                  onClicked: {
                    if (installedPath !== "") {
                      root.svc.setLcdPetPath(installedPath)
                      return
                    }
                    root.petIdDraft = modelData.id
                    root.petInstallStatus = "Installing " + modelData.name + "…"
                    petCatalogInstaller.running = true
                  }
                }
              }
            }
          }


          PanelSectionHeader {
            width: parent.width
            visible: root.localFavoritePets().length > 0
            text: "SAVED FILES"
            foreground: root.fg
            fontFamily: root.family
          }

          Repeater {
            model: root.localFavoritePets()

            Row {
              width: column.width
              spacing: Style.spacing.xs

              Text {
                width: parent.width - useFavorite.implicitWidth
                  - removeFavorite.implicitWidth - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                text: root.displayPetName(modelData)
                color: modelData === root.svc.resolvedPetPath()
                  ? root.svc.themeAccent : root.fg
                font.family: root.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Button {
                id: useFavorite
                bordered: true
                text: modelData === root.svc.resolvedPetPath() ? "Active" : "Use"
                enabled: modelData !== root.svc.resolvedPetPath()
                foreground: root.fg
                fontFamily: root.family
                onClicked: root.svc.setLcdPetPath(modelData)
              }

              Button {
                id: removeFavorite
                bordered: true
                text: "Forget"
                foreground: root.fg
                fontFamily: root.family
                onClicked: root.svc.removeFavoritePet(modelData)
              }
            }
          }
        }

        Toggle {
          width: parent.width
          visible: root.ready && root.svc.lcdPet
          label: "React to Omaherd agents"
          description: root.ready
            ? root.svc.lcdPetMoodLabel
            : "Waiting, working, and completed agents change the animation."
          checked: root.ready && root.svc.lcdPetReactToOmaherd
          foreground: root.fg
          fontFamily: root.family
          onClicked: if (root.ready) {
            root.svc.setLcdPetReactToOmaherd(!root.svc.lcdPetReactToOmaherd)
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
                  ? "file://" + root.svc.backgroundPath + "?theme="
                    + root.svc.currentThemeName + "&revision=" + root.svc.backgroundRevision
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
