#!/bin/bash
set -e

# MMDVM Host package build script for Debian
# For GitHub Actions ONLY
# Version: 3.0.0 - Display-Driver integration

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="mmdvmhost"
GITURL="https://github.com/g4klx/MMDVMHost.git"
GITURL_CAL="https://github.com/g4klx/MMDVMCal.git"
GITURL_DISPLAYDRIVER="https://github.com/g4klx/Display-Driver.git"
GITURL_OLED="https://github.com/MW0MWZ/ArduiPi_OLED.git"
BUILD_DIR="build"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Functions
print_message() { echo -e "${GREEN}[BUILD]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

clean_build() {
    print_message "Cleaning build environment..."
    rm -rf "$BUILD_DIR" MMDVMHost MMDVMCal Display-Driver ArduiPi_OLED oled-install
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
}

prepare_source() {
    print_message "Cloning MMDVMHost from $GITURL..."
    git clone "$GITURL" MMDVMHost
    cd MMDVMHost
    GIT_COMMIT=$(git rev-parse --short HEAD)
    GIT_COMMIT_FULL=$(git rev-parse HEAD)
    VERSION=$(git show -s --format=%cd --date=format:'%Y.%m.%d' HEAD)
    cd ..

    print_message "Cloning MMDVMCal from $GITURL_CAL..."
    git clone "$GITURL_CAL" MMDVMCal
    cd MMDVMCal
    CAL_COMMIT=$(git rev-parse --short HEAD)
    CAL_COMMIT_FULL=$(git rev-parse HEAD)
    cd ..

    print_message "Cloning Display-Driver from $GITURL_DISPLAYDRIVER..."
    git clone "$GITURL_DISPLAYDRIVER" Display-Driver
    cd Display-Driver
    DISPLAY_COMMIT=$(git rev-parse --short HEAD)
    DISPLAY_COMMIT_FULL=$(git rev-parse HEAD)
    cd ..

    # Clone ArduiPi_OLED for ARM platforms
    if [ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ]; then
        print_message "Cloning ArduiPi_OLED from $GITURL_OLED..."
        git clone "$GITURL_OLED" ArduiPi_OLED
        cd ArduiPi_OLED
        OLED_COMMIT=$(git rev-parse --short HEAD)
        OLED_COMMIT_FULL=$(git rev-parse HEAD)
        cd ..
        print_info "ArduiPi_OLED commit: $OLED_COMMIT"
    fi

    print_info "Source version: $VERSION"
    print_info "MMDVMHost commit: $GIT_COMMIT"
    print_info "MMDVMCal commit: $CAL_COMMIT"
    print_info "Display-Driver commit: $DISPLAY_COMMIT"
}

check_build_dependencies() {
    print_message "Checking build dependencies..."

    # List of required packages for building
    REQUIRED_PACKAGES="build-essential git pkg-config nlohmann-json3-dev libsamplerate0-dev libmosquitto-dev"

    # Additional packages for ARM display hardware support
    if [ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ]; then
        REQUIRED_PACKAGES="$REQUIRED_PACKAGES libi2c-dev"

        # Verify wiringPi is installed (should be from GitHub Actions workflow)
        if dpkg -l | grep -q "^ii  wiringpi"; then
            print_info "wiringPi is installed"
            if command -v gpio >/dev/null 2>&1; then
                GPIO_VERSION=$(gpio -v 2>/dev/null | head -1 || echo "unknown")
                print_info "  GPIO utility version: $GPIO_VERSION"
            fi
        else
            print_warning "wiringPi not found - it should be installed from deb.pistar.uk repository"
        fi
    fi

    MISSING_PACKAGES=""
    for pkg in $REQUIRED_PACKAGES; do
        if ! dpkg -l | grep -q "^ii  $pkg"; then
            MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
        fi
    done

    if [ -n "$MISSING_PACKAGES" ]; then
        print_error "Missing required packages:$MISSING_PACKAGES"
        print_info "Install them with: sudo apt-get install$MISSING_PACKAGES"

        # In CI/automated builds, try to install automatically
        if [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ]; then
            print_message "CI environment detected, attempting to install dependencies..."
            apt-get update && apt-get install -y $MISSING_PACKAGES || {
                print_error "Failed to install dependencies automatically"
                exit 1
            }
        else
            exit 1
        fi
    else
        print_info "All build dependencies are satisfied"
    fi
}

build_oled_library() {
    print_message "Building ArduiPi_OLED library..."

    cd ArduiPi_OLED

    # Clean any previous build
    make clean || true

    # Create a local install directory that we have write access to
    LOCAL_PREFIX="$(pwd)/../oled-install"
    mkdir -p "$LOCAL_PREFIX/lib" "$LOCAL_PREFIX/include"

    print_info "Building and installing to local prefix: $LOCAL_PREFIX"

    # Build and install to our local prefix (not system directories)
    make PREFIX="$LOCAL_PREFIX"

    # Validate the library was built
    if [ -f "$LOCAL_PREFIX/lib/libArduiPi_OLED.so.1.0" ]; then
        print_info "ArduiPi_OLED library successfully installed to $LOCAL_PREFIX"
    elif [ -f "libArduiPi_OLED.so.1.0" ]; then
        # Library was built but not installed, copy it manually
        print_info "Manually installing library files..."
        cp -a libArduiPi_OLED.so* "$LOCAL_PREFIX/lib/"
        cp -a *.h "$LOCAL_PREFIX/include/"
    else
        print_error "Library build failed - libArduiPi_OLED.so.1.0 not found"
        exit 1
    fi

    cd ..
}

build_software() {
    # Build MMDVMHost
    print_message "Building MMDVMHost..."
    cd MMDVMHost
    make clean || true
    make -j$(nproc) all

    if [ ! -f "MMDVMHost" ]; then
        print_error "Build failed - MMDVMHost binary not created"
        exit 1
    fi

    # Build RemoteCommand if it exists
    if [ -f "RemoteCommand.cpp" ]; then
        make RemoteCommand || true
    fi
    cd ..

    # Build MMDVMCal
    print_message "Building MMDVMCal..."
    cd MMDVMCal
    make clean || true
    make -j$(nproc) all

    if [ ! -f "MMDVMCal" ]; then
        print_error "Build failed - MMDVMCal binary not created"
        exit 1
    fi
    cd ..

    # Build OLED library for ARM platforms
    if [ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ]; then
        build_oled_library
    fi

    # Build Display-Driver
    print_message "Building Display-Driver..."
    cd Display-Driver
    make clean || true

    if [ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ]; then
        OLED_PREFIX="$(pwd)/../oled-install"
        print_info "Patching Display-Driver for ARM display hardware support..."

        # Append OLED/HD44780 defines to existing CFLAGS (preserve upstream flags)
        sed -i '/^CFLAGS/ s|$| -DOLED -DHD44780 -DPCF8574_DISPLAY -I'"$OLED_PREFIX"'/include|' Makefile
        # Append OLED/wiringPi libraries to existing LIBS
        sed -i '/^LIBS/ s|$| -lArduiPi_OLED -lwiringPi -lwiringPiDev|' Makefile

        # Fix upstream HD44780.cpp syntax error (misplaced parenthesis in sprintf)
        if [ -f "HD44780.cpp" ]; then
            sed -i 's|group ? "TG" : "", dst), DEADSPACE);|group ? "TG" : "", dst, DEADSPACE.c_str());|' HD44780.cpp
        fi

        export LIBRARY_PATH="$OLED_PREFIX/lib:$LIBRARY_PATH"
        export CPATH="$OLED_PREFIX/include:$CPATH"
    fi

    make -j$(nproc) all

    if [ ! -f "DisplayDriver" ]; then
        print_error "Build failed - DisplayDriver binary not created"
        exit 1
    fi
    if [ ! -f "NextionUpdater" ]; then
        print_error "Build failed - NextionUpdater binary not created"
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
    mkdir -p "$PKG_DIR/usr/share/doc/mmdvmhost"
    mkdir -p "$PKG_DIR/etc/mmdvmhost"
    mkdir -p "$PKG_DIR/lib/systemd/system"
    mkdir -p "$PKG_DIR/var/lib/mmdvmhost"
    mkdir -p "$PKG_DIR/var/log/mmdvmhost"

    # Copy MMDVMHost binaries
    cp "MMDVMHost/MMDVMHost" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/MMDVMHost"

    cp "MMDVMCal/MMDVMCal" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/MMDVMCal"

    if [ -f "MMDVMHost/RemoteCommand" ]; then
        cp "MMDVMHost/RemoteCommand" "$PKG_DIR/usr/bin/"
        chmod 755 "$PKG_DIR/usr/bin/RemoteCommand"
    fi

    # Copy Display-Driver binaries
    cp "Display-Driver/DisplayDriver" "$PKG_DIR/usr/bin/"
    cp "Display-Driver/NextionUpdater" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/DisplayDriver" "$PKG_DIR/usr/bin/NextionUpdater"

    # Copy OLED library for ARM platforms
    if [ "$PKG_ARCH" = "armhf" ] || [ "$PKG_ARCH" = "arm64" ]; then
        if [ -d "oled-install" ]; then
            print_info "Installing OLED library files..."
            mkdir -p "$PKG_DIR/usr/lib/mmdvmhost"
            if [ -f "oled-install/lib/libArduiPi_OLED.so.1.0" ]; then
                cp -a oled-install/lib/libArduiPi_OLED.so* "$PKG_DIR/usr/lib/mmdvmhost/"
            elif [ -f "oled-install/lib/libArduiPi_OLED.so" ]; then
                cp -L oled-install/lib/libArduiPi_OLED.so "$PKG_DIR/usr/lib/mmdvmhost/libArduiPi_OLED.so.1.0"
                cd "$PKG_DIR/usr/lib/mmdvmhost"
                ln -sf libArduiPi_OLED.so.1.0 libArduiPi_OLED.so.1
                ln -sf libArduiPi_OLED.so.1.0 libArduiPi_OLED.so
                cd - > /dev/null
            fi
        fi
    fi

    # Copy config files
    if [ -f "MMDVMHost/MMDVM.ini" ]; then
        cp "MMDVMHost/MMDVM.ini" "$PKG_DIR/etc/mmdvmhost/MMDVM.ini"
    fi

    cp "Display-Driver/DisplayDriver.ini" "$PKG_DIR/etc/mmdvmhost/DisplayDriver.ini"

    # Copy data files
    for datafile in DMRIds.dat DMRIds.csv NXDN.csv P25Hosts.txt DMR_Hosts.txt XLXHosts.txt; do
        if [ -f "MMDVMHost/$datafile" ]; then
            cp "MMDVMHost/$datafile" "$PKG_DIR/var/lib/mmdvmhost/$datafile"
        fi
    done

    # Copy docs
    for doc in README.md README LICENSE COPYING; do
        if [ -f "MMDVMHost/$doc" ]; then
            cp "MMDVMHost/$doc" "$PKG_DIR/usr/share/doc/mmdvmhost/"
        fi
        if [ -f "MMDVMCal/$doc" ]; then
            cp "MMDVMCal/$doc" "$PKG_DIR/usr/share/doc/mmdvmhost/MMDVMCal-$doc"
        fi
        if [ -f "Display-Driver/$doc" ]; then
            cp "Display-Driver/$doc" "$PKG_DIR/usr/share/doc/mmdvmhost/DisplayDriver-$doc"
        fi
    done

    # Copy OLED documentation for ARM builds
    if [ "$PKG_ARCH" = "armhf" ] || [ "$PKG_ARCH" = "arm64" ]; then
        if [ -f "ArduiPi_OLED/README.md" ]; then
            cp "ArduiPi_OLED/README.md" "$PKG_DIR/usr/share/doc/mmdvmhost/ArduiPi_OLED-README.md"
        fi
    fi

    # Create mmdvmhost systemd service
    cat > "$PKG_DIR/lib/systemd/system/mmdvmhost.service" << 'EOF'
[Unit]
Description=MMDVM Host Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/MMDVMHost /etc/mmdvmhost/MMDVM.ini
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup
WorkingDirectory=/var/lib/mmdvmhost

[Install]
WantedBy=multi-user.target
EOF

    # Create displaydriver systemd service
    cat > "$PKG_DIR/lib/systemd/system/displaydriver.service" << 'EOF'
[Unit]
Description=MMDVM Display Driver Service
After=network.target mosquitto.service mmdvmhost.service

[Service]
Type=simple
ExecStart=/usr/bin/DisplayDriver /etc/mmdvmhost/DisplayDriver.ini
Environment="LD_LIBRARY_PATH=/usr/lib/mmdvmhost"
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup
WorkingDirectory=/var/lib/mmdvmhost

[Install]
WantedBy=multi-user.target
EOF

    # Create changelog
    CHANGELOG_CONTENT="  * Package built from git commits:
    - MMDVMHost: ${GIT_COMMIT_FULL}
    - MMDVMCal: ${CAL_COMMIT_FULL}
    - Display-Driver: ${DISPLAY_COMMIT_FULL}"

    if [ "$PKG_ARCH" = "armhf" ] || [ "$PKG_ARCH" = "arm64" ]; then
        if [ -n "$OLED_COMMIT_FULL" ]; then
            CHANGELOG_CONTENT="$CHANGELOG_CONTENT
    - ArduiPi_OLED: ${OLED_COMMIT_FULL}"
        fi
    fi

    CHANGELOG_CONTENT="$CHANGELOG_CONTENT
  * Built for Debian ${DEBIAN_VERSION}
  * Build number: ${BUILD_NUMBER}"

    if [ "$PKG_ARCH" = "armhf" ] || [ "$PKG_ARCH" = "arm64" ]; then
        CHANGELOG_CONTENT="$CHANGELOG_CONTENT
  * ARM build with OLED and HD44780 display hardware support
  * Using wiringPi package from deb.pistar.uk"
    fi

    cat > "$PKG_DIR/usr/share/doc/mmdvmhost/changelog.Debian" << EOF
${PACKAGE_NAME} (${FULL_VERSION}) ${DEBIAN_VERSION}; urgency=medium

$CHANGELOG_CONTENT

 -- MW0MWZ <andy@mw0mwz.co.uk>  $(date -R)
EOF
    gzip -9n "$PKG_DIR/usr/share/doc/mmdvmhost/changelog.Debian"

    # Create copyright
    cat > "$PKG_DIR/usr/share/doc/mmdvmhost/copyright" << 'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: MMDVMHost
Source: https://github.com/g4klx/MMDVMHost

Files: *
Copyright: Jonathan Naylor G4KLX and contributors
License: GPL-2+

Files: Display-Driver/*
Copyright: Jonathan Naylor G4KLX and contributors
License: GPL-2+

Files: ArduiPi_OLED/*
Copyright: Charles-Henri Hallard and contributors
License: MIT
EOF

    # Set dependencies based on Debian version
    case "$DEBIAN_VERSION" in
        trixie)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11), libmosquitto1t64, libsamplerate0t64"
            ;;
        *)
            DEPENDS="libc6 (>= 2.36), libgcc-s1 (>= 3.0), libstdc++6 (>= 11), libmosquitto1, libsamplerate0"
            ;;
    esac

    # Add ARM-specific dependencies for display hardware support
    if [ "$PKG_ARCH" = "armhf" ] || [ "$PKG_ARCH" = "arm64" ]; then
        DEPENDS="$DEPENDS, wiringpi (>= 3.0), libi2c0, i2c-tools"
    fi

    RECOMMENDS="mosquitto"

    # Create description
    DESCRIPTION="MMDVM Host Software, Calibration and Display Driver
 Multi-Mode Digital Voice Modem Host Software
 Supports D-Star, DMR, YSF, P25, NXDN, M17 and POCSAG
 Includes MMDVMCal calibration tool and DisplayDriver display server"

    if [ "$PKG_ARCH" = "armhf" ] || [ "$PKG_ARCH" = "arm64" ]; then
        DESCRIPTION="$DESCRIPTION
 .
 This ARM build includes display hardware support for:
 - OLED displays (SSD1306, SH1106) via ArduiPi_OLED
 - HD44780 LCD displays with I2C PCF8574 expander
 - Uses wiringPi package from deb.pistar.uk"
    fi

    DESCRIPTION="$DESCRIPTION
 .
 Built for Debian ${DEBIAN_VERSION}
 Git commits: MMDVMHost ${GIT_COMMIT}, MMDVMCal ${CAL_COMMIT}, Display-Driver ${DISPLAY_COMMIT}"

    if [ -n "$OLED_COMMIT" ]; then
        DESCRIPTION="$DESCRIPTION, ArduiPi_OLED ${OLED_COMMIT}"
    fi

    cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: ${PACKAGE_NAME}
Version: ${FULL_VERSION}
Section: hamradio
Priority: optional
Architecture: ${PKG_ARCH}
Depends: ${DEPENDS}
Recommends: ${RECOMMENDS}
Maintainer: MW0MWZ <andy@mw0mwz.co.uk>
Description: ${DESCRIPTION}
Homepage: https://github.com/g4klx/MMDVMHost
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

        # Set up library cache for OLED library if present
        if [ -d /usr/lib/mmdvmhost ]; then
            echo "/usr/lib/mmdvmhost" > /etc/ld.so.conf.d/mmdvmhost.conf
            ldconfig || true
        fi

        # Create log directory with correct permissions
        if [ ! -d /var/log/mmdvmhost ]; then
            mkdir -p /var/log/mmdvmhost
            chown nobody:nogroup /var/log/mmdvmhost || true
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
        if [ -d /etc/mmdvmhost ]; then
            rmdir --ignore-fail-on-non-empty /etc/mmdvmhost || true
        fi
        # Remove data directory if empty
        if [ -d /var/lib/mmdvmhost ]; then
            rmdir --ignore-fail-on-non-empty /var/lib/mmdvmhost || true
        fi
        # Remove log directory if empty
        if [ -d /var/log/mmdvmhost ]; then
            rmdir --ignore-fail-on-non-empty /var/log/mmdvmhost || true
        fi
        # Remove library directory if empty
        if [ -d /usr/lib/mmdvmhost ]; then
            rmdir --ignore-fail-on-non-empty /usr/lib/mmdvmhost || true
        fi
        # Remove ldconfig entry
        if [ -f /etc/ld.so.conf.d/mmdvmhost.conf ]; then
            rm -f /etc/ld.so.conf.d/mmdvmhost.conf
            ldconfig || true
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
        # Stop both services if running
        if [ -d /run/systemd/system ]; then
            systemctl stop displaydriver.service >/dev/null 2>&1 || true
            systemctl disable displaydriver.service >/dev/null 2>&1 || true
            systemctl stop mmdvmhost.service >/dev/null 2>&1 || true
            systemctl disable mmdvmhost.service >/dev/null 2>&1 || true
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
    cat > "$PKG_DIR/DEBIAN/conffiles" << 'EOF'
/etc/mmdvmhost/MMDVM.ini
/etc/mmdvmhost/DisplayDriver.ini
EOF

    # Add shlibs for OLED library if present
    if [ "$PKG_ARCH" = "armhf" ] || [ "$PKG_ARCH" = "arm64" ]; then
        if [ -f "$PKG_DIR/usr/lib/mmdvmhost/libArduiPi_OLED.so.1.0" ]; then
            cat > "$PKG_DIR/DEBIAN/shlibs" << EOF
libArduiPi_OLED 1 mmdvmhost (>= ${VERSION})
EOF
        fi
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
        print_info "Package contents (first 50 files):"
        dpkg-deb -c "$DEB_FILE" | head -50
        print_info "Package size:"
        ls -lh "$DEB_FILE"

        # Check for DisplayDriver binary
        if dpkg-deb -c "$DEB_FILE" | grep -q "usr/bin/DisplayDriver"; then
            print_info "DisplayDriver binary found in package"
        else
            print_warning "DisplayDriver binary not found in package"
        fi

        # Check for display support files on ARM
        if [ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ]; then
            print_info "Checking for ARM display support files..."
            if dpkg-deb -c "$DEB_FILE" | grep -q "libArduiPi_OLED"; then
                print_info "OLED library found in package"
            else
                print_warning "OLED library not found in package"
            fi

            if dpkg-deb -I "$DEB_FILE" | grep -q "wiringpi"; then
                print_info "wiringPi dependency correctly set"
            else
                print_warning "wiringPi dependency not found"
            fi
        fi
    else
        print_error "Package file not found: $DEB_FILE"
        exit 1
    fi
}

# MAIN EXECUTION
print_message "Starting build for $PACKAGE_NAME"
print_info "Build script version: 3.0.0"

ARCH="${ARCH:-$(dpkg --print-architecture)}"

# Check for required build dependencies
check_build_dependencies

# Show environment
print_info "Architecture: $ARCH"
[ -n "$DEBIAN_VERSION" ] && print_info "Debian version: $DEBIAN_VERSION"
[ -n "$OUTPUT_DIR" ] && print_info "Output directory: $OUTPUT_DIR"
[ -n "$BUILD_NUMBER" ] && print_info "Build number: $BUILD_NUMBER"

# Build the package
clean_build
prepare_source
build_software
create_package
verify_package

print_message "Build completed successfully!"
print_info "Package: $OUTPUT_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}.deb"

if [ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ]; then
    print_info "This package includes OLED and HD44780 display hardware support for ARM"
fi
