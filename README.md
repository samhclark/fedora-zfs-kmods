# fedora-zfs-kmods
Some ZFS kmods that will help me not need to spend so much time building my CoreOS spin. 

## Why?

Why not use the [ZFS Repo](https://openzfs.github.io/openzfs-docs/Getting%20Started/Fedora/index.html) and do an easy `rpm-ostree install -y zfs`? 

Because I'm working with bootable containers instead of plain ostree on bare metal. So, that `rpm-ostree install` command gest confused. It tries to build (or link, idk) the kernel with the *host* kernel, not the kernel inside the container. Which makes sense because while it's executing that _is_ the kernel inside the container. 

If you build from source instead, you can install different kernel headers and point to them directly. So! Here I am, building from source. 

## How this works

I don't really want to host the RPMs directly, mostly because I'm not sure how to do with with GitHub Packages. 

So instead, I'm going to release containers that have the RPMs inside. Here are some example tags based on the ZFS version and the kernel version, where the kernel version can be found with `rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}`. (NOT `uname-r` because when executed inside the container, that will give the kernel of the _host_).

```
Examples:
ZFS_VERSION=2.3.3
KERNEL_VERSION=6.15.5-200.fc42

ghcr.io/samhclark/fedora-zfs-kmods:zfs-${ZFS_VERSION}_kernel-${KERNEL_VERSION}

ghcr.io/samhclark/fedora-zfs-kmods:zfs-2.3.3_kernel-6.14.11-300.fc42
ghcr.io/samhclark/fedora-zfs-kmods:zfs-2.3.3_kernel-6.15.5-200.fc42
```

