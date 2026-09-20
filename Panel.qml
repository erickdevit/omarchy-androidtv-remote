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

  // User can force returning to the TV list even if a TV is connected
  property bool forceDeviceList: false
  
  // VIEW MODE: "remote" ONLY if connected and not forcing device list; otherwise "devices"
  readonly property string currentView: (tvState.connected && !forceDeviceList) ? "remote" : "devices"

  // Searching state
  property bool isSearching: false

  // Fallback manual IP visibility (only shown if user clicks or no TVs found)
  property bool showManualIpFallback: false

  // Explicit discovered devices list for reactive QML bindings
  property var discoveredDevices: []

  // Paired devices list computed from tvState.known_devices
  readonly property var pairedDevices: {
    var list = []
    if (tvState && tvState.known_devices && Array.isArray(tvState.known_devices)) {
      for (var i = 0; i < tvState.known_devices.length; i++) {
        var d = tvState.known_devices[i]
        if (d && d.paired) {
          list.push(d)
        }
      }
    }
    return list
  }

  // Unpaired / available devices list (discovered devices that are not yet paired)
  readonly property var unpairedDevices: {
    var list = []
    var pairedHosts = {}
    for (var p = 0; p < pairedDevices.length; p++) {
      pairedHosts[pairedDevices[p].host] = true
    }
    if (discoveredDevices && Array.isArray(discoveredDevices)) {
      for (var i = 0; i < discoveredDevices.length; i++) {
        var dev = discoveredDevices[i]
        if (dev && dev.host && !pairedHosts[dev.host]) {
          list.push(dev)
        }
      }
    }
    return list
  }

  // Pairing in progress state
  property bool isPairingStarting: false

  Timer {
    id: pairingResetTimer
    interval: 3500
    onTriggered: root.isPairingStarting = false
  }

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
    ime_active: false,
    ime_label: "",
    discovered_devices: [],
    known_devices: [],
    last_error: ""
  })

  property bool imeActive: false
  property string imeLabel: ""

  // Watch state.json for reactive updates
  property FileView stateFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/androidtv-remote/state.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.reloadState()
    onFileChanged: reload()
  }

  function applyState(data) {
    if (!data) return
    root.tvState = data
    root.imeActive = (data.ime_active === true)
    root.imeLabel = data.ime_label || ""
    if (data.discovered_devices && Array.isArray(data.discovered_devices)) {
      root.discoveredDevices = data.discovered_devices
    }
    if (data.pairing_active) {
      root.forceDeviceList = true
      root.isPairingStarting = false
    }
    if (data.last_error) {
      root.isPairingStarting = false
    }
    if (root.imeActive && textInputField) {
      textInputField.forceActiveFocus()
    }
  }

  function reloadState() {
    var raw = ""
    try {
      if (typeof stateFile.text === "function") {
        raw = stateFile.text()
      } else if (typeof stateFile.text === "string") {
        raw = stateFile.text
      }
    } catch (e) {
      console.warn("[AndroidTV] Error reading stateFile:", e)
    }

    if (raw && raw.length > 0) {
      try {
        var parsed = JSON.parse(raw)
        if (parsed) {
          root.applyState(parsed)
        }
      } catch (e) {
        // Ignore transient JSON parse errors while writing
      }
    }
  }

  // Fallback status process to guarantee immediate sync
  Process {
    id: statusProc
    command: [root.cliPath, "status"]
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && statusOut.text) {
        try {
          var parsed = JSON.parse(statusOut.text)
          if (parsed) {
            root.applyState(parsed)
          }
        } catch (e) {}
      }
    }
  }

  // Ensure daemon is started on load and scan on open
  Component.onCompleted: {
    statusProc.running = true
    runCli(["start-daemon", "discover"])
  }

  onOpenedChanged: {
    if (opened) {
      if (!tvState.connected) {
        root.forceDeviceList = true
      }
      statusProc.running = true
      root.scanDevices()
    }
  }

  function scanDevices() {
    root.isSearching = true
    searchTimer.restart()
    statusProc.running = true
    runCli(["discover"])
  }

  Timer {
    id: searchTimer
    interval: 2500
    onTriggered: {
      root.isSearching = false
      statusProc.running = true
    }
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
        root.sendKey("POWER")
      } else if (buttonCode === Qt.MiddleButton) {
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight + Style.space(16), Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Block key capture if user is typing in any text field
      blocked: (textInputField && textInputField.activeFocus) || 
               (pinInputField && pinInputField.activeFocus) || 
               (manualIpField && manualIpField.activeFocus)

      onMoveRequested: function(dx, dy) {
        if (root.currentView !== "remote") return
        if (dy < 0) root.sendKey("UP")
        else if (dy > 0) root.sendKey("DOWN")
        else if (dx < 0) root.sendKey("LEFT")
        else if (dx > 0) root.sendKey("RIGHT")
      }
      onActivateRequested: {
        if (root.currentView === "remote") root.sendKey("OK")
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      onTextKey: function(t) {
        if (root.currentView !== "remote") return
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
          width: panelFlick.width
          spacing: Style.space(14)
          topPadding: Style.space(6)
          bottomPadding: Style.space(14)

          // ===================================================================
          // VIEW 1: LISTA DE DISPOSITIVOS (Exibida antes de abrir o controle)
          // ===================================================================
          Column {
            id: devicesView
            width: parent.width
            visible: root.currentView === "devices"
            spacing: Style.space(12)

            // Header da Lista de TVs com PanelHero
            PanelHero {
              width: parent.width
              foreground: root.foreground
              fontFamily: root.fontFamily
              title: "Selecionar Android TV"
              meta: root.isSearching ? "Buscando TVs na rede local..." : "Selecione a TV para abrir o controle"
              iconComponent: Component {
                Text {
                  text: "󰟴"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  color: Color.accent
                }
              }
              trailingControl: Component {
                PanelActionButton {
                  iconText: "󰑐"
                  tooltipText: "Buscar novamente"
                  fontFamily: root.fontFamily
                  fontSize: Style.font.heading
                  onClicked: root.scanDevices()
                }
              }
            }

            // AVISO DE ERRO (se houver)
            BorderSurface {
              width: parent.width
              visible: root.tvState.last_error !== undefined && root.tvState.last_error !== "" && !root.tvState.pairing_active
              color: Style.hoverFillFor(root.foreground, Color.urgent)
              borderSpec: Border.controlSpec("urgent", Color.urgent, Color.urgent)
              radius: Style.cornerRadius

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.topMargin: Style.space(10)
                anchors.bottomMargin: Style.space(10)
                spacing: Style.space(10)

                Text {
                  text: "󰅚"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  color: Color.urgent
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - parent.children[0].width - Style.space(12)
                  spacing: Style.space(2)

                  Text {
                    text: "Erro de Conexão"
                    color: Color.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    text: root.tvState.last_error || ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                    width: parent.width
                  }
                }
              }
            }

            // Botão para retornar ao controle se já estiver conectado a uma TV
            Button {
              width: parent.width
              visible: root.tvState.connected
              text: "Voltar ao Controle (" + (root.tvState.device_name || root.tvState.current_device) + ") 󰁔"
              active: true
              accent: Color.accent
              onClicked: root.forceDeviceList = false
            }

            // CARD DE PAREAMENTO (Exibido quando o pareamento é iniciado)
            BorderSurface {
              width: parent.width
              visible: root.tvState.pairing_active
              color: Style.hoverFillFor(root.foreground, Color.accent)
              borderSpec: Border.controlSpec("focus", Color.accent, Color.accent)
              radius: Style.cornerRadius
              implicitHeight: pairCol.implicitHeight + Style.space(24)

              Column {
                id: pairCol
                anchors.fill: parent
                anchors.margins: Style.space(12)
                spacing: Style.space(8)

                Text {
                  text: "Pareando com " + (root.tvState.pairing_host || "TV")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  text: "Digite o código de 6 dígitos que apareceu na TV:"
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
                    focus: root.tvState.pairing_active
                    onAccepted: {
                      if (text.length > 0) {
                        root.runCli(["pair-finish", text])
                        root.forceDeviceList = false
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
                        root.forceDeviceList = false
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

            // ===================================================================
            // SEÇÃO 1: TVs PAREADAS (Conectar ou Desparear)
            // ===================================================================
            PanelSectionHeader {
              text: "TVs Pareadas (" + root.pairedDevices.length + ")"
              foreground: root.foreground
              fontFamily: root.fontFamily
              visible: root.pairedDevices.length > 0
            }

            Repeater {
              model: root.pairedDevices
              delegate: BorderSurface {
                id: pairedCard
                width: parent.width
                implicitHeight: Style.space(64)
                color: pairedMouseArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                borderSpec: Border.controlSpec(pairedMouseArea.containsMouse ? "hover-cursor" : "normal", root.foreground, Color.accent)
                radius: Style.cornerRadius

                MouseArea {
                  id: pairedMouseArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (modelData.is_connected) {
                      root.forceDeviceList = false
                    } else if (modelData.is_awake !== false) {
                      root.runCli(["connect", modelData.host])
                      root.forceDeviceList = false
                    }
                  }
                }

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(14)
                  anchors.rightMargin: Style.space(14)
                  anchors.topMargin: Style.space(10)
                  anchors.bottomMargin: Style.space(10)
                  spacing: Style.space(12)

                  Text {
                    text: "󰟴"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    color: modelData.is_connected ? Color.accent : (modelData.is_awake ? root.foreground : Qt.darker(root.foreground, 1.8))
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - pairedActionRow.width - parent.children[0].width - (parent.spacing * 2)
                    spacing: Style.space(2)

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
                      text: (modelData.model || "Android TV") + " • " + (modelData.is_connected ? "Conectada" : (modelData.is_awake ? "Ligada" : (modelData.is_online ? "Standby" : "Desconectada")))
                      color: modelData.is_connected ? Color.accent : (modelData.is_awake ? Qt.darker(root.foreground, 1.4) : Qt.darker(root.foreground, 1.8))
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      width: parent.width
                    }
                  }

                  Row {
                    id: pairedActionRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    // Abrir controle (se conectado)
                    PanelActionButton {
                      visible: modelData.is_connected
                      iconText: "󰅂"
                      tooltipText: "Abrir controle remoto"
                      foreground: Color.accent
                      hoverColor: Qt.lighter(Color.accent, 1.2)
                      fontFamily: root.fontFamily
                      fontSize: Style.font.heading
                      onClicked: root.forceDeviceList = false
                    }

                    // Conectar (se desconectado)
                    PanelActionButton {
                      visible: !modelData.is_connected
                      iconText: "󰌹"
                      tooltipText: modelData.is_awake === false ? "TV em espera / standby (clique para conectar)" : "Conectar à TV"
                      foreground: modelData.is_awake !== false ? Color.accent : Qt.darker(root.foreground, 1.5)
                      hoverColor: Color.accent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.heading
                      enabled: modelData.is_awake !== false
                      opacity: modelData.is_awake === false ? 0.5 : 1.0
                      onClicked: {
                        if (modelData.is_awake !== false) {
                          root.runCli(["connect", modelData.host])
                          root.forceDeviceList = false
                        }
                      }
                    }

                    // Desconectar (apenas se conectado)
                    PanelActionButton {
                      visible: modelData.is_connected
                      iconText: "󰌙"
                      tooltipText: "Desconectar TV"
                      foreground: root.foreground
                      hoverColor: Color.urgent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.heading
                      onClicked: {
                        root.runCli(["disconnect"])
                        statusProc.running = true
                      }
                    }

                    // Desparear TV
                    PanelActionButton {
                      iconText: "󰅖"
                      tooltipText: "Desparear TV"
                      foreground: Color.urgent
                      hoverColor: Qt.lighter(Color.urgent, 1.2)
                      fontFamily: root.fontFamily
                      fontSize: Style.font.heading
                      onClicked: {
                        root.runCli(["unpair", modelData.host])
                        statusProc.running = true
                      }
                    }
                  }
                }
              }
            }

            // ===================================================================
            // SEÇÃO 2: DISPOSITIVOS DISPONÍVEIS (Despareadas / Novas TVs na rede)
            // ===================================================================
            PanelSectionHeader {
              text: "Dispositivos Disponíveis (" + root.unpairedDevices.length + ")"
              foreground: root.foreground
              fontFamily: root.fontFamily
              visible: root.unpairedDevices.length > 0
            }

            Repeater {
              model: root.unpairedDevices
              delegate: BorderSurface {
                id: unpairCard
                width: parent.width
                implicitHeight: Style.space(64)
                color: unpairMouseArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                borderSpec: Border.controlSpec(unpairMouseArea.containsMouse ? "hover-cursor" : "normal", root.foreground, Color.accent)
                radius: Style.cornerRadius

                MouseArea {
                  id: unpairMouseArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (modelData.is_awake !== false) {
                      root.isPairingStarting = true
                      pairingResetTimer.restart()
                      root.runCli(["pair-start", modelData.host])
                    }
                  }
                }

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(14)
                  anchors.rightMargin: Style.space(14)
                  anchors.topMargin: Style.space(10)
                  anchors.bottomMargin: Style.space(10)
                  spacing: Style.space(14)

                  Text {
                    text: "󰟴"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    color: Color.accent
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - unpairActionBtn.width - parent.children[0].width - (parent.spacing * 2)
                    spacing: Style.space(2)

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
                      text: (modelData.model || "Android TV") + (modelData.is_awake === false ? " • Standby" : " • Disponível")
                      color: modelData.is_awake === false ? Qt.darker(root.foreground, 1.8) : Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      width: parent.width
                    }
                  }

                  Button {
                    id: unpairActionBtn
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.isPairingStarting
                          ? "Aguardando TV..."
                          : (modelData.is_awake === false ? "Standby" : "Parear")
                    iconSpinning: root.isPairingStarting
                    accent: Color.accent
                    active: modelData.is_awake !== false
                    enabled: modelData.is_awake !== false
                    opacity: modelData.is_awake === false ? 0.5 : 1.0
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(14)
                    verticalPadding: Style.space(6)
                    onClicked: {
                      if (modelData.is_awake !== false) {
                        root.isPairingStarting = true
                        pairingResetTimer.restart()
                        root.runCli(["pair-start", modelData.host])
                      }
                    }
                  }
                }
              }
            }

            // AVISO E CONEXÃO POR IP SE NENHUMA TV FOR ENCONTRADA
            Column {
              width: parent.width
              visible: root.pairedDevices.length === 0 && root.unpairedDevices.length === 0 && !root.tvState.pairing_active
              spacing: Style.space(10)

              BorderSurface {
                width: parent.width
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
                    text: root.isSearching 
                          ? "Aguarde enquanto escaneamos o Wi-Fi da sua rede..." 
                          : "A busca automática não encontrou TVs ligadas. Digite o IP da TV abaixo:"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    width: parent.width
                  }
                }
              }

              // Campo de IP oferecido apenas se a busca falhar
              Column {
                width: parent.width
                visible: !root.isSearching
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
                        root.forceDeviceList = false
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
                        root.forceDeviceList = false
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

            // Opção discreta de IP caso TVs tenham sido encontradas mas o usuário queira outro IP
            Item {
              width: parent.width
              height: Style.space(32)
              visible: root.discoveredDevices.length > 0 && !root.tvState.pairing_active

              Text {
                text: root.showManualIpFallback ? "󰅃 Ocultar conexão por IP" : "󰅀 Não encontrou sua TV? Inserir IP..."
                color: Qt.darker(root.foreground, 1.7)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.centerIn: parent

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showManualIpFallback = !root.showManualIpFallback
                }
              }
            }

            Column {
              width: parent.width
              visible: root.discoveredDevices.length > 0 && root.showManualIpFallback && !root.tvState.pairing_active
              spacing: Style.space(6)

              Row {
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: optionalIpField
                  width: parent.width - optPairBtn.width - optConnectBtn.width - Style.space(12)
                  placeholderText: "IP da TV (ex: 192.168.1.50)"
                  font.pixelSize: Style.font.caption
                  onAccepted: {
                    if (text.length > 0) {
                      root.runCli(["connect", text])
                      root.forceDeviceList = false
                    }
                  }
                }

                Button {
                  id: optConnectBtn
                  text: "Conectar"
                  fontSize: Style.font.caption
                  onClicked: {
                    if (optionalIpField.text.length > 0) {
                      root.runCli(["connect", optionalIpField.text])
                      root.forceDeviceList = false
                    }
                  }
                }

                Button {
                  id: optPairBtn
                  text: "Parear"
                  fontSize: Style.font.caption
                  onClicked: {
                    if (optionalIpField.text.length > 0) {
                      root.runCli(["pair-start", optionalIpField.text])
                    }
                  }
                }
              }
            }
          }

          // ===================================================================
          // VIEW 2: O CONTROLE REMOTO (Exibido APENAS quando conectado à TV)
          // ===================================================================
          Column {
            id: remoteView
            width: parent.width
            visible: root.currentView === "remote"
            spacing: Style.space(12)

            // Cabeçalho com botão para voltar à lista de TVs e controle de energia
            PanelHero {
              width: parent.width
              foreground: root.foreground
              fontFamily: root.fontFamily
              title: root.tvState.device_name || (root.tvState.current_device || "Android TV")
              meta: (root.tvState.connected && root.tvState.is_on) 
                    ? (Model.formatAppName(root.tvState.current_app) || "Tela Inicial") 
                    : Model.statusDescription(root.tvState)
              iconComponent: Component {
                Button {
                  text: "TVs"
                  iconText: "󰅁"
                  tooltipText: "Voltar para lista de TVs"
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(4)
                  onClicked: root.forceDeviceList = true
                }
              }
              trailingControl: Component {
                Row {
                  spacing: Style.space(6)

                  PanelActionButton {
                    iconText: "󰌌"
                    tooltipText: root.imeActive ? "Fechar digitação" : "Digitar na TV"
                    foreground: root.imeActive ? Color.accent : root.foreground
                    hoverColor: Color.accent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.heading
                    onClicked: {
                      root.imeActive = !root.imeActive
                      if (root.imeActive) {
                        root.runCli(["ime-open"])
                      } else {
                        root.runCli(["ime-close"])
                      }
                    }
                  }

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

            // Ações Rápidas (Voltar, Início, Ajustes, Menu)
            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                width: (parent.width - Style.space(24)) / 4
                iconText: "󰌑"
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

            // D-PAD CONTROLLER
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

            // VOLUME & CONTROLES DE MÍDIA
            Row {
              width: parent.width
              spacing: Style.space(8)

              // Volume
              Row {
                width: (parent.width - Style.space(8)) / 2
                spacing: Style.space(4)

                Button {
                  width: (parent.width - Style.space(8)) / 3
                  iconText: "󰝞"
                  tooltipText: "Volume -"
                  onClicked: root.sendKey("VOL_DOWN")
                }

                Button {
                  width: (parent.width - Style.space(8)) / 3
                  iconText: "󰝟"
                  active: root.tvState.volume && root.tvState.volume.muted
                  accent: Color.urgent
                  tooltipText: "Mudo (M)"
                  onClicked: root.sendKey("MUTE")
                }

                Button {
                  width: (parent.width - Style.space(8)) / 3
                  iconText: "󰝝"
                  tooltipText: "Volume +"
                  onClicked: root.sendKey("VOL_UP")
                }
              }

              // Mídia
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

            // ATALHOS DE APPS
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

            // DIGITAR TEXTO NA TV (Visível quando focado na TV ou ativado pelo teclado)
            Column {
              id: textInputSection
              width: parent.width
              visible: root.imeActive
              spacing: Style.space(6)

              onVisibleChanged: {
                if (visible && textInputField) {
                  textInputField.forceActiveFocus()
                }
              }

              Row {
                width: parent.width

                Text {
                  width: parent.width - closeImeBtn.width
                  text: root.imeLabel ? ("DIGITAR EM: " + root.imeLabel.toUpperCase()) : "DIGITAR NA TV"
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.1
                  anchors.verticalCenter: parent.verticalCenter
                }

                PanelActionButton {
                  id: closeImeBtn
                  iconText: "󰅖"
                  tooltipText: "Fechar digitação"
                  fontFamily: root.fontFamily
                  fontSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                  onClicked: {
                    root.imeActive = false
                    root.runCli(["ime-close"])
                    root.sendKey("BACK")
                  }
                }
              }

              TextField {
                id: textInputField
                width: parent.width
                placeholderText: root.imeLabel ? ("Digitar em " + root.imeLabel + "...") : "Digitar texto na TV (Enter para enviar)..."
                focus: root.imeActive
                onAccepted: {
                  if (text.length > 0) {
                    root.runCli(["text", text])
                    text = ""
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
