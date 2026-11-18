pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// What this machine can actually do, so tools can gate themselves instead of
// the shell carrying per-machine config. This file is restored onto every box
// from the Linux backup repo unchanged; a laptop grows the brightness and
// battery tools by itself, a desktop never shows them.
Singleton {
    id: root

    // SMBIOS chassis type. World-readable, unlike most of /sys/class/dmi/id
    // (product_uuid and board_serial are root-only). 3 = Desktop on this box;
    // the portable family is 8 Portable, 9 Laptop, 10 Notebook, 11 Hand Held,
    // 14 Sub Notebook, 30 Tablet, 31 Convertible, 32 Detachable.
    //
    // It is a vendor-filled string, not a kernel-derived fact — this very
    // board ships "To Be Filled By O.E.M." in chassis_vendor and
    // product_family — so it gates form-factor behaviour only. Anything that
    // drives hardware gates on the capability probes below instead.
    readonly property int chassisType: parseInt(chassisFile.text()) || 0
    readonly property bool isLaptop:
        [8, 9, 10, 11, 14, 30, 31, 32].indexOf(chassisType) !== -1

    FileView {
        id: chassisFile
        path: "/sys/class/dmi/id/chassis_type"
        blockLoading: true
        printErrors: false
    }

    // What a brightness slider actually depends on. Driver-dependent names
    // (intel_backlight, amdgpu_bl0, nvidia_0) make it a glob, and FileView
    // reads files rather than directories, so this is the one probe that has
    // to shell out. Async, so hasBacklight is false for the first few ms —
    // bind to it rather than reading it once at construction.
    property string backlightDevice: ""
    readonly property bool hasBacklight: backlightDevice !== ""

    Process {
        running: true
        command: ["bash", "-c", "ls -1 /sys/class/backlight 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: root.backlightDevice = this.text.trim()
        }
    }

    // isLaptopBattery is what separates a system battery from a peripheral.
    // It matters here specifically: /sys/class/power_supply on this desktop is
    // not empty — it holds hidpp_battery_0, the Logitech mouse — so the
    // obvious "is there a battery?" probe returns true on a machine that has
    // no battery at all.
    readonly property bool hasSystemBattery:
        UPower.displayDevice !== null && UPower.displayDevice.isLaptopBattery
}
