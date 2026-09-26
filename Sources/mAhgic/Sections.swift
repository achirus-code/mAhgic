import Foundation
import mAhgicCore

/// Key/value groups for the "Details" card (everything the old info sheets showed).
enum Sections {
    static func mac(_ s: MacSystemInfo) -> [KVSection] {
        let uptime = Duration.seconds(s.uptime).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated))
        return [
            ("Mac", [
                ("Name", s.computerName),
                ("Model", s.productName),
                ("Model Identifier", s.modelIdentifier),
                ("Model Number", s.modelNumber ?? "—"),
                ("Regulatory Model", s.regulatoryModel ?? "—"),
                ("Serial Number", s.serialNumber ?? "—"),
            ]),
            ("Hardware & System", [
                ("Chip", s.chip ?? "—"),
                ("Memory", "\(s.memoryGB) GB"),
                ("macOS", s.osVersion),
                ("Uptime", uptime),
            ]),
        ]
    }

    static func macBattery(_ b: MacBatteryInfo) -> [KVSection] {
        var status: [(String, String)] = [
            ("Charge", "\(b.chargePercent) %"),
            ("Charging", Fmt.yesNo(b.isCharging)),
            ("Fully Charged", Fmt.yesNo(b.fullyCharged)),
        ]
        if b.timeToFull != nil { status.append(("Time to Full", Fmt.duration(minutes: b.timeToFull))) }
        if b.timeToEmpty != nil { status.append(("Time Remaining", Fmt.duration(minutes: b.timeToEmpty))) }

        var adapter: [(String, String)] = [("Connected", Fmt.yesNo(b.externalConnected))]
        if let name = b.adapterName { adapter.append(("Adapter", name)) }
        if let w = b.adapterWatts { adapter.append(("Negotiated Power", "\(w) W")) }
        if let v = b.adapterVoltage, let a = b.adapterCurrent {
            adapter.append(("Adapter Output", "\(Fmt.volts(v)) / \(Fmt.number(Double(a) / 1000, digits: 2)) A"))
        }
        if let sp = b.systemPower { adapter.append(("System Power", Fmt.number(sp) + " W")) }

        return [
            ("Battery", [
                ("Serial Number", b.batterySerial ?? "—"),
                ("Gas Gauge", b.gaugeName ?? "—"),
                ("Manufacture Date", Fmt.day(b.manufactureDate)),
                ("Age", b.manufactureDate.map(ageString(since:)) ?? "—"),
            ]),
            ("Capacity", [
                ("Current Charge", Fmt.mAh(b.currentCapacity)),
                ("Full Charge Capacity", Fmt.mAh(b.fullChargeCapacity)),
                ("Nominal Capacity", Fmt.mAh(b.nominalChargeCapacity)),
                ("Design Capacity", Fmt.mAh(b.designCapacity)),
                ("Health", Fmt.percent(b.health, digits: 1)),
                ("Charge Cycles", b.designCycleCount.map { "\(b.cycleCount) of \($0)" } ?? "\(b.cycleCount)"),
            ]),
            ("Electrical", [
                ("Voltage", Fmt.volts(b.voltage)),
                ("Amperage", "\(b.amperage) mA"),
                ("Battery Power", Fmt.number(b.batteryPower) + " W"),
                ("Cell Voltages", b.cellVoltages.isEmpty ? "—" : b.cellVoltages.map { Fmt.volts($0) }.joined(separator: ", ")),
                ("Temperature", Fmt.temperature(b.temperature)),
            ]),
            ("Status", status),
            ("Power Adapter", adapter),
        ]
    }

    static func device(_ info: IOSDeviceInfo) -> [KVSection] {
        [
            ("Device", [
                ("Name", info.name),
                ("Model", info.marketingName),
                ("Device Identifier", info.productType),
                ("Model Number", info.modelNumber ?? "—"),
                ("Regulatory Model", info.regulatoryModel ?? "—"),
                ("Hardware Model", info.hardwareModel ?? "—"),
                ("Serial Number", info.serialNumber),
                ("UDID", info.udid),
            ]),
            ("Software & Connection", [
                ("iOS Version", info.osVersion),
                ("Build", info.buildVersion ?? "—"),
                ("Connected via", info.connection.rawValue),
                ("Wi‑Fi Address", info.wifiAddress ?? "—"),
            ]),
        ]
    }

    static func deviceBattery(_ b: IOSBatteryInfo) -> [KVSection] {
        var status: [(String, String)] = [
            ("Charge", b.chargePercent.map { "\($0) %" } ?? "—"),
            ("Charging", Fmt.yesNo(b.isCharging)),
            ("External Power", Fmt.yesNo(b.externalConnected)),
            ("Fully Charged", Fmt.yesNo(b.fullyCharged)),
        ]
        if let name = b.adapterName { status.append(("Adapter", name)) }
        if let w = b.adapterWatts { status.append(("Adapter Power", "\(w) W")) }
        return [
            ("Battery", [
                ("Serial Number", b.batterySerial ?? "—"),
                ("Current Charge", Fmt.mAh(b.currentCapacity)),
                ("Full Charge Capacity", Fmt.mAh(b.fullChargeCapacity)),
                ("Design Capacity", Fmt.mAh(b.designCapacity)),
                ("Health", Fmt.percent(b.health, digits: 1)),
                ("Charge Cycles", b.cycleCount.map { "\($0)" } ?? "—"),
            ]),
            ("Electrical & Status", [
                ("Temperature", Fmt.temperature(b.temperature)),
                ("Voltage", Fmt.volts(b.voltage)),
                ("Amperage", b.amperage.map { "\($0) mA" } ?? "—"),
            ] + status),
        ]
    }
}
