import Foundation
import Security

/// Talks to lockdownd (port 62078) on an iOS/iPadOS device through usbmuxd.
public final class LockdownClient {
    static let port: UInt16 = 62078
    private static let label = "mAhgic"

    public let device: MuxDevice
    private let service: PlistService
    private let socket: Socket
    private let pairRecord: PlistDict
    private(set) var identity: SecIdentity?
    private var sessionID: String?

    public init(device: MuxDevice) throws {
        self.device = device
        pairRecord = try USBMux.pairRecord(udid: device.udid)
        let timeout: TimeInterval = device.connection == .network ? 15 : 8
        let mux = try USBMux(timeout: timeout)
        socket = try mux.connect(deviceID: device.deviceID, port: LockdownClient.port)
        service = PlistService(stream: socket)

        let type = try request(["Request": "QueryType"])
        if let t = type.string("Type"), t != "com.apple.mobile.lockdown" {
            throw MahgicError.lockdown("Unexpected lockdown service type \(t)")
        }
    }

    deinit { close() }

    public func close() {
        if sessionID != nil {
            _ = try? request(["Request": "StopSession", "SessionID": sessionID!])
            sessionID = nil
        }
        service.close()
    }

    @discardableResult
    func request(_ body: PlistDict) throws -> PlistDict {
        var msg = body
        msg["Label"] = LockdownClient.label
        let reply = try service.request(msg)
        if let error = reply.string("Error") {
            throw MahgicError.lockdown(LockdownClient.describe(error: error))
        }
        return reply
    }

    static func describe(error: String) -> String {
        switch error {
        case "InvalidHostID":
            return "The device no longer trusts this Mac. Connect it via USB and tap “Trust”."
        case "PasswordProtected":
            return "The device is locked. Unlock it and try again."
        case "PairingDialogResponsePending":
            return "Please tap “Trust” on the device."
        case "UserDeniedPairing":
            return "Pairing was denied on the device."
        case "SessionInactive":
            return "The lockdown session is not active."
        default:
            return "Device error: \(error)"
        }
    }

    public func startSession() throws {
        guard let hostID = pairRecord.string("HostID") else {
            throw MahgicError.pairing("The pairing record has no HostID.")
        }
        var req: PlistDict = ["Request": "StartSession", "HostID": hostID]
        if let buid = pairRecord.string("SystemBUID") { req["SystemBUID"] = buid }
        let reply = try request(req)
        sessionID = reply.string("SessionID")
        if reply.bool("EnableSessionSSL") ?? false {
            let identity = try makeIdentity()
            service.stream = try TLSStream(socket: socket, identity: identity)
        }
    }

    func makeIdentity() throws -> SecIdentity {
        if let identity { return identity }
        guard let cert = pairRecord["HostCertificate"] as? Data,
              let key = pairRecord["HostPrivateKey"] as? Data else {
            throw MahgicError.pairing("The pairing record contains no host certificate.")
        }
        let id = try TLSIdentity.make(certificatePEM: cert, privateKeyPEM: key)
        identity = id
        return id
    }

    public func value(domain: String? = nil, key: String? = nil) throws -> Any? {
        var req: PlistDict = ["Request": "GetValue"]
        if let domain { req["Domain"] = domain }
        if let key { req["Key"] = key }
        return try request(req)["Value"]
    }

    /// Starts a lockdown service and returns a plist connection to it.
    public func startService(_ name: String) throws -> PlistService {
        let reply = try request(["Request": "StartService", "Service": name])
        guard let port = reply.int("Port") else {
            throw MahgicError.lockdown("Service \(name) could not be started.")
        }
        let timeout: TimeInterval = device.connection == .network ? 15 : 8
        let mux = try USBMux(timeout: timeout)
        let serviceSocket = try mux.connect(deviceID: device.deviceID, port: UInt16(port))
        if reply.bool("EnableServiceSSL") ?? false {
            return PlistService(stream: try TLSStream(socket: serviceSocket, identity: try makeIdentity()))
        }
        return PlistService(stream: serviceSocket)
    }
}

// MARK: - Device + battery information

public struct IOSDeviceInfo: Sendable {
    public var udid: String
    public var connection: MuxDevice.Connection
    public var name: String
    public var productType: String          // e.g. iPhone17,1
    public var marketingName: String        // e.g. iPhone 16 Pro
    public var deviceClass: String          // iPhone / iPad / iPod
    public var osVersion: String
    public var buildVersion: String?
    public var serialNumber: String
    public var modelNumber: String?
    public var regulatoryModel: String?
    public var hardwareModel: String?
    public var wifiAddress: String?
    public var battery: IOSBatteryInfo
    public var readDate: Date
}

public struct IOSBatteryInfo: Sendable {
    public var chargePercent: Int?
    public var currentCapacity: Int?        // mAh
    public var fullChargeCapacity: Int?     // mAh
    public var designCapacity: Int?         // mAh
    public var cycleCount: Int?
    public var temperature: Double?         // °C
    public var voltage: Int?                // mV
    public var amperage: Int?               // mA, negative = discharging
    public var isCharging: Bool
    public var externalConnected: Bool
    public var fullyCharged: Bool
    public var batterySerial: String?
    public var adapterName: String?
    public var adapterWatts: Int?
    public var rawValues: [(String, String)]

    public var health: Double? {
        guard let fcc = fullChargeCapacity, let dc = designCapacity, dc > 0 else { return nil }
        return Double(fcc) / Double(dc) * 100
    }

    public var watts: Double? {
        guard let v = voltage, let a = amperage, a != 0 else { return nil }
        return Double(v) * Double(a) / 1_000_000
    }
}

public enum IOSDeviceReader {
    public static func read(_ device: MuxDevice) throws -> IOSDeviceInfo {
        let lockdown = try LockdownClient(device: device)
        defer { lockdown.close() }
        try lockdown.startSession()

        let values = (try lockdown.value() as? PlistDict) ?? [:]
        let batteryDomain = (try? lockdown.value(domain: "com.apple.mobile.battery") as? PlistDict) ?? [:]

        var registry: PlistDict = [:]
        do {
            let diag = try lockdown.startService("com.apple.mobile.diagnostics_relay")
            defer {
                _ = try? diag.request(["Request": "Goodbye"])
                diag.close()
            }
            registry = try ioRegistry(diag)
        } catch {
            // Without diagnostics we can still show the charge level from lockdown.
            if batteryDomain.isEmpty { throw error }
        }

        let productType = values.string("ProductType") ?? "Unknown"
        let battery = makeBattery(registry: registry, lockdownBattery: batteryDomain)
        return IOSDeviceInfo(
            udid: device.udid,
            connection: device.connection,
            name: values.string("DeviceName") ?? "iOS Device",
            productType: productType,
            marketingName: DeviceCatalog.marketingName(for: productType) ?? productType,
            deviceClass: values.string("DeviceClass") ?? "iPhone",
            osVersion: values.string("ProductVersion") ?? "?",
            buildVersion: values.string("BuildVersion"),
            serialNumber: values.string("SerialNumber") ?? device.udid,
            modelNumber: values.string("ModelNumber").map { $0 + (values.string("RegionInfo") ?? "") },
            regulatoryModel: values.string("RegulatoryModelNumber"),
            hardwareModel: values.string("HardwareModel"),
            wifiAddress: values.string("WiFiAddress"),
            battery: battery,
            readDate: Date()
        )
    }

    static func ioRegistry(_ diag: PlistService) throws -> PlistDict {
        let queries: [PlistDict] = [
            ["Request": "IORegistry", "EntryClass": "IOPMPowerSource"],
            ["Request": "IORegistry", "EntryName": "AppleSmartBattery"],
            ["Request": "IORegistry", "EntryName": "AppleARMPMUCharger"],
        ]
        var best: PlistDict = [:]
        var lastError: Error?
        for q in queries {
            do {
                let reply = try diag.request(q)
                guard reply.string("Status") == "Success",
                      let reg = reply.dict("Diagnostics")?.dict("IORegistry") else { continue }
                if reg["DesignCapacity"] != nil || reg.dict("BatteryData")?["DesignCapacity"] != nil {
                    return reg
                }
                if best.isEmpty { best = reg }
            } catch {
                lastError = error
                break
            }
        }
        if best.isEmpty, let lastError { throw lastError }
        if best.isEmpty { throw MahgicError.diagnostics("No battery data returned by the device.") }
        return best
    }

    static func makeBattery(registry r: PlistDict, lockdownBattery lb: PlistDict) -> IOSBatteryInfo {
        let batteryData = r.dict("BatteryData") ?? [:]
        let design = r.int("DesignCapacity") ?? batteryData.int("DesignCapacity")
        let rawMax = r.int("AppleRawMaxCapacity") ?? r.int("NominalChargeCapacity") ?? batteryData.int("FccComp1")
        var percent = lb.int("BatteryCurrentCapacity")
        if percent == nil, let cur = r.int("CurrentCapacity"), let max = r.int("MaxCapacity"), max > 0, max <= 100 {
            percent = cur * 100 / max
        }
        var temp: Double?
        if let t = r.int("Temperature"), t != 0 { temp = Double(t) / 100 }
        else if let t = r.int("VirtualTemperature"), t != 0 { temp = Double(t) / 100 }

        let adapter = r.dict("AdapterDetails")
        let raw = RawValues.flatten(r)

        return IOSBatteryInfo(
            chargePercent: percent,
            currentCapacity: r.int("AppleRawCurrentCapacity"),
            fullChargeCapacity: rawMax,
            designCapacity: design,
            cycleCount: r.int("CycleCount") ?? batteryData.int("CycleCount"),
            temperature: temp,
            voltage: r.int("Voltage") ?? r.int("AppleRawBatteryVoltage"),
            amperage: r.int("InstantAmperage") ?? r.int("Amperage"),
            isCharging: r.bool("IsCharging") ?? lb.bool("BatteryIsCharging") ?? false,
            externalConnected: r.bool("ExternalConnected") ?? lb.bool("ExternalConnected") ?? false,
            fullyCharged: r.bool("FullyCharged") ?? lb.bool("FullyCharged") ?? false,
            batterySerial: r.string("Serial") ?? batteryData.string("Serial"),
            adapterName: adapter?.string("Name") ?? adapter?.string("Description"),
            adapterWatts: adapter?.int("Watts"),
            rawValues: raw
        )
    }
}
