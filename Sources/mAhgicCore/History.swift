import Foundation
import SQLite3

public struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case mac, ios }

    public var id: UUID
    public var date: Date
    public var kind: Kind
    public var deviceSerial: String
    public var deviceName: String
    public var modelIdentifier: String
    public var osVersion: String?
    public var batterySerial: String?
    public var cycleCount: Int
    public var fullChargeCapacity: Int
    public var designCapacity: Int
    public var source: String?

    public init(id: UUID = UUID(), date: Date, kind: Kind, deviceSerial: String, deviceName: String,
                modelIdentifier: String, osVersion: String?, batterySerial: String?, cycleCount: Int,
                fullChargeCapacity: Int, designCapacity: Int, source: String? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.deviceSerial = deviceSerial
        self.deviceName = deviceName
        self.modelIdentifier = modelIdentifier
        self.osVersion = osVersion
        self.batterySerial = batterySerial
        self.cycleCount = cycleCount
        self.fullChargeCapacity = fullChargeCapacity
        self.designCapacity = designCapacity
        self.source = source
    }

    public var health: Double {
        designCapacity > 0 ? Double(fullChargeCapacity) / Double(designCapacity) * 100 : 0
    }
}

public struct HistoryDeviceGroup: Identifiable, Sendable {
    public struct Period: Identifiable, Sendable {
        public var id: String { label }
        public var label: String       // yyyy-MM
        public var averageHealth: Double
        public var cycles: Int
    }

    public var id: String { serial }
    public var serial: String
    public var title: String
    public var kind: HistoryEntry.Kind
    public var modelIdentifier: String
    public var entries: [HistoryEntry]
    public var periods: [Period]
}

public final class HistoryStore {
    public private(set) var entries: [HistoryEntry] = []
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let fm = FileManager.default
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let support = base.appendingPathComponent("mAhgic", isDirectory: true)
            try? fm.createDirectory(at: support, withIntermediateDirectories: true)
            self.fileURL = support.appendingPathComponent("history.json")
            // Carry over history from the app's previous names (newest first).
            if !fm.fileExists(atPath: self.fileURL.path),
               let legacy = ["cookieBattery", "Till Batty"]
                   .map({ base.appendingPathComponent("\($0)/history.json") })
                   .first(where: { fm.fileExists(atPath: $0.path) }) {
                try? fm.copyItem(at: legacy, to: self.fileURL)
            }
        }
        load()
    }

    public var isEmpty: Bool { entries.isEmpty }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
        entries.sort { $0.date < $1.date }
    }

    public func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Keeps at most one own snapshot per device and day (the latest one wins).
    public func record(_ entry: HistoryEntry) {
        let cal = Calendar.current
        if let idx = entries.lastIndex(where: {
            $0.deviceSerial == entry.deviceSerial && $0.source == nil && cal.isDate($0.date, inSameDayAs: entry.date)
        }) {
            var updated = entry
            updated.id = entries[idx].id
            entries[idx] = updated
        } else {
            entries.append(entry)
            entries.sort { $0.date < $1.date }
        }
        save()
    }

    public func delete(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    public func deleteDevice(serial: String) {
        entries.removeAll { $0.deviceSerial == serial }
        save()
    }

    public func groups() -> [HistoryDeviceGroup] {
        let bySerial = Dictionary(grouping: entries, by: \.deviceSerial)
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "yyyy-MM"
        monthFormatter.locale = Locale(identifier: "en_US_POSIX")

        var result: [HistoryDeviceGroup] = []
        for (serial, list) in bySerial {
            let sorted = list.sorted { $0.date < $1.date }
            guard let latest = sorted.last else { continue }
            let byMonth = Dictionary(grouping: sorted) { monthFormatter.string(from: $0.date) }
            let periods = byMonth.keys.sorted().map { key -> HistoryDeviceGroup.Period in
                let items = byMonth[key]!
                let avg = items.map(\.health).reduce(0, +) / Double(items.count)
                return .init(label: key, averageHealth: avg, cycles: items.map(\.cycleCount).max() ?? 0)
            }
            let model = DeviceCatalog.marketingName(for: latest.modelIdentifier) ?? latest.modelIdentifier
            result.append(HistoryDeviceGroup(serial: serial, title: "\(latest.deviceName) (\(model))",
                                             kind: latest.kind, modelIdentifier: latest.modelIdentifier,
                                             entries: sorted, periods: periods))
        }
        return result.sorted {
            if $0.kind != $1.kind { return $0.kind == .mac }
            return ($0.entries.last?.date ?? .distantPast) > ($1.entries.last?.date ?? .distantPast)
        }
    }

    public func csv() -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["date;device;model;serial;cycles;full_charge_capacity_mAh;design_capacity_mAh;health_percent;os;source"]
        for e in entries {
            let fields: [String] = [
                iso.string(from: e.date), e.deviceName, e.modelIdentifier, e.deviceSerial, "\(e.cycleCount)",
                "\(e.fullChargeCapacity)", "\(e.designCapacity)", String(format: "%.1f", e.health),
                e.osVersion ?? "", e.source ?? "mAhgic",
            ]
            lines.append(fields.map { $0.replacingOccurrences(of: ";", with: ",") }.joined(separator: ";"))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - coconutBattery import

    public static var coconutDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/R5SC3K86L5.com.coconut-flavour.coconutBattery/history.sqlite")
    }

    public static var coconutAvailable: Bool {
        FileManager.default.fileExists(atPath: coconutDatabaseURL.path)
    }

    /// Imports coconutBattery 4 history (read-only, from a temporary copy). Returns the number of new entries.
    @discardableResult
    public func importCoconutBattery() throws -> Int {
        let source = HistoryStore.coconutDatabaseURL
        guard FileManager.default.fileExists(atPath: source.path) else { return 0 }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mahgic-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: source.path + suffix)
            if FileManager.default.fileExists(atPath: from.path) {
                try FileManager.default.copyItem(at: from, to: tmp.appendingPathComponent("history.sqlite" + suffix))
            }
        }

        var db: OpaquePointer?
        guard sqlite3_open(tmp.appendingPathComponent("history.sqlite").path, &db) == SQLITE_OK else {
            throw MahgicError.diagnostics("coconutBattery database could not be opened")
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT ZDATASNAPSHOTDATE, ZDATATYPE, ZDEVICESERIAL, ZDEVICENAME, ZDEVICEMODEL, ZDEVICEOSVERSION,
                   ZBATTERYSERIAL, ZBATTERYCYCLECOUNT, ZBATTERYFCC, ZBATTERYDC
            FROM ZHISTORYENTITY ORDER BY ZDATASNAPSHOTDATE
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MahgicError.diagnostics("Unsupported coconutBattery database format")
        }
        defer { sqlite3_finalize(stmt) }

        func text(_ col: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, col) else { return nil }
            return String(cString: c)
        }

        var added = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            let date = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 0))
            guard let serial = text(2), !serial.isEmpty else { continue }
            let duplicate = entries.contains {
                $0.deviceSerial == serial && abs($0.date.timeIntervalSince(date)) < 1
            }
            if duplicate { continue }
            entries.append(HistoryEntry(
                date: date,
                kind: text(1) == "Mac" ? .mac : .ios,
                deviceSerial: serial,
                deviceName: text(3) ?? "Device",
                modelIdentifier: text(4) ?? "",
                osVersion: text(5),
                batterySerial: text(6),
                cycleCount: Int(sqlite3_column_int64(stmt, 7)),
                fullChargeCapacity: Int(sqlite3_column_int64(stmt, 8)),
                designCapacity: Int(sqlite3_column_int64(stmt, 9)),
                source: "coconutBattery"
            ))
            added += 1
        }
        entries.sort { $0.date < $1.date }
        save()
        return added
    }
}
