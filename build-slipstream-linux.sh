#!/usr/bin/env bash
# ==============================================================================
# Script Name:    build-macos-slipstream.sh
# Description:    Automates the cross-compilation of OpenSSL and slipstream-rust
#                 for macOS (Apple Silicon ARM64 & Intel x86_64) using osxcross.
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION & ENVIRONMENT SETUP
# ==============================================================================
OPENSSL_VERSION="openssl-3.5"
REPO_URL="https://github.com/Mygod/slipstream-rust.git"
ROOT_DIR="$HOME"

# Osxcross Cross-Compiler Toolchain Mappings
OSXCROSS_DIR="$ROOT_DIR/osxcross"
OSXCROSS_BIN="$OSXCROSS_DIR/target/bin"
MACOS_SDK_TAR="$ROOT_DIR/MacOSX14.0.sdk.tar.xz"
DARWIN_SUFFIX="darwin23"

# Dedicated Architecture Install Folders for OpenSSL Static Artifacts
OPENSSL_ARM64="$ROOT_DIR/macos-openssl-arm64"
OPENSSL_X86_64="$ROOT_DIR/macos-openssl-x86_64"

PROJECT_DIR="$ROOT_DIR/slipstream-rust"
DIST_DIR="$PWD/dist"

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
# 1. HOST PREREQUISITES & HOSTMCH DEPENDENCIES
# ==============================================================================
log "1. Installing system deps"

sudo apt-get update -y
sudo apt-get install -y \
    cmake ninja-build build-essential pkg-config \
    unzip wget git perl make gcc curl clang \
    libxml2-dev libssl-dev zlib1g-dev xz-utils \
    libbz2-dev patch lzma-dev uuid-dev

# Bootstrap Rust Toolchain if not globally discovered
if ! command -v rustup &>/dev/null; then
    log "Installing Rust Toolchain"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

# Apply current cargo configuration environment context
source "$HOME/.cargo/env"

log "1.1 Setting up Rust deployment cross targets"
run rustup target add aarch64-apple-darwin x86_64-apple-darwin

# ==============================================================================
# 2. TOOLCHAIN GENERATION (OSXCROSS COMPILATION)
# ==============================================================================
log "2. Building osxcross toolchain"

if [ ! -d "$OSXCROSS_DIR" ]; then
    run git clone https://github.com/tpoechtrager/osxcross.git "$OSXCROSS_DIR"
fi

if [ ! -f "$MACOS_SDK_TAR" ]; then
    run wget --progress=bar:force:noscroll \
        "https://github.com/joseluisq/macosx-sdks/releases/download/14.0/MacOSX14.0.sdk.tar.xz" \
        -O "$MACOS_SDK_TAR"
fi

if [ ! -f "$OSXCROSS_BIN/aarch64-apple-${DARWIN_SUFFIX}-clang" ]; then
    cp "$MACOS_SDK_TAR" "$OSXCROSS_DIR/tarballs/"
    cd "$OSXCROSS_DIR"
    UNATTENDED=1 run ./build.sh
fi

export PATH="$OSXCROSS_BIN:$PATH"

# ==============================================================================
# 3. OPENSSL SOURCE ENVIRONMENT SETUP
# ==============================================================================
log "3. OpenSSL source configuration"

if [ ! -d "$ROOT_DIR/openssl" ]; then
    run git clone https://github.com/openssl/openssl.git "$ROOT_DIR/openssl"
fi

cd "$ROOT_DIR/openssl"
run git fetch --all
run git checkout "$OPENSSL_VERSION"

# ==============================================================================
# 4. COMPILING NATIVE TARGET DEPENDENCIES (OPENSSL static libs)
# ==============================================================================
build_openssl() {
    local triple="$1"
    local config="$2"
    local prefix="$3"
    local min_ver="$4"

    if [ -f "$prefix/lib/libcrypto.a" ]; then
        return 0
    fi

    log "OpenSSL for $triple"
    cd "$ROOT_DIR/openssl"
    make clean || true

    export CC="$OSXCROSS_BIN/${triple}-clang"
    export CXX="$OSXCROSS_BIN/${triple}-clang++"
    export AR="$OSXCROSS_BIN/${triple}-ar"
    export RANLIB="$OSXCROSS_BIN/${triple}-ranlib"

    run ./Configure "$config" --prefix="$prefix" no-shared no-tests "-mmacosx-version-min=$min_ver"
    run make -j"$(nproc)" build_sw
    run "$RANLIB" libcrypto.a libssl.a
    run make install_sw
}

build_openssl "aarch64-apple-${DARWIN_SUFFIX}" darwin64-arm64-cc   "$OPENSSL_ARM64"   "11.0"
build_openssl "x86_64-apple-${DARWIN_SUFFIX}"  darwin64-x86_64-cc  "$OPENSSL_X86_64"  "10.15"

cd "$ROOT_DIR"

# ==============================================================================
# 5. WORKSPACE ACQUISITION
# ==============================================================================
log "6. Clone project working tree"

if [ ! -d "$PROJECT_DIR" ]; then
    run git clone "$REPO_URL" "$PROJECT_DIR"
fi

cd "$PROJECT_DIR"
run git submodule update --init --recursive

# ==============================================================================
# CORE DARWIN ARCHITECTURE CROSS-COMPILATION ENGINE
# ==============================================================================
build_target() {
    local arch="$1"
    local target="$2"
    local triple="$3"
    local openssl_dir="$4"
    local min_ver="$5"

    log "BUILDING DARWIN ARCHITECTURE TARGET: $arch"

    # Deep purge tracking caches to keep linker environments predictable
    rm -rf .picoquic-build
    cargo clean

    local cc="$OSXCROSS_BIN/${triple}-clang"
    local cxx="$OSXCROSS_BIN/${triple}-clang++"
    local ar="$OSXCROSS_BIN/${triple}-ar"
    local ranlib="$OSXCROSS_BIN/${triple}-ranlib"
    local ld="$OSXCROSS_BIN/${triple}-ld"
    local flags="-arch $arch -mmacosx-version-min=$min_ver"

    # Generate explicit Toolchain manifest parameters targeting downstream CMake builds
    local toolchain_file="/tmp/osxcross-toolchain-${arch}.cmake"
    cat > "$toolchain_file" <<EOF
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR ${arch})
set(CMAKE_C_COMPILER   "${cc}")
set(CMAKE_CXX_COMPILER "${cxx}")
set(CMAKE_AR           "${ar}" CACHE FILEPATH "")
set(CMAKE_RANLIB       "${ranlib}" CACHE FILEPATH "")
set(CMAKE_LINKER       "${ld}")
set(CMAKE_C_FLAGS_INIT   "${flags}")
set(CMAKE_CXX_FLAGS_INIT "${flags}")
set(CMAKE_EXE_LINKER_FLAGS_INIT    "${flags}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${flags}")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(PICOTLS_BUILD_CLI    OFF CACHE BOOL "" FORCE)
set(PICOTLS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
EOF

    # Environment Deployment Target Flags Configuration
    export CARGO_BUILD_TARGET="$target"
    export CC="$cc"
    export CXX="$cxx"
    export AR="$ar"
    export RANLIB="$ranlib"
    export LD="$ld"
    export CFLAGS="$flags"
    export CXXFLAGS="$flags"
    export LDFLAGS="$flags"

    # Explicit Cryptographic Framework Native Directories Linking Properties
    export OPENSSL_DIR="$openssl_dir"
    export OPENSSL_ROOT_DIR="$openssl_dir"
    export OPENSSL_LIB_DIR="$openssl_dir/lib"
    export OPENSSL_INCLUDE_DIR="$openssl_dir/include"
    export OPENSSL_CRYPTO_LIBRARY="$openssl_dir/lib/libcrypto.a"
    export OPENSSL_SSL_LIBRARY="$openssl_dir/lib/libssl.a"
    export OPENSSL_STATIC=1
    export OPENSSL_USE_STATIC_LIBS=ON

    # External Submodule Build Attributes
    export PICOQUIC_FETCH_PTLS=ON
    export BUILD_TYPE=Release
    export RUSTFLAGS="-C link-arg=-lc"
    export CARGO_FEATURE_PICOQUIC_MINIMAL_BUILD=1
    export CMAKE_TOOLCHAIN_FILE="$toolchain_file"

    # Target-specific toolchain environment injection mapping variables
    local target_env="${target//-/_}"
    export "CARGO_TARGET_${target_env^^}_LINKER"="$cc"
    export "CC_${target_env}"="$cc"
    export "CXX_${target_env}"="$cxx"
    export "AR_${target_env}"="$ar"

    log "Building picoquic submodules ($arch)"
    run bash scripts/build_picoquic.sh

    log "Cargo building compilation profiles ($arch)"
    run cargo build --release --target "$target" \
        -p slipstream-client \
        -p slipstream-server

    log "Verify Binary Health Structures ($arch)"
    local out="target/$target/release"
    file "$out/slipstream-client" || true
    file "$out/slipstream-server" || true
    du -h "$out/slipstream-client" "$out/slipstream-server" || true

    # ==============================================================================
    # PIPELINE STAGE 1: ORGANIZE RAW BINARIES FOR MONOLITHIC RELEASE STORAGE
    # ==============================================================================
    mkdir -p "$DIST_DIR"

    # Precise architecture conversion for user-facing assets on macOS
    local final_arch
    if [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
        final_arch="arm64"
    else
        final_arch="x86_64"
    fi

    log "Staging clean raw artifacts for macOS-${final_arch}"

    mv "$out/slipstream-client" "$DIST_DIR/slipstream-client-macos-${final_arch}"
    mv "$out/slipstream-server" "$DIST_DIR/slipstream-server-macos-${final_arch}"

    chmod +x "$DIST_DIR/slipstream-client-macos-${final_arch}"
    chmod +x "$DIST_DIR/slipstream-server-macos-${final_arch}"
}

# ==============================================================================
# PIPELINE ARCHITECTURE RUN SUBMISSIONS
# ==============================================================================

# 1. ARM64 Target Run (Apple Silicon)
build_target arm64  aarch64-apple-darwin "aarch64-apple-${DARWIN_SUFFIX}" "$OPENSSL_ARM64"   "11.0"

# 2. X86_64 Target Run (Intel Architecture)
build_target x86_64 x86_64-apple-darwin  "x86_64-apple-${DARWIN_SUFFIX}"  "$OPENSSL_X86_64"  "10.15"

# ==============================================================================
# PIPELINE EXIT CONDITIONS MET SUCCESSFUL
# ==============================================================================
log "BUILD SUCCESS"

echo "Staged Raw Binaries in $DIST_DIR:"
ls -lh "$DIST_DIR"
