# Kernel: Linux 6.18.59

`kernel/6.18/` is the kernel input of this recipe (the AIC8800 driver is in
`out-of-tree/aic8800/`):

- `series`: 263 patch paths, applied in this order to the pristine
  `linux-6.18.59.tar.xz` from cdn.kernel.org (sha256 in `scripts/lib/kernel.sh`).
- `patches/`: `backport/` (other people's patches, to drop once 6.18.y has
  them), `soc/<subsystem>/` (A733 support, any A733 board) and `board/dts/`
  (Cubie A7S wiring). File names carry no numbers; the order lives in `series`.
- `config`: a defconfig (output of `make savedefconfig`). Install it as
  `arch/arm64/configs/a7s_defconfig` and run `make a7s_defconfig`.

Apply with `patch -p1 --fuzz=0` and treat any `offset` or `fuzz` line as a
failure: a moved hunk means the base changed, and the patch has to be
regenerated, not nudged (the device tree has many identical OPP blocks).
`scripts/build.sh apply-patches` does exactly this.

## Changing the series

1. Apply the series to a pristine tree (`./build.sh fetch`, then `patch` as above in
   `work/linux-<version>`, or a git tree).
2. Edit, commit, regenerate the patch with `git format-patch`.
3. Put it into `kernel/6.18/patches/…` and list it in `series` at the right place.
4. Rebuild: `./build.sh`.

Patches of ours carry `From: DockSeed <dockseed@proton.me>`, one
`Assisted-by: Claude` and no `Signed-off-by`. Third-party patches keep their
authorship and trailers and name their source (`[ Upstream commit <sha> ]` or
`Link:`); if we changed one, it also says `[ adapted: … ]`. Code ported from
Allwinner's BSP says so in its header.

## Installing a kernel on the board

New kernels come as releases of this recipe; `sudo a7s-kernel-update` installs
the newest. There is no guarantee for how long new releases will be published.
The command is part of the package `a7s-kernel-hook`, which the images of
a7s-build carry.

1. `sudo a7s-kernel-update` installs the latest release (GitHub's "latest"
   leaves out drafts and pre-releases); `sudo a7s-kernel-update v6.18.60-R2`
   installs that release; a published test build is named the same way
   (`v6.18.60-T1`, a pre-release, with a note that it is one). It downloads the three packages
   of the release to a temporary directory below `/var/cache/a7s-kernel-update`,
   checks their sha256 against the release's `SHA256SUMS` (a mismatch removes
   the files and stops), installs them with `apt-get` and removes the directory.
   The `a7s-kernel-hook` package is installed only if the release has a newer one
   than the installed, in an `apt-get` call of its own before the kernel packages. It ends with one line: either that the new kernel starts
   at the next boot, or that it does not, after the messages of the hook that say
   why. `sudo a7s-kernel-update --help` lists the steps. If the newest kernel is
   installed and set to start, it says so and does nothing. In safe mode it
   installs nothing and names the way back (below), because a new kernel would
   not start there.
2. `sudo reboot`. The new kernel starts; the old one stays installed.
3. `uname -r` shows the release that runs.

The sha256 check is of the download, not of who made the release; there is no
apt source for the kernel packages.

If `a7s-kernel-update` stops with "the installation failed" (for example because
DKMS cannot build the WLAN driver), the boot entries are unchanged and the next
start uses the old kernel. To undo what was installed:
`sudo apt remove linux-image-<release> linux-headers-<release>`, and look at
`dkms status`. The downloaded packages stay in the directory the message names.

If the new kernel does not start, U-Boot starts safe mode after three tries,
with the kernel that worked before (no desktop, no WLAN; Ethernet, SSH and the
serial console work). To go back to it:

1. `sudo dpkg-reconfigure linux-image-$(uname -r)`: in safe mode `uname -r` is
   the old kernel. This sets it to start normally and clears the boot counter.
2. `sudo reboot`. The old kernel starts normally.
3. To remove the failed kernel: `sudo apt remove linux-image-<failed release>
   linux-headers-<failed release>` (`dpkg -l 'linux-image-*'` lists the names).
   Neither boot entry names it any more, so this is allowed. An older kernel that
   was fine can be removed once two newer ones have been installed and started.

If the new kernel starts but you want the old one back, run
`sudo dpkg-reconfigure linux-image-<old release>` and `sudo reboot`. The old
kernel becomes the one that starts, and the kernel that runs now becomes the
safe-mode kernel.

The same without `a7s-kernel-update`, for a first install or a board without
the command:

1. Download `linux-image-<release>_<version>_arm64.deb`,
   `linux-headers-<release>_<version>_arm64.deb`,
   `a7s-kernel-hook_<version>_all.deb` and `SHA256SUMS` from the release page.
2. `sha256sum -c --ignore-missing SHA256SUMS` (a test build's file names have a `.` where the package version has a `~`: `…_6.18.59.t4-1_…`)
3. Install the hook package first so that it is active when the kernel is
   installed: `sudo apt install ./a7s-kernel-hook_*.deb`, then `sudo apt install ./linux-image-<release>_*.deb ./linux-headers-<release>_*.deb`
4. Where the AIC8800 driver comes from DKMS (the images of a7s-build), check
   `dkms status`: the driver must be built for the new kernel.
5. `sudo reboot`

When the hook does not switch to the new kernel, it says why and which command
to run; the kernel is installed in any case. Each message is two lines. After
the cause is gone, `sudo dpkg-reconfigure linux-image-<release>` runs the check
again.

### What the hook does

This is reference; the steps above are all a user needs.

The kernel package puts the kernel and the device tree in `/boot` and
`/usr/lib/linux-image-<release>/`, but writes no boot entry: `a7s-kernel-hook`
does, for the two files that the image recipe writes, `/boot/extlinux/extlinux.conf`
(the normal start) and `extlinux-fallback.conf` (safe mode, which U-Boot starts
after three failed tries).

- **`/usr/share/kernel/postinst.d/zz-a7s-extlinux`** runs when a kernel package
  is installed, configured again (`dpkg-reconfigure`) or upgraded; the kernel
  package runs `/usr/share/kernel` and `/etc/kernel` together, sorted by name, so
  after DKMS. The new kernel and its device tree become the default entry. The
  kernel lines the default entry had, which is the kernel that started well, move
  to the safe-mode entry. If the previous install was not started yet
  (`/var/lib/a7s/kernel-pending` names it and it is not the running kernel), the
  default is replaced and the safe-mode entry stays. The `append` lines are
  never changed. Each file is written beside the old one, flushed and renamed,
  the safe-mode file first. After a power failure Linux sees each file either old
  or new once it has replayed the ext4 journal; U-Boot does not replay the
  journal when it reads the file, so it reads what the disk holds before that.
- **`/etc/kernel/header_postinst.d/zz-a7s-extlinux`** is a wrapper for the headers
  package, which knows `/etc/kernel` only. DKMS builds the WLAN driver there (its
  hook sorts before this one), and `apt` sets up the image package and the
  headers package in either order. If the image package comes first, its run
  notes the version in `/var/lib/a7s/kernel-waiting` and waits; the wrapper then
  makes the entry, only for that version. Any other run, such as a reinstall of
  old headers, does nothing.
- **`/usr/share/kernel/prerm.d/a7s-extlinux`** refuses to remove a kernel that
  either file starts (the default entry or the safe-mode entry); `apt` and
  `dpkg` stop with a message. **`/etc/kernel/header_prerm.d/a7s-extlinux`** does
  the same for the headers of that kernel (the headers package runs its hooks
  with `--exit-on-error`, so `apt remove linux-image-X linux-headers-X` removes
  neither). A kernel that neither file names can be removed, which is the case
  for the older ones after two more kernels were installed. When a removal is
  refused, the other hooks of `prerm.d` run anyway, DKMS's among them, and
  `dpkg` undoes the removal; DKMS builds the driver again at that step. Check
  `dkms status` after a refused removal.
- The two wrappers in `/etc` are conffiles (`dpkg` asks before replacing one you
  changed). The hooks in `/usr/share/kernel` go with the package; after `apt
  remove a7s-kernel-hook` the wrappers find no hook and do nothing.

The hook changes nothing, says why, and does not fail the install when:

- the kernel is not one of ours: the release name is not
  `<x>.<y>.<z>-r<n>` or `-t<n>`, or the package's maintainer is not
  `DockSeed <dockseed@proton.me>` (a Debian kernel never becomes the default);
- no systemd is running (a chroot; the image recipe writes the files itself);
- the two files do not start with the image recipe's header, or the kernel image
  or device tree is missing;
- `/boot` is not certainly the one the board started from: `root=` on the running
  kernel's command line is not the one of the default entry, or
  `/var/lib/a7s/root-identity.done` is missing (the first-start disk identity is
  not done);
- the default entry is not the running kernel: `/boot/vmlinuz-<release>` with
  another release than `uname -r`, or `/boot/Image` with another checksum than
  `kernel_sha256=` in `/boot/BUILD-ID`; then `/boot` is not shown to be the one
  that started, and the safe-mode entry must not be taken from it;
- the running kernel has the WLAN driver (`aic8800_fdrv.ko` under
  `/usr/lib/modules/<release>`) and the new one has not, because DKMS did not
  build it (or the headers are not installed): the board would lose WLAN and
  Bluetooth. This holds for an image built with `A7S_KERNEL=build`, whose driver
  is part of its own kernel and which has no DKMS: no kernel package becomes the
  default there;
- the running system is in safe mode (`a7s.fallback`), except for the one case
  below, or its `boot-complete.target` is not active: this start has not been
  confirmed as successful, so it must not become the safe-mode entry.

The one change in safe mode: when the kernel of the safe-mode entry is configured
again (`dpkg-reconfigure`, or its `.deb` installed again), it becomes the default
again. The safe-mode entry stays and the pending file goes, since the default is
the kernel that is running. The hook then clears the boot counter the way
`a7s-boot-good.service` of the image does (`/usr/bin/busybox devmem`, RTC
`GP_DATA_REG7`), so that the next start is a normal one. Without `busybox` it
prints the command and does not fail.

## Publishing a release

For the maintainer; the steps are those of [release.yml](../.github/workflows/release.yml).

1. Make sure `KERNEL_VERSION` in `scripts/lib/kernel.sh` is the kernel version
   to release, and rename the `[Unreleased]` section of `CHANGELOG.md` to
   `## [<kernel version>-R<n>] - <date>`. The workflow stops before the build
   when the tag does not name that version or the section is missing.
2. `git tag v<kernel version>-R<n>` on that commit, `git push origin` the tag
   (a `-T<n>` tag makes a test build, a pre-release).
3. The workflow builds the tag (`./build.sh all`, `deb`, `package`) and creates
   a draft release: three packages, the loose files, `SHA256SUMS`, the changelog
   section as text.
4. Read the draft (files, `KERNEL-ID`, text), then publish it by hand. Only a
   published `-R<n>` release is what `sudo a7s-kernel-update` installs.
5. In a7s-build, move the pins together: `KERNEL_RELEASE_TAG`, `_COMMIT`, `_NAME`,
   the three package names and their sha256 (from the release's `SHA256SUMS`)
   in `scripts/stages/kernel.sh`, and `KERNEL_RECIPE_COMMIT` to the same commit.

## Good to know

- **MAC address.** The kernel carries none. U-Boot writes `local-mac-address`
  into `ethernet0` from its `ethaddr`; without one the boot chain's
  `CONFIG_NET_RANDOM_ETHADDR=y` gives a random address per boot, so DHCP sees a
  new machine after every reboot.
- **Config.** `MEMTEST=y` stays (`memtest=1` on the kernel command line
  excludes a bad DRAM window); `KPROBES`, `DEBUG_FS` and the function tracer
  stay as debugging support. `SECURITY_DMESG_RESTRICT=y`
  as in Debian's kernel: only root reads the kernel log. ISO9660, UDF, exFAT and
  NTFS (ntfs3) are modules, as in Debian's kernel, for sticks, cards and DVDs;
  so are Btrfs, XFS, F2FS and the NFS and SMB clients, for disks and network
  shares (the tools come from Debian: `btrfs-progs`, `xfsprogs`, `f2fs-tools`,
  `nfs-common`, `cifs-utils`).
- **Container and VM host.** The config is minimal, but a server's standard
  equipment is in, as modules where Kconfig allows it: what Docker, containerd
  and Podman need (`VETH`, `BRIDGE`, `BRIDGE_NETFILTER`, `OVERLAY_FS`, the
  iptables/nftables NAT targets, `NF_CT_NETLINK`, IPVS, VXLAN, MACVLAN, IPVLAN,
  `CFS_BANDWIDTH`, `BLK_DEV_THROTTLING`, `CHECKPOINT_RESTORE`), what a KVM host
  needs beyond `KVM=y` (`VHOST_NET`, `VHOST_VSOCK`, `MACVTAP`), and the usual
  firewall and traffic-control pieces (ipset, the common xt matches, tc
  ingress/flower/htb/fq_codel) plus WireGuard. Checked with moby's
  `contrib/check-config.sh`; it still lists SELinux (AppArmor is the LSM,
  see Security), `MEMCG_SWAP` (no such option in 6.18) and the ZFS tools. A new option of this kind goes in as a module, measured with the
  service that needs it, not by copying a distribution config.
- **Home server.** Also modules: the NFS server (`NFSD`, v3 always,
  `NFSD_V4`), software RAID for `mdadm` (`DM_RAID` pulls in `BLK_DEV_MD` and
  the RAID personalities, so they do not show in `config`), device mapper for
  LUKS and LVM with thin pools and snapshots, NBD, the common USB network
  adapters (`r8152`, `ax88179_178a`, CDC Ethernet/NCM, RNDIS), USB video and
  audio class, USB printers, the CH341 and PL2303 serial adapters next to
  CP210x and FTDI, kTLS, BBR and CAKE. `HIDRAW`, `USB_HIDDEV` (UPS monitoring
  over USB) and `PSI` are built in. zswap stays out: swap is zram.
- **Security.** As in Debian's kernel, AppArmor is the default LSM
  (`CONFIG_LSM`, no kernel parameter needed), with Yama, Landlock
  and the BPF LSM, and `AUDIT` (AppArmor selects it). Hardening as in
  Debian: `FORTIFY_SOURCE`, `HARDENED_USERCOPY`, `INIT_ON_ALLOC_DEFAULT_ON`,
  hardened lists and slab freelists, a shuffled page allocator, a randomised
  kernel stack offset, `SYN_COOKIES`. Two differences: AppArmor's
  `EXPORT_BINARY` stays off (it would select `ZSTD_COMPRESS` built in), and
  `IO_STRICT_DEVMEM` stays off, because the image clears the boot chain's
  boot counter in an RTC register through `/dev/mem` while the RTC driver
  holds that range. Lockdown is not part of the config: it needs a verified
  boot chain to have an effect, and it would require signed modules, which
  DKMS-built modules on the board are not.
- **Tracing and BPF.** BTF (`DEBUG_INFO_BTF`, module BTF too), the function
  tracer with fprobe, syscall tracepoints and tc BPF, so `bpftool`,
  `bpftrace` and libbpf CO-RE tools work and systemd's
  `RestrictFileSystems=` has its BPF LSM. BTF needs the full debug info, so
  `DEBUG_INFO_REDUCED` is off; it is generated by `pahole`, which
  is part of the builder for that reason. Together with the function tracer
  this makes `Image` about 8 MB larger (21 to 29 MB; BTF is 4.7 MB of it).
- **Also as in Debian:** squashfs with xz, zstd, lz4 and lzo as a module
  (snaps), EROFS, CUSE, F2FS compression, quota for ext4 and XFS,
  `USERFAULTFD`, schedstats (off until `kernel.sched_schedstats=1`), the netdev
  LED trigger, and for Kubernetes NFLOG, nftables numgen, the IPVS set types
  and schedulers, IPIP, rpfilter, nfacct, the owner match and nftables bridge
  filtering. Preemption is full by default, with `PREEMPT_DYNAMIC`:
  `preempt=voluntary` on the command line selects Debian's model.

## Not carried

Test instruments (fault injection, test-only tracing) are not part of the
series. Neither are debugfs switches and module parameters that write to
hardware; the code behind them and the read-only status files remain.
Diagnostic messages that only read and print are part of it: the dyndbg
lines of `pinctrl-sunxi-instrument-the-power-source-handler` (silent until
`dyndbg="file pinctrl-sunxi.c +p"`) and the warnings of
`drm-a733-dp-instrument-the-training-failure-paths` on a failed link training.

## Checked

Against the pristine tree in the builder container: all 263 patches apply at
fuzz 0 without offsets; `make a7s_defconfig && make savedefconfig` reproduces
`config` (apart from its header comment); `make dtbs` and `make W=1` over the
display, PHY, PCIe, CCU, pin controller and USB/Bluetooth code touched by the
series are warning-free; `dt_binding_check` passes for the CH334 and AIC8800D80
bindings, and `dtbs_check` of `sun60i-a733-cubie-a7s.dtb` against those two
bindings and the generic USB device and hub schemas reports nothing
(dtschema 2026.9, installed in the builder with pip: the builder image does not
carry it). The check covers only those schemas, not every binding of the board.
