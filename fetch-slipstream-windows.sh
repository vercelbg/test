#!/usr/bin/env bash
# ==============================================================================
# Script Name:    fetch-windows-slipstream.sh
# Description:    Skips Windows cross-compilation by fetching pre-built
#                 binaries and prepping them raw for the release script.
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION & ENVIRONMENT SETUP
# ==============================================================================
ROOT_DIR="$PWD"
DIST_DIR="$ROOT_DIR/dist"
TEMP_DIR="$ROOT_DIR/temp_win"

# ==============================================================================
# SYSTEM RUNTIME HELPERS
# ==============================================================================

log() {
    echo
    echo "======================================"
    echo "$*"
    echo "======================================"
}

run() {
    echo "+ $*"
    "$@"
}

# ==============================================================================
# 1. PREREQUISITES & HOSTMCH DEPENDENCIES
# ==============================================================================
log "1. Installing system dependencies"

sudo apt-get update -y
sudo apt-get install -y curl unzip

mkdir -p "$DIST_DIR"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# ==============================================================================
# 2. FETCH PRE-BUILT ARCHIVES
# ==============================================================================
log "2. Downloading pre-compiled Windows zip files"

# Download AMD64
run curl -L "https://github.com/Mygod/slipstream-rust/releases/download/v0.1.1/slipstream-windows-x86_64.zip" \
    -o "$TEMP_DIR/amd64.zip"

# Download ARM64
run curl -L "https://github.com/Mygod/slipstream-rust/releases/download/v0.1.1/slipstream-windows-arm64.zip" \
    -o "$TEMP_DIR/arm64.zip"

# ==============================================================================
# 3. EXTRACT AND STAGE RAW BINARIES
# ==============================================================================
log "3. Extracting and normalizing Windows raw binaries"

# --- Process AMD64 ---
log "Processing windows-amd64..."
mkdir -p "$TEMP_DIR/ext_amd64"
run unzip -q "$TEMP_DIR/amd64.zip" -d "$TEMP_DIR/ext_amd64"

# Stage Client AMD64
if ls "$TEMP_DIR/ext_amd64"/slipstream-client*.exe >/dev/null 2>&1; then
    mv "$TEMP_DIR/ext_amd64"/slipstream-client*.exe "$DIST_DIR/slipstream-client-windows-amd64.exe"
else
    echo "Warning: Specific client binary name not found, trying fallback matching."
    mv "$TEMP_DIR/ext_amd64"/*client*.exe "$DIST_DIR/slipstream-client-windows-amd64.exe" 2>/dev/null || true
fi

# Stage Server AMD64
if ls "$TEMP_DIR/ext_amd64"/slipstream-server*.exe >/dev/null 2>&1; then
    mv "$TEMP_DIR/ext_amd64"/slipstream-server*.exe "$DIST_DIR/slipstream-server-windows-amd64.exe"
else
    mv "$TEMP_DIR/ext_amd64"/*server*.exe "$DIST_DIR/slipstream-server-windows-amd64.exe" 2>/dev/null || true
fi


# --- Process ARM64 ---
log "Processing windows-arm64..."
mkdir -p "$TEMP_DIR/ext_arm64"
run unzip -q "$TEMP_DIR/arm64.zip" -d "$TEMP_DIR/ext_arm64"

# Stage Client ARM64
if ls "$TEMP_DIR/ext_arm64"/slipstream-client*.exe >/dev/null 2>&1; then
    mv "$TEMP_DIR/ext_arm64"/slipstream-client*.exe "$DIST_DIR/slipstream-client-windows-arm64.exe"
else
    echo "Warning: Specific client binary name not found, trying fallback matching."
    mv "$TEMP_DIR/ext_arm64"/*client*.exe "$DIST_DIR/slipstream-client-windows-arm64.exe" 2>/dev/null || true
fi

# Stage Server ARM64
if ls "$TEMP_DIR/ext_arm64"/slipstream-server*.exe >/dev/null 2>&1; then
    mv "$TEMP_DIR/ext_arm64"/slipstream-server*.exe "$DIST_DIR/slipstream-server-windows-arm64.exe"
else
    mv "$TEMP_DIR/ext_arm64"/*server*.exe "$DIST_DIR/slipstream-server-windows-arm64.exe" 2>/dev/null || true
fi

# Clean up working tree remnants
rm -rf "$TEMP_DIR"

# ==============================================================================
# PIPELINE EXIT CONDITIONS MET SUCCESSFUL
# ==============================================================================
log "FETCH AND EXTRACTION SUCCESS"

echo "Staged Windows Binaries in $DIST_DIR:"
ls -lh "$DIST_DIR"/ | grep "windows" || true
