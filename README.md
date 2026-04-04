# venus-btbattery-gui

VenusOS QML overview page for parallel battery banks
monitored by
[dbus-btbattery](https://github.com/pace551/dbus-btbattery).

Displays animated battery icons with per-battery stats
(SOC, voltage, current, temperature, cell voltage delta,
charge cycles) and bank-level aggregates on the Cerbo GX
touchscreen. Temperatures are displayed in Fahrenheit.

## Requirements

- VenusOS v3.x (gui-v2)
- [dbus-btbattery](https://github.com/pace551/dbus-btbattery)
  running in parallel mode
- Cerbo GX with touchscreen (800x480) or Remote Console

## Installation

SSH into your VenusOS device:

```bash
cd /tmp
wget https://github.com/pace551/venus-btbattery-gui/archive/main.tar.gz
tar xzf main.tar.gz
cd venus-btbattery-gui-main
```

Edit `config.ini` with your battery MAC addresses
and names:

```ini
[GUI]
BT_NAMES = 70:3e:97:08:00:62=Bat A,a4:c1:38:xx:xx:xx=Bat B
```

Install:

```bash
bash install.sh
```

The page appears in the Remote Console swipe carousel.
Files are stored on `/data` and survive firmware
upgrades -- the install script patches
`SwipePageModel.qml` and sets up `rc.local` to
re-apply the patch on each boot.

## Uninstall

```bash
bash /data/venus-btbattery-gui/uninstall.sh
```

## Configuration

Edit `/data/venus-btbattery-gui/config.ini` via SSH:

### Battery Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `BT_NAMES` | (empty) | MAC=Name pairs, comma-separated. Batteries render in the order listed; unlisted batteries appended after. |
| `SOC_COLOR_GREEN` | 60 | SOC% threshold for green fill |
| `SOC_COLOR_YELLOW` | 20 | SOC% threshold for yellow/orange fill |
| `SOC_COLOR_RED` | 10 | SOC% threshold for red fill / critical |
| `MAX_BATTERIES` | 8 | Max batteries to display (1-8) |

### Font Customization

| Setting | Default | Description |
|---------|---------|-------------|
| `FONT_BAT_NAME_SIZE` | 13 | Battery name label font size (px) |
| `FONT_BAT_NAME_BOLD` | true | Battery name label bold |
| `FONT_BAT_SOC_SIZE` | 20 | Battery SOC percentage font size (px) |
| `FONT_BAT_SOC_BOLD` | true | Battery SOC percentage bold |
| `FONT_BAT_STATS_SIZE` | 16 | Battery stats (voltage, current, temp, cycles) font size (px) |
| `FONT_BAT_STATS_BOLD` | false | Battery stats bold |
| `FONT_BANK_LABEL_SIZE` | 13 | Bank aggregate labels font size (px) |
| `FONT_BANK_LABEL_BOLD` | false | Bank aggregate labels bold |
| `FONT_BANK_VALUE_SIZE` | 20 | Bank aggregate values font size (px) |
| `FONT_BANK_VALUE_BOLD` | true | Bank aggregate values bold |

Restart the GUI after config changes:
`svc -t /service/gui`

## Battery States

| State | Indicators |
|-------|-----------|
| Charging | Pulsing fill, wavy top, bubbles, bolt |
| Discharging | Gentle fade, falling drips, arrow |
| Idle | Static fill, no animations |
| Offline | Greyed icon, "Offline" text |

## Desktop Testing

For development without VenusOS hardware:

```bash
# Terminal 1: Start mock D-Bus services
python3 tools/mock_dbus.py \
  --session-bus --batteries 4 --state charging

# Terminal 2: Run QML page
QML2_IMPORT_PATH=qml qmlscene \
  qml/PageBatteryParallelOverview.qml
```

Note: Desktop testing requires a VeQuickItem shim
since the Victron.VenusOS module is only available
on VenusOS.

States: `charging`, `discharging`, `mixed`

## License

MIT
