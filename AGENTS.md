# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) and other LLM Agents when working with code in this repository.

## Project Overview

This repository builds ZFS kernel modules for Fedora CoreOS and packages them as container images containing RPMs. It was split out from a larger custom-coreos project to avoid rebuilding ZFS kmods on every NAS OS build, saving ~10 minutes of build time for kernel/ZFS combinations that haven't changed.

The approach is necessary because `rpm-ostree install zfs` from the standard ZFS repository doesn't work with bootable containers - it tries to build against the host kernel instead of the container kernel during the build process.

## Architecture

### Multi-stage Container Build
1. **Stage 1 (kernel-query)**: Runs in `quay.io/fedora/fedora-coreos:stable` to extract actual kernel and Fedora versions
2. **Stage 2 (builder)**: Builds ZFS from source with correct kernel headers in `quay.io/fedora/fedora`
3. **Stage 3 (final)**: Creates scratch image containing only organized RPM packages

### GitHub Actions Workflow (2-job design)
1. **query-versions job**: Runs in CoreOS container to discover versions and check compatibility
2. **build job**: Builds and publishes container images with proper attestations

### Compatibility System
Both Justfile and workflow maintain identical compatibility matrices mapping ZFS versions to maximum supported kernel versions. Builds fail early if:
- Unknown ZFS version encountered (forces manual matrix updates)
- Current kernel exceeds ZFS compatibility limits

## Key Files

- `Containerfile`: Multi-stage build definition (no defaults, all args required)
- `Justfile`: Local development commands with version discovery and compatibility checking
- `.github/workflows/build.yaml`: CI/CD pipeline with manual trigger
- `README.md`: Comprehensive documentation for users and maintainers
- `TODO.md`: Next session tasks and project backlog

## Container Output

Published to GitHub Container Registry with dual tagging:
```
ghcr.io/samhclark/fedora-zfs-kmods:zfs-{version}_kernel-{full-kernel-version}
ghcr.io/samhclark/fedora-zfs-kmods:latest
```

RPMs organized in final image:
- `/debug/` - Debug symbols
- `/devel/` - Development headers  
- `/other/` - dracut and test RPMs
- `/src/` - Source RPMs
- `/*.rpm` - Main ZFS RPMs

## Common Development Commands

```bash
# Version discovery and compatibility
just versions                    # Show all versions and check compatibility
just check-compatibility         # Verify ZFS/kernel compatibility
just zfs-version                 # Latest ZFS 2.3.x release
just kernel-version              # Current CoreOS kernel version

# Building and testing
just build                       # Build image locally (with compatibility check)
just test-build                  # Quick build test (removes image after)

# RPM management
just list-rpms                   # List RPMs in built image
just extract-rpms                # Extract RPMs to ./rpms/ directory

# GitHub integration
gh workflow run build.yaml       # Trigger CI build (manual)
```

## Build Arguments

All required (no defaults):
- `ZFS_VERSION`: Full ZFS tag (e.g., "zfs-2.3.3")
- `FEDORA_VERSION`: Fedora version number (e.g., "42") 
- `KERNEL_MAJOR_MINOR`: Kernel major.minor (e.g., "6.15")

## Integration Context

This repository supports a larger custom-coreos bootc image for NAS usage. The parent project previously built ZFS from source inline, causing long build times. Now it consumes pre-built RPMs from these containers, allowing faster daily OS builds while maintaining kernel module compatibility.

## Version Management Strategy

- ZFS version selection pinned to 2.3.x series for stability (avoid .0 releases that could cause data loss)
- Manual version progression prevents accidental NAS upgrades
- Compatibility matrix must be updated for each new ZFS release
- Build fails safe when encountering unknown versions