# just manual: https://github.com/casey/just/#readme

_default:
    @just --list

# Get the latest ZFS 2.3.x version tag
zfs-version:
    gh release list \
        --repo openzfs/zfs \
        --json publishedAt,tagName \
        --jq '[.[] | select(.tagName | startswith("zfs-2.3"))] | sort_by(.publishedAt) | last | .tagName' \
        --limit 100

# Get kernel version from Fedora CoreOS stable (super fast with remote inspection)
kernel-version:
    skopeo inspect docker://quay.io/fedora/fedora-coreos:stable | jq -r '.Labels."ostree.linux"'

# Get kernel major.minor version
kernel-major-minor:
    #!/usr/bin/env bash
    KERNEL_VERSION=$(skopeo inspect docker://quay.io/fedora/fedora-coreos:stable | jq -r '.Labels."ostree.linux"')
    echo "$KERNEL_VERSION" | cut -d'.' -f1-2

# Get Fedora version from CoreOS (super fast with remote inspection)
fedora-version:
    skopeo inspect docker://quay.io/fedora/fedora-coreos:stable | jq -r '.Labels."org.opencontainers.image.version" | split(".")[0]'

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

# Check if container exists AND has valid attestations
check-container-with-attestations:
    #!/usr/bin/env bash
    ZFS_VERSION=$(just zfs-version | sed 's/^zfs-//')
    KERNEL_VERSION=$(just kernel-version)
    TARGET_TAG="zfs-${ZFS_VERSION}_kernel-${KERNEL_VERSION}"
    IMAGE="ghcr.io/samhclark/fedora-zfs-kmods:${TARGET_TAG}"
    
    echo "🔍 Checking for existing container with tag: $TARGET_TAG"
    
    # Step 1: Check container existence
    CONTAINER_EXISTS=$(gh api "/user/packages/container/fedora-zfs-kmods/versions" | \
        jq --arg tag "$TARGET_TAG" \
        '[.[] | .metadata.container.tags[]? | select(. == $tag)] | length > 0')
    
    # Step 2: If container exists, verify attestations
    if [[ "$CONTAINER_EXISTS" == "true" ]]; then
        echo "✅ Container exists: $TARGET_TAG"
        echo "🔐 Checking attestations..."
        
        DIGEST=$(skopeo inspect docker://${IMAGE} | jq -r '.Digest')
        IMAGE_WITH_DIGEST="${IMAGE}@${DIGEST}"
        echo "📋 Verifying attestations for: ${IMAGE_WITH_DIGEST}"
        
        if gh attestation verify --repo samhclark/fedora-zfs-kmods "oci://${IMAGE_WITH_DIGEST}"; then
            echo "✅ Valid attestations found"
            ATTESTATIONS_VALID="true"
        else
            echo "❌ Invalid or missing attestations"
            ATTESTATIONS_VALID="false"
        fi
    else
        echo "🔨 Container does not exist: $TARGET_TAG"
        ATTESTATIONS_VALID="false"
    fi
    
    # Step 3: Final decision
    if [[ "$CONTAINER_EXISTS" == "true" && "$ATTESTATIONS_VALID" == "true" ]]; then
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
