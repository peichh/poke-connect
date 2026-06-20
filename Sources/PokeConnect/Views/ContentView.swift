import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var manager: PokeConnectManager
    @Environment(\.openWindow) private var openWindow
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !manager.isSetupComplete {
                setupGate
            }
            statusGrid
            publicURLRow
            actionButtons
            Divider()
            preferences
            if !manager.lastError.isEmpty {
                errorText
            }
        }
        .padding(18)
        .task {
            await manager.refreshStatus()
        }
    }

    private var header: some View {
        HStack {
            Label("Poke Connect", systemImage: manager.menuBarSystemImage)
                .font(.headline)
            Spacer()
            StatusPill(status: manager.overallStatus.rawValue, tint: tint(for: manager.overallStatus))
        }
    }

    private var statusGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                Text("Overall")
                    .foregroundStyle(.secondary)
                Text(manager.overallStatus.rawValue)
                    .fontWeight(.semibold)
            }
            GridRow {
                Text("Server")
                    .foregroundStyle(.secondary)
                Text(manager.serverStatus.rawValue)
            }
            GridRow {
                Text("Tunnel")
                    .foregroundStyle(.secondary)
                Text(manager.tunnelStatus.rawValue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var publicURLRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Public URL")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(manager.publicHost)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var setupGate: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Setup Required", systemImage: "lock")
                .font(.subheadline.weight(.semibold))
            Text(manager.setupStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                runAction { await manager.connectOrDisconnect() }
            } label: {
                Label(manager.connectButtonTitle, systemImage: manager.overallStatus == .online ? "power" : "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || (!manager.isSetupComplete && manager.overallStatus != .online))

            HStack {
                Button {
                    runAction { await manager.restart() }
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                .disabled(isWorking || !manager.isSetupComplete)

                Button {
                    openWindow(id: "logs")
                } label: {
                    Label("Open Logs", systemImage: "doc.text.magnifyingglass")
                }

                Button {
                    manager.copyURL()
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                }
                .disabled(!manager.isSetupComplete)
            }

            HStack {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }

                Spacer()

                Button(role: .destructive) {
                    manager.quit()
                } label: {
                    Label("Quit", systemImage: "xmark.circle")
                }
            }
        }
    }

    private var preferences: some View {
        Toggle("Start at Login", isOn: $manager.startAtLogin)
    }

    private var errorText: some View {
        Text(manager.lastError)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(4)
            .textSelection(.enabled)
    }

    private func runAction(_ action: @escaping () async -> Void) {
        isWorking = true
        Task {
            await action()
            isWorking = false
        }
    }

    private func tint(for status: OverallStatus) -> Color {
        switch status {
        case .online:
            .green
        case .offline:
            .secondary
        case .starting:
            .orange
        case .error:
            .red
        }
    }
}

private struct StatusPill: View {
    let status: String
    let tint: Color

    var body: some View {
        Text(status)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }
}
