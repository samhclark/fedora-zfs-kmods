# just manual: https://github.com/casey/just/#readme

_default:
    @just --list

# Get the latest ZFS 2.3.x version tag
zfs-version:
    ./scripts/query-zfs-version.sh | jq -r '.["zfs-tag"]'

# Compute the sha256 for a ZFS release tarball
zfs-tarball-hash TAG:
    #!/usr/bin/env bash
    set -euo pipefail
    TARBALL_PATH=$(mktemp)
    trap 'rm -f "$TARBALL_PATH"' EXIT
    curl --fail --location "https://github.com/openzfs/zfs/archive/refs/tags/{{TAG}}.tar.gz" \
        --output "$TARBALL_PATH"
    sha256sum "$TARBALL_PATH" | awk '{print $1}'

# Get kernel version from Fedora CoreOS stable (super fast with remote inspection)
kernel-version:
    ./scripts/query-kernel-info.sh | jq -r '.["kernel-version"]'

# Get kernel major.minor version
kernel-major-minor:
    ./scripts/query-kernel-info.sh | jq -r '.["kernel-major-minor"]'

# Get Fedora version from CoreOS (super fast with remote inspection)
fedora-version:
    ./scripts/query-kernel-info.sh | jq -r '.["fedora-version"]'

# Check if ZFS version is compatible with kernel version
check-compatibility:
    #!/usr/bin/env bash
    ZFS_VERSION=$(just zfs-version)
    KERNEL_MAJOR_MINOR=$(just kernel-major-minor)
    ./scripts/check-compatibility.sh "$ZFS_VERSION" "$KERNEL_MAJOR_MINOR"

# Show all versions that will be used for build
versions:
    #!/usr/bin/env bash
    echo "ZFS Version: $(just zfs-version)"
    echo "Kernel Version: $(just kernel-version)"
    echo "Kernel Major.Minor: $(just kernel-major-minor)"
    echo "Fedora Version: $(just fedora-version)"
    echo ""
    just check-compatibility

# Check if container already exists for current versions
check-container-exists:
    #!/usr/bin/env bash
    ZFS_VERSION=$(just zfs-version | sed 's/^zfs-//')
    KERNEL_VERSION=$(just kernel-version)

    if ./scripts/check-container.sh \
        --zfs-version "$ZFS_VERSION" \
        --kernel-version "$KERNEL_VERSION"; then
        echo "🚀 Build would be skipped"
        exit 0
    else
        echo "🔨 Build would proceed"
        exit 1
    fi

# Check if container exists AND has valid attestations
check-container-with-attestations:
    #!/usr/bin/env bash
    ZFS_VERSION=$(just zfs-version | sed 's/^zfs-//')
    KERNEL_VERSION=$(just kernel-version)

    if ./scripts/check-container.sh \
        --zfs-version "$ZFS_VERSION" \
        --kernel-version "$KERNEL_VERSION" \
        --require-attestations true; then
        echo "🚀 Build would be skipped - valid container already exists"
        exit 0
    else
        echo "🔨 Build would proceed"
        exit 1
    fi

# Build the image locally for testing
build:
    #!/usr/bin/env bash
    just check-compatibility
    
    ZFS_VERSION=$(just zfs-version)
    KERNEL_VERSION=$(just kernel-version)
    KERNEL_MAJOR_MINOR=$(just kernel-major-minor)
    FEDORA_VERSION=$(just fedora-version)
    BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    VCS_REF=$(git rev-parse HEAD)
    SOURCE_URL="https://github.com/samhclark/fedora-zfs-kmods"
    DOCUMENTATION_URL="https://github.com/samhclark/fedora-zfs-kmods#readme"
    REF_NAME="fedora-zfs-kmods:zfs-${ZFS_VERSION#zfs-}_kernel-${KERNEL_VERSION}"
    
    echo "Building with:"
    echo "  ZFS_VERSION=$ZFS_VERSION"
    echo "  KERNEL_MAJOR_MINOR=$KERNEL_MAJOR_MINOR"
    echo "  FEDORA_VERSION=$FEDORA_VERSION"
    echo ""
    
    podman build --rm \
        --build-arg ZFS_VERSION="$ZFS_VERSION" \
        --build-arg KERNEL_MAJOR_MINOR="$KERNEL_MAJOR_MINOR" \
        --build-arg KERNEL_VERSION="$KERNEL_VERSION" \
        --build-arg FEDORA_VERSION="$FEDORA_VERSION" \
        --build-arg BUILD_DATE="$BUILD_DATE" \
        --build-arg VCS_REF="$VCS_REF" \
        --build-arg SOURCE_URL="$SOURCE_URL" \
        --build-arg DOCUMENTATION_URL="$DOCUMENTATION_URL" \
        --build-arg REF_NAME="$REF_NAME" \
        -t "fedora-zfs-kmods:zfs-${ZFS_VERSION#zfs-}_kernel-${KERNEL_VERSION}" \
        .

# Quick build test (just verify it builds, don't keep the image)
test-build:
    #!/usr/bin/env bash
    just check-compatibility
    
    ZFS_VERSION=$(just zfs-version)
    KERNEL_VERSION=$(just kernel-version)
    KERNEL_MAJOR_MINOR=$(just kernel-major-minor)
    FEDORA_VERSION=$(just fedora-version)
    BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    VCS_REF=$(git rev-parse HEAD)
    SOURCE_URL="https://github.com/samhclark/fedora-zfs-kmods"
    DOCUMENTATION_URL="https://github.com/samhclark/fedora-zfs-kmods#readme"
    
    echo "Test building with:"
    echo "  ZFS_VERSION=$ZFS_VERSION"
    echo "  KERNEL_MAJOR_MINOR=$KERNEL_MAJOR_MINOR"
    echo "  FEDORA_VERSION=$FEDORA_VERSION"
    echo ""
    
    podman build --rm \
        --build-arg ZFS_VERSION="$ZFS_VERSION" \
        --build-arg KERNEL_MAJOR_MINOR="$KERNEL_MAJOR_MINOR" \
        --build-arg KERNEL_VERSION="$KERNEL_VERSION" \
        --build-arg FEDORA_VERSION="$FEDORA_VERSION" \
        --build-arg BUILD_DATE="$BUILD_DATE" \
        --build-arg VCS_REF="$VCS_REF" \
        --build-arg SOURCE_URL="$SOURCE_URL" \
        --build-arg DOCUMENTATION_URL="$DOCUMENTATION_URL" \
        --build-arg REF_NAME="fedora-zfs-kmods:test" \
        -t "fedora-zfs-kmods:test" \
        . && podman rmi "fedora-zfs-kmods:test"

# List built RPMs from a successful build
list-rpms:
    #!/usr/bin/env bash
    # Since the final image is FROM scratch, we need to mount it and list files
    # Create a temporary container to inspect the contents
    CONTAINER_ID=$(podman create "fedora-zfs-kmods:zfs-$(just zfs-version | sed 's/zfs-//')_kernel-$(just kernel-version)")
    echo "RPMs in built container:"
    podman export $CONTAINER_ID | tar -tv | grep '\.rpm$' | awk '{print $6}'
    podman rm $CONTAINER_ID

# Extract RPMs to local directory
extract-rpms:
    #!/usr/bin/env bash
    mkdir -p ./rpms
    # Since the final image is FROM scratch, we need to export and extract
    CONTAINER_ID=$(podman create "fedora-zfs-kmods:zfs-$(just zfs-version | sed 's/zfs-//')_kernel-$(just kernel-version)")
    podman export $CONTAINER_ID | tar -x -C ./rpms/
    podman rm $CONTAINER_ID
    echo "RPMs extracted to ./rpms/"
    find ./rpms -name "*.rpm" -type f

# Trigger GitHub Actions workflow
run-workflow:
    gh workflow run build.yaml

# Check status of GitHub Actions workflow runs
workflow-status:
    gh run list --workflow=build.yaml --limit=5

# Test cleanup logic locally with configurable parameters
cleanup-dry-run RETENTION_DAYS MIN_VERSIONS:
    #!/usr/bin/env bash
    ./scripts/cleanup-container-images.sh \
        --retention-days {{RETENTION_DAYS}} \
        --min-versions {{MIN_VERSIONS}} \
        --dry-run true
