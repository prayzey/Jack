#!/bin/bash
# notarize-release.sh — Builds, packages, and notarizes a release artifact.
# Usage:
#   ./scripts/notarize-release.sh release
#   NOTARY_PROFILE=clip-notary ./scripts/notarize-release.sh release dmg
#   NOTARY_PROFILE=clip-notary ./scripts/notarize-release.sh release zip

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

CONFIG="${1:-release}"
ARTIFACT_KIND="${2:-dmg}"
APP_NAME="${APP_NAME:-Jack}"
NOTARY_PROFILE="${NOTARY_PROFILE:-clip-notary}"
ZIP_NAME="${APP_NAME}.app.zip"
DMG_NAME="${DMG_NAME:-${APP_NAME}.dmg}"
APP_DIR="${APP_NAME}.app"

if [ "$CONFIG" != "release" ]; then
    echo "ERROR: notarization should use a release build."
    exit 1
fi

if [ "$ARTIFACT_KIND" != "dmg" ] && [ "$ARTIFACT_KIND" != "zip" ]; then
    echo "ERROR: artifact kind must be 'dmg' or 'zip'."
    exit 1
fi

echo "=== Preparing release artifacts for ${APP_NAME} ==="
"$SCRIPT_DIR/build-app.sh" "$CONFIG"
rm -f "$ZIP_NAME"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_NAME"

if [ "$ARTIFACT_KIND" = "dmg" ]; then
    "$SCRIPT_DIR/build-dmg.sh" "$CONFIG"
    ARTIFACT_PATH="$DMG_NAME"
else
    ARTIFACT_PATH="$ZIP_NAME"
fi

if [ ! -f "$ARTIFACT_PATH" ]; then
    echo "ERROR: Artifact not found at $ARTIFACT_PATH"
    exit 1
fi

echo "Submitting ${ARTIFACT_PATH} for notarization with profile ${NOTARY_PROFILE}..."
xcrun notarytool submit "$ARTIFACT_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "Stapling ${APP_DIR}..."
xcrun stapler staple "$APP_DIR"

if [ "$ARTIFACT_KIND" = "dmg" ]; then
    echo "Stapling ${ARTIFACT_PATH}..."
    xcrun stapler staple "$ARTIFACT_PATH"
fi

echo ""
echo "=== Notarization complete ==="
echo "Artifact: ${ARTIFACT_PATH}"
echo ""
echo "Suggested checks:"
echo "  codesign --verify --deep --strict --verbose=2 ${APP_DIR}"
echo "  spctl -a -t exec -vv ${APP_DIR}"
if [ "$ARTIFACT_KIND" = "dmg" ]; then
    echo "  spctl -a -t open --context context:primary-signature -vv ${ARTIFACT_PATH}"
fi
