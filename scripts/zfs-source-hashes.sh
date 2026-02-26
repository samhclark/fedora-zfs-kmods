#!/usr/bin/env bash

# shellcheck disable=SC2034 # Allow unused associative array when sourced
declare -A ZFS_TARBALL_SHA256S=(
  ["zfs-2.2.7"]="c144057d631d8a1a140f78db884b207e811c42a35ee4c3a6504ad438f237d974"
  ["zfs-2.2.8"]="a57b2cdd6ad5c15373d2e64313c2858e13530d0f255183db17b6a740e1a745c0"
  ["zfs-2.3.0"]="d4e8343c2ad91301c08d47df9b32d5ec4c9fe458d00e74df41e0d58ecbd44bfd"
  ["zfs-2.3.1"]="b870b9e21a34e6f14e04bcaf3795d14ce57270ea1f339f12b4cad25a10841e74"
  ["zfs-2.3.2"]="877a6b37755245955fadd68cee2f2729f7acc10e2aad5dd77a6426a8d46aca83"
  ["zfs-2.3.3"]="ba8db7766e6724dc1c1b9287174bc9022dab521919d3353dc488aad9e55de541"
  ["zfs-2.3.4"]="940af1303a01df3228b3e136a2ae99bb4d7a894f71f804cf7d3ae198f959dd46"
  ["zfs-2.3.5"]="f7513a31368924493b1715439337f3f7720a5d8d873300c6cd1741fac8616b85"
  ["zfs-2.4.0"]="84a37d5096b189375d2dbb74759d4dee8a5fcf14c9c3039d5397ce5019af133c"
  ["zfs-2.4.1"]="b6129b23e6bc6deb75d9fa4f1c24c5cfc079f849b8840d200c4ad46a2cc1c883"
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
