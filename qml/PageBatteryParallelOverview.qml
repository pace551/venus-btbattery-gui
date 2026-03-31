import QtQuick
import Victron.VenusOS

Rectangle {
    id: root
    width: 800
    height: 480
    color: "#1a1a2e"

    // Config properties (loaded from config.ini)
    property int socColorGreen: 60
    property int socColorYellow: 20
    property int socColorRed: 10
    property int maxBatteries: 8

    // Config: MAC-to-name mapping
    property var nameMap: ({})   // MAC string -> display name
    property var nameOrder: []   // MAC strings in config order

    Component.onCompleted: loadConfig()

    function loadConfig() {
        var xhr = new XMLHttpRequest()
        var configPath = "/data/venus-btbattery-gui/config.ini"
        xhr.open("GET", "file://" + configPath, false)
        xhr.send()

        var text = xhr.responseText
        if (!text || text.length === 0) {
            xhr.open("GET", "../config.ini", false)
            xhr.send()
            text = xhr.responseText
        }
        if (!text) return

        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line.indexOf("#") === 0 || line.indexOf("[") === 0 || line.indexOf("=") === -1) continue

            var eqIdx = line.indexOf("=")
            var key = line.substring(0, eqIdx).trim()
            var val = line.substring(eqIdx + 1).trim()

            if (key === "SOC_COLOR_GREEN") socColorGreen = parseInt(val)
            else if (key === "SOC_COLOR_YELLOW") socColorYellow = parseInt(val)
            else if (key === "SOC_COLOR_RED") socColorRed = parseInt(val)
            else if (key === "MAX_BATTERIES") maxBatteries = parseInt(val)
            else if (key === "BT_NAMES" && val.length > 0) {
                var pairs = val.split(",")
                var map = {}
                var order = []
                for (var j = 0; j < pairs.length; j++) {
                    var pair = pairs[j].trim()
                    var sepIdx = pair.indexOf("=")
                    if (sepIdx === -1) continue
                    var mac = pair.substring(0, sepIdx).trim().toLowerCase()
                    var name = pair.substring(sepIdx + 1).trim().substring(0, 6)
                    map[mac] = name
                    order.push(mac)
                }
                nameMap = map
                nameOrder = order
            }
        }
    }

    // D-Bus discovery
    property var discoveredServices: ({})
    property int nextUnnamedIndex: 1
    property var batteryBindings: []
    property var aggregateBinding: null

    // Watch for battery services on D-Bus
    // Strategy 1: Read system/Batteries list
    VeQuickItem {
        id: batteriesItem
        uid: BackendConnection.serviceUidForType("system") + "/Batteries"
        onValueChanged: {
            if (!valid || !value) return
            try {
                // Value may be a JSON string or a native array
                var batteries = typeof value === "string" ? JSON.parse(value) : value
                if (!Array.isArray(batteries)) return
                for (var i = 0; i < batteries.length; i++) {
                    var bat = batteries[i]
                    // Handle both object format {id:"svc"} and string format "svc"
                    var svcName = typeof bat === "string" ? bat : (bat.id || bat.service || bat.name || "")
                    if (svcName.indexOf("com.victronenergy.battery.") === 0) {
                        root.onBatteryServiceFound(svcName)
                    }
                }
            } catch (e) {
                console.warn("venus-btbattery-gui: Could not parse /Batteries:", e)
            }
        }
    }

    // Also watch for the parallel aggregate service directly
    VeQuickItem {
        id: parallelCheck
        uid: "dbus/com.victronenergy.battery.parallel/ProductName"
        onValidChanged: {
            if (valid) root.bindAggregate("dbus/com.victronenergy.battery.parallel")
        }
    }

    function extractMac(serviceName) {
        var suffix = serviceName.replace("com.victronenergy.battery.bt", "")
        return suffix.replace(/_/g, ":").toLowerCase()
    }

    function onBatteryServiceFound(serviceName) {
        if (serviceName === "com.victronenergy.battery.parallel") return
        if (discoveredServices[serviceName]) return
        if (!serviceName.match(/\.bt[0-9a-f]/)) return
        if (batteryModel.count >= maxBatteries) return

        var mac = extractMac(serviceName)
        var configName = nameMap[mac] || ""
        var displayName = configName || ("Battery " + nextUnnamedIndex++)
        var serviceUid = "dbus/" + serviceName

        // Determine insert position: named batteries in config order, unnamed appended
        var insertIdx = batteryModel.count
        if (nameMap[mac]) {
            var configIdx = nameOrder.indexOf(mac)
            insertIdx = 0
            for (var i = 0; i < batteryModel.count; i++) {
                var existingMac = batteryModel.get(i).mac
                var existingConfigIdx = nameOrder.indexOf(existingMac)
                if (existingConfigIdx === -1 || existingConfigIdx < configIdx) {
                    insertIdx = i + 1
                } else {
                    break
                }
            }
        }

        batteryModel.insert(insertIdx, {
            name: displayName,
            mac: mac,
            serviceName: serviceName,
            serviceUid: serviceUid,
            soc: 0, voltage: 0, current: 0,
            temperature: 0, cellDiff: 0, cycles: 0,
            online: true
        })

        discoveredServices[serviceName] = true

        // Create binding component
        var component = Qt.createComponent("BatteryBinding.qml")
        if (component.status === Component.Ready) {
            var binding = component.createObject(root, {
                serviceUid: serviceUid,
                serviceName: serviceName,
                batteryModel: batteryModel,
                configName: configName
            })
            batteryBindings.push(binding)
        }
    }

    function bindAggregate(serviceUid) {
        if (aggregateBinding) return
        var component = Qt.createComponent("AggregateBinding.qml")
        if (component.status === Component.Ready) {
            aggregateBinding = component.createObject(root, {
                serviceUid: serviceUid
            })
        }
    }

    // Bank aggregate — bound to aggregate service
    property int bankSoc: aggregateBinding ? Math.round(aggregateBinding.soc) : 0
    property real bankVoltage: aggregateBinding ? aggregateBinding.voltage : 0
    property real bankCurrent: aggregateBinding ? aggregateBinding.current : 0
    property real bankCapacity: aggregateBinding ? aggregateBinding.capacity : 0
    property real bankInstalledCapacity: aggregateBinding ? aggregateBinding.installedCapacity : 0

    // Bank state detection (0.5A deadband)
    property string bankState: {
        if (!aggregateBinding) return "idle"
        if (aggregateBinding.current > 0.5) return "charging"
        if (aggregateBinding.current < -0.5) return "discharging"
        return "idle"
    }

    property color accentColor: {
        if (bankState === "charging") return "#4fc3f7"
        if (bankState === "discharging") return "#ff8a65"
        return "#888888"
    }

    // Battery model — populated by D-Bus discovery
    ListModel { id: batteryModel }

    // Sizing function based on battery count
    property int batteryCount: batteryModel.count
    property int iconWidth: batteryCount <= 4 ? 56 : (batteryCount <= 6 ? 48 : 40)
    property int iconHeight: batteryCount <= 4 ? 110 : (batteryCount <= 6 ? 95 : 80)
    property int statFontSize: batteryCount <= 4 ? 13 : (batteryCount <= 6 ? 12 : 11)
    property int socFontSize: batteryCount <= 4 ? 18 : (batteryCount <= 6 ? 16 : 14)

    // SOC color helper
    function socColor(soc) {
        if (soc >= socColorGreen) return "#4caf50"
        if (soc >= socColorYellow) return "#ff9800"
        if (soc >= socColorRed) return "#f44336"
        return "#d32f2f"
    }

    // === TITLE BAR ===
    Text {
        id: titleBar
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 8
        text: {
            var stateLabel = root.bankState.charAt(0).toUpperCase() + root.bankState.slice(1)
            return "\u26A1 Parallel Battery Bank \u2014 " + stateLabel
        }
        color: root.accentColor
        font.pixelSize: 16
        font.bold: true
    }

    // === BATTERY ROW ===
    Row {
        id: batteryRow
        anchors.top: titleBar.bottom
        anchors.topMargin: 12
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: (root.width - batteryCount * (iconWidth + 20)) / (batteryCount + 1)

        Repeater {
            model: batteryModel
            delegate: Column {
                width: root.iconWidth + 20
                spacing: 2

                BatteryIcon {
                    width: root.iconWidth
                    height: root.iconHeight
                    anchors.horizontalCenter: parent.horizontalCenter
                    soc: model.soc
                    current: model.current
                    state: root.bankState
                    online: model.online
                    socColorGreen: root.socColorGreen
                    socColorYellow: root.socColorYellow
                    socColorRed: root.socColorRed
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: model.name
                    color: "#4fc3f7"
                    font.pixelSize: root.statFontSize + 1
                    font.bold: true
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: model.soc + "%"
                    color: root.socColor(model.soc)
                    font.pixelSize: root.socFontSize
                    font.bold: true
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: model.voltage.toFixed(2) + "V \u00B7 " + model.current.toFixed(1) + "A"
                    color: "#aaaaaa"
                    font.pixelSize: root.statFontSize
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: model.temperature + "\u00B0C \u00B7 \u0394V " + model.cellDiff.toFixed(2)
                    color: "#aaaaaa"
                    font.pixelSize: root.statFontSize
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: model.cycles + " cycles"
                    color: "#aaaaaa"
                    font.pixelSize: root.statFontSize
                }
            }
        }
    }

    // === SEPARATOR ===
    Rectangle {
        id: separator
        anchors.top: batteryRow.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        height: 2
        color: root.accentColor
    }

    // === BANK AGGREGATE ROW ===
    Row {
        id: aggregateRow
        anchors.top: separator.bottom
        anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 40

        Column {
            spacing: 2
            Text { text: "BANK SOC"; color: "#888888"; font.pixelSize: 11; anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: root.bankSoc + "%"; color: root.socColor(root.bankSoc); font.pixelSize: 22; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
        }

        Column {
            spacing: 2
            Text { text: "VOLTAGE"; color: "#888888"; font.pixelSize: 11; anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: root.bankVoltage.toFixed(2) + "V"; color: "#ffffff"; font.pixelSize: 22; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
        }

        Column {
            spacing: 2
            Text { text: "TOTAL CURRENT"; color: "#888888"; font.pixelSize: 11; anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: root.bankCurrent.toFixed(1) + "A"; color: root.accentColor; font.pixelSize: 22; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
        }

        Column {
            spacing: 2
            Text { text: "CAPACITY"; color: "#888888"; font.pixelSize: 11; anchors.horizontalCenter: parent.horizontalCenter }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 0
                Text { id: capText; text: Math.round(root.bankCapacity).toString(); color: "#ffffff"; font.pixelSize: 22; font.bold: true }
                Text { text: " / " + Math.round(root.bankInstalledCapacity) + " Ah"; color: "#888888"; font.pixelSize: 14; anchors.baseline: capText.baseline }
            }
        }
    }

    // === DISCOVERING PLACEHOLDER ===
    Text {
        anchors.centerIn: parent
        text: "Discovering batteries..."
        color: "#888888"
        font.pixelSize: 16
        visible: batteryModel.count === 0
    }
}
