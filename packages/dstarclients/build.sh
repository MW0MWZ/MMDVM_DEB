#!/bin/bash
set -e

# D-Star Clients package build script for Debian
# For GitHub Actions ONLY
# Version: 2.0.0 - Replaced ircDDBGateway with DStarGateway

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="dstarclients"
GITURL="https://github.com/g4klx/DStarGateway.git"
BUILD_DIR="build"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Functions
print_message() { echo -e "${GREEN}[BUILD]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

clean_build() {
    print_message "Cleaning build environment..."
    rm -rf "$BUILD_DIR" DStarGateway
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
}

prepare_source() {
    print_message "Cloning DStarGateway from $GITURL..."
    git clone "$GITURL" DStarGateway
    cd DStarGateway
    GIT_COMMIT=$(git rev-parse --short HEAD)
    GIT_COMMIT_FULL=$(git rev-parse HEAD)
    VERSION=$(git show -s --format=%cd --date=format:'%Y.%m.%d' HEAD)
    cd ..

    print_info "Source version: $VERSION"
    print_info "Git commit: $GIT_COMMIT"
}

build_software() {
    print_message "Building DStarGateway..."
    cd DStarGateway

    make clean || true

    # Build with Debian-appropriate paths compiled in
    make -j$(nproc) \
        CFG_DIR=/etc/dstarclients/ \
        DATA_DIR=/usr/share/dstarclients/ \
        LOG_DIR=/var/log/dstarclients/ \
        BIN_DIR=/usr/bin/ \
        all

    # Binaries are built into their respective subdirectories
    BINARY_MAP="DStarGateway/dstargateway DGWRemoteControl/dgwremotecontrol DGWTextTransmit/dgwtexttransmit DGWTimeServer/dgwtimeserver DGWVoiceTransmit/dgwvoicetransmit"
    for binary_path in $BINARY_MAP; do
        if [ ! -f "$binary_path" ]; then
            print_error "Build failed - $binary_path not created"
            exit 1
        fi
    done

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
    PKG_DIR="$(pwd)/$BUILD_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}"
    mkdir -p "$PKG_DIR/DEBIAN"
    mkdir -p "$PKG_DIR/usr/bin"
    mkdir -p "$PKG_DIR/usr/share/doc/dstarclients"
    mkdir -p "$PKG_DIR/usr/share/dstarclients"
    mkdir -p "$PKG_DIR/etc/dstarclients"
    mkdir -p "$PKG_DIR/lib/systemd/system"
    mkdir -p "$PKG_DIR/var/log/dstarclients"

    # Copy binaries from their subdirectories
    BINARY_MAP="DStarGateway/dstargateway DGWRemoteControl/dgwremotecontrol DGWTextTransmit/dgwtexttransmit DGWTimeServer/dgwtimeserver DGWVoiceTransmit/dgwvoicetransmit"
    for binary_path in $BINARY_MAP; do
        bin=$(basename "$binary_path")
        cp "DStarGateway/$binary_path" "$PKG_DIR/usr/bin/"
        chmod 755 "$PKG_DIR/usr/bin/$bin"
        print_info "Installed: $bin"
    done

    # Copy config file
    cp "DStarGateway/DStarGateway.ini" "$PKG_DIR/etc/dstarclients/DStarGateway.ini"

    # Copy data files
    if [ -d "DStarGateway/Data" ]; then
        print_info "Copying data files..."
        cp -r DStarGateway/Data/* "$PKG_DIR/usr/share/dstarclients/" 2>/dev/null || true
    fi

    # Copy docs
    for doc in README.md README LICENSE COPYING; do
        if [ -f "DStarGateway/$doc" ]; then
            cp "DStarGateway/$doc" "$PKG_DIR/usr/share/doc/dstarclients/"
        fi
    done

    # Create dstargateway systemd service
    cat > "$PKG_DIR/lib/systemd/system/dstargateway.service" << 'EOF'
[Unit]
Description=D-Star Gateway Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/dstargateway /etc/dstarclients/DStarGateway.ini
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup
WorkingDirectory=/var/lib/dstarclients

[Install]
WantedBy=multi-user.target
EOF

    # Create dgwtimeserver systemd service
    cat > "$PKG_DIR/lib/systemd/system/dgwtimeserver.service" << 'EOF'
[Unit]
Description=D-Star Gateway Time Server
After=network-online.target dstargateway.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/dgwtimeserver /etc/dstarclients/DStarGateway.ini
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup
WorkingDirectory=/var/lib/dstarclients

[Install]
WantedBy=multi-user.target
EOF

    # Create changelog
    cat > "$PKG_DIR/usr/share/doc/dstarclients/changelog.Debian" << EOF
${PACKAGE_NAME} (${FULL_VERSION}) ${DEBIAN_VERSION}; urgency=medium

  * Package built from git commit ${GIT_COMMIT_FULL}
  * Built for Debian ${DEBIAN_VERSION}
  * Build number: ${BUILD_NUMBER}
  * Replaced ircDDBGateway with DStarGateway (wxWidgets-free)

 -- MW0MWZ <andy@mw0mwz.co.uk>  $(date -R)
EOF
    gzip -9n "$PKG_DIR/usr/share/doc/dstarclients/changelog.Debian"

    # Create copyright
    cat > "$PKG_DIR/usr/share/doc/dstarclients/copyright" << 'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: DStarGateway
Source: https://github.com/g4klx/DStarGateway

Files: *
Copyright: Jonathan Naylor G4KLX and contributors
License: GPL-2+
EOF

    # Set dependencies based on Debian version
    case "$DEBIAN_VERSION" in
        trixie)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11), libcurl4t64, libmosquitto1t64"
            ;;
        *)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11), libcurl4, libmosquitto1"
            ;;
    esac

    RECOMMENDS="mosquitto"

    # Create control file
    cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: ${PACKAGE_NAME}
Version: ${FULL_VERSION}
Section: hamradio
Priority: optional
Architecture: ${PKG_ARCH}
Depends: ${DEPENDS}
Recommends: ${RECOMMENDS}
Maintainer: MW0MWZ <andy@mw0mwz.co.uk>
Description: D-Star Gateway and Tools
 D-Star Gateway for digital voice amateur radio
 Includes gateway, time server, remote control, and transmit tools
 .
 Built for Debian ${DEBIAN_VERSION}
 Git commit: ${GIT_COMMIT}
Homepage: https://github.com/g4klx/DStarGateway
EOF

    # Create postinst script
    cat > "$PKG_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e

case "$1" in
    configure)
        # Reload systemd to pick up the new services
        if [ -d /run/systemd/system ]; then
            systemctl daemon-reload >/dev/null || true
        fi

        # Create log directory with correct permissions
        if [ ! -d /var/log/dstarclients ]; then
            mkdir -p /var/log/dstarclients
            chown nobody:nogroup /var/log/dstarclients || true
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

    # Create postrm script
    cat > "$PKG_DIR/DEBIAN/postrm" << 'EOF'
#!/bin/sh
set -e

case "$1" in
    purge)
        # Remove config directory if empty
        if [ -d /etc/dstarclients ]; then
            rmdir --ignore-fail-on-non-empty /etc/dstarclients || true
        fi
        # Remove log directory if empty
        if [ -d /var/log/dstarclients ]; then
            rmdir --ignore-fail-on-non-empty /var/log/dstarclients || true
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

    # Create prerm script for stopping services
    cat > "$PKG_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/sh
set -e

case "$1" in
    remove|upgrade|deconfigure)
        if [ -d /run/systemd/system ]; then
            systemctl stop dgwtimeserver.service >/dev/null 2>&1 || true
            systemctl disable dgwtimeserver.service >/dev/null 2>&1 || true
            systemctl stop dstargateway.service >/dev/null 2>&1 || true
            systemctl disable dstargateway.service >/dev/null 2>&1 || true
        fi
        ;;
    failed-upgrade)
        ;;
    *)
        echo "prerm called with unknown argument \`$1'" >&2
        exit 1
        ;;
esac

#DEBHELPER#

exit 0
EOF
    chmod 755 "$PKG_DIR/DEBIAN/prerm"

    # Create md5sums
    cd "$PKG_DIR"
    find . -type f ! -path './DEBIAN/*' -exec md5sum {} \; | sed 's|\./||' > DEBIAN/md5sums
    cd - > /dev/null

    # Create conffiles
    echo "/etc/dstarclients/DStarGateway.ini" > "$PKG_DIR/DEBIAN/conffiles"

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

        # Check for main binary
        if dpkg-deb -c "$DEB_FILE" | grep -q "usr/bin/dstargateway"; then
            print_info "dstargateway binary found in package"
        else
            print_warning "dstargateway binary not found in package"
        fi
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
