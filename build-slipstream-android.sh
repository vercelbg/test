#!/usr/bin/env bash
# ==============================================================================
# Script Name:    build-android-slipstream.sh
# Description:    Automates multi-architecture cross-compilation of OpenSSL
#                 and slipstream-rust for all major Android ABIs.
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION & ENVIRONMENT SETUP
# ==============================================================================
API=21
NDK_VERSION="r27d"
OPENSSL_VERSION="openssl-3.5"
REPO_URL="https://github.com/Mygod/slipstream-rust.git"

ROOT_DIR="$HOME"
PROJECT_DIR="$ROOT_DIR/slipstream-rust"
DIST_DIR="$PWD/dist"

# NDK Toolchain Path Calculations
NDK_DIR="$ROOT_DIR/android-ndk-$NDK_VERSION"
NDK_BIN="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin"
SYSROOT="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/sysroot"

# Dedicated Architecture Install Folders for OpenSSL Static Artifacts
OPENSSL_ARM64="$ROOT_DIR/android-openssl-arm64"
OPENSSL_ARM32="$ROOT_DIR/android-openssl-armv7"
OPENSSL_X86="$ROOT_DIR/android-openssl-x86"
OPENSSL_X86_64="$ROOT_DIR/android-openssl-x86_64"

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
log "1. Installing system deps"

sudo apt-get update -y
sudo apt-get install -y \
    cmake ninja-build build-essential pkg-config unzip wget git perl make gcc curl

# ==============================================================================
# RUST TOOLCHAIN BOOTSTRAP
# ==============================================================================
if ! command -v rustup &>/dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

source "$HOME/.cargo/env"

rustup default stable

log "Installing Rust Android targets"
run rustup target add \
    aarch64-linux-android \
    armv7-linux-androideabi \
    i686-linux-android \
    x86_64-linux-android

log "Installing cargo-ndk"
if ! command -v cargo-ndk &>/dev/null; then
    run cargo install cargo-ndk
fi

# ==============================================================================
# 2. TOOLCHAIN & PATH ACQUISITION (ANDROID NDK)
# ==============================================================================
log "2. Android NDK"

if [ ! -d "$NDK_DIR" ]; then
    run wget \
        --progress=bar:force:noscroll \
        "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip" \
        -O "$ROOT_DIR/ndk.zip"

    run unzip -q "$ROOT_DIR/ndk.zip" -d "$ROOT_DIR"
    rm -f "$ROOT_DIR/ndk.zip"
fi

export ANDROID_NDK_HOME="$NDK_DIR"
export ANDROID_NDK_ROOT="$NDK_DIR"
export NDK_HOME="$NDK_DIR"
export PATH="$NDK_BIN:$PATH"

# ==============================================================================
# 3. COMPILING NATIVE TARGET DEPENDENCIES (OPENSSL static libs)
# ==============================================================================
log "3. OpenSSL source setup"

if [ ! -d "$ROOT_DIR/openssl" ]; then
    run git clone https://github.com/openssl/openssl.git "$ROOT_DIR/openssl"
fi

cd "$ROOT_DIR/openssl"
run git fetch --all
run git checkout "$OPENSSL_VERSION"

# --- Architecture Compilation Run Block ---

log "3.1: Compiling OpenSSL for arm64"
if [ ! -f "$OPENSSL_ARM64/lib/libcrypto.a" ]; then
    make clean || true
    run ./Configure android-arm64 -D__ANDROID_API__=$API --prefix="$OPENSSL_ARM64" no-shared
    run make -j"$(nproc)"
    run make install_sw
fi

log "3.2: Compiling OpenSSL for arm32"
if [ ! -f "$OPENSSL_ARM32/lib/libcrypto.a" ]; then
    make clean || true
    run ./Configure android-arm -D__ANDROID_API__=$API --prefix="$OPENSSL_ARM32" no-shared
    run make -j"$(nproc)"
    run make install_sw
fi

log "3.3: Compiling OpenSSL for x86 (Intel 32-bit)"
if [ ! -f "$OPENSSL_X86/lib/libcrypto.a" ]; then
    make clean || true
    run ./Configure android-x86 -D__ANDROID_API__=$API --prefix="$OPENSSL_X86" no-shared
    run make -j"$(nproc)"
    run make install_sw
fi

log "3.4: Compiling OpenSSL for x86_64 (Intel 64-bit)"
if [ ! -f "$OPENSSL_X86_64/lib/libcrypto.a" ]; then
    make clean || true
    run ./Configure android-x86_64 -D__ANDROID_API__=$API --prefix="$OPENSSL_X86_64" no-shared
    run make -j"$(nproc)"
    run make install_sw
fi

cd "$ROOT_DIR"

# ==============================================================================
# 4. WORKSPACE ACQUISITION
# ==============================================================================
log "4. Clone project working tree"

if [ ! -d "$PROJECT_DIR" ]; then
    run git clone "$REPO_URL" "$PROJECT_DIR"
fi

cd "$PROJECT_DIR"
run git submodule update --init --recursive

# ==============================================================================
# CORE ARCHITECTURE CROSS-COMPILATION ENGINE
# ==============================================================================
build_target() {
    ABI="$1"
    TARGET="$2"
    CLANG="$3"
    OPENSSL_DIR="$4"

    log "BUILDING ABI TARGET: $ABI"

    # Deep purge tracking caches to keep linker environments predictable
    rm -rf .picoquic-build
    cargo clean

    # Architecture Environment Context Flags
    export ANDROID_ABI="$ABI"
    export ANDROID_PLATFORM="android-$API"
    export TARGET="$TARGET"
    export CARGO_BUILD_TARGET="$TARGET"

    # Cross-Compile Compiler Tool Configuration Mapping Variables
    export CC="$NDK_BIN/$CLANG"
    export CXX="${CC}++"
    export AR="$NDK_BIN/llvm-ar"
    export RANLIB="$NDK_BIN/llvm-ranlib"
    export LD="$NDK_BIN/ld"
    export PATH="$NDK_BIN:$PATH"
    export SYSROOT="$SYSROOT"

    export CFLAGS="--target=${TARGET}${API} --sysroot=$SYSROOT"
    export CXXFLAGS="$CFLAGS"

    # Explicit Cryptographic Framework Native Directories Linking Properties
    export OPENSSL_DIR="$OPENSSL_DIR"
    export OPENSSL_ROOT_DIR="$OPENSSL_DIR"
    export OPENSSL_LIB_DIR="$OPENSSL_DIR/lib"
    export OPENSSL_INCLUDE_DIR="$OPENSSL_DIR/include"
    export OPENSSL_CRYPTO_LIBRARY="$OPENSSL_DIR/lib/libcrypto.a"
    export OPENSSL_SSL_LIBRARY="$OPENSSL_DIR/lib/libssl.a"
    export OPENSSL_STATIC=1
    export OPENSSL_USE_STATIC_LIBS=ON

    # External Submodule Build Attributes
    export PICOQUIC_FETCH_PTLS=ON
    export BUILD_TYPE=Release
    export RUSTFLAGS="-C link-arg=-lc -C link-arg=-ldl -C link-arg=-llog -C link-arg=-lunwind"

    # Explicit Toolchain Linker Architecture Variable Mapping Injection Blocks
    if [ "$TARGET" = "aarch64-linux-android" ]; then
        export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$CC"
        export CARGO_TARGET_AARCH64_LINUX_ANDROID_AR="$AR"
        export CC_aarch64_linux_android="$CC"
        export CXX_aarch64_linux_android="$CXX"
        export AR_aarch64_linux_android="$AR"

    elif [ "$TARGET" = "armv7-linux-androideabi" ]; then
        export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$CC"
        export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_AR="$AR"
        export CC_armv7_linux_androideabi="$CC"
        export CXX_armv7_linux_androideabi="$CXX"
        export AR_armv7_linux_androideabi="$AR"

    elif [ "$TARGET" = "i686-linux-android" ]; then
        export CARGO_TARGET_I686_LINUX_ANDROID_LINKER="$CC"
        export CARGO_TARGET_I686_LINUX_ANDROID_AR="$AR"
        export CC_i686_linux_android="$CC"
        export CXX_i686_linux_android="$CXX"
        export AR_i686_linux_android="$AR"

    elif [ "$TARGET" = "x86_64-linux-android" ]; then
        export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$CC"
        export CARGO_TARGET_X86_64_LINUX_ANDROID_AR="$AR"
        export CC_x86_64_linux_android="$CC"
        export CXX_x86_64_linux_android="$CXX"
        export AR_x86_64_linux_android="$AR"
    fi

    log "Building picoquic submodules ($ABI)"
    run bash scripts/build_picoquic.sh

    log "Cargo building compilation profiles ($ABI)"
    run cargo ndk \
        -t "$ABI" \
        build \
        --release \
        -p slipstream-client \
        -p slipstream-server

    log "Verify Binary Health Structures ($ABI)"
    OUT="target/$TARGET/release"
    file "$OUT/slipstream-client" || true
    file "$OUT/slipstream-server" || true
    du -h "$OUT/slipstream-client" || true
    du -h "$OUT/slipstream-server" || true

    # ==============================================================================
    # PIPELINE STAGE 1: ORGANIZE RAW BINARIES FOR MONOLITHIC RELEASE STORAGE
    # ==============================================================================
    mkdir -p "$DIST_DIR"

    # Normalize Android architecture naming conventions
    local final_arch
    case "$ABI" in
        "arm64-v8a")   final_arch="arm64" ;;
        "armeabi-v7a") final_arch="armv7" ;;
        "x86")         final_arch="x86"   ;;
        "x86_64")      final_arch="amd64" ;;
        *)             final_arch="$ABI"  ;;
    esac

    log "Staging clean raw artifacts for android-${final_arch}"

    mv "$OUT/slipstream-client" "$DIST_DIR/slipstream-client-android-${final_arch}"
    mv "$OUT/slipstream-server" "$DIST_DIR/slipstream-server-android-${final_arch}"

    chmod +x "$DIST_DIR/slipstream-client-android-${final_arch}"
    chmod +x "$DIST_DIR/slipstream-server-android-${final_arch}"
}

# ==============================================================================
# PIPELINE ARCHITECTURE RUN SUBMISSIONS
# ==============================================================================

# 1. ARM 64-bit Run
build_target \
    arm64-v8a \
    aarch64-linux-android \
    aarch64-linux-android21-clang \
    "$OPENSSL_ARM64"

# 2. Intel x86 32-bit Run
build_target \
    x86 \
    i686-linux-android \
    i686-linux-android21-clang \
    "$OPENSSL_X86"

# 3. ARM 32-bit Run
build_target \
    armeabi-v7a \
    armv7-linux-androideabi \
    armv7a-linux-androideabi21-clang \
    "$OPENSSL_ARM32"

# 4. Intel x86_64 64-bit Run
build_target \
    x86_64 \
    x86_64-linux-android \
    x86_64-linux-android21-clang \
    "$OPENSSL_X86_64"

# ==============================================================================
# PIPELINE EXIT CONDITIONS MET SUCCESSFUL
# ==============================================================================
log "BUILD SUCCESS"

echo "Staged Raw Binaries in $DIST_DIR:"
ls -lh "$DIST_DIR"
