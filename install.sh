#!/bin/sh
set -eu

REPO="${DICTIONARY_REPO:-https://github.com/3una/dictionary.git}"
INSTALL_DIR="${DICTIONARY_INSTALL_DIR:-$HOME/.local/bin}"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift is required. Install Apple's command-line tools with: xcode-select --install" >&2
  exit 1
fi

git clone --depth 1 "$REPO" "$BUILD_DIR/source"
cd "$BUILD_DIR/source"
swift build -c release
mkdir -p "$INSTALL_DIR"
cp .build/release/dictionary "$INSTALL_DIR/dictionary"
chmod +x "$INSTALL_DIR/dictionary"
printf 'Installed dictionary to %s/dictionary\n' "$INSTALL_DIR"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) printf 'Add this to your shell profile if needed: export PATH="%s:$PATH"\n' "$INSTALL_DIR" ;;
esac
