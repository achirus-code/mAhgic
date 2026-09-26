import Foundation
import mAhgicCore

// Developer tool to exercise mAhgicCore from the terminal.
//   mahcli mac                         Mac battery + system info
//   mahcli raw [n]                     flattened raw Mac battery values
//   mahcli list                        devices known to usbmuxd (USB + Wi‑Fi)
//   mahcli read [udid] [--wifi]                read battery of an iOS device
//   mahcli tls host port cert key      TLS client handshake test against a server
//   mahcli coconut <history.json>      import coconutBattery history into a scratch store

let args = CommandLine.arguments.dropFirst()

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

switch args.first {
case "mac":
    let sys = MacSystemInfo.read()
    print(sys)
    guard let b = MacBatteryReader.read() else { fail("No battery") }
    print(b)
    print(String(format: "health %.1f%%  power %.1f W", b.health, b.batteryPower))

case "raw":
    guard let r = MacBatteryReader.readRegistry() else { fail("No battery") }
    let rows = RawValues.flatten(r)
    print(rows.count, "rows")
    for row in rows.prefix(Int(args.dropFirst().first ?? "25") ?? 25) { print(row.0, "=", row.1) }

case "list":
    do {
        let devices = try USBMux.listDevices(allConnections: true)
        if devices.isEmpty { print("no devices") }
        for d in devices { print(d.udid, d.connection.rawValue, "id=\(d.deviceID)") }
    } catch { fail("\(error.localizedDescription)") }

case "read":
    do {
        let wifi = args.contains("--wifi")
        let devices = try USBMux.listDevices(allConnections: true)
        let udid = args.dropFirst().first { !$0.hasPrefix("--") }
        guard let device = devices.first(where: {
            (udid == nil || $0.udid == udid) && (!wifi || $0.connection == .network)
        }) else { fail("device not found") }
        let info = try IOSDeviceReader.read(device)
        print(info.name, info.marketingName, info.osVersion, info.serialNumber, info.connection.rawValue)
        let b = info.battery
        print("charge", b.chargePercent ?? -1, "% ", b.currentCapacity ?? -1, "mAh")
        print("fcc", b.fullChargeCapacity ?? -1, "design", b.designCapacity ?? -1, "health", b.health ?? -1)
        print("cycles", b.cycleCount ?? -1, "temp", b.temperature ?? -1)
    } catch { fail("\(error.localizedDescription)") }

case "tls":
    let a = Array(args)
    guard a.count == 5, let port = UInt16(a[2]) else { fail("usage: mahcli tls host port cert.pem key.pem") }
    do {
        let identity = try TLSIdentity.make(certificatePEM: try Data(contentsOf: URL(fileURLWithPath: a[3])),
                                            privateKeyPEM: try Data(contentsOf: URL(fileURLWithPath: a[4])))
        let socket = try Socket(host: a[1], port: port)
        let tls = try TLSStream(socket: socket, identity: identity)
        let service = PlistService(stream: tls)
        try service.send(["Request": "Ping", "Label": "mahcli"])
        print("handshake OK, sent plist")
        let reply = try service.receive()
        print("reply:", reply)
    } catch { fail("\(error.localizedDescription)") }

case "coconut":
    guard let path = args.dropFirst().first else { fail("usage: mahcli coconut out.json") }
    let store = HistoryStore(fileURL: URL(fileURLWithPath: path))
    do {
        print("imported", try store.importCoconutBattery())
        for g in store.groups() {
            print("==", g.title)
            for p in g.periods { print("  ", p.label, String(format: "%.0f %%", p.averageHealth), p.cycles) }
        }
    } catch { fail("\(error.localizedDescription)") }

default:
    print("usage: mahcli mac | list | read [udid] | tls host port cert key | coconut out.json")
}
