import SwiftUI

struct LogsView: View {
    @ObservedObject var manager: PokeConnectManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logs")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await manager.loadLogs() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button {
                    manager.logs = ""
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
            .padding()

            Divider()

            ScrollView {
                Text(manager.logs.isEmpty ? "No logs yet." : manager.logs)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
        }
        .task {
            await manager.loadLogs()
        }
    }
}
