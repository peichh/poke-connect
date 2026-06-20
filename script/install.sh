#!/usr/bin/env bash
set -euo pipefail

REPO="peichh/poke-connect"
APP_NAME="Poke Connect"
APP_BUNDLE="$APP_NAME.app"
BUNDLE_ID="dev.local.PokeConnect"
INSTALL_DIR="/Applications"
if [[ ! -w "$INSTALL_DIR" ]]; then
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
fi
INSTALL_PATH="$INSTALL_DIR/$APP_BUNDLE"
POKE_URL="https://poke.com/integrations/new"

NGROK_AUTHTOKEN=""
MARK_POKE_CONNECTED="false"
OPEN_POKE="false"

usage() {
  cat <<USAGE
Install Poke Connect.

Usage:
  curl -fsSL https://raw.githubusercontent.com/$REPO/main/script/install.sh | bash

Optional first-run setup:
  bash install.sh --ngrok-authtoken <token> [--mark-poke-connected] [--open-poke]

Options:
  --ngrok-authtoken <token>   Save the ngrok authtoken into app preferences.
  --mark-poke-connected      Mark the Poke MCP integration step complete.
  --open-poke                Open the Poke integrations page after install.
  --help                     Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ngrok-authtoken)
      NGROK_AUTHTOKEN="${2:-}"
      shift 2
      ;;
    --mark-poke-connected)
      MARK_POKE_CONNECTED="true"
      shift
      ;;
    --open-poke)
      OPEN_POKE="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Poke Connect can only be installed on macOS." >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ZIP_PATH="$TMP_DIR/PokeConnect.zip"
DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/PokeConnect.zip"

echo "Downloading Poke Connect..."
curl -fL "$DOWNLOAD_URL" -o "$ZIP_PATH"

echo "Installing to $INSTALL_PATH..."
ditto -x -k "$ZIP_PATH" "$TMP_DIR"

if [[ ! -d "$TMP_DIR/$APP_BUNDLE" ]]; then
  echo "Release archive did not contain $APP_BUNDLE." >&2
  exit 1
fi

rm -rf "$INSTALL_PATH"
cp -R "$TMP_DIR/$APP_BUNDLE" "$INSTALL_PATH"

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$INSTALL_PATH" >/dev/null 2>&1 || true
fi

if [[ -n "$NGROK_AUTHTOKEN" ]]; then
  echo "Saving ngrok authtoken preference..."
  defaults write "$BUNDLE_ID" ngrokAuthtoken -string "$NGROK_AUTHTOKEN"
  if command -v ngrok >/dev/null 2>&1; then
    echo "Writing authtoken to ngrok config..."
    if ngrok config add-authtoken "$NGROK_AUTHTOKEN"; then
      defaults write "$BUNDLE_ID" ngrokAuthtokenConfigured -bool true
    else
      defaults write "$BUNDLE_ID" ngrokAuthtokenConfigured -bool false
      echo "ngrok token setup failed. Open Poke Connect Settings and click 'Save to ngrok' once."
    fi
  else
    defaults write "$BUNDLE_ID" ngrokAuthtokenConfigured -bool false
    echo "ngrok CLI was not found. Install ngrok, then open Poke Connect Settings and click 'Save to ngrok' once."
  fi
fi

if [[ "$MARK_POKE_CONNECTED" == "true" ]]; then
  defaults write "$BUNDLE_ID" pokeIntegrationConnected -bool true
fi

if [[ "$OPEN_POKE" == "true" ]]; then
  open "$POKE_URL" >/dev/null 2>&1 || true
fi

echo "Opening Poke Connect..."
open "$INSTALL_PATH"

echo "Done."
echo "MCP URL: https://uncounted-chummy-tidings.ngrok-free.dev/sse"
