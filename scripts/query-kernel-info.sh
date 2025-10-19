#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-quay.io/fedora/fedora-coreos:stable}"

INSPECT_OUTPUT=$(skopeo inspect "docker://${IMAGE}")

KERNEL_VERSION=$(jq -r '.Labels["ostree.linux"]' <<<"${INSPECT_OUTPUT}")
if [[ -z "${KERNEL_VERSION}" || "${KERNEL_VERSION}" == "null" ]]; then
  echo "Failed to determine kernel version from ${IMAGE}" >&2
  exit 1
fi

KERNEL_MAJOR_MINOR=$(cut -d'.' -f1-2 <<<"${KERNEL_VERSION}")
FEDORA_VERSION=$(jq -r '.Labels["org.opencontainers.image.version"] | split(".")[0]' <<<"${INSPECT_OUTPUT}")
if [[ -z "${FEDORA_VERSION}" || "${FEDORA_VERSION}" == "null" ]]; then
  echo "Failed to determine Fedora version from ${IMAGE}" >&2
  exit 1
fi

jq -n \
  --arg kernel_version "${KERNEL_VERSION}" \
  --arg kernel_major_minor "${KERNEL_MAJOR_MINOR}" \
  --arg fedora_version "${FEDORA_VERSION}" \
  '{"kernel-version": $kernel_version, "kernel-major-minor": $kernel_major_minor, "fedora-version": $fedora_version}'
