ARG FEDORA_VERSION
ARG KERNEL_MAJOR_MINOR
ARG ZFS_VERSION

#####
# 
#  Stage 1: Gather info about the CoreOS kernel
#
#####
FROM quay.io/fedora/fedora-coreos:stable as kernel-query
ARG FEDORA_VERSION
ARG KERNEL_MAJOR_MINOR
ARG ZFS_VERSION

# Confirm the actual kernel matches expectations
RUN rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' > /kernel-version.txt
RUN [[ "$(cat /kernel-version.txt)" == ${KERNEL_MAJOR_MINOR}.* ]]

# Confirm the actual Fedora version matches expectations
RUN [[ "$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2)" == "${FEDORA_VERSION}" ]]


#####
# 
#  Stage 2: Build ZFS kmod from source
#
#####
FROM quay.io/fedora/fedora:${FEDORA_VERSION} as builder
ARG ZFS_VERSION
ARG FEDORA_VERSION
COPY --from=kernel-query /kernel-version.txt /kernel-version.txt
COPY scripts/zfs-source-hashes.sh /tmp/zfs-source-hashes.sh

# Need to add the updates archive to install specific kernel versions
RUN dnf install -y fedora-repos-archive

# Install ZFS build dependencies
# Using https://openzfs.github.io/openzfs-docs/Developer%20Resources/Custom%20Packages.html
RUN KERNEL_VERSION="$(cat /kernel-version.txt)" && \
    dnf install -y --setopt=install_weak_deps=False \
        autoconf automake gcc \
        kernel-$KERNEL_VERSION kernel-devel-$KERNEL_VERSION kernel-modules-$KERNEL_VERSION kernel-rpm-macros \
        libaio-devel libattr-devel libblkid-devel libffi-devel libtirpc-devel libtool libunwind-devel libuuid-devel \
        make ncompress openssl openssl-devel \
        python3 python3-devel python3-cffi python3-packaging python3-setuptools \
        rpm-build systemd-devel zlib-ng-compat-devel

# Build ZFS
WORKDIR /zfs
RUN set -euo pipefail \
    && source /tmp/zfs-source-hashes.sh \
    && EXPECTED_HASH="$(lookup_zfs_tarball_hash "$ZFS_VERSION")" \
    && TARBALL_PATH="$(mktemp)" \
    && curl --fail --location "https://github.com/openzfs/zfs/archive/refs/tags/${ZFS_VERSION}.tar.gz" \
        --output "$TARBALL_PATH" \
    && ACTUAL_HASH="$(sha256sum "$TARBALL_PATH" | awk '{print $1}')" \
    && if [[ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]]; then \
        echo "ERROR: Hash mismatch for ${ZFS_VERSION}" >&2; \
        echo "Expected: $EXPECTED_HASH" >&2; \
        echo "Actual:   $ACTUAL_HASH" >&2; \
        exit 1; \
    fi \
    && tar xzf "$TARBALL_PATH" -C . --strip-components 1 \
    && rm -f "$TARBALL_PATH"

RUN export KERNEL_VERSION="$(cat /kernel-version.txt)" && \
    ./autogen.sh && \
    ./configure \
        -with-linux=/usr/src/kernels/$KERNEL_VERSION/ \
        -with-linux-obj=/usr/src/kernels/$KERNEL_VERSION/ && \
    make -j $(nproc) rpm-utils rpm-kmod

# Rearrange artifacts
RUN mkdir -p /var/cache/rpms/kmods/zfs/{debug,devel,other,src} && \
    mv ./*src.rpm /var/cache/rpms/kmods/zfs/src/ && \
    mv ./*devel*.rpm /var/cache/rpms/kmods/zfs/devel/ && \
    mv ./*debug*.rpm /var/cache/rpms/kmods/zfs/debug/ && \
    mv zfs-dracut*.rpm /var/cache/rpms/kmods/zfs/other/ && \
    mv zfs-test*.rpm /var/cache/rpms/kmods/zfs/other/ && \
    mv ./*.rpm /var/cache/rpms/kmods/zfs/

#####
# 
#  Stage 3: Final image
#
#####
FROM scratch
COPY --from=builder /var/cache/rpms/kmods/zfs/ /