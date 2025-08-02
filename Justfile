# just manual: https://github.com/casey/just/#readme

_default:
    @just --list

# Get the latest ZFS 2.3.x version tag
zfs-version:
    gh release list \
        --repo openzfs/zfs \
        --json tagName \
        -q '.[] | select(.tagName | startswith("zfs-2.3")) | .tagName' \
        --limit 1

# Get kernel version from Fedora CoreOS stable
kernel-version:
    podman run --rm --pull=always quay.io/fedora/fedora-coreos:stable \
        rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}'

# Get kernel major.minor version
kernel-major-minor:
    #!/usr/bin/env bash
    KERNEL_VERSION=$(podman run --rm --pull=always quay.io/fedora/fedora-coreos:stable \
        rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')
    echo "$KERNEL_VERSION" | cut -d'.' -f1-2

# Get Fedora version from CoreOS
fedora-version:
    podman run --rm --pull=always quay.io/fedora/fedora-coreos:stable \
        grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2

# Check if ZFS version is compatible with kernel version
check-compatibility:
    #!/usr/bin/env bash
    ZFS_VERSION=$(just zfs-version)
    KERNEL_MAJOR_MINOR=$(just kernel-major-minor)
    
    # Define compatibility matrix for ZFS versions
    # Format: "zfs-version:max-kernel-version"
    declare -A compatibility_matrix=(
        ["zfs-2.2.7"]="6.12"
        ["zfs-2.3.0"]="6.12"
        ["zfs-2.3.1"]="6.13"
        ["zfs-2.3.2"]="6.14"
        ["zfs-2.2.8"]="6.15"
        ["zfs-2.3.3"]="6.15"
    )
    
    # Check if we have compatibility info for this ZFS version
    if [[ -z "${compatibility_matrix[$ZFS_VERSION]}" ]]; then
        echo "ERROR: Unknown ZFS version $ZFS_VERSION"
        echo "This version is not in the compatibility matrix."
        echo "Please update the compatibility matrix in both the Justfile and workflow to include this version."
        exit 1
    fi
    
    MAX_KERNEL="${compatibility_matrix[$ZFS_VERSION]}"
    
    # Check if current kernel is compatible
    if [[ $(echo "$KERNEL_MAJOR_MINOR $MAX_KERNEL" | tr ' ' '\n' | sort -V | tail -n1) != "$MAX_KERNEL" ]]; then
        echo "ERROR: ZFS $ZFS_VERSION is only compatible with Linux kernels up to $MAX_KERNEL"
        echo "Current kernel: $KERNEL_MAJOR_MINOR"
        echo "Please wait for a newer ZFS release or use an older kernel"
        exit 1
    fi
    
    echo "✓ ZFS $ZFS_VERSION is compatible with kernel $KERNEL_MAJOR_MINOR (max: $MAX_KERNEL)"

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
    TARGET_TAG="zfs-${ZFS_VERSION}_kernel-${KERNEL_VERSION}"
    
    echo "🔍 Checking for existing container with tag: $TARGET_TAG"
    
    # Check GitHub Container Registry API
    CONTAINER_EXISTS=$(gh api "/user/packages/container/fedora-zfs-kmods/versions" | \
        jq --arg tag "$TARGET_TAG" \
        '[.[] | .metadata.container.tags[]? | select(. == $tag)] | length > 0')
    
    if [[ "$CONTAINER_EXISTS" == "true" ]]; then
        echo "✅ Container already exists: $TARGET_TAG"
        echo "🚀 Build would be skipped"
        exit 0
    else
        echo "🔨 Container does not exist: $TARGET_TAG"
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
    
    echo "Building with:"
    echo "  ZFS_VERSION=$ZFS_VERSION"
    echo "  KERNEL_MAJOR_MINOR=$KERNEL_MAJOR_MINOR"
    echo "  FEDORA_VERSION=$FEDORA_VERSION"
    echo ""
    
    podman build --rm \
        --build-arg ZFS_VERSION="$ZFS_VERSION" \
        --build-arg KERNEL_MAJOR_MINOR="$KERNEL_MAJOR_MINOR" \
        --build-arg FEDORA_VERSION="$FEDORA_VERSION" \
        -t "fedora-zfs-kmods:zfs-${ZFS_VERSION#zfs-}_kernel-${KERNEL_VERSION}" \
        -t "fedora-zfs-kmods:latest" \
        .

# Quick build test (just verify it builds, don't keep the image)
test-build:
    #!/usr/bin/env bash
    just check-compatibility
    
    ZFS_VERSION=$(just zfs-version)
    KERNEL_MAJOR_MINOR=$(just kernel-major-minor)
    FEDORA_VERSION=$(just fedora-version)
    
    echo "Test building with:"
    echo "  ZFS_VERSION=$ZFS_VERSION"
    echo "  KERNEL_MAJOR_MINOR=$KERNEL_MAJOR_MINOR"
    echo "  FEDORA_VERSION=$FEDORA_VERSION"
    echo ""
    
    podman build --rm \
        --build-arg ZFS_VERSION="$ZFS_VERSION" \
        --build-arg KERNEL_MAJOR_MINOR="$KERNEL_MAJOR_MINOR" \
        --build-arg FEDORA_VERSION="$FEDORA_VERSION" \
        -t "fedora-zfs-kmods:test" \
        . && podman rmi "fedora-zfs-kmods:test"

# List built RPMs from a successful build
list-rpms:
    #!/usr/bin/env bash
    # Since the final image is FROM scratch, we need to mount it and list files
    # Create a temporary container to inspect the contents
    CONTAINER_ID=$(podman create fedora-zfs-kmods:latest)
    echo "RPMs in fedora-zfs-kmods:latest:"
    podman export $CONTAINER_ID | tar -tv | grep '\.rpm$' | awk '{print $6}'
    podman rm $CONTAINER_ID

# Extract RPMs to local directory
extract-rpms:
    #!/usr/bin/env bash
    mkdir -p ./rpms
    # Since the final image is FROM scratch, we need to export and extract
    CONTAINER_ID=$(podman create fedora-zfs-kmods:latest)
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