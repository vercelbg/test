#!/usr/bin/env bash
# ==============================================================================
# Script Name:    build-windows-dnstt.sh
# Description:    Automates multi-architecture cross-compilation of DNSTT
#                 for Windows platforms (AMD64 & ARM64) using Go.
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION & ENVIRONMENT SETUP
# ==============================================================================
DNSTT_REPO="https://www.bamsoftware.com/git/dnstt.git"
ROOT_DIR="$PWD"
PROJECT_DIR="$ROOT_DIR/dnstt"
DIST_DIR="$ROOT_DIR/dist"

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
sudo apt-get install -y git wget curl

if ! command -v go &>/dev/null; then
    log "ERROR: Go toolchain not found. Please install Go before running this script."
    exit 1
fi

if [ -d "$PROJECT_DIR" ]; then
    log "Cleaning existing workspace directory..."
    rm -rf "$PROJECT_DIR"
fi

# ==============================================================================
# 2. WORKSPACE ACQUISITION
# ==============================================================================
log "2. Clone project working tree"
run git clone "$DNSTT_REPO" "$PROJECT_DIR"

# ==============================================================================
# CORE WINDOWS ARCHITECTURE CROSS-COMPILATION ENGINE
# ==============================================================================
build_target() {
    local goarch="$1"
    local label="$2"

    log "BUILDING WINDOWS ARCHITECTURE TARGET: $label"

    # Environment Deployment Target Flags Configuration
    export GOOS=windows
    export GOARCH="$goarch"
    export CGO_ENABLED=0

    # Normalize Windows architecture nomenclature
    local final_arch
    if [ "$label" = "amd64" ] || [ "$label" = "x86_64" ]; then
        final_arch="amd64"
    elif [ "$label" = "arm64" ] || [ "$label" = "aarch64" ]; then
        final_arch="arm64"
    else
        final_arch="$label"
    fi

    # --------------------------------------------------------------------------
    # Client Compilation Profile
    # --------------------------------------------------------------------------
    log "Go building client profile ($final_arch)"
    (
        cd "$PROJECT_DIR/dnstt-client"
        run go build -trimpath -ldflags="-s -w -buildid=" \
            -o "$PROJECT_DIR/target-client.exe"
    )

    # --------------------------------------------------------------------------
    # Server Compilation Profile
    # --------------------------------------------------------------------------
    log "Go building server profile ($final_arch)"
    (
        cd "$PROJECT_DIR/dnstt-server"
        run go build -trimpath -ldflags="-s -w -buildid=" \
            -o "$PROJECT_DIR/target-server.exe"
    )

    log "Verify Binary Health Structures ($final_arch)"
    file "$PROJECT_DIR/target-client.exe" || true
    file "$PROJECT_DIR/target-server.exe" || true
    du -h "$PROJECT_DIR/target-client.exe" "$PROJECT_DIR/target-server.exe" || true

    # ==============================================================================
    # PIPELINE STAGE 1: ORGANIZE RAW BINARIES FOR MONOLITHIC RELEASE STORAGE
    # ==============================================================================
    mkdir -p "$DIST_DIR"

    log "Staging clean raw artifacts for windows-${final_arch}"

    mv "$PROJECT_DIR/target-client.exe" "$DIST_DIR/dnstt-client-windows-${final_arch}.exe"
    mv "$PROJECT_DIR/target-server.exe" "$DIST_DIR/dnstt-server-windows-${final_arch}.exe"

    chmod +x "$DIST_DIR/dnstt-client-windows-${final_arch}.exe"
    chmod +x "$DIST_DIR/dnstt-server-windows-${final_arch}.exe"
}

# ==============================================================================
# PIPELINE ARCHITECTURE RUN SUBMISSIONS
# ==============================================================================

# 1. Windows AMD64 Run (Most Common)
build_target "amd64" "amd64"

# 2. Windows ARM64 Run
build_target "arm64" "arm64"

# ==============================================================================
# PIPELINE EXIT CONDITIONS MET SUCCESSFUL
# ==============================================================================
log "BUILD SUCCESS"

echo "Staged Raw Binaries in $DIST_DIR:"
ls -lh "$DIST_DIR"
