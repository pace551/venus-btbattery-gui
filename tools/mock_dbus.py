#!/usr/bin/env python3
"""Mock D-Bus services for desktop testing of venus-btbattery-gui.

Publishes fake battery D-Bus services that mimic what dbus-btbattery
produces in parallel mode. Supports configurable battery count, SOC
levels, and charge/discharge simulation.

Usage:
    python3 tools/mock_dbus.py                    # 4 batteries, charging at 80%
    python3 tools/mock_dbus.py --batteries 2      # 2 batteries
    python3 tools/mock_dbus.py --state discharging # simulate discharge
    python3 tools/mock_dbus.py --state mixed       # mixed SOC levels for color testing
"""

import argparse
import sys
import signal

try:
    import dbus
    import dbus.service
    import dbus.mainloop.glib
    from gi.repository import GLib
except ImportError:
    print("Error: requires dbus-python and PyGObject")
    print("Install: pip install dbus-python PyGObject")
    sys.exit(1)


BATTERY_MACS = [
    "70_3e_97_08_00_62",
    "a4_c1_38_01_02_03",
    "a4_c1_38_04_05_06",
    "a4_c1_38_07_08_09",
    "a4_c1_38_0a_0b_0c",
    "a4_c1_38_0d_0e_0f",
    "a4_c1_38_10_11_12",
    "a4_c1_38_13_14_15",
]

CHARGING_DEFAULTS = {
    "soc": [80, 79, 80, 81, 78, 80, 79, 81],
    "voltage": [13.21, 13.20, 13.22, 13.19, 13.21, 13.20, 13.22, 13.18],
    "current": [5.2, 5.1, 5.3, 4.9, 5.0, 5.2, 5.1, 4.8],
    "temperature": [25, 26, 24, 27, 25, 26, 24, 28],
    "cell_diff": [0.02, 0.01, 0.03, 0.01, 0.02, 0.01, 0.03, 0.02],
    "cycles": [42, 38, 42, 15, 42, 38, 42, 15],
}

DISCHARGING_DEFAULTS = {
    "soc": [65, 63, 64, 66, 62, 65, 63, 67],
    "voltage": [13.10, 13.08, 13.09, 13.11, 13.07, 13.10, 13.08, 13.12],
    "current": [-12.1, -11.8, -12.3, -11.5, -12.0, -11.9, -12.2, -11.6],
    "temperature": [28, 29, 30, 27, 28, 29, 30, 27],
    "cell_diff": [0.03, 0.05, 0.04, 0.02, 0.03, 0.05, 0.04, 0.02],
    "cycles": [42, 38, 42, 15, 42, 38, 42, 15],
}

MIXED_DEFAULTS = {
    "soc": [65, 40, 15, 5, 80, 30, 10, 50],
    "voltage": [13.10, 12.90, 12.40, 11.80, 13.21, 12.80, 12.30, 13.00],
    "current": [-12.1, -11.8, -12.3, -11.5, -12.0, -11.9, -12.2, -11.6],
    "temperature": [28, 29, 30, 31, 25, 29, 30, 28],
    "cell_diff": [0.03, 0.05, 0.08, 0.12, 0.02, 0.06, 0.09, 0.04],
    "cycles": [42, 38, 42, 15, 42, 38, 42, 15],
}


class BatteryService(dbus.service.Object):
    """A single mock battery D-Bus service."""

    def __init__(self, bus, path, data):
        super().__init__(bus, path)
        self._data = data

    @dbus.service.method("com.victronenergy.BusItem", out_signature="v")
    def GetValue(self):
        return self._data

    @dbus.service.method("com.victronenergy.BusItem", in_signature="v")
    def SetValue(self, value):
        self._data = value


class MockBattery:
    """Registers a full mock battery service on D-Bus."""

    def __init__(self, bus, mac, soc, voltage, current, temperature, cell_diff, cycles, product_name):
        service_name = f"com.victronenergy.battery.bt{mac}"
        self._bus_name = dbus.service.BusName(service_name, bus)

        self.items = {}
        paths = {
            "/Soc": dbus.Double(soc),
            "/Dc/0/Voltage": dbus.Double(voltage),
            "/Dc/0/Current": dbus.Double(current),
            "/Dc/0/Temperature": dbus.Double(temperature),
            "/Voltages/Diff": dbus.Double(cell_diff),
            "/History/ChargeCycles": dbus.Int32(cycles),
            "/ProductName": dbus.String(product_name),
            "/Connected": dbus.Int32(1),
            "/DeviceInstance": dbus.Int32(0),
            "/Capacity": dbus.Double(150.0),
            "/InstalledCapacity": dbus.Double(150.0),
        }

        for path, value in paths.items():
            self.items[path] = BatteryService(bus, f"/{service_name.replace('.', '/')}{path}", value)

        print(f"  Registered: {service_name} — SOC={soc}%, {voltage}V, {current}A, {temperature}°C")


class MockAggregate:
    """Registers the aggregate parallel battery service."""

    def __init__(self, bus, batteries_data, count):
        service_name = "com.victronenergy.battery.parallel"
        self._bus_name = dbus.service.BusName(service_name, bus)

        avg_soc = sum(batteries_data["soc"][:count]) / count
        avg_voltage = sum(batteries_data["voltage"][:count]) / count
        total_current = sum(batteries_data["current"][:count])
        capacity_each = 150.0
        total_installed = capacity_each * count
        total_remaining = sum(
            capacity_each * batteries_data["soc"][i] / 100.0 for i in range(count)
        )

        self.items = {}
        paths = {
            "/Soc": dbus.Double(round(avg_soc, 1)),
            "/Dc/0/Voltage": dbus.Double(round(avg_voltage, 2)),
            "/Dc/0/Current": dbus.Double(round(total_current, 1)),
            "/Capacity": dbus.Double(round(total_remaining, 0)),
            "/InstalledCapacity": dbus.Double(total_installed),
            "/ProductName": dbus.String("BluetoothBattery(Parallel)"),
            "/Connected": dbus.Int32(1),
            "/DeviceInstance": dbus.Int32(0),
        }

        for path, value in paths.items():
            self.items[path] = BatteryService(bus, f"/{service_name.replace('.', '/')}{path}", value)

        print(f"  Registered: {service_name} — SOC={avg_soc:.0f}%, {avg_voltage:.2f}V, {total_current:.1f}A")


def parse_args():
    parser = argparse.ArgumentParser(description="Mock D-Bus battery services for testing")
    parser.add_argument("--batteries", type=int, default=4, choices=range(1, 9),
                        help="Number of batteries (1-8, default: 4)")
    parser.add_argument("--state", choices=["charging", "discharging", "mixed"],
                        default="charging", help="Simulation state (default: charging)")
    parser.add_argument("--session-bus", action="store_true",
                        help="Use session bus instead of system bus (for desktop testing)")
    return parser.parse_args()


def main():
    args = parse_args()

    if args.state == "charging":
        data = CHARGING_DEFAULTS
    elif args.state == "discharging":
        data = DISCHARGING_DEFAULTS
    else:
        data = MIXED_DEFAULTS

    count = args.batteries

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    if args.session_bus:
        bus = dbus.SessionBus()
        print("Using session bus")
    else:
        bus = dbus.SystemBus()
        print("Using system bus")

    print(f"\nPublishing {count} battery services ({args.state} state):\n")

    batteries = []
    for i in range(count):
        bat = MockBattery(
            bus, BATTERY_MACS[i],
            soc=data["soc"][i],
            voltage=data["voltage"][i],
            current=data["current"][i],
            temperature=data["temperature"][i],
            cell_diff=data["cell_diff"][i],
            cycles=data["cycles"][i],
            product_name="BluetoothBattery(Single)",
        )
        batteries.append(bat)

    print()
    aggregate = MockAggregate(bus, data, count)  # noqa: F841 — must keep reference alive

    print(f"\n{count + 1} services published. Press Ctrl+C to stop.\n")

    loop = GLib.MainLoop()
    signal.signal(signal.SIGINT, lambda *_: loop.quit())
    signal.signal(signal.SIGTERM, lambda *_: loop.quit())

    try:
        loop.run()
    except KeyboardInterrupt:
        pass

    print("\nStopped.")


if __name__ == "__main__":
    main()
