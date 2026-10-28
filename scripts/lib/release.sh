# SPDX-License-Identifier: GPL-2.0-only OR MIT
# SPDX-FileCopyrightText: the a7s-linux-lts contributors
# shellcheck shell=bash
#
# The release files: what a published release of this recipe carries, made from
# a finished build (steps build and deb). Sourced by scripts/build.sh after
# scripts/lib/kernel.sh and scripts/lib/deb.sh; step "package".
#
# Input:  OUT_DIR as the build leaves it (with OUT_DIR/deb from the deb step)
#         and the git checkout of the recipe. A7S_KERNEL_REVISION is required.
# Output: OUT_DIR/release/
#   Image, <dtb>, config, System.map, KERNEL-ID   as built
#   linux-image-<release>_<version>_arm64.deb     the kernel and its modules
#   linux-headers-<release>_<version>_arm64.deb   the build environment for modules
#   a7s-linux-lts-<release>-modules.tar.xz        the same modules as a tarball
#   linux-<version>.tar.xz                        the pristine kernel source (sha256 pinned)
#   SHA256SUMS                                    over all of the above
#
# The AIC8800 modules are not part of it: the image recipe builds that driver.
# The module tarball is made without updates/aic8800/ and depmod is run again
# over what is left. Every module in the tarball and in the image package must
# declare a GPL-compatible MODULE_LICENSE, and the packages must be what this
# build made: same Image, config, System.map, device tree and modules.

# MODULE_LICENSE strings that mean "free" (include/linux/module.h).
RELEASE_MODULE_LICENSES="GPL|GPL v2|GPL and additional rights|Dual BSD/GPL|Dual MIT/GPL|Dual MPL/GPL"

# release_license_gate <dir with .ko files below it> -> prints the count
release_license_gate() {
  local root="$1" n=0 ko lic bad=""
  while IFS= read -r -d '' ko; do
    lic="$(modinfo -F license "${ko}" 2>/dev/null | head -n1 || true)"
    if [ -z "${lic}" ] || ! printf '%s\n' "${lic}" | grep -qxE "${RELEASE_MODULE_LICENSES}"; then
      bad+="${ko#"${root}/"}: '${lic}'"$'\n'
    fi
    n=$((n + 1))
  done < <(find "${root}" -name '*.ko' -print0 | LC_ALL=C sort -z)
  [ "${n}" -gt 0 ] || die "package: no module found in ${root}"
  [ -z "${bad}" ] || die "package: modules without a GPL-compatible MODULE_LICENSE:
${bad}"
  printf '%s\n' "${n}"
}

# sha256 and relative path of every module below <dir>, sorted
release_module_list() {
  ( cd "$1" && find . -name '*.ko' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum )
}

stage_package() {
  local id="${OUT_DIR}/KERNEL-ID" f rel dest stage dtb ver n
  kernel_revision_check
  [ -n "${A7S_KERNEL_REVISION:-}" ] || die "package: set A7S_KERNEL_REVISION (r<n> or t<n>)"
  for f in Image config System.map KERNEL-ID; do
    [ -f "${OUT_DIR}/${f}" ] || die "package: ${OUT_DIR}/${f} is missing -- run build first"
  done
  [ -d "${OUT_DIR}/modules/lib/modules" ] || die "package: ${OUT_DIR}/modules is missing -- run build first"
  ! grep -q '^variant=' "${id}" || die "package: this build is a developer variant ($(sed -n 's/^variant=//p' "${id}")), not a release"
  rel="$(sed -n 's/^release=//p' "${id}")"
  dtb="$(sed -n 's/^dtb=//p' "${id}")"
  [ -n "${rel}" ] && [ -n "${dtb}" ] || die "package: KERNEL-ID has no release or dtb line"
  [ -f "${OUT_DIR}/${dtb}" ] || die "package: ${OUT_DIR}/${dtb} is missing"
  [ "${rel}" = "${KERNEL_VERSION}-${A7S_KERNEL_REVISION}" ] \
    || die "package: KERNEL-ID says release ${rel}, expected ${KERNEL_VERSION}-${A7S_KERNEL_REVISION}"
  [ "$(sed -n 's/^revision=//p' "${id}")" = "${A7S_KERNEL_REVISION}" ] \
    || die "package: KERNEL-ID has another revision than ${A7S_KERNEL_REVISION}"
  ver="$(deb_version)"
  local img="linux-image-${rel}_${ver}_arm64.deb" hdr="linux-headers-${rel}_${ver}_arm64.deb"
  for f in "${img}" "${hdr}"; do
    [ -f "$(deb_dir)/${f}" ] || die "package: $(deb_dir)/${f} is missing -- run deb first"
  done

  git -C "${ROOT_DIR}" rev-parse --verify -q HEAD >/dev/null || die "package: ${ROOT_DIR} is not a git checkout"
  [ -z "$(git -C "${ROOT_DIR}" --no-optional-locks status --porcelain)" ] \
    || die "package: the checkout has uncommitted changes; a release is built from a commit"

  dest="${OUT_DIR}/release"
  rm -rf "${dest}"
  mkdir -p "${dest}"
  for f in Image "${dtb}" config System.map KERNEL-ID; do cp "${OUT_DIR}/${f}" "${dest}/"; done
  # KERNEL-ID names the driver commit the build used; say that the modules of
  # this release do not contain it.
  printf 'release_modules=without_aic8800\n' >> "${dest}/KERNEL-ID"

  # The modules without the AIC8800 driver. A staging copy, so that out/modules
  # stays what the build made (the image recipe takes it from there).
  stage="$(mktemp -d "${WORK_DIR}/tmp/package.XXXXXX")"
  mkdir -p "${stage}/tar/lib/modules" "${stage}/img"
  cp -a "${OUT_DIR}/modules/lib/modules/${rel}" "${stage}/tar/lib/modules/${rel}"
  rm -rf "${stage}/tar/lib/modules/${rel}/updates/aic8800"
  rmdir "${stage}/tar/lib/modules/${rel}/updates" 2>/dev/null || true
  # build/ and source/ point into the build tree, which a release does not carry.
  rm -f "${stage}/tar/lib/modules/${rel}/build" "${stage}/tar/lib/modules/${rel}/source"
  depmod -b "${stage}/tar" "${rel}" || die "package: depmod over the module set failed"
  if grep -rqE 'aic8800|aic_load_fw' "${stage}/tar/lib/modules/${rel}" --include='modules.*' 2>/dev/null; then
    die "package: the AIC8800 driver is still in the module index"
  fi
  n="$(release_license_gate "${stage}/tar/lib/modules/${rel}")"
  log "package: ${n} modules in the tarball, all with a GPL-compatible licence"

  # The image package must be this build.
  dpkg-deb -x "$(deb_dir)/${img}" "${stage}/img"
  local d="${stage}/img"
  n="$(release_license_gate "${d}/lib/modules/${rel}")"
  log "package: ${n} modules in ${img}, all with a GPL-compatible licence"
  [ "$(release_module_list "${d}/lib/modules/${rel}")" = "$(release_module_list "${stage}/tar/lib/modules/${rel}")" ] \
    || die "package: the modules of ${img} are not the modules of this build"
  ! find "${d}" -iname '*aic8800*' -o -iname 'aic_load_fw*' | grep -q . || die "package: the AIC8800 driver is in ${img}"
  cmp -s "${d}/boot/vmlinuz-${rel}" "${OUT_DIR}/Image" || die "package: vmlinuz-${rel} in ${img} is not this build's Image"
  cmp -s "${d}/boot/config-${rel}" "${OUT_DIR}/config" || die "package: config-${rel} in ${img} is not this build's config"
  cmp -s "${d}/boot/System.map-${rel}" "${OUT_DIR}/System.map" || die "package: System.map-${rel} in ${img} is not this build's"
  cmp -s "${d}/usr/lib/linux-image-${rel}/${KERNEL_DTB}" "${OUT_DIR}/${dtb}" \
    || die "package: ${KERNEL_DTB} in ${img} is not this build's device tree"

  # The headers package: what DKMS needs, built for arm64.
  local h="${stage}/hdr"
  mkdir -p "${h}"
  dpkg-deb -x "$(deb_dir)/${hdr}" "${h}"
  local hs="${h}/usr/src/linux-headers-${rel}" t
  [ -f "${hs}/Module.symvers" ] && [ -f "${hs}/Makefile" ] && [ -f "${hs}/include/config/auto.conf" ] \
    || die "package: ${hdr} lacks Makefile, include/config/auto.conf or Module.symvers"
  [ "$(readlink "${h}/lib/modules/${rel}/build")" = "/usr/src/linux-headers-${rel}" ] \
    || die "package: ${hdr}: /lib/modules/${rel}/build does not point to /usr/src/linux-headers-${rel}"
  for t in scripts/basic/fixdep scripts/mod/modpost; do
    [ -f "${hs}/${t}" ] || die "package: ${hdr} lacks ${t}"
    aarch64-linux-gnu-readelf -h "${hs}/${t}" | grep -q 'Machine:.*AArch64' \
      || die "package: ${hdr}: ${t} is not an arm64 binary (DKMS would not run on the board)"
  done
  dpkg-deb -e "$(deb_dir)/${hdr}" "${stage}/hdrctl"
  [ -x "${stage}/hdrctl/postinst" ] || die "package: ${hdr} has no postinst"
  for f in "${img}" "${hdr}"; do
    [ "$(dpkg-deb -f "$(deb_dir)/${f}" Version)" = "${ver}" ] || die "package: ${f}: wrong Version"
    [ "$(dpkg-deb -f "$(deb_dir)/${f}" Architecture)" = arm64 ] || die "package: ${f}: wrong Architecture"
    cp "$(deb_dir)/${f}" "${dest}/"
  done

  # Same bytes for the same inputs: sorted names, no owners, the build time as mtime.
  local mods="a7s-linux-lts-${rel}-modules.tar.xz"
  tar --sort=name --owner=0 --group=0 --numeric-owner --format=gnu \
      --mtime="@${SOURCE_DATE_EPOCH}" -C "${stage}/tar" -cf - lib \
    | xz -T1 -9 -c > "${dest}/${mods}"
  rm -rf "${stage}"

  # The corresponding source: the kernel tarball unchanged, so that the release
  # does not depend on cdn.kernel.org staying up. The recipe (patches, config,
  # scripts) is the tag's source archive that GitHub makes for the release.
  fetch_verified "${KERNEL_SHA256}" "${dest}/${KERNEL_TARBALL}" "${KERNEL_URL}"

  ( cd "${dest}" && LC_ALL=C find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort \
      | xargs sha256sum > SHA256SUMS )
  log "release files -> ${dest}"
  ls -l "${dest}" | sed 's/^/        /'
}
