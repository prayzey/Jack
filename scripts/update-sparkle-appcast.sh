#!/bin/bash
# update-sparkle-appcast.sh — Regenerates appcast.xml for Sparkle updates.
# Run this after publishing the release DMG to R2.
#
# Delta updates: Previous DMGs are kept in sparkle-archives/ so generate_appcast
# can create binary delta patches between versions. Users upgrading from a recent
# version download only the diff (~2-5MB) instead of the full DMG (~160MB).
# If no previous archives exist, only the full update is offered (safe fallback).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG_NAME="v${VERSION}"
APP_NAME="${APP_NAME:-Jack}"
DMG_NAME="${DMG_NAME:-${APP_NAME}.dmg}"
RELEASE_BASENAME="${RELEASE_BASENAME:-Gilt}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-prayzey-gilt}"
APPCAST_URL="${APPCAST_URL:-https://downloads.gilt.novor.dev/appcast.xml}"
DOWNLOAD_BASE="${DOWNLOAD_BASE:-https://downloads.gilt.novor.dev}"
WEBSITE_URL="${WEBSITE_URL:-https://gilt.novor.dev}"
GENERATE_APPCAST="${GENERATE_APPCAST:-.build/artifacts/sparkle/Sparkle/bin/generate_appcast}"
ARCHIVES_DIR="sparkle-archives"

# How many previous versions to keep for delta generation.
# Sparkle falls back to full DMG for versions older than this.
MAX_OLD_VERSIONS="${MAX_OLD_VERSIONS:-3}"

if [ ! -f "$DMG_NAME" ]; then
    echo "ERROR: ${DMG_NAME} not found."
    echo "Build and notarize the DMG first."
    exit 1
fi

# --- Set up archives directory with old + new DMGs ---
mkdir -p "$ARCHIVES_DIR"

# Copy the new DMG into the archives folder (versioned filename so generate_appcast
# can distinguish versions by scanning the embedded app bundles).
cp "$DMG_NAME" "$ARCHIVES_DIR/${RELEASE_BASENAME}-${VERSION}.dmg"

# Copy existing appcast if present (generate_appcast merges with it)
if [ -f appcast.xml ]; then
    cp appcast.xml "$ARCHIVES_DIR/appcast.xml"
fi

# --- Generate appcast + deltas ---
# generate_appcast scans all DMGs in the folder, extracts the app bundles,
# compares versions, and automatically creates .delta patch files between them.
# Delta entries are added to the appcast with <sparkle:deltas> elements.
"$GENERATE_APPCAST" \
    --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "${DOWNLOAD_BASE}/releases/${TAG_NAME}/" \
    --full-release-notes-url "${WEBSITE_URL}/releases/${TAG_NAME}" \
    --link "$WEBSITE_URL" \
    --maximum-versions "$MAX_OLD_VERSIONS" \
    -o "$ARCHIVES_DIR/appcast.xml" \
    "$ARCHIVES_DIR"

cp "$ARCHIVES_DIR/appcast.xml" appcast.xml

# --- Upload any generated delta files to R2 ---
DELTA_COUNT=0
for delta_file in "$ARCHIVES_DIR"/*.delta; do
    [ -f "$delta_file" ] || continue
    DELTA_COUNT=$((DELTA_COUNT + 1))
    delta_basename="$(basename "$delta_file")"
    echo "Uploading delta: $delta_basename"
    aws s3 cp "$delta_file" "s3://gilt-downloads/releases/${TAG_NAME}/${delta_basename}" \
        --profile r2 \
        --endpoint-url "https://53efd4156db034899e5cf7b54238b7a1.r2.cloudflarestorage.com" \
        --content-type "application/octet-stream" \
        --cache-control "public, max-age=31536000, immutable"
done

if [ "$DELTA_COUNT" -gt 0 ]; then
    echo "Uploaded $DELTA_COUNT delta file(s) to R2."
else
    echo "No delta files generated (first release or no previous archives)."
fi

# --- Prune old archives beyond MAX_OLD_VERSIONS ---
# Keep only the N most recent DMGs (by modification time) to avoid unbounded growth.
ARCHIVE_COUNT=$(find "$ARCHIVES_DIR" -name "*.dmg" | wc -l | tr -d ' ')
if [ "$ARCHIVE_COUNT" -gt "$MAX_OLD_VERSIONS" ]; then
    PRUNE_COUNT=$((ARCHIVE_COUNT - MAX_OLD_VERSIONS))
    echo "Pruning $PRUNE_COUNT old archive(s)..."
    find "$ARCHIVES_DIR" -name "*.dmg" -print0 | xargs -0 ls -t | tail -n "$PRUNE_COUNT" | xargs rm -f
fi

# Clean up old_updates directory that generate_appcast may create
rm -rf "$ARCHIVES_DIR/old_updates"

echo ""
echo "Updated appcast.xml for ${TAG_NAME}"
echo "Feed URL:"
echo "  ${APPCAST_URL}"
echo "Enclosure URL:"
echo "  ${DOWNLOAD_BASE}/releases/${TAG_NAME}/${DMG_NAME}"
echo "Release notes URL:"
echo "  ${WEBSITE_URL}/releases/${TAG_NAME}"
if [ "$DELTA_COUNT" -gt 0 ]; then
    echo "Delta updates: $DELTA_COUNT patch file(s) uploaded"
fi
