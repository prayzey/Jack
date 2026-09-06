#!/bin/bash
# install-jack-cli.sh — Put `jack` on your PATH (no ./ prefix needed)
#
#   ./scripts/install-jack-cli.sh
#
# Then from any directory:
#   jack start
#   jack restart

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE="$PROJECT_ROOT/bin/jack"
DEST_DIR="${HOME}/.local/bin"
DEST="${DEST_DIR}/jack"
ZSHRC="${HOME}/.zshrc"
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

mkdir -p "$DEST_DIR"
chmod +x "$SOURCE"
ln -sf "$SOURCE" "$DEST"

if ! echo ":$PATH:" | grep -q ":${DEST_DIR}:"; then
  if [[ -f "$ZSHRC" ]] && grep -Fq "$PATH_LINE" "$ZSHRC"; then
    :
  elif [[ -f "$ZSHRC" ]]; then
    printf '\n# Jack dev CLI\n%s\n' "$PATH_LINE" >>"$ZSHRC"
    echo "Added ~/.local/bin to PATH in ~/.zshrc"
  else
    echo "Add this to your shell config (~/.zshrc):"
    echo "  $PATH_LINE"
  fi
fi

echo "Installed: $DEST -> $SOURCE"
echo ""
echo "Open a new terminal (or run: source ~/.zshrc), then:"
echo "  jack start"
echo "  jack restart"
echo "  jack release"
