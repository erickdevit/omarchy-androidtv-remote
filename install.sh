#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="erick.androidtv-remote"
TARGET_DIR="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"

echo "==> Instalando plugin $PLUGIN_ID para Omarchy..."

# 1. Ensure target plugin link/directory
mkdir -p "${HOME}/.config/omarchy/plugins"
if [ ! -e "$TARGET_DIR" ]; then
    echo "==> Criando link simbólico em $TARGET_DIR..."
    ln -s "$SCRIPT_DIR" "$TARGET_DIR"
fi

# 2. Bootstrap virtual environment and dependencies
echo "==> Verificando ambiente Python e dependências (androidtvremote2, zeroconf)..."
python3 "$SCRIPT_DIR/backend/bootstrap.py"

# 3. Rescan Omarchy plugins
echo "==> Notificando o Omarchy shell para recarregar plugins..."
if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins || true
elif [ -f "/usr/share/omarchy/bin/omarchy-shell" ]; then
    /usr/share/omarchy/bin/omarchy-shell shell rescanPlugins || true
fi

# 4. Enable plugin
echo "==> Ativando o plugin no Omarchy..."
if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin enable "$PLUGIN_ID" || true
elif [ -f "/usr/share/omarchy/bin/omarchy" ]; then
    /usr/share/omarchy/bin/omarchy plugin enable "$PLUGIN_ID" || true
fi

echo ""
echo "✨ Plugin instalado e ativado com sucesso!"
echo "O ícone da TV (󰟴) já deve estar visível na barra do Omarchy."
echo "Clique nele para abrir o controle remoto, buscar TVs na rede ou parear manualmente via IP."
