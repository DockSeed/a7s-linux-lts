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
may be short).

## [Unreleased]

### Added

- `a7s-aic8800-dkms`, the WLAN/BT driver source for DKMS, is a release
  file. `a7s-kernel-update` installs it before the kernel packages, so a
  board gets a new driver without a new image. It links
  `/usr/lib/firmware/aic8800_fw/USB/aic8800D80`, where the `-11` driver opens
  the firmware, to `/usr/lib/firmware/aic8800D80`.

### Fixed

- USB host on the A733: the HCI interface register selects AHB INCR16 bursts
  instead of INCR8, as the vendor kernel does for this SoC
  (`phy-sun4i-usb-use-incr16-bursts-on-the-a733`). With INCR8 the AIC8800
  WLAN on USB1 stopped under memory load from a second bus master; the
  register reads `0x0b01` instead of `0x0701`. The binding gains the A733
  compatible the device tree already uses
  (`dt-bindings-phy-sun50i-a64-usb-phy-add-the-a733`). Other SoCs are
  unchanged. Tested as `v6.18.63-T1`.
- aic8800: lengths and indexes from the device are checked before use (rx
  frames, A-MSDU subframes, firmware messages and their table indexes, scan
  results, association IEs, QoS TIDs), and the error paths of rx refill,
  bulk-in errors, tx drops and rx defragmentation no longer sleep in atomic
  context, leak or use freed memory (`out-of-tree/aic8800/README.md`). New
  counter `rx_bad_frame_drops`.

### Changed

- aic8800: patches from other projects are carried unchanged in
  `out-of-tree/aic8800/patches/upstream/` and applied before ours: Feng
  Zhang's `fix-Lower-the-debugging-log-level`, bnister's Bluetooth firmware
  upload fix and Jiali Chen's `fix-usb-suspend-reboot-hang`. What we changed
  in them is a patch of our own on top. Feng Zhang's PCIe and SDIO hunks now
  apply too (not built). Our patch messages are shorter.
- aic8800: the source is Radxa's `5.0+git20260123.5f7be68d-11` as shipped
  (its `debian/patches/series`, with Feng Zhang's and Jiali Chen's patches),
  plus radxa-pkg/aic8800 pull requests 114 (16 of 17) and 106 unchanged.
  Seven of our patches and the compat patch are dropped, one is added. The
  counter `rx_unknown_msgs` is gone.

## [6.18.63-R2] - 2026-11-15

6.18.63-R1 with the `netconsole` module added; the patches, the configuration
otherwise and the dtb are unchanged. `sudo a7s-kernel-update` on a board with an
earlier release installs this one.

### Added

- `CONFIG_NETCONSOLE=m` (which selects `NETPOLL`): the `netconsole` module sends
  kernel log messages over UDP to another host
  (`modprobe netconsole netconsole=<src-port>@<src-ip>/<dev>,<tgt-port>@<tgt-ip>/<tgt-mac>`),
  to capture oops and panic output when no serial console is attached.

## [6.18.63-R1] - 2026-11-11

The recipe of 6.18.62-R1 on Linux 6.18.63, with fixes for 16 CVEs that
6.18.63 does not carry. Configuration and the packages are the same;
`sudo a7s-kernel-update` on a board with 6.18.62-R1 installs this release.

### Changed

- Linux 6.18.63 (longterm) as the base, up from 6.18.62, with the fixes of that
  stable release
  ([ChangeLog-6.18.63](https://cdn.kernel.org/pub/linux/kernel/v6.x/ChangeLog-6.18.63)).
- Three patches regenerated against the new base, because stable changed the
  surrounding lines of `btusb.c` and `pci.c`: only hunk offsets differ, not the
  patched code.
  `bluetooth-btusb-request-the-reset-gpio-only-where-a-handler-uses-it`,
  `pci-err-reset-root-ports-platform-specific` and
  `pci-host-common-link-down-handling-for-root-ports`. The rest of the series
  applies unchanged at fuzz 0 without offsets.
- None of the backports in `kernel/6.18/patches/backport/` is in 6.18.63, so
  all stay.

### Security

The kernel CVE team listed 106 CVEs as unfixed in 6.18.63 (vulns.git of
2026-11-10). This release:

- fixes 16 with patches in `kernel/6.18/patches/cve/`: CVE-2026-46017,
  CVE-2026-89632, CVE-2026-98125, CVE-2026-98285, CVE-2026-98376,
  CVE-2026-98427, CVE-2026-98444, CVE-2026-98551, CVE-2026-98570,
  CVE-2026-98599, CVE-2026-98814, CVE-2026-98954, CVE-2026-98960,
  CVE-2026-98972, CVE-2026-99272, CVE-2026-99275;
- is not affected by 61: for 49 the fixed code is not built, for 2 the fix
  leaves every built object byte-identical, 4 concern code that 6.18 does not
  have (CVE-2026-31710, CVE-2026-74342, CVE-2026-89772, CVE-2026-98983), and 6
  are not reachable with this configuration and device tree (CVE-2026-43042
  MPLS, CVE-2026-43174 io_uring zero-copy receive, CVE-2026-43326 sched_ext,
  CVE-2026-80899 erofs on-demand, CVE-2026-98124 fscache, CVE-2026-98288
  stmmac TSO; see `docs/kernel.md`, *CVE fixes*);
- leaves 29 open, whose fix needs a backport by hand and is expected from a
  later 6.18 stable release: CVE-2026-53091, CVE-2026-53106, CVE-2026-64160,
  CVE-2026-74314, CVE-2026-74354, CVE-2026-74533, CVE-2026-89584,
  CVE-2026-90237, CVE-2026-90256, CVE-2026-93044, CVE-2026-93270,
  CVE-2026-98118, CVE-2026-98153, CVE-2026-98284, CVE-2026-98318,
  CVE-2026-98558, CVE-2026-98589, CVE-2026-98628, CVE-2026-98747,
  CVE-2026-98788, CVE-2026-98789, CVE-2026-98799, CVE-2026-98800,
  CVE-2026-98813, CVE-2026-98815, CVE-2026-98816, CVE-2026-98818,
  CVE-2026-98869, CVE-2026-100073.

## [6.18.62-R1] - 2026-11-08

The recipe of 6.18.60-R2 on Linux 6.18.62. Configuration and the packages are
the same; `sudo a7s-kernel-update` on a board with 6.18.60-R2 installs this
release.

### Changed

- Linux 6.18.62 (longterm) as the base, up from 6.18.60, with the fixes of the
  two stable releases in between
  ([ChangeLog-6.18.61](https://cdn.kernel.org/pub/linux/kernel/v6.x/ChangeLog-6.18.61),
  [ChangeLog-6.18.62](https://cdn.kernel.org/pub/linux/kernel/v6.x/ChangeLog-6.18.62)).
- Six patches regenerated against the new base, because stable changed the
  surrounding lines of `stmmac_main.c`, `stmmac_platform.c`, `btusb.c`
  and `pci.c`: only hunk offsets differ, not the patched code.
  `net-stmmac-move-msi-data-out-of-struct-stmmac_priv`,
  `net-stmmac-platform-read-channels-irq`,
  `net-stmmac-retry-a-failed-rx-refill-from-a-timer`,
  `bluetooth-btusb-request-the-reset-gpio-only-where-a-handler-uses-it`,
  `pci-err-reset-root-ports-platform-specific` and
  `pci-host-common-link-down-handling-for-root-ports`. The rest of the series
  applies unchanged at fuzz 0 without offsets.
- None of the backports in `kernel/6.18/patches/backport/` is in 6.18.61 or
  6.18.62, so all stay.

## [6.18.60-R2] - 2026-11-01

The kernel of 6.18.60-R1 with one backport from mainline. Configuration and the
packages are the same; `sudo a7s-kernel-update` on a board with 6.18.60-R1
installs this release.

### Fixed

- A boot in which the pin controller is ready before the PMIC's regulators no
  longer logs `Error applying setting, reverse things back` for the devices
  whose pins wait for those supplies (PWM, UARTs, Ethernet); the devices probe
  again later as before. Backport of upstream commit 33d4feff673b
  ("pinctrl: core: use dev_err_probe() when applying state"), which is not in
  6.18.60.

## [6.18.60-R1] - 2026-11-01

The recipe of 6.18.59-R2 on the next longterm release of Linux. Configuration,
patch series and the packages are the same; `sudo a7s-kernel-update` on a board
with 6.18.59-R2 installs this release.

### Changed

- Linux 6.18.60 (longterm) as the base, up from 6.18.59, with the fixes of that
  stable release ([ChangeLog-6.18.60](https://cdn.kernel.org/pub/linux/kernel/v6.x/ChangeLog-6.18.60)).
  The series applies unchanged at fuzz 0 without offsets.

## [6.18.59-R2] - 2026-10-31

The same kernel as 6.18.59-R1, plus the kernel update path first published
in 6.18.59-T5 and two clearer messages.

### Added

- `a7s-kernel-hook_<version>_all.deb`, a third package of the release: hooks
  in `/usr/share/kernel` that make a newly installed kernel the default entry of
  `/boot/extlinux/extlinux.conf` and the kernel that booted well the safe-mode
  entry of `extlinux-fallback.conf`, and that refuse to remove a kernel that either
  file boots, headers included. They change nothing for other kernels, in a chroot, in
  safe mode (but for making the safe-mode kernel the default again), before the
  boot has been confirmed as successful, or when the new kernel would have no WLAN
  driver (DKMS did not build it). See `docs/kernel.md`.
- `sudo a7s-kernel-update` (in the same package): installs the newest release,
  or the one named (`v6.18.60-R2`, or a published test build `v6.18.60-T1`), after
  checking the sha256 of the download. Run it when you want to update.
- Step `hook` (`./build.sh hook`), which builds that package without a kernel
  build; step `deb` runs it too.

### Fixed

- `a7s-kernel-update` names the missing package in a plain message instead of
  a search pattern when a release has no hook package (releases before
  `v6.18.59-R2`), and suggests running it without a tag when one was given.
- The kernel hook no longer says "another disk" on the first start after
  flashing, when the boot entries already name the disk the system runs from;
  it asks you to restart once and then run `dpkg-reconfigure`.

## [6.18.59-T5] - 2026-10-31

Test build.

### Added

- `a7s-kernel-hook_<version>_all.deb`, a third package of the release: hooks
  in `/usr/share/kernel` that make a newly installed kernel the default entry of
  `/boot/extlinux/extlinux.conf` and the kernel that booted well the safe-mode
  entry of `extlinux-fallback.conf`, and that refuse to remove a kernel that either
  file boots, headers included. They change nothing for other kernels, in a chroot, in
  safe mode (but for making the safe-mode kernel the default again), before the
  boot has been confirmed as successful, or when the new kernel would have no WLAN
  driver (DKMS did not build it). See `docs/kernel.md`.
- `sudo a7s-kernel-update` (in the same package): installs the newest release,
  or the one named (`v6.18.60-R2`, or a published test build `v6.18.60-T1`), after
  checking the sha256 of the download. Run it when you want to update.
- Step `hook` (`./build.sh hook`), which builds that package without a kernel
  build; step `deb` runs it too.

## [6.18.59-R1] - 2026-10-29

First release: the same recipe as the test build 6.18.59-T4; the sections
below list what it contains.

## [6.18.59-T4] - 2026-10-29

Test build.

### Fixed

- The A733 r-pinctrl leaves the withstand voltage of banks PL and PM as the
  boot chain set it; the boot no longer logs
  `Couldn't set bank PL I/O bias: -22`.

## [6.18.59-T3] - 2026-10-28

Test build.

### Added

- Device tree nodes for the on-board USB hub (WCH CH334F) and the AIC8800D80
  WiFi/Bluetooth module behind it: `onboard_usb_dev` (built as a module) owns
  the module's supply and its reset line. Backports of the CH334 binding and its
  `onboard_usb_dev` entry, a binding and an `onboard_usb_dev` entry for the
  AIC8800D80.
- Names for the I/O supplies of the remaining pin banks, from the schematic;
  bank PF sets its withstand mode together with its supply.

### Changed

- btusb requests the reset GPIO only for devices whose reset handler uses it.

### Fixed

- The AIC8800 drivers keep their data on their own USB interface instead of
  the USB device, whose driver data belongs to `onboard_usb_dev`. A disconnect
  of the module no longer ends in an oops.

## [6.18.59-T2] - 2026-10-28

Test build, the first one built by the release workflow on GitHub.

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
