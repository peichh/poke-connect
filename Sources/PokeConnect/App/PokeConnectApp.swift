import SwiftUI

@main
struct PokeConnectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = PokeConnectManager()

    var body: some Scene {
        MenuBarExtra {
            ContentView(manager: manager)
                .frame(width: 340)
        } label: {
            Label("Poke Connect", systemImage: manager.menuBarSystemImage)
        }
        .menuBarExtraStyle(.window)

        Window("Poke Connect Logs", id: "logs") {
            LogsView(manager: manager)
                .frame(minWidth: 640, minHeight: 420)
        }

        Window("Poke Connect Settings", id: "settings") {
            SettingsView(manager: manager)
                .frame(minWidth: 620, minHeight: 520)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
