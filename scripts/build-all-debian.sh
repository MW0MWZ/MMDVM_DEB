#!/bin/bash
set -e

# Master build script for all Debian packages
# This script builds all packages and prepares them for deployment to GitHub Pages

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DEBIAN_VERSIONS=("bullseye" "bookworm")  # Debian 11 and 12
ARCHITECTURES=("amd64" "arm64" "armhf")
PACKAGES=("aprsclients" "dmrclients" "dstarclients" "ysfclients" "nxdnclients" "p25clients" "pocsagclients" "fmclients" "mmdvmhost")
REPO_BASE="repo"  # Root of repository structure (no /deb subdirectory)
GPG_KEY_ID="andy@mw0mwz.co.uk"  # Update with your GPG key

# Function to print colored messages
print_message() {
    echo -e "${GREEN}[BUILD]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Function to detect current architecture
detect_architecture() {
    local arch=$(dpkg --print-architecture)
    case "$arch" in
        amd64|x86_64)
            echo "amd64"
            ;;
        arm64|aarch64)
            echo "arm64"
            ;;
        armhf)
            echo "armhf"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# Function to setup repository structure
setup_repo_structure() {
    print_message "Setting up repository structure..."
    
    for debian_version in "${DEBIAN_VERSIONS[@]}"; do
        for arch in "${ARCHITECTURES[@]}"; do
            mkdir -p "$REPO_BASE/$debian_version/main/binary-$arch"
        done
        mkdir -p "$REPO_BASE/$debian_version/main/source"
    done
    
    # Create repo configuration
    for debian_version in "${DEBIAN_VERSIONS[@]}"; do
        cat > "$REPO_BASE/$debian_version/main/Release" << EOF
Archive: $debian_version
Component: main
Origin: Ham Radio Packages
Label: Ham Radio Packages for $debian_version
Architecture: amd64 arm64 armhf
Description: Amateur Radio Digital Voice packages
EOF
    done
}

# Function to build a package
build_package() {
    local package=$1
    local arch=$2
    local debian_version=$3
    
    print_info "Building $package for $arch on $debian_version..."
    
    # Check if package directory exists
    if [ ! -d "packages/$package" ]; then
        print_error "Package directory packages/$package not found"
        return 1
    fi
    
    # Check if build script exists
    if [ ! -f "packages/$package/build.sh" ]; then
        print_error "Build script packages/$package/build.sh not found"
        return 1
    fi
    
    # Create temporary output directory
    local temp_output="packages/$package/output"
    mkdir -p "$temp_output"
    
    # Run build script
    (
        cd "packages/$package"
        
        # Set environment for cross-compilation if needed
        if [ "$arch" != "$(detect_architecture)" ]; then
            print_warning "Cross-compilation from $(detect_architecture) to $arch"
            export ARCH="$arch"
            export CROSS_COMPILE="true"
            
            case "$arch" in
                armhf)
                    export CC="arm-linux-gnueabihf-gcc"
                    export CXX="arm-linux-gnueabihf-g++"
                    ;;
                arm64|aarch64)
                    export CC="aarch64-linux-gnu-gcc"
                    export CXX="aarch64-linux-gnu-g++"
                    ;;
            esac
        fi
        
        # Run the build
        ./build.sh
    )
    
    # Move built packages to repository structure
    local target_dir="$REPO_BASE/$debian_version/main/binary-$arch"
    
    if ls "$temp_output"/*.deb 1> /dev/null 2>&1; then
        mv "$temp_output"/*.deb "$target_dir/"
        print_message "Package $package built successfully for $arch"
    else
        print_warning "No .deb files found for $package"
    fi
    
    # Clean up
    rm -rf "$temp_output"
}

# Function to generate Packages files
generate_packages_files() {
    print_message "Generating Packages files..."
    
    for debian_version in "${DEBIAN_VERSIONS[@]}"; do
        for arch in "${ARCHITECTURES[@]}"; do
            local pkg_dir="$REPO_BASE/$debian_version/main/binary-$arch"
            
            if [ -d "$pkg_dir" ]; then
                print_info "Generating Packages file for $debian_version/$arch..."
                
                (
                    cd "$pkg_dir"
                    # Generate Packages file
                    dpkg-scanpackages . /dev/null > Packages
                    # Compress it
                    gzip -9c Packages > Packages.gz
                    bzip2 -9c Packages > Packages.bz2
                )
            fi
        done
    done
}

# Function to generate Release files
generate_release_files() {
    print_message "Generating Release files..."
    
    for debian_version in "${DEBIAN_VERSIONS[@]}"; do
        local release_dir="$REPO_BASE/$debian_version"
        
        print_info "Generating Release file for $debian_version..."
        
        cat > "$release_dir/Release" << EOF
Origin: Ham Radio Packages
Label: Ham Radio Packages
Suite: $debian_version
Codename: $debian_version
Version: 1.0
Architectures: amd64 arm64 armhf
Components: main
Description: Amateur Radio Digital Voice packages for Debian $debian_version
Date: $(date -R)
EOF
        
        # Add checksums for Packages files
        (
            cd "$release_dir"
            
            # MD5Sum
            echo "MD5Sum:" >> Release
            for arch in "${ARCHITECTURES[@]}"; do
                if [ -f "main/binary-$arch/Packages" ]; then
                    echo " $(md5sum main/binary-$arch/Packages | cut -d' ' -f1) $(stat -c%s main/binary-$arch/Packages) main/binary-$arch/Packages" >> Release
                fi
                if [ -f "main/binary-$arch/Packages.gz" ]; then
                    echo " $(md5sum main/binary-$arch/Packages.gz | cut -d' ' -f1) $(stat -c%s main/binary-$arch/Packages.gz) main/binary-$arch/Packages.gz" >> Release
                fi
            done
            
            # SHA256
            echo "SHA256:" >> Release
            for arch in "${ARCHITECTURES[@]}"; do
                if [ -f "main/binary-$arch/Packages" ]; then
                    echo " $(sha256sum main/binary-$arch/Packages | cut -d' ' -f1) $(stat -c%s main/binary-$arch/Packages) main/binary-$arch/Packages" >> Release
                fi
                if [ -f "main/binary-$arch/Packages.gz" ]; then
                    echo " $(sha256sum main/binary-$arch/Packages.gz | cut -d' ' -f1) $(stat -c%s main/binary-$arch/Packages.gz) main/binary-$arch/Packages.gz" >> Release
                fi
            done
        )
        
        # Sign Release file if GPG key is available
        if command -v gpg &> /dev/null && gpg --list-secret-keys "$GPG_KEY_ID" &> /dev/null; then
            print_info "Signing Release file for $debian_version..."
            gpg --default-key "$GPG_KEY_ID" -abs -o "$release_dir/Release.gpg" "$release_dir/Release"
            gpg --default-key "$GPG_KEY_ID" --clearsign -o "$release_dir/InRelease" "$release_dir/Release"
        else
            print_warning "GPG key not found, skipping Release file signing"
        fi
    done
}

# Function to export GPG public key
export_gpg_key() {
    if command -v gpg &> /dev/null && gpg --list-keys "$GPG_KEY_ID" &> /dev/null; then
        print_message "Exporting GPG public key..."
        gpg --armor --export "$GPG_KEY_ID" > "$REPO_BASE/hamradio.gpg"
    else
        print_warning "GPG key not found, skipping key export"
    fi
}

# Function to create APT repository instructions
create_apt_instructions() {
    print_message "Creating APT repository instructions..."
    
    cat > "$REPO_BASE/README.md" << 'EOF'
# Ham Radio Debian Repository

## Adding this repository to your system

### 1. Add the GPG key:
```bash
wget -qO - https://deb.pistar.uk/hamradio.gpg | sudo apt-key add -
```

Or for newer Debian/Ubuntu systems:
```bash
wget -qO - https://deb.pistar.uk/hamradio.gpg | sudo tee /usr/share/keyrings/hamradio.gpg > /dev/null
```

### 2. Add the repository:

For Debian 11 (Bullseye):
```bash
echo "deb https://deb.pistar.uk/ bullseye main" | sudo tee /etc/apt/sources.list.d/hamradio.list
```

For Debian 12 (Bookworm):
```bash
echo "deb https://deb.pistar.uk/ bookworm main" | sudo tee /etc/apt/sources.list.d/hamradio.list
```

### 3. Update and install packages:
```bash
sudo apt update
sudo apt install mmdvmhost dmrclients ysfclients
```

## Available Packages

- **mmdvmhost** - MMDVM Host Software and Calibration Tool
- **dmrclients** - DMR Gateway and Cross-Mode converters
- **ysfclients** - YSF Gateway, Parrot, and Cross-Mode converters
- **dstarclients** - D-Star ircDDB Gateway and DStarGateway
- **nxdnclients** - NXDN Gateway, Parrot and Cross-Mode converters
- **p25clients** - P25 Gateway and Parrot
- **aprsclients** - APRS Gateway
- **pocsagclients** - DAPNET Gateway for POCSAG
- **fmclients** - FM Gateway

## Architectures Supported

- amd64 (x86_64)
- arm64 (aarch64)
- armhf (32-bit ARM)

## Source Code

All source code is available at:
- https://github.com/g4klx/
EOF
}

# Function to generate statistics
generate_statistics() {
    print_message "Generating repository statistics..."
    
    echo "# Repository Statistics" > "$REPO_BASE/STATS.md"
    echo "Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >> "$REPO_BASE/STATS.md"
    echo "" >> "$REPO_BASE/STATS.md"
    
    for debian_version in "${DEBIAN_VERSIONS[@]}"; do
        echo "## Debian $debian_version" >> "$REPO_BASE/STATS.md"
        
        for arch in "${ARCHITECTURES[@]}"; do
            local pkg_dir="$REPO_BASE/$debian_version/main/binary-$arch"
            if [ -d "$pkg_dir" ]; then
                local count=$(find "$pkg_dir" -name "*.deb" 2>/dev/null | wc -l)
                local size=$(du -sh "$pkg_dir" 2>/dev/null | cut -f1)
                echo "- **$arch**: $count packages ($size)" >> "$REPO_BASE/STATS.md"
            fi
        done
        echo "" >> "$REPO_BASE/STATS.md"
    done
}

# Main execution
main() {
    print_header "Ham Radio Debian Package Builder"
    
    # Check dependencies
    print_message "Checking build dependencies..."
    local missing_deps=()
    for tool in dpkg-scanpackages dpkg-deb gpg; do
        if ! command -v "$tool" &> /dev/null; then
            missing_deps+=("$tool")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_info "Install with: sudo apt-get install dpkg-dev gnupg"
        exit 1
    fi
    
    # Setup repository structure
    setup_repo_structure
    
    # Determine which architecture to build for
    CURRENT_ARCH=$(detect_architecture)
    print_info "Current architecture: $CURRENT_ARCH"
    
    # Build all packages
    for package in "${PACKAGES[@]}"; do
        print_header "Building $package"
        
        for debian_version in "${DEBIAN_VERSIONS[@]}"; do
            # For now, build only for current architecture
            # Cross-compilation can be enabled by uncommenting the loop below
            # for arch in "${ARCHITECTURES[@]}"; do
            #     build_package "$package" "$arch" "$debian_version"
            # done
            
            build_package "$package" "$CURRENT_ARCH" "$debian_version"
        done
    done
    
    # Generate repository metadata
    print_header "Generating Repository Metadata"
    generate_packages_files
    generate_release_files
    export_gpg_key
    create_apt_instructions
    generate_statistics
    
    print_header "Build Complete!"
    print_message "Repository created in: $REPO_BASE"
    print_message "Ready for deployment to GitHub Pages"
    
    # Show summary
    print_info "Repository structure:"
    tree -L 3 "$REPO_BASE" 2>/dev/null || ls -la "$REPO_BASE"
}

# Run main function
main "$@"