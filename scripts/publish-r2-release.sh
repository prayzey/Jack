#!/bin/bash
# publish-r2-release.sh — Uploads release artifacts to Cloudflare R2.
#
# Usage:
#   ./scripts/publish-r2-release.sh              → uploads DMG + appcast.xml + version.json
#   ./scripts/publish-r2-release.sh --appcast-only  → uploads only appcast.xml + version.json
#
# Requires: aws CLI configured with the 'r2' profile
#   aws configure --profile r2
#   Endpoint: https://53efd4156db034899e5cf7b54238b7a1.r2.cloudflarestorage.com

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

R2_BUCKET="gilt-downloads"
R2_ENDPOINT="https://53efd4156db034899e5cf7b54238b7a1.r2.cloudflarestorage.com"
AWS_PROFILE="r2"
APP_NAME="${APP_NAME:-Jack}"
DMG_NAME="${DMG_NAME:-${APP_NAME}.dmg}"
RELEASE_BASENAME="${RELEASE_BASENAME:-Gilt}"
APPCAST_ONLY=false

if [ "${1:-}" = "--appcast-only" ]; then
    APPCAST_ONLY=true
fi

# Verify aws CLI is available
if ! command -v aws &>/dev/null; then
    echo "ERROR: aws CLI not found. Install it with: brew install awscli"
    exit 1
fi

# Helper: upload a file to R2 with content-type and cache-control
r2_upload() {
    local file="$1"
    local key="$2"
    local content_type="$3"
    local cache_control="$4"

    aws s3 cp "$file" "s3://${R2_BUCKET}/${key}" \
        --profile "$AWS_PROFILE" \
        --endpoint-url "$R2_ENDPOINT" \
        --content-type "$content_type" \
        --cache-control "$cache_control"
}

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG_NAME="v${VERSION}"
VERSIONED_DMG_NAME="${RELEASE_BASENAME}-${VERSION}.dmg"

if [ "$APPCAST_ONLY" = false ]; then
    if [ ! -f "$DMG_NAME" ]; then
        echo "ERROR: ${DMG_NAME} not found."
        echo "Build and notarize the DMG first:"
        echo "  ./scripts/build-app.sh release"
        echo "  ./scripts/notarize-release.sh release dmg"
        exit 1
    fi

    DMG_SIZE=$(stat -f%z "$DMG_NAME")
    echo "Uploading ${DMG_NAME} ($(echo "scale=1; $DMG_SIZE / 1048576" | bc)MB)..."
    echo ""

    echo "  → releases/${TAG_NAME}/${VERSIONED_DMG_NAME}"
    r2_upload "$DMG_NAME" "releases/${TAG_NAME}/${VERSIONED_DMG_NAME}" \
        "application/x-apple-diskimage" "public, max-age=31536000, immutable"

    echo "  → releases/${TAG_NAME}/${DMG_NAME}"
    r2_upload "$DMG_NAME" "releases/${TAG_NAME}/${DMG_NAME}" \
        "application/x-apple-diskimage" "public, max-age=31536000, immutable"

    echo "  → ${DMG_NAME} (stable latest)"
    r2_upload "$DMG_NAME" "${DMG_NAME}" \
        "application/x-apple-diskimage" "public, max-age=3600"

    echo ""
    echo "DMG published:"
    echo "  Latest:    https://downloads.gilt.novor.dev/${DMG_NAME}"
    echo "  Versioned: https://downloads.gilt.novor.dev/releases/${TAG_NAME}/${VERSIONED_DMG_NAME}"
fi

# Upload delta files if any exist for this version.
# generate_appcast writes deltas into sparkle-archives/ (see update-sparkle-appcast.sh),
# not the repo root, so a "." glob here never matches anything.
DELTA_DIR="sparkle-archives"
DELTA_COUNT=0
for delta in "${DELTA_DIR}/${RELEASE_BASENAME}"*-*.delta; do
    [ -f "$delta" ] || continue
    DELTA_BASE="$(basename "$delta")"
    echo "  → releases/${TAG_NAME}/${DELTA_BASE}"
    r2_upload "$delta" "releases/${TAG_NAME}/${DELTA_BASE}" \
        "application/octet-stream" "public, max-age=31536000, immutable"
    DELTA_COUNT=$((DELTA_COUNT + 1))
done
if [ "$DELTA_COUNT" -gt 0 ]; then
    echo "Uploaded ${DELTA_COUNT} delta file(s)."
fi

if [ ! -f "appcast.xml" ]; then
    echo "ERROR: appcast.xml not found."
    echo "Generate it first:"
    echo "  ./scripts/update-sparkle-appcast.sh"
    exit 1
fi

if [ ! -f "version.json" ]; then
    echo "ERROR: version.json not found."
    exit 1
fi

echo ""
echo "Uploading appcast.xml..."
r2_upload "appcast.xml" "appcast.xml" "application/xml" "public, max-age=300"

echo "Uploading version.json..."
r2_upload "version.json" "version.json" "application/json" "public, max-age=300"

echo ""
echo "Appcast published:"
echo "  https://downloads.gilt.novor.dev/appcast.xml"
echo "Version manifest published:"
echo "  https://downloads.gilt.novor.dev/version.json"
echo ""
echo "Release ${TAG_NAME} published to R2."
