#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="erick.androidtv-remote"
TARGET_DIR="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"

echo "==> Installing plugin $PLUGIN_ID for Omarchy..."

# 1. Ensure target plugin link/directory
mkdir -p "${HOME}/.config/omarchy/plugins"
if [ ! -e "$TARGET_DIR" ]; then
    echo "==> Creating symbolic link at $TARGET_DIR..."
    ln -s "$SCRIPT_DIR" "$TARGET_DIR"
fi

# 2. Bootstrap virtual environment and dependencies
echo "==> Checking Python environment and dependencies (androidtvremote2, zeroconf)..."
python3 "$SCRIPT_DIR/backend/bootstrap.py"

# 3. Rescan Omarchy plugins
echo "==> Notifying Omarchy shell to rescan plugins..."
if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins || true
elif [ -f "/usr/share/omarchy/bin/omarchy-shell" ]; then
    /usr/share/omarchy/bin/omarchy-shell shell rescanPlugins || true
fi

# 4. Enable plugin
echo "==> Enabling plugin in Omarchy..."
if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin enable "$PLUGIN_ID" || true
elif [ -f "/usr/share/omarchy/bin/omarchy" ]; then
    /usr/share/omarchy/bin/omarchy plugin enable "$PLUGIN_ID" || true
fi

echo ""
echo "✨ Plugin installed and enabled successfully!"
echo "The TV icon (󰟴) should now be visible in your Omarchy bar."
echo "Click it to open the virtual remote, discover TVs on the network, or pair manually via IP."
