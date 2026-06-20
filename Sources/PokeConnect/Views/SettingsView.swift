import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var manager: PokeConnectManager
    @State private var isConfiguringNgrok = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            Form {
                Section("Setup") {
                    SetupStepRow(
                        title: "ngrok authtoken",
                        isComplete: manager.ngrokAuthtokenConfigured,
                        detail: manager.ngrokAuthtokenConfigured ? "Saved to ngrok." : "Required before anything else can run."
                    )
                    SetupStepRow(
                        title: "Poke MCP integration",
                        isComplete: manager.pokeIntegrationConnected,
                        detail: manager.pokeIntegrationConnected ? "Marked connected." : "Connect the MCP URL in Poke after ngrok is ready."
                    )
                    if !manager.isSetupComplete {
                        Text(manager.setupStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Launch") {
                    Toggle("Start at Login", isOn: $manager.startAtLogin)
                        .disabled(!manager.isSetupComplete)
                    Toggle("Auto-connect on launch", isOn: $manager.autoConnectOnLaunch)
                        .disabled(!manager.isSetupComplete)
                }

                Section("Script Folder") {
                    HStack {
                        TextField("Working directory", text: $manager.workingDirectory)
                        Button {
                            chooseWorkingDirectory()
                        } label: {
                            Label("Choose", systemImage: "folder")
                        }
                    }
                    Button {
                        manager.useBundledServerFolder()
                    } label: {
                        Label("Use Bundled Server", systemImage: "shippingbox")
                    }
                    Text("Folder containing server.ts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Command Paths") {
                    TextField("PM2 command path", text: $manager.pm2CommandPath)
                    TextField("ngrok command path", text: $manager.ngrokCommandPath)
                }

                Section("ngrok") {
                    SecureField("Your Authtoken", text: $manager.ngrokAuthtoken)
                    HStack {
                        Button {
                            manager.openNgrokAuthtokenPage()
                        } label: {
                            Label("Get Authtoken", systemImage: "safari")
                        }

                        Button {
                            isConfiguringNgrok = true
                            Task {
                                await manager.configureNgrokAuthtoken()
                                isConfiguringNgrok = false
                            }
                        } label: {
                            Label("Save to ngrok", systemImage: "key")
                        }
                        .disabled(manager.ngrokAuthtoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConfiguringNgrok)
                    }
                    Text("Required before starting a reserved ngrok domain. If you do not have a token yet, open the ngrok dashboard link above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Poke") {
                    LabeledContent("MCP URL", value: manager.mcpURL)
                    HStack {
                        Button {
                            manager.copyURL()
                        } label: {
                            Label("Copy MCP URL", systemImage: "doc.on.doc")
                        }

                        Button {
                            manager.openPokeIntegrationPage()
                        } label: {
                            Label("Connect Poke", systemImage: "link")
                        }
                        .disabled(!manager.ngrokAuthtokenConfigured)

                        Button {
                            manager.markPokeIntegrationConnected()
                        } label: {
                            Label("I Connected Poke", systemImage: "checkmark.circle")
                        }
                        .disabled(!manager.ngrokAuthtokenConfigured)
                    }
                    Text("First save your ngrok authtoken. Then open Poke, paste the MCP URL, finish the integration, and confirm here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Commands") {
                    TextField("Server command", text: $manager.customServerCommand, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Tunnel command", text: $manager.customNgrokCommand, axis: .vertical)
                        .lineLimit(2...4)
                    Button {
                        manager.resetCommandsToDefaults()
                    } label: {
                        Label("Reset Commands", systemImage: "arrow.counterclockwise")
                    }
                }

                Section("Status") {
                    LabeledContent("Public URL", value: manager.publicURL)
                    LabeledContent("MCP URL", value: manager.mcpURL)
                    if !manager.lastError.isEmpty {
                        Text(manager.lastError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var header: some View {
        HStack {
            Label("Poke Connect Settings", systemImage: "gearshape")
                .font(.headline)
            Spacer()
            Button {
                NSApp.keyWindow?.close()
            } label: {
                        Label("Close", systemImage: "xmark")
            }
        }
        .padding()
    }

    private func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose folder containing server.ts"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: manager.workingDirectory)

        if panel.runModal() == .OK, let url = panel.url {
            manager.workingDirectory = url.path
        }
    }
}

private struct SetupStepRow: View {
    let title: String
    let isComplete: Bool
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
