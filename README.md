# 📺 Android TV & Google TV Remote para Omarchy

[![Omarchy Plugin](https://img.shields.io/badge/Omarchy-Plugin-blue?style=for-the-badge&logo=archlinux)](https://omarchyplugins.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-emerald.svg?style=for-the-badge)](manifest.json)
[![Protocol](https://img.shields.io/badge/Protocol-Android%20TV%20v2-orange?style=for-the-badge&logo=google)](https://github.com/erickdevit/omarchy-androidtv-remote)

Controle remoto virtual nativo para **Android TV** e **Google TV**, integrado diretamente à barra e ao ecossistema do **Omarchy**. 

Utiliza o protocolo oficial **Android TV Remote v2** (TLS/Protobuf criptografado nas portas `6466` e `6467`) — o mesmo utilizado pelos apps Google TV e Google Home. **Não requer ativação de ADB, root ou modo de desenvolvedor na TV.**

---

## 📸 Demonstração / Preview

> [!NOTE]
> *Capturas de tela e demonstrações visuais do plugin em funcionamento no Omarchy shell.*

| Controle Remoto | Seleção de TVs | Pareamento Seguro |
| :---: | :---: | :---: |
| ![Controle Remoto](docs/screenshots/remote_view.png) | ![Lista de Dispositivos](docs/screenshots/devices_view.png) | ![Código de Pareamento](docs/screenshots/pairing_prompt.png) |

---

## ✨ Funcionalidades Principais

- 📡 **Protocolo Oficial Google TV / Android TV v2**: Conexão TLS direta, autenticada e criptografada com latência ultrabaixa (< 5ms).
- 🔍 **Descoberta Automática na Rede (mDNS / Zeroconf)**: Detecta automaticamente suas televisões na rede local sem necessidade de configuração manual.
- 📺 **Gerenciamento de Múltiplas TVs**:
  - Lista de TVs pareadas com status em tempo real (Conectada, Ligada, Standby).
  - Conexão e desconexão com 1 clique.
  - Ação rápida para desparear e esquecer dispositivos.
  - Lista de novas TVs disponíveis na rede prontas para pareamento.
- 🎯 **Integração Perfeita com a Barra do Omarchy**:
  - Ícone de status dinâmico (`󰟴` quando ligada / `󰟵` em standby).
  - **Clique Esquerdo**: Abre/fecha o painel do controle remoto.
  - **Clique Direito**: Alterna energia da TV (Liga / Desliga).
  - **Clique Médio**: Alterna mudo (Mute).
  - Tooltip informativo com nome da TV, app em execução e status de conexão.
- 🎮 **Controles Completos de Navegação**:
  - **D-Pad Virtual**: Cima, Baixo, Esquerda, Direita e botão central `OK`.
  - **Ações Rápidas**: Voltar (`Back`), Tela Inicial (`Home`), Ajustes (`Settings`) e Menu / Entrada.
- 🔊 **Volume & Mídia com Indicador de Estado**:
  - Controle de Volume (`-`, `Mudo`, `+`).
  - Botão dinâmico de **Play / Pause** que alterna seu ícone e estado ativo (`󰐊` Reproduzir / `󰏤` Pausar) de acordo com o status da reprodução.
  - Navegação de faixas (`Anterior` e `Próximo`).
- 🚀 **Lançador de Aplicativos com 1 Clique**:
  - Acesso direto a **YouTube**, **Netflix**, **Prime Video**, **Disney+**, **Spotify** e **Twitch**.
- ⌨️ **Digitação Direta na TV (IME)**:
  - Detecta automaticamente quando um campo de texto está aberto na TV (buscas no YouTube, Play Store, login, etc.) e exibe a caixa de digitação.
  - Envio direto de texto do teclado do computador para a TV.
- ⌨️ **Navegação por Teclado**:
  - Opere todo o controle pelo teclado enquanto o painel estiver aberto.

---

## ⌨️ Atalhos do Teclado

Com o painel do controle aberto, você pode utilizar os seguintes atalhos:

| Tecla | Ação |
| :--- | :--- |
| `Setas Direcionais` | Cima, Baixo, Esquerda, Direita no D-Pad |
| `Enter` / `Espaço no OK` | Confirmar / OK |
| `Esc` / `Backspace` / `B` | Voltar |
| `H` | Tela Inicial (Home) |
| `Espaço` / `P` | Alternar Play / Pause |
| `+` / `-` | Aumentar / Diminuir Volume |
| `M` | Mudo |

---

## 🚀 Instalação

### Método 1: Via Gerenciador de Plugins do Omarchy (Recomendado)

Basta executar no terminal:

```bash
omarchy plugin add https://github.com/erickdevit/omarchy-androidtv-remote.git --enable
```

O Omarchy irá clonar o repositório, validar o manifesto e ativar o widget na sua barra automaticamente.

### Método 2: Instalação Manual

```bash
git clone https://github.com/erickdevit/omarchy-androidtv-remote.git ~/.config/omarchy/plugins/erick.androidtv-remote
omarchy plugin enable erick.androidtv-remote
```

---

## 📱 Guia de Pareamento

1. Certifique-se de que seu computador e sua TV estejam na **mesma rede local (Wi-Fi ou cabo)**.
2. Clique no ícone de TV na barra do Omarchy.
3. Na lista **"Dispositivos Disponíveis"**, localize sua televisão e clique em **"Parear"**.
4. Um código de 6 caracteres aparecerá na tela da sua televisão.
5. Digite o código no campo que se abrirá no painel do Omarchy e confirme com **"OK"**.
6. Pronto! Sua TV agora está pareada e pronta para ser controlada.

---

## 💻 Controle via Linha de Comando (CLI)

O plugin inclui um utilitário CLI poderoso para automações, scripts e atalhos globais no Hyprland:

```bash
# Navegação
omarchy-androidtv-remote key UP
omarchy-androidtv-remote key DOWN
omarchy-androidtv-remote key LEFT
omarchy-androidtv-remote key RIGHT
omarchy-androidtv-remote key OK
omarchy-androidtv-remote key BACK
omarchy-androidtv-remote key HOME
omarchy-androidtv-remote key POWER

# Volume e Mídia
omarchy-androidtv-remote key VOL_UP
omarchy-androidtv-remote key VOL_DOWN
omarchy-androidtv-remote key MUTE
omarchy-androidtv-remote key PLAY_PAUSE
omarchy-androidtv-remote key PLAY
omarchy-androidtv-remote key PAUSE
omarchy-androidtv-remote key NEXT
omarchy-androidtv-remote key PREV

# Lançar Aplicativos
omarchy-androidtv-remote app youtube
omarchy-androidtv-remote app netflix
omarchy-androidtv-remote app prime
omarchy-androidtv-remote app spotify

# Enviar Texto
omarchy-androidtv-remote text "Minha busca no YouTube"

# Consultar Estado em JSON
omarchy-androidtv-remote status
```

---

## 🛡️ Segurança e Privacidade

- **Sem ADB**: Não requer ativação de depuração USB/rede ou permissões inseguras na televisão.
- **TLS Criptografado**: Todas as mensagens trafegam criptografadas com certificado local gerado de forma autônoma em `~/.local/state/omarchy/androidtv-remote/`.
- **Totalmente Local**: Nenhuma informação, credencial ou dado de uso é transmitido para a internet; a comunicação é 100% interna na sua rede local (LAN).
- **Em Conformidade com o Omarchy**: Segue rigorosamente o schema de plugins do Omarchy (`manifest.json` v1) e as diretrizes de segurança da comunidade.

---

## 📄 Licença

Distribuído sob a licença [MIT](LICENSE). Desenvolvido por [Erick](https://github.com/erickdevit).
