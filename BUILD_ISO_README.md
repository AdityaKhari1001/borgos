# BorgOS Offline ISO Build System

## Overview

This is a comprehensive, production-ready build system for creating fully offline BorgOS ISO images. The system includes automated building, testing, and validation in Docker containers to ensure consistent and reliable ISO creation.

## Features

- **Fully Offline ISO**: Creates a complete ISO that requires no network access during installation
- **Docker-based Build**: Builds in isolated Docker containers for consistency
- **Comprehensive Testing**: Automated VM testing with QEMU
- **Cross-platform**: Works on macOS and Linux
- **Quality Assurance**: Built-in validation and testing at every step
- **No Bad Sources**: All cdrom and external dependencies removed/cached

## Prerequisites

- Docker (version 20.10 or higher)
- 20GB+ free disk space
- 4GB+ RAM available

## Quick Start

1. **Validate Environment**:
```bash
./validate-build-environment.sh
```

2. **Build ISO with Tests**:
```bash
./build-and-test-iso.sh
```

3. **Build ISO without Tests** (faster):
```bash
./build-and-test-iso.sh --skip-tests
```

## Build System Components

### Main Scripts

| Script | Purpose |
|--------|---------|
| `build-and-test-iso.sh` | Master orchestrator - runs complete build pipeline |
| `build-offline-iso.sh` | Core ISO builder with offline packages |
| `validate-build-environment.sh` | Pre-build environment checker |
| `test-suite.sh` | Comprehensive ISO testing suite |
| `test-iso-vm.py` | Python-based VM testing framework |

### Docker Components

| File | Purpose |
|------|---------|
| `Dockerfile.isobuilder` | Build environment for ISO creation |
| `Dockerfile.vm-test` | Test environment with QEMU |
| `docker-compose-build.yml` | Orchestrates multi-container build |

## ISO Features

The generated ISO includes:

- **Base System**: Debian 12 (Bookworm) minimal
- **Package Management**: All packages pre-cached for offline install
- **Docker**: Pre-installed with Docker and Docker Compose
- **Docker Images**: Core images pre-loaded (postgres, redis, python, etc.)
- **BorgOS**: Complete BorgOS system with all components
- **Auto-start**: Services configured to start on boot
- **Networking**: NetworkManager for easy configuration
- **Desktop** (Optional): XFCE lightweight desktop environment
- **Boot Support**: Both BIOS and UEFI boot modes

## Build Process

1. **Environment Validation**
   - Checks Docker availability
   - Verifies disk space
   - Validates source files
   - Scans for problematic sources

2. **Package Preparation**
   - Downloads all required Debian packages
   - Creates offline repository with indexes
   - Caches Docker images as tar files

3. **Base System Creation**
   - Uses debootstrap to create minimal Debian
   - Configures system settings
   - Installs kernel and bootloader

4. **BorgOS Integration**
   - Copies BorgOS components
   - Configures services
   - Sets up auto-start scripts

5. **ISO Generation**
   - Creates compressed squashfs filesystem
   - Configures ISOLINUX/GRUB bootloaders
   - Generates hybrid ISO (USB/DVD bootable)

6. **Testing & Validation**
   - Boot test in QEMU
   - Service verification
   - Network testing
   - Offline capability check

## Testing

The test suite includes:

- **ISO Validation**: Format, size, structure checks
- **Boot Testing**: BIOS and UEFI boot verification
- **Login Testing**: Default credentials validation
- **Service Testing**: Docker, BorgOS services
- **Network Testing**: Interface and connectivity
- **Offline Testing**: Package and image availability

### Running Tests Separately

```bash
# Test existing ISO
docker run --privileged --rm \
  -v ./iso_output:/iso:ro \
  -v ./test-results:/results \
  borgos-vm-tester:latest \
  /tests/test-suite.sh /iso/BorgOS-Offline-*.iso
```

## Output

After successful build:

- **ISO Location**: `iso_output/BorgOS-Offline-4.0.0-[DATE]-amd64.iso`
- **Build Logs**: `build-logs-[DATE]/`
- **Test Results**: `test-results/test-results.json`
- **Build Report**: `build-logs-[DATE]/build-report.md`
- **Checksums**: SHA256 and MD5 in `iso_output/`

## Writing to USB

After building, write the ISO to USB:

```bash
# Linux
sudo dd if=iso_output/BorgOS-Offline-*.iso of=/dev/sdX bs=4M status=progress

# macOS
sudo dd if=iso_output/BorgOS-Offline-*.iso of=/dev/diskN bs=4m
```

## Default Credentials

- **Username**: borgos
- **Password**: borgos
- **Root Password**: borgos

## Troubleshooting

### Build Fails

1. Check Docker is running: `docker ps`
2. Verify disk space: `df -h`
3. Check logs in `build-logs-[DATE]/`

### Tests Fail

1. Review `test-results/test-results.json`
2. Check VM console log: `test-results/vm-console.log`
3. Verify QEMU installation: `docker run borgos-vm-tester qemu-system-x86_64 --version`

### ISO Won't Boot

1. Verify ISO integrity with checksums
2. Try different USB creation method
3. Check BIOS/UEFI settings on target machine

## Architecture

```
BorgOS ISO Build System
├── Build Phase
│   ├── Environment Setup (Docker)
│   ├── Package Download & Cache
│   ├── Base System (debootstrap)
│   ├── BorgOS Installation
│   └── ISO Generation (xorriso)
├── Test Phase
│   ├── Static Analysis
│   ├── Boot Testing (QEMU)
│   ├── Service Validation
│   └── Offline Verification
└── Output Phase
    ├── ISO File
    ├── Checksums
    ├── Test Reports
    └── Build Logs
```

## Quality Assurance

Every build includes:

- **Source Validation**: No cdrom or problematic sources
- **Dependency Caching**: All packages available offline
- **Boot Testing**: Automated VM boot verification
- **Service Testing**: All services start correctly
- **Documentation**: Complete build and test reports
- **Checksums**: SHA256 and MD5 for verification

## Advanced Options

### Custom Package List

Edit the package list in `build-offline-iso.sh`:

```bash
local packages=(
    # Add your packages here
    "your-package"
)
```

### Custom Docker Images

Add images to cache in `build-offline-iso.sh`:

```bash
local images=(
    "your-image:tag"
)
```

### Build Configuration

Modify settings in `build-offline-iso.sh`:

```bash
readonly ISO_VERSION="4.0.0"  # Change version
readonly WORK_DIR="/tmp/borgos-iso-offline"  # Change temp directory
```

## Security Considerations

- All scripts validated with shellcheck
- No hardcoded passwords in build scripts
- Secure defaults with password change prompts
- No external network dependencies during install
- All packages verified with dpkg signatures

## Contributing

When modifying the build system:

1. Run `shellcheck` on all shell scripts
2. Test changes in Docker first
3. Verify offline functionality
4. Update documentation
5. Run full test suite

## License

See LICENSE file in the repository root.

## Support

For issues or questions:
1. Check troubleshooting section
2. Review build logs
3. Open an issue with logs attached

---

Built with care for the BorgOS project - AI-First Multi-Agent Operating System