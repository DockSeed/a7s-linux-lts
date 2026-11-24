# SPDX-License-Identifier: GPL-2.0-only OR MIT
# SPDX-FileCopyrightText: the a7s-linux-lts contributors
# shellcheck shell=bash
#
# The kernel as Debian packages, made with the kernel's own `make bindeb-pkg`
# from the tree that `build` configured and compiled. Sourced by
# scripts/build.sh after scripts/lib/kernel.sh; step "deb".
#
# Needs A7S_KERNEL_REVISION (r<n> release, t<n> test): it is in the kernel
# release, and with it in the package names.
#
#   linux-image-<release>    /boot/vmlinuz-<release> (the uncompressed Image),
#                            /boot/config-, /boot/System.map-, the modules in
#                            /lib/modules/<release>, the device trees in
#                            /usr/lib/linux-image-<release>/allwinner/
#   linux-headers-<release>  /usr/src/linux-headers-<release> with Module.symvers
#                            and the scripts built for arm64, so that DKMS and
#                            `make -C /lib/modules/<release>/build M=...` work on
#                            the board; /lib/modules/<release>/build points to it
#
# <release> is <kernel version>-r<n> or -t<n>, so a newer release installs
# beside an older one instead of replacing it. Versions: r<n> is
# <kernel version>-<n>; t<n> is <kernel version>~t<n>-1, which sorts before the
# release of the same kernel version. linux-libc-dev is built by the kernel's
# rules and the -dbg package is skipped (profile); neither is kept.
# The AIC8800 driver is in neither package.
#
# The packages a7s-kernel-hook (scripts/lib/hook.sh) and a7s-aic8800-dkms
# (scripts/lib/dkms.sh) are made after these two.
#
# Both packages get a machine-readable copyright file (deb_copyright_text).
#
# The kernel's headers package has no maintainer scripts. Ours gets a postinst
# and a prerm that run /etc/kernel/header_postinst.d and header_prerm.d, as
# Debian's headers packages do, which is what makes DKMS build its modules when
# the headers arrive after the DKMS package.

deb_version() {
  case "${A7S_KERNEL_REVISION:-}" in
    r[0-9]*) printf '%s-%s' "${KERNEL_VERSION}" "${A7S_KERNEL_REVISION#r}" ;;
    t[0-9]*) printf '%s~%s-1' "${KERNEL_VERSION}" "${A7S_KERNEL_REVISION}" ;;
    *) die "deb: A7S_KERNEL_REVISION (r<n> or t<n>) is required" ;;
  esac
}

# Where the finished packages go.
deb_dir() { printf '%s' "${OUT_DIR}/deb"; }

stage_deb() {
  kernel_revision_check
  [ -n "${A7S_KERNEL_REVISION:-}" ] || die "deb: set A7S_KERNEL_REVISION (r<n> or t<n>)"
  local tree rel ver dest
  tree="$(kernel_tree)"
  [ -f "${tree}/include/config/kernel.release" ] || die "deb: the kernel is not built -- run build first"
  rel="$(cat "${tree}/include/config/kernel.release")"
  [ "${rel}" = "${KERNEL_VERSION}-${A7S_KERNEL_REVISION}" ] \
    || die "deb: the built kernel is ${rel}, not ${KERNEL_VERSION}-${A7S_KERNEL_REVISION} -- build with the same revision"
  ver="$(deb_version)"
  dest="$(deb_dir)"
  rm -rf "${dest}"
  mkdir -p "${dest}"
  # bindeb-pkg leaves its packages in the directory above the tree.
  rm -f "${WORK_DIR}"/linux-*.deb "${WORK_DIR}"/linux-a7s_*

  # The changelog of the package carries `date -R`, which would put the clock
  # into the package. A `date` that answers -R with the build time.
  local shim; shim="$(mktemp -d "${WORK_DIR}/tmp/shim.XXXXXX")"
  cat > "${shim}/date" <<SHIM
#!/bin/sh
if [ "\$*" = "-R" ]; then exec /bin/date -R -u -d "@${SOURCE_DATE_EPOCH}"; fi
exec /bin/date "\$@"
SHIM
  chmod +x "${shim}/date"

  cd "${tree}"
  # KBUILD_IMAGE: the raw Image as vmlinuz (U-Boot's extlinux boots it as the
  # image does today), not Image.gz. The profile leaves out the debug package.
  PATH="${shim}:${PATH}" \
  DEBFULLNAME="DockSeed" DEBEMAIL="dockseed@proton.me" \
  DEB_BUILD_OPTIONS="parallel=${A7S_JOBS}" \
    _kmake -j"${A7S_JOBS}" bindeb-pkg \
      KBUILD_IMAGE=arch/arm64/boot/Image \
      KDEB_SOURCENAME=linux-a7s KDEB_PKGVERSION="${ver}" \
      KDEB_CHANGELOG_DIST=trixie KDEB_COMPRESS=xz \
      DPKG_FLAGS="-d -Ppkg.linux-a7s.nokerneldbg" \
    || die "deb: make bindeb-pkg failed"
  rm -rf "${shim}"

  local img="${WORK_DIR}/linux-image-${rel}_${ver}_arm64.deb"
  local hdr="${WORK_DIR}/linux-headers-${rel}_${ver}_arm64.deb"
  [ -f "${img}" ] && [ -f "${hdr}" ] || die "deb: bindeb-pkg did not produce ${img##*/} and ${hdr##*/}"
  deb_set_copyright "${img}" "${dest}/${img##*/}"
  deb_add_header_scripts "${hdr}" "${dest}/${hdr##*/}" "${rel}"
  stage_hook
  stage_dkms
  log "deb: packages -> ${dest}"
  ls -l "${dest}" | sed 's/^/        /'
}

# The copyright file that make bindeb-pkg puts into the packages is the generic
# text of scripts/package/debian/copyright ("The sources may be found at most
# Linux archive sites"). Debian's own linux package has one machine-readable
# file; this is the same form, with the source these packages were built from.
deb_copyright_text() {
  local tag
  tag="v${KERNEL_VERSION}-$(printf '%s' "${A7S_KERNEL_REVISION}" | tr rt RT)"
  cat <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Linux kernel
Source: https://www.kernel.org/pub/linux/kernel/
Comment:
 The kernel is linux-${KERNEL_VERSION}.tar.xz from kernel.org with the patch
 series of a7s-linux-lts applied and the configuration of that repository. The
 corresponding source is the kernel tarball and the source archive of the tag
 ${tag} of https://github.com/DockSeed/a7s-linux-lts (kernel/6.18/patches,
 kernel/6.18/series, kernel/6.18/config), built with ./build.sh all and
 ./build.sh deb as its README describes.
 .
 The kernel files carry SPDX-License-Identifier lines; a few are under other
 licences (dual-licensed or permissive), see LICENSES/ in the kernel source.

Files: *
Copyright: 1991-2026 Linus Torvalds and many others
 2026 the a7s-linux-lts contributors and the authors named in the patches
License: GPL-2

License: GPL-2
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; version 2 of the License.
 .
 On Debian systems, the complete text of the GNU General Public License
 version 2 can be found in /usr/share/common-licenses/GPL-2.
COPYRIGHT
}

# Replace the copyright file of an unpacked package directory <dir> (the one
# file under usr/share/doc/<package>/) and its line in DEBIAN/md5sums.
deb_write_copyright() {  # <dir>
  local t="$1" f rel sum
  f="$(find "${t}/usr/share/doc" -mindepth 2 -maxdepth 2 -name copyright)"
  [ -n "${f}" ] && [ "$(printf '%s\n' "${f}" | wc -l)" -eq 1 ] \
    || die "deb: expected one copyright file in ${t}"
  deb_copyright_text > "${f}"
  touch -h -d "@${SOURCE_DATE_EPOCH}" "${f}"
  rel="${f#"${t}"/}"
  sum="$(md5sum < "${f}" | cut -d' ' -f1)"
  grep -q " ${rel}\$" "${t}/DEBIAN/md5sums" || die "deb: ${rel} is not in md5sums"
  sed -i "s|^[0-9a-f]\{32\}  ${rel}\$|${sum}  ${rel}|" "${t}/DEBIAN/md5sums"
}

# Copy a package with its copyright file replaced.
deb_set_copyright() {  # <in.deb> <out.deb>
  local t
  t="$(mktemp -d "${WORK_DIR}/tmp/cpr.XXXXXX")"
  dpkg-deb -R "$1" "${t}"
  deb_write_copyright "${t}"
  dpkg-deb --root-owner-group -Zxz -b "${t}" "$2" >/dev/null
  rm -rf "${t}"
}

# Copy the headers package with a postinst and a prerm added.
deb_add_header_scripts() {  # <in.deb> <out.deb> <release>
  local in="$1" out="$2" rel="$3" t f
  t="$(mktemp -d "${WORK_DIR}/tmp/hdr.XXXXXX")"
  dpkg-deb -R "${in}" "${t}"
  for f in postinst prerm; do
    [ ! -e "${t}/DEBIAN/${f}" ] || die "deb: the headers package has a ${f} already"
  done
  cat > "${t}/DEBIAN/postinst" <<HOOK
#!/bin/sh
set -e
# DKMS and other users of the headers (run-parts of /etc/kernel/header_postinst.d)
if [ "\$1" = configure ] && [ -d /etc/kernel/header_postinst.d ]; then
  run-parts --report --exit-on-error --arg=${rel} /etc/kernel/header_postinst.d
fi
exit 0
HOOK
  cat > "${t}/DEBIAN/prerm" <<HOOK
#!/bin/sh
set -e
if [ "\$1" = remove ] && [ -d /etc/kernel/header_prerm.d ]; then
  run-parts --report --exit-on-error --arg=${rel} /etc/kernel/header_prerm.d
fi
exit 0
HOOK
  chmod 755 "${t}/DEBIAN/postinst" "${t}/DEBIAN/prerm"
  deb_write_copyright "${t}"
  dpkg-deb --root-owner-group -Zxz -b "${t}" "${out}" >/dev/null
  rm -rf "${t}"
}
