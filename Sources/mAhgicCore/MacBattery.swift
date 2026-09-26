import Foundation
import IOKit
import IOKit.ps

public struct MacBatteryInfo: Sendable {
    public var chargePercent: Int
    public var currentCapacity: Int          // mAh
    public var fullChargeCapacity: Int       // mAh
    public var designCapacity: Int           // mAh
    public var nominalChargeCapacity: Int?   // mAh
    public var cycleCount: Int
    public var designCycleCount: Int?
    public var temperature: Double           // °C
    public var voltage: Int                  // mV
    public var amperage: Int                 // mA, negative = discharging
    public var isCharging: Bool
    public var externalConnected: Bool
    public var fullyCharged: Bool
    public var timeToFull: Int?              // minutes
    public var timeToEmpty: Int?             // minutes
    public var manufactureDate: Date?
    public var batterySerial: String?
    public var gaugeName: String?
    public var cellVoltages: [Int]
    public var adapterName: String?
    public var adapterWatts: Int?
    public var adapterVoltage: Int?          // mV
    public var adapterCurrent: Int?          // mA
    public var systemPower: Double?          // W
    public var readDate: Date

    public var health: Double {
        designCapacity > 0 ? Double(fullChargeCapacity) / Double(designCapacity) * 100 : 0
    }

    /// Power flowing into (positive) or out of (negative) the battery, in watts.
    public var batteryPower: Double {
        Double(voltage) * Double(amperage) / 1_000_000
    }
}

public enum MacBatteryReader {
    public static func readRegistry() -> PlistDict? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? PlistDict else { return nil }
        return dict
    }

    public static func read() -> MacBatteryInfo? {
        guard let r = readRegistry(), r.bool("BatteryInstalled") ?? true else { return nil }
        let data = r.dict("BatteryData") ?? [:]
        let adapter = r.dict("AdapterDetails")

        let fcc = r.int("AppleRawMaxCapacity") ?? r.int("MaxCapacity") ?? 0
        let current = r.int("AppleRawCurrentCapacity") ?? r.int("CurrentCapacity") ?? 0
        var percent = r.int("CurrentCapacity") ?? 0
        if let max = r.int("MaxCapacity"), max > 100, max > 0 {   // Intel Macs report mAh here
            percent = Int((Double(current) / Double(max) * 100).rounded())
        }

        let tempRaw = r.int("VirtualTemperature").flatMap { $0 > 0 ? $0 : nil } ?? r.int("Temperature") ?? 0
        let toFull = r.int("AvgTimeToFull").flatMap { $0 > 0 && $0 < 65535 ? $0 : nil }
        let toEmpty = r.int("AvgTimeToEmpty").flatMap { $0 > 0 && $0 < 65535 ? $0 : nil }
        let serial = r.string("Serial") ?? data.string("Serial")

        return MacBatteryInfo(
            chargePercent: percent,
            currentCapacity: current,
            fullChargeCapacity: fcc,
            designCapacity: r.int("DesignCapacity") ?? data.int("DesignCapacity") ?? 0,
            nominalChargeCapacity: r.int("NominalChargeCapacity"),
            cycleCount: r.int("CycleCount") ?? 0,
            designCycleCount: r.int("DesignCycleCount9C"),
            temperature: Double(tempRaw) / 100,
            voltage: r.int("Voltage") ?? r.int("AppleRawBatteryVoltage") ?? 0,
            amperage: r.int("InstantAmperage") ?? r.int("Amperage") ?? 0,
            isCharging: r.bool("IsCharging") ?? false,
            externalConnected: r.bool("ExternalConnected") ?? false,
            fullyCharged: r.bool("FullyCharged") ?? false,
            timeToFull: toFull,
            timeToEmpty: toEmpty,
            manufactureDate: manufactureDate(raw: r.int("ManufactureDate") ?? data.int("ManufactureDate"), serial: serial),
            batterySerial: serial,
            gaugeName: r.string("DeviceName"),
            cellVoltages: (data["CellVoltage"] as? [NSNumber])?.map(\.intValue) ?? [],
            adapterName: adapter?.string("Name") ?? adapter?.string("Description"),
            adapterWatts: adapter?.int("Watts"),
            adapterVoltage: adapter?.int("AdapterVoltage"),
            adapterCurrent: adapter?.int("Current"),
            systemPower: data.double("SystemPower"),
            readDate: Date()
        )
    }

    /// Intel Macs store a packed date (day | month << 5 | (year - 1980) << 9).
    /// Apple Silicon batteries encode it in the pack serial: position 3 = year digit,
    /// 4–5 = week of year (0-based), 6 = weekday (1–7).
    static func manufactureDate(raw: Int?, serial: String?) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        if let raw, raw > 0, raw < 0x10000 {
            let day = raw & 0x1F, month = (raw >> 5) & 0x0F, year = 1980 + (raw >> 9)
            return cal.date(from: DateComponents(year: year, month: month, day: day))
        }
        guard let serial, serial.count >= 7 else { return nil }
        let chars = Array(serial)
        guard let yearDigit = chars[3].wholeNumberValue,
              let week = Int(String(chars[4...5])), week <= 53,
              let weekday = chars[6].wholeNumberValue, (1...7).contains(weekday) else { return nil }
        let currentYear = cal.component(.year, from: Date())
        var year = currentYear - ((currentYear % 10) - yearDigit + 10) % 10
        if year > currentYear { year -= 10 }
        guard let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let date = cal.date(byAdding: .day, value: week * 7 + weekday - 1, to: jan1),
              date <= Date() else { return nil }
        return date
    }
}

public struct MacSystemInfo: Sendable {
    public var computerName: String
    public var modelIdentifier: String       // Mac15,13
    public var productName: String           // MacBook Air (15-inch, M3, 2024)
    public var regulatoryModel: String?      // A3114
    public var modelNumber: String?          // MXD13
    public var serialNumber: String?
    public var chip: String?
    public var memoryGB: Int
    public var osVersion: String
    public var uptime: TimeInterval

    /// "MacBook Air" from "MacBook Air (15-inch, M3, 2024)"
    public var familyName: String {
        if let r = productName.range(of: " (") { return String(productName[..<r.lowerBound]) }
        return productName
    }

    /// "15-inch, M3, 2024" from "MacBook Air (15-inch, M3, 2024)"
    public var variantName: String? {
        guard let open = productName.firstIndex(of: "("), let close = productName.lastIndex(of: ")"), open < close else { return nil }
        return String(productName[productName.index(after: open)..<close])
    }

    public static func read() -> MacSystemInfo {
        let model = sysctlString("hw.model") ?? "Mac"
        let product = deviceTreeString(path: "IODeviceTree:/product", key: "product-name")
            ?? DeviceCatalog.marketingName(for: model) ?? model
        let chip = deviceTreeString(path: "IODeviceTree:/product", key: "product-soc-name")
            ?? sysctlString("machdep.cpu.brand_string")
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return MacSystemInfo(
            computerName: Host.current().localizedName ?? "Mac",
            modelIdentifier: model,
            productName: product,
            regulatoryModel: deviceTreeString(path: "IODeviceTree:/", key: "regulatory-model-number"),
            modelNumber: deviceTreeString(path: "IODeviceTree:/", key: "model-number"),
            serialNumber: platformSerial(),
            chip: chip,
            memoryGB: Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824),
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static func deviceTreeString(path: String, key: String) -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        if let data = value as? Data {
            let s = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? nil : s
        }
        return value as? String
    }

    static func platformSerial() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, kIOPlatformSerialNumberKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }
}
