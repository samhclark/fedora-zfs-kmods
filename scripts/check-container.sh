#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 --zfs-version VERSION --kernel-version VERSION [--require-attestations true|false] [--github-output PATH]

Options:
  --zfs-version VERSION        ZFS version without the "zfs-" prefix (e.g., 2.4.0)
  --kernel-version VERSION     Full kernel version string (e.g., 6.18.3-200.fc42.x86_64)
  --require-attestations FLAG  Require attestations to be valid (default: false)
  --github-output PATH         Append key=value pairs suitable for GitHub Actions outputs
  -h, --help                   Show this help message
USAGE
}

ZFS_VERSION=""
KERNEL_VERSION=""
REQUIRE_ATTESTATIONS="false"
GITHUB_OUTPUT_PATH=""

append_output() {
  local key="$1"
  local value="$2"
  if [[ -n "$GITHUB_OUTPUT_PATH" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT_PATH"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zfs-version)
      if [[ $# -lt 2 ]]; then
        echo "Error: --zfs-version requires an argument" >&2
        exit 1
      fi
      ZFS_VERSION="$2"
      shift 2
      ;;
    --kernel-version)
      if [[ $# -lt 2 ]]; then
        echo "Error: --kernel-version requires an argument" >&2
        exit 1
      fi
      KERNEL_VERSION="$2"
      shift 2
      ;;
    --require-attestations)
      if [[ $# -lt 2 ]]; then
        echo "Error: --require-attestations requires an argument" >&2
        exit 1
      fi
      REQUIRE_ATTESTATIONS="${2,,}"
      shift 2
      ;;
    --github-output)
      if [[ $# -lt 2 ]]; then
        echo "Error: --github-output requires an argument" >&2
        exit 1
      fi
      GITHUB_OUTPUT_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$ZFS_VERSION" || -z "$KERNEL_VERSION" ]]; then
  echo "Error: --zfs-version and --kernel-version are required" >&2
  usage >&2
  exit 1
fi

TARGET_TAG="zfs-${ZFS_VERSION}_kernel-${KERNEL_VERSION}"
IMAGE="ghcr.io/samhclark/fedora-zfs-kmods:${TARGET_TAG}"

append_output "target-tag" "$TARGET_TAG"

echo "🔍 Checking for existing container with tag: $TARGET_TAG"

API_RESPONSE=$(gh api "/user/packages/container/fedora-zfs-kmods/versions")

CONTAINER_EXISTS=$(echo "$API_RESPONSE" | jq --arg tag "$TARGET_TAG" '[.[] | .metadata.container.tags[]? | select(. == $tag)] | length > 0')

if [[ "$CONTAINER_EXISTS" == "true" ]]; then
  echo "✅ Container exists: $TARGET_TAG"
else
  echo "🔨 Container does not exist: $TARGET_TAG"
  append_output "container-exists" "false"
  exit 1
fi

if [[ "$REQUIRE_ATTESTATIONS" == "true" ]]; then
  if ! command -v skopeo >/dev/null 2>&1; then
    echo "❌ skopeo is required to verify attestations" >&2
    append_output "container-exists" "false"
    exit 1
  fi

  DIGEST=$(skopeo inspect "docker://${IMAGE}" | jq -r '.Digest')
  IMAGE_WITH_DIGEST="${IMAGE}@${DIGEST}"
  echo "📋 Verifying attestations for: ${IMAGE_WITH_DIGEST}"

  if gh attestation verify --repo samhclark/fedora-zfs-kmods "oci://${IMAGE_WITH_DIGEST}"; then
    echo "✅ Valid attestations found"
  else
    echo "❌ Invalid or missing attestations"
    append_output "container-exists" "false"
    exit 1
  fi
fi

append_output "container-exists" "true"

echo "🚀 Container is ready to use"
