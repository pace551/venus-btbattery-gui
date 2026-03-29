import QtQuick
import Victron.VenusOS

Item {
    id: root

    required property string serviceUid

    property real soc: socItem.valid ? socItem.value : 0
    property real voltage: voltageItem.valid ? voltageItem.value : 0
    property real current: currentItem.valid ? currentItem.value : 0
    property real capacity: capacityItem.valid ? capacityItem.value : 0
    property real installedCapacity: installedCapacityItem.valid ? installedCapacityItem.value : 0

    VeQuickItem { id: socItem; uid: root.serviceUid + "/Soc" }
    VeQuickItem { id: voltageItem; uid: root.serviceUid + "/Dc/0/Voltage" }
    VeQuickItem { id: currentItem; uid: root.serviceUid + "/Dc/0/Current" }
    VeQuickItem { id: capacityItem; uid: root.serviceUid + "/Capacity" }
    VeQuickItem { id: installedCapacityItem; uid: root.serviceUid + "/InstalledCapacity" }
}
