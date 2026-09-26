import AppKit
import SwiftUI
import mAhgicCore
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    enum Selection: Hashable {
        case mac
        case device(String)   // UDID
        case history
        case connectHelp
    }

    enum DeviceState {
        case loading
        case loaded(IOSDeviceInfo, error: String?)
        case failed(String)
    }

    @Published var selection: Selection = UserDefaults.standard.string(forKey: "page") == "history" ? .history : .mac {
        didSet {
            if case .history = selection { UserDefaults.standard.set("history", forKey: "page") }
            else { UserDefaults.standard.set("mac", forKey: "page") }
        }
    }
    @Published private(set) var macSystem = MacSystemInfo.read()
    @Published private(set) var macBattery: MacBatteryInfo?
    @Published private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var devices: [MuxDevice] = []
    @Published private(set) var deviceStates: [String: DeviceState] = [:]
    @Published private(set) var historyGroups: [HistoryDeviceGroup] = []
    @Published private(set) var usbmuxError: String?

    let history = HistoryStore()

    private let deviceQueue = DispatchQueue(label: "de.till.mAhgic.devices", qos: .userInitiated)
    private var inFlight = Set<String>()
    private var lastConnection: [String: MuxDevice.Connection] = [:]
    private var lastMacRecord: (day: Date, cycles: Int, fcc: Int)?
    private var timers: [Timer] = []

    init() {
        if history.isEmpty && HistoryStore.coconutAvailable {
            _ = try? history.importCoconutBattery()
        }
        refreshMac()
        refreshHistory()
        pollDevices()

        timers = [
            Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshMac() }
            },
            Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.pollDevices() }
            },
            Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.reloadAllDevices() }
            },
        ]
    }

    // MARK: Mac

    func refreshMac() {
        macBattery = MacBatteryReader.read()
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard let b = macBattery else { return }
        let today = Calendar.current.startOfDay(for: Date())
        if let last = lastMacRecord, last.day == today, last.cycles == b.cycleCount, last.fcc == b.fullChargeCapacity {
            return
        }
        lastMacRecord = (today, b.cycleCount, b.fullChargeCapacity)
        history.record(HistoryEntry(
            date: Date(), kind: .mac,
            deviceSerial: macSystem.serialNumber ?? macSystem.modelIdentifier,
            deviceName: macSystem.computerName,
            modelIdentifier: macSystem.modelIdentifier,
            osVersion: macSystem.osVersion,
            batterySerial: b.batterySerial,
            cycleCount: b.cycleCount,
            fullChargeCapacity: b.fullChargeCapacity,
            designCapacity: b.designCapacity))
        refreshHistory()
    }

    // MARK: iPhone / iPad

    func pollDevices() {
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try USBMux.listDevices() }
            DispatchQueue.main.async { self.apply(result) }
        }
    }

    private func apply(_ result: Result<[MuxDevice], Error>) {
        switch result {
        case .failure(let error):
            usbmuxError = error.localizedDescription
            devices = []
        case .success(let list):
            usbmuxError = nil
            if list != devices { devices = list }
            let present = Set(list.map(\.udid))
            for udid in deviceStates.keys where !present.contains(udid) {
                deviceStates[udid] = nil
                lastConnection[udid] = nil
            }
            for device in list where deviceStates[device.udid] == nil || lastConnection[device.udid] != device.connection {
                load(device)
            }
            if case .device(let udid) = selection, !present.contains(udid) {
                selection = .mac
            }
            if case .connectHelp = selection, let first = list.first {
                selection = .device(first.udid)
            }
        }
    }

    func load(_ device: MuxDevice) {
        guard !inFlight.contains(device.udid) else { return }
        inFlight.insert(device.udid)
        lastConnection[device.udid] = device.connection
        if deviceStates[device.udid] == nil { deviceStates[device.udid] = .loading }

        deviceQueue.async {
            let result = Result { try IOSDeviceReader.read(device) }
            DispatchQueue.main.async { self.finishLoad(device, result) }
        }
    }

    private func finishLoad(_ device: MuxDevice, _ result: Result<IOSDeviceInfo, Error>) {
        inFlight.remove(device.udid)
        guard devices.contains(where: { $0.udid == device.udid }) else { return }
        switch result {
        case .success(let info):
            deviceStates[device.udid] = .loaded(info, error: nil)
            record(info)
        case .failure(let error):
            let message = error.localizedDescription
            if case .loaded(let old, _) = deviceStates[device.udid] {
                deviceStates[device.udid] = .loaded(old, error: message)
            } else {
                deviceStates[device.udid] = .failed(message)
            }
        }
    }

    func reloadAllDevices() {
        for device in devices { load(device) }
    }

    func reload(udid: String) {
        guard let device = devices.first(where: { $0.udid == udid }) else { return }
        load(device)
    }

    func history(forSerial serial: String?) -> HistoryDeviceGroup? {
        guard let serial else { return nil }
        return historyGroups.first { $0.serial == serial }
    }

    private func record(_ info: IOSDeviceInfo) {
        let b = info.battery
        guard let fcc = b.fullChargeCapacity, let dc = b.designCapacity, dc > 0 else { return }
        history.record(HistoryEntry(
            date: info.readDate, kind: .ios,
            deviceSerial: info.serialNumber,
            deviceName: info.name,
            modelIdentifier: info.productType,
            osVersion: info.osVersion,
            batterySerial: b.batterySerial,
            cycleCount: b.cycleCount ?? 0,
            fullChargeCapacity: fcc,
            designCapacity: dc))
        refreshHistory()
    }

    // MARK: History

    func refreshHistory() {
        historyGroups = history.groups()
    }

    func deleteHistory(ids: Set<UUID>) {
        history.delete(ids: ids)
        refreshHistory()
    }

    func deleteHistoryDevice(serial: String) {
        history.deleteDevice(serial: serial)
        refreshHistory()
    }

    func refreshAll() {
        refreshMac()
        pollDevices()
        reloadAllDevices()
    }

    func importCoconut() {
        do {
            let count = try history.importCoconutBattery()
            refreshHistory()
            showAlert(count == 0
                ? "No new entries found in the coconutBattery history."
                : "Imported \(count) entries from coconutBattery.")
        } catch {
            showAlert("Import failed: \(error.localizedDescription)")
        }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "mAhgic History.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try history.csv().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showAlert("Export failed: \(error.localizedDescription)")
        }
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "mAhgic"
        alert.informativeText = message
        alert.runModal()
    }
}
