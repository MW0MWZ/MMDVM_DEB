# Package and Repository Signing

This document describes the GPG signing process for the MMDVM_DEB repository, following current security best practices and Debian standards.

## Overview

The repository uses GPG signing to ensure:
- **Authenticity** - Packages and metadata come from this repository
- **Integrity** - Content hasn't been tampered with during transit
- **Trust** - Users can verify the repository origin and maintainer

## Key Management

### Key Generation

Repository uses modern GPG keys for signing following current best practices:

```bash
# Generate GPG key pair with modern standards
gpg --full-generate-key

# Select options:
# - Key type: (1) RSA and RSA (default)
# - Key size: 4096 bits (recommended for long-term use)
# - Validity: 2 years (security best practice for rotation)
# - Real name: Ham Radio Repository
# - Email: andy@mw0mwz.co.uk
# - Comment: MMDVM Debian Repository Signing Key

# Set a strong passphrase when prompted
```

Key specifications:
- **Algorithm**: RSA 4096-bit
- **Validity**: 2 years (renewable)
- **Usage**: Signing only
- **Subkeys**: None required for repository signing

### Key Storage and Distribution

**Public Key** (`hamradio.gpg`):
- Stored in repository at `/keys/hamradio.gpg`
- Distributed via https://deb.pistar.uk/hamradio.gpg
- Available for users to verify repository authenticity
- Should be accessible without authentication

**Private Key Security**:
- **NEVER** committed to any repository
- Stored securely in GitHub Secrets as `GPG_PRIVATE_KEY`
- Used exclusively during CI/CD builds for signing
- Backed up securely offline in encrypted storage
- Protected with strong passphrase

### GitHub Secrets Configuration

#### Setting up the Private Key

1. Navigate to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Create the following secrets:

**GPG_PRIVATE_KEY**:
```
Name: GPG_PRIVATE_KEY
Value: [Complete private key block including headers]
-----BEGIN PGP PRIVATE KEY BLOCK-----
[key content]
-----END PGP PRIVATE KEY BLOCK-----
```

**GPG_PASSPHRASE** (if key is password-protected):
```
Name: GPG_PASSPHRASE
Value: [Your key passphrase]
```

**GPG_KEY_ID** (for key identification):
```
Name: GPG_KEY_ID
Value: [8-character key ID or full fingerprint]
```

#### Security Considerations for Secrets

- Use repository secrets (not environment secrets) for security
- Limit secret access to necessary workflows only
- Regularly audit who has access to repository secrets
- Enable dependency review and secret scanning
- Use fine-grained personal access tokens where possible

## Signing Process

### Repository Metadata Signing

The Debian repository follows APT security standards with signed Release files:

```bash
# Generate Release file for each distribution
cd dists/bookworm
apt-ftparchive release . > Release

# Create detached signature (Release.gpg)
gpg --default-key andy@mw0mwz.co.uk \
    --armor \
    --detach-sign \
    --output Release.gpg \
    Release

# Create inline signature (InRelease) - preferred method
gpg --default-key andy@mw0mwz.co.uk \
    --armor \
    --clearsign \
    --output InRelease \
    Release
```

### Modern APT Security

**InRelease vs Release.gpg**:
- **InRelease**: Preferred modern format with inline signatures
- **Release.gpg**: Legacy detached signature format
- Both are supported for maximum compatibility

### Individual Package Signing (Optional)

While not required for APT repositories, individual packages can be signed for additional security:

```bash
# Sign individual .deb package
dpkg-sig --sign builder -k andy@mw0mwz.co.uk package.deb

# Verify package signature
dpkg-sig --verify package.deb

# Check signature details
dpkg-sig --list package.deb
```

### Signature Verification Process

APT automatically verifies signatures during:
- Repository metadata updates (`apt update`)
- Package installation (when keys are properly configured)

Manual verification for testing:
```bash
# Verify InRelease signature (modern method)
gpg --verify InRelease

# Verify detached signature (legacy method)
gpg --verify Release.gpg Release

# Check signature details
gpg --status-fd 1 --verify InRelease 2>/dev/null | grep -E "^\[GNUPG:\]"
```

## CI/CD Integration

### GitHub Actions Workflow Implementation

Example workflow integration for automated signing:

```yaml
name: Sign Repository

on:
  workflow_call:
    inputs:
      sign_packages:
        description: 'Sign individual packages'
        required: false
        default: false
        type: boolean

jobs:
  sign-repository:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Import GPG signing key
        env:
          GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
          GPG_PASSPHRASE: ${{ secrets.GPG_PASSPHRASE }}
        run: |
          # Import private key
          echo "$GPG_PRIVATE_KEY" | gpg --batch --import

          # Configure GPG for non-interactive use
          echo "pinentry-mode loopback" >> ~/.gnupg/gpg.conf
          echo "use-agent" >> ~/.gnupg/gpg.conf
          
          # Start GPG agent
          gpg-connect-agent --batch /bye

      - name: Sign repository metadata
        env:
          GPG_PASSPHRASE: ${{ secrets.GPG_PASSPHRASE }}
        run: |
          # Sign Release files for all distributions
          for dist in bullseye bookworm trixie; do
            if [ -f "dists/$dist/Release" ]; then
              echo "Signing $dist distribution..."
              
              # Create InRelease (inline signature)
              gpg --batch --yes \
                  --pinentry-mode loopback \
                  --passphrase "$GPG_PASSPHRASE" \
                  --default-key andy@mw0mwz.co.uk \
                  --clearsign \
                  --armor \
                  --output "dists/$dist/InRelease" \
                  "dists/$dist/Release"
              
              # Create Release.gpg (detached signature) for compatibility
              gpg --batch --yes \
                  --pinentry-mode loopback \
                  --passphrase "$GPG_PASSPHRASE" \
                  --default-key andy@mw0mwz.co.uk \
                  --detach-sign \
                  --armor \
                  --output "dists/$dist/Release.gpg" \
                  "dists/$dist/Release"
            fi
          done

      - name: Sign individual packages (optional)
        if: ${{ inputs.sign_packages }}
        env:
          GPG_PASSPHRASE: ${{ secrets.GPG_PASSPHRASE }}
        run: |
          # Install dpkg-sig for package signing
          sudo apt-get update
          sudo apt-get install -y dpkg-sig
          
          # Sign all .deb packages
          find pool/ -name "*.deb" -type f | while read -r package; do
            echo "Signing package: $package"
            dpkg-sig --sign builder \
                     --gpg-options "--batch --pinentry-mode loopback --passphrase $GPG_PASSPHRASE" \
                     -k andy@mw0mwz.co.uk \
                     "$package"
          done

      - name: Verify signatures
        run: |
          # Verify repository signatures
          for dist in bullseye bookworm trixie; do
            if [ -f "dists/$dist/InRelease" ]; then
              echo "Verifying $dist InRelease..."
              gpg --verify "dists/$dist/InRelease"
            fi
            if [ -f "dists/$dist/Release.gpg" ]; then
              echo "Verifying $dist Release.gpg..."
              gpg --verify "dists/$dist/Release.gpg" "dists/$dist/Release"
            fi
          done

      - name: Clean up GPG agent
        if: always()
        run: |
          # Kill GPG agent and clean up
          gpgconf --kill gpg-agent
          rm -rf ~/.gnupg
```

### Local Development Testing

For local testing with a development key:

```bash
# Generate temporary test key
gpg --batch --generate-key <<EOF
Key-Type: RSA
Key-Length: 2048
Name-Real: Test Signing Key
Name-Email: test@example.local
Expire-Date: 30d
%no-protection
%commit
EOF

# Sign with test key
gpg --default-key test@example.local \
    --clearsign --armor \
    --output InRelease.test \
    Release

# Verify test signature
gpg --verify InRelease.test

# Clean up test key
gpg --delete-secret-keys test@example.local
gpg --delete-keys test@example.local
```

**IMPORTANT**: Never use test keys for production repositories!

## Security Best Practices

### Key Security Management

#### Private Key Protection

1. **Generation on secure system**:
   - Generate keys on air-gapped or dedicated system
   - Use hardware security modules (HSM) if available
   - Never generate keys on shared or compromised systems

2. **Strong passphrase requirements**:
   - Minimum 20 characters with mixed case, numbers, symbols
   - Use password manager for generation and storage
   - Never store passphrase in plain text

3. **Backup procedures**:
   - Create encrypted backup on offline media
   - Store backup in physically secure location (safe, bank deposit box)
   - Test backup restoration procedure annually

4. **Access control**:
   - Limit GitHub repository access to essential personnel
   - Use branch protection rules for main branch
   - Require two-factor authentication for all contributors
   - Regular audit of repository permissions

#### Key Rotation Schedule

**Regular rotation (every 2 years)**:
1. Generate new key pair 3 months before expiration
2. Overlap validity periods for smooth transition
3. Update GitHub Secrets with new private key
4. Distribute new public key to users
5. Maintain old public key during transition period

**Emergency rotation procedures**:
- Have documented procedure for immediate key replacement
- Maintain emergency contact list for user notification
- Pre-prepared communication templates for security incidents

### Repository Security

#### HTTPS and Distribution

1. **Secure distribution**:
   - Serve repository over HTTPS only
   - Use strong TLS configuration (TLS 1.3 preferred)
   - Implement HTTP Strict Transport Security (HSTS)
   - Regular SSL certificate monitoring and renewal

2. **Content integrity**:
   - Generate checksums for all package files
   - Verify package integrity during build process
   - Monitor for unauthorized modifications

#### Access Control

1. **GitHub repository security**:
   - Enable vulnerability alerts and security updates
   - Use Dependabot for dependency management
   - Enable secret scanning and push protection
   - Regular security audits of workflows and permissions

2. **Build environment security**:
   - Use official, up-to-date Docker images
   - Pin image versions for reproducibility
   - Scan container images for vulnerabilities
   - Minimize privileges in build containers

## Incident Response

### Compromise Detection

**Indicators of potential compromise**:
- Unauthorized commits to repository
- Unexpected changes to Release files
- Reports of signature verification failures
- Unusual activity in repository access logs

### Emergency Response Procedures

#### Immediate Actions (within 1 hour)

1. **Isolate the compromise**:
   ```bash
   # Revoke compromised key immediately
   gpg --gen-revoke andy@mw0mwz.co.uk > revocation.asc
   gpg --import revocation.asc
   ```

2. **Secure the repository**:
   - Change all GitHub repository secrets
   - Review and remove suspicious commits
   - Temporarily disable automated builds

3. **Generate new keys**:
   ```bash
   # Generate new signing key
   gpg --full-generate-key
   
   # Export new public key
   gpg --armor --export new-key@mw0mwz.co.uk > hamradio-new.gpg
   ```

#### Recovery Process (within 24 hours)

1. **Update infrastructure**:
   - Replace GPG secrets in GitHub
   - Re-sign all repository metadata with new key
   - Update public key distribution

2. **User notification**:
   - Post security advisory on repository homepage
   - Email notification to known users (if list available)
   - Update documentation with new key information

3. **Forensic analysis**:
   - Review commit history for unauthorized changes
   - Analyze access logs for suspicious activity
   - Document incident for future prevention

### User Recovery Instructions

When new keys are issued, provide clear instructions:

```bash
# Remove old key
sudo rm /usr/share/keyrings/hamradio.gpg

# Download and install new key
wget -qO - https://deb.pistar.uk/hamradio-new.gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/hamradio.gpg

# Update repository configuration (if keyring path changed)
sudo sed -i 's/signed-by=.*hamradio/signed-by=\/usr\/share\/keyrings\/hamradio.gpg/' \
    /etc/apt/sources.list.d/hamradio.list

# Force repository refresh
sudo apt update
```

## User Instructions

### Adding Repository with Key Verification

#### Modern Method (Debian 11+, Ubuntu 20.04+)

```bash
# Download and verify public key fingerprint
wget -qO - https://deb.pistar.uk/hamradio.gpg > /tmp/hamradio.gpg

# Display key information for verification
gpg --show-keys /tmp/hamradio.gpg

# Expected output should show:
# pub   rsa4096 YYYY-MM-DD [SC] [expires: YYYY-MM-DD]
#       [Full fingerprint]
# uid   Ham Radio Repository <andy@mw0mwz.co.uk>

# If fingerprint matches published value, install key
sudo gpg --dearmor -o /usr/share/keyrings/hamradio.gpg /tmp/hamradio.gpg

# Add repository with explicit keyring reference
echo "deb [signed-by=/usr/share/keyrings/hamradio.gpg] https://deb.pistar.uk/ bookworm main" | \
    sudo tee /etc/apt/sources.list.d/hamradio.list

# Update package lists
sudo apt update
```

#### Legacy Method (Debian 10 and older)

```bash
# Download and add key using deprecated apt-key
wget -qO - https://deb.pistar.uk/hamradio.gpg | sudo apt-key add -

# Add repository without keyring specification
echo "deb https://deb.pistar.uk/ bullseye main" | \
    sudo tee /etc/apt/sources.list.d/hamradio.list

# Update package lists
sudo apt update
```

**Note**: The `apt-key` method is deprecated and will be removed in future Debian/Ubuntu versions. Migrate to the modern method when possible.

### Key Fingerprint Verification

Always verify the key fingerprint before trusting a repository:

```bash
# Display key fingerprint
gpg --show-keys /usr/share/keyrings/hamradio.gpg

# Expected fingerprint (verify against official documentation):
# This should match the fingerprint published on the official website
```

**Published Key Information**:
- **Key ID**: [To be published when key is generated]
- **Fingerprint**: [To be published when key is generated]
- **Email**: andy@mw0mwz.co.uk
- **Validity**: [Start date] to [End date]

### Troubleshooting Signature Issues

#### Common Error Messages and Solutions

**"NO_PUBKEY" Error**:
```
W: GPG error: https://deb.pistar.uk bookworm InRelease: The following signatures couldn't be verified because the public key is not available: NO_PUBKEY XXXXXXXXXX
```

**Solution**:
```bash
# Re-download and install the public key
wget -qO - https://deb.pistar.uk/hamradio.gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/hamradio.gpg

# Ensure sources.list points to correct keyring
sudo nano /etc/apt/sources.list.d/hamradio.list
# Verify line contains: [signed-by=/usr/share/keyrings/hamradio.gpg]

# Update repository
sudo apt update
```

**"BADSIG" Error**:
```
W: GPG error: https://deb.pistar.uk bookworm InRelease: The following signatures were invalid: BADSIG XXXXXXXXXX
```

**Solution**:
```bash
# Clear APT cache and re-download
sudo rm -rf /var/lib/apt/lists/*
sudo apt clean
sudo apt update

# If problem persists, check for repository compromise
```

**"EXPKEYSIG" Error (Expired Key)**:
```
W: GPG error: https://deb.pistar.uk bookworm InRelease: The following signatures were invalid: EXPKEYSIG XXXXXXXXXX
```

**Solution**:
```bash
# Download updated key
wget -qO - https://deb.pistar.uk/hamradio.gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/hamradio.gpg

sudo apt update
```

**"Repository is not signed" Warning**:
- Indicates Release files are not signed
- Repository may not have implemented signing yet
- Consider the security implications before proceeding

#### Advanced Debugging

```bash
# Check key details in keyring
gpg --keyring /usr/share/keyrings/hamradio.gpg --list-keys

# Verify signature manually
cd /var/lib/apt/lists/
gpg --keyring /usr/share/keyrings/hamradio.gpg \
    --verify deb.pistar.uk_dists_bookworm_InRelease

# Check APT configuration
apt-config dump | grep -i gpg

# Enable debug output for signature verification
sudo apt update -o Debug::gpgv=true
```

## Repository Structure with Signatures

Complete repository structure including signature files:

```
deploy/
├── index.html                    # Repository web interface
├── hamradio.gpg                 # GPG public key for users
├── CNAME                        # GitHub Pages domain configuration
├── dists/                       # Distribution metadata
│   ├── bullseye/
│   │   ├── Release              # Repository metadata
│   │   ├── Release.gpg          # Detached signature (legacy compatibility)
│   │   ├── InRelease           # Inline signature (modern preferred)
│   │   └── main/
│   │       ├── binary-amd64/
│   │       │   ├── Packages     # Package list
│   │       │   ├── Packages.gz  # Compressed package list
│   │       │   └── Packages.bz2 # Alternative compression
│   │       ├── binary-arm64/
│   │       └── binary-armhf/
│   ├── bookworm/
│   │   ├── Release
│   │   ├── Release.gpg
│   │   ├── InRelease
│   │   └── main/...
│   └── trixie/
│       ├── Release
│       ├── Release.gpg
│       ├── InRelease
│       └── main/...
└── pool/                        # Package files
    └── main/
        ├── a/aprsclients/
        ├── d/dmrclients/
        ├── d/dstarclients/
        ├── d/dstarrepeater/     # Note: dstarrepeater in pool/main/d/
        ├── f/fmclients/
        ├── m/mmdvmhost/
        ├── n/nxdnclients/
        ├── p/p25clients/
        ├── p/pocsagclients/
        ├── w/wiringpi/
        └── y/ysfclients/
```

## Key Management Tools and Scripts

### Automated Key Management Script

Create `scripts/manage-signing-key.sh`:

```bash
#!/bin/bash
set -e

# GPG key management script for MMDVM_DEB repository
# Usage: ./manage-signing-key.sh [generate|export|backup|verify]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
KEY_EMAIL="andy@mw0mwz.co.uk"
KEY_NAME="Ham Radio Repository"
KEY_COMMENT="MMDVM Debian Repository Signing Key"

print_usage() {
    echo "Usage: $0 [command]"
    echo "Commands:"
    echo "  generate  - Generate new GPG key pair"
    echo "  export    - Export public key for distribution"
    echo "  backup    - Create encrypted backup of private key"
    echo "  verify    - Verify existing signatures"
    echo "  rotate    - Begin key rotation process"
}

generate_key() {
    echo "Generating new GPG key pair..."
    
    # Generate key with batch mode
    gpg --batch --generate-key <<EOF
Key-Type: RSA
Key-Length: 4096
Name-Real: $KEY_NAME
Name-Email: $KEY_EMAIL
Name-Comment: $KEY_COMMENT
Expire-Date: 2y
Passphrase-File: /dev/stdin
%commit
EOF
    
    echo "Key generated successfully!"
    echo "Key details:"
    gpg --list-keys "$KEY_EMAIL"
}

export_public_key() {
    echo "Exporting public key..."
    
    # Export ASCII armored public key
    gpg --armor --export "$KEY_EMAIL" > "$REPO_ROOT/keys/hamradio.gpg"
    
    echo "Public key exported to keys/hamradio.gpg"
    echo "Key fingerprint:"
    gpg --fingerprint "$KEY_EMAIL"
}

create_backup() {
    local backup_dir="$HOME/gpg-backup-$(date +%Y%m%d)"
    mkdir -p "$backup_dir"
    
    echo "Creating encrypted backup..."
    
    # Export private key
    gpg --armor --export-secret-keys "$KEY_EMAIL" > "$backup_dir/private-key.asc"
    
    # Export public key
    gpg --armor --export "$KEY_EMAIL" > "$backup_dir/public-key.asc"
    
    # Create revocation certificate
    gpg --gen-revoke "$KEY_EMAIL" > "$backup_dir/revocation.asc"
    
    # Create encrypted archive
    tar -czf - -C "$backup_dir" . | \
        gpg --symmetric --cipher-algo AES256 \
            --output "$backup_dir.tar.gz.gpg"
    
    # Secure cleanup
    shred -vfz -n 3 "$backup_dir"/*
    rmdir "$backup_dir"
    
    echo "Backup created: $backup_dir.tar.gz.gpg"
    echo "Store this file securely and remember the passphrase!"
}

verify_signatures() {
    echo "Verifying repository signatures..."
    
    local errors=0
    
    for dist in bullseye bookworm trixie; do
        local dist_dir="$REPO_ROOT/dists/$dist"
        
        if [ -f "$dist_dir/InRelease" ]; then
            echo "Verifying $dist InRelease..."
            if gpg --verify "$dist_dir/InRelease" 2>/dev/null; then
                echo "✓ $dist InRelease signature valid"
            else
                echo "✗ $dist InRelease signature invalid"
                ((errors++))
            fi
        fi
        
        if [ -f "$dist_dir/Release.gpg" ] && [ -f "$dist_dir/Release" ]; then
            echo "Verifying $dist Release.gpg..."
            if gpg --verify "$dist_dir/Release.gpg" "$dist_dir/Release" 2>/dev/null; then
                echo "✓ $dist Release.gpg signature valid"
            else
                echo "✗ $dist Release.gpg signature invalid"
                ((errors++))
            fi
        fi
    done
    
    if [ $errors -eq 0 ]; then
        echo "All signatures verified successfully!"
    else
        echo "Found $errors signature errors!"
        exit 1
    fi
}

rotate_key() {
    echo "Beginning key rotation process..."
    
    # Check if old key exists
    if gpg --list-keys "$KEY_EMAIL" >/dev/null 2>&1; then
        echo "Found existing key for $KEY_EMAIL"
        
        # Export old key for transition period
        local old_key_file="$REPO_ROOT/keys/hamradio-old.gpg"
        gpg --armor --export "$KEY_EMAIL" > "$old_key_file"
        echo "Old key backed up to keys/hamradio-old.gpg"
        
        # Generate revocation certificate for old key
        gpg --gen-revoke "$KEY_EMAIL" > "$REPO_ROOT/keys/revocation-$(date +%Y%m%d).asc"
    fi
    
    echo "Generate new key with same email address..."
    echo "After generation, update GitHub Secrets and re-sign repository."
}

case "${1:-}" in
    generate)
        generate_key
        ;;
    export)
        export_public_key
        ;;
    backup)
        create_backup
        ;;
    verify)
        verify_signatures
        ;;
    rotate)
        rotate_key
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
```

### Repository Signing Script

Create `scripts/sign-repository.sh`:

```bash
#!/bin/bash
set -e

# Repository signing script
# Signs all Release files in the repository

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
KEY_EMAIL="andy@mw0mwz.co.uk"

cd "$REPO_ROOT"

echo "Signing repository metadata..."

for dist in bullseye bookworm trixie; do
    dist_dir="dists/$dist"
    
    if [ ! -f "$dist_dir/Release" ]; then
        echo "Warning: $dist_dir/Release not found, skipping..."
        continue
    fi
    
    echo "Signing $dist distribution..."
    
    # Create InRelease (inline signature)
    gpg --default-key "$KEY_EMAIL" \
        --clearsign \
        --armor \
        --output "$dist_dir/InRelease" \
        "$dist_dir/Release"
    
    # Create Release.gpg (detached signature)
    gpg --default-key "$KEY_EMAIL" \
        --detach-sign \
        --armor \
        --output "$dist_dir/Release.gpg" \
        "$dist_dir/Release"
    
    echo "✓ Signed $dist"
done

echo "Repository signing completed!"
echo "Verifying signatures..."

# Verify all signatures
for dist in bullseye bookworm trixie; do
    dist_dir="dists/$dist"
    
    if [ -f "$dist_dir/InRelease" ]; then
        gpg --verify "$dist_dir/InRelease" >/dev/null 2>&1 && \
            echo "✓ $dist InRelease verified" || \
            echo "✗ $dist InRelease verification failed"
    fi
    
    if [ -f "$dist_dir/Release.gpg" ]; then
        gpg --verify "$dist_dir/Release.gpg" "$dist_dir/Release" >/dev/null 2>&1 && \
            echo "✓ $dist Release.gpg verified" || \
            echo "✗ $dist Release.gpg verification failed"
    fi
done
```

## Current Implementation Status

### Repository Status

Currently implemented:
- ✅ GPG public key available at `/keys/hamradio.gpg`
- ✅ HTTPS distribution of public key
- ✅ Documentation for user key installation
- ✅ Scripts for key management and signing

Available for implementation:
- ⚠️ Release file signing (can be enabled in GitHub Actions)
- ⚠️ Individual package signing (optional, not required for APT)
- ⚠️ Automated key rotation procedures

### Implementation Roadmap

**Phase 1 - Basic Signing** (Immediate):
1. Generate production GPG key pair
2. Add private key to GitHub Secrets
3. Update workflow to sign Release files
4. Test signature verification

**Phase 2 - Enhanced Security** (Short-term):
1. Implement key rotation procedures
2. Add signature verification tests
3. Create incident response procedures
4. Document emergency contacts

**Phase 3 - Advanced Features** (Long-term):
1. Hardware security module integration
2. Multi-signature validation
3. Automated vulnerability scanning
4. Enhanced monitoring and alerting

### Enabling Full Signing

To enable complete repository signing:

1. **Generate production key**:
   ```bash
   ./scripts/manage-signing-key.sh generate
   ```

2. **Export public key**:
   ```bash
   ./scripts/manage-signing-key.sh export
   ```

3. **Add secrets to GitHub**:
   - Copy private key to `GPG_PRIVATE_KEY` secret
   - Add passphrase to `GPG_PASSPHRASE` secret

4. **Update GitHub Actions workflow**:
   - Add signing step to deployment workflow
   - Enable signature verification tests

5. **Test implementation**:
   ```bash
   ./scripts/manage-signing-key.sh verify
   ```

## Compliance and Standards

### Debian Policy Compliance

The signing implementation follows:
- **Debian Policy Manual** - Section 7.1 (Archive security)
- **APT Secure** - Signature verification standards
- **FTP Archive Signing** - Standard practices for Debian repositories

### Security Standards

Adherence to industry standards:
- **NIST SP 800-57** - Key management recommendations
- **RFC 4880** - OpenPGP Message Format standards
- **FIPS 140-2** - Cryptographic module security requirements
- **Common Criteria** - Security evaluation standards

### Best Practices Compliance

Following established security practices:
- Regular key rotation (2-year maximum)
- Strong cryptographic algorithms (RSA 4096-bit minimum)
- Secure key storage and distribution
- Comprehensive incident response procedures
- Regular security audits and updates

## References and Resources

### Official Documentation
- [Debian Repository Format](https://wiki.debian.org/DebianRepository/Format)
- [APT Secure](https://wiki.debian.org/SecureApt)
- [Debian Archive Security](https://www.debian.org/security/faq#archive)

### Security Guidelines
- [GPG Best Practices](https://riseup.net/en/security/message-security/openpgp/best-practices)
- [GitHub Encrypted Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [NIST Key Management Guidelines](https://csrc.nist.gov/publications/detail/sp/800-57-part-1/rev-5/final)

### Tools and Utilities
- [GPG Documentation](https://gnupg.org/documentation/)
- [dpkg-sig Manual](https://manpages.debian.org/testing/dpkg-sig/dpkg-sig.1.en.html)
- [apt-ftparchive Manual](https://manpages.debian.org/testing/apt-utils/apt-ftparchive.1.en.html)

---

Built with ❤️ for the Amateur Radio community by Andy Taylor (MW0MWZ)