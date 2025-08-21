# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository builds reproducible, hardened Linux images for confidential computing environments and MEV applications using mkosi and Nix. It contains the bottom-of-block (BOB) searcher sandbox infrastructure and BuilderNet infrastructure for Intel TDX confidential computing.

## Build Commands

### Environment Setup
```bash
# Enter development environment (required before building)
nix develop -c $SHELL
```

### Building Images
```bash
# Build BOB (searcher sandbox) image
mkosi --force -I bob.conf

# Build BuilderNet image  
mkosi --force -I buildernet.conf

# Build TDX dummy test image
mkosi --force -I tdx-dummy.conf

# Build with profiles
mkosi --force -I bob.conf --profile=devtools       # Include development tools
mkosi --force -I bob.conf --profile=azure          # Azure compatibility
mkosi --force -I bob.conf --profile=azure,devtools # Multiple profiles
```

### Testing and Running
```bash
# Create persistent storage for QEMU
qemu-img create -f qcow2 persistent.qcow2 2048G

# Run in QEMU (see README for full command with TDX support)
sudo qemu-system-x86_64 -enable-kvm -m 16384M -kernel build/tdx-debian.efi ...

# Access build environment shell
mkosi-chroot /bin/bash

# Test reproducibility
./scripts/test_reproducibility.sh bob.conf
```

### Cloud Deployment
```bash
# GCP instance creation (without persistent disk to avoid mount issues)
gcloud compute instances create tdx-dev-3-instance \
    --image=tdx-debian-dev-disk-2-image \
    --machine-type=c3-standard-4 \
    --zone=us-central1-a \
    --confidential-compute-type=TDX \
    --maintenance-policy=TERMINATE \
    --tags=http-8080 \
    --metadata serial-port-enable=TRUE \
    --project=taiko-mainnet

# Check serial output for debugging
gcloud compute instances get-serial-port-output tdx-dev-3-instance \
    --zone=us-central1-a \
    --project=taiko-mainnet | tail -100
```

## Architecture

### Module Structure
Each module (bob, buildernet, tdx-dummy) follows this pattern:
- **Top-level .conf**: Includes base configuration and module-specific config
- **Module directory**: Contains module-specific files
  - `module.conf`: Module configuration (packages, scripts)
  - `mkosi.build`: Build-time script (runs in chroot)
  - `mkosi.postinst`: Post-installation script
  - `mkosi.extra/`: Files to overlay on the filesystem

### Key Configuration Sections
- `[Build]`: Build environment settings, network access, build scripts
- `[Content]`: Runtime packages, post-installation scripts, file overlays
- `[Output]`: Image format (uki/disk), output directory
- `[Distribution]`: Debian release and mirror configuration

### Service Dependencies
Many services depend on `persistent-mount.service` which waits for `/persistent` to be mounted. For cloud deployments, ensure either:
1. An additional disk is attached and will be mounted to `/persistent`
2. Override/disable the service if persistent storage is not needed

### Build System Flow
1. **Base system** (base/base.conf): Minimal Debian with kernel, systemd, basic tools
2. **Module overlay**: Additional packages, configuration, services
3. **Build scripts** (mkosi.build): Compile custom software, download binaries
4. **Post-install** (mkosi.postinst): Configure systemd services, permissions
5. **Debloat**: Remove unnecessary files to minimize image size

### Important Files
- `base/base.conf`: Core system configuration inherited by all modules
- `kernel/kernel-yocto.config`: Base kernel configuration
- `services/systemd/`: Shared systemd service definitions
- `scripts/build_rust_package.sh`: Helper for building Rust packages reproducibly
- `flake.nix`: Nix development environment definition

## Module-Specific Notes

### BOB Module
- Implements network isolation for MEV searchers
- SSH access controlled by toggle mechanism
- Logs delayed by 2 minutes (~10 blocks)
- Requires ed25519 key submission on port 8080 for initialization
- Persistent storage encrypted with LUKS

### BuilderNet Module  
- Configured for block building infrastructure
- Includes Lighthouse beacon client
- Network configuration via render-config.sh

### TDX-Dummy Module
- Minimal test environment for TDX functionality
- No SSH access by design
- Used for testing attestation and TDX features

## Common Issues

### Persistent Mount Timeout
If system hangs at "Job persistent-mount.service/start running":
- Check if additional disk is properly attached
- For GCP: Use pd-balanced or pd-ssd disk types (not pd-standard) with C3 instances
- Device name may be /dev/sdb instead of /dev/vda on cloud platforms

### Build Failures
- Ensure you're in nix development environment: `nix develop -c $SHELL`
- Check network access if downloading during build
- Verify debian-archive-keyring is installed

### Module Configuration
- BuildScripts and BuildPackages go in `[Content]` section (not `[Build]`)
- WithNetwork=true goes in `[Build]` section
- PostInstallationScripts go in `[Content]` section