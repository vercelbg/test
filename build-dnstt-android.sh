#!/usr/bin/env bash
# ==============================================================================
# Script Name:    build-android-dnstt.sh
# Description:    Automates multi-architecture cross-compilation of DNSTT
#                 for Android platforms (ARM64, ARMv7, 386, AMD64) using Go + NDK.
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION & ENVIRONMENT SETUP
# ==============================================================================
API=21
NDK_VERSION="r27d"
DNSTT_REPO="https://www.bamsoftware.com/git/dnstt.git"

ROOT_DIR="$PWD"
PROJECT_DIR="$ROOT_DIR/dnstt"
DIST_DIR="$ROOT_DIR/dist"
NDK_DIR="$ROOT_DIR/android-ndk-$NDK_VERSION"

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
# 1. TOOLCHAIN & PATH ACQUISITION (ANDROID NDK)
# ==============================================================================
log "1. Installing host dependencies and NDK Toolchain"

sudo apt-get update -y
sudo apt-get install -y build-essential git wget unzip curl

if [ ! -d "$NDK_DIR" ]; then
    log "Downloading Android NDK $NDK_VERSION..."
    run wget \
        --progress=bar:force:noscroll \
        "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip" \
        -O "$ROOT_DIR/ndk.zip"

    run unzip -q "$ROOT_DIR/ndk.zip" -d "$ROOT_DIR"
    rm -f "$ROOT_DIR/ndk.zip"
fi

TOOLCHAIN_BIN="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin"
export PATH="$TOOLCHAIN_BIN:$PATH"

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
# CORE ANDROID ARCHITECTURE CROSS-COMPILATION ENGINE
# ==============================================================================
build_target() {
    local goarch="$1"
    local compiler_binary="$2"
    local label="$3"

    log "BUILDING ANDROID ARCHITECTURE TARGET: $label"

    # Environment Deployment Target Flags Configuration
    export GOOS=android
    export GOARCH="$goarch"
    export CGO_ENABLED=1
    export CC="$TOOLCHAIN_BIN/$compiler_binary"

    # Normalize architecture nomenclature to release standards
    local final_arch
    case "$label" in
        "arm64"|"arm64-v8a")   final_arch="arm64" ;;
        "armv7"|"armeabi-v7a") final_arch="armv7" ;;
        "x86"|"386")           final_arch="386"   ;;
        "x86_64"|"amd64")      final_arch="amd64" ;;
        *)                     final_arch="$label" ;;
    esac

    # --------------------------------------------------------------------------
    # Client Compilation Profile
    # --------------------------------------------------------------------------
    log "Go building client profile ($final_arch)"
    (
        cd "$PROJECT_DIR/dnstt-client"
        run go build -trimpath -ldflags="-s -w" \
            -o "$PROJECT_DIR/target-client"
    )

    # --------------------------------------------------------------------------
    # Server Compilation Profile
    # --------------------------------------------------------------------------
    log "Go building server profile ($final_arch)"
    (
        cd "$PROJECT_DIR/dnstt-server"
        run go build -trimpath -ldflags="-s -w" \
            -o "$PROJECT_DIR/target-server"
    )

    log "Verify Binary Health Structures ($final_arch)"
    file "$PROJECT_DIR/target-client" || true
    file "$PROJECT_DIR/target-server" || true
    du -h "$PROJECT_DIR/target-client" "$PROJECT_DIR/target-server" || true

    # ==============================================================================
    # PIPELINE STAGE 1: ORGANIZE RAW BINARIES FOR MONOLITHIC RELEASE STORAGE
    # ==============================================================================
    mkdir -p "$DIST_DIR"

    log "Staging clean raw artifacts for android-${final_arch}"

    mv "$PROJECT_DIR/target-client" "$DIST_DIR/dnstt-client-android-${final_arch}"
    mv "$PROJECT_DIR/target-server" "$DIST_DIR/dnstt-server-android-${final_arch}"

    chmod +x "$DIST_DIR/dnstt-client-android-${final_arch}"
    chmod +x "$DIST_DIR/dnstt-server-android-${final_arch}"
}

# ==============================================================================
# PIPELINE ARCHITECTURE RUN SUBMISSIONS
# ==============================================================================

# 1. ARM 64-bit Run
build_target "arm64" "aarch64-linux-android${API}-clang" "arm64"

# 2. ARM 32-bit Run
build_target "arm" "armv7a-linux-androideabi${API}-clang" "armv7"

# 3. Intel x86 32-bit Run
build_target "386" "i686-linux-android${API}-clang" "x86"

# 4. Intel x86_64 64-bit Run
build_target "amd64" "x86_64-linux-android${API}-clang" "x86_64"

# ==============================================================================
# PIPELINE EXIT CONDITIONS MET SUCCESSFUL
# ==============================================================================
log "BUILD SUCCESS"

echo "Staged Raw Binaries in $DIST_DIR:"
ls -lh "$DIST_DIR"
