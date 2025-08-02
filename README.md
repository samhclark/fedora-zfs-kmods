# fedora-zfs-kmods

Pre-built ZFS kernel modules for Fedora CoreOS, packaged as container images containing RPMs.

## Why This Exists

The standard approach of using the [ZFS repository](https://openzfs.github.io/openzfs-docs/Getting%20Started/Fedora/index.html) with `rpm-ostree install -y zfs` doesn't work with bootable containers. The `rpm-ostree install` command gets confused because it tries to build against the *host* kernel instead of the kernel inside the container during the build process.

By building ZFS from source with specific kernel headers, we can create kernel modules that work correctly in bootable container environments.

## How It Works

This project builds ZFS kernel modules from source and packages them as container images containing RPMs. The build process:

1. **Queries Fedora CoreOS stable** to determine the current kernel and Fedora versions
2. **Checks compatibility** between the ZFS version and kernel version using a compatibility matrix
3. **Builds ZFS from source** with the correct kernel headers
4. **Packages the RPMs** into a scratch container image

## Container Images

Images are tagged with ZFS and kernel versions:

```
ghcr.io/samhclark/fedora-zfs-kmods:zfs-{zfs-version}_kernel-{kernel-version}
```

Example:
```
ghcr.io/samhclark/fedora-zfs-kmods:zfs-2.3.3_kernel-6.15.4-200.fc42.x86_64
```

Where:
- `zfs-version` is the ZFS release version (e.g., `2.3.3`)
- `kernel-version` comes from `rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}'`

## Local Development

### Prerequisites

- `just` (command runner)
- `podman` 
- `gh` (GitHub CLI)

### Common Commands

```bash
# Show all version information
just versions

# Check ZFS/kernel compatibility
just check-compatibility

# Build the image locally
just build

# Quick build test (builds then removes image)
just test-build

# List RPMs in built image
just list-rpms

# Extract RPMs to ./rpms/ directory
just extract-rpms

# Trigger GitHub Actions workflow
just run-workflow

# Check status of recent workflow runs
just workflow-status

# Test cleanup logic locally (configurable retention/versions)
just cleanup-dry-run 7 2    # Test with 7 days retention, keep 2 versions
just cleanup-dry-run 90 3   # Test with production settings
```

### Individual Version Queries

```bash
just zfs-version           # Latest ZFS 2.3.x version
just kernel-version        # Current CoreOS kernel version
just kernel-major-minor    # Kernel major.minor (e.g., 6.15)
just fedora-version        # Fedora version from CoreOS
```

## Compatibility Management

### Version Compatibility Matrix

Both the Justfile and GitHub workflow maintain a compatibility matrix that maps ZFS versions to their maximum supported kernel versions:

```bash
declare -A compatibility_matrix=(
    ["zfs-2.2.7"]="6.12"
    ["zfs-2.3.0"]="6.12"
    ["zfs-2.3.1"]="6.13"
    ["zfs-2.3.2"]="6.14"
    ["zfs-2.2.8"]="6.15"
    ["zfs-2.3.3"]="6.15"
)
```

### Adding New ZFS Versions

When a new ZFS version is released:

1. **Check kernel compatibility** in the ZFS release notes
2. **Update the compatibility matrix** in both:
   - `Justfile` (line ~40-45)
   - `.github/workflows/build.yaml` (line ~67-73)
3. **Test locally** with `just build`
4. **Run the workflow** to build and publish

### Upgrading to New Major/Minor Versions

To upgrade from ZFS 2.3.x to 2.4.x (when available):

1. **Update ZFS version queries** in both:
   - `Justfile`: Change `startswith("zfs-2.3")` to `startswith("zfs-2.4")`
   - `.github/workflows/build.yaml`: Same change
2. **Update compatibility matrix** with new version mappings
3. **Test thoroughly** before using in production

## GitHub Actions Workflow

### Build Triggers

The build workflow runs:
- **Daily at 6 AM UTC** (automated builds)
- **Manual trigger** via `workflow_dispatch`

Automated builds include duplicate detection - they check if a container already exists for the current ZFS/kernel combination and skip building if found (unless forced).

```bash
# Manual build via GitHub UI: Actions → Build ZFS Kmods → Run workflow
# Or via CLI:
just run-workflow
# Or directly:
gh workflow run build.yaml
```

### Container Cleanup

A separate cleanup workflow runs **weekly on Sundays at 2 AM UTC** to remove old container images:
- Retains images from the last 90 days
- Always preserves the 3 most recent versioned containers
- Preserves attestations for all retained images
- Includes dry-run mode for safety (default for manual runs)

### Workflow Process

1. **Query versions job** (runs in CoreOS container):
   - Extracts kernel and Fedora versions from CoreOS stable
   - Finds latest ZFS 2.3.x release
   - Checks version compatibility
   
2. **Build job** (runs on Ubuntu):
   - Builds container image with extracted versions
   - Pushes to GitHub Container Registry
   - Generates build provenance attestations

### Debugging Failed Workflows

Common failure points:

1. **Compatibility check fails**: New kernel version exceeds ZFS compatibility
   - Check CoreOS kernel version vs ZFS support matrix
   - Wait for newer ZFS release or update matrix if compatibility confirmed
   
2. **Build fails**: Usually dependency or compilation issues
   - Check if Fedora package repositories changed
   - Verify ZFS source download works
   - Check build dependencies in Containerfile
   
3. **Unknown ZFS version**: New release not in compatibility matrix
   - Add new version to both compatibility matrices
   - Verify kernel compatibility before adding

## Architecture

### Build Process

The build uses a multi-stage Containerfile:

1. **Stage 1 (kernel-query)**: Runs in CoreOS stable to extract kernel version
2. **Stage 2 (builder)**: Builds ZFS from source with correct kernel headers  
3. **Stage 3 (final)**: Scratch image containing only the built RPMs

### Key Files

- `Containerfile`: Multi-stage build definition
- `Justfile`: Local development commands
- `.github/workflows/build.yaml`: CI/CD pipeline
- `CLAUDE.md`: AI assistant context

### RPM Organization

Built RPMs are organized in the final image:
```
/debug/     - Debug symbols
/devel/     - Development headers  
/other/     - dracut and test RPMs
/src/       - Source RPMs
/*.rpm      - Main ZFS RPMs
```

## Usage with Bootable Containers

This project builds ZFS kernel modules as container images containing organized RPM packages, designed for integration with bootc-based CoreOS builds.

### Integration Approach

Instead of building ZFS from source during your CoreOS build (which takes ~10 minutes), use pre-built RPMs from this container:

```dockerfile
# Replace ZFS build stages with this approach:

# Stage 1: Verify CoreOS kernel version (keep existing verification)
FROM quay.io/fedora/fedora-coreos:stable as kernel-query
ARG KERNEL_MAJOR_MINOR
# ... existing verification logic ...

# Stage 2: Pull pre-built ZFS RPMs  
# IMPORTANT: Must match exact ZFS and kernel versions
ARG ZFS_VERSION=2.3.3
ARG KERNEL_VERSION=6.15.4-200.fc42.x86_64
FROM ghcr.io/samhclark/fedora-zfs-kmods:zfs-${ZFS_VERSION}_kernel-${KERNEL_VERSION} as zfs-rpms

# Stage 3: Install RPMs in CoreOS image
FROM quay.io/fedora/fedora-coreos:stable
RUN --mount=type=bind,from=zfs-rpms,source=/,target=/zfs-rpms \
    rpm-ostree install -y \
        /zfs-rpms/*.$(rpm -qa kernel --queryformat '%{ARCH}').rpm \
        /zfs-rpms/*.noarch.rpm \
        /zfs-rpms/other/zfs-dracut-*.noarch.rpm && \
    depmod -a "$(rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    echo "zfs" > /etc/modules-load.d/zfs.conf && \
    ostree container commit
```

### Version Management Considerations

**Critical:** Container tags must exactly match your target kernel and ZFS versions.

**External build arguments:** Since Containerfile ARG values cannot be determined programmatically during build, ZFS and kernel versions must be provided externally (similar to this project's `.github/workflows/build.yaml` approach).

**Verification:** Stage 1 kernel verification should still be used to ensure the pulled RPM container matches your expected kernel version.

## Integration Examples

### Custom CoreOS Replacement

Replace the commented-out ZFS build in your custom CoreOS Containerfile:

```dockerfile
# OLD APPROACH (10+ minute builds):
# FROM quay.io/fedora/fedora:${FEDORA_VERSION} as builder
# ... 40+ lines of ZFS build from source ...

# NEW APPROACH (cached RPMs):
ARG ZFS_VERSION
ARG KERNEL_VERSION  
FROM ghcr.io/samhclark/fedora-zfs-kmods:zfs-${ZFS_VERSION}_kernel-${KERNEL_VERSION} as zfs-rpms

FROM quay.io/fedora/fedora-coreos:stable
RUN --mount=type=bind,from=zfs-rpms,source=/,target=/zfs-rpms \
    --mount=type=bind,from=kernel-query,source=/kernel-version.txt,target=/kernel-version.txt \
    rpm-ostree install -y \
        tailscale \
        /zfs-rpms/*.$(rpm -qa kernel --queryformat '%{ARCH}').rpm \
        /zfs-rpms/*.noarch.rpm \
        /zfs-rpms/other/zfs-dracut-*.noarch.rpm && \
    depmod -a "$(rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
    echo "zfs" > /etc/modules-load.d/zfs.conf && \
    systemctl enable tailscaled && \
    ostree container commit
```

### Benefits

- **Faster builds:** Eliminates ~10 minutes of ZFS compilation per build
- **Cached compatibility:** RPMs only rebuild when kernel/ZFS versions change  
- **Same functionality:** Identical ZFS installation in final image
- **Reduced complexity:** No ZFS build dependencies in your Containerfile