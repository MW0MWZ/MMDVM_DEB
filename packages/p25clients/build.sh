#!/bin/bash
set -e

# P25 Clients package build script for Debian
# For GitHub Actions ONLY

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="p25clients"
GITURL="https://github.com/g4klx/P25Clients.git"
BUILD_DIR="build"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Functions
print_message() { echo -e "${GREEN}[BUILD]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

clean_build() {
    print_message "Cleaning build environment..."
    rm -rf "$BUILD_DIR" P25Clients
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
}

prepare_source() {
    print_message "Cloning P25Clients from $GITURL..."
    git clone "$GITURL" P25Clients
    cd P25Clients
    GIT_COMMIT=$(git rev-parse --short HEAD)
    GIT_COMMIT_FULL=$(git rev-parse HEAD)
    VERSION=$(git show -s --format=%cd --date=format:'%Y.%m.%d' HEAD)
    cd ..
    
    print_info "Source version: $VERSION"
    print_info "Git commit: $GIT_COMMIT"
}

build_software() {
    print_message "Building P25Clients components..."
    cd P25Clients
    
    # Standard build flags
    export CFLAGS="-O2 -Wall -g"
    export CXXFLAGS="-O2 -Wall -g"
    
    # Build P25Gateway
    if [ -d "P25Gateway" ]; then
        print_info "Building P25Gateway..."
        cd P25Gateway
        make clean || true
        make -j$(nproc) all
        cd ..
    fi
    
    # Build P25Parrot
    if [ -d "P25Parrot" ]; then
        print_info "Building P25Parrot..."
        cd P25Parrot
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
    mkdir -p "$PKG_DIR/usr/share/doc/p25clients"
    mkdir -p "$PKG_DIR/usr/share/p25clients"
    mkdir -p "$PKG_DIR/etc/p25clients"
    mkdir -p "$PKG_DIR/lib/systemd/system"
    
    # Copy P25Clients binaries and configs
    cd P25Clients
    
    # P25Gateway
    if [ -f "P25Gateway/P25Gateway" ]; then
        cp "P25Gateway/P25Gateway" "$PKG_DIR/usr/bin/"
        chmod 755 "$PKG_DIR/usr/bin/P25Gateway"
    fi
    if [ -f "P25Gateway/P25Gateway.ini" ]; then
        cp "P25Gateway/P25Gateway.ini" "$PKG_DIR/etc/p25clients/P25Gateway.ini"
    fi
    
    # P25Parrot
    if [ -f "P25Parrot/P25Parrot" ]; then
        cp "P25Parrot/P25Parrot" "$PKG_DIR/usr/bin/"
        chmod 755 "$PKG_DIR/usr/bin/P25Parrot"
    fi
    if [ -f "P25Parrot/P25Parrot.ini" ]; then
        cp "P25Parrot/P25Parrot.ini" "$PKG_DIR/etc/p25clients/P25Parrot.ini"
    fi
    
    # Copy data files
    for datafile in P25Hosts.txt P25Ids.dat; do
        for dir in P25Gateway P25Parrot; do
            if [ -f "$dir/$datafile" ]; then
                cp "$dir/$datafile" "$PKG_DIR/usr/share/p25clients/$datafile"
                break
            fi
        done
    done
    
    cd ..
    
    # Copy docs
    for doc in README.md README LICENSE COPYING; do
        if [ -f "P25Clients/$doc" ]; then
            cp "P25Clients/$doc" "$PKG_DIR/usr/share/doc/p25clients/"
        fi
    done
    
    # Create systemd service files
    cat > "$PKG_DIR/lib/systemd/system/p25gateway.service" << 'EOF'
[Unit]
Description=P25 Gateway Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/P25Gateway /etc/p25clients/P25Gateway.ini
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

    cat > "$PKG_DIR/lib/systemd/system/p25parrot.service" << 'EOF'
[Unit]
Description=P25 Parrot Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/P25Parrot /etc/p25clients/P25Parrot.ini
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF
    
    # Create changelog
    cat > "$PKG_DIR/usr/share/doc/p25clients/changelog.Debian" << EOF
${PACKAGE_NAME} (${FULL_VERSION}) ${DEBIAN_VERSION}; urgency=medium

  * Package built from git commit ${GIT_COMMIT_FULL}
  * Built for Debian ${DEBIAN_VERSION}
  * Build number: ${BUILD_NUMBER}

 -- MW0MWZ <andy@mw0mwz.co.uk>  $(date -R)
EOF
    gzip -9n "$PKG_DIR/usr/share/doc/p25clients/changelog.Debian"
    
    # Create copyright
    cat > "$PKG_DIR/usr/share/doc/p25clients/copyright" << 'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: P25Clients
Source: https://github.com/g4klx/P25Clients

Files: *
Copyright: Jonathan Naylor G4KLX and contributors
License: GPL-2+
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
Description: P25 Clients for Amateur Radio
 P25 Gateway and Parrot for digital communications
 Includes P25Gateway and P25Parrot
 Built for Debian ${DEBIAN_VERSION}
 Git commit: ${GIT_COMMIT}
Homepage: https://github.com/g4klx/P25Clients
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
        if [ -d /etc/p25clients ]; then
            rmdir --ignore-fail-on-non-empty /etc/p25clients || true
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
    for conf in P25Gateway P25Parrot; do
        if [ -f "$PKG_DIR/etc/p25clients/${conf}.ini" ]; then
            echo "/etc/p25clients/${conf}.ini" >> "$PKG_DIR/DEBIAN/conffiles"
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