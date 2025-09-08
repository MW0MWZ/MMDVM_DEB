#!/bin/bash
set -e

# YSF Clients package build script for Debian
# For GitHub Actions ONLY
# Builds YSFGateway, YSFParrot, DGIdGateway and MMDVM_CM cross-mode converters

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="ysfclients"
YSFCLIENTS_GITURL="https://github.com/g4klx/YSFClients.git"
MMDVM_CM_GITURL="https://github.com/nostar/MMDVM_CM.git"
BUILD_DIR="build"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Functions
print_message() { echo -e "${GREEN}[BUILD]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

clean_build() {
    print_message "Cleaning build environment..."
    rm -rf "$BUILD_DIR" YSFClients MMDVM_CM
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
}

prepare_source() {
    print_message "Cloning YSFClients from $YSFCLIENTS_GITURL..."
    git clone "$YSFCLIENTS_GITURL" YSFClients
    
    cd YSFClients
    YSFCLIENTS_COMMIT=$(git rev-parse --short HEAD)
    YSFCLIENTS_COMMIT_FULL=$(git rev-parse HEAD)
    VERSION=$(git show -s --format=%cd --date=format:'%Y.%m.%d' HEAD)
    cd ..
    
    print_message "Cloning MMDVM_CM from $MMDVM_CM_GITURL..."
    git clone "$MMDVM_CM_GITURL" MMDVM_CM
    
    cd MMDVM_CM
    MMDVM_CM_COMMIT=$(git rev-parse --short HEAD)
    MMDVM_CM_COMMIT_FULL=$(git rev-parse HEAD)
    cd ..
    
    print_info "Source version: $VERSION"
    print_info "YSFClients commit: $YSFCLIENTS_COMMIT"
    print_info "MMDVM_CM commit: $MMDVM_CM_COMMIT"
}

build_software() {
    print_message "Building YSFClients components..."
    
    cd YSFClients
    
    # Standard build flags
    export CFLAGS="-O2 -Wall -g"
    export CXXFLAGS="-O2 -Wall -g"
    
    # Build YSFGateway
    if [ -d "YSFGateway" ]; then
        print_info "Building YSFGateway..."
        cd YSFGateway
        make clean || true
        make -j$(nproc) all
        cd ..
    fi
    
    # Build YSFParrot
    if [ -d "YSFParrot" ]; then
        print_info "Building YSFParrot..."
        cd YSFParrot
        make clean || true
        make -j$(nproc) all
        cd ..
    fi
    
    # Build DGIdGateway
    if [ -d "DGIdGateway" ]; then
        print_info "Building DGIdGateway..."
        cd DGIdGateway
        make clean || true
        make -j$(nproc) all
        cd ..
    fi
    
    cd ..
    
    print_message "Building MMDVM_CM cross-mode converters..."
    
    cd MMDVM_CM
    
    # Build YSF2DMR
    if [ -d "YSF2DMR" ]; then
        print_info "Building YSF2DMR..."
        cd YSF2DMR
        make clean || true
        make -j$(nproc) all
        cd ..
    fi
    
    # Build YSF2NXDN
    if [ -d "YSF2NXDN" ]; then
        print_info "Building YSF2NXDN..."
        cd YSF2NXDN
        make clean || true
        make -j$(nproc) all
        cd ..
    fi
    
    # Build YSF2P25
    if [ -d "YSF2P25" ]; then
        print_info "Building YSF2P25..."
        cd YSF2P25
        make clean || true
        make -j$(nproc) all
        cd ..
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
    
    # Create package directory structure - use absolute path
    PKG_DIR="$(pwd)/$BUILD_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}"
    mkdir -p "$PKG_DIR/DEBIAN"
    mkdir -p "$PKG_DIR/usr/bin"
    mkdir -p "$PKG_DIR/usr/share/doc/ysfclients"
    mkdir -p "$PKG_DIR/usr/share/ysfclients"
    mkdir -p "$PKG_DIR/etc/ysfclients"
    mkdir -p "$PKG_DIR/lib/systemd/system"
    
    # Copy YSFClients binaries and configs
    cd YSFClients
    
    # YSFGateway
    if [ -f "YSFGateway/YSFGateway" ]; then
        cp "YSFGateway/YSFGateway" "$PKG_DIR/usr/bin/"
        chmod 755 "$PKG_DIR/usr/bin/YSFGateway"
    fi
    if [ -f "YSFGateway/YSFGateway.ini" ]; then
        cp "YSFGateway/YSFGateway.ini" "$PKG_DIR/etc/ysfclients/YSFGateway.ini"
    fi
    
    # YSFParrot
    if [ -f "YSFParrot/YSFParrot" ]; then
        cp "YSFParrot/YSFParrot" "$PKG_DIR/usr/bin/"
        chmod 755 "$PKG_DIR/usr/bin/YSFParrot"
    fi
    if [ -f "YSFParrot/YSFParrot.ini" ]; then
        cp "YSFParrot/YSFParrot.ini" "$PKG_DIR/etc/ysfclients/YSFParrot.ini"
    fi
    
    # DGIdGateway
    if [ -f "DGIdGateway/DGIdGateway" ]; then
        cp "DGIdGateway/DGIdGateway" "$PKG_DIR/usr/bin/"
        chmod 755 "$PKG_DIR/usr/bin/DGIdGateway"
    fi
    if [ -f "DGIdGateway/DGIdGateway.ini" ]; then
        cp "DGIdGateway/DGIdGateway.ini" "$PKG_DIR/etc/ysfclients/DGIdGateway.ini"
    fi
    
    # Copy data files
    for datafile in YSFHosts.txt FCSHosts.txt FCSRooms.txt; do
        for dir in YSFGateway YSFParrot DGIdGateway; do
            if [ -f "$dir/$datafile" ]; then
                cp "$dir/$datafile" "$PKG_DIR/usr/share/ysfclients/$datafile"
                break
            fi
        done
    done
    
    cd ..
    
    # Copy MMDVM_CM binaries and configs
    cd MMDVM_CM
    
    # YSF2DMR
    if [ -f "YSF2DMR/YSF2DMR" ]; then
        cp "YSF2DMR/YSF2DMR" "$PKG_DIR/usr/bin/"
        chmod 755 "$PKG_DIR/usr/bin/YSF2DMR"
    fi
    if [ -f "YSF2DMR/YSF2DMR.ini" ]; then
        cp "YSF2DMR/YSF2DMR.ini" "$PKG_DIR/etc/ysfclients/YSF2DMR.ini"
    fi
    
    # YSF2NXDN
    if [ -f "YSF2NXDN/YSF2NXDN" ]; then
        cp "YSF2NXDN/YSF2NXDN" "$PKG_DIR/usr/bin/"
        chmod 755 "$PKG_DIR/usr/bin/YSF2NXDN"
    fi
    if [ -f "YSF2NXDN/YSF2NXDN.ini" ]; then
        cp "YSF2NXDN/YSF2NXDN.ini" "$PKG_DIR/etc/ysfclients/YSF2NXDN.ini"
    fi
    
    # YSF2P25
    if [ -f "YSF2P25/YSF2P25" ]; then
        cp "YSF2P25/YSF2P25" "$PKG_DIR/usr/bin/"
        chmod 755 "$PKG_DIR/usr/bin/YSF2P25"
    fi
    if [ -f "YSF2P25/YSF2P25.ini" ]; then
        cp "YSF2P25/YSF2P25.ini" "$PKG_DIR/etc/ysfclients/YSF2P25.ini"
    fi
    
    # Copy ID files
    for id_file in DMRIds.dat NXDNIds.dat TGList_BM.txt TGList_FCS.txt; do
        for dir in YSF2DMR YSF2NXDN YSF2P25; do
            if [ -f "$dir/$id_file" ]; then
                cp "$dir/$id_file" "$PKG_DIR/usr/share/ysfclients/$id_file"
                break
            fi
        done
    done
    
    cd ..
    
    # Copy documentation
    for doc in README.md README LICENSE COPYING; do
        if [ -f "YSFClients/$doc" ]; then
            cp "YSFClients/$doc" "$PKG_DIR/usr/share/doc/ysfclients/"
        fi
        if [ -f "MMDVM_CM/$doc" ]; then
            cp "MMDVM_CM/$doc" "$PKG_DIR/usr/share/doc/ysfclients/MMDVM_CM-$doc"
        fi
    done
    
    # Create systemd service files
    cat > "$PKG_DIR/lib/systemd/system/ysfgateway.service" << 'EOF'
[Unit]
Description=YSF Gateway Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/YSFGateway /etc/ysfclients/YSFGateway.ini
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

    cat > "$PKG_DIR/lib/systemd/system/dgidgateway.service" << 'EOF'
[Unit]
Description=DGId Gateway Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/DGIdGateway /etc/ysfclients/DGIdGateway.ini
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF
    
    # Create changelog
    cat > "$PKG_DIR/usr/share/doc/ysfclients/changelog.Debian" << EOF
${PACKAGE_NAME} (${FULL_VERSION}) ${DEBIAN_VERSION}; urgency=medium

  * Package built from git commits:
    - YSFClients: ${YSFCLIENTS_COMMIT_FULL}
    - MMDVM_CM: ${MMDVM_CM_COMMIT_FULL}
  * Built for Debian ${DEBIAN_VERSION}
  * Build number: ${BUILD_NUMBER}

 -- MW0MWZ <andy@mw0mwz.co.uk>  $(date -R)
EOF
    gzip -9n "$PKG_DIR/usr/share/doc/ysfclients/changelog.Debian"
    
    # Create copyright
    cat > "$PKG_DIR/usr/share/doc/ysfclients/copyright" << 'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: YSFClients
Source: https://github.com/g4klx/YSFClients

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
Recommends: ntp | chrony
Maintainer: MW0MWZ <andy@mw0mwz.co.uk>
Description: YSF Clients for Amateur Radio
 YSF Gateway, Parrot, DGId Gateway and Cross-Mode converters for
 digital communications using Yaesu System Fusion (YSF) protocol.
 .
 This package includes:
  - YSFGateway: Gateway for YSF networks
  - YSFParrot: Echo/parrot server for testing
  - DGIdGateway: Digital Group ID Gateway
  - YSF2DMR: Cross-mode converter from YSF to DMR
  - YSF2NXDN: Cross-mode converter from YSF to NXDN
  - YSF2P25: Cross-mode converter from YSF to P25
 .
 Built for Debian ${DEBIAN_VERSION}
 YSFClients commit: ${YSFCLIENTS_COMMIT}
 MMDVM_CM commit: ${MMDVM_CM_COMMIT}
Homepage: https://github.com/g4klx/YSFClients
EOF
    
    # Create postinst script for systemd
    cat > "$PKG_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e

case "$1" in
    configure)
        # Reload systemd to pick up the new services
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
        if [ -d /etc/ysfclients ]; then
            rmdir --ignore-fail-on-non-empty /etc/ysfclients || true
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
    
    # Create conffiles list
    > "$PKG_DIR/DEBIAN/conffiles"
    for conf in YSFGateway YSFParrot DGIdGateway YSF2DMR YSF2NXDN YSF2P25; do
        if [ -f "$PKG_DIR/etc/ysfclients/${conf}.ini" ]; then
            echo "/etc/ysfclients/${conf}.ini" >> "$PKG_DIR/DEBIAN/conffiles"
        fi
    done
    
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
        print_info "Package contents (first 30 files):"
        dpkg-deb -c "$DEB_FILE" | head -30
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