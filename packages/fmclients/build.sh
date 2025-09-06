#!/bin/bash
set -e

# FM Clients package build script for Debian
# For GitHub Actions ONLY

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="fmclients"
GITURL="https://github.com/g4klx/FMGateway.git"
BUILD_DIR="build"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Functions
print_message() { echo -e "${GREEN}[BUILD]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

clean_build() {
    print_message "Cleaning build environment..."
    rm -rf "$BUILD_DIR" FMGateway
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
}

prepare_source() {
    print_message "Cloning source from $GITURL..."
    git clone "$GITURL" FMGateway
    cd FMGateway
    GIT_COMMIT=$(git rev-parse --short HEAD)
    GIT_COMMIT_FULL=$(git rev-parse HEAD)
    VERSION=$(git show -s --format=%cd --date=format:'%Y.%m.%d' HEAD)
    cd ..
    
    print_info "Source version: $VERSION"
    print_info "Git commit: $GIT_COMMIT"
}

build_software() {
    print_message "Building FMGateway..."
    cd FMGateway
    
    make clean || true
    
    # Standard build flags
    export CFLAGS="-O2 -Wall -g"
    export CXXFLAGS="-O2 -Wall -g"
    
    make -j$(nproc) all
    
    if [ ! -f "FMGateway" ]; then
        print_error "Build failed - FMGateway binary not created"
        exit 1
    fi
    
    cd ..
    print_message "Build completed"
}

create_package() {
    DEBIAN_VERSION="${DEBIAN_VERSION:-bookworm}"
    DEB_VERSION_SUFFIX="${DEB_VERSION_SUFFIX:-}"
    BUILD_NUMBER="${BUILD_NUMBER:-1}"
    print_message "Creating Debian package..."
    
    # Use build number for revision to handle multiple builds
    REVISION="${BUILD_NUMBER}${DEB_VERSION_SUFFIX}"
    FULL_VERSION="${VERSION}-${REVISION}"
    PKG_ARCH="${ARCH:-$(dpkg --print-architecture)}"
    
    print_info "Package version: $FULL_VERSION"
    print_info "Architecture: $PKG_ARCH"
    print_info "Debian version: $DEBIAN_VERSION"
    print_info "Build number: $BUILD_NUMBER"
    
    # Create package directory structure
    PKG_DIR="$BUILD_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}"
    mkdir -p "$PKG_DIR/DEBIAN"
    mkdir -p "$PKG_DIR/usr/bin"
    mkdir -p "$PKG_DIR/usr/share/doc/fmclients"
    mkdir -p "$PKG_DIR/etc/fmclients"
    
    # Copy binary
    cp "FMGateway/FMGateway" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/FMGateway"
    
    # Copy config if exists
    if [ -f "FMGateway/FMGateway.ini" ]; then
        cp "FMGateway/FMGateway.ini" "$PKG_DIR/etc/fmclients/FMGateway.ini"
    fi
    
    # Copy docs
    for doc in README.md README LICENSE COPYING; do
        if [ -f "FMGateway/$doc" ]; then
            cp "FMGateway/$doc" "$PKG_DIR/usr/share/doc/fmclients/"
        fi
    done
    
    # Create changelog
    cat > "$PKG_DIR/usr/share/doc/fmclients/changelog.Debian" << EOF
${PACKAGE_NAME} (${FULL_VERSION}) ${DEBIAN_VERSION}; urgency=medium

  * Package built from git commit ${GIT_COMMIT_FULL}
  * Built for Debian ${DEBIAN_VERSION}
  * Build number: ${BUILD_NUMBER}

 -- MW0MWZ <andy@mw0mwz.co.uk>  $(date -R)
EOF
    gzip -9n "$PKG_DIR/usr/share/doc/fmclients/changelog.Debian"
    
    # Create copyright
    cat > "$PKG_DIR/usr/share/doc/fmclients/copyright" << 'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: FMGateway
Source: https://github.com/g4klx/FMGateway

Files: *
Copyright: Jonathan Naylor G4KLX and contributors
License: GPL-2+
EOF
    
    # Set dependencies based on Debian version
    case "$DEBIAN_VERSION" in
        bullseye)
            DEPENDS="libc6 (>= 2.31), libgcc-s1 (>= 3.0), libstdc++6 (>= 5.2), libmd0 (>= 1.0.3)"
            ;;
        bookworm)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11), libmd0 (>= 1.0.3)"
            ;;
        trixie)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11), libmd0 (>= 1.0.3)"
            ;;
        *)
            DEPENDS="libc6 (>= 2.31), libgcc-s1 (>= 3.0), libstdc++6 (>= 5.2), libmd0 (>= 1.0.3)"
            ;;
    esac
    
    # Create control file
    cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: ${PACKAGE_NAME}
Version: ${FULL_VERSION}
Section: hamradio
Priority: optional
Architecture: ${PKG_ARCH}
Depends: ${DEPENDS}
Maintainer: MW0MWZ <andy@mw0mwz.co.uk>
Description: FM Clients for Amateur Radio
 FM repeater gateway for digital modes
 Built for Debian ${DEBIAN_VERSION}
 Git commit: ${GIT_COMMIT}
Homepage: https://github.com/g4klx/FMGateway
EOF
    
    # Create md5sums
    cd "$PKG_DIR"
    find . -type f ! -path './DEBIAN/*' -exec md5sum {} \; | sed 's|\./||' > DEBIAN/md5sums
    cd - > /dev/null
    
    # Create conffiles if config exists
    if [ -f "$PKG_DIR/etc/fmclients/FMGateway.ini" ]; then
        echo "/etc/fmclients/FMGateway.ini" > "$PKG_DIR/DEBIAN/conffiles"
    fi
    
    # Build the package
    print_message "Building .deb package..."
    fakeroot dpkg-deb --build "$PKG_DIR"
    
    mv "$BUILD_DIR"/*.deb "$OUTPUT_DIR/"
    
    DEB_FILE="${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}.deb"
    print_message "Package created: ${DEB_FILE}"
}

verify_package() {
    print_message "Verifying package..."
    
    PKG_ARCH="${ARCH:-$(dpkg --print-architecture)}"
    DEB_FILE="$OUTPUT_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}.deb"
    
    if [ -f "$DEB_FILE" ]; then
        print_info "Package info:"
        dpkg-deb -I "$DEB_FILE"
        print_info "Package size:"
        ls -lh "$DEB_FILE"
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

# Build the package
clean_build
prepare_source
build_software
create_package
verify_package

print_message "Build completed!"
print_info "Package: $OUTPUT_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}.deb"