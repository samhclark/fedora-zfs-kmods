#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-quay.io/fedora/fedora-coreos:stable}"
CONTAINER_CLI="${CONTAINER_CLI:-}"

if [[ -z "${CONTAINER_CLI}" ]]; then
  if command -v podman >/dev/null 2>&1; then
    CONTAINER_CLI="podman"
  elif command -v docker >/dev/null 2>&1; then
    CONTAINER_CLI="docker"
  else
    CONTAINER_CLI=""
  fi
fi

INSPECT_OUTPUT=$(skopeo inspect "docker://${IMAGE}")

KERNEL_VERSION=$(jq -r '.Labels["ostree.linux"]' <<<"${INSPECT_OUTPUT}")
if [[ -z "${KERNEL_VERSION}" || "${KERNEL_VERSION}" == "null" ]]; then
  if [[ -z "${CONTAINER_CLI}" ]]; then
    echo "Failed to determine kernel version from ${IMAGE} and no container runtime available for fallback" >&2
    exit 1
  fi

  if ! RPM_QUERY_OUTPUT=$("${CONTAINER_CLI}" run --rm --entrypoint rpm "${IMAGE}" \
    -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n'); then
    echo "Failed to run rpm fallback inside ${IMAGE}" >&2
    exit 1
  fi

  KERNEL_VERSION=$(head -n1 <<<"${RPM_QUERY_OUTPUT}" | tr -d '\r')
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
