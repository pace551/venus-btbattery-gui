#!/bin/bash
set -e

INSTALL_DIR="/data/venus-btbattery-gui"
GUI_V2_DIR="/opt/victronenergy/gui-v2"
GUI_QML_DIR="$GUI_V2_DIR/pages"
GUI_COMPONENTS_DIR="$GUI_V2_DIR/components"
SWIPE_MODEL="$GUI_COMPONENTS_DIR/SwipePageModel.qml"
RC_LOCAL="/data/rc.local"
RC_MARKER="# venus-btbattery-gui"
PAGE_NAME="PageBatteryParallelOverview"

echo "=== venus-btbattery-gui uninstaller ==="
echo ""

# Remove QML symlinks
echo "Removing QML symlinks..."
for dir in "$GUI_QML_DIR" "$GUI_COMPONENTS_DIR"; do
    if ls "$INSTALL_DIR/qml/"*.qml >/dev/null 2>&1; then
        for qmlfile in "$INSTALL_DIR/qml/"*.qml; do
            filename=$(basename "$qmlfile")
            if [ -L "$dir/$filename" ]; then
                rm "$dir/$filename"
                echo "  Removed: $dir/$filename"
            fi
        done
    fi
done

# Restore SwipePageModel.qml from backup
if [ -f "$INSTALL_DIR/SwipePageModel.qml.orig" ] && [ -f "$SWIPE_MODEL" ]; then
    if grep -q "$PAGE_NAME" "$SWIPE_MODEL"; then
        echo "Restoring original SwipePageModel.qml..."
        cp "$INSTALL_DIR/SwipePageModel.qml.orig" "$SWIPE_MODEL"
    fi
elif [ -f "$SWIPE_MODEL" ] && grep -q "$PAGE_NAME" "$SWIPE_MODEL"; then
    echo "Removing patch from SwipePageModel.qml..."
    sed -i "/$RC_MARKER/,/SwipeViewPage.*$PAGE_NAME.*}/d" "$SWIPE_MODEL"
fi

# Remove rc.local entry
if [ -f "$RC_LOCAL" ] && grep -q "$RC_MARKER" "$RC_LOCAL"; then
    echo "Removing rc.local entry..."
    sed -i "/$RC_MARKER/,/$RC_MARKER END/d" "$RC_LOCAL"
fi

# Ask about removing install directory
echo ""
read -p "Remove $INSTALL_DIR and all config? (y/N) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
else
    echo "Keeping $INSTALL_DIR (config preserved)."
fi

# Restart GUI
echo "Restarting GUI service..."
svc -t /service/gui 2>/dev/null || echo "Note: GUI service restart skipped (not running on VenusOS)"

echo ""
echo "=== Uninstall complete ==="
