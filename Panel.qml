import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "erick.androidtv-remote"
  ipcTarget: "erick.androidtv-remote"
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property var anchorItem: null
  readonly property var barIdentity: root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color accent: Color.accent

  // Whether user explicitly chose to view the device list even if connected
  property bool forceShowDevices: false
  readonly property bool showRemote: tvState.connected && !forceShowDevices

  // Searching animation state
  property bool isSearching: false

  // TV State loaded from daemon's state.json
  property var tvState: ({
    daemon_running: false,
    connected: false,
    is_on: false,
    current_app: "",
    current_device: "",
    device_name: "",
    volume: { level: 0, max: 100, muted: false },
    pairing_active: false,
    pairing_host: "",
    discovered_devices: [],
    known_devices: [],
    last_error: ""
  })

  // Watch state.json for reactive updates
  property FileView stateFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/androidtv-remote/state.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.reloadState()
  }

  function reloadState() {
    if (!stateFile.text) return
    try {
      var parsed = JSON.parse(stateFile.text)
      if (parsed) {
        root.tvState = parsed
        if (parsed.pairing_active) {
          root.forceShowDevices = true
        }
      }
    } catch (e) {
      // Ignore transient JSON parse errors while writing
    }
  }

  // Trigger automatic search on open
  onOpenedChanged: {
    if (opened) {
      if (!tvState.connected) {
        root.forceShowDevices = true
      }
      root.scanDevices()
    }
  }

  function scanDevices() {
    root.isSearching = true
    searchTimer.restart()
    runCli(["discover"])
  }

  Timer {
    id: searchTimer
    interval: 2000
    onTriggered: root.isSearching = false
  }

  // Helper to run CLI commands
  readonly property string cliPath: Quickshell.env("HOME") + "/repos/tv-remote-controll/bin/omarchy-androidtv-remote"

  function runCli(args) {
    var p = cliComponent.createObject(root, {
      command: [root.cliPath].concat(args)
    })
    p.running = true
  }

  Component {
    id: cliComponent
    Process {
      onExited: destroy()
    }
  }

  // Remote key action
  function sendKey(key) {
    runCli(["key", key])
  }

  // App launch action
  function launchApp(app) {
    runCli(["app", app])
  }

  // Bar icon styling
  readonly property bool isTvActive: tvState.connected && tvState.is_on

  // Status text for tooltip
  readonly property string barTooltip: {
    if (!tvState.daemon_running) return "Android TV: Desconectado"
    if (tvState.pairing_active) return "Android TV: Pareando..."
    if (!tvState.connected) return "Android TV: Desconectado"
    var name = tvState.device_name || tvState.current_device || "TV"
    return "Android TV: " + name + (tvState.is_on ? " (Ligada)" : " (Standby)")
  }

  // Bar button representation
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰟴" // Nerd Font TV icon
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.icon
    tooltipText: root.barTooltip
    active: root.isTvActive
    activeColor: Color.accent
    dimmed: !root.isTvActive

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        // Right click: toggle power
        root.sendKey("POWER")
      } else if (buttonCode === Qt.MiddleButton) {
        // Middle click: toggle mute
        root.sendKey("MUTE")
      } else {
        root.toggle()
      }
    }
  }

  // Main Popup Panel
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(350))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Block key capture if user is typing in any text field
      blocked: (textInputField && textInputField.activeFocus) || (pinInputField && pinInputField.activeFocus) || (manualIpField && manualIpField.activeFocus)

      onMoveRequested: function(dx, dy) {
        if (!root.showRemote) return
        if (dy < 0) root.sendKey("UP")
        else if (dy > 0) root.sendKey("DOWN")
        else if (dx < 0) root.sendKey("LEFT")
        else if (dx > 0) root.sendKey("RIGHT")
      }
      onActivateRequested: {
        if (root.showRemote) root.sendKey("OK")
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      onTextKey: function(t) {
        if (!root.showRemote) return
        if (t === "h" || t === "H") root.sendKey("HOME")
        else if (t === "m" || t === "M") root.sendKey("MUTE")
        else if (t === "p" || t === "P" || t === " ") root.sendKey("PLAY_PAUSE")
        else if (t === "+") root.sendKey("VOL_UP")
        else if (t === "-") root.sendKey("VOL_DOWN")
        else if (t === "b" || t === "B") root.sendKey("BACK")
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: mainColumn
          width: parent.width
          spacing: Style.space(12)

          // =========================================================
          // VIEW 1: DISCOVERY & DEVICE LIST (Shown before opening remote)
          // =========================================================
          Column {
            id: devicesView
            width: parent.width
            visible: !root.showRemote
            spacing: Style.space(10)

            // Header for Device List
            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: "󰟴"
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                color: Color.accent
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - scanBtn.width - Style.space(16)
                Text {
                  text: "Selecionar Android TV"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }
                Text {
                  text: root.isSearching ? "Buscando TVs na sua rede..." : "TVs disponíveis na rede local"
                  color: Qt.darker(root.foreground, 1.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Button {
                id: scanBtn
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰑐"
                iconSpinning: root.isSearching
                tooltipText: "Escanear novamente"
                fontSize: Style.font.body
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(4)
                onClicked: root.scanDevices()
              }
            }

            // Return to Remote button (if currently connected to a TV)
            Button {
              width: parent.width
              visible: root.tvState.connected
              text: "Voltar ao Controle: " + (root.tvState.device_name || root.tvState.current_device)
              iconText: "󰁔"
              active: true
              accent: Color.accent
              onClicked: root.forceShowDevices = false
            }

            // PAIRING CARD (Visible when pairing is active)
            BorderSurface {
              width: parent.width
              visible: root.tvState.pairing_active
              color: Style.hoverFillFor(root.foreground, Color.accent)
              borderSpec: Border.controlSpec("focus", Color.accent, Color.accent)
              radius: Style.cornerRadius
              topPadding: Style.space(10)
              bottomPadding: Style.space(10)
              leftPadding: Style.space(12)
              rightPadding: Style.space(12)

              Column {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  text: "Pareamento com " + (root.tvState.pairing_host || "TV")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  text: "Digite o código PIN exibido na tela da sua TV:"
                  color: Qt.darker(root.foreground, 1.3)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Row {
                  width: parent.width
                  spacing: Style.space(6)

                  TextField {
                    id: pinInputField
                    width: parent.width - confirmPinBtn.width - cancelPinBtn.width - Style.space(12)
                    placeholderText: "Código (ex: 1A2B3C)"
                    font.capitalization: Font.AllUppercase
                    onAccepted: {
                      if (text.length > 0) {
                        root.runCli(["pair-finish", text])
                        root.forceShowDevices = false
                      }
                    }
                  }

                  Button {
                    id: confirmPinBtn
                    text: "OK"
                    accent: Color.accent
                    active: true
                    onClicked: {
                      if (pinInputField.text.length > 0) {
                        root.runCli(["pair-finish", pinInputField.text])
                        root.forceShowDevices = false
                      }
                    }
                  }

                  Button {
                    id: cancelPinBtn
                    text: "Cancelar"
                    onClicked: root.runCli(["pair-cancel"])
                  }
                }
              }
            }

            // LIST OF DISCOVERED TVS
            Text {
              text: "DISPOSITIVOS ENCONTRADOS (" + (root.tvState.discovered_devices ? root.tvState.discovered_devices.length : 0) + ")"
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.1
              visible: root.tvState.discovered_devices && root.tvState.discovered_devices.length > 0
            }

            Repeater {
              model: root.tvState.discovered_devices || []
              delegate: BorderSurface {
                id: devCard
                width: parent.width
                implicitHeight: Style.space(52)
                color: mouseArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                borderSpec: Border.controlSpec(mouseArea.containsMouse ? "hover-cursor" : "normal", root.foreground, Color.accent)
                radius: Style.cornerRadius
                leftPadding: Style.space(10)
                rightPadding: Style.space(10)

                MouseArea {
                  id: mouseArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (Model.isDevicePaired(root.tvState.known_devices, modelData.host)) {
                      root.runCli(["connect", modelData.host])
                      root.forceShowDevices = false
                    } else {
                      root.runCli(["pair-start", modelData.host])
                    }
                  }
                }

                Row {
                  anchors.fill: parent
                  spacing: Style.space(10)

                  Text {
                    text: "󰟴"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    color: Color.accent
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - actionBtn.width - Style.space(42)

                    Text {
                      text: modelData.name || modelData.host
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                      width: parent.width
                    }

                    Text {
                      text: (modelData.model ? modelData.model + " • " : "") + modelData.host
                      color: Qt.darker(root.foreground, 1.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Button {
                    id: actionBtn
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.isDevicePaired(root.tvState.known_devices, modelData.host) ? "Conectar" : "Parear"
                    accent: Color.accent
                    active: true
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(10)
                    verticalPadding: Style.space(4)
                    onClicked: {
                      if (Model.isDevicePaired(root.tvState.known_devices, modelData.host)) {
                        root.runCli(["connect", modelData.host])
                        root.forceShowDevices = false
                      } else {
                        root.runCli(["pair-start", modelData.host])
                      }
                    }
                  }
                }
              }
            }

            // Empty state if no TVs found yet
            BorderSurface {
              width: parent.width
              visible: (!root.tvState.discovered_devices || root.tvState.discovered_devices.length === 0) && !root.tvState.pairing_active
              color: Style.hoverFillFor(root.foreground, Color.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              radius: Style.cornerRadius
              topPadding: Style.space(16)
              bottomPadding: Style.space(16)
              leftPadding: Style.space(14)
              rightPadding: Style.space(14)

              Column {
                width: parent.width
                spacing: Style.space(6)
                anchors.centerIn: parent

                Text {
                  text: root.isSearching ? "Buscando TVs na rede..." : "Nenhuma TV encontrada automaticamente"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                }

                Text {
                  text: root.isSearching ? "Aguarde alguns instantes enquanto escaneamos o Wi-Fi." : "Certifique-se de que a TV está ligada na mesma rede ou insira o IP abaixo:"
                  color: Qt.darker(root.foreground, 1.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                  width: parent.width
                }
              }
            }

            PanelSeparator { width: parent.width }

            // Manual IP connection
            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "CONEXÃO MANUAL POR IP"
                color: Qt.darker(root.foreground, 1.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.1
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: manualIpField
                  width: parent.width - manualPairBtn.width - manualConnectBtn.width - Style.space(12)
                  placeholderText: "IP da TV (ex: 192.168.1.50)"
                  font.pixelSize: Style.font.caption
                  onAccepted: {
                    if (text.length > 0) {
                      root.runCli(["connect", text])
                      root.forceShowDevices = false
                    }
                  }
                }

                Button {
                  id: manualConnectBtn
                  text: "Conectar"
                  fontSize: Style.font.caption
                  onClicked: {
                    if (manualIpField.text.length > 0) {
                      root.runCli(["connect", manualIpField.text])
                      root.forceShowDevices = false
                    }
                  }
                }

                Button {
                  id: manualPairBtn
                  text: "Parear"
                  fontSize: Style.font.caption
                  onClicked: {
                    if (manualIpField.text.length > 0) {
                      root.runCli(["pair-start", manualIpField.text])
                    }
                  }
                }
              }
            }
          }

          // =========================================================
          // VIEW 2: REMOTE CONTROL VIEW (Shown when TV is selected & connected)
          // =========================================================
          Column {
            id: remoteView
            width: parent.width
            visible: root.showRemote
            spacing: Style.space(12)

            // 1. HERO HEADER WITH "SWITCH TV" BUTTON
            Row {
              width: parent.width
              spacing: Style.space(6)

              Button {
                text: "TVs"
                iconText: "󰁮"
                tooltipText: "Selecionar outra TV"
                fontSize: Style.font.caption
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.forceShowDevices = true
              }

              PanelHero {
                width: parent.width - parent.children[0].width - Style.space(6)
                foreground: root.foreground
                fontFamily: root.fontFamily
                title: root.tvState.device_name || (root.tvState.current_device || "Android TV")
                meta: Model.statusDescription(root.tvState)
                detail: (root.tvState.connected && root.tvState.is_on && root.tvState.volume) 
                        ? ("Vol " + root.tvState.volume.level + (root.tvState.volume.muted ? " (Mudo)" : ""))
                        : ""
                iconComponent: Component {
                  Text {
                    text: "󰟴"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    color: root.tvState.connected && root.tvState.is_on ? Color.accent : Qt.darker(root.foreground, 1.8)
                  }
                }
                trailingControl: Component {
                  PanelActionButton {
                    iconText: "󰐥"
                    tooltipText: root.tvState.is_on ? "Desligar TV" : "Ligar TV"
                    foreground: root.tvState.is_on ? "#2ecc71" : root.foreground
                    hoverColor: root.tvState.is_on ? "#e74c3c" : "#2ecc71"
                    fontFamily: root.fontFamily
                    fontSize: Style.font.heading
                    onClicked: root.sendKey("POWER")
                  }
                }
              }
            }

            PanelSeparator { width: parent.width }

            // 2. TOP QUICK ACTION BUTTONS (Back, Home, Settings, Menu)
            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                width: (parent.width - Style.space(24)) / 4
                iconText: "󰁮"
                text: "Voltar"
                tooltipText: "Voltar (Esc / Backspace)"
                onClicked: root.sendKey("BACK")
              }

              Button {
                width: (parent.width - Style.space(24)) / 4
                iconText: "󰋜"
                text: "Início"
                tooltipText: "Tela Inicial (H)"
                onClicked: root.sendKey("HOME")
              }

              Button {
                width: (parent.width - Style.space(24)) / 4
                iconText: "󰒓"
                text: "Ajustes"
                tooltipText: "Configurações"
                onClicked: root.sendKey("SETTINGS")
              }

              Button {
                width: (parent.width - Style.space(24)) / 4
                iconText: "󰍜"
                text: "Menu"
                tooltipText: "Menu / Entrada"
                onClicked: root.sendKey("MENU")
              }
            }

            // 3. D-PAD DIRECTIONAL CONTROLLER
            Item {
              width: parent.width
              height: Style.space(170)

              Item {
                width: Style.space(170)
                height: Style.space(170)
                anchors.centerIn: parent

                BorderSurface {
                  anchors.fill: parent
                  radius: width / 2
                  color: Style.hoverFillFor(root.foreground, Color.accent)
                  borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
                }

                // UP
                Button {
                  width: Style.space(50)
                  height: Style.space(46)
                  anchors.top: parent.top
                  anchors.horizontalCenter: parent.horizontalCenter
                  iconText: "󰁝"
                  fontSize: Style.font.title
                  onClicked: root.sendKey("UP")
                }

                // DOWN
                Button {
                  width: Style.space(50)
                  height: Style.space(46)
                  anchors.bottom: parent.bottom
                  anchors.horizontalCenter: parent.horizontalCenter
                  iconText: "󰁅"
                  fontSize: Style.font.title
                  onClicked: root.sendKey("DOWN")
                }

                // LEFT
                Button {
                  width: Style.space(46)
                  height: Style.space(50)
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰁍"
                  fontSize: Style.font.title
                  onClicked: root.sendKey("LEFT")
                }

                // RIGHT
                Button {
                  width: Style.space(46)
                  height: Style.space(50)
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰁔"
                  fontSize: Style.font.title
                  onClicked: root.sendKey("RIGHT")
                }

                // CENTER / OK
                Button {
                  width: Style.space(58)
                  height: Style.space(58)
                  anchors.centerIn: parent
                  radius: width / 2
                  text: "OK"
                  active: true
                  accent: Color.accent
                  fontSize: Style.font.body
                  onClicked: root.sendKey("OK")
                }
              }
            }

            // 4. VOLUME & MEDIA CONTROLS
            Row {
              width: parent.width
              spacing: Style.space(8)

              // Volume Group
              Row {
                width: (parent.width - Style.space(8)) / 2
                spacing: Style.space(4)

                Button {
                  width: (parent.width - Style.space(8)) / 3
                  iconText: "󰝝"
                  tooltipText: "Volume -"
                  onClicked: root.sendKey("VOL_DOWN")
                }

                Button {
                  width: (parent.width - Style.space(8)) / 3
                  iconText: root.tvState.volume && root.tvState.volume.muted ? "󰝟" : "󰕾"
                  active: root.tvState.volume && root.tvState.volume.muted
                  tooltipText: "Mudo (M)"
                  onClicked: root.sendKey("MUTE")
                }

                Button {
                  width: (parent.width - Style.space(8)) / 3
                  iconText: "󰕾"
                  tooltipText: "Volume +"
                  onClicked: root.sendKey("VOL_UP")
                }
              }

              // Media Group
              Row {
                width: (parent.width - Style.space(8)) / 2
                spacing: Style.space(4)

                Button {
                  width: (parent.width - Style.space(8)) / 3
                  iconText: "󰒮"
                  tooltipText: "Anterior"
                  onClicked: root.sendKey("PREV")
                }

                Button {
                  width: (parent.width - Style.space(8)) / 3
                  iconText: "󰐊"
                  tooltipText: "Play / Pause (Espaço)"
                  onClicked: root.sendKey("PLAY_PAUSE")
                }

                Button {
                  width: (parent.width - Style.space(8)) / 3
                  iconText: "󰒭"
                  tooltipText: "Próximo"
                  onClicked: root.sendKey("NEXT")
                }
              }
            }

            // 5. APP SHORTCUTS
            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "APLICATIVOS"
                color: Qt.darker(root.foreground, 1.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.1
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                Button {
                  width: (parent.width - Style.space(12)) / 3
                  iconText: "󰗃"
                  text: "YouTube"
                  fontSize: Style.font.caption
                  onClicked: root.launchApp("youtube")
                }

                Button {
                  width: (parent.width - Style.space(12)) / 3
                  iconText: "󰝆"
                  text: "Netflix"
                  fontSize: Style.font.caption
                  onClicked: root.launchApp("netflix")
                }

                Button {
                  width: (parent.width - Style.space(12)) / 3
                  iconText: "󰝆"
                  text: "Prime"
                  fontSize: Style.font.caption
                  onClicked: root.launchApp("prime")
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                Button {
                  width: (parent.width - Style.space(12)) / 3
                  iconText: "󰓇"
                  text: "Spotify"
                  fontSize: Style.font.caption
                  onClicked: root.launchApp("spotify")
                }

                Button {
                  width: (parent.width - Style.space(12)) / 3
                  iconText: "󰕧"
                  text: "Twitch"
                  fontSize: Style.font.caption
                  onClicked: root.launchApp("twitch")
                }

                Button {
                  width: (parent.width - Style.space(12)) / 3
                  iconText: "󰝆"
                  text: "Disney+"
                  fontSize: Style.font.caption
                  onClicked: root.launchApp("disney")
                }
              }
            }

            // 6. TEXT INPUT TO TV
            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: "DIGITAR NA TV"
                color: Qt.darker(root.foreground, 1.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.1
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: textInputField
                  width: parent.width - sendTextBtn.width - Style.space(6)
                  placeholderText: "Digitar texto na TV..."
                  onAccepted: {
                    if (text.length > 0) {
                      root.runCli(["text", text])
                      text = ""
                    }
                  }
                }

                Button {
                  id: sendTextBtn
                  iconText: "󰒍"
                  tooltipText: "Enviar texto"
                  accent: Color.accent
                  onClicked: {
                    if (textInputField.text.length > 0) {
                      root.runCli(["text", textInputField.text])
                      textInputField.text = ""
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
