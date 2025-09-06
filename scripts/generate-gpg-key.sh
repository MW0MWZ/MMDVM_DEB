#!/bin/bash
set -e

# Script to generate GPG key for package signing
# This should be run once to create the repository signing key

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[GPG]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Configuration
KEY_NAME="Ham Radio Repository"
KEY_EMAIL="repo@pistar.uk"
KEY_COMMENT="Debian package signing key"
KEY_TYPE="RSA"
KEY_LENGTH="4096"
KEY_EXPIRE="2y"

# Check if GPG is installed
if ! command -v gpg &> /dev/null; then
    print_error "GPG is not installed"
    print_info "Install with: sudo apt-get install gnupg"
    exit 1
fi

# Check if key already exists
if gpg --list-secret-keys "$KEY_EMAIL" &> /dev/null; then
    print_warning "GPG key for $KEY_EMAIL already exists"
    read -p "Do you want to regenerate it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Exporting existing key..."
        gpg --armor --export "$KEY_EMAIL" > keys/public.asc
        gpg --armor --export "$KEY_EMAIL" > keys/hamradio.gpg
        print_message "Public key exported to keys/public.asc and keys/hamradio.gpg"
        exit 0
    fi
fi

print_message "Generating new GPG key..."

# Create GPG batch file for unattended key generation
cat > /tmp/gpg-batch.txt << EOF
%echo Generating GPG key for package signing...
Key-Type: $KEY_TYPE
Key-Length: $KEY_LENGTH
Subkey-Type: $KEY_TYPE
Subkey-Length: $KEY_LENGTH
Name-Real: $KEY_NAME
Name-Email: $KEY_EMAIL
Name-Comment: $KEY_COMMENT
Expire-Date: $KEY_EXPIRE
%no-protection
%commit
%echo done
EOF

# Generate the key
gpg --batch --generate-key /tmp/gpg-batch.txt

# Clean up
rm -f /tmp/gpg-batch.txt

# Export public key
print_message "Exporting public key..."
mkdir -p keys
gpg --armor --export "$KEY_EMAIL" > keys/public.asc
gpg --armor --export "$KEY_EMAIL" > keys/hamradio.gpg

# Export private key (for backup - KEEP THIS SECURE!)
print_warning "Exporting private key for backup..."
gpg --armor --export-secret-keys "$KEY_EMAIL" > keys/private.key

print_message "GPG key generation complete!"
print_info "Public key: keys/public.asc and keys/hamradio.gpg"
print_warning "Private key: keys/private.key (KEEP THIS SECURE!)"

# Display key info
print_info "Key fingerprint:"
gpg --fingerprint "$KEY_EMAIL"

# Instructions for GitHub
cat << EOF

${GREEN}Next steps:${NC}

1. Add the private key to GitHub Secrets:
   - Go to Settings > Secrets and variables > Actions
   - Create a new secret named GPG_PRIVATE_KEY
   - Paste the contents of keys/private.key

2. Add the passphrase (if any) to GitHub Secrets:
   - Create a new secret named GPG_PASSPHRASE
   - Enter the passphrase used for the key

3. Commit the public key files:
   git add keys/public.asc keys/hamradio.gpg
   git commit -m "Add GPG public key for package signing"
   git push

${YELLOW}IMPORTANT:${NC} Never commit the private key (keys/private.key) to the repository!
Add it to .gitignore if not already there.

EOF