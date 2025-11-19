#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE >&2
Usage: $0 <zfs_version> <kernel_major_minor>

Example:
  $0 zfs-2.3.5 6.17
USAGE
}

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

ZFS_VERSION=$1
KERNEL_MAJOR_MINOR=$2

declare -A COMPATIBILITY_MATRIX=(
  ["zfs-2.2.7"]="6.12"
  ["zfs-2.3.0"]="6.12"
  ["zfs-2.3.1"]="6.13"
  ["zfs-2.3.2"]="6.14"
  ["zfs-2.2.8"]="6.15"
  ["zfs-2.3.3"]="6.15"
  ["zfs-2.3.4"]="6.16"
  ["zfs-2.3.5"]="6.17"
)

MAX_KERNEL=${COMPATIBILITY_MATRIX[$ZFS_VERSION]:-}

if [[ -z "$MAX_KERNEL" ]]; then
  echo "ERROR: Unknown ZFS version $ZFS_VERSION" >&2
  echo "This version is not in the compatibility matrix." >&2
  echo "Please update scripts/check-compatibility.sh to include this version." >&2
  exit 1
fi

# Compare kernel versions (semantic-aware by leveraging sort -V)
if [[ $(printf '%s\n%s\n' "$KERNEL_MAJOR_MINOR" "$MAX_KERNEL" | sort -V | tail -n1) != "$MAX_KERNEL" ]]; then
  echo "ERROR: ZFS $ZFS_VERSION is only compatible with Linux kernels up to $MAX_KERNEL" >&2
  echo "Current kernel: $KERNEL_MAJOR_MINOR" >&2
  echo "Please wait for a newer ZFS release or use an older kernel" >&2
  exit 1
fi

echo "✓ ZFS $ZFS_VERSION is compatible with kernel $KERNEL_MAJOR_MINOR (max: $MAX_KERNEL)"
