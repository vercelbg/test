# 🛡️ Dependency Builder BG Scanner Pipeline 

This repository houses the automated, multi-platform asset collection and compilation framework for **Slipstream** and **DNSTT** network dependency binaries. These assets are handled transparently in the cloud using GitHub Actions to guarantee un-tampered, secure, and auditable distributions for the **BgScanner** core engine.

---

## 🏗️ Asset Matrix & Pipeline Flow

The deployment architecture utilizes a strict **2-Stage Separation** design to handle asset gathering followed by unified release packaging. 

### ⚙️ Stage 1: Asset Gathering Matrix
The pipeline spawns independent parallel jobs to process each platform's binaries differently based on source requirements:

| Target Dependency | Target OS / Architecture | Processing Strategy | Execution Script |
| :--- | :--- | :--- | :--- |
| **Slipstream Client/Server** | 🤖 Android (ARM64, v7, x86, x64) | **Compiles From Source** | `./build-slipstream-android.sh` |
| **Slipstream Client/Server** | 🐧 Linux (AMD64, 386, ARM64, ARMv7) | **Compiles From Source** | `./build-slipstream-linux.sh` |
| **Slipstream Client/Server** | 🍏 macOS (Intel & Apple Silicon) | **Compiles From Source** | `./build-slipstream-macos.sh` |
| **Slipstream Client/Server** | 🪟 Windows (AMD64, ARM64) | 📥 **Fetches Pre-builts** *(No Source Build)* | `./fetch-slipstream-windows.sh` |
| **DNSTT Client/Server** | 🤖 Android (ARM64, v7, x86, x64) | **Compiles From Source** | `./build-dnstt-android.sh` |
| **DNSTT Client/Server** | 🐧 Linux (AMD64, 386, ARM64, ARMv7) | **Compiles From Source** | `./build-dnstt-linux.sh` |
| **DNSTT Client/Server** | 🍏 macOS (Intel & Apple Silicon) | **Compiles From Source** | `./build-dnstt-macos.sh` |
| **DNSTT Client/Server** | 🪟 Windows (AMD64, ARM64) | **Compiles From Source** | `./build-dnstt-windows.sh` |

### 📦 Stage 2: Monolithic Release Aggregator
Once Stage 1 finishes gathering assets into the shared `dist/` directory, a final runner runs `./release.sh <tag>` to:
1. Bundle individual binaries into target archive types (`.zip` for Windows, `.tar.gz` for everything else).
2. Compute a complete `checksum.txt` file logging SHA-256 hashes for both the raw binaries and compressed packages.
3. Dynamically generate structured, table-based Markdown release notes mapping explicitly to the asset download URLs.

---

## 🚀 Execution & Workflow Triggers

The GitHub Actions automated pipeline can be triggered in three distinct ways:

### 1. Production Releases (Git Tags)
Pushing a version tag matching the `v*` pattern automatically triggers a stable production release.
```bash
git tag v1.12
git push origin v1.12
