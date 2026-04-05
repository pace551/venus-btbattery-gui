import QtQuick
import Victron.VenusOS

Item {
    id: root

    required property string serviceUid

    // Cached values — updated by explicit handlers so they survive
    // the brief invalid window during uid-toggle refresh
    property real soc: 0
    property real voltage: 0
    property real current: 0
    property real capacity: 0
    property real installedCapacity: 0

    VeQuickItem {
        id: socItem
        uid: root.serviceUid + "/Soc"
        onValueChanged: if (valid) root.soc = value
        onValidChanged: if (valid && value !== undefined) root.soc = value
    }
    VeQuickItem {
        id: voltageItem
        uid: root.serviceUid + "/Dc/0/Voltage"
        onValueChanged: if (valid) root.voltage = value
        onValidChanged: if (valid && value !== undefined) root.voltage = value
    }
    VeQuickItem {
        id: currentItem
        uid: root.serviceUid + "/Dc/0/Current"
        onValueChanged: if (valid) root.current = value
        onValidChanged: if (valid && value !== undefined) root.current = value
    }
    VeQuickItem {
        id: capacityItem
        uid: root.serviceUid + "/Capacity"
        onValueChanged: if (valid) root.capacity = value
        onValidChanged: if (valid && value !== undefined) root.capacity = value
    }
    VeQuickItem {
        id: installedCapacityItem
        uid: root.serviceUid + "/InstalledCapacity"
        onValueChanged: if (valid) root.installedCapacity = value
        onValidChanged: if (valid && value !== undefined) root.installedCapacity = value
    }

    // Force VeQuickItems to re-subscribe by toggling uid off and back on.
    // Works around live MQTT subscriptions not being maintained for
    // VeQuickItems inside file://-loaded SwipeViewPages.
    function forceRefresh() {
        var items = [socItem, voltageItem, currentItem, capacityItem, installedCapacityItem]
        for (var i = 0; i < items.length; i++) {
            var u = items[i].uid
            items[i].uid = ""
            items[i].uid = u
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.forceRefresh()
    }
}
