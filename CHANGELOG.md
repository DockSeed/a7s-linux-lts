<!--
SPDX-License-Identifier: GPL-2.0-only OR MIT
-->
# Changelog

All notable changes to this recipe are listed here, one section per release.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

A tag is named `v<kernel version>-T<n>` for a test build or
`v<kernel version>-R<n>` for a release, for example `v6.18.59-R1`: the Linux
stable version the recipe builds, a letter and a counter that restarts at 1 with
each new kernel version. Pushing such a tag builds it; the text of the draft
release on GitHub is the section below with the same version (for a test tag it
may be short). No schedule is promised for new releases.

## [Unreleased]

Nothing yet.

## [6.18.59-T2] - 2026-10-28

Test build of the release 6.18.59-R1 below: same recipe, built by the release
workflow on GitHub.

## [6.18.59-R1] - 2026-10-28

First release.

### Added

- Linux 6.18.59 (the stable tarball from cdn.kernel.org, sha256 pinned) with 257
  patches for the Allwinner A733 and the Radxa Cubie A7S: 15 backports, 221
  SoC patches (clocks, pin control, power domains, MMC, Ethernet, USB, PCIe,
  PWM, thermal, DVFS, display, GPU, IOMMU, DMA, audio, device tree) and 21 board
  device tree patches.
- Config for server use, as modules where Kconfig allows it: what Docker,
  containerd, Podman and Kubernetes need (bridge, veth, overlayfs, netfilter
  NAT, IPVS, VXLAN, cgroup controllers), KVM host support (vhost-net,
  vhost-vsock, macvtap), WireGuard, the NFS server, software RAID, device
  mapper (crypt, thin provisioning, snapshots), NBD, common USB network
  adapters, USB video and audio class, USB serial adapters, kTLS, BBR and CAKE.
- Config for security and tracing: AppArmor as the default LSM with Yama,
  Landlock and the BPF LSM; kernel hardening options; BTF including
  module BTF, the function tracer with fprobe, syscall tracepoints and tc BPF.
- A pwm-fan on header J7 as a cooling device of both CPU thermal zones.
- Release files, built by GitHub Actions from the tagged commit with
  `./build.sh` and attached to the release: the kernel as Debian packages
  (`linux-image-<release>` with the modules and device trees, and
  `linux-headers-<release>` for DKMS, named for the release so that a newer one
  installs beside an older one), `Image`, the device tree blob, `config`,
  `System.map`, `KERNEL-ID`, the module tree
  (`a7s-linux-lts-<release>-modules.tar.xz`), the unchanged kernel tarball and
  `SHA256SUMS`.
- `./build.sh deb` and `./build.sh package`, which make the Debian packages with
  the kernel's `bindeb-pkg` and assemble the release files from a finished
  build, and refuse a module without a GPL-compatible `MODULE_LICENSE`.
- `A7S_KERNEL_REVISION` (`r1`, `t1`): the revision of a tag, part of the kernel
  release (`6.18.59-r1`) and of the build identity.

### Not included

- The AIC8800 WLAN/BT driver is not part of the release files; the image
  recipe builds it from its pinned source.
