#!/bin/bash
# build-app.sh — Builds Jack as a proper .app bundle
# Usage:
#   ./scripts/build-app.sh              → debug build (faster, for development)
#   ./scripts/build-app.sh release      → release build (optimized, for distribution)
#
# Version is read from VERSION file (semver). Build number is the git commit count.
# Override with:
#   VERSION=1.2.0 BUILD=42 ./scripts/build-app.sh release
#   APP_NAME=Clipboardy BUNDLE_ID=com.example.clipboardy ./scripts/build-app.sh release

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

CONFIG="${1:-debug}"
TARGET_NAME="${TARGET_NAME:-Gilt}"
SOURCE_TARGET_DIR="${SOURCE_TARGET_DIR:-Gilt}"
APP_NAME="${APP_NAME:-Jack}"
BUNDLE_ID="${BUNDLE_ID:-com.praisedev.gilt}"
TEAM_ID="${TEAM_ID:-XLAM8T9NYQ}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-Jack.entitlements}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Praise Adesokan (${TEAM_ID})}"
ENABLE_HARDENED_RUNTIME="${ENABLE_HARDENED_RUNTIME:-1}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://downloads.gilt.novor.dev/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-PzQpVDhl8XgrCCKucwJcbf1e0p1ZEAa92mCdVOZ/y2M=}"
SPARKLE_FRAMEWORK_SOURCE="${SPARKLE_FRAMEWORK_SOURCE:-.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework}"
# LLM.swift ships llama.cpp as a binary xcframework. Ship the macOS slice with
# the .app so `@rpath/llama.framework/...` resolves at launch. Without this the
# app crashes with `Library not loaded: @rpath/llama.framework/...` on launch.
LLAMA_FRAMEWORK_SOURCE="${LLAMA_FRAMEWORK_SOURCE:-.build/checkouts/LLM.swift/llama.cpp/llama.xcframework/macos-arm64_x86_64/llama.framework}"
# SwiftOGG ships libogg/libopus as dynamic xcframeworks (YbridOgg/YbridOpus) for
# audio-file transcription. The app links them via @rpath, so a packaged build
# missing them crashes at launch — guard them like llama.framework below.
YBRID_OGG_FRAMEWORK_SOURCE="${YBRID_OGG_FRAMEWORK_SOURCE:-.build/artifacts/ogg-swift/YbridOgg/YbridOgg.xcframework/macos-arm64_x86_64/YbridOgg.framework}"
YBRID_OPUS_FRAMEWORK_SOURCE="${YBRID_OPUS_FRAMEWORK_SOURCE:-.build/artifacts/opus-swift/YbridOpus/YbridOpus.xcframework/macos-arm64_x86_64/YbridOpus.framework}"
APP_DIR="$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
RESOURCE_BUNDLE_NAME="${TARGET_NAME}_${TARGET_NAME}.bundle"
RESOURCE_BUNDLE_DEST="$RESOURCES/$RESOURCE_BUNDLE_NAME"

require_path() {
    local path="$1"
    local message="$2"

    if [ ! -e "$path" ]; then
        echo "ERROR: $message"
        exit 1
    fi
}

# --- Version Management ---
# Marketing version from VERSION file (e.g., "1.0.0")
if [ -z "${VERSION:-}" ]; then
    if [ -f VERSION ]; then
        VERSION=$(cat VERSION | tr -d '[:space:]')
    else
        VERSION="1.0.0"
    fi
fi

# Build number from git commit count (auto-incrementing)
if [ -z "${BUILD:-}" ]; then
    BUILD=$(git rev-list --count HEAD 2>/dev/null || echo "1")
fi

# Short commit hash for identification
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

echo "Building $APP_NAME v${VERSION} (${BUILD}) [$CONFIG] @ $COMMIT..."
swift build -c "$CONFIG"

# Locate the built binary
BINARY=".build/$CONFIG/$TARGET_NAME"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "Assembling $APP_DIR..."

# Clean previous bundle
rm -rf "$APP_DIR"

# Create bundle structure
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"
mkdir -p "$FRAMEWORKS"

# Copy binary
cp "$BINARY" "$MACOS/$APP_NAME"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/$APP_NAME" 2>/dev/null || true

# --- jack-transcribe-stream helper (streaming dictation engine) ---
# The Parakeet Unified streaming engine runs inference in this subprocess.
# It lives in Contents/MacOS beside the main executable (Apple's required
# location for auxiliary binaries — notarization rejects executables in
# Resources). Build it on demand; fail loudly rather than shipping an app
# whose streaming model silently can't start.
HELPER_SOURCE="Vendor/jack-transcribe-stream/jack-transcribe-stream"
if [ ! -f "$HELPER_SOURCE" ]; then
    echo "Building jack-transcribe-stream helper..."
    ./scripts/build-transcribe-helper.sh
fi
require_path \
    "$HELPER_SOURCE" \
    "Missing jack-transcribe-stream helper. Run scripts/build-transcribe-helper.sh before packaging."
cp "$HELPER_SOURCE" "$MACOS/jack-transcribe-stream"

# SwiftPM resource bundles live beside the built binary, and generated
# `Bundle.module` accessors look for them at the app bundle root.
RESOURCE_BUNDLE_SOURCE=$(find ".build" -type d -name "$RESOURCE_BUNDLE_NAME" -print -quit 2>/dev/null || true)
if [ -n "$RESOURCE_BUNDLE_SOURCE" ] && [ -d "$RESOURCE_BUNDLE_SOURCE" ]; then
    echo "Embedding ${RESOURCE_BUNDLE_NAME}..."
    rm -rf "$RESOURCE_BUNDLE_DEST"
    ditto "$RESOURCE_BUNDLE_SOURCE" "$RESOURCE_BUNDLE_DEST"
fi

# Direct-download builds depend on the SwiftPM resource bundle existing inside the
# packaged app. If this bundle is missing, launch-time resource lookups can crash
# before the app shows any UI, so fail the release build loudly here instead.
require_path \
    "$RESOURCE_BUNDLE_DEST" \
    "Missing ${RESOURCE_BUNDLE_NAME} in ${APP_DIR}. SwiftPM resources must be embedded before shipping."

# Copy loose resources needed by the app bundle itself (icon, wallpapers, preview media).
if [ -d "Sources/$SOURCE_TARGET_DIR/Resources" ]; then
    cp -R "Sources/$SOURCE_TARGET_DIR/Resources/." "$RESOURCES/"
fi

# --- macOS 26 Liquid Glass app icon (Icon Composer) ---
# AppIcon.icon is a layered Icon Composer bundle. actool compiles it to Assets.car, which
# macOS 26+ uses (via CFBundleIconName) to render the icon with the Liquid Glass material
# inside the system squircle. We compile into a temp dir and copy ONLY Assets.car: the loose
# AppIcon.icns copied above stays the pre-26 fallback (CFBundleIconFile), where the system
# does NOT add its own rounded mask and the established flat artwork is already correct.
# actool also emits its own AppIcon.icns (a flattened glass render) — we deliberately ignore
# it so the legacy icns is never clobbered.
ICON_SOURCE="$PROJECT_ROOT/AppIcon.icon"
if [ -d "$ICON_SOURCE" ] && command -v xcrun >/dev/null 2>&1 && xcrun --find actool >/dev/null 2>&1; then
    echo "Compiling Liquid Glass icon (Assets.car) from AppIcon.icon..."
    ICON_TMP="$(mktemp -d)"
    if xcrun actool "$ICON_SOURCE" \
        --compile "$ICON_TMP" \
        --app-icon AppIcon \
        --include-all-app-icons \
        --enable-on-demand-resources NO \
        --development-region en \
        --target-device mac \
        --minimum-deployment-target 26.0 \
        --platform macosx \
        --output-partial-info-plist "$ICON_TMP/icon-partial.plist" \
        --output-format human-readable-text >/dev/null 2>&1 && [ -f "$ICON_TMP/Assets.car" ]; then
        cp "$ICON_TMP/Assets.car" "$RESOURCES/Assets.car"
        echo "  Embedded $RESOURCES/Assets.car"
    else
        echo "  WARNING: actool failed to produce Assets.car — macOS 26 will fall back to the flat .icns."
    fi
    rm -rf "$ICON_TMP"
else
    echo "WARNING: AppIcon.icon or actool not found — shipping flat .icns only (no Liquid Glass icon for macOS 26)."
fi

if [ -d "$SPARKLE_FRAMEWORK_SOURCE" ]; then
    echo "Embedding Sparkle.framework..."
    rm -rf "$FRAMEWORKS/Sparkle.framework"
    ditto "$SPARKLE_FRAMEWORK_SOURCE" "$FRAMEWORKS/Sparkle.framework"
fi

# llama.cpp framework for local LLM inference (Qwen via LLM.swift)
if [ -d "$LLAMA_FRAMEWORK_SOURCE" ]; then
    echo "Embedding llama.framework..."
    rm -rf "$FRAMEWORKS/llama.framework"
    ditto "$LLAMA_FRAMEWORK_SOURCE" "$FRAMEWORKS/llama.framework"
else
    # Same spirit as the Gilt_Gilt.bundle guardrail: never let a shippable
    # build go out missing a framework the app loads at runtime.
    if [ "$CONFIG" = "release" ]; then
        echo "ERROR: llama.framework not found at $LLAMA_FRAMEWORK_SOURCE"
        echo "       Release builds must embed llama.framework — meeting summary/Q&A would crash at launch."
        exit 1
    fi
    echo "WARNING: llama.framework not found at $LLAMA_FRAMEWORK_SOURCE"
    echo "         Meeting summary/Q&A features will crash at launch."
fi

# YbridOgg / YbridOpus frameworks (Ogg-Opus voice-note transcription via
# SwiftOGG). Dynamically linked, so a missing one crashes the whole app at
# launch — same guardrail as llama.framework.
for ybrid_entry in "YbridOgg=$YBRID_OGG_FRAMEWORK_SOURCE" "YbridOpus=$YBRID_OPUS_FRAMEWORK_SOURCE"; do
    ybrid_name="${ybrid_entry%%=*}"
    ybrid_src="${ybrid_entry#*=}"
    if [ -d "$ybrid_src" ]; then
        echo "Embedding $ybrid_name.framework..."
        rm -rf "$FRAMEWORKS/$ybrid_name.framework"
        ditto "$ybrid_src" "$FRAMEWORKS/$ybrid_name.framework"
    elif [ "$CONFIG" = "release" ]; then
        echo "ERROR: $ybrid_name.framework not found at $ybrid_src"
        echo "       Release builds must embed $ybrid_name.framework — the app links it at launch and crashes without it."
        exit 1
    else
        echo "WARNING: $ybrid_name.framework not found at $ybrid_src"
        echo "         Audio-file transcription will crash at launch without it."
    fi
done

# Create Info.plist
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025-2026 Praise Adesokan. All rights reserved.</string>
    <key>SUEnableDownloaderService</key>
    <true/>
    <key>SUEnableInstallerLauncherService</key>
    <true/>
    <key>SUVerifyUpdateBeforeExtraction</key>
    <true/>
    <key>SUFeedURL</key>
    <string>${SPARKLE_FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_ED_KEY}</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Jack needs microphone access to create local meeting notes from your audio.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Jack briefly reads the frontmost window when you start a dictation so it can spell on-screen names, code symbols, and jargon correctly. Capture happens entirely on your Mac and is never sent anywhere.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>Jack adds reminders you create to Apple Reminders so they sync to your iPhone and iPad and alert you even when Jack is closed.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Jack uses this to control Spotify playback when you ask it to with your voice.</string>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.praisedev.gilt.strip-drag-item</string>
            <key>UTTypeDescription</key>
            <string>Jack Internal Drag Item</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict/>
        </dict>
    </array>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Send to ${APP_NAME}</string>
            </dict>
            <key>NSMessage</key>
            <string>sendToJack</string>
            <key>NSPortName</key>
            <string>${APP_NAME}</string>
            <key>NSSendTypes</key>
            <array>
                <string>NSStringPboardType</string>
                <string>public.utf8-plain-text</string>
                <string>public.plain-text</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Developer ID distribution needs hardened runtime, a secure timestamp, and
# real entitlements so notarization succeeds later. Sign inside-out: nested
# Sparkle helpers first (SPM ships them adhoc-signed), then frameworks, then
# the main executable, then the bundle. A single `codesign --deep` on the app
# leaves Sparkle.framework without a secure timestamp and fails verification.
RUNTIME_ARGS=()
if [ "$ENABLE_HARDENED_RUNTIME" = "1" ]; then
    RUNTIME_ARGS=(--options runtime)
fi

sign_path() {
    local target="$1"
    shift
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "${RUNTIME_ARGS[@]}" "$@" "$target"
}

sign_sparkle_framework() {
    local sparkle_framework="$1"
    [ -d "$sparkle_framework" ] || return 0

    local sparkle_root="$sparkle_framework/Versions/B"
    if [ ! -d "$sparkle_root" ]; then
        sparkle_root="$sparkle_framework/Versions/Current"
    fi

    echo "Signing Sparkle.framework (nested helpers first)..."
    local nested
    for nested in \
        "$sparkle_root/Autoupdate" \
        "$sparkle_root/XPCServices/Downloader.xpc" \
        "$sparkle_root/XPCServices/Installer.xpc" \
        "$sparkle_root/Updater.app"
    do
        if [ -e "$nested" ]; then
            sign_path "$nested"
        fi
    done
    sign_path "$sparkle_framework"
}

sign_embedded_frameworks() {
    if [ -d "$FRAMEWORKS/Sparkle.framework" ]; then
        sign_sparkle_framework "$FRAMEWORKS/Sparkle.framework"
    fi

    local framework_name
    for framework_name in llama YbridOgg YbridOpus; do
        local framework_path="$FRAMEWORKS/${framework_name}.framework"
        if [ -d "$framework_path" ]; then
            echo "Signing ${framework_name}.framework..."
            sign_path "$framework_path"
        fi
    done
}

ENTITLEMENTS_ARGS=()
if [ -f "$ENTITLEMENTS_PATH" ]; then
    ENTITLEMENTS_ARGS=(--entitlements "$ENTITLEMENTS_PATH")
fi

echo "Signing embedded frameworks..."
sign_embedded_frameworks

echo "Signing jack-transcribe-stream helper..."
sign_path "$MACOS/jack-transcribe-stream"

echo "Signing ${APP_NAME} executable..."
sign_path "$MACOS/$APP_NAME" "${ENTITLEMENTS_ARGS[@]}"

echo "Signing ${APP_DIR} with ${SIGN_IDENTITY}..."
sign_path "$APP_DIR" "${ENTITLEMENTS_ARGS[@]}"

# Upload debug symbols to Sentry so crash/hang reports show symbolicated stack traces.
# Requires SENTRY_AUTH_TOKEN env var (create at https://sentry.io/settings/auth-tokens/).
# Skipped silently if sentry-cli is not installed or token is not set.
SENTRY_ORG="${SENTRY_ORG:-novor}"
SENTRY_PROJECT="${SENTRY_PROJECT:-apple-macos}"
if command -v sentry-cli &>/dev/null && [ -n "${SENTRY_AUTH_TOKEN:-}" ]; then
    echo "Uploading debug symbols to Sentry..."
    sentry-cli debug-files upload \
        --org "$SENTRY_ORG" \
        --project "$SENTRY_PROJECT" \
        --include-sources \
        ".build/$CONFIG/" 2>&1 | tail -3
    echo "dSYM upload complete."
else
    echo "Skipping Sentry dSYM upload (set SENTRY_AUTH_TOKEN to enable)."
fi

echo ""
echo "Done! $APP_NAME.app v${VERSION} (${BUILD}) @ $COMMIT"
echo ""
echo "First time setup:"
echo "  1. Run:  open $APP_DIR"
echo "  2. Go to System Settings → Privacy & Security → Accessibility"
echo "  3. Add and enable '$APP_NAME'"
echo "  4. Double-click paste will now work!"
echo ""
echo "Quick launch:  open $APP_DIR"
