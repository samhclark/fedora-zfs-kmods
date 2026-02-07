#!/usr/bin/env bash
set -euo pipefail

PREFIX="zfs-2.4"

usage() {
  cat <<USAGE
Usage: $0 [--prefix PREFIX]

Options:
  --prefix PREFIX   ZFS release tag prefix to search for (default: zfs-2.4)
  -h, --help        Show this help message
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      if [[ $# -lt 2 ]]; then
        echo "Error: --prefix requires an argument" >&2
        exit 1
      fi
      PREFIX="$2"
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

ZFS_TAG=$(gh release list \
  --repo openzfs/zfs \
  --json publishedAt,tagName \
  --jq "[.[] | select(.tagName | startswith(\"${PREFIX}\"))] | sort_by(.publishedAt) | last | .tagName" \
  --limit 100)

if [[ -z "${ZFS_TAG}" ]]; then
  echo "Error: No releases found for prefix '${PREFIX}'" >&2
  exit 1
fi

ZFS_VERSION=${ZFS_TAG#zfs-}

cat <<JSON
{
  "zfs-tag": "${ZFS_TAG}",
  "zfs-version": "${ZFS_VERSION}"
}
JSON
