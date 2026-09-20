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
  property bool showDevices: !tvState.connected && !tvState.pairing_active
  readonly property var barIdentity: root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color accent: Color.accent

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
      if (parsed) root.tvState = parsed
    } catch (e) {
      // Ignore transient JSON parse errors while writing
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
  readonly property color barIconColor: isTvActive ? Color.accent : Qt.darker(barForeground, 1.6)

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
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Block key capture if user is typing in the text field or PIN field
      blocked: (textInputField && textInputField.activeFocus) || (pinInputField && pinInputField.activeFocus) || (manualIpField && manualIpField.activeFocus)

      onMoveRequested: function(dx, dy) {
        if (dy < 0) root.sendKey("UP")
        else if (dy > 0) root.sendKey("DOWN")
        else if (dx < 0) root.sendKey("LEFT")
        else if (dx > 0) root.sendKey("RIGHT")
      }
      onActivateRequested: root.sendKey("OK")
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      onTextKey: function(t) {
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

          // 1. HERO HEADER
          PanelHero {
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            title: root.tvState.device_name || (root.tvState.current_device || "Android TV")
            meta: Model.statusDescription(root.tvState)
            detail: (root.tvState.connected && root.tvState.is_on && root.tvState.volume) 
                    ? ("Vol " + root.tvState.volume.level + (root.tvState.volume.muted ? " (Mudo)" : ""))
                    : ""
            iconComponent: Component {
              Text {
                text: "\udb81\uddf4"
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
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

          // 2. PAIRING CARD (Visible when pairing is active)
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
                    if (text.length > 0) root.runCli(["pair-finish", text])
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

          // 3. DEVICE SELECTOR / SETUP (Visible if not connected or when expanded)
          Column {
            width: parent.width
            spacing: Style.space(8)

            Row {
              width: parent.width
              Text {
                text: "DISPOSITIVOS"
                color: Qt.darker(root.foreground, 1.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.1
                anchors.verticalCenter: parent.verticalCenter
              }

              Item { width: Math.max(0, parent.width - parent.children[0].width - toggleDevBtn.width); height: 1 }

              Button {
                id: toggleDevBtn
                text: root.showDevices ? "Ocultar" : "Configurar TV"
                fontSize: Style.font.caption
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(2)
                onClicked: root.showDevices = !root.showDevices
              }
            }

            Column {
              width: parent.width
              visible: root.showDevices
              spacing: Style.space(6)

              // Discovered devices list
              Repeater {
                model: root.tvState.discovered_devices || []
                delegate: BorderSurface {
                  width: parent.width
                  implicitHeight: Style.space(36)
                  color: Style.hoverFillFor(root.foreground, Color.accent)
                  borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
                  radius: Style.cornerRadius
                  leftPadding: Style.space(8)
                  rightPadding: Style.space(8)

                  Row {
                    anchors.fill: parent
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
                      width: parent.width - connectDevBtn.width - Style.space(32)
                      Text {
                        text: modelData.name || modelData.host
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                        width: parent.width
                      }
                      Text {
                        text: modelData.host
                        color: Qt.darker(root.foreground, 1.6)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Button {
                      id: connectDevBtn
                      anchors.verticalCenter: parent.verticalCenter
                      text: Model.isDevicePaired(root.tvState.known_devices, modelData.host) ? "Conectar" : "Parear"
                      fontSize: Style.font.caption
                      horizontalPadding: Style.space(8)
                      verticalPadding: Style.space(4)
                      onClicked: {
                        if (Model.isDevicePaired(root.tvState.known_devices, modelData.host)) {
                          root.runCli(["connect", modelData.host])
                        } else {
                          root.runCli(["pair-start", modelData.host])
                        }
                      }
                    }
                  }
                }
              }

              // Manual IP input
              Row {
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  id: manualIpField
                  width: parent.width - manualPairBtn.width - manualConnectBtn.width - Style.space(12)
                  placeholderText: "IP manual (ex: 192.168.1.50)"
                  font.pixelSize: Style.font.caption
                  onAccepted: {
                    if (text.length > 0) root.runCli(["connect", text])
                  }
                }

                Button {
                  id: manualConnectBtn
                  text: "Conectar"
                  fontSize: Style.font.caption
                  onClicked: {
                    if (manualIpField.text.length > 0) root.runCli(["connect", manualIpField.text])
                  }
                }

                Button {
                  id: manualPairBtn
                  text: "Parear"
                  fontSize: Style.font.caption
                  onClicked: {
                    if (manualIpField.text.length > 0) root.runCli(["pair-start", manualIpField.text])
                  }
                }
              }
            }
          }

          PanelSeparator { width: parent.width }

          // 4. TOP QUICK ACTION BUTTONS (Back, Home, Settings, Input)
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

          // 5. D-PAD DIRECTIONAL CONTROLLER
          Item {
            width: parent.width
            height: Style.space(170)

            // D-Pad Container centered
            Item {
              width: Style.space(170)
              height: Style.space(170)
              anchors.centerIn: parent

              // Background ring
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

          // 6. VOLUME & MEDIA CONTROLS
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

          // 7. APP SHORTCUTS
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

          // 8. TEXT INPUT TO TV
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
