# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MMDVM_DEB is a Debian package repository for amateur radio digital voice and gateway software, hosted on GitHub Pages at `deb.pistar.uk`. It builds `.deb` packages from upstream G4KLX and related ham radio git repositories using GitHub Actions with Docker-based cross-compilation.

Maintainer: MW0MWZ (Andy Taylor) - andy@mw0mwz.co.uk

## Build Commands

### Local package build (requires Docker or native Debian environment)
```bash
cd packages/<packagename>
OUTPUT_DIR=./output ARCH=amd64 DEBIAN_VERSION=bookworm ./build.sh
```

### Verify a built package
```bash
dpkg-deb -I output/*.deb   # Package info
dpkg-deb -c output/*.deb   # Package contents
```

### Full repository build (all packages, current arch)
```bash
./scripts/build-all-debian.sh
```

### Calculate build number against live repo
```bash
./scripts/calculate_build_number.sh <package> <version> <deb_suffix> <arch> <repo_url>
```

There is no test suite or linter. Validation is done by the build succeeding and `dpkg-deb` verification.

## Architecture

### Package Structure

Each package lives in `packages/<name>/` with exactly two files:
- **`build.sh`** - Self-contained build script (~300-800 lines) that clones source, compiles, and creates the `.deb`
- **`source.conf`** - Metadata: upstream git URL(s), package name, components, dependencies, and tracked `GIT_COMMIT`

### Build Script Pattern

All `build.sh` scripts follow the same function flow:
1. `clean_build()` - Remove old artifacts
2. `prepare_source()` - `git clone` upstream, capture commit hash and date-based version
3. `build_software()` - `make -j$(nproc)` compilation
4. `create_package()` - Assemble DEBIAN directory structure, control file, postinst/postrm scripts, then `fakeroot dpkg-deb --build`
5. `verify_package()` - Validate the `.deb` output

### Multi-Repository Packages

Several packages build from multiple upstream repos (e.g., `dmrclients` builds DMRGateway from `g4klx/DMRGateway` and cross-mode converters from `nostar/MMDVM_CM`). These have `GITURL_SECONDARY` in `source.conf` and extended `prepare_source()`/`build_software()` functions.

### CI/CD Pipeline

The main workflow is `.github/workflows/build-debian-packages.yml`:
- Triggered manually via `workflow_dispatch` with package/version selectors
- Build matrix: 2 Debian versions (bookworm/trixie) x 3 architectures (amd64/arm64/armhf) x 11 packages
- Uses Docker containers with QEMU for ARM cross-compilation
- Deploys to GitHub Pages (`deploy/` directory) with standard APT repository structure

Supporting workflows:
- `check-upstream-updates.yml` - Monitors upstream repos for new commits, updates `GIT_COMMIT` in `source.conf`
- `cleanup-old-packages.yml` - Prunes old package versions from the repository

### Platform-Specific Build Logic

- **ARM builds** (arm64/armhf): `mmdvmhost` includes OLED display support via `ArduiPi_OLED`; `dstarrepeater` uses `MakefilePi` for GPIO support via `wiringpi`
- **amd64 builds**: Software-only, no GPIO/OLED
- **Debian version differences**: wxWidgets 3.2 on bookworm/trixie; trixie uses `t64` library name suffixes

### Environment Variables

Build scripts read these from the environment (set by CI or manually):
- `ARCH` - Target architecture: `amd64`, `arm64`, `armhf`
- `DEBIAN_VERSION` - Target release: `bookworm`, `trixie`
- `OUTPUT_DIR` - Where to place built `.deb` files

### Versioning

Format: `YYYY.MM.DD-<revision>` (e.g., `2025.01.02-1`). Version date comes from the upstream git commit date. The upstream git commit hash is embedded in the package description.

### Naming Convention

- Core software: descriptive names (`mmdvmhost`, `dstarrepeater`)
- Gateway/client packages: always end in `clients` (`dmrclients`, `ysfclients`, `aprsclients`)

### Installed File Layout

All packages follow:
- `/usr/bin/` - Binaries
- `/etc/<package>/` - Configuration files (with `.example` templates)
- `/var/log/<package>/` - Log directory
- `/usr/lib/systemd/system/` - Systemd service files

Packages create dedicated system users (e.g., `mmdvm`, `dstar`) via `postinst` scripts.
