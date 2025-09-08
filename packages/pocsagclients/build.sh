#!/bin/bash
set -e

# POCSAG Clients package build script for Debian
# For GitHub Actions ONLY

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="pocsagclients"
GITURL="https://github.com/g4klx/DAPNETGateway.git"
BUILD_DIR="build"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Functions
print_message() { echo -e "${GREEN}[BUILD]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

clean_build() {
    print_message "Cleaning build environment..."
    rm -rf "$BUILD_DIR" DAPNETGateway
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
}

prepare_source() {
    print_message "Cloning source from $GITURL..."
    git clone "$GITURL" DAPNETGateway
    cd DAPNETGateway
    GIT_COMMIT=$(git rev-parse --short HEAD)
    GIT_COMMIT_FULL=$(git rev-parse HEAD)
    VERSION=$(git show -s --format=%cd --date=format:'%Y.%m.%d' HEAD)
    cd ..
    
    print_info "Source version: $VERSION"
    print_info "Git commit: $GIT_COMMIT"
}

build_software() {
    print_message "Building DAPNETGateway..."
    cd DAPNETGateway
    
    make clean || true
    
    # Standard build flags
    export CFLAGS="-O2 -Wall -g"
    export CXXFLAGS="-O2 -Wall -g"
    
    make -j$(nproc) all
    
    if [ ! -f "DAPNETGateway" ]; then
        print_error "Build failed - DAPNETGateway binary not created"
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
    mkdir -p "$PKG_DIR/usr/share/doc/pocsagclients"
    mkdir -p "$PKG_DIR/etc/pocsagclients"
    mkdir -p "$PKG_DIR/lib/systemd/system"
    
    # Copy binary
    cp "DAPNETGateway/DAPNETGateway" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/DAPNETGateway"
    
    # Copy config if exists
    if [ -f "DAPNETGateway/DAPNETGateway.ini" ]; then
        cp "DAPNETGateway/DAPNETGateway.ini" "$PKG_DIR/etc/pocsagclients/DAPNETGateway.ini"
    fi
    
    # Create systemd service file
    cat > "$PKG_DIR/lib/systemd/system/dapnetgateway.service" << 'EOF'
[Unit]
Description=DAPNET Gateway Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/DAPNETGateway /etc/pocsagclients/DAPNETGateway.ini
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF
    
    # Copy docs
    for doc in README.md README LICENSE COPYING; do
        if [ -f "DAPNETGateway/$doc" ]; then
            cp "DAPNETGateway/$doc" "$PKG_DIR/usr/share/doc/pocsagclients/"
        fi
    done
    
    # Create changelog
    cat > "$PKG_DIR/usr/share/doc/pocsagclients/changelog.Debian" << EOF
${PACKAGE_NAME} (${FULL_VERSION}) ${DEBIAN_VERSION}; urgency=medium

  * Package built from git commit ${GIT_COMMIT_FULL}
  * Built for Debian ${DEBIAN_VERSION}
  * Build number: ${BUILD_NUMBER}

 -- MW0MWZ <andy@mw0mwz.co.uk>  $(date -R)
EOF
    gzip -9n "$PKG_DIR/usr/share/doc/pocsagclients/changelog.Debian"
    
    # Create copyright
    cat > "$PKG_DIR/usr/share/doc/pocsagclients/copyright" << 'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: DAPNETGateway
Source: https://github.com/g4klx/DAPNETGateway

Files: *
Copyright: Jonathan Naylor G4KLX and contributors
License: GPL-2+
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 .
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU General Public License for more details.
 .
 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
EOF
    
    # Set dependencies based on Debian version
    case "$DEBIAN_VERSION" in
        bullseye)
            DEPENDS="libc6 (>= 2.31), libgcc-s1 (>= 3.0), libstdc++6 (>= 5.2)"
            ;;
        bookworm)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11)"
            ;;
        trixie)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11)"
            ;;
        *)
            DEPENDS="libc6 (>= 2.31), libgcc-s1 (>= 3.0), libstdc++6 (>= 5.2)"
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
Description: POCSAG/DAPNET Gateway for Amateur Radio
 DAPNET Gateway for POCSAG paging network
 Supports connection to the DAPNET amateur radio paging network
 Built for Debian ${DEBIAN_VERSION}
 Git commit: ${GIT_COMMIT}
Homepage: https://github.com/g4klx/DAPNETGateway
EOF
    
    # Create postinst script for systemd
    cat > "$PKG_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e

case "$1" in
    configure)
        # Reload systemd to pick up the new service
        if [ -d /run/systemd/system ]; then
            systemctl daemon-reload >/dev/null || true
        fi
        ;;
    abort-upgrade|abort-remove|abort-deconfigure)
        ;;
    *)
        echo "postinst called with unknown argument \`$1'" >&2
        exit 1
        ;;
esac

#DEBHELPER#

exit 0
EOF
    chmod 755 "$PKG_DIR/DEBIAN/postinst"
    
    # Create postrm script for cleanup
    cat > "$PKG_DIR/DEBIAN/postrm" << 'EOF'
#!/bin/sh
set -e

case "$1" in
    purge)
        # Remove config directory if empty
        if [ -d /etc/pocsagclients ]; then
            rmdir --ignore-fail-on-non-empty /etc/pocsagclients || true
        fi
        ;;
    remove|upgrade|failed-upgrade|abort-install|abort-upgrade|disappear)
        ;;
    *)
        echo "postrm called with unknown argument \`$1'" >&2
        exit 1
        ;;
esac

#DEBHELPER#

exit 0
EOF
    chmod 755 "$PKG_DIR/DEBIAN/postrm"
    
    # Create md5sums
    cd "$PKG_DIR"
    find . -type f ! -path './DEBIAN/*' -exec md5sum {} \; | sed 's|\./||' > DEBIAN/md5sums
    cd - > /dev/null
    
    # Create conffiles if config exists
    if [ -f "$PKG_DIR/etc/pocsagclients/DAPNETGateway.ini" ]; then
        echo "/etc/pocsagclients/DAPNETGateway.ini" > "$PKG_DIR/DEBIAN/conffiles"
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
        print_info "Package contents:"
        dpkg-deb -c "$DEB_FILE" | head -20
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
[ -n "$BUILD_NUMBER" ] && print_info "Build number: $BUILD_NUMBER"

# Build the package
clean_build
prepare_source
build_software
create_package
verify_package

print_message "Build completed!"
print_info "Package: $OUTPUT_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}.deb"