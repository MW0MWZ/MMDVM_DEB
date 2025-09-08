#!/bin/bash
set -e

# DMR Clients package build script for Debian
# For GitHub Actions ONLY

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="dmrclients"
GITURL="https://github.com/g4klx/DMRGateway.git"
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
    rm -rf "$BUILD_DIR" DMRGateway MMDVM_CM
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
}

prepare_source() {
    print_message "Cloning DMRGateway from $GITURL..."
    git clone "$GITURL" DMRGateway
    cd DMRGateway
    GIT_COMMIT=$(git rev-parse --short HEAD)
    GIT_COMMIT_FULL=$(git rev-parse HEAD)
    VERSION=$(git show -s --format=%cd --date=format:'%Y.%m.%d' HEAD)
    cd ..
    
    print_message "Cloning MMDVM_CM from $MMDVM_CM_GITURL..."
    git clone "$MMDVM_CM_GITURL" MMDVM_CM
    cd MMDVM_CM
    MMDVM_CM_COMMIT=$(git rev-parse --short HEAD)
    MMDVM_CM_COMMIT_FULL=$(git rev-parse HEAD)
    cd ..
    
    print_info "Source version: $VERSION"
    print_info "DMRGateway commit: $GIT_COMMIT"
    print_info "MMDVM_CM commit: $MMDVM_CM_COMMIT"
}

build_software() {
    print_message "Building DMRGateway..."
    cd DMRGateway
    
    make clean || true
    
    # Standard build flags
    export CFLAGS="-O2 -Wall -g"
    export CXXFLAGS="-O2 -Wall -g"
    
    make -j$(nproc) all
    
    if [ ! -f "DMRGateway" ]; then
        print_error "Build failed - DMRGateway binary not created"
        exit 1
    fi
    
    cd ..
    
    print_message "Building MMDVM_CM cross-mode tools..."
    cd MMDVM_CM
    
    # Build DMR2YSF
    if [ -d "DMR2YSF" ]; then
        print_info "Building DMR2YSF..."
        cd DMR2YSF
        make clean || true
        make -j$(nproc) all
        cd ..
    fi
    
    # Build DMR2NXDN
    if [ -d "DMR2NXDN" ]; then
        print_info "Building DMR2NXDN..."
        cd DMR2NXDN
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
    
    # Create package directory structure
    PKG_DIR="$BUILD_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}"
    mkdir -p "$PKG_DIR/DEBIAN"
    mkdir -p "$PKG_DIR/usr/bin"
    mkdir -p "$PKG_DIR/usr/share/doc/dmrclients"
    mkdir -p "$PKG_DIR/usr/share/dmrclients"
    mkdir -p "$PKG_DIR/etc/dmrclients"
    mkdir -p "$PKG_DIR/lib/systemd/system"
    
    # Copy DMRGateway binary and config
    cp "DMRGateway/DMRGateway" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/DMRGateway"
    
    if [ -f "DMRGateway/DMRGateway.ini" ]; then
        cp "DMRGateway/DMRGateway.ini" "$PKG_DIR/etc/dmrclients/DMRGateway.ini"
    fi
    
    # Copy data files
    for datafile in XLXHosts.txt DMR_Hosts.txt; do
        if [ -f "DMRGateway/$datafile" ]; then
            cp "DMRGateway/$datafile" "$PKG_DIR/usr/share/dmrclients/$datafile"
        fi
    done
    
    # Copy MMDVM_CM binaries and configs
    if [ -f "MMDVM_CM/DMR2YSF/DMR2YSF" ]; then
        cp "MMDVM_CM/DMR2YSF/DMR2YSF" "$PKG_DIR/usr/bin/"
        chmod 755 "$PKG_DIR/usr/bin/DMR2YSF"
    fi
    if [ -f "MMDVM_CM/DMR2YSF/DMR2YSF.ini" ]; then
        cp "MMDVM_CM/DMR2YSF/DMR2YSF.ini" "$PKG_DIR/etc/dmrclients/DMR2YSF.ini"
    fi
    
    if [ -f "MMDVM_CM/DMR2NXDN/DMR2NXDN" ]; then
        cp "MMDVM_CM/DMR2NXDN/DMR2NXDN" "$PKG_DIR/usr/bin/"
        chmod 755 "$PKG_DIR/usr/bin/DMR2NXDN"
    fi
    if [ -f "MMDVM_CM/DMR2NXDN/DMR2NXDN.ini" ]; then
        cp "MMDVM_CM/DMR2NXDN/DMR2NXDN.ini" "$PKG_DIR/etc/dmrclients/DMR2NXDN.ini"
    fi
    
    # Copy ID files
    for id_file in DMRIds.dat TGList_BM.txt TGList_FCS.txt; do
        for dir in DMRGateway DMR2YSF DMR2NXDN; do
            if [ -f "MMDVM_CM/$dir/$id_file" ] || [ -f "DMRGateway/$id_file" ]; then
                [ -f "MMDVM_CM/$dir/$id_file" ] && cp "MMDVM_CM/$dir/$id_file" "$PKG_DIR/usr/share/dmrclients/$id_file"
                [ -f "DMRGateway/$id_file" ] && cp "DMRGateway/$id_file" "$PKG_DIR/usr/share/dmrclients/$id_file"
                break
            fi
        done
    done
    
    # Copy docs
    for doc in README.md README LICENSE COPYING; do
        if [ -f "DMRGateway/$doc" ]; then
            cp "DMRGateway/$doc" "$PKG_DIR/usr/share/doc/dmrclients/"
        fi
        if [ -f "MMDVM_CM/$doc" ]; then
            cp "MMDVM_CM/$doc" "$PKG_DIR/usr/share/doc/dmrclients/MMDVM_CM-$doc"
        fi
    done
    
    # Create systemd service
    cat > "$PKG_DIR/lib/systemd/system/dmrgateway.service" << 'EOF'
[Unit]
Description=DMR Gateway Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/DMRGateway /etc/dmrclients/DMRGateway.ini
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF
    
    # Create changelog
    cat > "$PKG_DIR/usr/share/doc/dmrclients/changelog.Debian" << EOF
${PACKAGE_NAME} (${FULL_VERSION}) ${DEBIAN_VERSION}; urgency=medium

  * Package built from git commits:
    - DMRGateway: ${GIT_COMMIT_FULL}
    - MMDVM_CM: ${MMDVM_CM_COMMIT_FULL}
  * Built for Debian ${DEBIAN_VERSION}
  * Build number: ${BUILD_NUMBER}

 -- MW0MWZ <andy@mw0mwz.co.uk>  $(date -R)
EOF
    gzip -9n "$PKG_DIR/usr/share/doc/dmrclients/changelog.Debian"
    
    # Create copyright
    cat > "$PKG_DIR/usr/share/doc/dmrclients/copyright" << 'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: DMRGateway
Source: https://github.com/g4klx/DMRGateway

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
Description: DMR Clients for Amateur Radio
 DMR Gateway and Cross-Mode converters for digital communications
 Includes DMRGateway, DMR2YSF, and DMR2NXDN
 Built for Debian ${DEBIAN_VERSION}
 Git commits: DMRGateway ${GIT_COMMIT}, MMDVM_CM ${MMDVM_CM_COMMIT}
Homepage: https://github.com/g4klx/DMRGateway
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
        if [ -d /etc/dmrclients ]; then
            rmdir --ignore-fail-on-non-empty /etc/dmrclients || true
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
    for conf in DMRGateway DMR2YSF DMR2NXDN; do
        if [ -f "$PKG_DIR/etc/dmrclients/${conf}.ini" ]; then
            echo "/etc/dmrclients/${conf}.ini" >> "$PKG_DIR/DEBIAN/conffiles"
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