#!/bin/bash
set -e

# WiringPi package build script for Debian
# Uses WiringPi's built-in debian packaging
# For GitHub Actions ONLY

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="wiringpi"
BUILD_DIR="build_deb"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Source the package configuration
if [ -f "source.conf" ]; then
    source source.conf
elif [ -f "packages/${PACKAGE_NAME}/source.conf" ]; then
    source "packages/${PACKAGE_NAME}/source.conf"
fi

# Functions
print_message() { echo -e "${GREEN}[BUILD]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

check_architecture() {
    local arch="${ARCH:-$(dpkg --print-architecture)}"
    
    # Only build for ARM architectures
    case "$arch" in
        armhf|arm64|aarch64)
            print_info "Architecture $arch is supported for WiringPi"
            return 0
            ;;
        amd64|i386|x86_64)
            print_warning "WiringPi is not built for $arch architecture"
            print_info "Creating dummy package for $arch"
            create_dummy_package
            exit 0
            ;;
        *)
            print_error "Unknown architecture: $arch"
            exit 1
            ;;
    esac
}

create_dummy_package() {
    # Create a minimal dummy package for non-ARM architectures
    local arch="${ARCH:-$(dpkg --print-architecture)}"
    local DEBIAN_VERSION="${DEBIAN_VERSION:-bookworm}"
    local DEB_VERSION_SUFFIX="${DEB_VERSION_SUFFIX:-}"
    local BUILD_NUMBER="${BUILD_NUMBER:-1}"
    
    # Use GIT_REF as the version, stripping any 'v' prefix
    local VERSION="${GIT_REF#v}"
    local REVISION="${BUILD_NUMBER}${DEB_VERSION_SUFFIX}"
    local FULL_VERSION="${VERSION}-${REVISION}"
    
    mkdir -p "$OUTPUT_DIR"
    
    # Create minimal package structure
    local PKG_DIR="$BUILD_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${arch}"
    mkdir -p "$PKG_DIR/DEBIAN"
    mkdir -p "$PKG_DIR/usr/share/doc/wiringpi"
    
    # Create control file
    cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: ${PACKAGE_NAME}
Version: ${FULL_VERSION}
Section: libs
Priority: optional
Architecture: ${arch}
Maintainer: MW0MWZ <andy@mw0mwz.co.uk>
Description: GPIO Interface library for Raspberry Pi (dummy package)
 This is a dummy package for non-ARM architectures.
 WiringPi is only functional on ARM-based systems with GPIO hardware.
 .
 This package exists to satisfy dependencies on non-ARM systems
 but provides no actual functionality.
Homepage: https://github.com/WiringPi/WiringPi
EOF
    
    # Create minimal documentation
    cat > "$PKG_DIR/usr/share/doc/wiringpi/README.Debian" << EOF
WiringPi for Debian - ${arch} Architecture
==========================================

This is a dummy package. WiringPi is only functional on ARM-based
systems (Raspberry Pi and compatible boards) with GPIO hardware.

This package is provided to satisfy dependencies on ${arch} systems
but contains no functional libraries or tools.

For actual GPIO functionality, please use an ARM-based system.

 -- MW0MWZ <andy@mw0mwz.co.uk>  $(date -R)
EOF
    
    # Create changelog
    cat > "$PKG_DIR/usr/share/doc/wiringpi/changelog.Debian" << EOF
${PACKAGE_NAME} (${FULL_VERSION}) ${DEBIAN_VERSION}; urgency=medium

  * Dummy package for ${arch} architecture
  * No functional GPIO libraries included
  * Built for Debian ${DEBIAN_VERSION}

 -- MW0MWZ <andy@mw0mwz.co.uk>  $(date -R)
EOF
    gzip -9n "$PKG_DIR/usr/share/doc/wiringpi/changelog.Debian"
    
    # Create copyright
    cat > "$PKG_DIR/usr/share/doc/wiringpi/copyright" << 'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: WiringPi
Source: https://github.com/WiringPi/WiringPi

Files: *
Copyright: Gordon Henderson
License: LGPL-3+
 This library is free software; you can redistribute it and/or
 modify it under the terms of the GNU Lesser General Public
 License as published by the Free Software Foundation; either
 version 3 of the License, or (at your option) any later version.
 .
 This library is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 Lesser General Public License for more details.
 .
 You should have received a copy of the GNU Lesser General Public
 License along with this library; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
EOF
    
    # Build the package
    fakeroot dpkg-deb --build "$PKG_DIR"
    mv "$BUILD_DIR"/*.deb "$OUTPUT_DIR/"
    
    print_message "Dummy package created for $arch"
}

clean_build() {
    print_message "Cleaning build environment..."
    rm -rf "$BUILD_DIR" WiringPi
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
}

prepare_source() {
    print_message "Cloning WiringPi from $GITURL..."
    
    # If GIT_REF is set, checkout that specific tag/branch
    if [ -n "${GIT_REF:-}" ]; then
        print_info "Checking out version ${GIT_REF}"
        git clone --branch "${GIT_REF}" --depth 1 "$GITURL" WiringPi
    else
        git clone "$GITURL" WiringPi
    fi
    
    cd WiringPi
    
    # Get version from GIT_REF if available, otherwise from VERSION file
    if [ -n "${GIT_REF:-}" ]; then
        VERSION="${GIT_REF#v}"  # Remove 'v' prefix if present
    elif [ -f "VERSION" ]; then
        VERSION=$(cat VERSION | tr -d '\n')
    else
        VERSION="3.0"
    fi
    
    GIT_COMMIT_ACTUAL=$(git rev-parse --short HEAD)
    GIT_COMMIT_FULL=$(git rev-parse HEAD)
    
    # Verify we're at the expected commit if GIT_COMMIT was specified
    if [ -n "${GIT_COMMIT:-}" ] && [ "${GIT_COMMIT}" != "${GIT_COMMIT_ACTUAL}" ]; then
        print_warning "Expected commit ${GIT_COMMIT} but got ${GIT_COMMIT_ACTUAL}"
    fi
    
    cd ..
    
    print_info "Source version: $VERSION"
    print_info "Git commit: $GIT_COMMIT_ACTUAL"
    print_info "Git ref: ${GIT_REF:-unspecified}"
}

build_and_package() {
    DEBIAN_VERSION="${DEBIAN_VERSION:-bookworm}"
    DEB_VERSION_SUFFIX="${DEB_VERSION_SUFFIX:-}"
    BUILD_NUMBER="${BUILD_NUMBER:-1}"
    PKG_ARCH="${ARCH:-$(dpkg --print-architecture)}"
    
    # Map arm64/aarch64 consistently
    case "$PKG_ARCH" in
        aarch64)
            PKG_ARCH="arm64"
            ;;
    esac
    
    print_message "Building WiringPi for Debian $DEBIAN_VERSION on $PKG_ARCH..."
    
    # CRITICAL: Verify we're in the right environment
    ACTUAL_GLIBC=$(ldd --version | head -1 | grep -oE '[0-9]+\.[0-9]+$')
    ACTUAL_DEBIAN=$(cat /etc/debian_version)
    print_info "Build environment:"
    print_info "  Debian version: $ACTUAL_DEBIAN"
    print_info "  GLIBC version: $ACTUAL_GLIBC"
    print_info "  Target: $DEBIAN_VERSION"
    
    # Verify we're in the expected container
    case "$DEBIAN_VERSION" in
        bullseye)
            if [[ ! "$ACTUAL_GLIBC" =~ ^2\.31 ]]; then
                print_error "Wrong GLIBC! Expected 2.31 for Bullseye, got $ACTUAL_GLIBC"
                exit 1
            fi
            ;;
        bookworm)
            if [[ ! "$ACTUAL_GLIBC" =~ ^2\.36 ]]; then
                print_error "Wrong GLIBC! Expected 2.36 for Bookworm, got $ACTUAL_GLIBC"
                exit 1
            fi
            ;;
        trixie)
            # Trixie is testing, GLIBC version may vary (2.37-2.38+)
            print_info "Trixie build with GLIBC $ACTUAL_GLIBC"
            ;;
    esac
    
    cd WiringPi
    
    # Set up version for the build
    vMaj=$(echo $VERSION | cut -d. -f1)
    vMin=$(echo $VERSION | cut -d. -f2)
    
    # Export required variables for the debian build
    export VERSION="${vMaj}.${vMin}"
    export ARCH="${PKG_ARCH}"
    export WIRINGPI_SUDO=""  # Don't use sudo in our build environment
    
    # Set build environment to ensure correct linking
    export CC="gcc"
    export CFLAGS="-O2 -Wall -fPIC"
    export LDFLAGS=""
    
    print_info "Building debian package with VERSION=$VERSION ARCH=$ARCH"
    
    # Use WiringPi's built-in debian packaging
    ./build debian
    
    # Find the generated .deb file
    BUILT_DEB=$(find debian-template -name "*.deb" -type f | head -1)
    
    if [ -z "$BUILT_DEB" ] || [ ! -f "$BUILT_DEB" ]; then
        print_error "WiringPi debian build failed - no .deb file created"
        exit 1
    fi
    
    print_info "Built package: $BUILT_DEB"
    
    # CRITICAL: Verify what GLIBC the built library actually needs
    print_info "Verifying built library dependencies..."
    TEMP_EXTRACT=$(mktemp -d)
    dpkg-deb -x "$BUILT_DEB" "$TEMP_EXTRACT"
    
    if [ -f "$TEMP_EXTRACT/usr/lib/libwiringPi.so.3.0" ]; then
        print_info "Checking GLIBC requirements of libwiringPi.so..."
        REQUIRED_GLIBC=$(objdump -T "$TEMP_EXTRACT/usr/lib/libwiringPi.so.3.0" 2>/dev/null | grep GLIBC | sed 's/.*GLIBC_//' | sort -V | tail -1)
        print_info "Built library requires maximum GLIBC version: $REQUIRED_GLIBC"
        
        # Show all GLIBC versions required for debugging
        print_info "All GLIBC versions required:"
        objdump -T "$TEMP_EXTRACT/usr/lib/libwiringPi.so.3.0" 2>/dev/null | grep GLIBC | sed 's/.*GLIBC_/GLIBC_/' | sort -u
        
        # Verify it's appropriate for the target Debian version
        case "$DEBIAN_VERSION" in
            bullseye)
                if [[ "$REQUIRED_GLIBC" > "2.31" ]]; then
                    print_error "ERROR: Library requires GLIBC $REQUIRED_GLIBC but Bullseye only has 2.31!"
                    print_error "This package will NOT work on Bullseye systems!"
                    rm -rf "$TEMP_EXTRACT"
                    exit 1
                fi
                print_info "✓ Package is compatible with Bullseye (GLIBC 2.31)"
                ;;
            bookworm)
                if [[ "$REQUIRED_GLIBC" > "2.36" ]]; then
                    print_error "ERROR: Library requires GLIBC $REQUIRED_GLIBC but Bookworm only has 2.36!"
                    print_error "This package will NOT work on Bookworm systems!"
                    rm -rf "$TEMP_EXTRACT"
                    exit 1
                fi
                print_info "✓ Package is compatible with Bookworm (GLIBC 2.36)"
                ;;
            trixie)
                print_info "✓ Package built for Trixie with GLIBC $REQUIRED_GLIBC"
                ;;
        esac
    else
        print_warning "Could not find libwiringPi.so.3.0 in package"
    fi
    rm -rf "$TEMP_EXTRACT"
    
    # Now we need to repackage it with our versioning scheme
    REVISION="${BUILD_NUMBER}${DEB_VERSION_SUFFIX}"
    FULL_VERSION="${VERSION}-${REVISION}"
    NEW_DEB_NAME="${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}.deb"
    
    # Extract the built package to modify it
    EXTRACT_DIR="$BUILD_DIR/extracted"
    mkdir -p "$EXTRACT_DIR"
    dpkg-deb -x "$BUILT_DEB" "$EXTRACT_DIR"
    dpkg-deb -e "$BUILT_DEB" "$EXTRACT_DIR/DEBIAN"
    
    # Update the control file with our version and maintainer info
    sed -i "s/^Version:.*/Version: ${FULL_VERSION}/" "$EXTRACT_DIR/DEBIAN/control"
    sed -i "s/^Maintainer:.*/Maintainer: MW0MWZ <andy@mw0mwz.co.uk>/" "$EXTRACT_DIR/DEBIAN/control"
    
    # Add our changelog if it doesn't exist
    if [ ! -f "$EXTRACT_DIR/usr/share/doc/wiringpi/changelog.Debian.gz" ]; then
        mkdir -p "$EXTRACT_DIR/usr/share/doc/wiringpi"
        cat > "$EXTRACT_DIR/usr/share/doc/wiringpi/changelog.Debian" << EOF
${PACKAGE_NAME} (${FULL_VERSION}) ${DEBIAN_VERSION}; urgency=medium

  * Package built from release ${GIT_REF:-$VERSION}
  * Git commit: ${GIT_COMMIT_FULL}
  * Built for Debian ${DEBIAN_VERSION} on ${PKG_ARCH}
  * Build number: ${BUILD_NUMBER}
  * Using WiringPi native debian packaging
  * GLIBC compatibility verified for ${DEBIAN_VERSION}

 -- MW0MWZ <andy@mw0mwz.co.uk>  $(date -R)
EOF
        gzip -9n "$EXTRACT_DIR/usr/share/doc/wiringpi/changelog.Debian"
    fi
    
    # Ensure proper permissions on control scripts
    for script in postinst postrm preinst prerm; do
        if [ -f "$EXTRACT_DIR/DEBIAN/$script" ]; then
            chmod 755 "$EXTRACT_DIR/DEBIAN/$script"
        fi
    done
    
    # Create md5sums
    cd "$EXTRACT_DIR"
    find . -type f ! -path './DEBIAN/*' -exec md5sum {} \; | sed 's|\./||' > DEBIAN/md5sums
    cd - > /dev/null
    
    # Build the repackaged .deb
    print_message "Creating final package: $NEW_DEB_NAME"
    fakeroot dpkg-deb --build "$EXTRACT_DIR" "$OUTPUT_DIR/$NEW_DEB_NAME"
    
    # Clean up
    cd ..
    rm -rf "$EXTRACT_DIR"
    
    print_message "Package created: ../$OUTPUT_DIR/$NEW_DEB_NAME"
}

verify_package() {
    print_message "Verifying package..."
    
    PKG_ARCH="${ARCH:-$(dpkg --print-architecture)}"
    case "$PKG_ARCH" in
        aarch64)
            PKG_ARCH="arm64"
            ;;
    esac
    
    # Use GIT_REF as version source
    local VERSION="${GIT_REF#v}"
    REVISION="${BUILD_NUMBER}${DEB_VERSION_SUFFIX}"
    FULL_VERSION="${VERSION}-${REVISION}"
    DEB_FILE="$OUTPUT_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}.deb"
    
    if [ -f "$DEB_FILE" ]; then
        print_info "Package info:"
        dpkg-deb -I "$DEB_FILE"
        
        print_info "Package contents (first 30 files):"
        # Fix: Suppress broken pipe error by redirecting stderr and ignoring exit code
        dpkg-deb -c "$DEB_FILE" 2>/dev/null | head -30 || true
        
        print_info "Package size:"
        ls -lh "$DEB_FILE"
        
        # Check for required files
        print_info "Checking for required files..."
        
        # Fix: Get contents once to avoid multiple broken pipes
        local CONTENTS=$(dpkg-deb -c "$DEB_FILE" 2>/dev/null)
        
        local required_files=(
            "./usr/lib/libwiringPi.so"
            "./usr/lib/libwiringPiDev.so"
            "./usr/bin/gpio"
            "./usr/include/wiringPi.h"
        )
        
        for file in "${required_files[@]}"; do
            if echo "$CONTENTS" | grep -q "$file"; then
                print_info "✓ Found: $file"
            else
                print_warning "✗ Missing: $file"
            fi
        done
        
        # Final GLIBC check on the packaged library
        print_info "Final GLIBC verification:"
        TEMP_FINAL=$(mktemp -d)
        dpkg-deb -x "$DEB_FILE" "$TEMP_FINAL"
        if [ -f "$TEMP_FINAL/usr/lib/libwiringPi.so.3.0" ]; then
            MAX_GLIBC=$(objdump -T "$TEMP_FINAL/usr/lib/libwiringPi.so.3.0" 2>/dev/null | grep GLIBC | sed 's/.*GLIBC_//' | sort -V | tail -1)
            print_info "Package requires GLIBC <= $MAX_GLIBC"
        fi
        rm -rf "$TEMP_FINAL"
    else
        print_error "Package file not found: $DEB_FILE"
        exit 1
    fi
}

# MAIN EXECUTION
print_message "Starting build for $PACKAGE_NAME"

# Show environment
[ -n "$ARCH" ] && print_info "Architecture: $ARCH"
[ -n "$DEBIAN_VERSION" ] && print_info "Debian version: $DEBIAN_VERSION"
[ -n "$OUTPUT_DIR" ] && print_info "Output directory: $OUTPUT_DIR"
[ -n "$BUILD_NUMBER" ] && print_info "Build number: $BUILD_NUMBER"
[ -n "$GIT_REF" ] && print_info "Git ref/version: $GIT_REF"

# Check if we should build for this architecture
check_architecture

# Build the package
clean_build
prepare_source
build_and_package
verify_package

print_message "Build completed!"

# Final version info using GIT_REF
VERSION="${GIT_REF#v}"
REVISION="${BUILD_NUMBER}${DEB_VERSION_SUFFIX:-}"
FULL_VERSION="${VERSION}-${REVISION}"
PKG_ARCH="${ARCH:-$(dpkg --print-architecture)}"
[ "$PKG_ARCH" = "aarch64" ] && PKG_ARCH="arm64"
print_info "Package: $OUTPUT_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}.deb"