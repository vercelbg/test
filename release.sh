#!/usr/bin/env bash
# ==============================================================================
# Script Name:    release.sh
# Description:    Stage 2 automated asset packaging. Generates matching zip/tar
#                 archives, computes a raw/archive checksum manifest file, and
#                 produces table-based Markdown release notes.
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION & ENVIRONMENT SETUP
# ==============================================================================
ROOT_DIR="$PWD"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$ROOT_DIR/release"
CHECKSUM_FILE="$RELEASE_DIR/checksum.txt"
NOTES_FILE="$RELEASE_DIR/release_notes.md"

# Fallback tag name if run locally outside of GitHub Actions
TAG_VERSION="${GITHUB_REF_NAME:-vManual}"
REPO_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-user/repo}"

log() {
    echo
    echo "======================================"
    echo "$*"
    echo "======================================"
}

# ==============================================================================
# 1. PREREQUISITES & HOST DEPENDENCIES
# ==============================================================================
log "1. Installing release runner dependencies"

sudo apt-get update -y
sudo apt-get install -y zip tar coreutils

for cmd in sha256sum zip tar; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: Required system tool '$cmd' is missing." >&2
        exit 1
    fi
done

# Initialize fresh release target directory tree
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

if [ ! -d "$DIST_DIR" ] || [ -z "$(ls -A "$DIST_DIR" 2>/dev/null)" ]; then
    log "ERROR: The directory '$DIST_DIR' is missing or empty. Nothing to release."
    exit 1
fi

RAW_BINARIES=()
ARCHIVES=()

# ==============================================================================
# 2. COMPRESSION AND ARCHIVING ENGINE
# ==============================================================================
log "2. Packaging raw binaries from dist/ into release/"

cd "$DIST_DIR"

for asset in *; do
    [ -f "$asset" ] || continue
    
    log "Processing: $asset"
    RAW_BINARIES+=("$asset")

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
# 3. SEPARATED CHECKSUM MANIFEST GENERATION (SAVED AS ASSET FILE)
# ==============================================================================
log "3. Compiling structured SHA-256 validation manifest file"

: > "$CHECKSUM_FILE"

echo "# archive" >> "$CHECKSUM_FILE"
cd "$RELEASE_DIR"
for archive in "${ARCHIVES[@]}"; do
    sha256sum "$archive" >> "$CHECKSUM_FILE"
done

echo "" >> "$CHECKSUM_FILE"

echo "# raw binary" >> "$CHECKSUM_FILE"
cd "$DIST_DIR"
for binary in "${RAW_BINARIES[@]}"; do
    sha256sum "$binary" >> "$CHECKSUM_FILE"
done

# ==============================================================================
# 4. DYNAMIC MARKDOWN RELEASE NOTES GENERATION (WITHOUT EMBEDDED CHECKSUM)
# ==============================================================================
log "4. Formatting production Markdown release template"

# Helper function to generate clean direct download links
get_link() {
    local name="$1"
    echo "[$2]($REPO_URL/releases/download/$TAG_VERSION/$name)"
}

: > "$NOTES_FILE"

cat << EOF >> "$NOTES_FILE"
# 🛡️ Dependency Background Scan — Release Package ($TAG_VERSION)

This release contains the verified, automated builds for **Slipstream** and **DNSTT** dependency binaries.

### 🔍 Transparent Security & Verification
These binaries are required by the **BgScanner (Background Scanner)** engine to handle secure network transport and tunnel routing protocols. Instead of bundling unverified, opaque binaries inside the scanner, all assets listed below are generated transparently in the cloud via GitHub Actions. This public compilation pipeline guarantees that the binaries are un-tampered, safe, and directly auditable from the source repository.

---

## 📥 Download Links

### 🚀 Slipstream Client Assets
| Platform / Architecture | Binary Type | Download Link |
| :--- | :--- | :--- |
| 🪟 **Windows** AMD64 (x86_64) | Production Archive | $(get_link "slipstream-client-windows-amd64.zip" "📦 Download (.zip)") |
| 🪟 **Windows** ARM64 | Production Archive | $(get_link "slipstream-client-windows-arm64.zip" "📦 Download (.zip)") |
| 🐧 **Linux** AMD64 (x86_64) | Compressed Tarball | $(get_link "slipstream-client-linux-amd64.tar.gz" "📦 Download (.tar.gz)") |
| 🐧 **Linux** 386 (32-bit) | Compressed Tarball | $(get_link "slipstream-client-linux-386.tar.gz" "📦 Download (.tar.gz)") |
| 🐧 **Linux** ARM64 | Compressed Tarball | $(get_link "slipstream-client-linux-armv8.tar.gz" "📦 Download (.tar.gz)") |
| 🐧 **Linux** ARMv7 | Compressed Tarball | $(get_link "slipstream-client-linux-armv7.tar.gz" "📦 Download (.tar.gz)") |
| 🍏 **macOS** Apple Silicon (ARM64) | Compressed Tarball | $(get_link "slipstream-client-macos-arm64.tar.gz" "📦 Download (.tar.gz)") |
| 🍏 **macOS** Intel (x86_64) | Compressed Tarball | $(get_link "slipstream-client-macos-x86_64.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** ARM64 (v8a) | Compressed Tarball | $(get_link "slipstream-client-android-arm64.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** ARMv7 | Compressed Tarball | $(get_link "slipstream-client-android-armv7.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** x86 | Compressed Tarball | $(get_link "slipstream-client-android-x86.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** x86_64 | Compressed Tarball | $(get_link "slipstream-client-android-amd64.tar.gz" "📦 Download (.tar.gz)") |

---

### 📡 Slipstream Server Assets
| Platform / Architecture | Binary Type | Download Link |
| :--- | :--- | :--- |
| 🪟 **Windows** AMD64 (x86_64) | Production Archive | $(get_link "slipstream-server-windows-amd64.zip" "📦 Download (.zip)") |
| 🪟 **Windows** ARM64 | Production Archive | $(get_link "slipstream-server-windows-arm64.zip" "📦 Download (.zip)") |
| 🐧 **Linux** AMD64 (x86_64) | Compressed Tarball | $(get_link "slipstream-server-linux-amd64.tar.gz" "📦 Download (.tar.gz)") |
| 🐧 **Linux** 386 (32-bit) | Compressed Tarball | $(get_link "slipstream-server-linux-386.tar.gz" "📦 Download (.tar.gz)") |
| 🐧 **Linux** ARM64 | Compressed Tarball | $(get_link "slipstream-server-linux-armv8.tar.gz" "📦 Download (.tar.gz)") |
| 🐧 **Linux** ARMv7 | Compressed Tarball | $(get_link "slipstream-server-linux-armv7.tar.gz" "📦 Download (.tar.gz)") |
| 🍏 **macOS** Apple Silicon (ARM64) | Compressed Tarball | $(get_link "slipstream-server-macos-arm64.tar.gz" "📦 Download (.tar.gz)") |
| 🍏 **macOS** Intel (x86_64) | Compressed Tarball | $(get_link "slipstream-server-macos-x86_64.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** ARM64 (v8a) | Compressed Tarball | $(get_link "slipstream-server-android-arm64.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** ARMv7 | Compressed Tarball | $(get_link "slipstream-server-android-armv7.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** x86 | Compressed Tarball | $(get_link "slipstream-server-android-x86.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** x86_64 | Compressed Tarball | $(get_link "slipstream-server-android-amd64.tar.gz" "📦 Download (.tar.gz)") |

---

### 💻 DNSTT Client Assets
| Platform / Architecture | Binary Type | Download Link |
| :--- | :--- | :--- |
| 🪟 **Windows** AMD64 (x86_64) | Production Archive | $(get_link "dnstt-client-windows-amd64.zip" "📦 Download (.zip)") |
| 🪟 **Windows** ARM64 | Production Archive | $(get_link "dnstt-client-windows-arm64.zip" "📦 Download (.zip)") |
| 🐧 **Linux** AMD64 (x86_64) | Compressed Tarball | $(get_link "dnstt-client-linux-amd64.tar.gz" "📦 Download (.tar.gz)") |
| 🐧 **Linux** 386 (32-bit) | Compressed Tarball | $(get_link "dnstt-client-linux-386.tar.gz" "📦 Download (.tar.gz)") |
| 🐧 **Linux** ARM64 | Compressed Tarball | $(get_link "dnstt-client-linux-arm64.tar.gz" "📦 Download (.tar.gz)") |
| 🐧 **Linux** ARMv7 | Compressed Tarball | $(get_link "dnstt-client-linux-armv7.tar.gz" "📦 Download (.tar.gz)") |
| 🍏 **macOS** Apple Silicon (ARM64) | Compressed Tarball | $(get_link "dnstt-client-macos-arm64.tar.gz" "📦 Download (.tar.gz)") |
| 🍏 **macOS** Intel (x86_64) | Compressed Tarball | $(get_link "dnstt-client-macos-x86_64.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** ARM64 (v8a) | Compressed Tarball | $(get_link "dnstt-client-android-arm64.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** ARMv7 | Compressed Tarball | $(get_link "dnstt-client-android-armv7.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** x86 | Compressed Tarball | $(get_link "dnstt-client-android-x86.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** x86_64 | Compressed Tarball | $(get_link "dnstt-client-android-amd64.tar.gz" "📦 Download (.tar.gz)") |

---

### 🏢 DNSTT Server Assets
| Platform / Architecture | Binary Type | Download Link |
| :--- | :--- | :--- |
| 🪟 **Windows** AMD64 (x86_64) | Production Archive | $(get_link "dnstt-server-windows-amd64.zip" "📦 Download (.zip)") |
| 🪟 **Windows** ARM64 | Production Archive | $(get_link "dnstt-server-windows-arm64.zip" "📦 Download (.zip)") |
| 🐧 **Linux** AMD64 (x86_64) | Compressed Tarball | $(get_link "dnstt-server-linux-amd64.tar.gz" "📦 Download (.tar.gz)") |
| 🐧 **Linux** 386 (32-bit) | Compressed Tarball | $(get_link "dnstt-server-linux-386.tar.gz" "📦 Download (.tar.gz)") |
| 🐧 **Linux** ARM64 | Compressed Tarball | $(get_link "dnstt-server-linux-arm64.tar.gz" "📦 Download (.tar.gz)") |
| 🐧 **Linux** ARMv7 | Compressed Tarball | $(get_link "dnstt-server-linux-armv7.tar.gz" "📦 Download (.tar.gz)") |
| 🍏 **macOS** Apple Silicon (ARM64) | Compressed Tarball | $(get_link "dnstt-server-macos-arm64.tar.gz" "📦 Download (.tar.gz)") |
| 🍏 **macOS** Intel (x86_64) | Compressed Tarball | $(get_link "dnstt-server-macos-x86_64.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** ARM64 (v8a) | Compressed Tarball | $(get_link "dnstt-server-android-arm64.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** ARMv7 | Compressed Tarball | $(get_link "dnstt-server-android-armv7.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** x86 | Compressed Tarball | $(get_link "dnstt-server-android-x86.tar.gz" "📦 Download (.tar.gz)") |
| 🤖 **Android** x86_64 | Compressed Tarball | $(get_link "dnstt-server-android-amd64.tar.gz" "📦 Download (.tar.gz)") |
EOF

log "STAGING, PACKAGING, AND DOCUMENTATION MET SUCCESSFUL"
