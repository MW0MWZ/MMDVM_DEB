#!/bin/bash
set -e

# MMDVM Host package build script for Debian
# For GitHub Actions ONLY
# Version: 2.6.0 - Fixed for non-root builds

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
GITURL_OLED="https://github.com/MW0MWZ/ArduiPi_OLED.git"
BUILD_DIR="build"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Functions
print_message() { echo -e "${GREEN}[BUILD]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

detect_architecture() {
    ARCH="${ARCH:-$(dpkg --print-architecture)}"
    print_info "Detected architecture: $ARCH"
    
    # Set architecture-specific compiler flags
    case "$ARCH" in
        armhf)
            print_info "ARM hard-float (armv6/armv7) platform detected - will build with OLED and HD44780 support"
            BUILD_ARM_DISPLAY=true
            # Use armv6 for compatibility (Raspberry Pi Zero/1)
            ARM_CFLAGS="-march=armv6 -mfpu=vfp -mfloat-abi=hard"
            ;;
        arm64|aarch64)
            print_info "ARM 64-bit platform detected - will build with OLED and HD44780 support"
            BUILD_ARM_DISPLAY=true
            # For aarch64/arm64
            ARM_CFLAGS="-march=armv8-a"
            ;;
        armel)
            print_info "ARM soft-float platform detected - will build with OLED and HD44780 support"
            BUILD_ARM_DISPLAY=true
            ARM_CFLAGS="-march=armv6"
            ;;
        *)
            print_info "x86/other platform detected - standard build"
            BUILD_ARM_DISPLAY=false
            ARM_CFLAGS=""
            ;;
    esac
    
    if [ -n "$ARM_CFLAGS" ]; then
        print_info "Using ARM compiler flags: $ARM_CFLAGS"
    fi
}

clean_build() {
    print_message "Cleaning build environment..."
    rm -rf "$BUILD_DIR" MMDVMHost MMDVMCal ArduiPi_OLED oled-install
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
    
    # Clone ArduiPi_OLED for ARM platforms
    if [ "$BUILD_ARM_DISPLAY" = true ]; then
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
}

patch_arm_makefile() {
    print_message "Patching Makefile for ARM display support..."
    cd MMDVMHost
    
    if [ -f "Makefile.Pi.OLED" ]; then
        print_info "Applying HD44780 and PCF8574 I2C expander support patches..."
        
        # Create a backup
        cp Makefile.Pi.OLED Makefile.Pi.OLED.orig
        
        # Add HD44780 LCD support with PCF8574 I2C expander
        sed -i 's/-DOLED/-DHD44780 -DPCF8574_DISPLAY -DOLED/g' Makefile.Pi.OLED
        
        # Add HD44780.o to build objects if not already present
        if ! grep -q "HD44780.o" Makefile.Pi.OLED; then
            sed -i 's/Hamming.o/Hamming.o HD44780.o/g' Makefile.Pi.OLED
        fi
        
        # Add wiringPi and i2c libraries for GPIO and I2C support
        sed -i 's/-lArduiPi_OLED/-lwiringPi -lwiringPiDev -lArduiPi_OLED -li2c/g' Makefile.Pi.OLED
        
        print_info "Makefile patches applied successfully"
    else
        print_warning "Makefile.Pi.OLED not found - using standard build"
    fi
    
    cd ..
}

check_build_dependencies() {
    print_message "Checking build dependencies..."
    
    # List of required packages for building
    REQUIRED_PACKAGES="build-essential git pkg-config"
    
    # Additional packages for ARM display support
    if [ "$BUILD_ARM_DISPLAY" = true ]; then
        REQUIRED_PACKAGES="$REQUIRED_PACKAGES libi2c-dev"
        
        # Just verify wiringPi is installed (it should be from the GitHub Actions yml)
        if dpkg -l | grep -q "^ii  wiringpi"; then
            print_info "✓ wiringPi is installed"
            if command -v gpio >/dev/null 2>&1; then
                GPIO_VERSION=$(gpio -v 2>/dev/null | head -1 || echo "unknown")
                print_info "  GPIO utility version: $GPIO_VERSION"
            fi
        else
            print_warning "wiringPi not found - it should be installed from deb.pistar.uk repository"
            print_info "Add to your workflow: apt-get install wiringpi"
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
    if [ "$BUILD_ARM_DISPLAY" != true ]; then
        return 0
    fi
    
    print_message "Building ArduiPi_OLED library..."
    
    cd ArduiPi_OLED
    
    # Clean any previous build
    make clean || true
    
    # Create a local install directory that we have write access to
    LOCAL_PREFIX="$(pwd)/../oled-install"
    mkdir -p $LOCAL_PREFIX/lib $LOCAL_PREFIX/include
    
    print_info "Building and installing to local prefix: $LOCAL_PREFIX"
    
    # Build and install to our local prefix (not system directories)
    make PREFIX="$LOCAL_PREFIX"
    
    # The make command will build and try to install
    # Check if the library ended up in the right place
    if [ -f "$LOCAL_PREFIX/lib/libArduiPi_OLED.so.1.0" ]; then
        print_info "ArduiPi_OLED library successfully installed to $LOCAL_PREFIX"
    elif [ -f "libArduiPi_OLED.so.1.0" ]; then
        # Library was built but not installed, copy it manually
        print_info "Manually installing library files..."
        cp -a libArduiPi_OLED.so* $LOCAL_PREFIX/lib/
        cp -a *.h $LOCAL_PREFIX/include/
        print_info "Library files copied to $LOCAL_PREFIX"
    else
        print_error "Library build failed - libArduiPi_OLED.so.1.0 not found"
        exit 1
    fi
    
    cd ..
}

build_software() {
    # Build OLED library first for ARM platforms
    if [ "$BUILD_ARM_DISPLAY" = true ]; then
        build_oled_library
        patch_arm_makefile
    fi
    
    print_message "Building MMDVMHost..."
    cd MMDVMHost
    
    make clean || true
    
    # Standard build flags
    export CFLAGS="-O2 -Wall -g"
    export CXXFLAGS="-O2 -Wall -g"
    
    # Build with appropriate options for architecture
    if [ "$BUILD_ARM_DISPLAY" = true ]; then
        # ARM builds with OLED/HD44780 support
        if [ -f "Makefile.Pi.OLED" ]; then
            print_info "Building with OLED and HD44780 display support..."
            
            # Set library paths for OLED support
            export LIBRARY_PATH="$(pwd)/../oled-install/lib:$LIBRARY_PATH"
            export CPATH="$(pwd)/../oled-install/include:$CPATH"
            export LD_LIBRARY_PATH="$(pwd)/../oled-install/lib:$LD_LIBRARY_PATH"
            
            # Additional flags for the build
            export CFLAGS="$CFLAGS -I$(pwd)/../oled-install/include"
            export CXXFLAGS="$CXXFLAGS -I$(pwd)/../oled-install/include"
            export LDFLAGS="-L$(pwd)/../oled-install/lib -Wl,-rpath,/usr/lib/mmdvmhost"
            
            # Build with the OLED-enabled Makefile
            make -f Makefile.Pi.OLED -j$(nproc) all
        else
            print_warning "Makefile.Pi.OLED not found, using standard Makefile"
            make -j$(nproc) all
        fi
    else
        # Standard x86/other builds
        make -j$(nproc) all
    fi
    
    if [ ! -f "MMDVMHost" ]; then
        print_error "Build failed - MMDVMHost binary not created"
        exit 1
    fi
    
    # Build RemoteCommand if it exists
    if [ -f "RemoteCommand.cpp" ]; then
        make RemoteCommand || true
    fi
    
    cd ..
    
    print_message "Building MMDVMCal..."
    cd MMDVMCal
    
    make clean || true
    make -j$(nproc) all
    
    if [ ! -f "MMDVMCal" ]; then
        print_error "Build failed - MMDVMCal binary not created"
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
    if [ "$BUILD_ARM_DISPLAY" = true ]; then
        print_info "Display support: OLED and HD44780 enabled"
    fi
    
    # Create package directory structure
    PKG_DIR="$BUILD_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}"
    mkdir -p "$PKG_DIR/DEBIAN"
    mkdir -p "$PKG_DIR/usr/bin"
    mkdir -p "$PKG_DIR/usr/share/doc/mmdvmhost"
    mkdir -p "$PKG_DIR/etc/mmdvmhost"
    mkdir -p "$PKG_DIR/lib/systemd/system"
    mkdir -p "$PKG_DIR/var/lib/mmdvmhost"
    mkdir -p "$PKG_DIR/var/log/mmdvmhost"
    
    # Create library directory for ARM OLED support
    if [ "$BUILD_ARM_DISPLAY" = true ]; then
        mkdir -p "$PKG_DIR/usr/lib/mmdvmhost"
        mkdir -p "$PKG_DIR/usr/include/mmdvmhost"
    fi
    
    # Copy binaries
    cp "MMDVMHost/MMDVMHost" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/MMDVMHost"
    
    cp "MMDVMCal/MMDVMCal" "$PKG_DIR/usr/bin/"
    chmod 755 "$PKG_DIR/usr/bin/MMDVMCal"
    
    if [ -f "MMDVMHost/RemoteCommand" ]; then
        cp "MMDVMHost/RemoteCommand" "$PKG_DIR/usr/bin/"
        chmod 755 "$PKG_DIR/usr/bin/RemoteCommand"
    fi
    
    # Copy OLED library and headers for ARM platforms
    if [ "$BUILD_ARM_DISPLAY" = true ] && [ -d "oled-install" ]; then
        print_info "Installing OLED library files..."
        
        # Copy library files
        if [ -f "oled-install/lib/libArduiPi_OLED.so.1.0" ]; then
            cp -a oled-install/lib/libArduiPi_OLED.so* "$PKG_DIR/usr/lib/mmdvmhost/"
        elif [ -f "oled-install/lib/libArduiPi_OLED.so" ]; then
            cp -L oled-install/lib/libArduiPi_OLED.so "$PKG_DIR/usr/lib/mmdvmhost/libArduiPi_OLED.so.1.0"
            cd "$PKG_DIR/usr/lib/mmdvmhost"
            ln -sf libArduiPi_OLED.so.1.0 libArduiPi_OLED.so.1
            ln -sf libArduiPi_OLED.so.1.0 libArduiPi_OLED.so
            cd - > /dev/null
        fi
        
        # Copy header files for development
        if [ -d "oled-install/include" ]; then
            cp -a oled-install/include/*.h "$PKG_DIR/usr/include/mmdvmhost/" 2>/dev/null || true
        fi
        
        # Copy OLED examples if they exist
        if [ -d "ArduiPi_OLED/examples" ]; then
            mkdir -p "$PKG_DIR/usr/share/doc/mmdvmhost/oled-examples"
            cp -r ArduiPi_OLED/examples/* "$PKG_DIR/usr/share/doc/mmdvmhost/oled-examples/" 2>/dev/null || true
        fi
    fi
    
    # Copy config with display options commented out
    if [ -f "MMDVMHost/MMDVM.ini" ]; then
        cp "MMDVMHost/MMDVM.ini" "$PKG_DIR/etc/mmdvmhost/MMDVM.ini"
        
        # Add display configuration examples as comments for ARM builds
        if [ "$BUILD_ARM_DISPLAY" = true ]; then
            cat >> "$PKG_DIR/etc/mmdvmhost/MMDVM.ini" << 'EOF'

# Display Support Examples (uncomment and configure as needed)
# 
# For OLED displays:
# [OLED]
# Type=3
# Brightness=0
# Invert=0
# Scroll=1
# Rotate=0
# Cast=0
# 
# For HD44780 LCD with I2C PCF8574:
# [HD44780]
# Rows=4
# Columns=20
# # I2C addresses vary, common ones are 0x27 or 0x3F
# I2CAddress=0x27
# PWM=0
# PWMPin=
# PWMBright=100
# PWMDim=16
# DisplayClock=1
# UTC=0
EOF
        fi
    fi
    
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
    done
    
    # Add OLED documentation for ARM builds
    if [ "$BUILD_ARM_DISPLAY" = true ] && [ -f "ArduiPi_OLED/README.md" ]; then
        cp "ArduiPi_OLED/README.md" "$PKG_DIR/usr/share/doc/mmdvmhost/ArduiPi_OLED-README.md"
    fi
    
    # Create systemd service with library path for ARM
    if [ "$BUILD_ARM_DISPLAY" = true ]; then
        cat > "$PKG_DIR/lib/systemd/system/mmdvmhost.service" << 'EOF'
[Unit]
Description=MMDVM Host Service with Display Support
After=network.target

[Service]
Type=simple
Environment="LD_LIBRARY_PATH=/usr/lib/mmdvmhost:$LD_LIBRARY_PATH"
ExecStart=/usr/bin/MMDVMHost /etc/mmdvmhost/MMDVM.ini
Restart=on-failure
RestartSec=5
User=nobody
Group=nogroup
WorkingDirectory=/var/lib/mmdvmhost

[Install]
WantedBy=multi-user.target
EOF
    else
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
    fi
    
    # Create changelog
    CHANGELOG_CONTENT="  * Package built from git commits:
    - MMDVMHost: ${GIT_COMMIT_FULL}
    - MMDVMCal: ${CAL_COMMIT_FULL}"
    
    if [ "$BUILD_ARM_DISPLAY" = true ] && [ -n "$OLED_COMMIT_FULL" ]; then
        CHANGELOG_CONTENT="$CHANGELOG_CONTENT
    - ArduiPi_OLED: ${OLED_COMMIT_FULL}"
    fi
    
    CHANGELOG_CONTENT="$CHANGELOG_CONTENT
  * Built for Debian ${DEBIAN_VERSION}
  * Build number: ${BUILD_NUMBER}"
    
    if [ "$BUILD_ARM_DISPLAY" = true ]; then
        CHANGELOG_CONTENT="$CHANGELOG_CONTENT
  * ARM build with OLED and HD44780 display support
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

Files: ArduiPi_OLED/*
Copyright: Charles-Henri Hallard and contributors
License: MIT
EOF
    
    # Set dependencies based on Debian version and architecture
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
    
    # Add ARM-specific dependencies
    if [ "$PKG_ARCH" = "armhf" ] || [ "$PKG_ARCH" = "arm64" ] || [ "$PKG_ARCH" = "aarch64" ]; then
        DEPENDS="$DEPENDS, libi2c0"
        if [ "$BUILD_ARM_DISPLAY" = true ]; then
            # Add wiringpi as a dependency from our repository
            DEPENDS="$DEPENDS, wiringpi (>= 3.0), i2c-tools"
            SUGGESTS="python3-smbus, python3-dev"
            RECOMMENDS="wiringpi"
        fi
    fi
    
    # Create control file
    DESCRIPTION="MMDVM Host Software and Calibration Tool
 Multi-Mode Digital Voice Modem Host Software
 Supports D-Star, DMR, YSF, P25, NXDN, M17 and POCSAG
 Includes MMDVMCal calibration tool"
    
    if [ "$BUILD_ARM_DISPLAY" = true ]; then
        DESCRIPTION="$DESCRIPTION
 .
 This ARM build includes support for:
 - OLED displays (SSD1306, SH1106)
 - HD44780 LCD displays with I2C PCF8574 expander
 - Direct GPIO and I2C interfaces
 - Uses wiringPi package from deb.pistar.uk"
    fi
    
    DESCRIPTION="$DESCRIPTION
 .
 Built for Debian ${DEBIAN_VERSION}
 Git commits: MMDVMHost ${GIT_COMMIT}, MMDVMCal ${CAL_COMMIT}"
    
    if [ "$BUILD_ARM_DISPLAY" = true ] && [ -n "$OLED_COMMIT" ]; then
        DESCRIPTION="$DESCRIPTION, ArduiPi_OLED ${OLED_COMMIT}"
    fi
    
    cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: ${PACKAGE_NAME}
Version: ${FULL_VERSION}
Section: hamradio
Priority: optional
Architecture: ${PKG_ARCH}
Depends: ${DEPENDS}
EOF
    
    if [ -n "$SUGGESTS" ]; then
        echo "Suggests: ${SUGGESTS}" >> "$PKG_DIR/DEBIAN/control"
    fi
    
    if [ -n "$RECOMMENDS" ]; then
        echo "Recommends: ${RECOMMENDS}" >> "$PKG_DIR/DEBIAN/control"
    fi
    
    cat >> "$PKG_DIR/DEBIAN/control" << EOF
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
        # Reload systemd to pick up the new service
        if [ -d /run/systemd/system ]; then
            systemctl daemon-reload >/dev/null || true
        fi
        
        # Set up library cache for OLED library if present
        if [ -d /usr/lib/mmdvmhost ]; then
            echo "/usr/lib/mmdvmhost" > /etc/ld.so.conf.d/mmdvmhost.conf
            ldconfig || true
        fi
        
        # Enable I2C on Raspberry Pi if needed (but don't fail if not Pi)
        if [ -f /boot/config.txt ] && ! grep -q "^dtparam=i2c_arm=on" /boot/config.txt; then
            echo "# Enable I2C for MMDVM displays" >> /boot/config.txt
            echo "dtparam=i2c_arm=on" >> /boot/config.txt
            echo "Note: I2C has been enabled in /boot/config.txt. Reboot required." >&2
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
        # Remove include directory if empty
        if [ -d /usr/include/mmdvmhost ]; then
            rmdir --ignore-fail-on-non-empty /usr/include/mmdvmhost || true
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
    
    # Create prerm script for stopping service
    cat > "$PKG_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/sh
set -e

case "$1" in
    remove|upgrade|deconfigure)
        # Stop the service if it's running
        if [ -d /run/systemd/system ]; then
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
    if [ -f "$PKG_DIR/etc/mmdvmhost/MMDVM.ini" ]; then
        echo "/etc/mmdvmhost/MMDVM.ini" > "$PKG_DIR/DEBIAN/conffiles"
    fi
    
    # Add shlibs for OLED library if present
    if [ "$BUILD_ARM_DISPLAY" = true ] && [ -f "$PKG_DIR/usr/lib/mmdvmhost/libArduiPi_OLED.so.1.0" ]; then
        cat > "$PKG_DIR/DEBIAN/shlibs" << EOF
libArduiPi_OLED 1 mmdvmhost (>= ${VERSION})
EOF
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
        print_info "Package contents (first 40 files):"
        dpkg-deb -c "$DEB_FILE" | head -40
        print_info "Package size:"
        ls -lh "$DEB_FILE"
        
        # Check for display support files on ARM
        if [ "$BUILD_ARM_DISPLAY" = true ]; then
            print_info "Checking for display support files..."
            if dpkg-deb -c "$DEB_FILE" | grep -q "libArduiPi_OLED"; then
                print_info "✓ OLED library found in package"
            else
                print_warning "⚠ OLED library not found in package"
            fi
            
            # Check for wiringPi dependency
            if dpkg-deb -I "$DEB_FILE" | grep -q "wiringpi"; then
                print_info "✓ wiringPi dependency correctly set"
            else
                print_warning "⚠ wiringPi dependency not found"
            fi
        fi
    else
        print_error "Package file not found: $DEB_FILE"
        exit 1
    fi
}

# MAIN EXECUTION
print_message "Starting build for $PACKAGE_NAME"
print_info "Build script version: 2.6.0"

# Detect architecture first
detect_architecture

# Check for required build dependencies
check_build_dependencies

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

print_message "Build completed successfully!"
print_info "Package: $OUTPUT_DIR/${PACKAGE_NAME}_${FULL_VERSION}_${PKG_ARCH}.deb"

if [ "$BUILD_ARM_DISPLAY" = true ]; then
    print_info "This package includes OLED and HD44780 display support for ARM platforms"
    print_info "wiringPi dependency will be installed from deb.pistar.uk repository"
    print_info "Configure display settings in /etc/mmdvmhost/MMDVM.ini after installation"
fi