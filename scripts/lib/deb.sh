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
  cp "${img}" "${dest}/"
  deb_add_header_scripts "${hdr}" "${dest}/${hdr##*/}" "${rel}"
  log "deb: packages -> ${dest}"
  ls -l "${dest}" | sed 's/^/        /'
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
  dpkg-deb --root-owner-group -Zxz -b "${t}" "${out}" >/dev/null
  rm -rf "${t}"
}
