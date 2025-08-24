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
    echo "🧪 Testing cleanup logic (DRY RUN)"
    echo "📅 Retention period: {{RETENTION_DAYS}} days"
    echo "🔒 Minimum versions to keep: {{MIN_VERSIONS}}"
    echo ""
    
    # Calculate cutoff date
    cutoff_date=$(date -d "{{RETENTION_DAYS}} days ago" -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "📅 Cutoff date: $cutoff_date"
    echo ""
    
    # Query all package versions
    echo "🔍 Querying all package versions..."
    versions_json=$(gh api "/user/packages/container/fedora-zfs-kmods/versions" --paginate)
    
    # Parse and categorize versions
    echo "📦 Found versions:"
    echo "$versions_json" | jq -r '.[] | "\(.metadata.container.tags[]? // "<untagged>") - \(.created_at) - ID: \(.id)"' | sort
    echo ""
    
    # Find ALL versioned tags (not limited yet)
    all_versioned_tags=$(echo "$versions_json" | jq -r '
      .[] | select(.metadata.container.tags[]? | test("^zfs-.*_kernel-.*$")) |
      {created_at: .created_at, tag: .metadata.container.tags[], id: .id}' |
      jq -s 'sort_by(.created_at) | reverse')
    
    # Count total versioned tags available
    total_versioned_count=$(echo "$all_versioned_tags" | jq length)
    echo "🏷️  Total versioned tags found: $total_versioned_count"
    
    # Early safety check - do we have enough versioned tags in the repository?
    if [[ "$total_versioned_count" -lt {{MIN_VERSIONS}} ]]; then
      echo "❌ EARLY SAFETY CHECK FAILED: Only $total_versioned_count versioned tags exist in repository (minimum {{MIN_VERSIONS}} required)"
      echo "📋 Available versioned tags:"
      echo "$all_versioned_tags" | jq -r '.[].tag'
      echo ""
      echo "🚨 Cannot proceed with cleanup - insufficient versioned tags to maintain minimum policy"
      echo "This indicates the repository needs more tagged releases before cleanup can run safely"
      exit 1
    fi
    
    # Select the most recent N versioned tags to protect
    protected_versioned_tags=$(echo "$all_versioned_tags" | jq -r ".[0:{{MIN_VERSIONS}}] | .[].tag")
    echo "🛡️  Protected tags ({{MIN_VERSIONS}} most recent):"
    echo "$protected_versioned_tags"
    echo ""
    
    # Build protected digests list from retained images
    echo "🔐 Building protected attestation digests..."
    protected_digests=()
    while IFS= read -r tag; do
        if [[ -n "$tag" ]]; then
            digest=$(echo "$versions_json" | jq -r --arg tag "$tag" '.[] | select(.metadata.container.tags[]? == $tag) | .name')
            if [[ -n "$digest" && "$digest" != "null" ]]; then
                attestation_tag="sha256-${digest#sha256:}"
                protected_digests+=("$attestation_tag")
                echo "  $tag -> $attestation_tag"
            fi
        fi
    done <<< "$protected_versioned_tags"
    echo ""
    
    # Create regex pattern for protected tags
    protected_pattern=$(echo "$protected_versioned_tags" | tr '\n' '|' | sed 's/|$//')
    
    echo "🔍 Safety validation:"
    echo "  - Total versioned tags in repository: $total_versioned_count"
    echo "  - Versioned tags being protected: {{MIN_VERSIONS}}"
    echo "  - Protected attestations: ${#protected_digests[@]}"
    echo "✅ Safety check passed: $total_versioned_count versioned tags available, protecting {{MIN_VERSIONS}} most recent"
    echo ""
    
    # Identify deletion candidates
    echo "🗑️  Identifying deletion candidates..."
    deletion_candidates=$(echo "$versions_json" | jq -r --arg cutoff "$cutoff_date" --argjson protected "$(printf '%s\n' "${protected_digests[@]}" | jq -R . | jq -s .)" --arg protected_tags "$protected_pattern" '
        .[] | select(
            (.created_at < $cutoff) and
            ((.metadata.container.tags[]? | test($protected_tags)) | not) and
            ((.metadata.container.tags[]? | IN($protected[])) | not)
        ) | "\(.metadata.container.tags[]? // "<untagged>") - \(.created_at) - ID: \(.id)"'
    )
    
    if [[ -n "$deletion_candidates" ]]; then
        echo "$deletion_candidates" | sort
        echo ""
        echo "📊 Summary:"
        echo "  - Deletion candidates: $(echo "$deletion_candidates" | wc -l)"
    else
        echo "  No versions would be deleted"
        echo ""
        echo "📊 Summary:"
        echo "  - Deletion candidates: 0"
    fi
    
    total_versions=$(echo "$versions_json" | jq length)
    echo "  - Total versions: $total_versions"
    echo "  - Protected versions: {{MIN_VERSIONS}}"
    echo "  - Protected attestations: ${#protected_digests[@]}"