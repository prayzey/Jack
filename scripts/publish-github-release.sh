#!/bin/bash
# publish-github-release.sh — Publishes the notarized DMG to GitHub Releases.
# Usage:
#   ./scripts/publish-github-release.sh
#   ./scripts/publish-github-release.sh --notes-file RELEASE_NOTES.md
#   ./scripts/publish-github-release.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION_FILE="VERSION"
APP_NAME="${APP_NAME:-Jack}"
REPOSITORY="${GITHUB_REPOSITORY_OVERRIDE:-prayzey/Jack}"
DMG_NAME="${DMG_NAME:-${APP_NAME}.dmg}"
TAG_NAME="${TAG_NAME:-v$(tr -d '[:space:]' < "$VERSION_FILE")}"
TITLE="${TITLE:-${TAG_NAME}}"
NOTES_FILE=""

if [ ! -f "$VERSION_FILE" ]; then
    echo "ERROR: VERSION file not found."
    exit 1
fi

if [ ! -f "$DMG_NAME" ]; then
    echo "ERROR: ${DMG_NAME} not found."
    echo "Run ./scripts/notarize-release.sh release dmg first."
    exit 1
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            echo "Usage:"
            echo "  ./scripts/publish-github-release.sh"
            echo "  ./scripts/publish-github-release.sh --notes-file RELEASE_NOTES.md"
            exit 0
            ;;
        --notes-file)
            NOTES_FILE="${2:-}"
            if [ -z "$NOTES_FILE" ]; then
                echo "ERROR: --notes-file needs a file path."
                exit 1
            fi
            shift 2
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            exit 1
            ;;
    esac
done

echo "Publishing ${DMG_NAME} to ${REPOSITORY} as ${TAG_NAME}..."

if gh release view "$TAG_NAME" --repo "$REPOSITORY" >/dev/null 2>&1; then
    echo "Release ${TAG_NAME} already exists. Uploading updated DMG..."
    gh release upload "$TAG_NAME" "$DMG_NAME" \
        --repo "$REPOSITORY" \
        --clobber
else
    CREATE_ARGS=(
        "$TAG_NAME"
        "$DMG_NAME"
        --repo "$REPOSITORY"
        --title "$TITLE"
        --generate-notes
    )

    if [ -n "$NOTES_FILE" ]; then
        CREATE_ARGS+=(--notes-file "$NOTES_FILE")
    fi

    gh release create "${CREATE_ARGS[@]}"
fi

echo ""
echo "Release is live:"
echo "  https://github.com/${REPOSITORY}/releases/tag/${TAG_NAME}"
echo "Stable download URL:"
echo "  https://github.com/${REPOSITORY}/releases/latest/download/${DMG_NAME}"
