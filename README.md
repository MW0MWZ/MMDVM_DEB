# Ham Radio DEB Repository

Debian/Ubuntu package repository for Ham Radio software, hosted on GitHub Pages.

[![Build Status](https://github.com/MW0MWZ/MMDVM_DEB/actions/workflows/build-debian-packages.yml/badge.svg)](https://github.com/MW0MWZ/MMDVM_DEB/actions)

## 🌐 Repository URL

- **Web**: https://deb.pistar.uk
- **Repository**: https://deb.pistar.uk/

## 📦 Available Packages

### Core MMDVM Software

| Package | Description | Components | Upstream |
|---------|-------------|------------|----------|
| **mmdvmhost** | MMDVM Host Software & Calibration Tool | MMDVMHost, MMDVMCal, RemoteCommand | [MMDVMHost](https://github.com/g4klx/MMDVMHost) & [MMDVMCal](https://github.com/g4klx/MMDVMCal) |
| **dstarrepeater** | D-Star Repeater Controller | dstarrepeaterd, dstarrepeaterconfig | [DStarRepeater](https://github.com/g4klx/DStarRepeater) |

### Gateway & Client Packages

| Package | Description | Components | Upstream |
|---------|-------------|------------|----------|
| **dmrclients** | DMR Gateway and Cross-Mode converters | DMRGateway, DMR2YSF, DMR2NXDN | [DMRGateway](https://github.com/g4klx/DMRGateway) & [MMDVM_CM](https://github.com/nostar/MMDVM_CM) |
| **dstarclients** | D-Star Gateway and tools | DStarGateway, dgwtimeserver, dgwtexttransmit, dgwvoicetransmit | [DStarGateway](https://github.com/g4klx/DStarGateway) |
| **ysfclients** | YSF Gateway, Parrot, DGId Gateway and Cross-Mode converters | YSFGateway, YSFParrot, DGIdGateway, YSF2DMR, YSF2NXDN, YSF2P25 | [YSFClients](https://github.com/g4klx/YSFClients) & [MMDVM_CM](https://github.com/nostar/MMDVM_CM) |
| **nxdnclients** | NXDN Gateway, Parrot and Cross-Mode converter | NXDNGateway, NXDNParrot, NXDN2DMR | [NXDNClients](https://github.com/g4klx/NXDNClients) & [MMDVM_CM](https://github.com/nostar/MMDVM_CM) |
| **p25clients** | P25 Gateway and Parrot | P25Gateway, P25Parrot | [P25Clients](https://github.com/g4klx/P25Clients) |
| **pocsagclients** | POCSAG/DAPNET Gateway for paging | DAPNETGateway | [DAPNETGateway](https://github.com/g4klx/DAPNETGateway) |
| **fmclients** | FM Gateway for analog-to-digital bridging | FMGateway | [FMGateway](https://github.com/g4klx/FMGateway) |
| **aprsclients** | APRS Gateway between APRS-IS and RF | APRSGateway | [APRSGateway](https://github.com/g4klx/APRSGateway) |

## 🐧 Supported Debian/Ubuntu Versions

### Debian
- Debian 13 "Trixie" (stable)
- Debian 12 "Bookworm" (oldstable)

### Ubuntu
- Ubuntu 25.10 "Questing Quokka" (use bookworm packages)
- Ubuntu 25.04 "Plucky Puffin" (use bookworm packages)
- Ubuntu 24.04 LTS "Noble" (use bookworm packages)
- Ubuntu 22.04 LTS "Jammy" (use bookworm packages)

### Raspberry Pi OS
- Raspberry Pi OS (Current - based on Trixie, use trixie packages)
- Raspberry Pi OS (Legacy - based on Bookworm, use bookworm packages)

## 🖥️ Supported Architectures

- `amd64` - 64-bit Intel/AMD
- `arm64` - 64-bit ARM (Raspberry Pi 3/4/5 64-bit OS)
- `armhf` - 32-bit ARM (Raspberry Pi, ARMv7)

## 🚀 Quick Start

### Installation

Add the repository and install packages on your Debian/Ubuntu system:

```bash
# Add GPG key
wget -qO - https://deb.pistar.uk/hamradio.gpg | sudo gpg --dearmor -o /usr/share/keyrings/hamradio.gpg

# Add repository (choose your Debian version)
# For Debian 13 (Trixie) / Raspberry Pi OS (Current)
echo "deb [signed-by=/usr/share/keyrings/hamradio.gpg] https://deb.pistar.uk/ trixie main" | sudo tee /etc/apt/sources.list.d/hamradio.list

# For Debian 12 (Bookworm) / Ubuntu 22.04-25.10 / Raspberry Pi OS (Legacy)
echo "deb [signed-by=/usr/share/keyrings/hamradio.gpg] https://deb.pistar.uk/ bookworm main" | sudo tee /etc/apt/sources.list.d/hamradio.list

# Update and install
sudo apt update
sudo apt install mmdvmhost dmrclients ysfclients
```

### Configuration

All packages store configuration in package-specific directories:

```bash
# Configuration files location
/etc/mmdvmhost/       # MMDVM Host configuration
/etc/dmrclients/      # DMR Gateway and cross-mode configs
/etc/ysfclients/      # YSF Gateway, DGId, and cross-mode configs
/etc/dstarclients/    # D-Star gateway configs
/etc/dstarrepeater/   # D-Star repeater configuration
/etc/nxdnclients/     # NXDN gateway and cross-mode configs
/etc/p25clients/      # P25 gateway config
/etc/aprsclients/     # APRS gateway config
/etc/pocsagclients/   # DAPNET gateway config
/etc/fmclients/       # FM gateway config

# Example: Configure MMDVM Host
sudo cp /etc/mmdvmhost/MMDVM.ini.example /etc/mmdvmhost/MMDVM.ini
sudo nano /etc/mmdvmhost/MMDVM.ini

# Example: Configure DMR Gateway
sudo cp /etc/dmrclients/DMRGateway.ini.example /etc/dmrclients/DMRGateway.ini
sudo nano /etc/dmrclients/DMRGateway.ini

# Example: Configure D-Star Repeater
sudo cp /etc/dstarrepeater/dstarrepeater.conf.example /etc/dstarrepeater/dstarrepeater.conf
sudo nano /etc/dstarrepeater/dstarrepeater.conf
```

### Starting Services

Services are managed via systemd:

```bash
# Start services
sudo systemctl start mmdvmhost      # MMDVM Host
sudo systemctl start dmrgateway     # DMR Gateway
sudo systemctl start ysfgateway     # YSF Gateway
sudo systemctl start dstargateway   # D-Star Gateway
sudo systemctl start dstarrepeater  # D-Star Repeater Controller
sudo systemctl start nxdngateway    # NXDN Gateway
sudo systemctl start p25gateway     # P25 Gateway
sudo systemctl start aprsgateway    # APRS Gateway
sudo systemctl start dapnetgateway  # DAPNET/POCSAG Gateway

# Enable at boot
sudo systemctl enable mmdvmhost
sudo systemctl enable dmrgateway
sudo systemctl enable ysfgateway
sudo systemctl enable dstarrepeater

# Check status
sudo systemctl status mmdvmhost
```

## 🔧 Building Packages

Packages are built using GitHub Actions. To trigger a build:

1. Go to [Actions](https://github.com/MW0MWZ/MMDVM_DEB/actions)
2. Select "Build Debian Packages" workflow
3. Click "Run workflow"
4. Select options:
   - **Package**: Choose specific package or "all"
   - **Debian Version**: Choose specific version or "all"
5. Click "Run workflow"

The build process:
- Clones source from upstream git repositories
- Builds for all architectures using Docker and QEMU
- Creates DEB packages following Debian standards
- Generates repository metadata (Packages, Release files)
- Deploys to GitHub Pages

### Automatic Builds

The repository can monitor upstream repositories for changes and automatically rebuild packages when updates are detected (workflow available but not scheduled by default).

## 📝 Package Versioning

Packages use date-based versioning with git commit tracking:
- Format: `YYYY.MM.DD-r{revision}`
- Example: `2025.01.02-r1`
- Git commit hash is embedded in the package description

## 🔑 Repository Signing

The repository uses GPG signing for security:
- **Public Key**: https://deb.pistar.uk/hamradio.gpg
- **Key Location**: `/usr/share/keyrings/hamradio.gpg`

All repository metadata (Release files) can be signed with GPG for APT secure verification.

## 🛠️ Development

### Repository Structure

```
MMDVM_DEB/
├── .github/workflows/       # GitHub Actions workflows
│   ├── build-debian-packages.yml
│   ├── check-upstream-updates.yml
│   └── cleanup-old-packages.yml
├── packages/                # Package definitions
│   ├── mmdvmhost/
│   ├── dmrclients/         # DMRGateway, DMR2YSF, DMR2NXDN
│   ├── dstarclients/       # DStarGateway and tools
│   ├── dstarrepeater/      # D-Star Repeater Controller
│   ├── ysfclients/         # YSFGateway, YSFParrot, DGIdGateway, YSF2*
│   ├── nxdnclients/        # NXDNGateway, NXDNParrot, NXDN2DMR
│   ├── p25clients/         # P25Gateway, P25Parrot
│   ├── pocsagclients/      # DAPNETGateway
│   ├── fmclients/          # FMGateway
│   └── aprsclients/        # APRSGateway
│       ├── build.sh        # Build script
│       └── source.conf     # Source configuration
├── keys/                   # GPG public key
├── scripts/                # Build and maintenance scripts
├── docs/                   # Documentation
└── deploy/                 # GitHub Pages deployment (auto-generated)
    ├── index.html         # Repository landing page
    ├── dists/             # APT repository structure
    │   ├── bookworm/
    │   └── trixie/
    └── pool/              # Package pool
        └── main/
```

### Package Organization

The repository follows Debian packaging conventions:

- **Protocol-specific clients**: `dmrclients`, `dstarclients`, `ysfclients`, `nxdnclients`, `p25clients`
  - Each contains the main gateway, parrot/test tools, and cross-mode converters where applicable
- **Core software**: `mmdvmhost` - The main MMDVM host software with calibration tools
- **Repeater controller**: `dstarrepeater` - D-Star repeater system
- **Single-purpose clients**: `aprsclients`, `pocsagclients`, `fmclients`

### Adding New Packages

1. Create package directory: `packages/{package_name}/`
2. Add `build.sh` script with build instructions
3. Add `source.conf` with source repository information
4. Test locally with Docker
5. Commit and run workflow

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for detailed instructions.

### Local Testing

Test builds locally using Docker:

```bash
# Clone repository
git clone https://github.com/MW0MWZ/MMDVM_DEB.git
cd MMDVM_DEB

# Test build (requires Docker)
cd packages/mmdvmhost
OUTPUT_DIR=./output ARCH=amd64 DEBIAN_VERSION=bookworm ./build.sh

# Check output
ls -la output/
```

## 📚 Documentation

- [Building Packages](docs/BUILDING.md) - Detailed build process
- [Package Signing](docs/SIGNING.md) - GPG signing details
- [Contributing](docs/CONTRIBUTING.md) - How to contribute

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Add your package following the guidelines
4. Submit a pull request

All packages must be Ham Radio related and build from source.

## 📜 License

- Repository infrastructure: MIT License
- Individual packages maintain their upstream licenses
- Most packages: GPL-2.0-or-later

## 👤 Maintainer

**MW0MWZ** - andy@mw0mwz.co.uk

## 🔗 Links

- **Repository**: https://github.com/MW0MWZ/MMDVM_DEB
- **Issues**: https://github.com/MW0MWZ/MMDVM_DEB/issues
- **Web Interface**: https://deb.pistar.uk
- **Sister APK Repository**: https://apk.pistar.uk

---

Built with ❤️ for the Amateur Radio community by Andy Taylor (MW0MWZ)