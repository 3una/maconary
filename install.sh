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
  *)
    case "${SHELL:-}" in
      */zsh) SHELL_PROFILE="$HOME/.zshrc" ;;
      */bash) SHELL_PROFILE="$HOME/.bash_profile" ;;
      *) SHELL_PROFILE="$HOME/.profile" ;;
    esac
    mkdir -p "$(dirname "$SHELL_PROFILE")"
    touch "$SHELL_PROFILE"
    if [ "$INSTALL_DIR" = "$HOME/.local/bin" ]; then
      PATH_ENTRY='export PATH="$HOME/.local/bin:$PATH"'
      PROFILE_MATCH='$HOME/.local/bin'
    else
      PATH_ENTRY="export PATH=\"$INSTALL_DIR:\$PATH\""
      PROFILE_MATCH="$INSTALL_DIR"
    fi
    if ! grep -Fq "$PROFILE_MATCH" "$SHELL_PROFILE"; then
      printf '\n%s\n' "$PATH_ENTRY" >> "$SHELL_PROFILE"
      printf 'Added %s to %s. Open a new Terminal window to use dictionary.\n' "$INSTALL_DIR" "$SHELL_PROFILE"
    fi
    ;;
esac
