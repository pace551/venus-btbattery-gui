#!/bin/bash
set -e

INSTALL_DIR="/data/venus-btbattery-gui"
RC_LOCAL="/data/rc.local"

echo "=== venus-btbattery-gui uninstaller ==="
echo ""

# Locate gui-v2 (path differs between Cerbo GX and RPi4)
if [ -d "/opt/victronenergy/gui-v2" ]; then
    GUI_V2_DIR="/opt/victronenergy/gui-v2"
elif [ -d "/var/www/venus/gui-v2" ]; then
    GUI_V2_DIR="/var/www/venus/gui-v2"
else
    GUI_V2_DIR=""
fi

GUI_COMPONENTS_DIR="${GUI_V2_DIR:+$GUI_V2_DIR/Victron/VenusOS/components}"
SWIPE_MODEL="${GUI_COMPONENTS_DIR:+$GUI_COMPONENTS_DIR/SwipePageModel.qml}"

# Restore SwipePageModel.qml
if [ -f "$SWIPE_MODEL" ] && grep -q "venus-btbattery-gui" "$SWIPE_MODEL" 2>/dev/null; then
    if [ -f "$INSTALL_DIR/SwipePageModel.qml.orig" ]; then
        echo "Restoring SwipePageModel.qml from backup..."
        cp "$INSTALL_DIR/SwipePageModel.qml.orig" "$SWIPE_MODEL"
    else
        echo "No backup found — removing patch from SwipePageModel.qml..."
        python3 - "$SWIPE_MODEL" << 'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
content = re.sub(
    r'    // venus-btbattery-gui\n.*?    // venus-btbattery-gui END\n\n',
    '',
    content,
    flags=re.DOTALL
)
with open(sys.argv[1], 'w') as f:
    f.write(content)
print("Patch removed.")
PYEOF
    fi
fi

# Remove rc.local entry
if [ -f "$RC_LOCAL" ] && grep -q "venus-btbattery-gui" "$RC_LOCAL" 2>/dev/null; then
    echo "Removing rc.local entry..."
    python3 - << 'PYEOF'
import re
with open('/data/rc.local') as f:
    content = f.read()
content = re.sub(
    r'\n# venus-btbattery-gui\n.*?# venus-btbattery-gui END\n',
    '',
    content,
    flags=re.DOTALL
)
with open('/data/rc.local', 'w') as f:
    f.write(content)
PYEOF
fi

# Ask about removing install directory
echo ""
read -rp "Remove $INSTALL_DIR and all config? (y/N) " REPLY
echo ""
case "$REPLY" in
    [Yy]*)
        echo "Removing $INSTALL_DIR..."
        rm -rf "$INSTALL_DIR"
        ;;
    *)
        echo "Keeping $INSTALL_DIR (config preserved)."
        ;;
esac

# Restart GUI
echo "Restarting GUI..."
svc -t /service/gui 2>/dev/null || echo "Note: GUI restart skipped (not on VenusOS)."

echo ""
echo "=== Uninstall complete ==="
