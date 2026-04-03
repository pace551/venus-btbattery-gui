#!/bin/bash
set -e

INSTALL_DIR="/data/venus-btbattery-gui"
RC_LOCAL="/data/rc.local"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RC_MARKER="# venus-btbattery-gui"

echo "=== venus-btbattery-gui installer ==="
echo ""

# Locate gui-v2 (path differs between Cerbo GX and RPi4)
if [ -d "/opt/victronenergy/gui-v2" ]; then
    GUI_V2_DIR="/opt/victronenergy/gui-v2"
elif [ -d "/var/www/venus/gui-v2" ]; then
    GUI_V2_DIR="/var/www/venus/gui-v2"
else
    echo "ERROR: gui-v2 not found. Searched:"
    echo "  /opt/victronenergy/gui-v2"
    echo "  /var/www/venus/gui-v2"
    echo "This installer requires VenusOS v3.x with gui-v2."
    exit 1
fi

GUI_COMPONENTS_DIR="$GUI_V2_DIR/Victron/VenusOS/components"
SWIPE_MODEL="$GUI_COMPONENTS_DIR/SwipePageModel.qml"

# Log gui-v2 version for troubleshooting
if [ -f /opt/victronenergy/version ]; then
    echo "VenusOS version: $(head -n 1 /opt/victronenergy/version)"
fi

# Validate config
if [ -f "$SCRIPT_DIR/config.ini" ]; then
    MAX_BAT=$(grep -E "^MAX_BATTERIES" "$SCRIPT_DIR/config.ini" | cut -d= -f2 | tr -d ' ')
    if [ -n "$MAX_BAT" ] && [ "$MAX_BAT" -gt 8 ]; then
        echo "ERROR: MAX_BATTERIES=$MAX_BAT exceeds limit of 8"
        exit 1
    fi
fi

# Copy files to /data (persists across firmware upgrades)
echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR/qml"
cp "$SCRIPT_DIR/config.ini" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/qml/"*.qml "$INSTALL_DIR/qml/"
cp "$SCRIPT_DIR/install.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/"

# Write the SwipePageModel patch script
cat > "$INSTALL_DIR/patch_swipe_model.py" << 'PYEOF'
#!/usr/bin/env python3
"""Patches SwipePageModel.qml to load PageBatteryParallelOverview into the carousel."""
import sys, os

swipe_model = sys.argv[1] if len(sys.argv) > 1 else \
    "/opt/victronenergy/gui-v2/Victron/VenusOS/components/SwipePageModel.qml"

marker = "// venus-btbattery-gui"
insert_code = (
    "    // venus-btbattery-gui\n"
    "    var btBatComp = Qt.createComponent("
        '"file:///data/venus-btbattery-gui/qml/PageBatteryParallelOverview.qml")\n'
    "    if (btBatComp.status === Component.Ready) {\n"
    "        insert(count - 1, btBatComp.createObject(parent, {view: root.view}))\n"
    "    }\n"
    "    // venus-btbattery-gui END\n"
    "\n"
)
anchor = "        completed = true"

if not os.path.exists(swipe_model):
    print("ERROR: {} not found".format(swipe_model))
    sys.exit(1)

with open(swipe_model) as f:
    content = f.read()

if marker in content:
    print("SwipePageModel.qml already patched.")
    sys.exit(0)

if anchor not in content:
    print("ERROR: insertion point not found in SwipePageModel.qml")
    sys.exit(1)

content = content.replace(anchor, insert_code + anchor, 1)
with open(swipe_model, "w") as f:
    f.write(content)
print("SwipePageModel.qml patched.")
PYEOF

# Patch SwipePageModel.qml
echo "Patching SwipePageModel.qml..."
if [ ! -f "$SWIPE_MODEL" ]; then
    echo "ERROR: $SWIPE_MODEL not found"
    exit 1
fi

if [ ! -f "$INSTALL_DIR/SwipePageModel.qml.orig" ]; then
    cp "$SWIPE_MODEL" "$INSTALL_DIR/SwipePageModel.qml.orig"
    echo "Backed up original SwipePageModel.qml"
fi

python3 "$INSTALL_DIR/patch_swipe_model.py" "$SWIPE_MODEL"

# Update rc.local for firmware upgrade persistence
echo "Updating rc.local..."
touch "$RC_LOCAL"
chmod +x "$RC_LOCAL"

# Remove existing venus-btbattery-gui block and ensure shebang, using Python
python3 - << 'PYEOF'
import re
path = '/data/rc.local'
with open(path) as f:
    content = f.read()
# Remove old block if present
content = re.sub(
    r'\n# venus-btbattery-gui\n.*?# venus-btbattery-gui END\n',
    '',
    content,
    flags=re.DOTALL
)
# Ensure shebang
if not content.startswith('#!'):
    content = '#!/bin/bash\n' + content
with open(path, 'w') as f:
    f.write(content)
PYEOF

cat >> "$RC_LOCAL" << RCEOF

$RC_MARKER
# Re-apply SwipePageModel.qml patch after firmware upgrade
SWIPE_MODEL="$SWIPE_MODEL"
INSTALL_DIR="$INSTALL_DIR"
if [ -f "\$INSTALL_DIR/patch_swipe_model.py" ] && [ -f "\$SWIPE_MODEL" ]; then
    python3 "\$INSTALL_DIR/patch_swipe_model.py" "\$SWIPE_MODEL"
fi
$RC_MARKER END
RCEOF

echo "rc.local updated."

# Restart GUI
echo "Restarting GUI..."
svc -t /service/gui 2>/dev/null || echo "Note: GUI restart skipped (not on VenusOS)."

echo ""
echo "=== Installation complete ==="
echo "Config: $INSTALL_DIR/config.ini"
echo "Uninstall: bash $INSTALL_DIR/uninstall.sh"
