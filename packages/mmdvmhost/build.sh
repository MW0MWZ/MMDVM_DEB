#!/bin/bash
set -e

# MMDVM Host package build script for Debian
# For GitHub Actions ONLY
# Version: 4.1.0 - MMDVM-Host / MMDVM-Display / MMDVM-Info, templates in /usr/share

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PACKAGE_NAME="mmdvmhost"
GITURL="https://github.com/g4klx/MMDVM-Host.git"
GITURL_CAL="https://github.com/g4klx/MMDVMCal.git"
GITURL_DISPLAY="https://github.com/g4klx/MMDVM-Display.git"
GITURL_INFO="https://github.com/g4klx/MMDVM-Info.git"
GITURL_OLED="https://github.com/MW0MWZ/ArduiPi_OLED.git"
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
    rm -rf "$BUILD_DIR" MMDVM-Host MMDVMCal MMDVM-Display MMDVM-Info ArduiPi_OLED oled-install
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
}

prepare_source() {
    print_message "Cloning MMDVM-Host from $GITURL..."
    git clone "$GITURL" MMDVM-Host
    cd MMDVM-Host
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

    print_message "Cloning MMDVM-Display from $GITURL_DISPLAY..."
    git clone "$GITURL_DISPLAY" MMDVM-Display
    cd MMDVM-Display
    DISPLAY_COMMIT=$(git rev-parse --short HEAD)
    DISPLAY_COMMIT_FULL=$(git rev-parse HEAD)
    cd ..

    # MMDVM-Display gets host configuration, network addresses and CPU
    # status from MMDVM-Info
    print_message "Cloning MMDVM-Info from $GITURL_INFO..."
    git clone "$GITURL_INFO" MMDVM-Info
    cd MMDVM-Info
    INFO_COMMIT=$(git rev-parse --short HEAD)
    INFO_COMMIT_FULL=$(git rev-parse HEAD)
    # Upstream relies on <unistd.h> being pulled in indirectly; include it
    # explicitly so the build doesn't depend on libc header internals.
    if patch -p1 -N --dry-run < "$SCRIPT_DIR/mmdvminfo-unistd.patch" >/dev/null 2>&1; then
        patch -p1 -N < "$SCRIPT_DIR/mmdvminfo-unistd.patch"
    fi
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
    print_info "MMDVM-Host commit: $GIT_COMMIT"
    print_info "MMDVMCal commit: $CAL_COMMIT"
    print_info "MMDVM-Display commit: $DISPLAY_COMMIT"
    print_info "MMDVM-Info commit: $INFO_COMMIT"
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
    # Build MMDVM-Host
    print_message "Building MMDVM-Host..."
    cd MMDVM-Host
    make clean || true
    make -j$(nproc) all

    if [ ! -f "MMDVM-Host" ]; then
        print_error "Build failed - MMDVM-Host binary not created"
        exit 1
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

    # Build MMDVM-Display
    print_message "Building MMDVM-Display..."
    cd MMDVM-Display
    make clean || true

    # Enable display hardware support on ARM platforms
    if [ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ]; then
        OLED_PREFIX="$(pwd)/../oled-install"
        print_info "Patching Makefile for OLED/HD44780/PCF8574 display support..."
        sed -i "s|^CFLAGS.*=.*|CFLAGS  = -g -O3 -Wall -std=c++0x -pthread -DUSE_OLED -DUSE_HD44780 -DUSE_PCF8574_DISPLAY -I${OLED_PREFIX}/include -I/usr/local/include|" Makefile
        sed -i "s|^LIBS.*=.*|LIBS    = -lArduiPi_OLED -lwiringPi -lwiringPiDev -lpthread -lutil -lmosquitto|" Makefile
        export LIBRARY_PATH="${OLED_PREFIX}/lib"
        export CPATH="${OLED_PREFIX}/include"
    fi

    make -j$(nproc) all

    if [ ! -f "MMDVM-Display" ]; then
        print_error "Build failed - MMDVM-Display binary not created"
        exit 1
    fi
    if [ ! -f "NextionUpdater" ]; then
        print_error "Build failed - NextionUpdater binary not created"
        exit 1
    fi
    cd ..

    # Build MMDVM-Info
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
    mkdir -p "$PKG_DIR/usr/share/mmdvmhost"
    mkdir -p "$PKG_DIR/etc/mmdvmhost"
    mkdir -p "$PKG_DIR/lib/systemd/system"
    mkdir -p "$PKG_DIR/var/lib/mmdvmhost"
    mkdir -p "$PKG_DIR/var/log/mmdvmhost"

    # Copy MMDVM-Host binary
    cp "MMDVM-Host/MMDVM-Host" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/MMDVM-Host"

    cp "MMDVMCal/MMDVMCal" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/MMDVMCal"

    # Copy MMDVM-Display binaries
    cp "MMDVM-Display/MMDVM-Display" "$PKG_DIR/usr/bin/"
    cp "MMDVM-Display/NextionUpdater" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/MMDVM-Display" "$PKG_DIR/usr/bin/NextionUpdater"

    # Copy MMDVM-Info binary
    cp "MMDVM-Info/MMDVM-Info" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/MMDVM-Info"

    # Copy OLED library for ARM platforms
    if [ "$PKG_ARCH" = "armhf" ] || [ "$PKG_ARCH" = "arm64" ]; then
        if [ -d "oled-install" ]; then
            print_info "Installing OLED library files..."
            mkdir -p "$PKG_DIR/usr/lib/mmdvmhost"
            if [ -f "oled-install/lib/libArduiPi_OLED.so.1.0" ]; then
                cp -a oled-install/lib/libArduiPi_OLED.so* "$PKG_DIR/usr/lib/mmdvmhost/"
                # Ensure soname symlink exists (ArduiPi_OLED build doesn't create .so.1)
                cd "$PKG_DIR/usr/lib/mmdvmhost"
                ln -sf libArduiPi_OLED.so.1.0 libArduiPi_OLED.so.1
                ln -sf libArduiPi_OLED.so.1.0 libArduiPi_OLED.so
                cd - > /dev/null
            elif [ -f "oled-install/lib/libArduiPi_OLED.so" ]; then
                cp -L oled-install/lib/libArduiPi_OLED.so "$PKG_DIR/usr/lib/mmdvmhost/libArduiPi_OLED.so.1.0"
                cd "$PKG_DIR/usr/lib/mmdvmhost"
                ln -sf libArduiPi_OLED.so.1.0 libArduiPi_OLED.so.1
                ln -sf libArduiPi_OLED.so.1.0 libArduiPi_OLED.so
                cd - > /dev/null
            fi
        fi
    fi

    # Configuration templates are package-owned and live in /usr/share.
    # /etc/mmdvmhost/ ships empty and holds only user configuration; the
    # postinst creates missing configs from these templates.
    cp "MMDVM-Host/MMDVM-Host.ini" "$PKG_DIR/usr/share/mmdvmhost/MMDVM-Host.ini.example"
    cp "MMDVM-Display/MMDVM-Display.ini" "$PKG_DIR/usr/share/mmdvmhost/MMDVM-Display.ini.example"

    # The upstream MMDVM-Info template points [Configs] at a source-tree
    # layout and lists programs this repository doesn't ship, so point it
    # at the paths our packages install to.
    INFO_TEMPLATE="$PKG_DIR/usr/share/mmdvmhost/MMDVM-Info.ini.example"
    cp "MMDVM-Info/MMDVM-Info.ini" "$INFO_TEMPLATE"
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
        "$INFO_TEMPLATE"

    # Copy data files
    for datafile in DMRIds.dat DMRIds.csv NXDN.csv P25Hosts.txt DMR_Hosts.txt XLXHosts.txt; do
        if [ -f "MMDVM-Host/$datafile" ]; then
            cp "MMDVM-Host/$datafile" "$PKG_DIR/var/lib/mmdvmhost/$datafile"
        fi
    done

    # Copy RSSI reference files to /usr/share/mmdvmhost/
    if [ -f "MMDVM-Host/RSSI.dat" ]; then
        cp "MMDVM-Host/RSSI.dat" "$PKG_DIR/usr/share/mmdvmhost/"
    fi
    if [ -d "MMDVM-Host/RSSI" ]; then
        cp MMDVM-Host/RSSI/*.dat "$PKG_DIR/usr/share/mmdvmhost/" 2>/dev/null || true
    fi

    # Create RSSI_MMDVM_HS.dat reference file
    cat > "$PKG_DIR/usr/share/mmdvmhost/RSSI_MMDVM_HS.dat" << 'RSSIEOF'
# This file maps the raw RSSI values to dBm values to send to the DMR network. A number of data
# points should be entered and the software will use those to work out the in-between values.
#
# The format of the file is:
# Raw RSSI Value        dBm Value
#
#
# RSSI Default Values for MMDVM_HS
#
43           -43
53           -53
63           -63
73           -73
83           -83
93           -93
99           -99
105          -105
111          -111
117          -117
123          -123
129          -129
135          -135
141          -141
RSSIEOF

    # Install MMDVM_HS defaults as the active RSSI.dat
    cp "$PKG_DIR/usr/share/mmdvmhost/RSSI_MMDVM_HS.dat" "$PKG_DIR/var/lib/mmdvmhost/RSSI.dat"

    # Copy docs
    for doc in README.md README LICENSE COPYING; do
        if [ -f "MMDVM-Host/$doc" ]; then
            cp "MMDVM-Host/$doc" "$PKG_DIR/usr/share/doc/mmdvmhost/"
        fi
        if [ -f "MMDVMCal/$doc" ]; then
            cp "MMDVMCal/$doc" "$PKG_DIR/usr/share/doc/mmdvmhost/MMDVMCal-$doc"
        fi
        if [ -f "MMDVM-Display/$doc" ]; then
            cp "MMDVM-Display/$doc" "$PKG_DIR/usr/share/doc/mmdvmhost/MMDVM-Display-$doc"
        fi
        if [ -f "MMDVM-Info/$doc" ]; then
            cp "MMDVM-Info/$doc" "$PKG_DIR/usr/share/doc/mmdvmhost/MMDVM-Info-$doc"
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
Description=MMDVM-Host Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/MMDVM-Host /etc/mmdvmhost/MMDVM-Host.ini
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
Description=MMDVM-Display Service
After=network.target mosquitto.service mmdvmhost.service mmdvminfo.service
Wants=mmdvminfo.service

[Service]
Type=simple
ExecStart=/usr/bin/MMDVM-Display /etc/mmdvmhost/MMDVM-Display.ini
Environment="LD_LIBRARY_PATH=/usr/lib/mmdvmhost"
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup
WorkingDirectory=/var/lib/mmdvmhost

[Install]
WantedBy=multi-user.target
EOF

    # Create mmdvminfo systemd service
    cat > "$PKG_DIR/lib/systemd/system/mmdvminfo.service" << 'EOF'
[Unit]
Description=MMDVM-Info Service
After=network.target mosquitto.service

[Service]
Type=simple
ExecStart=/usr/bin/MMDVM-Info /etc/mmdvmhost/MMDVM-Info.ini
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

    # Create changelog
    CHANGELOG_CONTENT="  * Package built from git commits:
    - MMDVM-Host: ${GIT_COMMIT_FULL}
    - MMDVMCal: ${CAL_COMMIT_FULL}
    - MMDVM-Display: ${DISPLAY_COMMIT_FULL}
    - MMDVM-Info: ${INFO_COMMIT_FULL}"

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
Upstream-Name: MMDVM-Host
Source: https://github.com/g4klx/MMDVM-Host

Files: *
Copyright: Jonathan Naylor G4KLX and contributors
License: GPL-2+

Files: MMDVM-Display/*
Copyright: Jonathan Naylor G4KLX and contributors
License: GPL-2+

Files: MMDVM-Info/*
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
    DESCRIPTION="MMDVM-Host, MMDVM-Display, MMDVM-Info and MMDVMCal
 Multi-Mode Digital Voice Modem Host Software
 Supports D-Star, DMR, YSF, P25, NXDN, POCSAG and FM
 Includes the MMDVM-Display display driver, the MMDVM-Info information
 service it relies on, and the MMDVMCal calibration tool"

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
 Git commits: MMDVM-Host ${GIT_COMMIT}, MMDVMCal ${CAL_COMMIT}, MMDVM-Display ${DISPLAY_COMMIT}, MMDVM-Info ${INFO_COMMIT}"

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
Homepage: https://github.com/g4klx/MMDVM-Host
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

        # Upstream renamed MMDVMHost to MMDVM-Host and DisplayDriver to
        # MMDVM-Display. Carry existing configuration over to the new names.
        mkdir -p /etc/mmdvmhost
        if [ ! -e /etc/mmdvmhost/MMDVM-Host.ini ] && [ -f /etc/mmdvmhost/MMDVMHost.ini ]; then
            mv /etc/mmdvmhost/MMDVMHost.ini /etc/mmdvmhost/MMDVM-Host.ini
            echo "Renamed /etc/mmdvmhost/MMDVMHost.ini to MMDVM-Host.ini"
        fi
        if [ ! -e /etc/mmdvmhost/MMDVM-Display.ini ] && [ -f /etc/mmdvmhost/DisplayDriver.ini ]; then
            mv /etc/mmdvmhost/DisplayDriver.ini /etc/mmdvmhost/MMDVM-Display.ini
            echo "Renamed /etc/mmdvmhost/DisplayDriver.ini to MMDVM-Display.ini"
        fi

        # Templates now live in /usr/share/mmdvmhost; remove stale copies
        # that older versions of this package installed into /etc.
        rm -f /etc/mmdvmhost/MMDVMHost.ini.example /etc/mmdvmhost/DisplayDriver.ini.example

        # Create configuration from the package templates if missing
        for name in MMDVM-Host MMDVM-Display MMDVM-Info; do
            if [ ! -f /etc/mmdvmhost/$name.ini ] && [ -f /usr/share/mmdvmhost/$name.ini.example ]; then
                cp /usr/share/mmdvmhost/$name.ini.example /etc/mmdvmhost/$name.ini
                echo "Created /etc/mmdvmhost/$name.ini from template - edit it to match your setup"
            fi
        done
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
        # Stop the services if running
        if [ -d /run/systemd/system ]; then
            systemctl stop mmdvminfo.service >/dev/null 2>&1 || true
            systemctl disable mmdvminfo.service >/dev/null 2>&1 || true
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

    # No conffiles: /etc/mmdvmhost/ holds only user configuration created
    # by the postinst from the templates in /usr/share/mmdvmhost.

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

        # Check for MMDVM-Display binary
        if dpkg-deb -c "$DEB_FILE" | grep -q "usr/bin/MMDVM-Display"; then
            print_info "MMDVM-Display binary found in package"
        else
            print_warning "MMDVM-Display binary not found in package"
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
