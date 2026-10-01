#!/bin/bash
set -e

# MMDVM-Info package build script for Debian
# For GitHub Actions ONLY

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="mmdvminfo"
GITURL="https://github.com/g4klx/MMDVM-Info.git"
BUILD_DIR="build"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Functions
print_message() { echo -e "${GREEN}[BUILD]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

clean_build() {
    print_message "Cleaning build environment..."
    rm -rf "$BUILD_DIR" MMDVM-Info
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
}

prepare_source() {
    print_message "Cloning MMDVM-Info from $GITURL..."
    git clone "$GITURL" MMDVM-Info
    cd MMDVM-Info
    GIT_COMMIT=$(git rev-parse --short HEAD)
    GIT_COMMIT_FULL=$(git rev-parse HEAD)
    VERSION=$(git show -s --format=%cd --date=format:'%Y.%m.%d' HEAD)

    # Upstream relies on <unistd.h> being pulled in indirectly; include it
    # explicitly so the build doesn't depend on libc header internals.
    if patch -p1 -N --dry-run < "$SCRIPT_DIR/unistd.patch" >/dev/null 2>&1; then
        patch -p1 -N < "$SCRIPT_DIR/unistd.patch"
    fi
    cd ..

    print_info "Source version: $VERSION"
    print_info "Git commit: $GIT_COMMIT"
}

build_software() {
    print_message "Building MMDVM-Info..."
    cd MMDVM-Info

    make clean || true
    make -j$(nproc) all

    if [ ! -f "MMDVM-Info" ]; then
        print_error "Build failed - MMDVM-Info binary not created"
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

    REVISION="${BUILD_NUMBER}${DEB_VERSION_SUFFIX}"
    FULL_VERSION="${VERSION}-${REVISION}"
    PKG_ARCH="${ARCH:-$(dpkg --print-architecture)}"

    print_info "Package version: $FULL_VERSION"
    print_info "Architecture: $PKG_ARCH"
    print_info "Debian version: $DEBIAN_VERSION"
    print_info "Build number: $BUILD_NUMBER"

    PKG_DIR="$BUILD_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}"
    mkdir -p "$PKG_DIR/DEBIAN"
    mkdir -p "$PKG_DIR/usr/bin"
    mkdir -p "$PKG_DIR/usr/share/doc/mmdvminfo"
    mkdir -p "$PKG_DIR/usr/share/mmdvminfo"
    mkdir -p "$PKG_DIR/etc/mmdvminfo"
    mkdir -p "$PKG_DIR/lib/systemd/system"

    cp "MMDVM-Info/MMDVM-Info" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/MMDVM-Info"

    # The configuration template is package-owned and lives in /usr/share;
    # /etc/mmdvminfo/ ships empty and holds only user configuration. The
    # upstream template points [Configs] at a source-tree layout and lists
    # programs this repository doesn't ship, so point it at our paths.
    TEMPLATE="$PKG_DIR/usr/share/mmdvminfo/MMDVM-Info.ini.example"
    cp "MMDVM-Info/MMDVM-Info.ini" "$TEMPLATE"
    sed -i \
        -e 's|^APRSGateway=.*|APRSGateway=/etc/aprsclients/APRSGateway.ini|' \
        -e 's|^DAPNETGateway=.*|DAPNETGateway=/etc/pocsagclients/DAPNETGateway.ini|' \
        -e 's|^DGIdGateway=.*|DGIdGateway=/etc/ysfclients/DGIdGateway.ini|' \
        -e 's|^DMRGateway=.*|DMRGateway=/etc/dmrclients/DMRGateway.ini|' \
        -e 's|^DStarGateway=.*|DStarGateway=/etc/dstarclients/DStarGateway.ini|' \
        -e 's|^FMGateway=.*|FMGateway=/etc/fmclients/FMGateway.ini|' \
        -e 's|^MMDVM-Host=.*|MMDVM-Host=/etc/mmdvmhost/MMDVM-Host.ini|' \
        -e 's|^NXDNGateway=.*|NXDNGateway=/etc/nxdnclients/NXDNGateway.ini|' \
        -e 's|^P25Gateway=.*|P25Gateway=/etc/p25clients/P25Gateway.ini|' \
        -e 's|^YSFGateway=.*|YSFGateway=/etc/ysfclients/YSFGateway.ini|' \
        -e '/^MMDVM-CrossMode=/d' -e '/^MMDVM-IQ=/d' \
        -e '/^Program=MMDVM-CrossMode$/d' -e '/^Program=MMDVM-IQ$/d' \
        -e 's|^Program=MMDVMHost$|Program=MMDVM-Host\nProgram=MMDVM-Display|' \
        "$TEMPLATE"

    for doc in README.md README LICENSE COPYING; do
        if [ -f "MMDVM-Info/$doc" ]; then
            cp "MMDVM-Info/$doc" "$PKG_DIR/usr/share/doc/mmdvminfo/"
        fi
    done

    cat > "$PKG_DIR/lib/systemd/system/mmdvminfo.service" << 'EOF'
[Unit]
Description=MMDVM-Info Service
After=network.target mosquitto.service

[Service]
Type=simple
ExecStart=/usr/bin/MMDVM-Info /etc/mmdvminfo/MMDVM-Info.ini
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

    cat > "$PKG_DIR/usr/share/doc/mmdvminfo/changelog.Debian" << EOF
${PACKAGE_NAME} (${FULL_VERSION}) ${DEBIAN_VERSION}; urgency=medium

  * Package built from git commit ${GIT_COMMIT_FULL}
  * Built for Debian ${DEBIAN_VERSION}
  * Build number: ${BUILD_NUMBER}

 -- MW0MWZ <andy@mw0mwz.co.uk>  $(date -R)
EOF
    gzip -9n "$PKG_DIR/usr/share/doc/mmdvminfo/changelog.Debian"

    cat > "$PKG_DIR/usr/share/doc/mmdvminfo/copyright" << 'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: MMDVM-Info
Source: https://github.com/g4klx/MMDVM-Info

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

    case "$DEBIAN_VERSION" in
        trixie)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11), libmosquitto1t64"
            ;;
        *)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11), libmosquitto1"
            ;;
    esac

    cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: ${PACKAGE_NAME}
Version: ${FULL_VERSION}
Section: hamradio
Priority: optional
Architecture: ${PKG_ARCH}
Depends: ${DEPENDS}
Recommends: mosquitto
Maintainer: MW0MWZ <andy@mw0mwz.co.uk>
Description: Configuration, network and system information for MMDVM via MQTT
 MMDVM-Info answers requests over MQTT for the configuration of other MMDVM
 programs (with sensitive keys excluded), network addresses, running
 programs and CPU status. MMDVM-Display uses it to show host details.
 Built for Debian ${DEBIAN_VERSION}
 Git commit: ${GIT_COMMIT}
Homepage: https://github.com/g4klx/MMDVM-Info
EOF

    cat > "$PKG_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e

case "$1" in
    configure)
        if [ -d /run/systemd/system ]; then
            systemctl daemon-reload >/dev/null || true
        fi

        # Create configuration from the package template if missing
        mkdir -p /etc/mmdvminfo
        if [ ! -f /etc/mmdvminfo/MMDVM-Info.ini ] && [ -f /usr/share/mmdvminfo/MMDVM-Info.ini.example ]; then
            cp /usr/share/mmdvminfo/MMDVM-Info.ini.example /etc/mmdvminfo/MMDVM-Info.ini
            echo "Created /etc/mmdvminfo/MMDVM-Info.ini from template"
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

    cat > "$PKG_DIR/DEBIAN/postrm" << 'EOF'
#!/bin/sh
set -e

case "$1" in
    purge)
        if [ -d /etc/mmdvminfo ]; then
            rmdir --ignore-fail-on-non-empty /etc/mmdvminfo || true
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

    cd "$PKG_DIR"
    find . -type f ! -path './DEBIAN/*' -exec md5sum {} \; | sed 's|\./||' > DEBIAN/md5sums
    cd - > /dev/null

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
        dpkg-deb -c "$DEB_FILE"
        print_info "Package size:"
        ls -lh "$DEB_FILE"
    else
        print_error "Package file not found: $DEB_FILE"
        exit 1
    fi
}

# MAIN EXECUTION
print_message "Starting build for $PACKAGE_NAME"

[ -n "$ARCH" ] && print_info "Architecture: $ARCH"
[ -n "$DEBIAN_VERSION" ] && print_info "Debian version: $DEBIAN_VERSION"
[ -n "$OUTPUT_DIR" ] && print_info "Output directory: $OUTPUT_DIR"
[ -n "$BUILD_NUMBER" ] && print_info "Build number: $BUILD_NUMBER"

clean_build
prepare_source
build_software
create_package
verify_package

print_message "Build completed!"
print_info "Package: $OUTPUT_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}.deb"
