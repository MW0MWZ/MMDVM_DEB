# 🔐 GPG Keys Directory

This directory contains the **PUBLIC** GPG key used for signing the Debian repository metadata and ensuring package authenticity.

## 📁 Directory Contents

| File | Description | Status | Distribution |
|------|-------------|--------|--------------|
| `hamradio.gpg` | Public GPG key for repository signing | ✅ Committed | https://deb.pistar.uk/hamradio.gpg |
| `private.key` | Private GPG key | ❌ **NEVER COMMIT** | GitHub Secrets only |
| `README.md` | This documentation | ✅ Committed | - |

## 🔑 Key Information

### Current Repository Key

- **Type**: GPG (GNU Privacy Guard)
- **Algorithm**: RSA
- **Key Size**: 4096 bits
- **Email**: repo@pistar.uk
- **Usage**: Repository Release file signing
- **Validity**: 2 years (rotate before expiration)
- **Public Key URL**: https://deb.pistar.uk/hamradio.gpg

### Key Fingerprint

To verify the key authenticity:
```bash
gpg --show-keys hamradio.gpg
```

Expected output format:
```
pub   rsa4096 2025-01-01 [SC] [expires: 2027-01-01]
      XXXX XXXX XXXX XXXX XXXX  XXXX XXXX XXXX XXXX XXXX
uid   Ham Radio Repository <repo@pistar.uk>
```

## 🛠️ Key Management

### Generating New Keys

To generate a new GPG key pair:

```bash
# Use the provided script
./scripts/generate-gpg-key.sh

# Or manually
gpg --full-generate-key
# Select: RSA and RSA, 4096 bits, 2y validity
# Name: Ham Radio Repository
# Email: repo@pistar.uk
```

### Exporting Keys

After generation:

```bash
# Export public key (for this directory)
gpg --armor --export repo@pistar.uk > keys/hamradio.gpg

# Export private key (for secure backup - NEVER COMMIT)
gpg --armor --export-secret-keys repo@pistar.uk > private.key
```

### Key Rotation Schedule

- **Every 2 years**: Generate new key before current expires
- **30 days before expiration**: Begin transition period
- **Keep old public key**: Available during transition
- **Update documentation**: New fingerprint and dates

## 🔒 Security Requirements

### ⚠️ CRITICAL Security Rules

1. **NEVER commit private keys to the repository**
   - Add `*.key`, `*.asc`, `*private*` to `.gitignore`
   - Use `git status` to verify before committing

2. **Store private key in GitHub Secrets**
   - Secret name: `GPG_PRIVATE_KEY`
   - Optional: `GPG_PASSPHRASE` if key is protected
   - Access: Limited to necessary workflows only

3. **Backup private key securely**
   - Encrypted USB drive in secure location
   - Password manager with encryption
   - Physical safe or safety deposit box
   - **Never** in cloud storage without encryption

4. **Protect the key**
   - Use strong passphrase (20+ characters)
   - Generate on air-gapped/secure system
   - Limit access to key material

## 📝 GitHub Secrets Configuration

### Adding Private Key to GitHub Secrets

1. Navigate to repository **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Configure:
   - **Name**: `GPG_PRIVATE_KEY`
   - **Value**: Complete private key including:
     ```
     -----BEGIN PGP PRIVATE KEY BLOCK-----
     [key content]
     -----END PGP PRIVATE KEY BLOCK-----
     ```
4. If using passphrase, add another secret:
   - **Name**: `GPG_PASSPHRASE`
   - **Value**: Your key passphrase

### Workflow Usage

The private key is used in GitHub Actions for signing:

```yaml
- name: Import GPG key
  env:
    GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
  run: |
    echo "$GPG_PRIVATE_KEY" | gpg --batch --import
    # Sign Release files...
```

## 👥 User Installation

Users install the public key to verify repository authenticity:

### Modern Method (Debian 11+, Ubuntu 20.04+)

```bash
# Download and install repository key
wget -qO - https://deb.pistar.uk/hamradio.gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/hamradio.gpg

# Add repository with key reference
echo "deb [signed-by=/usr/share/keyrings/hamradio.gpg] https://deb.pistar.uk/ bookworm main" | \
    sudo tee /etc/apt/sources.list.d/hamradio.list
```

### Legacy Method (Debian 10 and older)

```bash
# Using deprecated apt-key
wget -qO - https://deb.pistar.uk/hamradio.gpg | sudo apt-key add -
```

## 🚨 Emergency Procedures

### If Private Key is Compromised

1. **Immediately**:
   - Revoke the compromised key
   - Generate new key pair
   - Update GitHub Secrets
   - Re-sign all repository metadata

2. **Notify users**:
   - Update repository README
   - Post security notice on website
   - Provide new key installation instructions

3. **User recovery**:
   ```bash
   # Remove old key
   sudo rm /usr/share/keyrings/hamradio.gpg
   
   # Install new key
   wget -qO - https://deb.pistar.uk/hamradio-new.gpg | \
       sudo gpg --dearmor -o /usr/share/keyrings/hamradio-new.gpg
   
   # Update repository configuration
   sudo sed -i 's/hamradio.gpg/hamradio-new.gpg/' \
       /etc/apt/sources.list.d/hamradio.list
   ```

## 📋 Checklist for Key Operations

### When Generating New Keys
- [ ] Run key generation script
- [ ] Verify key details (size, validity, email)
- [ ] Export public key to `keys/hamradio.gpg`
- [ ] Export private key for backup (don't commit!)
- [ ] Update GitHub Secrets
- [ ] Test signing process
- [ ] Update documentation with new fingerprint
- [ ] Commit only public key

### When Rotating Keys
- [ ] Generate new key 30 days before expiration
- [ ] Keep old public key during transition
- [ ] Update all documentation
- [ ] Notify users of upcoming change
- [ ] Test with both old and new keys
- [ ] Archive old key after transition

## 📚 References

- [Debian SecureApt](https://wiki.debian.org/SecureApt)
- [GPG Best Practices](https://riseup.net/en/security/message-security/openpgp/best-practices)
- [GitHub Encrypted Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)

## ⚡ Quick Commands

```bash
# Show key info
gpg --show-keys hamradio.gpg

# List keys in keyring
gpg --list-keys

# Check key expiration
gpg --list-keys --with-colons repo@pistar.uk | grep ^pub

# Verify a signed file
gpg --verify Release.gpg Release
```

---

**Remember**: The security of the entire repository depends on keeping the private key secure. When in doubt, err on the side of caution!

Built with ❤️ for the Amateur Radio community by Andy Taylor (MW0MWZ)