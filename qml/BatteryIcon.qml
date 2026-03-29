import QtQuick

Item {
    id: root

    // Input properties
    property int soc: 0
    property real current: 0.0
    property string state: "idle"  // "charging", "discharging", "idle"
    property bool online: true

    // Color thresholds from config
    property int socColorGreen: 60
    property int socColorYellow: 20
    property int socColorRed: 10

    // Computed properties
    property color fillColorTop: {
        if (!online) return "#555"
        if (soc >= socColorGreen) return "#4caf50"
        if (soc >= socColorYellow) return "#ff9800"
        if (soc >= socColorRed) return "#f44336"
        return "#d32f2f"
    }
    property color fillColorBottom: {
        if (!online) return "#333"
        if (soc >= socColorGreen) return "#2e7d32"
        if (soc >= socColorYellow) return "#e65100"
        if (soc >= socColorRed) return "#b71c1c"
        return "#880e0e"
    }
    property color fillTopEdgeColor: {
        if (!online) return "#666"
        if (soc >= socColorGreen) return "#66bb6a"
        if (soc >= socColorYellow) return "#ffb74d"
        if (soc >= socColorRed) return "#e57373"
        return "#ef5350"
    }
    property bool isCritical: online && soc < socColorRed
    property color shellBorderColor: isCritical ? "#f44336" : "#666666"

    // Terminal nub
    Rectangle {
        id: terminal
        width: parent.width * 0.4
        height: parent.height * 0.07
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: shell.top
        color: "#666666"
        radius: 3
    }

    // Shell
    Rectangle {
        id: shell
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * 0.88
        color: "#111111"
        border.color: root.shellBorderColor
        border.width: 3
        radius: 6
        clip: true

        // Critical glow effect
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: "#f44336"
            border.width: 3
            radius: parent.radius
            opacity: root.isCritical ? 0.4 : 0
            visible: root.isCritical

            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                color: "transparent"
                border.color: "#f44336"
                border.width: 2
                radius: parent.radius + 4
                opacity: 0.2
            }
        }

        // Fill rectangle
        Rectangle {
            id: fill
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: shell.border.width
            anchors.rightMargin: shell.border.width
            anchors.bottomMargin: shell.border.width
            height: Math.max(0, (shell.height - shell.border.width * 2) * root.soc / 100)
            radius: 3

            gradient: Gradient {
                GradientStop { position: 0.0; color: root.fillColorTop }
                GradientStop { position: 1.0; color: root.fillColorBottom }
            }

            // Top edge highlight
            Rectangle {
                id: fillTopEdge
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: -2
                height: 4
                radius: 2
                color: root.fillTopEdgeColor
            }
        }

        // === Charging animations ===

        // Fill pulse (charging)
        OpacityAnimator {
            target: fill
            from: 0.85
            to: 1.0
            duration: 2000
            loops: Animation.Infinite
            running: root.online && root.state === "charging"
            easing.type: Easing.InOutSine
        }

        // Top edge wavy bounce (charging)
        SequentialAnimation {
            loops: Animation.Infinite
            running: root.online && root.state === "charging"
            NumberAnimation {
                target: fillTopEdge
                property: "anchors.topMargin"
                from: -4
                to: 0
                duration: 750
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: fillTopEdge
                property: "anchors.topMargin"
                from: 0
                to: -4
                duration: 750
                easing.type: Easing.InOutSine
            }
        }

        // Rising bubbles (charging)
        Repeater {
            model: 3
            Rectangle {
                id: bubble
                required property int index
                readonly property real startX: [0.25, 0.55, 0.4][index]
                readonly property int delay: [0, 700, 1300][index]
                readonly property real startY: 0.8
                width: 4
                height: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.3)
                x: fill.x + fill.width * startX
                visible: root.online && root.state === "charging"

                SequentialAnimation on y {
                    loops: Animation.Infinite
                    running: root.online && root.state === "charging"
                    PauseAnimation { duration: bubble.delay }
                    NumberAnimation {
                        from: fill.y + fill.height * bubble.startY
                        to: fill.y + fill.height * bubble.startY - 40
                        duration: 2000
                        easing.type: Easing.Linear
                    }
                }

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: root.online && root.state === "charging"
                    PauseAnimation { duration: bubble.delay }
                    NumberAnimation {
                        from: 0.6
                        to: 0
                        duration: 2000
                        easing.type: Easing.Linear
                    }
                }
            }
        }

        // Bolt overlay (charging)
        Text {
            anchors.centerIn: parent
            text: "\u26A1"
            font.pixelSize: 22
            color: Qt.rgba(1, 1, 0.78, 0.8)
            style: Text.Outline
            styleColor: Qt.rgba(1, 1, 0, 0.4)
            visible: root.online && root.state === "charging"
        }

        // === Discharging animations ===

        // Fill gentle fade (discharging)
        OpacityAnimator {
            target: fill
            from: 0.75
            to: 0.9
            duration: 2500
            loops: Animation.Infinite
            running: root.online && root.state === "discharging"
            easing.type: Easing.InOutSine
        }

        // Falling drips (discharging)
        Repeater {
            model: 3
            Rectangle {
                id: drip
                required property int index
                readonly property real startX: [0.28, 0.5, 0.72][index]
                readonly property int delay: [0, 900, 1500][index]
                width: 4
                height: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.45)
                x: fill.x + fill.width * startX
                visible: root.online && root.state === "discharging"

                SequentialAnimation on y {
                    loops: Animation.Infinite
                    running: root.online && root.state === "discharging"
                    PauseAnimation { duration: drip.delay }
                    NumberAnimation {
                        from: fill.y
                        to: fill.y + 35
                        duration: 1800
                        easing.type: Easing.Linear
                    }
                }

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: root.online && root.state === "discharging"
                    PauseAnimation { duration: drip.delay }
                    NumberAnimation {
                        from: 0.7
                        to: 0
                        duration: 1800
                        easing.type: Easing.Linear
                    }
                }
            }
        }

        // Arrow overlay (discharging)
        Text {
            anchors.centerIn: parent
            text: "\u25BC"
            font.pixelSize: 20
            font.bold: true
            color: Qt.rgba(0.9, 0.9, 0.9, 0.7)
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.8)
            visible: root.online && root.state === "discharging"
        }

        // === Idle state ===

        // Reset opacity when idle or offline
        Binding {
            target: fill
            property: "opacity"
            value: 1.0
            when: root.state === "idle" || !root.online
        }

        // Offline text overlay
        Text {
            anchors.centerIn: parent
            text: "Offline"
            color: "#888888"
            font.pixelSize: 11
            font.bold: true
            visible: !root.online
        }
    }
}
