# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository builds ZFS kernel modules for Fedora CoreOS using bootable containers. It creates containerized RPM packages rather than using the standard ZFS repository because `rpm-ostree install` gets confused when working with bootable containers - it tries to build against the host kernel instead of the container kernel.

## Architecture

The build process uses a multi-stage Containerfile:

1. **Stage 1 (kernel-query)**: Extracts kernel version information from Fedora CoreOS stable image
2. **Stage 2 (builder)**: Builds ZFS kmods from source using the extracted kernel version
3. **Stage 3**: Creates final scratch image containing only the built RPM packages

Key files:
- `Containerfile`: Multi-stage container build that compiles ZFS kmods from source
- `README.md`: Explains the project rationale and container tagging scheme
- `Justfile`: Currently empty but intended for build automation
- `.github/workflows/build.yaml`: GitHub Actions workflow (present but empty)

## Container Output

The build produces containers tagged with both ZFS and kernel versions:
```
ghcr.io/samhclark/fedora-zfs-kmods:zfs-${ZFS_VERSION}_kernel-${KERNEL_VERSION}
```

Where `KERNEL_VERSION` comes from `rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}'` (not `uname -r`).

## Build Parameters

The Containerfile accepts build arguments:
- `FEDORA_VERSION`: Target Fedora version (default: 42)
- `KERNEL_MAJOR_MINOR`: Kernel major.minor version (default: 6.14)
- `ZFS_VERSION`: ZFS version to build (must be provided)

## Development Commands

Currently, the Justfile is empty, so container builds would use standard Docker/Podman commands:

```bash
# Build with specific versions
podman build \
  --build-arg ZFS_VERSION=2.3.3 \
  --build-arg KERNEL_MAJOR_MINOR=6.15 \
  --build-arg FEDORA_VERSION=42 \
  -t fedora-zfs-kmods:local .
```

The repository structure is minimal and focused specifically on the container build process for ZFS kernel modules.