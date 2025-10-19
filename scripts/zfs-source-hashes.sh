#!/usr/bin/env bash

# shellcheck disable=SC2034 # Allow unused associative array when sourced
declare -A ZFS_TARBALL_SHA256S=(
  ["zfs-2.2.7"]="__REPLACE_WITH_ACTUAL_SHA256_FOR_zfs-2.2.7__"
  ["zfs-2.2.8"]="__REPLACE_WITH_ACTUAL_SHA256_FOR_zfs-2.2.8__"
  ["zfs-2.3.0"]="__REPLACE_WITH_ACTUAL_SHA256_FOR_zfs-2.3.0__"
  ["zfs-2.3.1"]="__REPLACE_WITH_ACTUAL_SHA256_FOR_zfs-2.3.1__"
  ["zfs-2.3.2"]="__REPLACE_WITH_ACTUAL_SHA256_FOR_zfs-2.3.2__"
  ["zfs-2.3.3"]="__REPLACE_WITH_ACTUAL_SHA256_FOR_zfs-2.3.3__"
  ["zfs-2.3.4"]="__REPLACE_WITH_ACTUAL_SHA256_FOR_zfs-2.3.4__"
)

lookup_zfs_tarball_hash() {
  local zfs_version="$1"
  local hash="${ZFS_TARBALL_SHA256S[$zfs_version]:-}"

  if [[ -z "$hash" ]]; then
    echo "ERROR: Unknown ZFS version $zfs_version" >&2
    echo "Please update scripts/zfs-source-hashes.sh with the expected hash." >&2
    return 1
  fi

  if [[ "$hash" == __REPLACE_WITH_ACTUAL_SHA256_FOR_*__ ]]; then
    echo "ERROR: Placeholder hash detected for $zfs_version." >&2
    echo "Please replace the placeholder in scripts/zfs-source-hashes.sh with the real sha256." >&2
    return 1
  fi

  printf '%s\n' "$hash"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <zfs_version>" >&2
    exit 1
  fi

  if ! lookup_zfs_tarball_hash "$1"; then
    exit 1
  fi
fi
