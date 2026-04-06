import QtQuick
import Victron.VenusOS

Item {
    id: root

    required property string serviceUid
    required property string serviceName
    required property var batteryModel
    property string configName: ""

    function findModelIndex() {
        for (var i = 0; i < batteryModel.count; i++) {
            if (batteryModel.get(i).serviceName === root.serviceName) return i
        }
        return -1
    }

    function updateModel(prop, value) {
        var idx = findModelIndex()
        if (idx >= 0) batteryModel.setProperty(idx, prop, value)
    }

    VeQuickItem {
        uid: root.serviceUid + "/CustomName"
        onValueChanged: {
            if (valid && value && root.configName === "")
                root.updateModel("name", value)
        }
    }

    VeQuickItem {
        uid: root.serviceUid + "/Soc"
        onValueChanged: if (valid) root.updateModel("soc", Math.round(value))
    }
    VeQuickItem {
        uid: root.serviceUid + "/Dc/0/Voltage"
        onValueChanged: if (valid) root.updateModel("voltage", value)
    }
    VeQuickItem {
        uid: root.serviceUid + "/Dc/0/Current"
        onValueChanged: if (valid) root.updateModel("current", value)
    }
    VeQuickItem {
        uid: root.serviceUid + "/Dc/0/Temperature"
        onValueChanged: if (valid) root.updateModel("temperature", Math.round(value))
    }
    VeQuickItem {
        uid: root.serviceUid + "/Voltages/Diff"
        onValueChanged: if (valid) root.updateModel("cellDiff", value)
    }
    VeQuickItem {
        uid: root.serviceUid + "/History/ChargeCycles"
        onValueChanged: if (valid) root.updateModel("cycles", value)
    }
    // Issue 3 fix: Disconnection handling
    // Watch /Connected to detect service going offline
    VeQuickItem {
        id: connectedItem
        uid: root.serviceUid + "/Connected"
        onValidChanged: {
            var idx = root.findModelIndex()
            if (idx >= 0) root.batteryModel.setProperty(idx, "online", valid)
        }
        onValueChanged: {
            var idx = root.findModelIndex()
            if (idx >= 0) root.batteryModel.setProperty(idx, "online", valid && value === 1)
        }
    }
}
