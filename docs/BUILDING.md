# Building Debian Packages

This document describes how packages are built in the MMDVM_DEB repository.

## Build System Overview

The repository uses:
- **GitHub Actions** for CI/CD
- **Debian Docker containers** for build environments
- **dpkg-deb** for package creation
- **Docker with QEMU** for cross-architecture builds
- **Automatic upstream monitoring** for rebuild triggers

## Available Packages

The repository currently builds the following packages:

### Core Digital Voice Software

| Package | Description | Components | Dependencies |
|---------|-------------|------------|--------------|
| **mmdvmhost** | MMDVM Host Software & Calibration | MMDVMHost, MMDVMCal, RemoteCommand | `build-essential`, `git`, ARM: `libi2c-dev` for OLED support |
| **dstarrepeater** | D-Star Repeater Controller | dstarrepeaterd, dstarrepeaterconfig, 6 hardware-specific daemons | `libwxgtk3.0-gtk3-dev` or `libwxgtk3.2-dev`, `libusb-1.0-0-dev`, `libasound2-dev`, ARM: `wiringpi` for GPIO |

### Gateway & Client Packages

| Package | Description | Components | Dependencies |
|---------|-------------|------------|--------------|
| **dmrclients** | DMR Gateway and Cross-Mode | DMRGateway, DMR2YSF, DMR2NXDN | `build-essential`, `git` |
| **dstarclients** | D-Star Gateways and tools | ircDDBGateway, DStarGateway, remotecontrold, starnetserverd, and more | `libwxgtk3.0-gtk3-dev` or `libwxgtk3.2-dev`, `libcurl4-openssl-dev`, `libboost-dev` |
| **ysfclients** | YSF Gateway, Parrot and Cross-Mode | YSFGateway, YSFParrot, DGIdGateway, YSF2DMR, YSF2NXDN, YSF2P25 | `build-essential`, `git` |
| **nxdnclients** | NXDN Gateway, Parrot and Cross-Mode | NXDNGateway, NXDNParrot, NXDN2DMR | `build-essential`, `git` |
| **p25clients** | P25 Gateway and Parrot | P25Gateway, P25Parrot | `build-essential`, `git` |
| **aprsclients** | APRS Gateway | APRSGateway | `build-essential`, `git` |
| **pocsagclients** | POCSAG/DAPNET Gateway | DAPNETGateway | `build-essential`, `git` |
| **fmclients** | FM Gateway | FMGateway | `build-essential`, `git`, `libmd-dev` |

## Build Process

### 1. Version Generation

Packages use date-based versioning:
```
Version: YYYY.MM.DD-r{revision}
Example: 2025.01.02-r1
```

The git commit hash from upstream is captured and included in the package description.

### 2. Source Code

All packages are built from git repositories to ensure:
- Proper version tracking with git commits
- Git commit information embedded in package metadata
- Reproducible builds from specific commits
- Automatic rebuild capability on upstream changes

### 3. Multi-Repository Builds

Several packages build from multiple upstream repositories:

- **dmrclients**: 
  - DMRGateway from `g4klx/DMRGateway`
  - DMR2YSF, DMR2NXDN from `nostar/MMDVM_CM`

- **dstarclients**:
  - ircDDBGateway and tools from `g4klx/ircDDBGateway`
  - DStarGateway and tools from `F4FXL/DStarGateway`

- **ysfclients**:
  - YSFGateway, YSFParrot, DGIdGateway from `g4klx/YSFClients`
  - YSF2DMR, YSF2NXDN, YSF2P25 from `nostar/MMDVM_CM`

- **nxdnclients**:
  - NXDNGateway, NXDNParrot from `g4klx/NXDNClients`
  - NXDN2DMR from `nostar/MMDVM_CM`

### 4. Architecture Support

Builds run for three architectures:
- `amd64` - Native or Docker linux/amd64
- `arm64` - Docker with QEMU linux/arm64
- `armhf` - Docker with QEMU linux/arm/v6

### 5. Build Environment

Each build runs in a Debian Docker container matching the target version:
- Debian 11 (Bullseye)
- Debian 12 (Bookworm)
- Debian 13 (Trixie/Testing)

### 6. Debian-Specific Dependencies

Packages have version-specific dependencies based on the Debian release:

**Bullseye (11)**:
- libc6 (>= 2.31)
- libgcc-s1 (>= 3.0) | libgcc1
- libstdc++6 (>= 5.2)
- libwxbase3.0-0v5, libwxgtk3.0-gtk3-0v5 (for dstarrepeater, dstarclients)

**Bookworm (12)**:
- libc6 (>= 2.36)
- libgcc-s1 (>= 3.0)
- libstdc++6 (>= 11)
- libwxbase3.2-1, libwxgtk3.2-1 (for dstarrepeater, dstarclients)

**Trixie (13)**:
- libc6 (>= 2.38)
- libgcc-s1 (>= 3.0)
- libstdc++6 (>= 13)
- libwxbase3.2-1, libwxgtk3.2-1 (for dstarrepeater, dstarclients)

## Automatic Build Triggers

The repository can monitor upstream repositories and automatically rebuild when changes are detected.

### Check Upstream Updates Workflow

The `check-upstream-updates.yml` workflow:
- Can be run manually or scheduled
- Checks all upstream git repositories for new commits
- Compares with stored commit hashes in `source.conf` files
- Optionally updates source configurations
- Can trigger automatic rebuilds

Monitored repositories:
- https://github.com/g4klx/MMDVMHost
- https://github.com/g4klx/MMDVMCal
- https://github.com/g4klx/DStarRepeater
- https://github.com/g4klx/DMRGateway
- https://github.com/g4klx/ircDDBGateway
- https://github.com/F4FXL/DStarGateway
- https://github.com/g4klx/YSFClients
- https://github.com/g4klx/NXDNClients
- https://github.com/g4klx/P25Clients
- https://github.com/g4klx/DAPNETGateway
- https://github.com/g4klx/FMGateway
- https://github.com/g4klx/APRSGateway
- https://github.com/nostar/MMDVM_CM
- https://github.com/MW0MWZ/ArduiPi_OLED (for ARM OLED support)

## Manual Build Trigger

### Using GitHub Actions

1. Navigate to [Actions](https://github.com/MW0MWZ/MMDVM_DEB/actions)
2. Select "Build Debian Packages"
3. Click "Run workflow"
4. Choose options:
   - **Package**: Select specific package or "all"
   - **Debian Version**: Select specific version or "all"
5. Click green "Run workflow" button

### Build Matrix

With "all" options selected, the build matrix includes:
- 3 Debian versions (bullseye, bookworm, trixie)
- 3 architectures (amd64, arm64, armhf)
- 11 packages
= **99 total build jobs**

## Local Testing

### Prerequisites

- Docker Desktop (macOS/Windows) or Docker Engine (Linux)
- Git
- Basic build tools

### Test Build Script

```bash
# Navigate to package directory
cd packages/mmdvmhost

# Set environment variables
export OUTPUT_DIR=./output
export ARCH=amd64              # or arm64, armhf
export DEBIAN_VERSION=bookworm # or bullseye, trixie

# Run build script
./build.sh

# Check output
ls -la output/*.deb
dpkg-deb -I output/*.deb  # Show package info
dpkg-deb -c output/*.deb  # Show package contents
```

### Docker Build Process

The GitHub Actions workflow uses Docker to:
1. Create a Debian container for the target version
2. Install build dependencies
3. Clone upstream git repositories
4. Run the package build script
5. Output .deb files to the pool directory

Example Docker build command:
```bash
docker run --rm \
  --platform linux/amd64 \
  -v "$(pwd):/workspace" \
  -w /workspace \
  -e DEBIAN_VERSION=bookworm \
  -e ARCH=amd64 \
  debian:12 \
  bash -c "
    apt-get update
    apt-get install -y build-essential git dpkg-dev fakeroot
    cd /workspace/packages/mmdvmhost
    ./build.sh
  "
```

## Build Script Structure

### Basic Template

Each package has a `build.sh` script following this structure:

```bash
#!/bin/bash
set -e

# Configuration
PACKAGE_NAME="packagename"
GITURL="https://github.com/upstream/repo.git"
BUILD_DIR="build"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Functions for colored output
print_message() { echo -e "${GREEN}[BUILD]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Clean build environment
clean_build() {
    rm -rf "$BUILD_DIR" RepoName
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
}

# Clone and prepare source
prepare_source() {
    git clone "$GITURL" RepoName
    cd RepoName
    GIT_COMMIT=$(git rev-parse --short HEAD)
    VERSION=$(git show -s --format=%cd --date=format:'%Y.%m.%d' HEAD)
    cd ..
}

# Build software
build_software() {
    cd RepoName
    make clean || true
    make -j$(nproc)
    cd ..
}

# Create Debian package
create_package() {
    DEBIAN_VERSION="${DEBIAN_VERSION:-bookworm}"
    FULL_VERSION="${VERSION}-1"
    PKG_ARCH="${ARCH:-$(dpkg --print-architecture)}"
    
    # Create package structure
    PKG_DIR="$BUILD_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}"
    mkdir -p "$PKG_DIR/DEBIAN"
    mkdir -p "$PKG_DIR/usr/bin"
    mkdir -p "$PKG_DIR/etc/$PACKAGE_NAME"
    
    # Copy files
    cp RepoName/binary "$PKG_DIR/usr/bin/"
    
    # Create control file
    cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: $PACKAGE_NAME
Version: $FULL_VERSION
Architecture: $PKG_ARCH
Maintainer: MW0MWZ <andy@mw0mwz.co.uk>
Description: Package description
 Git commit: $GIT_COMMIT
EOF
    
    # Build package
    fakeroot dpkg-deb --build "$PKG_DIR"
    mv "$BUILD_DIR"/*.deb "$OUTPUT_DIR/"
}

# Main execution
main() {
    check_dependencies
    clean_build
    prepare_source
    build_software
    create_package
    verify_package
}

main "$@"
```

## Package-Specific Build Notes

### mmdvmhost
- ARM builds include OLED support with ArduiPi_OLED library
- x86_64 builds use standard Makefile without OLED
- Includes MMDVMHost, MMDVMCal, and RemoteCommand

### dstarrepeater

**Build Characteristics:**
- Requires wxWidgets for configuration GUI
- Builds multiple binaries from single source
- ARM builds include GPIO support via wiringPi
- Uses MakefilePi for ARM platforms with GPIO

**Components Built:**
- Main repeater daemon (`dstarrepeaterd`)
- Configuration utility (`dstarrepeaterconfig`)
- Hardware-specific daemons for different modem types
- Each component built as separate binary

**Platform Differences:**
- **ARM (armhf/arm64)**: 
  - Built with `MakefilePi` if available
  - Includes GPIO support for hardware PTT
  - Depends on wiringPi library
  - Supports direct hardware control
- **x86_64 (amd64)**:
  - Built with standard `Makefile`
  - No GPIO support
  - Software-only operation

**Dependencies by Debian Version:**
- **Bullseye**: `libwxgtk3.0-gtk3-0v5`, `libwxbase3.0-0v5`
- **Bookworm/Trixie**: `libwxgtk3.2-1`, `libwxbase3.2-1`
- **All versions**: `libusb-1.0-0`, `libasound2`

**Configuration Files:**
- Main config: `/etc/dstarrepeater/dstarrepeater.conf`
- Hardware configs: Various `.conf` files for each daemon type
- All configs have `.example` templates

**Service Management:**
- Runs as `dstar` user (created during installation)
- Service name: `dstarrepeater.service`
- Logs to `/var/log/dstarrepeater/`

### dstarclients
- Requires wxWidgets (3.0 for Bullseye, 3.2 for Bookworm/Trixie)
- Builds from two repositories (ircDDBGateway and DStarGateway)
- Multiple binaries from each source

### Cross-Mode Packages
- dmrclients, ysfclients, nxdnclients build from multiple repositories
- Main gateway from g4klx repositories
- Cross-mode converters from nostar/MMDVM_CM

### fmclients
- Simple single-binary package
- May require libmd for some functionality

## Repository Structure

The Debian repository follows standard APT repository structure:

```
deploy/
├── index.html              # Web interface
├── hamradio.gpg           # GPG public key
├── CNAME                  # GitHub Pages domain
├── dists/                 # Distribution metadata
│   ├── bullseye/
│   │   ├── Release        # Repository metadata
│   │   ├── Release.gpg    # Signature (optional)
│   │   ├── InRelease      # Inline signature (optional)
│   │   └── main/
│   │       ├── binary-amd64/
│   │       │   ├── Packages
│   │       │   ├── Packages.gz
│   │       │   └── Packages.bz2
│   │       ├── binary-arm64/
│   │       └── binary-armhf/
│   ├── bookworm/
│   └── trixie/
└── pool/                  # Package files
    └── main/
        ├── a/
        │   └── aprsclients/
        │       └── aprsclients_2025.01.02-1_amd64.deb
        ├── d/
        │   ├── dmrclients/
        │   ├── dstarclients/
        │   └── dstarrepeater/
        ├── f/
        │   └── fmclients/
        ├── m/
        │   └── mmdvmhost/
        ├── n/
        │   └── nxdnclients/
        ├── p/
        │   ├── p25clients/
        │   └── pocsagclients/
        ├── w/
        │   └── wiringpi/
        └── y/
            └── ysfclients/
```

## Directory Structure Convention

All packages follow a consistent directory structure:
- `/etc/{package}/` - Configuration files
- `/var/log/{package}/` - Log files (if needed)
- `/usr/share/{package}/` - Data files, samples, documentation

Examples:
- `/etc/mmdvmhost/MMDVM.ini`
- `/etc/dstarrepeater/dstarrepeater.conf`
- `/etc/dmrclients/DMRGateway.ini`
- `/etc/dstarclients/ircddbgateway.conf`
- `/usr/share/ysfclients/YSFHosts.txt.example`

## Troubleshooting

### Build Failures

Common issues and solutions:

**Missing dependencies**:
```bash
# Install build essentials
apt-get update
apt-get install -y build-essential git dpkg-dev fakeroot
```

**Architecture mismatch**:
```bash
# Ensure ARCH environment variable matches target
export ARCH=amd64  # or arm64, armhf
```

**wxWidgets issues (dstarrepeater, dstarclients)**:
```bash
# Debian 11
apt-get install -y libwxgtk3.0-gtk3-dev
# Debian 12+
apt-get install -y libwxgtk3.2-dev
```

**OLED library issues (mmdvmhost on ARM)**:
```bash
# Install I2C development files
apt-get install -y libi2c-dev
```

## Performance Tips

- Use `-j$(nproc)` for parallel compilation
- Build natively when possible for best performance
- Use GitHub Actions for full matrix builds
- Cache Docker images locally for repeated builds
- OLED library may require serial build (`-j1`)

## Security

- Packages can be signed with GPG (Release files)
- Repository served over HTTPS
- GPG key distributed separately
- Build process runs in isolated Docker containers

## Package Cleanup

The repository includes a cleanup workflow to manage old package versions:
- Keeps configurable number of versions per package
- Removes orphaned packages
- Regenerates repository metadata after cleanup
- Can run manually or on schedule

## Adding Support for New Debian Versions

To add support for a new Debian version:

1. Update `.github/workflows/build-debian-packages.yml`
2. Add version to workflow inputs and matrix
3. Update package build scripts for version-specific dependencies
4. Test builds for all packages
5. Update documentation

---

Built with ❤️ for the Amateur Radio community by Andy Taylor (MW0MWZ)