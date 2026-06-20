import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var manager: PokeConnectManager
    @State private var isConfiguringNgrok = false
    @State private var isResettingSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            Form {
                Section("Setup") {
                    SetupStepRow(
                        title: "ngrok tunnel",
                        isComplete: manager.tunnelStatus == .running && !manager.mcpURL.isEmpty,
                        detail: manager.mcpURL.isEmpty ? "Start the bridge to generate a public MCP URL." : manager.mcpURL
                    )
                    SetupStepRow(
                        title: "ngrok authtoken",
                        isComplete: manager.ngrokAuthtokenConfigured,
                        detail: manager.ngrokAuthtokenConfigured ? "Saved to ngrok." : "Required before anything else can run."
                    )
                    SetupStepRow(
                        title: "Poke MCP integration",
                        isComplete: manager.pokeIntegrationConnected,
                        detail: manager.pokeIntegrationConnected ? "Marked connected." : "Connect the generated MCP URL in Poke."
                    )
                    if !manager.isSetupComplete {
                        Text(manager.setupStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Button(role: .destructive) {
                        isResettingSetup = true
                        Task {
                            await manager.resetSetup()
                            isResettingSetup = false
                        }
                    } label: {
                        Label("Reset Setup", systemImage: "arrow.counterclockwise.circle")
                    }
                    .disabled(isResettingSetup)
                    Text("Stops the bridge, clears setup status and the generated ngrok URL. Your pasted token text is kept.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    TextField("Static domain (optional)", text: $manager.ngrokDomain)
                    Text("Leave empty to let ngrok generate the public URL after the tunnel starts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Text("Save the token first. Then click Connect in the menu bar to start ngrok and generate the MCP URL.")
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
                        .disabled(manager.mcpURL.isEmpty)

                        Button {
                            manager.openPokeIntegrationPage()
                        } label: {
                            Label("Connect Poke", systemImage: "link")
                        }
                        .disabled(manager.mcpURL.isEmpty)

                        Button {
                            manager.markPokeIntegrationConnected()
                        } label: {
                            Label("I Connected Poke", systemImage: "checkmark.circle")
                        }
                        .disabled(manager.mcpURL.isEmpty)
                    }
                    Text("First save your ngrok authtoken, then start the bridge. After ngrok generates the MCP URL, paste it into Poke and confirm here.")
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
                    LabeledContent("Public URL", value: manager.publicURL.isEmpty ? "Not generated yet" : manager.publicURL)
                    LabeledContent("MCP URL", value: manager.mcpURL.isEmpty ? "Not generated yet" : manager.mcpURL)
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
