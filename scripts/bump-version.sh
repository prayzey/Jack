#!/bin/bash
# bump-version.sh — Updates the VERSION file for a new release.
# Usage:
#   ./scripts/bump-version.sh 1.0.1
#   ./scripts/bump-version.sh patch
#   ./scripts/bump-version.sh minor
#   ./scripts/bump-version.sh major

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION_FILE="VERSION"

if [ ! -f "$VERSION_FILE" ]; then
    echo "ERROR: VERSION file not found."
    exit 1
fi

CURRENT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
INPUT="${1:-}"

if [ -z "$INPUT" ]; then
    echo "ERROR: Pass a semver like 1.0.1 or one of: patch, minor, major"
    exit 1
fi

if [[ ! "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "ERROR: Current VERSION must use semantic versioning like 1.0.0"
    exit 1
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

case "$INPUT" in
    patch)
        NEXT_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
        ;;
    minor)
        NEXT_VERSION="${MAJOR}.$((MINOR + 1)).0"
        ;;
    major)
        NEXT_VERSION="$((MAJOR + 1)).0.0"
        ;;
    *)
        if [[ ! "$INPUT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "ERROR: Version must look like 1.2.3"
            exit 1
        fi
        NEXT_VERSION="$INPUT"
        ;;
esac

printf '%s\n' "$NEXT_VERSION" > "$VERSION_FILE"

# Keep version.json's latestVersion in sync (minimumVersion and the rest stay put).
VERSION_JSON="version.json"
if [ -f "$VERSION_JSON" ]; then
    sed -i '' "s/\"latestVersion\": \"[^\"]*\"/\"latestVersion\": \"${NEXT_VERSION}\"/" "$VERSION_JSON"
fi

echo "Updated VERSION:"
echo "  from: $CURRENT_VERSION"
echo "  to:   $NEXT_VERSION"
