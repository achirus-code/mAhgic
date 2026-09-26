import Foundation

public struct MuxDevice: Identifiable, Hashable, Sendable {
    public enum Connection: String, Sendable { case usb = "USB", network = "Wi‑Fi" }

    public var id: String { udid }
    public let udid: String
    public let deviceID: Int
    public let connection: Connection
}

/// Client for Apple's usbmuxd (/var/run/usbmuxd). usbmuxd lists both USB devices and
/// paired devices that advertise themselves on the local network (Wi‑Fi sync), and
/// tunnels TCP connections to ports on those devices.
public final class USBMux {
    public static let socketPath = "/var/run/usbmuxd"

    private let socket: Socket
    private var tag: UInt32 = 1

    public init(timeout: TimeInterval = 10) throws {
        socket = try Socket(unixPath: USBMux.socketPath, timeout: timeout)
    }

    public func close() { socket.close() }

    private func baseMessage(_ type: String) -> PlistDict {
        [
            "MessageType": type,
            "ClientVersionString": "mAhgic-1.0",
            "ProgName": "mAhgic",
            "BundleID": "de.till.mAhgic",
            "kLibUSBMuxVersion": 3,
        ]
    }

    private func send(_ dict: PlistDict) throws {
        let body = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        var header = [UInt32(16 + body.count), 1, 8, tag].map { $0.littleEndian }
        tag += 1
        var packet = Data(bytes: &header, count: 16)
        packet.append(body)
        try socket.write(packet)
    }

    private func receive() throws -> PlistDict {
        let header = try socket.read(exactly: 16)
        let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard length >= 16, length < 32 * 1024 * 1024 else { throw MahgicError.usbmux("Invalid packet length") }
        let body = try socket.read(exactly: Int(length) - 16)
        guard let dict = try PropertyListSerialization.propertyList(from: body, format: nil) as? PlistDict else {
            throw MahgicError.usbmux("Invalid response")
        }
        return dict
    }

    private func checkResult(_ reply: PlistDict, action: String) throws {
        if reply.string("MessageType") == "Result", let number = reply.int("Number"), number != 0 {
            let reason: String
            switch number {
            case 2: reason = "device is no longer connected"
            case 3: reason = "connection refused by device"
            case 5: reason = "malfunction"
            case 6: reason = "bad version"
            default: reason = "error \(number)"
            }
            throw MahgicError.usbmux("\(action) failed: \(reason)")
        }
    }

    /// Lists devices; when a device is reachable via USB and Wi‑Fi only the USB entry is kept
    /// unless `allConnections` is set.
    public func listDevices(allConnections: Bool = false) throws -> [MuxDevice] {
        try send(baseMessage("ListDevices"))
        let reply = try receive()
        let list = reply["DeviceList"] as? [PlistDict] ?? []
        var byUDID: [String: MuxDevice] = [:]
        var all: [MuxDevice] = []
        for entry in list {
            guard let props = entry.dict("Properties"),
                  let udid = props.string("SerialNumber"),
                  let deviceID = entry.int("DeviceID") ?? props.int("DeviceID") else { continue }
            let connection: MuxDevice.Connection = props.string("ConnectionType") == "Network" ? .network : .usb
            let device = MuxDevice(udid: udid, deviceID: deviceID, connection: connection)
            all.append(device)
            // Prefer USB when a device is reachable both ways.
            if let existing = byUDID[udid], existing.connection == .usb { continue }
            byUDID[udid] = device
        }
        if allConnections { return all }
        return byUDID.values.sorted { $0.udid < $1.udid }
    }

    public func readPairRecord(udid: String) throws -> PlistDict {
        var msg = baseMessage("ReadPairRecord")
        msg["PairRecordID"] = udid
        try send(msg)
        let reply = try receive()
        guard let data = reply["PairRecordData"] as? Data else {
            throw MahgicError.pairing("This Mac is not paired with the device. Connect it once via USB and tap “Trust” on the device.")
        }
        guard let record = try PropertyListSerialization.propertyList(from: data, format: nil) as? PlistDict else {
            throw MahgicError.pairing("The pairing record could not be read.")
        }
        return record
    }

    /// Opens a tunnel to `port` on the device. After this call the underlying socket is
    /// a raw byte stream to the device; the USBMux object must not be used for anything else.
    public func connect(deviceID: Int, port: UInt16) throws -> Socket {
        var msg = baseMessage("Connect")
        msg["DeviceID"] = deviceID
        msg["PortNumber"] = Int(port.byteSwapped)
        try send(msg)
        let reply = try receive()
        try checkResult(reply, action: "Connect to port \(port)")
        return socket
    }

    public static func listDevices(allConnections: Bool = false) throws -> [MuxDevice] {
        let mux = try USBMux(timeout: 5)
        defer { mux.close() }
        return try mux.listDevices(allConnections: allConnections)
    }

    public static func pairRecord(udid: String) throws -> PlistDict {
        let mux = try USBMux(timeout: 5)
        defer { mux.close() }
        return try mux.readPairRecord(udid: udid)
    }
}
