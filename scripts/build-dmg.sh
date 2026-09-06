#!/bin/bash
# build-dmg.sh — Creates a branded DMG installer for Jack
# Usage:
#   ./scripts/build-dmg.sh          → builds app (release) then creates DMG
#   ./scripts/build-dmg.sh debug    → builds app (debug) then creates DMG
#   ./scripts/build-dmg.sh release  → builds app (release) then creates DMG
#
# Prerequisites: Jack.app must exist (runs scripts/build-app.sh automatically if missing)
# No external dependencies — uses only macOS built-in tools (hdiutil, osascript, sips)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

CONFIG="${1:-release}"
TARGET_NAME="${TARGET_NAME:-Gilt}"
SOURCE_TARGET_DIR="${SOURCE_TARGET_DIR:-Gilt}"
APP_NAME="${APP_NAME:-Jack}"
DMG_NAME="${DMG_NAME:-${APP_NAME}}"
DMG_STEM="${DMG_NAME%.dmg}"
DMG_FINAL="${DMG_STEM}.dmg"
DMG_TEMP="${DMG_STEM}-temp.dmg"
VOLUME_NAME="$APP_NAME"
APP_DIR="${APP_NAME}.app"
# Keep the installer artwork as a dedicated resource so DMG previews and
# release builds always use the same background image.
BG_IMAGE="Sources/${SOURCE_TARGET_DIR}/Resources/InstallerBackground.png"
ICON_IMAGE="Sources/${SOURCE_TARGET_DIR}/Resources/AppIcon.png"
ICON_ICNS="Sources/${SOURCE_TARGET_DIR}/Resources/AppIcon.icns"

# DMG window dimensions (matches the preview)
WIN_WIDTH=660
WIN_HEIGHT=440
ICON_SIZE=128
TEXT_SIZE=13

# Icon positions (centered in window)
APP_X=175
APP_Y=220
APPS_X=485
APPS_Y=220

if [ -z "${SIGN_DMG:-}" ]; then
    if [ "$CONFIG" = "release" ]; then
        SIGN_DMG=1
    else
        SIGN_DMG=0
    fi
fi

echo "=== Jack DMG Builder ==="
echo ""

# --- Step 1: Always rebuild the app so the DMG can't package stale output ---
echo "Building ${APP_DIR} first..."
"$SCRIPT_DIR/build-app.sh" "$CONFIG"
echo ""

if [ ! -d "$APP_DIR" ]; then
    echo "ERROR: ${APP_DIR} not found. Run ./scripts/build-app.sh first."
    exit 1
fi

# --- Step 2: Clean previous DMG ---
rm -f "$DMG_FINAL" "$DMG_TEMP"

# --- Step 3: Calculate DMG size ---
APP_SIZE_KB=$(du -sk "$APP_DIR" | cut -f1)
# Add 20MB overhead for background, layout, filesystem
DMG_SIZE_KB=$(( APP_SIZE_KB + 20480 ))
echo "App size: ${APP_SIZE_KB}KB, DMG size: ${DMG_SIZE_KB}KB"

# --- Step 4: Detach any existing Jack volumes to avoid name collisions ---
if [ -d "/Volumes/${VOLUME_NAME}" ]; then
    echo "Detaching existing /Volumes/${VOLUME_NAME}..."
    hdiutil detach "/Volumes/${VOLUME_NAME}" -quiet 2>/dev/null || \
        hdiutil detach "/Volumes/${VOLUME_NAME}" -force -quiet 2>/dev/null || true
    sleep 1
fi

# --- Step 5: Create writable DMG ---
echo "Creating temporary DMG..."
hdiutil create \
    -srcfolder "$APP_DIR" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "${DMG_SIZE_KB}k" \
    "$DMG_TEMP" \
    > /dev/null

# --- Step 6: Mount the DMG ---
echo "Mounting DMG..."
MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TEMP")
DEVICE=$(echo "$MOUNT_OUTPUT" | grep '/dev/disk' | head -1 | awk '{print $1}')
MOUNT_POINT="/Volumes/${VOLUME_NAME}"

if [ ! -d "$MOUNT_POINT" ]; then
    echo "ERROR: Volume not mounted at $MOUNT_POINT"
    echo "Mount output: $MOUNT_OUTPUT"
    exit 1
fi

echo "Mounted at: $MOUNT_POINT"

# --- Step 6: Add Applications symlink ---
ln -sf /Applications "${MOUNT_POINT}/Applications"

# --- Step 7: Add background image ---
BG_DIR="${MOUNT_POINT}/.background"
mkdir -p "$BG_DIR"

# Prepare a Retina-sized background without distorting the artwork.
# This behaves like fitting a photo into a frame: scale to cover, then center-crop.
BG_TARGET_WIDTH=$(( WIN_WIDTH * 2 ))
BG_TARGET_HEIGHT=$(( WIN_HEIGHT * 2 ))
BG_SOURCE_WIDTH=$(sips -g pixelWidth "$BG_IMAGE" | awk '/pixelWidth:/ {print $2}')
BG_SOURCE_HEIGHT=$(sips -g pixelHeight "$BG_IMAGE" | awk '/pixelHeight:/ {print $2}')

if [ -n "$BG_SOURCE_WIDTH" ] && [ -n "$BG_SOURCE_HEIGHT" ]; then
    if [ $(( BG_SOURCE_WIDTH * BG_TARGET_HEIGHT )) -ge $(( BG_SOURCE_HEIGHT * BG_TARGET_WIDTH )) ]; then
        BG_RESIZE_HEIGHT=$BG_TARGET_HEIGHT
        BG_RESIZE_WIDTH=$(( (BG_SOURCE_WIDTH * BG_TARGET_HEIGHT + BG_SOURCE_HEIGHT - 1) / BG_SOURCE_HEIGHT ))
    else
        BG_RESIZE_WIDTH=$BG_TARGET_WIDTH
        BG_RESIZE_HEIGHT=$(( (BG_SOURCE_HEIGHT * BG_TARGET_WIDTH + BG_SOURCE_WIDTH - 1) / BG_SOURCE_WIDTH ))
    fi

    TEMP_BG=$(mktemp -t gilt-dmg-bg).png
    sips -z "$BG_RESIZE_HEIGHT" "$BG_RESIZE_WIDTH" "$BG_IMAGE" --out "$TEMP_BG" > /dev/null 2>&1 && \
        sips -c "$BG_TARGET_HEIGHT" "$BG_TARGET_WIDTH" "$TEMP_BG" --out "${BG_DIR}/background.png" > /dev/null 2>&1 || \
        cp "$BG_IMAGE" "${BG_DIR}/background.png"
    rm -f "$TEMP_BG"
else
    cp "$BG_IMAGE" "${BG_DIR}/background.png"
fi

echo "Background image installed"

# --- Step 8: Set volume icon ---
if [ -f "$ICON_ICNS" ]; then
    cp "$ICON_ICNS" "${MOUNT_POINT}/.VolumeIcon.icns"
    SetFile -a C "${MOUNT_POINT}" 2>/dev/null || true
    echo "Volume icon set from AppIcon.icns"
elif [ -f "$ICON_IMAGE" ]; then
    # Fallback for local development if the icns file is missing.
    ICONSET_DIR=$(mktemp -d)/Jack.iconset
    mkdir -p "$ICONSET_DIR"
    sips -z 1024 1024 "$ICON_IMAGE" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null 2>&1
    sips -z 512 512 "$ICON_IMAGE" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512 "$ICON_IMAGE" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null 2>&1
    sips -z 256 256 "$ICON_IMAGE" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null 2>&1
    sips -z 256 256 "$ICON_IMAGE" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 128 128 "$ICON_IMAGE" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null 2>&1
    sips -z 64 64 "$ICON_IMAGE" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null 2>&1
    sips -z 32 32 "$ICON_IMAGE" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null 2>&1
    sips -z 32 32 "$ICON_IMAGE" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null 2>&1
    sips -z 16 16 "$ICON_IMAGE" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null 2>&1
    iconutil -c icns "$ICONSET_DIR" -o "${MOUNT_POINT}/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "${MOUNT_POINT}" 2>/dev/null || true
    rm -rf "$(dirname "$ICONSET_DIR")"
    echo "Volume icon set"
fi

# --- Step 9: Configure Finder window with AppleScript ---
echo "Configuring Finder layout..."

# Calculate window position (centered on a 1440px wide screen)
WIN_X=$(( (1440 - WIN_WIDTH) / 2 ))
WIN_Y=200
WIN_R=$(( WIN_X + WIN_WIDTH ))
WIN_B=$(( WIN_Y + WIN_HEIGHT + 38 ))  # +38 for titlebar

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open

        -- Set window properties
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {${WIN_X}, ${WIN_Y}, ${WIN_R}, ${WIN_B}}

        -- Configure icon view options
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to ${ICON_SIZE}
        set text size of viewOptions to ${TEXT_SIZE}
        set label position of viewOptions to bottom
        set background picture of viewOptions to file ".background:background.png"

        -- Position icons
        set position of item "${APP_NAME}.app" of container window to {${APP_X}, ${APP_Y}}
        set position of item "Applications" of container window to {${APPS_X}, ${APPS_Y}}

        close
        open

        -- Brief delay to let Finder apply changes
        delay 2

        close
    end tell
end tell
APPLESCRIPT

echo "Finder layout configured"

# --- Step 10: Hide auxiliary files and finalize ---
# Hide .background, .fseventsd, and .VolumeIcon.icns so they don't show in Finder
SetFile -a V "${MOUNT_POINT}/.background" 2>/dev/null || true
SetFile -a V "${MOUNT_POINT}/.VolumeIcon.icns" 2>/dev/null || true
SetFile -a V "${MOUNT_POINT}/.fseventsd" 2>/dev/null || true

# Also use chflags hidden as a fallback (works on modern macOS)
chflags hidden "${MOUNT_POINT}/.background" 2>/dev/null || true
chflags hidden "${MOUNT_POINT}/.VolumeIcon.icns" 2>/dev/null || true
chflags hidden "${MOUNT_POINT}/.fseventsd" 2>/dev/null || true

# Ensure .DS_Store is written
sync

# --- Step 11: Unmount ---
echo "Unmounting..."
sleep 2
hdiutil detach "$DEVICE" -quiet || hdiutil detach "$DEVICE" -force -quiet

# --- Step 12: Convert to compressed read-only DMG ---
echo "Compressing to final DMG..."
hdiutil convert \
    "$DMG_TEMP" \
    -format ULFO \
    -o "$DMG_FINAL" \
    > /dev/null 2>&1 || \
hdiutil convert \
    "$DMG_TEMP" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_FINAL" \
    > /dev/null

# Clean up temp DMG
rm -f "$DMG_TEMP"

# Show result
FINAL_SIZE=$(du -h "$DMG_FINAL" | cut -f1 | xargs)
echo ""
echo "=== Done! ==="
echo "  DMG:  ${DMG_FINAL}"
echo "  Size: ${FINAL_SIZE}"
echo ""
echo "To test: open ${DMG_FINAL}"
echo "To distribute: upload ${DMG_FINAL} to your website or GitHub Releases"

if [ "${SIGN_DMG}" = "1" ]; then
    TEAM_ID="${TEAM_ID:-XLAM8T9NYQ}"
    SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Praise Adesokan (${TEAM_ID})}"
    echo ""
    echo "Signing DMG with ${SIGN_IDENTITY}..."
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_FINAL"
fi
