import QtQuick
import Victron.VenusOS

SwipeViewPage {
    id: root

    navButtonText: "Batteries"
    navButtonIcon: "qrc:/images/icon_battery_24.svg"
    url: "file:///data/venus-btbattery-gui/qml/PageBatteryParallelOverview.qml"

    // Config — loaded from generated ConfigData.qml
    property int socColorGreen: 60
    property int socColorYellow: 20
    property int socColorRed: 10
    property int maxBatteries: 8
    property var nameMap: ({})   // MAC string -> display name
    property var batOrder: []    // MAC strings in config order

    // Font config
    property int fontBatNameSize: 13
    property bool fontBatNameBold: true
    property int fontBatSocSize: 20
    property bool fontBatSocBold: true
    property int fontBatStatsSize: 16
    property bool fontBatStatsBold: false
    property int fontBankLabelSize: 12
    property bool fontBankLabelBold: false
    property int fontBankValueSize: 20
    property bool fontBankValueBold: true

    Component.onCompleted: loadConfig()

    function loadConfig() {
        var comp = Qt.createComponent(Qt.resolvedUrl("ConfigData.qml"))
        if (comp.status === Component.Ready) {
            var cfg = comp.createObject(root)
            if (!cfg) return
            socColorGreen = cfg.socColorGreen
            socColorYellow = cfg.socColorYellow
            socColorRed = cfg.socColorRed
            maxBatteries = cfg.maxBatteries
            nameMap = cfg.btNames || {}
            batOrder = cfg.batOrder || []
            fontBatNameSize = cfg.fontBatNameSize
            fontBatNameBold = cfg.fontBatNameBold
            fontBatSocSize = cfg.fontBatSocSize
            fontBatSocBold = cfg.fontBatSocBold
            fontBatStatsSize = cfg.fontBatStatsSize
            fontBatStatsBold = cfg.fontBatStatsBold
            fontBankLabelSize = cfg.fontBankLabelSize
            fontBankLabelBold = cfg.fontBankLabelBold
            fontBankValueSize = cfg.fontBankValueSize
            fontBankValueBold = cfg.fontBankValueBold
            cfg.destroy()
        }
    }

    // D-Bus discovery
    property var discoveredServices: ({})
    property int nextUnnamedIndex: 1
    property var batteryBindings: []
    property var aggregateBinding: null

    // Watch for battery services on D-Bus
    VeQuickItem {
        id: batteriesItem
        uid: "dbus/com.victronenergy.system/Batteries"
        onValidChanged: {
            if (valid && value) batteriesItem.processBatteries(value)
        }
        onValueChanged: {
            if (!valid || !value) return
            batteriesItem.processBatteries(value)
        }
        function processBatteries(val) {
            try {
                var batteries = typeof val === "string" ? JSON.parse(val) : val
                if (!batteries || !batteries.length) return
                for (var i = 0; i < batteries.length; i++) {
                    var bat = batteries[i]
                    var svcName = typeof bat === "string" ? bat : (bat.id || bat.service || bat.name || "")
                    if (svcName === "com.victronenergy.battery.parallel") {
                        root.bindAggregate("dbus/" + svcName)
                    } else if (svcName.indexOf("com.victronenergy.battery.") === 0) {
                        root.onBatteryServiceFound(svcName)
                    }
                }
            } catch (e) {
                console.warn("venus-btbattery-gui: Could not parse /Batteries:", e)
            }
        }
    }

    // Fallback: watch for the parallel aggregate service directly
    VeQuickItem {
        id: parallelCheck
        uid: "dbus/com.victronenergy.battery.parallel/Soc"
        onValidChanged: {
            if (valid) root.bindAggregate("dbus/com.victronenergy.battery.parallel")
        }
    }

    function extractMac(serviceName) {
        var hex = serviceName.replace("com.victronenergy.battery.bt", "").toLowerCase()
        if (hex.indexOf(":") === -1 && hex.indexOf("_") === -1 && hex.length === 12)
            return hex.match(/.{2}/g).join(":")
        return hex.replace(/_/g, ":")
    }

    function onBatteryServiceFound(serviceName) {
        if (serviceName === "com.victronenergy.battery.parallel") return
        if (discoveredServices[serviceName]) return
        if (!serviceName.match(/\.bt[0-9a-fA-F]/)) return
        if (batteryModel.count >= maxBatteries) return

        var mac = extractMac(serviceName)
        var configName = nameMap[mac] || ""
        var displayName = configName || ("Battery " + nextUnnamedIndex++)
        var serviceUid = "dbus/" + serviceName

        // Determine insert position: ordered batteries by batOrder, unnamed appended
        var insertIdx = batteryModel.count
        var configIdx = batOrder.indexOf(mac)
        if (configIdx >= 0) {
            insertIdx = 0
            for (var i = 0; i < batteryModel.count; i++) {
                var existingConfigIdx = batOrder.indexOf(batteryModel.get(i).mac)
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

        var component = Qt.createComponent(Qt.resolvedUrl("BatteryBinding.qml"))
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
        var component = Qt.createComponent(Qt.resolvedUrl("AggregateBinding.qml"))
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

    // Sizing — scaled for 480x272 Touch 70 screen
    property int batteryCount: batteryModel.count
    property int iconWidth: batteryCount <= 4 ? 62 : (batteryCount <= 6 ? 52 : 44)
    property int iconHeight: batteryCount <= 4 ? 125 : (batteryCount <= 6 ? 106 : 88)

    // SOC color helper
    function socColor(soc) {
        if (soc >= socColorGreen) return "#4caf50"
        if (soc >= socColorYellow) return "#ff9800"
        if (soc >= socColorRed) return "#f44336"
        return "#d32f2f"
    }

    // === MAIN CONTENT — vertically centered ===
    Column {
        id: mainContent
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        // === BATTERY ROW ===
        Row {
            id: batteryRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: (root.width - batteryCount * (iconWidth + 20)) / (batteryCount + 1)

            Repeater {
                model: batteryModel
                delegate: Column {
                    width: root.iconWidth + 20
                    spacing: 1

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

                    Item { width: 1; height: 4 }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: model.name
                        color: "#4fc3f7"
                        font.pixelSize: root.fontBatNameSize
                        font.bold: root.fontBatNameBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: model.soc + "%"
                        color: root.socColor(model.soc)
                        font.pixelSize: root.fontBatSocSize
                        font.bold: root.fontBatSocBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: model.voltage.toFixed(2) + "V \u00B7 " + model.current.toFixed(1) + "A"
                        color: "#aaaaaa"
                        font.pixelSize: root.fontBatStatsSize
                        font.bold: root.fontBatStatsBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: model.temperature + "\u00B0C \u00B7 \u0394V " + model.cellDiff.toFixed(2)
                        color: "#aaaaaa"
                        font.pixelSize: root.fontBatStatsSize
                        font.bold: root.fontBatStatsBold
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: model.cycles + " cycles"
                        color: "#aaaaaa"
                        font.pixelSize: root.fontBatStatsSize
                        font.bold: root.fontBatStatsBold
                    }
                }
            }
        }

        // === SEPARATOR ===
        Item { width: 1; height: 4 }
        Rectangle {
            width: batteryRow.width
            height: 1
            color: root.accentColor
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Item { width: 1; height: 4 }

        // === BANK AGGREGATE ROW ===
        Row {
            id: aggregateRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16

            Column {
                spacing: 1
                Text {
                    text: root.bankState.charAt(0).toUpperCase() + root.bankState.slice(1)
                    color: root.accentColor
                    font.pixelSize: root.fontBankValueSize
                    font.bold: root.fontBankValueBold
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Column {
                spacing: 1
                Text { text: "BANK SOC"; color: "#888888"; font.pixelSize: root.fontBankLabelSize; font.bold: root.fontBankLabelBold; anchors.horizontalCenter: parent.horizontalCenter }
                Text { text: root.bankSoc + "%"; color: root.socColor(root.bankSoc); font.pixelSize: root.fontBankValueSize; font.bold: root.fontBankValueBold; anchors.horizontalCenter: parent.horizontalCenter }
            }

            Column {
                spacing: 1
                Text { text: "VOLTAGE"; color: "#888888"; font.pixelSize: root.fontBankLabelSize; font.bold: root.fontBankLabelBold; anchors.horizontalCenter: parent.horizontalCenter }
                Text { text: root.bankVoltage.toFixed(2) + "V"; color: "#ffffff"; font.pixelSize: root.fontBankValueSize; font.bold: root.fontBankValueBold; anchors.horizontalCenter: parent.horizontalCenter }
            }

            Column {
                spacing: 1
                Text { text: "CURRENT"; color: "#888888"; font.pixelSize: root.fontBankLabelSize; font.bold: root.fontBankLabelBold; anchors.horizontalCenter: parent.horizontalCenter }
                Text { text: root.bankCurrent.toFixed(1) + "A"; color: root.accentColor; font.pixelSize: root.fontBankValueSize; font.bold: root.fontBankValueBold; anchors.horizontalCenter: parent.horizontalCenter }
            }

            Column {
                spacing: 1
                Text { text: "CAPACITY"; color: "#888888"; font.pixelSize: root.fontBankLabelSize; font.bold: root.fontBankLabelBold; anchors.horizontalCenter: parent.horizontalCenter }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 0
                    Text { id: capText; text: Math.round(root.bankCapacity).toString(); color: "#ffffff"; font.pixelSize: root.fontBankValueSize; font.bold: root.fontBankValueBold }
                    Text { text: " / " + Math.round(root.bankInstalledCapacity) + " Ah"; color: "#888888"; font.pixelSize: root.fontBankLabelSize + 2; anchors.baseline: capText.baseline }
                }
            }
        }
    }

    // === DISCOVERING PLACEHOLDER ===
    Text {
        anchors.centerIn: parent
        text: "Discovering batteries..."
        color: "#888888"
        font.pixelSize: 14
        visible: batteryModel.count === 0
    }
}
