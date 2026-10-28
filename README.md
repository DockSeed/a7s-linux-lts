# a7s-linux-lts

Linux 6.18 LTS for the **Radxa Cubie A7S** (Allwinner A733): the mainline stable
tarball plus a series of patches for the A733 and the board, cross compiled for
arm64, and the AIC8800 WLAN/BT driver built against it.

**You can build it yourself**: the kernel tarball is downloaded from
cdn.kernel.org and checked against a sha256 committed here; the driver source
is fetched at a pinned commit. Nothing in this repository is a binary. A tagged
version is also built by GitHub Actions and attached to a release, see
[Releases](#releases).

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
- `release/` after `./build.sh package`: the files of a release (see
  [Releases](#releases))

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
| `deb` | after `build`, with `A7S_KERNEL_REVISION=r<n>` (or `t<n>`): `linux-image` and `linux-headers` as Debian packages in `out/deb/` |
| `package` | after `build` and `deb`: the release files in `out/release/` (see [Releases](#releases)) |
| `key` | print the identity of this checkout: `<version>-<tarball sha256 12>-<hash 12>`; the hash covers `scripts/`, `kernel/`, `pins/`, `out-of-tree/`, `container/packages.txt` and the build time |

The build time of the kernel is the commit time of this checkout's HEAD; an
ambient `SOURCE_DATE_EPOCH` is ignored, `A7S_KERNEL_SOURCE_DATE_EPOCH` sets it.
Two builds of the same commit give the same `Image`, dtb and modules. The
developer switches (`A7S_KERNEL_SERIES`, `A7S_KERNEL_PATCHES`,
`A7S_KERNEL_CONFIG`, `A7S_SKIP_PATCHES`, `A7S_LOCALVERSION`) mark `KERNEL-ID`
as a variant.

## Releases

A release is named `v<kernel version>-R<n>` (`v6.18.59-R1`); a test build is
`v<kernel version>-T<n>` (`v6.18.59-T1`). Both are built by GitHub Actions
([release.yml](.github/workflows/release.yml)) from the tagged commit with
`./build.sh all`, `deb` and `package`, in the same pinned builder container, on a
GitHub-hosted x86_64 runner. The text of a release is its section in
[CHANGELOG.md](CHANGELOG.md) (required for every tag). Both create a draft
release that the maintainer publishes by hand; a test tag's draft is marked as
a pre-release. Builds are made when the maintainer tags one; no schedule is
promised. A pull request is only checked for applying the series and compiling
the A733 directories ([compile-check.yml](.github/workflows/compile-check.yml)).

The tag gives the kernel a revision: `v6.18.59-R1` builds the kernel release
`6.18.59-r1` (`A7S_KERNEL_REVISION=r1`), `v6.18.59-T1` builds `6.18.59-t1`.
Local builds without a revision are the same kernel, named `6.18.59`.

Attached to a release:

| File | What it is |
|---|---|
| `linux-image-<release>_<version>_arm64.deb` | `/boot/vmlinuz-<release>` (the raw `Image`), `config-`, `System.map-`, the modules in `/lib/modules/<release>`, the device trees in `/usr/lib/linux-image-<release>/allwinner/` |
| `linux-headers-<release>_<version>_arm64.deb` | `/usr/src/linux-headers-<release>` with `Module.symvers` and the scripts built for arm64, `/lib/modules/<release>/build` pointing to it; for DKMS and `make -C /lib/modules/<release>/build M=...` on the board |
| `Image`, `sun60i-a733-cubie-a7s.dtb`, `config`, `System.map` | as `./build.sh` leaves them in `out/` |
| `a7s-linux-lts-<release>-modules.tar.xz` | the kernel's modules, `lib/modules/<release>/`, `depmod` run over the set |
| `KERNEL-ID` | the build identity, with the sha256 of the four files above, and the line `release_modules=without_aic8800` |
| `linux-<version>.tar.xz` | the unchanged kernel tarball from cdn.kernel.org |
| `SHA256SUMS` | the sha256 of every file above |

The WLAN/BT driver is not part of the releases (the image recipe builds it).
The packages are named for the release, so a newer one installs beside an older
one and the older kernel stays bootable; `apt install ./linux-image-<release>_*.deb
./linux-headers-<release>_*.deb` installs a pair, and the boot menu entry is the
job of the tool that manages `/boot/extlinux` (u-boot-menu finds the device tree
under `/usr/lib/linux-image-<release>/` and takes `allwinner/<dtb>` from its
`U_BOOT_FDT` setting). Versions: `R<n>` is `<kernel version>-<n>`, `T<n>` is
`<kernel version>~t<n>-1`, which sorts before the release of the same kernel
version. Nothing here promises further releases.

The kernel tarball and the source archive of the tag, which GitHub adds to every
release (patches, config, scripts), are the corresponding source of the kernel
(GPL-2.0).

To check a release: `sha256sum -c SHA256SUMS`; build the tagged commit with
`A7S_KERNEL_REVISION=r1 ./build.sh all`, `deb`, `package` and compare. Two builds
of the same commit and revision give the same files, packages included (the build
time is the commit time); `KERNEL-ID` has the sha256 of `Image`, dtb, `config`
and `System.map`. The module tarball differs from a local `out/modules/` only by
the driver, the `depmod` indexes and the `build`/`source` links. `./build.sh
package` fails if a module declares a licence that is not GPL-compatible or if a
package is not what the build made.

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
