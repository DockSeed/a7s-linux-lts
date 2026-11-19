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
# of radxa-pkg/aic8800 and prepared as Radxa ships it (CRLF_FILES to LF, then
# its debian/patches/series), plus other projects' patches unchanged
# (out-of-tree/aic8800/patches/upstream/) and ours (out-of-tree/aic8800/patches/).
# Nothing from that source is committed here. The firmware is not part of this
# recipe.
#
# Output: OUT_DIR/modules/lib/modules/<release>/updates/aic8800/{aic_load_fw,
# aic8800_fdrv}.ko, beside the kernel's own modules, with depmod run over the set.

# Pinned to a COMMIT, not the tag; the tag is recorded so a reader can find the
# release.
AIC8800_URL="https://github.com/radxa-pkg/aic8800.git"
AIC8800_TAG="5.0+git20260123.5f7be68d-11"
AIC8800_COMMIT="b6e136a9fe30a4babf0dde5ba9d02313e1c99c30"
# The board's part sits on USB behind the on-board hub, so src/USB is the subtree.
AIC8800_SUBDIR="src/USB/driver_fw/drivers/aic8800"
# Modules that must resolve in the finished tree (aic8800_fdrv with its
# dependencies, and the Bluetooth stack the part uses; see out-of-tree/aic8800/README.md).
AIC8800_MODULES="aic8800_fdrv btusb hidp uhid uinput rfcomm bnep"

stage_pins_aic8800() {
  log "aic8800  : ${AIC8800_URL} @ ${AIC8800_COMMIT} (tag ${AIC8800_TAG})"
  log "           $(grep -cEv '^(#|$)' "${ROOT_DIR}/out-of-tree/aic8800/patches/series") patches"
}

# aic8800_upstream_roots <series>: "<entry> <root>" per entry of
# patches/upstream/series; <root> is "." unless a "# root: <dir>" line comes
# before the entry (its paths start below the tree root).
aic8800_upstream_roots() {
  awk '
    /^# root: / { root = substr($0, 9); next }
    /^#/ || /^$/ { next }
    { print $0, (root == "" ? "." : root); root = "" }
  ' "$1"
}

# aic8800_apply_unchanged <patch> <root>: applies another project's patch as
# published, file by file with `patch -p1 --fuzz=0` from <root>. Where the
# target file has CRLF line ends (some vendor files do; quilt accepts that,
# `git apply` does not), the hunk lines get CRLF for that file. Context and
# content stay exact: no fuzz, no whitespace tolerance.
aic8800_apply_unchanged() {
  local patch="$1" root="$2" tmp n t
  tmp="$(mktemp -d)"
  awk -v d="${tmp}" '/^diff / { n++ } n { print > (d "/" n ".diff") }' "${patch}"
  for n in $(ls "${tmp}" | sort -n); do
    t="$(awk '/^\+\+\+ / { p = $2; sub(/\t.*/, "", p); sub(/^b\//, "", p); print p; exit }' "${tmp}/${n}")"
    [ -n "${t}" ] || { rm -rf "${tmp}"; return 1; }
    if [ -f "${root}/${t}" ] && grep -q $'\r$' "${root}/${t}"; then
      awk '
        /^@@/ { h = 1; print; next }
        /^(diff |--- |\+\+\+ |index )/ { h = 0 }
        h && /^[ +-]/ && !/\r$/ { printf "%s\r\n", $0; next }
        { print }
      ' "${tmp}/${n}" > "${tmp}/${n}.crlf" && mv "${tmp}/${n}.crlf" "${tmp}/${n}"
    fi
    patch -d "${root}" -p1 --fuzz=0 -N -s --no-backup-if-mismatch < "${tmp}/${n}" \
      || { rm -rf "${tmp}"; return 1; }
  done
  rm -rf "${tmp}"
}

# aic8800_prepare_tree <tree> <patch-dir>: prepares a checkout of the pinned
# commit (the whole repository, without .git) in place: Radxa's package as
# shipped, then <patch-dir>/upstream/series, then <patch-dir>/series. Used by
# fetch below and by the image recipe a7s-build, which packages the same tree
# for DKMS; both get the same source this way. Needs log, die and series_load.
aic8800_prepare_tree() {
  local tree="$1" pdir="$2" up="$2/upstream" p e r f n=0
  local -A root=()
  cd "${tree}" || die "aic8800: ${tree} does not exist"

  # Radxa's package as shipped: the files its build converts to LF
  # (CRLF_FILES in .github/local/Makefile.local), then its debian/patches/series
  # with `patch -p1 --fuzz=0`, as quilt applies it.
  for f in $(sed -n '/^CRLF_FILES/,/^$/p' .github/local/Makefile.local | grep -o 'src/[^ \\]*'); do
    [ -f "${f}" ] || die "aic8800: CRLF_FILES names ${f}, which does not exist"
    sed -i 's/\r$//' "${f}"
  done
  while read -r p; do
    case "${p}" in ''|'#'*) continue ;; esac
    patch -p1 --fuzz=0 -N -s --no-backup-if-mismatch < "debian/patches/${p}" \
      || die "aic8800: debian/patches/${p} did not apply"
    n=$((n + 1))
  done < debian/patches/series
  [ "${n}" -gt 0 ] || die "aic8800: debian/patches/series is empty"
  log "applied ${n} patches of debian/patches/series"

  # Then the patches of other projects, unchanged (patches/upstream/series),
  # then ours (patches/series) on top. The order matters: each step is made
  # against the tree with the steps before it applied.
  series_load "${up}" \
    || die "aic8800: patches/upstream/series is missing, empty or malformed"
  while read -r e r; do root[${e}]=${r}; done < <(aic8800_upstream_roots "${up}/series")
  for p in "${SERIES[@]}"; do
    r="${root[${p}]:-.}"
    case "/${r}/" in //*|*/../*) die "aic8800: upstream/${p}: root '${r}' is not inside the tree" ;; esac
    [ -d "${r}" ] || die "aic8800: upstream/${p}: root '${r}' does not exist"
    aic8800_apply_unchanged "${up}/${p}" "${r}" || die "aic8800: upstream/${p} did not apply"
    log "applied upstream/${p}"
  done

  # `git apply` is exact on context, so the order is not cosmetic. Inside a
  # repository it skips, without a word, paths outside the current directory;
  # the ceiling keeps it from finding a repository above the tree.
  series_load "${pdir}" \
    || die "aic8800: patches/series is missing, empty or malformed"
  for p in "${SERIES[@]}"; do
    GIT_CEILING_DIRECTORIES="${tree%/*}" git apply --whitespace=nowarn "${pdir}/${p}" \
      || die "aic8800: ${p} did not apply"
    log "applied ${p}"
  done
}

stage_fetch_aic8800() {
  mkdir -p "${WORK_DIR}"
  local dir="${WORK_DIR}/aic8800"
  git_fetch_pinned "${AIC8800_URL}" "${AIC8800_COMMIT}" "${dir}"
  log "aic8800 at ${AIC8800_COMMIT} (tag ${AIC8800_TAG}, verified)"
  aic8800_prepare_tree "${dir}" "${ROOT_DIR}/out-of-tree/aic8800/patches"
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
