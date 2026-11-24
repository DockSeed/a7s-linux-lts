# SPDX-License-Identifier: GPL-2.0-only OR MIT
# SPDX-FileCopyrightText: the a7s-linux-lts contributors
# shellcheck shell=bash
#
# The AIC8800 driver as a DKMS source package, a7s-aic8800-dkms. Sourced by
# scripts/build.sh after scripts/lib/aic8800.sh and deb.sh; part of step "deb"
# (after fetch, needs A7S_KERNEL_REVISION).
#
# The source is the pinned commit, prepared by aic8800_prepare_tree (Radxa's
# package as shipped, then patches/upstream/ and patches/). The firmware is not
# in the package; it links /usr/lib/firmware/aic8800_fw/USB/aic8800D80, where
# the driver opens it, to /usr/lib/firmware/aic8800D80, where the image puts it.
# The version is the one of the kernel packages of the release.
# Output: OUT_DIR/deb/a7s-aic8800-dkms_<version>_all.deb.

DKMS_PACKAGE="a7s-aic8800-dkms"
DKMS_MODULE="aic8800"

dkms_deb_name() { printf '%s_%s_all.deb' "${DKMS_PACKAGE}" "$(deb_version)"; }

stage_dkms() {
  kernel_revision_check
  [ -n "${A7S_KERNEL_REVISION:-}" ] || die "dkms: set A7S_KERNEL_REVISION (r<n> or t<n>)"
  command -v dpkg-deb >/dev/null || die "dkms: dpkg-deb is missing"
  local src="${WORK_DIR}/aic8800" pdir="${ROOT_DIR}/out-of-tree/aic8800/patches"
  local t pkg usr doc v m="${DKMS_MODULE}"
  [ "$(git -C "${src}" rev-parse HEAD 2>/dev/null)" = "${AIC8800_COMMIT}" ] \
    || die "dkms: ${src} is not at ${AIC8800_COMMIT} -- run fetch first"
  v="$(deb_version)"

  # A clean copy: the build compiles in ${src}.
  t="$(mktemp -d "${WORK_DIR}/tmp/dkms.XXXXXX")"
  mkdir -p "${t}/tree"
  git -C "${src}" archive "${AIC8800_COMMIT}" | tar -x -C "${t}/tree" || die "dkms: export of ${AIC8800_COMMIT} failed"
  ( aic8800_prepare_tree "${t}/tree" "${pdir}" ) || die "dkms: preparing the source failed"

  pkg="${t}/pkg"; usr="${pkg}/usr/src/${m}-${v}"; doc="${pkg}/usr/share/doc/${DKMS_PACKAGE}"
  mkdir -p "${usr}" "${doc}" "${pkg}/DEBIAN" "${pkg}/usr/lib/firmware/aic8800_fw/USB"
  cp -a "${t}/tree/${AIC8800_SUBDIR}/." "${usr}/"
  # The package carries the source the modules of this build came from.
  local f n=0
  while IFS= read -r -d '' f; do
    cmp -s "${usr}/${f}" "${src}/${AIC8800_SUBDIR}/${f}" \
      || die "dkms: ${f} differs from the source the modules were built from"
    n=$((n + 1))
  done < <(cd "${usr}" && find . -type f -print0)
  [ "${n}" -gt 0 ] || die "dkms: no source files"
  ln -s ../../aic8800D80 "${pkg}/usr/lib/firmware/aic8800_fw/USB/aic8800D80"
  cat > "${usr}/dkms.conf" <<EOF
PACKAGE_NAME="${m}"
PACKAGE_VERSION="${v}"
AUTOINSTALL="yes"
BUILT_MODULE_NAME[0]="aic_load_fw"
BUILT_MODULE_LOCATION[0]="aic_load_fw/"
DEST_MODULE_LOCATION[0]="/updates/dkms"
BUILT_MODULE_NAME[1]="aic8800_fdrv"
BUILT_MODULE_LOCATION[1]="aic8800_fdrv/"
DEST_MODULE_LOCATION[1]="/updates/dkms"
EOF
  cat > "${doc}/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: aic8800
Source: ${AIC8800_URL%.git} ${AIC8800_TAG} (${AIC8800_COMMIT}),
 ${AIC8800_SUBDIR}, with the patches of a7s-linux-lts out-of-tree/aic8800/.
Comment: The firmware is not part of this package.

Files: *
Copyright: AICSemi; RivieraWaves; Radxa Computer Co., Ltd
License: GPL-2
Comment: Radxa's debian/copyright states GPL-2 for src/; both modules
 declare MODULE_LICENSE("GPL").

Files: aic8800_fdrv/rwnx_radar.c
 aic8800_fdrv/rwnx_radar.h
Copyright: 2012 Neratec Solutions AG
 2012-2019 RivieraWaves
License: ISC
Comment: rwnx_radar.c states that it is copied and adapted from the ath driver
 of the Linux kernel (drivers/net/wireless/ath/dfs_pri_detector.c, ISC);
 struct pri_sequence in rwnx_radar.h has the members and the comment of the
 one in dfs_pri_detector.h. The files themselves carry no licence notice;
 RivieraWaves' changes fall under the GPL-2 of the package.

Files: aic8800_fdrv/aic_br_ext.*
Copyright: 2019-2021 Aicsemi Corporation
License: Apache-2.0
Comment: Not built (CONFIG_BR_SUPPORT = n).

License: GPL-2
 On Debian systems, see /usr/share/common-licenses/GPL-2.

License: Apache-2.0
 On Debian systems, see /usr/share/common-licenses/Apache-2.0.

License: ISC
 Permission to use, copy, modify, and/or distribute this software for any
 purpose with or without fee is hereby granted, provided that the above
 copyright notice and this permission notice appear in all copies.
 .
 THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
EOF
  {
    echo "Source:  ${AIC8800_URL} ${AIC8800_TAG} (${AIC8800_COMMIT}), ${AIC8800_SUBDIR}"
    echo "Prepared as Radxa ships it, then the patches of a7s-linux-lts"
    echo "out-of-tree/aic8800/ (upstream/series, then series)."
  } > "${doc}/README"
  cat > "${pkg}/DEBIAN/control" <<EOF
Package: ${DKMS_PACKAGE}
Version: ${v}
Architecture: all
Maintainer: ${HOOK_MAINTAINER}
Section: kernel
Priority: optional
Depends: dkms (>= 3.0), gcc, make
Description: AIC8800D80 WLAN/BT driver source for DKMS
 The driver of the WLAN/BT part of the Radxa Cubie A7S, built by DKMS for
 each installed kernel that has its headers package.
EOF
  # dpkg cannot put the link where a directory is.
  cat > "${pkg}/DEBIAN/preinst" <<'EOF'
#!/bin/sh
set -e
d=/usr/lib/firmware/aic8800_fw/USB/aic8800D80
if [ -d "$d" ] && [ ! -L "$d" ]; then
  echo "a7s-aic8800-dkms: $d is a directory; move its files to /usr/lib/firmware/aic8800D80 and remove it" >&2
  exit 1
fi
exit 0
EOF
  cat > "${pkg}/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
if [ "\$1" = configure ]; then
  [ -d /var/lib/dkms/${m}/${v} ] || dkms add -m ${m} -v ${v}
  for b in /lib/modules/*/build; do
    [ -d "\$b/include" ] || continue
    k="\${b%/build}"; k="\${k##*/}"
    dkms autoinstall -k "\$k"
  done
fi
exit 0
EOF
  cat > "${pkg}/DEBIAN/prerm" <<EOF
#!/bin/sh
set -e
if [ "\$1" = remove ] || [ "\$1" = upgrade ] || [ "\$1" = deconfigure ]; then
  dkms remove -m ${m} -v ${v} --all || true
fi
exit 0
EOF
  chmod 0755 "${pkg}/DEBIAN/preinst" "${pkg}/DEBIAN/postinst" "${pkg}/DEBIAN/prerm"
  find "${pkg}" -type d -exec chmod 0755 {} +
  find "${pkg}/usr" -type f -exec chmod 0644 {} +
  find "${pkg}" -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +
  mkdir -p "$(deb_dir)"
  dpkg-deb --root-owner-group -Zxz --build "${pkg}" "$(deb_dir)/$(dkms_deb_name)" >/dev/null \
    || die "dkms: building ${DKMS_PACKAGE} failed"
  rm -rf "${t}"
  log "dkms: $(dkms_deb_name) -> $(deb_dir)"
}
