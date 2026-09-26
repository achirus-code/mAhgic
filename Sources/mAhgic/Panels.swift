import Charts
import SwiftUI
import mAhgicCore

// MARK: - Window content

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Text("mAhgic")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.muted)
                .frame(height: 28)
            DeviceStrip()
                .padding(.bottom, 8)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            Group {
                switch model.selection {
                case .mac: MacPanel()
                case .device(let udid): IOSPanel(udid: udid)
                case .history: HistoryPanel()
                case .connectHelp: ConnectHelpPanel()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        // Extends the content under the hidden title bar; the fixed frame below is the area
        // *below* the title bar, so the window ends up 300 × 560 without an empty strip.
        .ignoresSafeArea()
        .frame(width: 300, height: 553)
        .preferredColorScheme(.dark)
        .tint(Theme.amber)
    }
}

// MARK: - Device strip

struct DeviceStrip: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                macButton
                ForEach(model.devices) { device in
                    deviceButton(device)
                }
                if model.devices.isEmpty {
                    StripButton(label: "iPhone", selected: model.selection == .connectHelp, dimmed: true) {
                        Image(systemName: "iphone.slash")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.faint)
                    } action: {
                        model.selection = .connectHelp
                    }
                }
                StripButton(label: "History", selected: model.selection == .history) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                } action: {
                    model.selection = .history
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private var macButton: some View {
        let s = model.macSystem
        let pct = model.macBattery.map { Double($0.chargePercent) }
        return StripButton(label: "Mac", selected: model.selection == .mac, charge: pct) {
            Image(nsImage: DeviceCatalog.icon(for: s.modelIdentifier, fallbackSymbol: "laptopcomputer"))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        } action: {
            model.selection = .mac
        }
    }

    private func deviceButton(_ device: MuxDevice) -> some View {
        var label = "…"
        var productType = ""
        var pct: Double?
        var failed = false
        switch model.deviceStates[device.udid] {
        case .loaded(let info, _):
            label = info.name
            productType = info.productType
            pct = info.battery.chargePercent.map(Double.init)
        case .failed:
            failed = true
            label = "Error"
        default:
            break
        }
        return StripButton(label: label, selected: model.selection == .device(device.udid), charge: pct,
                           badge: device.connection == .network ? "wifi" : nil) {
            if failed {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
            } else if productType.isEmpty {
                ProgressView().controlSize(.small)
            } else {
                Image(nsImage: DeviceCatalog.icon(for: productType, fallbackSymbol: "iphone"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            }
        } action: {
            model.selection = .device(device.udid)
        }
    }
}

struct StripButton<Icon: View>: View {
    var label: String
    var selected: Bool
    var charge: Double? = nil
    var dimmed = false
    var badge: String? = nil
    @ViewBuilder var icon: Icon
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    if let charge {
                        MiniRing(fraction: charge / 100, tint: Theme.charge(charge))
                    } else {
                        Circle().stroke(Color.white.opacity(dimmed ? 0.06 : 0.1),
                                        style: StrokeStyle(lineWidth: 1.5, dash: dimmed ? [3, 3] : []))
                    }
                    icon
                }
                .frame(width: 38, height: 38)
                .overlay(alignment: .bottomTrailing) {
                    if let badge {
                        Image(systemName: badge)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Theme.cream)
                            .padding(2.5)
                            .background(Circle().fill(Theme.blue))
                    }
                }
                Text(label)
                    .font(.system(size: 9, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.cream : Theme.muted)
                    .lineLimit(1)
                    .frame(width: 48)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Theme.amber.opacity(0.18) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Theme.amber.opacity(0.4) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}

// MARK: - Device panel (shared by Mac and iOS)

struct PanelData {
    var icon: NSImage
    var name: String
    var subtitle: String
    var chargePercent: Double?
    var health: Double?
    var power: PowerState
    var timeInfo: String?
    var stats: [StatSpec]
    var historySerial: String?
    var details: [KVSection]
    var updated: Date?
    var warning: String?
    var onRefresh: () -> Void
    /// Raw IORegistry rows, loaded only when the raw-values window is opened.
    var rawValues: () -> [(String, String)]
}

struct DevicePanel: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("panelSegment") private var segment = "stats"
    @State private var showRaw = false
    @State private var rawRows: [(String, String)] = []
    var data: PanelData

    var body: some View {
        VStack(spacing: 8) {
            header
            if let warning = data.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.orange)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 22) {
                RingGauge(fraction: (data.chargePercent ?? 0) / 100, tint: Theme.charge(data.chargePercent),
                          value: data.chargePercent.map { "\(Int($0)) %" } ?? "—", caption: "Charge")
                RingGauge(fraction: (data.health ?? 0) / 100, tint: Theme.health(data.health),
                          value: Fmt.percent(data.health, digits: 1), caption: "Health")
            }
            .padding(.top, 5)
            HStack(spacing: 5) {
                Image(systemName: data.power.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(data.power.tint)
                Text(data.power.text)
                    .foregroundStyle(Theme.cream)
                if let time = data.timeInfo {
                    Text("· \(time)").foregroundStyle(Theme.muted)
                }
            }
            .font(.system(size: 10.5, weight: .medium))
            .lineLimit(1)
            .padding(.top, 5)
            .padding(.bottom, 7)
            SegmentBar(items: [("stats", "Stats"), ("history", "History"), ("details", "Details")],
                       selection: $segment)
            Group {
                switch segment {
                case "history": historySegment
                case "details": ScrollView { KVList(sections: data.details).padding(.bottom, 8) }
                default: statsSegment
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .sheet(isPresented: $showRaw) {
            RawValuesSheet(title: data.name, rows: rawRows)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: data.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(data.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                Text(data.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            IconButton(symbol: "curlybraces", help: "Raw battery values") {
                rawRows = data.rawValues()
                showRaw = true
            }
            IconButton(symbol: "arrow.clockwise",
                       help: "Refresh · last update \(data.updated?.formatted(date: .omitted, time: .standard) ?? "—")",
                       action: data.onRefresh)
        }
    }

    private var statsSegment: some View {
        let rows = stride(from: 0, to: data.stats.count, by: 2).map { Array(data.stats[$0..<min($0 + 2, data.stats.count)]) }
        return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row) { StatCell(stat: $0) }
                    if row.count == 1 { Color.clear }
                }
            }
        }
    }

    @ViewBuilder
    private var historySegment: some View {
        if let group = model.history(forSerial: data.historySerial) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HealthChart(series: [(group.title, group.entries)])
                        .frame(height: 96)
                    MonthRows(periods: group.periods)
                }
                .padding(.bottom, 8)
            }
        } else {
            Text("No history yet – measurements are saved automatically.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 30)
        }
    }
}

// MARK: - Mac

struct MacPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let b = model.macBattery {
            DevicePanel(data: data(b))
        } else {
            MessageView(symbol: "powerplug", title: "No internal battery",
                        message: "This Mac runs on mains power only.")
        }
    }

    private func data(_ b: MacBatteryInfo) -> PanelData {
        let s = model.macSystem
        var time: String?
        if let m = b.timeToFull { time = "\(Fmt.duration(minutes: m)) to full" }
        if let m = b.timeToEmpty { time = "\(Fmt.duration(minutes: m)) left" }
        let adapterValue = b.externalConnected ? (b.adapterWatts.map { "\($0) W" } ?? "Connected") : "—"

        return PanelData(
            icon: DeviceCatalog.icon(for: s.modelIdentifier, fallbackSymbol: "laptopcomputer"),
            name: s.familyName,
            subtitle: [s.variantName, s.regulatoryModel].compactMap { $0 }.joined(separator: " · "),
            chargePercent: Double(b.chargePercent),
            health: b.health,
            power: PowerState(amperage: b.amperage, watts: b.batteryPower,
                              externalConnected: b.externalConnected, fullyCharged: b.fullyCharged),
            timeInfo: time,
            stats: [
                StatSpec(symbol: "battery.50percent", tint: Theme.green, title: "Charge",
                         value: Fmt.mAh(b.currentCapacity), note: "\(b.chargePercent) % of full"),
                StatSpec(symbol: "battery.100percent", tint: Theme.green, title: "Full Charge",
                         value: Fmt.mAh(b.fullChargeCapacity), note: "Nominal \(Fmt.mAh(b.nominalChargeCapacity))"),
                StatSpec(symbol: "sparkles", tint: Theme.amber, title: "Design Capacity",
                         value: Fmt.mAh(b.designCapacity), note: "when new"),
                StatSpec(symbol: "arrow.triangle.2.circlepath", tint: Theme.blue, title: "Cycles",
                         value: "\(b.cycleCount)", note: b.designCycleCount.map { "of \($0.formatted()) rated" }),
                StatSpec(symbol: "thermometer.medium", tint: b.temperature > 40 ? Theme.red : Theme.orange,
                         title: "Temperature", value: Fmt.temperature(b.temperature)),
                StatSpec(symbol: "calendar", tint: Theme.amber, title: "Manufactured",
                         value: Fmt.day(b.manufactureDate), note: b.manufactureDate.map(ageString(since:))),
                StatSpec(symbol: "powerplug.fill", tint: Theme.blue, title: "Adapter",
                         value: adapterValue, note: b.externalConnected ? b.adapterName : "not connected"),
                StatSpec(symbol: "leaf.fill", tint: model.lowPowerMode ? Theme.green : Theme.faint,
                         title: "Low Power Mode", value: model.lowPowerMode ? "Enabled" : "Disabled",
                         note: "\(Fmt.volts(b.voltage)) · \(b.amperage) mA"),
            ],
            historySerial: s.serialNumber,
            details: Sections.mac(s) + Sections.macBattery(b),
            updated: b.readDate,
            onRefresh: { model.refreshMac() },
            rawValues: { MacBatteryReader.readRegistry().map { RawValues.flatten($0) } ?? [] })
    }
}

// MARK: - iPhone / iPad

struct IOSPanel: View {
    @EnvironmentObject private var model: AppModel
    var udid: String

    var body: some View {
        switch model.deviceStates[udid] {
        case .loaded(let info, let error):
            DevicePanel(data: data(info, warning: error))
        case .failed(let message):
            MessageView(symbol: "exclamationmark.triangle", title: "Could not read the device",
                        message: message, actionTitle: "Try Again") { model.reload(udid: udid) }
        case .loading, .none:
            VStack(spacing: 10) {
                ProgressView()
                Text("Reading battery data…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func data(_ info: IOSDeviceInfo, warning: String?) -> PanelData {
        let b = info.battery
        let symbol = info.deviceClass == "iPad" ? "ipad" : "iphone"
        let adapterValue = b.externalConnected ? (b.adapterWatts.map { "\($0) W" } ?? "Connected") : "—"

        return PanelData(
            icon: DeviceCatalog.icon(for: info.productType, fallbackSymbol: symbol),
            name: info.name,
            subtitle: "\(info.marketingName) · iOS \(info.osVersion)",
            chargePercent: b.chargePercent.map(Double.init),
            health: b.health,
            power: PowerState(amperage: b.amperage, watts: b.watts,
                              externalConnected: b.externalConnected, fullyCharged: b.fullyCharged),
            timeInfo: nil,
            stats: [
                StatSpec(symbol: "battery.50percent", tint: Theme.green, title: "Charge",
                         value: Fmt.mAh(b.currentCapacity), note: b.chargePercent.map { "\($0) % of full" }),
                StatSpec(symbol: "battery.100percent", tint: Theme.green, title: "Full Charge",
                         value: Fmt.mAh(b.fullChargeCapacity)),
                StatSpec(symbol: "sparkles", tint: Theme.amber, title: "Design Capacity",
                         value: Fmt.mAh(b.designCapacity), note: "when new"),
                StatSpec(symbol: "arrow.triangle.2.circlepath", tint: Theme.blue, title: "Cycles",
                         value: b.cycleCount.map { "\($0)" } ?? "—"),
                StatSpec(symbol: "thermometer.medium", tint: (b.temperature ?? 0) > 40 ? Theme.red : Theme.orange,
                         title: "Temperature", value: Fmt.temperature(b.temperature)),
                StatSpec(symbol: "waveform.path.ecg", tint: Theme.blue, title: "Voltage",
                         value: Fmt.volts(b.voltage), note: b.amperage.map { "\($0) mA" }),
                StatSpec(symbol: "powerplug.fill", tint: Theme.blue, title: "Adapter",
                         value: adapterValue, note: b.externalConnected ? b.adapterName : "not connected"),
                StatSpec(symbol: info.connection == .usb ? "cable.connector" : "wifi", tint: Theme.blue,
                         title: "Connected via", value: info.connection.rawValue,
                         note: info.regulatoryModel ?? info.modelNumber),
            ],
            historySerial: info.serialNumber,
            details: Sections.device(info) + Sections.deviceBattery(b),
            updated: info.readDate,
            warning: warning.map { "Last refresh failed: \($0)" },
            onRefresh: { model.reload(udid: udid) },
            rawValues: { b.rawValues })
    }
}

// MARK: - History

struct HistoryPanel: View {
    @EnvironmentObject private var model: AppModel
    @State private var expanded = Set<String>()

    private static let palette: [Color] = [Theme.green, Theme.amber, Theme.blue, Theme.violet, Theme.red]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("History")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.cream)
                    Text("\(model.historyGroups.reduce(0) { $0 + $1.entries.count }) measurements")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if HistoryStore.coconutAvailable {
                    IconButton(symbol: "square.and.arrow.down", help: "Import coconutBattery history") {
                        model.importCoconut()
                    }
                }
                IconButton(symbol: "square.and.arrow.up", help: "Export history as CSV") {
                    model.exportCSV()
                }
            }
            if !model.historyGroups.isEmpty {
                HealthChart(series: model.historyGroups.map { ($0.title, $0.entries) })
                    .frame(height: 100)
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(model.historyGroups.enumerated()), id: \.element.id) { index, group in
                        groupView(group, color: Self.palette[index % Self.palette.count])
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private func groupView(_ group: HistoryDeviceGroup, color: Color) -> some View {
        let isOpen = expanded.contains(group.id)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                if isOpen { expanded.remove(group.id) } else { expanded.insert(group.id) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(Theme.faint)
                        .frame(width: 8)
                    Circle().fill(color).frame(width: 6, height: 6)
                    Image(nsImage: DeviceCatalog.icon(for: group.modelIdentifier,
                                                      fallbackSymbol: group.kind == .mac ? "laptopcomputer" : "iphone"))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(group.entries.last?.deviceName ?? group.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.cream)
                            .lineLimit(1)
                        Text(DeviceCatalog.marketingName(for: group.modelIdentifier) ?? group.modelIdentifier)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let last = group.entries.last {
                        Text(Fmt.percent(last.health))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.health(last.health))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Delete History of This Device", role: .destructive) {
                    model.deleteHistoryDevice(serial: group.serial)
                }
            }

            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    MonthRows(periods: group.periods)
                    Text("MEASUREMENTS")
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.amber)
                        .padding(.top, 2)
                    ForEach(group.entries.reversed()) { entry in
                        HStack(spacing: 6) {
                            Text(entry.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))
                                .foregroundStyle(Theme.muted)
                            Spacer(minLength: 2)
                            Text(Fmt.percent(entry.health, digits: 1)).foregroundStyle(Theme.cream)
                            Text("\(entry.cycleCount) cyc.").foregroundStyle(Theme.faint).frame(width: 52, alignment: .trailing)
                            Button {
                                model.deleteHistory(ids: [entry.id])
                            } label: {
                                Image(systemName: "trash").font(.system(size: 8.5))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.faint)
                            .help("Delete this measurement (\(entry.source ?? "mAhgic"), \(Fmt.mAh(entry.fullChargeCapacity)) / \(Fmt.mAh(entry.designCapacity)))")
                        }
                        .font(.system(size: 10).monospacedDigit())
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .padding(.bottom, 6)
            }
        }
    }
}

struct MonthRows: View {
    var periods: [HistoryDeviceGroup.Period]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Month")
                Spacer()
                Text("ø Health").frame(width: 60, alignment: .trailing)
                Text("Cycles").frame(width: 46, alignment: .trailing)
            }
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(Theme.faint)
            .padding(.bottom, 3)
            ForEach(Array(periods.reversed().enumerated()), id: \.element.id) { index, period in
                HStack {
                    Text(period.label).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(Fmt.percent(period.averageHealth))
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.health(period.averageHealth))
                        .frame(width: 60, alignment: .trailing)
                    Text("\(period.cycles)")
                        .foregroundStyle(Theme.cream)
                        .frame(width: 46, alignment: .trailing)
                }
                .font(.system(size: 10.5).monospacedDigit())
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(index.isMultiple(of: 2) ? Color.white.opacity(0.035) : .clear)
            }
        }
    }
}

struct HealthChart: View {
    var series: [(name: String, entries: [HistoryEntry])]

    private static let palette: [Color] = [Theme.green, Theme.amber, Theme.blue, Theme.violet, Theme.red]

    var body: some View {
        let all = series.flatMap(\.entries)
        let low = floor(min(all.map(\.health).min() ?? 80, 80) - 3)
        let high = ceil(max(all.map(\.health).max() ?? 100, 100) + 2)
        return Chart {
            ForEach(Array(series.enumerated()), id: \.offset) { _, s in
                ForEach(s.entries) { entry in
                    LineMark(x: .value("Date", entry.date), y: .value("Health", entry.health))
                        .foregroundStyle(by: .value("Device", s.name))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", entry.date), y: .value("Health", entry.health))
                        .foregroundStyle(by: .value("Device", s.name))
                        .symbolSize(12)
                }
            }
            RuleMark(y: .value("Replace", 80))
                .foregroundStyle(Theme.orange.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .chartForegroundStyleScale(domain: series.map(\.name),
                                   range: series.indices.map { Self.palette[$0 % Self.palette.count] })
        .chartLegend(.hidden)
        .chartYScale(domain: low...high)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))%").font(.system(size: 8)).foregroundStyle(Theme.faint)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel().font(.system(size: 8)).foregroundStyle(Theme.faint)
            }
        }
    }
}

// MARK: - Messages

struct ConnectHelpPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 1) {
                    Text("No iPhone or iPad found")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.cream)
                    Text("Connect one via USB or Wi‑Fi")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                step("1", "Connect the device via USB and tap “Trust this Computer”.")
                step("2", "In Finder, select the device and enable “Show this iPhone when on Wi‑Fi”.")
                step("3", "Keep the device in the same network as this Mac – it then shows up without a cable.")
            }
            if let error = model.usbmuxError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.red)
            }
            Spacer()
        }
        .padding(16)
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x1E1713))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Theme.amber))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MessageView: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.amber)
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.cream)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Raw values

struct RawValuesSheet: View {
    var title: String
    var rows: [(String, String)]
    @State private var filter = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [(String, String)] {
        guard !filter.isEmpty else { return rows }
        return rows.filter { $0.0.localizedCaseInsensitiveContains(filter) || $0.1.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 1) {
                Text("Raw Battery Values")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.cream)
                Text("\(title) · \(rows.count) IORegistry keys")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
            }
            TextField("Search", text: $filter)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.offset) { index, row in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.0)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Theme.amber)
                            Text(row.1)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.cream)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index.isMultiple(of: 2) ? Color.white.opacity(0.035) : .clear)
                    }
                }
            }
            HStack {
                Button("Copy All") {
                    let text = rows.map { "\($0.0) = \($0.1)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 290, height: 470)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}
