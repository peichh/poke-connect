# Poke Connect

Poke Connect is a native macOS menu bar app for starting and stopping a local PM2 server plus an ngrok tunnel.

## Build and Run

From this directory:

```bash
./script/build_and_run.sh
```

The script builds the SwiftPM app, stages `dist/Poke Connect.app`, and opens it as a menu-bar-only app.

You can also open the package in Xcode:

```bash
open Package.swift
```

Select the `Poke Connect` executable target, then build and run.

## Install From GitHub

After a release is published, install the latest version with:

```bash
curl -fsSL https://raw.githubusercontent.com/peichh/poke-connect/main/script/install.sh | bash
```

Optional first-run setup:

```bash
curl -fsSL https://raw.githubusercontent.com/peichh/poke-connect/main/script/install.sh | bash -s -- --ngrok-authtoken YOUR_NGROK_TOKEN --open-poke
```

The installer downloads `PokeConnect.zip` from the latest GitHub Release, installs `Poke Connect.app` to `/Applications`, clears the download quarantine flag for the app bundle, and opens the app.

If you pass `--ngrok-authtoken`, the installer saves the token into app preferences. You still need to open Settings once and click **Save to ngrok**, so the token is written into ngrok's own config on that Mac.

## Configure the Working Directory

Poke Connect includes a bundled copy of `mac-local-manager`. On first launch, the app copies it to:

```text
~/Library/Application Support/Poke Connect/mac-local-manager
```

That bundled copy is the default **Working directory**, so most users do not need to choose a folder manually.

If you want to use a different copy, open the menu bar item, click **Settings**, and set **Working directory** to the folder containing `server.ts`. You can type the path manually or click **Choose**.

To switch back to the bundled copy, click **Use Bundled Server**.

The previous local development folder was:

```text
/Users/peach/Documents/Codex/2026-06-20/brew-install-node/mac-local-manager
```

The default server command is:

```bash
pm2 start npm --name "mac-local-server" -- start
```

That command runs with the configured working directory. The bundled server package includes local `pm2`, `ts-node`, `typescript`, and the MCP/Express dependencies it needs.

## Start at Login

Enable **Start at Login** in the menu bar UI or Settings window.

The app uses `SMAppService.mainApp` on macOS 13+. For a production Xcode app, verify:

- The app has a stable bundle identifier.
- The app is signed.
- The final `.app` bundle is launched from a normal app location such as `/Applications`.

The generated SwiftPM run script creates a local development bundle in `dist/`.

## Auto-connect on Launch

In Settings, enable **Auto-connect on launch**. When Poke Connect starts, it will automatically run the same Connect flow used by the main button.

## PM2 and ngrok Path Troubleshooting

The app runs commands with:

```bash
/bin/zsh -lc "<command>"
```

This usually loads your shell environment, but GUI apps can still see a different `PATH` than Terminal.

Poke Connect defaults to the bundled PM2 path:

```text
./node_modules/.bin/pm2
```

That path is resolved inside the bundled server working directory.

If ngrok is not found:

1. Run `which ngrok` in Terminal.
2. Paste that full path into **ngrok command path** in Settings.
3. Confirm the server working directory points at the folder with `server.ts`.

The default tunnel command is:

```bash
ngrok http --url=uncounted-chummy-tidings.ngrok-free.dev 3000
```

## ngrok Authtoken

Open **Settings**, paste your ngrok authtoken into **Your Authtoken**, then click **Save to ngrok**.

If you do not have a token yet, click **Get Authtoken** or open:

```text
https://dashboard.ngrok.com/get-started/your-authtoken
```

Poke Connect locks the main bridge controls until this step succeeds.

## Poke MCP Setup

After saving the ngrok authtoken:

1. Copy the MCP URL from Settings.
2. Click **Connect Poke** or open `https://poke.com/integrations/new`.
3. Paste the MCP URL into Poke and finish creating the integration.
4. Return to Poke Connect and click **I Connected Poke**.

The main **Connect**, **Restart**, and menu-bar **Copy URL** controls remain disabled until both ngrok and Poke setup are complete.

The default stop command for ngrok is:

```bash
pkill -f "ngrok http --url=uncounted-chummy-tidings.ngrok-free.dev 3000"
```

## Verify It Is Working

1. Open Poke Connect from the menu bar.
2. Click **Connect**.
3. The app should show:
   - Overall: `Online`
   - Server: `Running`
   - Tunnel: `Running`
4. Click **Open Logs** to view recent PM2 logs and current ngrok process output.
5. Click **Copy URL** and confirm the clipboard contains the MCP SSE URL:

```text
https://uncounted-chummy-tidings.ngrok-free.dev/sse
```

To connect this to Poke, open **Settings** and click **Connect Poke**, or visit:

```text
https://poke.com/integrations/new
```

Manual checks:

```bash
pm2 jlist
ps ax -o pid= -o command= | grep '[n]grok'
```

## Files

- `Sources/PokeConnect/App/PokeConnectApp.swift`
- `Sources/PokeConnect/Views/ContentView.swift`
- `Sources/PokeConnect/Views/SettingsView.swift`
- `Sources/PokeConnect/Views/LogsView.swift`
- `Sources/PokeConnect/Services/PokeConnectManager.swift`
- `Sources/PokeConnect/Services/ShellRunner.swift`
- `Sources/PokeConnect/Models/PokeStatus.swift`
- `Sources/PokeConnect/Support/String+ShellQuote.swift`
