#!/bin/bash
set -e

# D-Star Clients package build script for Debian
# For GitHub Actions ONLY

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="dstarclients"
GITURL="https://github.com/g4klx/ircDDBGateway.git"
BUILD_DIR="build"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Functions
print_message() { echo -e "${GREEN}[BUILD]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

clean_build() {
    print_message "Cleaning build environment..."
    rm -rf "$BUILD_DIR" ircDDBGateway
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
}

prepare_source() {
    print_message "Cloning ircDDBGateway from $GITURL..."
    git clone "$GITURL" ircDDBGateway
    cd ircDDBGateway
    GIT_COMMIT=$(git rev-parse --short HEAD)
    GIT_COMMIT_FULL=$(git rev-parse HEAD)
    VERSION=$(git show -s --format=%cd --date=format:'%Y.%m.%d' HEAD)
    cd ..
    
    print_info "Source version: $VERSION"
    print_info "Git commit: $GIT_COMMIT"
}

patch_makefiles() {
    print_message "Patching Makefiles for Debian build..."
    cd ircDDBGateway
    
    # Patch the main Makefile to set proper directories and use correct wx-config
    sed -i 's|export DATADIR ?= /usr/share/ircddbgateway|export DATADIR ?= /usr/share/dstarclients|' Makefile
    sed -i 's|export BINDIR  ?= /usr/bin|export BINDIR  ?= /usr/bin|' Makefile
    
    # Ensure wx-config is used properly
    sed -i 's|export CXX     := $(shell wx-config --cxx)|export CXX     := g++|' Makefile
    
    # Add -fPIC for shared library compatibility if needed
    sed -i 's|export CFLAGS  := -O2 -Wall|export CFLAGS  := -O2 -Wall -fPIC|' Makefile
    
    # For daemon builds, we need to add -DwxUSE_GUI=0
    for dir in ircDDBGateway APRSTransmit RemoteControl StarNetServer TextTransmit TimerControl TimeServer VoiceTransmit; do
        if [ -f "$dir/Makefile" ]; then
            # Add -DwxUSE_GUI=0 to daemon builds if not already present
            sed -i 's|$(CFLAGS)|$(CFLAGS) -DwxUSE_GUI=0|g' "$dir/Makefile" 2>/dev/null || true
        fi
    done
    
    cd ..
}

build_software() {
    print_message "Building ircDDBGateway components..."
    cd ircDDBGateway
    
    # Set build environment
    export BUILD="release"
    export DATADIR="/usr/share/dstarclients"
    export LOGDIR="/var/log"
    export CONFDIR="/etc/dstarclients"
    export BINDIR="/usr/bin"
    
    # Clean first
    make clean || true
    
    # Build everything using the main Makefile
    print_info "Running make with $(nproc) jobs..."
    make -j$(nproc) all
    
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
    mkdir -p "$PKG_DIR/usr/share/doc/dstarclients"
    mkdir -p "$PKG_DIR/usr/share/dstarclients"
    mkdir -p "$PKG_DIR/etc/dstarclients"
    mkdir -p "$PKG_DIR/lib/systemd/system"
    
    # Copy binaries
    cd ircDDBGateway
    
    # List of expected binaries
    BINARIES="ircDDBGateway/ircddbgatewayd TimeServer/timeserverd RemoteControl/remotecontrold 
              StarNetServer/starnetserverd TextTransmit/texttransmitd VoiceTransmit/voicetransmitd
              APRSTransmit/aprstransmitd TimerControl/timercontrold"
    
    for binary_path in $BINARIES; do
        if [ -f "$binary_path" ]; then
            binary_name=$(basename "$binary_path")
            cp "$binary_path" "$PKG_DIR/usr/bin/"
            chmod 755 "$PKG_DIR/usr/bin/$binary_name"
            print_info "Installed: $binary_name"
        else
            print_warning "Binary not found: $binary_path"
        fi
    done
    
    # Copy data files
    if [ -d "Data" ]; then
        print_info "Copying data files..."
        cp -r Data/* "$PKG_DIR/usr/share/dstarclients/" 2>/dev/null || true
    fi
    
    # Create sample config files
    for component in ircDDBGateway TimeServer RemoteControl StarNetServer TextTransmit VoiceTransmit; do
        config_name="${component}.cfg"
        if [ -d "$component" ]; then
            # Create a basic config file
            cat > "$PKG_DIR/etc/dstarclients/${config_name}" << EOF
# Configuration file for $component
# Generated during package build
# Please edit according to your needs
EOF
        fi
    done
    
    cd ..
    
    # Copy docs
    for doc in README.md README LICENSE COPYING; do
        if [ -f "ircDDBGateway/$doc" ]; then
            cp "ircDDBGateway/$doc" "$PKG_DIR/usr/share/doc/dstarclients/"
        fi
    done
    
    # Create systemd service
    cat > "$PKG_DIR/lib/systemd/system/ircddbgateway.service" << 'EOF'
[Unit]
Description=ircDDB Gateway Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/ircddbgatewayd -daemon
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF
    
    # Create changelog
    cat > "$PKG_DIR/usr/share/doc/dstarclients/changelog.Debian" << EOF
${PACKAGE_NAME} (${FULL_VERSION}) ${DEBIAN_VERSION}; urgency=medium

  * Package built from git commit ${GIT_COMMIT_FULL}
  * Built for Debian ${DEBIAN_VERSION}
  * Build number: ${BUILD_NUMBER}

 -- MW0MWZ <andy@mw0mwz.co.uk>  $(date -R)
EOF
    gzip -9n "$PKG_DIR/usr/share/doc/dstarclients/changelog.Debian"
    
    # Create copyright
    cat > "$PKG_DIR/usr/share/doc/dstarclients/copyright" << 'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ircDDBGateway
Source: https://github.com/g4klx/ircDDBGateway

Files: *
Copyright: Jonathan Naylor G4KLX and contributors
License: GPL-2+
EOF
    
    # Set dependencies based on Debian version
    case "$DEBIAN_VERSION" in
        bullseye)
            DEPENDS="libc6 (>= 2.31), libgcc-s1 (>= 3.0), libstdc++6 (>= 5.2), libwxgtk3.0-gtk3-0v5, libportaudio2, libusb-1.0-0"
            ;;
        bookworm)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11), libwxgtk3.2-1, libportaudio2, libusb-1.0-0"
            ;;
        trixie)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11), libwxgtk3.2-1t64, libportaudio2t64, libusb-1.0-0t64"
            ;;
        *)
            DEPENDS="libc6 (>= 2.31), libgcc-s1 (>= 3.0), libstdc++6 (>= 5.2), libwxbase3.0-0v5, libportaudio2, libusb-1.0-0"
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
Description: D-Star ircDDB Gateway and Tools
 ircDDB Gateway for D-Star digital voice
 Includes gateway, time server, remote control, and transmit tools
 Built for Debian ${DEBIAN_VERSION}
 Git commit: ${GIT_COMMIT}
Homepage: https://github.com/g4klx/ircDDBGateway
EOF
    
    # Create postinst script
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
    
    # Create conffiles
    > "$PKG_DIR/DEBIAN/conffiles"
    find "$PKG_DIR/etc/dstarclients" -type f 2>/dev/null | while read conf; do
        echo "${conf#$PKG_DIR}" >> "$PKG_DIR/DEBIAN/conffiles"
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
patch_makefiles
build_software
create_package
verify_package

print_message "Build completed!"
print_info "Package: $OUTPUT_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}.deb"