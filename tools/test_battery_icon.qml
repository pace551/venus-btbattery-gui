import QtQuick
import QtQuick.Window

Window {
    width: 800
    height: 480
    visible: true
    color: "#1a1a2e"
    title: "BatteryIcon Animation Test"

    Column {
        anchors.centerIn: parent
        spacing: 20

        Row {
            spacing: 30
            Text { text: "Charging:"; color: "#4fc3f7"; font.pixelSize: 14; font.bold: true; width: 100; anchors.verticalCenter: parent.verticalCenter }
            Repeater {
                model: [80, 79, 80, 81]
                Column {
                    required property int modelData
                    spacing: 4
                    BatteryIcon {
                        width: 56; height: 110
                        soc: parent.modelData; current: 5.2; state: "charging"; online: true
                    }
                    Text { text: parent.modelData + "%"; color: "#4caf50"; font.pixelSize: 12; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                }
            }
        }

        Row {
            spacing: 30
            Text { text: "Discharging:"; color: "#ff8a65"; font.pixelSize: 14; font.bold: true; width: 100; anchors.verticalCenter: parent.verticalCenter }
            Repeater {
                model: [65, 40, 15, 5]
                Column {
                    required property int modelData
                    spacing: 4
                    BatteryIcon {
                        width: 56; height: 110
                        soc: parent.modelData; current: -12.0; state: "discharging"; online: true
                    }
                    Text { text: parent.modelData + "%"; color: "#e0e0e0"; font.pixelSize: 12; anchors.horizontalCenter: parent.horizontalCenter }
                }
            }
        }

        Row {
            spacing: 30
            Text { text: "Idle/Off:"; color: "#888"; font.pixelSize: 14; font.bold: true; width: 100; anchors.verticalCenter: parent.verticalCenter }
            Column {
                spacing: 4
                BatteryIcon {
                    width: 56; height: 110
                    soc: 75; current: 0; state: "idle"; online: true
                }
                Text { text: "75% idle"; color: "#e0e0e0"; font.pixelSize: 12; anchors.horizontalCenter: parent.horizontalCenter }
            }
            Column {
                spacing: 4
                BatteryIcon {
                    width: 56; height: 110
                    soc: 50; current: 0; state: "idle"; online: false
                }
                Text { text: "Offline"; color: "#888"; font.pixelSize: 12; anchors.horizontalCenter: parent.horizontalCenter }
            }
        }
    }
}
