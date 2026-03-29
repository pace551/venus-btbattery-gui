# gui-v2 QML API Research

## Imports

- `import QtQuick` (Qt 6 style, no version numbers)
- `import Victron.VenusOS`

## D-Bus Binding: VeQuickItem

Replaces gui-v1's `VBusItem`. Usage:

```qml
VeQuickItem {
    id: batteryVoltage
    uid: "dbus/com.victronenergy.battery.ttyUSB0"
         + "/Dc/0/Voltage"
}
// Access: batteryVoltage.value, batteryVoltage.valid
```

UID format: `"dbus/<service-name>/<path>"`
or `"mqtt/<type>/<instance>/<path>"`

Helper:
`BackendConnection.serviceUidFromName(svcName, devInst)`

## Page Registration

Main pages are hardcoded in `SwipePageModel.qml` as
`SwipeViewPage` entries in an `ObjectModel`. No dynamic
registration API. NavigationPage plugin type exists but
is NOT implemented (marked TODO).

Our approach: Patch `SwipePageModel.qml` via install
script + rc.local re-patch on boot.

## Battery Discovery

Centralized via `com.victronenergy.system/Batteries`
JSON array. Can also bind directly to known service
UIDs with VeQuickItem.

## Key Base Components

- `SwipeViewPage` -- for main carousel pages
  (navButtonText, navButtonIcon, url)
- `DevicePage` -- for device settings pages
  (serviceUid, settingsModel)
- `Page` -- base for all pages

## Key Files in gui-v2

- `components/SwipePageModel.qml` --
  page carousel registration
- `pages/settings/devicelist/battery/PageBattery.qml` --
  battery settings page
- `components/widgets/BatteryWidget.qml` --
  overview battery widget
- `components/SystemBatteryDeviceModel.qml` --
  battery list from system/Batteries
