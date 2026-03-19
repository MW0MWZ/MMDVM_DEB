#!/bin/bash
set -e

# D-Star Repeater package build script for Debian
# For GitHub Actions ONLY
# Version: 2.0.0 - wxWidgets removed, single binary, INI config

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="dstarrepeater"
GITURL="https://github.com/g4klx/DStarRepeater.git"
BUILD_DIR="build"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Functions
print_message() { echo -e "${GREEN}[BUILD]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

clean_build() {
    print_message "Cleaning build environment..."
    rm -rf "$BUILD_DIR" DStarRepeater
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
}

prepare_source() {
    print_message "Cloning DStarRepeater from $GITURL..."
    git clone "$GITURL" DStarRepeater
    cd DStarRepeater
    GIT_COMMIT=$(git rev-parse --short HEAD)
    GIT_COMMIT_FULL=$(git rev-parse HEAD)
    VERSION=$(git show -s --format=%cd --date=format:'%Y.%m.%d' HEAD)
    cd ..
    
    print_info "Source version: $VERSION"
    print_info "Git commit: $GIT_COMMIT"
}

build_software() {
    print_message "Building DStarRepeater..."
    cd DStarRepeater

    make clean || true

    # Upstream Makefile auto-detects GPIO on ARM, MQTT on by default
    print_info "Building with MQTT=1 (GPIO auto-detected on ARM)"
    make -j$(nproc) all

    if [ ! -f "DStarRepeater/dstarrepeaterd" ]; then
        print_error "Build failed - dstarrepeaterd not created"
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
    
    # Create package directory structure
    PKG_DIR="$(pwd)/$BUILD_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}"
    mkdir -p "$PKG_DIR"/{DEBIAN,usr/bin,usr/share/{doc/dstarrepeater,dstarrepeater}}
    mkdir -p "$PKG_DIR"/{etc/dstarrepeater,lib/systemd/system,var/{lib,log}/dstarrepeater}
    
    cd DStarRepeater

    # Install single binary
    cp "DStarRepeater/dstarrepeaterd" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/dstarrepeaterd"
    print_info "Installed: dstarrepeaterd"

    # Copy AMBE voice data files
    if [ -d "Data" ]; then
        for ext in ambe indx; do
            cp Data/*.$ext "$PKG_DIR/usr/share/dstarrepeater/" 2>/dev/null || true
        done
    fi

    # Install config: example and active copy
    if [ -f "Data/dstarrepeater.ini.example" ]; then
        cp "Data/dstarrepeater.ini.example" "$PKG_DIR/etc/dstarrepeater/dstarrepeater.ini.example"
        cp "Data/dstarrepeater.ini.example" "$PKG_DIR/etc/dstarrepeater/dstarrepeater.ini"
        print_info "Installed: dstarrepeater.ini"
    fi

    # Copy docs
    for doc in README.md CHANGELOG.md CONFIGURATION.md MQTT.md BUILD.md COPYING.txt; do
        [ -f "$doc" ] && cp "$doc" "$PKG_DIR/usr/share/doc/dstarrepeater/"
    done

    cd ..
    
    # Create systemd service
    cat > "$PKG_DIR/lib/systemd/system/dstarrepeater.service" << 'EOF'
[Unit]
Description=D-Star Repeater Controller
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/dstarrepeaterd /etc/dstarrepeater/dstarrepeater.ini
Restart=on-failure
RestartSec=5
User=dstar
Group=dstar
WorkingDirectory=/var/lib/dstarrepeater

[Install]
WantedBy=multi-user.target
EOF
    
    # Create changelog
    cat > "$PKG_DIR/usr/share/doc/dstarrepeater/changelog.Debian" << EOF
${PACKAGE_NAME} (${FULL_VERSION}) ${DEBIAN_VERSION}; urgency=medium

  * Package built from git commit ${GIT_COMMIT_FULL}
  * Built for Debian ${DEBIAN_VERSION}

 -- MW0MWZ <andy@mw0mwz.co.uk>  $(date -R)
EOF
    gzip -9n "$PKG_DIR/usr/share/doc/dstarrepeater/changelog.Debian"
    
    # Create copyright
    cat > "$PKG_DIR/usr/share/doc/dstarrepeater/copyright" << 'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: DStarRepeater
Source: https://github.com/g4klx/DStarRepeater

Files: *
Copyright: Jonathan Naylor G4KLX and contributors
License: GPL-2+
EOF
    
    # Set dependencies based on Debian version
    case "$DEBIAN_VERSION" in
        trixie)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11), libusb-1.0-0, libasound2t64, libmosquitto1t64"
            ;;
        *)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11), libusb-1.0-0, libasound2, libmosquitto1"
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
Description: D-Star Repeater Controller for Amateur Radio
 D-Star repeater controller daemon with MQTT telemetry support
 Built for Debian ${DEBIAN_VERSION}
 Git commit: ${GIT_COMMIT}
Homepage: https://github.com/g4klx/DStarRepeater
EOF
    
    # Create postinst script
    cat > "$PKG_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e

case "$1" in
    configure)
        # Create dstar user if it doesn't exist
        if ! getent passwd dstar >/dev/null; then
            adduser --system --group --home /var/lib/dstarrepeater \
                    --no-create-home --disabled-password \
                    --gecos "D-Star Repeater" dstar || true
        fi
        
        # Add to groups
        for group in dialout audio usb plugdev gpio; do
            if getent group $group >/dev/null; then
                usermod -a -G $group dstar 2>/dev/null || true
            fi
        done
        
        # Set ownership
        chown -R dstar:dstar /var/lib/dstarrepeater /var/log/dstarrepeater || true
        
        # Reload systemd
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
        # Remove user
        if getent passwd dstar >/dev/null; then
            deluser --quiet dstar || true
        fi
        # Remove directories
        for dir in /etc/dstarrepeater /var/lib/dstarrepeater /var/log/dstarrepeater; do
            [ -d "$dir" ] && rmdir --ignore-fail-on-non-empty "$dir" || true
        done
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
    echo "/etc/dstarrepeater/dstarrepeater.ini" > "$PKG_DIR/DEBIAN/conffiles"
    
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
    DEB_FILE="$OUTPUT_DIR/${PACKAGE_NAME}_${VERSION}-${BUILD_NUMBER}${DEB_VERSION_SUFFIX}_${PKG_ARCH}.deb"
    
    if [ -f "$DEB_FILE" ]; then
        print_info "Package info:"
        dpkg-deb -I "$DEB_FILE"
        print_info "Package size: $(ls -lh "$DEB_FILE" | awk '{print $5}')"
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
[ -n "$BUILD_NUMBER" ] && print_info "Build number: $BUILD_NUMBER"

# Build the package
clean_build
prepare_source
build_software
create_package
verify_package

print_message "Build completed!"
print_info "Package: $OUTPUT_DIR/${PACKAGE_NAME}_${VERSION}-${BUILD_NUMBER}${DEB_VERSION_SUFFIX}_${ARCH}.deb"