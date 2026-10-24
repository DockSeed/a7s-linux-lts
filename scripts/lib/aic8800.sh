# SPDX-License-Identifier: GPL-2.0-only OR MIT
# SPDX-FileCopyrightText: the a7s-linux-lts contributors
# shellcheck shell=bash
#
# The AIC8800D80 WLAN/BT driver, built out of tree against the kernel tree.
# Sourced by scripts/build.sh after scripts/lib/kernel.sh; the steps run as part
# of fetch and build.
#
# The driver is vendor code used as shipped, not imported as kernel patches
# (out-of-tree/aic8800/README.md): about 130 files fetched at the pinned commit
# of radxa-pkg/aic8800, plus the patch series in out-of-tree/aic8800/patches/.
# Nothing from that source is committed here. The firmware is not part of this
# recipe.
#
# Output: OUT_DIR/modules/lib/modules/<release>/updates/aic8800/{aic_load_fw,
# aic8800_fdrv}.ko, beside the kernel's own modules, with depmod run over the set.

# Pinned to a COMMIT, not the tag; the tag is recorded so a reader can find the
# release.
AIC8800_URL="https://github.com/radxa-pkg/aic8800.git"
AIC8800_TAG="5.0+git20260123.5f7be68d-8"
AIC8800_COMMIT="df4c783b663eba1956579c681acd5e45f25c671d"
# The board's part sits on USB behind the on-board hub, so src/USB is the subtree.
AIC8800_SUBDIR="src/USB/driver_fw/drivers/aic8800"
# Modules that must resolve in the finished tree (aic8800_fdrv with its
# dependencies, and the Bluetooth stack the part uses; see out-of-tree/aic8800/README.md).
AIC8800_MODULES="aic8800_fdrv btusb hidp uhid uinput rfcomm bnep"

stage_pins_aic8800() {
  log "aic8800  : ${AIC8800_URL} @ ${AIC8800_COMMIT} (tag ${AIC8800_TAG})"
  log "           $(grep -cEv '^(#|$)' "${ROOT_DIR}/out-of-tree/aic8800/patches/series") patches"
}

stage_fetch_aic8800() {
  mkdir -p "${WORK_DIR}"
  local dir="${WORK_DIR}/aic8800" p
  git_fetch_pinned "${AIC8800_URL}" "${AIC8800_COMMIT}" "${dir}"
  log "aic8800 at ${AIC8800_COMMIT} (tag ${AIC8800_TAG}, verified)"

  # Order: out-of-tree/aic8800/patches/series. `git apply` is exact on context,
  # so the order is not cosmetic.
  series_load "${ROOT_DIR}/out-of-tree/aic8800/patches" \
    || die "aic8800: patches/series is missing, empty or malformed"
  cd "${dir}"
  for p in "${SERIES[@]}"; do
    git apply --whitespace=nowarn "${ROOT_DIR}/out-of-tree/aic8800/patches/${p}" \
      || die "aic8800: ${p} did not apply"
    log "applied ${p}"
  done
}

# Build the two modules against the kernel tree. Needs the kernel build to have
# run: modpost wants that tree's Module.symvers, and without it the .ko still
# links but carries no dependency information, which reads as "no dependencies".
stage_build_aic8800() {
  local tree dir kver mtree dst
  tree="$(kernel_tree)"
  dir="${WORK_DIR}/aic8800/${AIC8800_SUBDIR}"
  [ -d "${tree}" ] || die "kernel tree missing -- run fetch, apply-patches and build first"
  [ -d "${dir}" ]  || die "aic8800 source missing -- run fetch first"
  [ -f "${tree}/Module.symvers" ] \
    || die "no ${tree}/Module.symvers -- build the kernel first (a module built without it has no depends:)"
  kver="$(cat "${tree}/include/config/kernel.release")"
  mtree="${OUT_DIR}/modules"
  [ -d "${mtree}/lib/modules/${kver}" ] \
    || die "no ${mtree}/lib/modules/${kver} -- the kernel build installed no modules"

  cd "${tree}"
  _kmake -j"${A7S_JOBS}" M="${dir}" modules || die "aic8800 module build failed"

  dst="${mtree}/lib/modules/${kver}/updates/aic8800"
  rm -rf "${dst}"
  mkdir -p "${dst}"
  local m
  for m in aic_load_fw/aic_load_fw.ko aic8800_fdrv/aic8800_fdrv.ko; do
    [ -f "${dir}/${m}" ] || die "aic8800: ${m} was not produced"
    cp "${dir}/${m}" "${dst}/"
  done
  depmod -b "${mtree}" "${kver}" || die "depmod over the installed tree failed"

  # Non-empty is not enough: a module that was never built simply drops out
  # while the others keep the list non-empty. Every name has to resolve to its
  # own file.
  local want
  want="$(
    for m in ${AIC8800_MODULES}; do
      modprobe -d "${mtree}" -S "${kver}" --show-depends "${m}" 2>/dev/null \
        | awk '$1=="insmod" {print $2}'
    done | sort -u
  )"
  [ -n "${want}" ] || die "modprobe resolved no dependencies -- depmod or the module names are wrong"
  for m in ${AIC8800_MODULES}; do
    printf '%s\n' "${want}" | grep -q "/${m}\.ko" \
      || die "${m}.ko did not resolve in ${mtree} -- its Kconfig symbol is not =m in this build"
  done
  log "aic8800 modules -> ${dst}"
  ls -l "${dst}" | sed 's/^/        /'
}
