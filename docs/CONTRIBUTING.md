# Contributing to MMDVM_DEB

Thank you for your interest in contributing to the Ham Radio Debian Repository! This guide will help you add new packages or improve existing ones.

## 📋 Prerequisites

Before contributing, ensure you have:
- GitHub account
- Basic knowledge of Debian packaging
- Docker Desktop (for testing)
- Git command line tools
- Understanding of shell scripting

## 🎯 Contribution Scope

We accept packages that are:
- ✅ **Ham Radio / Amateur Radio related**
- ✅ **Open source with clear licensing**
- ✅ **Buildable from source code**
- ✅ **Actively maintained upstream**

We do NOT accept:
- ❌ Proprietary/closed-source software
- ❌ Packages unrelated to amateur radio
- ❌ Binary-only distributions
- ❌ Abandoned projects (>2 years without updates)

## 📦 Current Package Portfolio

The repository currently maintains these packages:

### Core Digital Voice Software

These are the foundational software packages that directly control radio hardware and handle the core digital voice protocols.

#### MMDVM Host Software (`mmdvmhost`)
- **MMDVMHost** - Multi-Mode Digital Voice Modem host software
- **MMDVMCal** - Calibration tool for MMDVM modems
- **RemoteCommand** - Remote control interface
- **Features**: Supports DMR, D-Star, YSF, P25, NXDN, POCSAG, FM
- **Hardware**: GPIO, I2C displays, OLED support on ARM architectures

#### D-Star Repeater Controller (`dstarrepeater`)
- **dstarrepeaterd** - Main D-Star repeater controller daemon
- **dstarrepeaterconfig** - GUI configuration utility for repeater setup
- **Hardware daemons** - Support for DVAP, DV-RPTR, GMSK modems, sound cards, analog interfaces
- **Features** - Voice announcements, beacons, GPIO control (ARM), hardware PTT
- **Platform Support** - Full GPIO support on ARM, software-only on x86_64

### Gateway & Client Packages

All gateway packages follow the "*clients" naming convention and include gateways, test tools (parrots), and cross-mode converters where applicable.

#### DMR Ecosystem (`dmrclients`)
- **DMRGateway** - Routes between multiple DMR networks (Brandmeister, DMR+, TGIF, etc.)
- **DMR2YSF** - Cross-mode: DMR to YSF converter
- **DMR2NXDN** - Cross-mode: DMR to NXDN converter

#### D-Star Gateway & Clients (`dstarclients`)
- **ircDDBGateway** - IRC DDB Gateway for D-Star networking
- **DStarGateway** - D-Star Gateway for reflector connections
- **remotecontrold** - Remote control daemon
- **starnetserverd** - STARnet server for group calls
- **Additional tools** - Time server, text/voice transmit tools

#### YSF/Fusion Ecosystem (`ysfclients`)
- **YSFGateway** - Yaesu System Fusion gateway
- **YSFParrot** - YSF test/echo server
- **DGIdGateway** - DG-ID routing gateway
- **YSF2DMR** - Cross-mode: YSF to DMR converter
- **YSF2NXDN** - Cross-mode: YSF to NXDN converter
- **YSF2P25** - Cross-mode: YSF to P25 converter

#### NXDN Ecosystem (`nxdnclients`)
- **NXDNGateway** - NXDN gateway for reflector connections
- **NXDNParrot** - NXDN test/echo server
- **NXDN2DMR** - Cross-mode: NXDN to DMR converter

#### P25 Ecosystem (`p25clients`)
- **P25Gateway** - P25 gateway for reflector connections
- **P25Parrot** - P25 test/echo server

#### Other Protocol Clients
- **aprsclients** - APRS Gateway between APRS-IS and RF networks
- **pocsagclients** - DAPNET Gateway for POCSAG paging network
- **fmclients** - FM Gateway for analog-to-digital bridging

#### Support Libraries
- **wiringpi** - GPIO interface library for Raspberry Pi (ARM only)

## 📦 Adding a New Package

### Step 1: Fork and Clone

```bash
# Fork the repository on GitHub
# Then clone your fork
git clone https://github.com/YOUR-USERNAME/MMDVM_DEB.git
cd MMDVM_DEB

# Add upstream remote
git remote add upstream https://github.com/MW0MWZ/MMDVM_DEB.git
```

### Step 2: Determine Package Type

Follow the naming convention:

#### Core Software
For foundational software that directly controls hardware or provides core protocol functionality:
- **Examples**: `mmdvmhost`, `dstarrepeater`
- **Criteria**: Direct hardware control, core protocol implementation, foundational software

#### Gateway/Client Packages
For network gateways, protocol converters, and related tools:
- **Naming**: Must end in "clients" - `protocolclients` or `purposeclients`
- **Group related tools**: Gateway + parrot + cross-mode converters
- **Examples**: `dmrclients`, `ysfclients`, `nxdnclients`

### Step 3: Create Package Structure

```bash
# Create package directory
mkdir -p packages/PACKAGENAME

# Navigate to package directory (use actual name, not PACKAGENAME)
cd packages/PACKAGENAME
```

### Step 4: Create Build Script

Create `build.sh` with the following template:

#### Standard Single-Repository Package

```bash
#!/bin/bash
set -e

# Package build script for Debian
# Following Debian packaging best practices and GitHub best practices

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
PACKAGE_NAME="packagename"
GITURL="https://github.com/upstream/repo.git"
BUILD_DIR="build"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Function to print colored messages
print_message() {
    echo -e "${GREEN}[BUILD]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to check build dependencies
check_dependencies() {
    print_message "Checking build dependencies..."
    
    local missing_deps=()
    local required_tools=("git" "make" "g++" "dpkg-deb" "fakeroot")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_deps+=("$tool")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing build dependencies: ${missing_deps[*]}"
        print_message "Install with: sudo apt-get install git build-essential dpkg-dev fakeroot"
        exit 1
    fi
}

# Function to clean build environment
clean_build() {
    print_message "Cleaning build environment..."
    rm -rf "$BUILD_DIR"
    rm -rf RepoName
    mkdir -p "$BUILD_DIR"
    mkdir -p "$OUTPUT_DIR"
}

# Function to clone and prepare sources
prepare_source() {
    print_message "Cloning source from $GITURL..."
    git clone "$GITURL" RepoName
    
    cd RepoName
    GIT_COMMIT=$(git rev-parse --short HEAD)
    GIT_DATE=$(git show -s --format=%cd --date=format:'%Y.%m.%d' HEAD)
    cd ..
    
    # Use git date as version for consistency
    VERSION="$GIT_DATE"
    
    print_info "Source version: $VERSION"
    print_info "Git commit: $GIT_COMMIT"
}

# Function to build the software
build_software() {
    print_message "Building software..."
    
    cd RepoName
    
    # Clean any previous builds
    make clean || true
    
    # Build with optimization and current C++ standards
    make -j$(nproc) \
        CFLAGS="-O2 -Wall -g" \
        CXXFLAGS="-O2 -Wall -g -std=c++17" \
        all
    
    cd ..
    
    print_message "Build completed successfully"
}

# Function to determine package revision
get_package_revision() {
    local pkg_version="$1"
    local revision=1
    echo "$revision"
}

# Function to create Debian package structure
create_package() {
    # Use Debian version from environment or default to bookworm
    DEBIAN_VERSION="${DEBIAN_VERSION:-bookworm}"
    print_message "Creating Debian package for $DEBIAN_VERSION..."
    
    # Determine package revision
    REVISION=$(get_package_revision "$VERSION")
    FULL_VERSION="${VERSION}-${REVISION}"
    
    print_info "Package version: $FULL_VERSION"
    
    # Use ARCH from environment if set, otherwise detect
    if [ -n "$ARCH" ]; then
        PKG_ARCH="$ARCH"
    else
        PKG_ARCH=$(dpkg --print-architecture)
    fi
    
    # Create package directory structure following Debian standards
    PKG_DIR="$BUILD_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}"
    mkdir -p "$PKG_DIR/DEBIAN"
    mkdir -p "$PKG_DIR/usr/bin"
    mkdir -p "$PKG_DIR/usr/share/$PACKAGE_NAME"
    mkdir -p "$PKG_DIR/etc/$PACKAGE_NAME"
    mkdir -p "$PKG_DIR/var/log/$PACKAGE_NAME"
    mkdir -p "$PKG_DIR/usr/share/doc/$PACKAGE_NAME"
    mkdir -p "$PKG_DIR/usr/lib/systemd/system"
    
    # Copy binary
    cp "RepoName/Binary" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/Binary"
    
    # Copy configuration files
    if [ -f "RepoName/config.ini" ]; then
        cp "RepoName/config.ini" "$PKG_DIR/usr/share/$PACKAGE_NAME/config.ini.sample"
        cp "RepoName/config.ini" "$PKG_DIR/etc/$PACKAGE_NAME/config.ini.example"
    fi
    
    # Copy documentation
    for doc in README.md README LICENSE COPYING AUTHORS CHANGELOG; do
        if [ -f "RepoName/$doc" ]; then
            cp "RepoName/$doc" "$PKG_DIR/usr/share/doc/$PACKAGE_NAME/"
        fi
    done
    
    # Generate control file with proper dependencies based on Debian version
    DEPENDS="libc6 (>= 2.31), libgcc-s1 (>= 3.0) | libgcc1, libstdc++6 (>= 5.2)"
    
    case "$DEBIAN_VERSION" in
        bullseye)
            DEPENDS="libc6 (>= 2.31), libgcc-s1 (>= 3.0) | libgcc1, libstdc++6 (>= 5.2)"
            ;;
        bookworm)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11)"
            ;;
        trixie)
            DEPENDS="libc6 (>= 2.38), libgcc-s1 (>= 3.0), libstdc++6 (>= 13)"
            ;;
        *)
            print_warning "Unknown Debian version: $DEBIAN_VERSION, using bookworm defaults"
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11)"
            ;;
    esac
    
    cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: $PACKAGE_NAME
Version: $FULL_VERSION
Section: hamradio
Priority: optional
Architecture: $PKG_ARCH
Depends: $DEPENDS
Maintainer: MW0MWZ <andy@mw0mwz.co.uk>
Description: Brief description for Amateur Radio
 Detailed description of the package and its components.
 .
 This package provides [list components and their functions].
 .
 Git commit: $GIT_COMMIT
Homepage: https://github.com/upstream/repo
EOF
    
    # Create conffiles list for configuration files
    if [ -f "$PKG_DIR/etc/$PACKAGE_NAME/config.ini.example" ]; then
        cat > "$PKG_DIR/DEBIAN/conffiles" << EOF
/etc/$PACKAGE_NAME/config.ini.example
EOF
    fi
    
    # Create postinst script for user creation and service setup
    cat > "$PKG_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e

# Create user if it doesn't exist
if ! getent passwd packagename >/dev/null; then
    useradd --system --home /var/lib/packagename --shell /bin/false \
            --comment "Package User" packagename
fi

# Create directories and set permissions
mkdir -p /var/lib/packagename
mkdir -p /var/log/packagename
chown packagename:packagename /var/lib/packagename
chown packagename:packagename /var/log/packagename

# Enable and start service (if systemd service exists)
if [ -f /usr/lib/systemd/system/packagename.service ]; then
    systemctl daemon-reload
    systemctl enable packagename.service
fi

#DEBHELPER#
EOF
    chmod 755 "$PKG_DIR/DEBIAN/postinst"
    
    # Create postrm script for cleanup
    cat > "$PKG_DIR/DEBIAN/postrm" << 'EOF'
#!/bin/bash
set -e

case "$1" in
    purge)
        # Remove user and home directory on purge
        if getent passwd packagename >/dev/null; then
            userdel packagename || true
        fi
        rm -rf /var/lib/packagename
        rm -rf /var/log/packagename
        ;;
esac

#DEBHELPER#
EOF
    chmod 755 "$PKG_DIR/DEBIAN/postrm"
    
    # Build the package
    print_message "Building .deb package..."
    fakeroot dpkg-deb --build "$PKG_DIR"
    
    # Move to output directory
    mv "$BUILD_DIR"/*.deb "$OUTPUT_DIR/"
    
    print_message "Package created: ${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}.deb"
}

# Function to verify package
verify_package() {
    print_message "Verifying package..."
    
    local PKG_ARCH="${ARCH:-$(dpkg --print-architecture)}"
    DEB_FILE="$OUTPUT_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}.deb"
    
    if [ -f "$DEB_FILE" ]; then
        print_info "Package info:"
        dpkg-deb -I "$DEB_FILE"
        
        print_info "Package contents (first 20 files):"
        dpkg-deb -c "$DEB_FILE" | head -20
        
        # Basic validation
        print_info "Package validation:"
        if dpkg-deb -e "$DEB_FILE" /tmp/package_extract 2>/dev/null; then
            print_info "✓ Package structure is valid"
            rm -rf /tmp/package_extract
        else
            print_warning "⚠ Package structure validation failed"
        fi
    else
        print_error "Package file not found: $DEB_FILE"
        exit 1
    fi
}

# Main execution
main() {
    print_message "Starting build for $PACKAGE_NAME"
    
    # Use environment variables if set
    if [ -n "$ARCH" ]; then
        print_info "Using architecture from environment: $ARCH"
    fi
    if [ -n "$DEBIAN_VERSION" ]; then
        print_info "Using Debian version from environment: $DEBIAN_VERSION"
    fi
    if [ -n "$OUTPUT_DIR" ]; then
        print_info "Using output directory from environment: $OUTPUT_DIR"
    fi
    
    check_dependencies
    clean_build
    prepare_source
    build_software
    create_package
    verify_package
    
    print_message "Build completed successfully!"
    print_info "Package available in: $OUTPUT_DIR"
}

# Run main function with all arguments
main "$@"
```

#### Multi-Repository Package (Cross-Mode Converters)

For packages that build from multiple repositories, modify the preparation and build functions:

```bash
# Configuration for multi-repository builds
MAIN_GITURL="https://github.com/g4klx/MainRepo.git"
MMDVM_CM_GITURL="https://github.com/nostar/MMDVM_CM.git"

# Function to clone and prepare sources
prepare_source() {
    print_message "Cloning MainRepo from $MAIN_GITURL..."
    git clone "$MAIN_GITURL" MainRepo
    
    cd MainRepo
    MAIN_COMMIT=$(git rev-parse --short HEAD)
    GIT_DATE=$(git show -s --format=%cd --date=format:'%Y.%m.%d' HEAD)
    cd ..
    
    print_message "Cloning MMDVM_CM from $MMDVM_CM_GITURL..."
    git clone "$MMDVM_CM_GITURL" MMDVM_CM
    
    cd MMDVM_CM
    MMDVM_CM_COMMIT=$(git rev-parse --short HEAD)
    cd ..
    
    VERSION="$GIT_DATE"
    
    print_info "Source version: $VERSION"
    print_info "MainRepo commit: $MAIN_COMMIT"
    print_info "MMDVM_CM commit: $MMDVM_CM_COMMIT"
}

# Function to build the software
build_software() {
    print_message "Building main components..."
    
    cd MainRepo
    for component in Gateway Parrot; do
        if [ -d "$component" ]; then
            print_info "Building $component..."
            cd "$component"
            make clean || true
            make -j$(nproc) CXXFLAGS="-O2 -Wall -g -std=c++17"
            cd ..
        fi
    done
    cd ..
    
    print_message "Building cross-mode converters..."
    
    cd MMDVM_CM
    for converter in Mode2DMR Mode2YSF Mode2NXDN; do
        if [ -d "$converter" ]; then
            print_info "Building $converter..."
            cd "$converter"
            make clean || true
            make -j$(nproc) CXXFLAGS="-O2 -Wall -g -std=c++17"
            cd ..
        fi
    done
    cd ..
}
```

### Step 5: Create Source Configuration

Create `source.conf` with repository information:

```bash
# Source configuration for packagename
GITURL="https://github.com/upstream/repo.git"

# Package metadata
PACKAGE_NAME="packagename"
PACKAGE_DESCRIPTION="Description for Amateur Radio digital communications"
PACKAGE_SECTION="hamradio"
PACKAGE_PRIORITY="optional"

# Components built from this package
COMPONENTS="Component1 Component2"

# Build dependencies
BUILD_DEPS="build-essential cmake git"

# Runtime dependencies (base dependencies)
RUNTIME_DEPS="libstdc++6"

# Git commit (updated automatically by check-upstream-updates workflow)
GIT_COMMIT="unknown"

# Additional upstream repositories (if needed for multi-repo builds)
# GITURL_SECONDARY="https://github.com/other/repo.git"
# GIT_COMMIT_SECONDARY="unknown"
```

### Step 6: Test Locally

```bash
# From package directory
cd packages/packagename

# Set environment variables for testing
export OUTPUT_DIR=./output
export ARCH=amd64
export DEBIAN_VERSION=bookworm

# Make build script executable
chmod +x build.sh

# Run build
./build.sh

# Check output
ls -la output/
dpkg-deb -I output/*.deb  # Show package info
dpkg-deb -c output/*.deb  # Show contents

# Test with different architectures
ARCH=arm64 ./build.sh
ARCH=armhf ./build.sh

# Test with different Debian versions
DEBIAN_VERSION=bullseye ./build.sh
DEBIAN_VERSION=trixie ./build.sh
```

### Step 7: Update Documentation

Add your package to the README.md in the appropriate section:

```markdown
### Core Digital Voice Software (if core software)
| **packagename** | Description including all components | ComponentA, ComponentB | [Upstream](https://github.com/...) |

### Gateway & Client Packages (if client software)
| **packagenameclients** | Description including all components | ComponentA, ComponentB | [Upstream](https://github.com/...) |
```

### Step 8: Submit Pull Request

```bash
# Create feature branch with descriptive name
git checkout -b add-packagename

# Add your changes
git add packages/packagename/
git add README.md

# Commit with detailed message following conventional commits
git commit -m "feat: add packagename for Amateur Radio

- Add build.sh for packagename following GitHub best practices
- Add source.conf configuration
- Includes components: X, Y, Z
- Builds from upstream git repository using latest standards
- Supports amd64, arm64, armhf architectures
- Compatible with Debian 11, 12, 13
- Uses C++17 standard and modern build practices
- Includes systemd service files and user management
- Follows Debian packaging standards"

# Push to your fork
git push origin add-packagename
```

## 🔧 Package Organization Examples

### Core Software Example (mmdvmhost)

Foundational software for MMDVM hardware:
```
mmdvmhost/
├── build.sh        # Handles ARM OLED support
└── source.conf     # Configuration
```

Features:
- ARM builds include OLED support
- GPIO and I2C display support
- Cross-platform compatibility

### Core Repeater Software Example (dstarrepeater)

Dedicated repeater controller:
```
dstarrepeater/
├── build.sh        # Handles ARM/x86 differences
└── source.conf     # Single upstream source
```

The build script:
- Detects architecture for GPIO support
- Uses different Makefiles (Makefile vs MakefilePi)
- Installs wiringPi dependency on ARM
- Builds multiple hardware-specific daemons

### Protocol Suite Example (ysfclients)

Combines multiple related tools:
```
ysfclients/
├── build.sh        # Builds from 2 repositories
└── source.conf     # Source configuration
```

The build script handles:
- YSFGateway, YSFParrot, DGIdGateway from g4klx/YSFClients
- YSF2DMR, YSF2NXDN, YSF2P25 from nostar/MMDVM_CM

### Complex Multi-Source Example (dstarclients)

Multiple binaries from multiple sources:
```
dstarclients/
├── build.sh        # Builds from 2 repositories
└── source.conf     # Source configuration
```

Builds:
- ircDDBGateway and tools from g4klx/ircDDBGateway
- DStarGateway and tools from F4FXL/DStarGateway

### Simple Package Example (pocsagclients)

Single binary, single purpose:
```
pocsagclients/
├── build.sh        # Simple single-repo build
└── source.conf     # Source configuration
```

## 📝 Best Practices

### Package Naming
1. **Core software**: Use descriptive names (`mmdvmhost`, `dstarrepeater`)
2. **Gateway packages**: Always use "*clients" suffix (`dmrclients`, `ysfclients`)
3. **Group related functionality**: Combine gateways, parrots, and cross-mode converters

### Build Standards
1. **Use modern C++ standards**: Default to C++17 or later
2. **Optimize builds**: Use `-O2` optimization flags
3. **Enable warnings**: Use `-Wall` for better code quality
4. **Support parallel builds**: Use `-j$(nproc)`

### Directory Structure
1. **Consistent paths**:
   - Config: `/etc/{package}/`
   - Logs: `/var/log/{package}/`
   - Data: `/usr/share/{package}/`
   - User home: `/var/lib/{package}/`
2. **Standard systemd integration**: `/usr/lib/systemd/system/`

### Version Management
1. **Date-based versioning**: Use git commit dates (`YYYY.MM.DD-r1`)
2. **Include git commits**: Embed commit hash in package descriptions
3. **Handle revisions**: Increment revision for same-day rebuilds

### Dependencies
1. **Version-specific**: Handle different Debian versions properly
2. **Minimal dependencies**: Only include what's actually needed
3. **Development vs runtime**: Separate build and runtime dependencies

### User Management
1. **System users**: Create dedicated users for services
2. **Proper permissions**: Set appropriate file and directory permissions
3. **Cleanup on removal**: Remove users and data on package purge

## 🧪 Testing Guidelines

Before submitting, ensure your package passes all tests:

### 1. Build Test
```bash
# Test basic build
./build.sh

# Verify no errors in build output
echo $?  # Should be 0
```

### 2. Package Validation
```bash
# Inspect package contents
dpkg-deb -c output/*.deb | head -20

# Check package information
dpkg-deb -I output/*.deb

# Validate control file
dpkg-deb -e output/*.deb /tmp/extract
cat /tmp/extract/control
rm -rf /tmp/extract
```

### 3. Cross-Architecture Testing
```bash
# Test all supported architectures
for arch in amd64 arm64 armhf; do
    echo "Testing $arch..."
    ARCH=$arch ./build.sh
done
```

### 4. Debian Version Testing
```bash
# Test all supported Debian versions
for version in bullseye bookworm trixie; do
    echo "Testing $version..."
    DEBIAN_VERSION=$version ./build.sh
done
```

### 5. Installation Test (Optional)
```bash
# Test package installation on a test system
sudo dpkg -i output/*.deb

# Check service status (if applicable)
systemctl status packagename

# Clean up
sudo dpkg -r packagename
```

### 6. Lintian Check (Optional but Recommended)
```bash
# Install lintian
sudo apt-get install lintian

# Check package
lintian output/*.deb

# Check for serious issues only
lintian --pedantic output/*.deb
```

## 🚫 Common Mistakes to Avoid

### Package Organization
- Don't forget "*clients" suffix for gateway packages
- Don't mix core software with client software
- Don't create overly specific packages (group related tools)

### Build Scripts
- Don't hardcode versions - use git dates
- Don't ignore the ARCH environment variable
- Don't use outdated C++ standards (avoid C++98/C++03)
- Don't forget parallel build support (`-j$(nproc)`)

### Dependencies
- Don't use incorrect dependencies for Debian versions
- Don't include unnecessary build dependencies in runtime deps
- Don't forget to handle missing optional dependencies gracefully

### File Management
- Don't forget proper file permissions (755 for binaries, 644 for configs)
- Don't omit git commit information from package descriptions
- Don't use inconsistent directory naming
- Don't forget to handle platform-specific features

### Service Management
- Don't create services without proper user accounts
- Don't forget cleanup scripts (postrm)
- Don't enable services by default without user consent

## 📞 Getting Help

If you need assistance:

1. **Check examples**: Look at existing packages for reference
2. **Open an issue**: Ask questions via GitHub issues
3. **Review build logs**: Check GitHub Actions for error details
4. **Contact maintainer**: Email andy@mw0mwz.co.uk for complex issues

## 🎉 Thank You!

Your contributions help the Amateur Radio community access modern digital voice software on Debian-based systems with professional-grade packaging and the latest software development practices!

---

Built with ❤️ for the Amateur Radio community by Andy Taylor (MW0MWZ)