# Kernel: Linux 6.18.59

`kernel/6.18/` is the kernel input of this recipe (the AIC8800 driver is in
`out-of-tree/aic8800/`):

- `series`: 257 patch paths, applied in this order to the pristine
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

Test instruments (fault injection, debug instrumentation) are not part of the
series. Neither are debugfs switches and module parameters that write to
hardware; the code behind them and the read-only status files remain.

## Checked

Against the pristine tree in a `debian:trixie` container: all 257 patches
apply at fuzz 0 without offsets; `make a7s_defconfig && make savedefconfig`
reproduces `config`; `make dtbs` and `make W=1` over the display, PHY, PCIe and
CCU code are warning-free.
