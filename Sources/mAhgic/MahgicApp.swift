import AppKit
import SwiftUI
import mAhgicCore

@main
struct MahgicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("mAhgic", id: "main") {
            RootView()
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Battery") {
                Button("Refresh") { model.refreshAll() }
                    .keyboardShortcut("r")
                Divider()
                Button("This Mac") { model.selection = .mac }
                    .keyboardShortcut("1")
                Button("First iPhone/iPad") {
                    if let first = model.devices.first { model.selection = .device(first.udid) }
                }
                .keyboardShortcut("2")
                .disabled(model.devices.isEmpty)
                Button("History") { model.selection = .history }
                    .keyboardShortcut("3")
                Divider()
                Button("Import coconutBattery History") { model.importCoconut() }
                    .disabled(!HistoryStore.coconutAvailable)
                Button("Export History as CSV…") { model.exportCSV() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when started as a bare executable (swift run); harmless inside the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
