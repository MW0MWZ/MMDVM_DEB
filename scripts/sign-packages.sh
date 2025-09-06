#!/bin/bash
set -e

# Script to sign Debian packages and Release files with GPG

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[SIGN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Configuration
REPO_DIR="${1:-./deploy}"
GPG_KEY="${GPG_KEY_ID:-repo@pistar.uk}"

# Check if GPG is available
if ! command -v gpg &> /dev/null; then
    print_error "GPG is not installed"
    exit 1
fi

# Check if key exists
if ! gpg --list-secret-keys "$GPG_KEY" &> /dev/null; then
    print_error "GPG key $GPG_KEY not found"
    print_info "Generate one with: scripts/generate-gpg-key.sh"
    exit 1
fi

# Sign Release files
print_message "Signing Release files..."
for dist in bullseye bookworm; do
    RELEASE_FILE="$REPO_DIR/dists/$dist/Release"
    
    if [ -f "$RELEASE_FILE" ]; then
        print_info "Signing $dist Release file..."
        
        # Create detached signature
        gpg --default-key "$GPG_KEY" \
            --armor \
            --detach-sign \
            --output "${RELEASE_FILE}.gpg" \
            "$RELEASE_FILE"
        
        # Create inline signature (InRelease)
        gpg --default-key "$GPG_KEY" \
            --armor \
            --clearsign \
            --output "$REPO_DIR/dists/$dist/InRelease" \
            "$RELEASE_FILE"
        
        print_message "Signed $dist repository"
    else
        print_warning "Release file not found for $dist"
    fi
done

# Optionally sign individual packages
if [ "${SIGN_PACKAGES:-false}" = "true" ]; then
    print_message "Signing individual packages..."
    
    find "$REPO_DIR/pool" -name "*.deb" -type f | while read -r deb; do
        print_info "Signing $(basename "$deb")..."
        dpkg-sig --sign builder -k "$GPG_KEY" "$deb"
    done
fi

print_message "Signing complete!"