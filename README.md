# a7s-linux-lts

Linux 6.18 LTS for the **Radxa Cubie A7S** (Allwinner A733): the mainline stable
tarball plus a series of patches for the A733 and the board, cross compiled for
arm64, and the AIC8800 WLAN/BT driver built against it.

**You build it yourself. We ship no binary**: the kernel tarball is downloaded
from cdn.kernel.org and checked against a sha256 committed here; the driver
source is fetched at a pinned commit.

The kernel is one input of the image recipe
[a7s-build](https://github.com/DockSeed/a7s-build), which pins this repository
to a commit. The boot chain is a separate recipe:
[a733-bootchain](https://github.com/DockSeed/a733-bootchain).

## What you get

In `out/`:

- `Image`, `sun60i-a733-cubie-a7s.dtb`, the final `config` and `System.map`
- `modules/`: the output of `modules_install` (stripped) with the two AIC8800
  modules in `updates/aic8800/`, `depmod` run over the set
- `KERNEL-ID`: `key`, kernel version and release, tarball sha256, the driver's
  upstream commit, the build time, and the sha256 of `Image`, the dtb, `config`
  and `System.map`

The build refuses to finish unless the result is what the recipe says: every
patch applies at fuzz 0 without offset, the symbols and module files listed in
[pins/kernel-config.assert](pins/kernel-config.assert) are present, the kernel
release is the expected one, and the driver's modules and their Bluetooth
dependencies resolve.

## Build

Needs bash, coreutils and podman or docker; nothing else on the host.

```sh
./build.sh
```

The first run builds the builder image from `container/` (Debian trixie pinned
by digest, packages from snapshot.debian.org at the versions in
`container/packages.lock`). `KERNEL_WORK`, `KERNEL_OUT` and `KERNEL_CACHE` move
the work, output and download-cache directories; `./build.sh --help` lists the
rest. `./build.sh shell` opens a shell in the builder.

`scripts/build.sh` is the entry point inside the container; a7s-build runs it in
its own builder.

| Step | What it does |
|---|---|
| `pins` | print the pinned inputs |
| `fetch` | download the tarball, check its sha256, unpack it to `work/linux-<version>`; fetch the driver and apply its patches |
| `apply-patches` | apply `kernel/6.18/series` at fuzz 0 |
| `compile-check` | configure and compile only the A733 driver directories (fast) |
| `build` | configure, build `Image`, the dtb, the modules and the driver, write `KERNEL-ID` |
| `all` | `fetch`, `apply-patches`, `build` |
| `key` | print the identity of this checkout: `<version>-<tarball sha256 12>-<hash 12>`; the hash covers `scripts/`, `kernel/`, `pins/`, `out-of-tree/`, `container/packages.txt` and the build time |

The build time of the kernel is the commit time of this checkout's HEAD; an
ambient `SOURCE_DATE_EPOCH` is ignored, `A7S_KERNEL_SOURCE_DATE_EPOCH` sets it.
Two builds of the same commit give the same `Image`, dtb and modules. The
developer switches (`A7S_KERNEL_SERIES`, `A7S_KERNEL_PATCHES`,
`A7S_KERNEL_CONFIG`, `A7S_SKIP_PATCHES`, `A7S_LOCALVERSION`) mark `KERNEL-ID`
as a variant.

## The series

[docs/kernel.md](docs/kernel.md) describes `kernel/6.18/`: where the patches
come from, how to change the series and what is not carried.
[out-of-tree/aic8800/README.md](out-of-tree/aic8800/README.md) describes the
driver and its patches. The driver's firmware is not part of this recipe.

## Who wrote this

One human and AI coding agents (Claude). The code was written by the agents:
the patches, the build scripts and the documentation. Every patch of our own
carries `Assisted-by: Claude`. The decisions were the human's:

- to follow the 6.18 LTS line and take stable releases as separate commits,
  rather than move to a newer kernel;
- to keep this recipe separate from the boot chain and the image recipe, with
  no copies between them;
- to keep vendor firmware out of the recipe: the WLAN firmware is not part of
  it, and nothing that may not be redistributed is committed here;
- what counts as proven: a statement about the hardware is made only after it
  was measured on a board, and a stable release is taken over only after a
  board has booted it.

## Licence

Our own files are `GPL-2.0-only OR MIT`. The patches and the config are
`GPL-2.0-only` like the kernel; third-party patches keep their authorship.
The repository as a whole can be shared under GPL-2.0 ([LICENSE](LICENSE)).
Full texts in [LICENSES/](LICENSES/), assignments in [REUSE.toml](REUSE.toml);
`reuse lint` checks them.
