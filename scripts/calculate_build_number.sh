#!/bin/bash
set -e

# Calculate build number for Debian packages
# Checks existing repository and increments only when needed

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Required parameters
PACKAGE_NAME="${1:-}"
VERSION="${2:-}"
DEB_VERSION_SUFFIX="${3:-}"
ARCH="${4:-}"
REPO_URL="${5:-}"

# Validate parameters
if [ -z "$PACKAGE_NAME" ] || [ -z "$VERSION" ] || [ -z "$DEB_VERSION_SUFFIX" ] || [ -z "$ARCH" ] || [ -z "$REPO_URL" ]; then
    print_error "Usage: $0 <package_name> <version> <deb_version_suffix> <arch> <repo_url>"
    print_error "Example: $0 dstarrepeater 2021.12.12 ~deb13u1 amd64 https://repo.example.com/debian"
    exit 1
fi

print_info "Calculating build number for: ${PACKAGE_NAME}_${VERSION}"
print_info "Debian suffix: ${DEB_VERSION_SUFFIX}"
print_info "Architecture: ${ARCH}"
print_info "Repository: ${REPO_URL}"

# Function to extract build number from filename
extract_build_number() {
    local filename="$1"
    # Extract the number between VERSION- and DEB_VERSION_SUFFIX
    # Example: dstarrepeater_2021.12.12-105~deb13u1_amd64.deb -> 105
    echo "$filename" | sed -n "s/.*${VERSION}-\([0-9]\+\)${DEB_VERSION_SUFFIX}.*/\1/p"
}

# Initialize build number
BUILD_NUMBER=0
FOUND_EXISTING=false

# Create temp directory for package list
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Try to fetch the Packages file from the repo
# This works for both flat and pool-style repositories
print_info "Fetching package list from repository..."

# Try different possible Packages file locations
PACKAGES_URLS=(
    "${REPO_URL}/Packages"
    "${REPO_URL}/Packages.gz"
    "${REPO_URL}/dists/stable/main/binary-${ARCH}/Packages"
    "${REPO_URL}/dists/stable/main/binary-${ARCH}/Packages.gz"
    "${REPO_URL}/dists/unstable/main/binary-${ARCH}/Packages"
    "${REPO_URL}/dists/unstable/main/binary-${ARCH}/Packages.gz"
)

PACKAGES_FOUND=false
for url in "${PACKAGES_URLS[@]}"; do
    print_info "Trying: $url"
    if curl -sf -o "$TEMP_DIR/Packages.gz" "$url" 2>/dev/null; then
        if [[ "$url" == *.gz ]]; then
            gunzip "$TEMP_DIR/Packages.gz"
        else
            mv "$TEMP_DIR/Packages.gz" "$TEMP_DIR/Packages"
        fi
        PACKAGES_FOUND=true
        print_success "Found Packages file at: $url"
        break
    fi
done

if [ "$PACKAGES_FOUND" = false ]; then
    # Fallback: try to list directory (works for simple HTTP indexes)
    print_info "Packages file not found, trying directory listing..."
    if curl -sf -o "$TEMP_DIR/index.html" "${REPO_URL}/" 2>/dev/null; then
        # Extract .deb filenames from HTML directory listing
        grep -oP 'href="[^"]*\.deb"' "$TEMP_DIR/index.html" | sed 's/href="//;s/"//' > "$TEMP_DIR/deb_files.txt" || true
        
        if [ -s "$TEMP_DIR/deb_files.txt" ]; then
            print_info "Found $(wc -l < "$TEMP_DIR/deb_files.txt") .deb files in directory listing"
            
            # Find matching packages
            PATTERN="${PACKAGE_NAME}_${VERSION}-[0-9]*${DEB_VERSION_SUFFIX}_${ARCH}.deb"
            HIGHEST=-1
            
            while IFS= read -r filename; do
                if [[ "$filename" =~ ${PACKAGE_NAME}_${VERSION}-([0-9]+)${DEB_VERSION_SUFFIX}_${ARCH}\.deb ]]; then
                    BUILD_NUM="${BASH_REMATCH[1]}"
                    print_info "Found existing package: $filename (build number: $BUILD_NUM)"
                    FOUND_EXISTING=true
                    if [ "$BUILD_NUM" -gt "$HIGHEST" ]; then
                        HIGHEST=$BUILD_NUM
                    fi
                fi
            done < "$TEMP_DIR/deb_files.txt"
            
            if [ "$FOUND_EXISTING" = true ]; then
                BUILD_NUMBER=$((HIGHEST + 1))
                print_success "Found existing builds, highest: $HIGHEST, will use: $BUILD_NUMBER"
            else
                print_info "No existing packages found for this version, will use: 0"
            fi
        else
            print_info "No .deb files found in directory listing, will use: 0"
        fi
    else
        print_info "Could not fetch repository information, starting with build number: 0"
    fi
else
    # Parse the Packages file
    print_info "Parsing Packages file..."
    
    # Look for our package with the same version
    PATTERN="^Package: ${PACKAGE_NAME}$"
    HIGHEST=-1
    
    # Parse Packages file to find matching versions
    while IFS= read -r line; do
        if [[ "$line" =~ ^Package:\ ${PACKAGE_NAME}$ ]]; then
            # Found our package, now look for its version
            while IFS= read -r vline && [[ ! "$vline" =~ ^Package: ]] && [ -n "$vline" ]; do
                if [[ "$vline" =~ ^Version:\ ${VERSION}-([0-9]+)${DEB_VERSION_SUFFIX}$ ]]; then
                    BUILD_NUM="${BASH_REMATCH[1]}"
                    print_info "Found existing version: ${VERSION}-${BUILD_NUM}${DEB_VERSION_SUFFIX}"
                    FOUND_EXISTING=true
                    if [ "$BUILD_NUM" -gt "$HIGHEST" ]; then
                        HIGHEST=$BUILD_NUM
                    fi
                    break
                fi
            done
        fi
    done < "$TEMP_DIR/Packages"
    
    if [ "$FOUND_EXISTING" = true ]; then
        BUILD_NUMBER=$((HIGHEST + 1))
        print_success "Found existing builds, highest: $HIGHEST, will use: $BUILD_NUMBER"
    else
        print_info "No existing packages found for version ${VERSION}, will use: 0"
    fi
fi

# Output the result
echo "BUILD_NUMBER=${BUILD_NUMBER}"

# Also export for GitHub Actions if running in that environment
if [ -n "$GITHUB_OUTPUT" ]; then
    echo "build_number=${BUILD_NUMBER}" >> "$GITHUB_OUTPUT"
    print_success "Set GitHub Actions output: build_number=${BUILD_NUMBER}"
fi

# Also export as environment variable
export BUILD_NUMBER

print_success "Build number calculated: ${BUILD_NUMBER}"