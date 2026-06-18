#!/usr/bin/env bash
# ==============================================================================
# Script Name:    release.sh
# Description:    Stage 2 automated asset packaging. Generates clean, separate
#                 checksum manifests for raw binaries and compressed archives.
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION & ENVIRONMENT SETUP
# ==============================================================================
ROOT_DIR="$PWD"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$ROOT_DIR/release"
CHECKSUM_FILE="$RELEASE_DIR/checksum.txt"

# ==============================================================================
# SYSTEM RUNTIME HELPERS
# ==============================================================================

log() {
    echo
    echo "======================================"
    echo "$*"
    echo "======================================"
}

# ==============================================================================
# 1. PREREQUISITES & HOSTMCH DEPENDENCIES
# ==============================================================================
log "1. Installing release runner dependencies"

sudo apt-get update -y
sudo apt-get install -y zip tar coreutils

# Double check that commands are available in path execution environments
for cmd in sha256sum zip tar; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: Required system tool '$cmd' is missing." >&2
        exit 1
    fi
done

# Initialize fresh directory trees
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

if [ ! -d "$DIST_DIR" ] || [ -z "$(ls -A "$DIST_DIR" 2>/dev/null)" ]; then
    log "ERROR: The directory '$DIST_DIR' is missing or empty. Nothing to release."
    exit 1
fi

# Arrays to keep track of assets sequentially for structured hashing
RAW_BINARIES=()
ARCHIVES=()

# ==============================================================================
# 2. COMPRESSION AND ARCHIVING ENGINE
# ==============================================================================
log "2. Packaging raw binaries from dist/ into release/"

cd "$DIST_DIR"

for asset in *; do
    # Safeguard against accidental loop matches
    [ -f "$asset" ] || continue

    log "Processing: $asset"
    RAW_BINARIES+=("$asset")

    # Determine packaging standard depending on OS keyword signature
    if [[ "$asset" == *"windows"* ]]; then
        archive_name="${asset%.exe}.zip"
        zip -q "$RELEASE_DIR/$archive_name" "$asset"
    else
        archive_name="${asset}.tar.gz"
        tar -czf "$RELEASE_DIR/$archive_name" "$asset"
    fi

    ARCHIVES+=("$archive_name")
done

# ==============================================================================
# 3. SEPARATED CHECKSUM MANIFEST GENERATION
# ==============================================================================
log "3. Compiling structured SHA-256 validation manifest"

# Create/Clear file
: > "$CHECKSUM_FILE"

# --- PART A: COMPRESSED ARCHIVES ---
echo "# archive" >> "$CHECKSUM_FILE"
cd "$RELEASE_DIR"
for archive in "${ARCHIVES[@]}"; do
    sha256sum "$archive" >> "$CHECKSUM_FILE"
done

echo "" >> "$CHECKSUM_FILE"

# --- PART B: RAW BINARIES ---
echo "# raw binary" >> "$CHECKSUM_FILE"
cd "$DIST_DIR"
for binary in "${RAW_BINARIES[@]}"; do
    # Relative path output matching standard format
    sha256sum "$binary" >> "$CHECKSUM_FILE"
done

# ==============================================================================
# PIPELINE EXIT CONDITIONS MET SUCCESSFUL
# ==============================================================================
log "STAGING AND PACKAGING MET SUCCESSFUL"

echo "Final Release Folder Contents:"
ls -lh "$RELEASE_DIR"

echo -e "\n--- Generated Manifest Content ($CHECKSUM_FILE) ---"
cat "$CHECKSUM_FILE"
