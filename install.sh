#!/bin/bash
set -e

INSTALL_DIR="/data/venus-btbattery-gui"
GUI_V2_DIR="/opt/victronenergy/gui-v2"
GUI_QML_DIR="$GUI_V2_DIR/pages"
GUI_COMPONENTS_DIR="$GUI_V2_DIR/components"
SWIPE_MODEL="$GUI_COMPONENTS_DIR/SwipePageModel.qml"
RC_LOCAL="/data/rc.local"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RC_MARKER="# venus-btbattery-gui"
PAGE_NAME="PageBatteryParallelOverview"

echo "=== venus-btbattery-gui installer ==="
echo ""

# Validate VenusOS
if [ ! -d "$GUI_V2_DIR" ]; then
    echo "ERROR: gui-v2 not found at $GUI_V2_DIR"
    echo "This installer requires VenusOS v3.x with gui-v2."
    exit 1
fi

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
mkdir -p "$INSTALL_DIR/tools"
cp "$SCRIPT_DIR/config.ini" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/qml/"*.qml "$INSTALL_DIR/qml/"
cp "$SCRIPT_DIR/install.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/"

# Create symlinks for QML files into gui-v2 pages directory
echo "Creating QML symlinks in gui-v2..."
for qmlfile in "$INSTALL_DIR/qml/"*.qml; do
    filename=$(basename "$qmlfile")
    ln -sf "$qmlfile" "$GUI_QML_DIR/$filename" 2>/dev/null || \
    ln -sf "$qmlfile" "$GUI_COMPONENTS_DIR/$filename" 2>/dev/null || true
done

# Patch SwipePageModel.qml to add our page to the carousel
patch_swipe_model() {
    local swipe_model="$1"
    if [ ! -f "$swipe_model" ]; then
        echo "WARNING: SwipePageModel.qml not found at $swipe_model"
        echo "Page will not appear in carousel. Manual integration needed."
        return 1
    fi

    # Check if already patched
    if grep -q "$PAGE_NAME" "$swipe_model"; then
        echo "SwipePageModel.qml already contains $PAGE_NAME entry."
        return 0
    fi

    # Back up original
    cp "$swipe_model" "$INSTALL_DIR/SwipePageModel.qml.orig"

    # Find the last SwipeViewPage entry and add ours after it
    # We insert before the closing brace of the ObjectModel
    sed -i "/^[[:space:]]*}[[:space:]]*\/\/[[:space:]]*end[[:space:]]*ObjectModel\|^[[:space:]]*}[[:space:]]*$/,\${
        /^[[:space:]]*}/ {
            i\\
\\        // $RC_MARKER\\
\\        SwipeViewPage {\\
\\            navButtonText: \"Batteries\"\\
\\            navButtonIcon: \"qrc:///images/icon_battery_24.svg\"\\
\\            url: \"file://$INSTALL_DIR/qml/$PAGE_NAME.qml\"\\
\\        }
            b
        }
    }" "$swipe_model"

    # Verify patch applied
    if grep -q "$PAGE_NAME" "$swipe_model"; then
        echo "SwipePageModel.qml patched successfully."
        return 0
    else
        echo "WARNING: Failed to patch SwipePageModel.qml automatically."
        echo "Restoring backup..."
        cp "$INSTALL_DIR/SwipePageModel.qml.orig" "$swipe_model"
        echo "Manual integration needed. Add a SwipeViewPage entry for $PAGE_NAME."
        return 1
    fi
}

patch_swipe_model "$SWIPE_MODEL"

# Set up rc.local for firmware upgrade persistence
echo "Configuring rc.local for boot persistence..."

# Ensure rc.local exists and is executable
touch "$RC_LOCAL"
chmod +x "$RC_LOCAL"

# Add shebang if missing
if ! head -1 "$RC_LOCAL" | grep -q "^#!"; then
    sed -i '1i#!/bin/bash' "$RC_LOCAL"
fi

# Remove old entry if present
if grep -q "$RC_MARKER" "$RC_LOCAL"; then
    sed -i "/$RC_MARKER/,/^$RC_MARKER END/d" "$RC_LOCAL"
fi

cat >> "$RC_LOCAL" << RCEOF

$RC_MARKER
# Re-establish QML symlinks and SwipePageModel patch after firmware upgrade
if [ -d "$GUI_V2_DIR" ] && [ -d "$INSTALL_DIR" ]; then
    # Symlink QML files
    for qmlfile in $INSTALL_DIR/qml/*.qml; do
        filename=\$(basename "\$qmlfile")
        ln -sf "\$qmlfile" "$GUI_QML_DIR/\$filename" 2>/dev/null || true
    done
    # Patch SwipePageModel if needed
    SWIPE_MODEL="$SWIPE_MODEL"
    if [ -f "\$SWIPE_MODEL" ] && ! grep -q "$PAGE_NAME" "\$SWIPE_MODEL"; then
        cp "\$SWIPE_MODEL" "$INSTALL_DIR/SwipePageModel.qml.orig"
        # Simple append before last closing brace
        sed -i "/^[[:space:]]*}[[:space:]]*$/,\\\${ /^[[:space:]]*}/ {
            i\\\\
\\\\        // $RC_MARKER\\\\
\\\\        SwipeViewPage {\\\\
\\\\            navButtonText: \\\"Batteries\\\"\\\\
\\\\            navButtonIcon: \\\"qrc:///images/icon_battery_24.svg\\\"\\\\
\\\\            url: \\\"file://$INSTALL_DIR/qml/$PAGE_NAME.qml\\\"\\\\
\\\\        }
            b
        }}" "\$SWIPE_MODEL"
    fi
fi
$RC_MARKER END
RCEOF

echo "rc.local updated."

# Restart GUI
echo "Restarting GUI service..."
svc -t /service/gui 2>/dev/null || echo "Note: GUI service restart skipped (not running on VenusOS)"

echo ""
echo "=== Installation complete ==="
echo "Config: $INSTALL_DIR/config.ini"
echo "To uninstall: $INSTALL_DIR/uninstall.sh"
