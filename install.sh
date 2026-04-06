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
# When running from INSTALL_DIR itself, skip copies that would be src==dst
echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR/qml"
if [ "$(realpath "$SCRIPT_DIR")" != "$(realpath "$INSTALL_DIR")" ]; then
    cp "$SCRIPT_DIR/config.ini" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/qml/"*.qml "$INSTALL_DIR/qml/"
    cp "$SCRIPT_DIR/install.sh" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/"
else
    echo "Running from install directory, skipping file copy."
fi

# Write the SwipePageModel patch script
cat > "$INSTALL_DIR/patch_swipe_model.py" << 'PYEOF'
#!/usr/bin/env python3
"""Patches SwipePageModel.qml to load PageBatteryParallelOverview into the carousel."""
import sys, os

swipe_model = sys.argv[1] if len(sys.argv) > 1 else \
    "/opt/victronenergy/gui-v2/Victron/VenusOS/components/SwipePageModel.qml"

marker = "// venus-btbattery-gui"
insert_code = (
    "\t\t// venus-btbattery-gui\n"
    "\t\tvar btBatComp = Qt.createComponent("
        '"file:///data/venus-btbattery-gui/qml/PageBatteryParallelOverview.qml")\n'
    "\t\tif (btBatComp.status === Component.Ready) {\n"
    "\t\t\tinsert(count - 1, btBatComp.createObject(parent, {view: root.view}))\n"
    "\t\t}\n"
    "\t\t// venus-btbattery-gui END\n"
    "\n"
)
anchor = "\t\tcompleted = true"

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

# Generate ConfigData.qml from config.ini (workaround for XHR file:// being blocked)
echo "Generating ConfigData.qml from config.ini..."
python3 - "$INSTALL_DIR/config.ini" "$INSTALL_DIR/qml/ConfigData.qml" << 'PYEOF'
import sys, re

config_path = sys.argv[1]
output_path = sys.argv[2]

# Defaults
vals = {
    "socColorGreen": 60, "socColorYellow": 20, "socColorRed": 10,
    "maxBatteries": 8,
    "fontBatNameSize": 14, "fontBatNameBold": True,
    "fontBatSocSize": 20, "fontBatSocBold": True,
    "fontBatStatsSize": 14, "fontBatStatsBold": False,
    "fontBankLabelSize": 11, "fontBankLabelBold": False,
    "fontBankValueSize": 18, "fontBankValueBold": True,
}
bt_names = {}   # mac -> name
bat_order = []  # macs in config order

key_map = {
    "SOC_COLOR_GREEN": ("socColorGreen", "int"),
    "SOC_COLOR_YELLOW": ("socColorYellow", "int"),
    "SOC_COLOR_RED": ("socColorRed", "int"),
    "MAX_BATTERIES": ("maxBatteries", "int"),
    "FONT_BAT_NAME_SIZE": ("fontBatNameSize", "int"),
    "FONT_BAT_NAME_BOLD": ("fontBatNameBold", "bool"),
    "FONT_BAT_SOC_SIZE": ("fontBatSocSize", "int"),
    "FONT_BAT_SOC_BOLD": ("fontBatSocBold", "bool"),
    "FONT_BAT_STATS_SIZE": ("fontBatStatsSize", "int"),
    "FONT_BAT_STATS_BOLD": ("fontBatStatsBold", "bool"),
    "FONT_BANK_LABEL_SIZE": ("fontBankLabelSize", "int"),
    "FONT_BANK_LABEL_BOLD": ("fontBankLabelBold", "bool"),
    "FONT_BANK_VALUE_SIZE": ("fontBankValueSize", "int"),
    "FONT_BANK_VALUE_BOLD": ("fontBankValueBold", "bool"),
}

with open(config_path) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("[") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key, val = key.strip(), val.strip()
        if key == "BT_NAMES" and val:
            for pair in val.split(","):
                pair = pair.strip()
                if "=" not in pair:
                    continue
                mac, name = pair.split("=", 1)
                mac = mac.strip().lower()
                name = name.strip()
                bt_names[mac] = name
                bat_order.append(mac)
        elif key in key_map:
            prop, typ = key_map[key]
            if typ == "int":
                vals[prop] = int(val)
            elif typ == "bool":
                vals[prop] = val.lower() in ("true", "1", "yes")

# Generate QML
lines = ["import QtQuick", "", "QtObject {"]
for prop, val in vals.items():
    if isinstance(val, bool):
        lines.append("    property bool {}: {}".format(prop, "true" if val else "false"))
    else:
        lines.append("    property int {}: {}".format(prop, val))

# Emit btNames as a JS object and batOrder as a list
names_entries = ", ".join('"{}": "{}"'.format(m, n) for m, n in bt_names.items())
lines.append("    property var btNames: ({{{}}})".format(names_entries))
order_str = ", ".join('"{}"'.format(m) for m in bat_order)
lines.append("    property var batOrder: [{}]".format(order_str))
lines.append("}")
lines.append("")

with open(output_path, "w") as f:
    f.write("\n".join(lines))
print("ConfigData.qml generated.")
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
