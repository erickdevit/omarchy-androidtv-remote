# Android TV Remote Plugin para Omarchy 📺

Plugin de controle remoto virtual para **Android TV** e **Google TV**, desenvolvido para o **Omarchy shell** (Quickshell). Utiliza o protocolo oficial **Android TV Remote v2** (o mesmo protocolo TLS/Protobuf utilizado pelo app Google TV e Google Home nas portas `6466` e `6467`), sem requerer ativação de ADB ou modo desenvolvedor na televisão.

---

## ✨ Funcionalidades

- **Protocolo Oficial Google TV / Android TV v2**: Comunicação criptografada TLS com certificados auto-assinados e mensagens Protobuf.
- **Descoberta Automática de TVs (mDNS / Zeroconf)**: Varredura local para encontrar dispositivos Android TV na rede sem precisar digitar IP.
- **Pareamento Fácil e Rápido**: Inicie o pareamento direto pelo painel e digite o código de 6 dígitos exibido na TV.
- **Controle Direto na Barra do Omarchy**:
  - Ícone de status na barra (`󰟴`).
  - **Clique Esquerdo**: Abre/fecha o painel do controle remoto virtual.
  - **Clique Direito**: Liga/Desliga a TV imediatamente (Power toggle).
  - **Clique Médio**: Mudo (Mute toggle).
  - Tooltip informativo com nome da TV, status de energia e aplicativo em reprodução.
- **Controles Completos**:
  - **D-Pad Direcional**: Cima, Baixo, Esquerda, Direita e OK/Enter central.
  - **Navegação**: Voltar (Back), Tela Inicial (Home), Ajustes (Settings), Menu.
  - **Volume & Mídia**: Volume +, Volume -, Mudo, Play/Pause, Próximo, Anterior.
  - **Lançador Rápido de Apps**: Abra YouTube, Netflix, Prime Video, Disney+, Spotify, Twitch com 1 clique.
  - **Digitação na TV**: Campo de texto para enviar palavras, buscas ou URLs diretamente para o teclado da TV.
  - **Atalhos do Teclado no Painel**:
    - `Setas`: Navegação D-Pad
    - `Enter`: OK / Selecionar
    - `Esc` ou `Backspace`: Voltar
    - `Espaço`: Play / Pause
    - `+` / `-`: Volume Up / Down
    - `M`: Mudo
    - `H`: Home

---

## 🛠️ Arquitetura

1. **Frontend (QML / Quickshell)**:
   - Baseado em `qs.Ui` e `qs.Commons` do Omarchy, adotando os temas, cores e bordas ativas do sistema.
   - Utiliza `KeyboardPanel` para popup fluido e suporte completo a navegação por teclado.
   - Observa `~/.local/state/omarchy/androidtv-remote/state.json` via `Quickshell.Io.FileView` para renderização reativa em tempo real.

2. **Backend (Python & Daemon)**:
   - Um daemon leve em segundo plano (`backend/daemon.py`) mantém a conexão TLS persistente com a TV.
   - Atende comandos com latência instantânea (< 5ms) via Unix Domain Socket (`~/.local/state/omarchy/androidtv-remote/daemon.sock`).
   - Biblioteca `androidtvremote2` para implementação nativa do protocolo v2.
   - Auto-bootstrap de ambiente virtual em `~/.local/share/omarchy-androidtv/venv`.

---

## 🚀 Instalação e Ativação

Para instalar e ativar o plugin no Omarchy:

```bash
cd ~/repos/tv-remote-controll
./install.sh
```

Ou usando o gerenciador de plugins nativo do Omarchy:

```bash
omarchy plugin enable erick.androidtv-remote
```

---

## 📱 Como Conectar à sua Android TV

1. Certifique-se de que seu computador e sua Android TV / Google TV estejam conectados na **mesma rede Wi-Fi ou cabo**.
2. Clique no ícone da TV na barra do Omarchy.
3. Se a TV for descoberta automaticamente, clique em **"Parear"** ao lado do nome dela. Se preferir, digite o IP da TV e clique em **"Parear"**.
4. Um código de pareamento de 6 dígitos será exibido na tela da sua TV.
5. Digite o código no campo que apareceu no painel do Omarchy e clique em **"OK"**.
6. Pronto! A TV está conectada e pronta para ser controlada.

---

## 💻 Uso via Linha de Comando (CLI)

O plugin inclui o utilitário `omarchy-androidtv-remote` para controle via terminal ou scripts:

```bash
# Enviar teclas de navegação
omarchy-androidtv-remote key UP
omarchy-androidtv-remote key DOWN
omarchy-androidtv-remote key LEFT
omarchy-androidtv-remote key RIGHT
omarchy-androidtv-remote key OK
omarchy-androidtv-remote key BACK
omarchy-androidtv-remote key HOME
omarchy-androidtv-remote key POWER

# Volume e reprodução
omarchy-androidtv-remote key VOL_UP
omarchy-androidtv-remote key VOL_DOWN
omarchy-androidtv-remote key MUTE
omarchy-androidtv-remote key PLAY_PAUSE

# Digitar texto na TV
omarchy-androidtv-remote text "Minha pesquisa"

# Abrir aplicativos diretamente
omarchy-androidtv-remote app youtube
omarchy-androidtv-remote app netflix
omarchy-androidtv-remote app prime

# Consultar status em JSON
omarchy-androidtv-remote status
```
