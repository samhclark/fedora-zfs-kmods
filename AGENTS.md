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

Published to GitHub Container Registry:
```
ghcr.io/samhclark/fedora-zfs-kmods:zfs-{version}_kernel-{full-kernel-version}
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
just check-container-exists      # Check if container already exists for current versions
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
just workflow-status             # Check workflow run status
```

## Development Patterns

### Local CI/CD Development
**Pattern**: Implement CI/CD logic in Justfile commands first, then port to GitHub workflows.

**Benefits**:
- Fast iteration without triggering expensive Actions runs
- Local testing and debugging of complex shell/API logic
- Immediate feedback on command syntax and API responses

**Example**: The container existence check was developed as `just check-container-exists`:
```bash
# Developed and tested locally first
just check-container-exists
# 🔍 Checking for existing container with tag: zfs-2.3.3_kernel-6.15.4-200.fc42.x86_64
# ✅ Container already exists: zfs-2.3.3_kernel-6.15.4-200.fc42.x86_64

# Then ported to .github/workflows/build.yaml with identical logic
```

This approach saved significant development time by avoiding the GitHub Actions feedback loop during the jq syntax debugging phase.

## Build Arguments

All required (no defaults):
- `ZFS_VERSION`: Full ZFS tag (e.g., "zfs-2.3.3")
- `FEDORA_VERSION`: Fedora version number (e.g., "42") 
- `KERNEL_MAJOR_MINOR`: Kernel major.minor (e.g., "6.15")

## Integration Context

This repository supports a larger custom-coreos bootc image for NAS usage. The parent project previously built ZFS from source inline, causing long build times. Now it consumes pre-built RPMs from these containers, allowing faster daily OS builds while maintaining kernel module compatibility.

### Bootc Integration Pattern
The integration uses container bind mounts to access pre-built RPMs:
```dockerfile
FROM ghcr.io/samhclark/fedora-zfs-kmods:zfs-{version}_kernel-{version} as zfs-rpms
RUN --mount=type=bind,from=zfs-rpms,source=/,target=/zfs-rpms \
    rpm-ostree install -y \
        /zfs-rpms/*.$(rpm -qa kernel --queryformat '%{ARCH}').rpm \
        /zfs-rpms/*.noarch.rpm \
        /zfs-rpms/other/zfs-dracut-*.noarch.rpm
```

This replaces ~40 lines of ZFS build-from-source with 3 lines of RPM installation, saving ~10 minutes per build.

## Version Management Strategy

- ZFS version selection pinned to 2.3.x series for stability (avoid .0 releases that could cause data loss)
- Manual version progression prevents accidental NAS upgrades
- Compatibility matrix must be updated for each new ZFS release
- Build fails safe when encountering unknown versions

## Container Attestations

GitHub Actions automatically generates and publishes build attestations alongside container images. These attestations are critical for security verification and cannot be deleted independently from their parent containers.

**Attestation Storage Pattern:**
- Main container: `ghcr.io/samhclark/fedora-zfs-kmods:zfs-2.3.3_kernel-6.15.4-200.fc42.x86_64`
- Container digest: `sha256:842bc9e9f77bb39ae52becb8b0231f1ef99b580b81f7a6bd051a5f6eb72ed7c8`
- Attestation tag: `ghcr.io/samhclark/fedora-zfs-kmods:sha256-842bc9e9f77bb39ae52becb8b0231f1ef99b580b81f7a6bd051a5f6eb72ed7c8`

**Key Points:**
- Attestation tags use format `sha256-{digest}` (colon replaced with dash)
- Each container image has corresponding attestation stored as separate image
- Attestations must be preserved when their parent containers are retained
- Deleting attestations breaks container verification and security policies
- GitHub's `actions/attest-build-provenance` automatically creates these during CI builds

## Current Status (as of recent updates)

✅ **Fully operational:**
- Multi-stage container build with organized RPM output
- GitHub Actions workflow with version discovery and compatibility checking
- Container registry publishing with attestations
- Complete bootc integration documentation and examples
- Local development workflow with Justfile commands
- Version-specific container tagging (removed `:latest` tag)

📋 **Next planned enhancements:**
- Automated/scheduled builds with duplicate detection
- Container image cleanup workflows with attestation preservation
- Additional local testing commands