# SPDX-License-Identifier: GPL-2.0-only OR MIT
# SPDX-FileCopyrightText: the a7s-linux-lts contributors
# shellcheck shell=bash
#
# The a7s-kernel-hook package: hooks for /etc/kernel that keep
# /boot/extlinux/extlinux.conf and extlinux-fallback.conf in step with the
# kernel packages (no boot loader tool
# knows this board's device tree). Sourced by scripts/build.sh after
# scripts/lib/deb.sh; step "hook", also run at the end of step "deb".
#
#   /usr/share/kernel/postinst.d/zz-a7s-extlinux
#                                            a newly installed a7s kernel becomes
#                                            the default; the kernel that booted
#                                            well becomes the safe-mode fallback
#   /usr/share/kernel/prerm.d/a7s-extlinux   the default and the fallback kernel
#                                            cannot be removed
#   /etc/kernel/header_postinst.d/zz-a7s-extlinux, header_prerm.d/a7s-extlinux
#                                            wrappers for the headers package,
#                                            which knows /etc/kernel only: finish
#                                            a start entry that waited for the
#                                            DKMS driver, and keep the headers
#                                            of such a kernel
#
# The kernel package runs /etc/kernel and /usr/share/kernel (sorted together by
# name, so after DKMS), so the hooks go away with this package; only the two
# wrappers are conffiles.
#
# The files are in packaging/a7s-kernel-hook/. The package is architecture
# independent and has the version of the kernel packages of the same release
# (see deb_version in scripts/lib/deb.sh), so the three files of a release
# carry one version and a newer release upgrades the hook with the kernel.
# Needs A7S_KERNEL_REVISION (r<n> release, t<n> test) for that version; it does
# not need a built kernel. Output: OUT_DIR/deb/a7s-kernel-hook_<version>_all.deb.
# /usr/sbin/a7s-kernel-update downloads and installs a release (see the script). Reproducible: owners are root, modes are set here, mtimes are the build time.

HOOK_PACKAGE="a7s-kernel-hook"
HOOK_MAINTAINER="DockSeed <dockseed@proton.me>"

hook_source_dir() { printf '%s' "${ROOT_DIR}/packaging/${HOOK_PACKAGE}"; }

# The package file name for the revision in A7S_KERNEL_REVISION.
hook_deb_name() { printf '%s_%s_all.deb' "${HOOK_PACKAGE}" "$(deb_version)"; }

stage_hook() {
  kernel_revision_check
  [ -n "${A7S_KERNEL_REVISION:-}" ] || die "hook: set A7S_KERNEL_REVISION (r<n> or t<n>)"
  command -v dpkg-deb >/dev/null || die "hook: dpkg-deb is missing"
  local src t f dest ver
  src="$(hook_source_dir)"
  ver="$(deb_version)"
  dest="$(deb_dir)"
  t="$(mktemp -d "${WORK_DIR}/tmp/hook.XXXXXX")"
  chmod 0755 "${t}"
  mkdir -p "${dest}"
  rm -f "${dest}/${HOOK_PACKAGE}"_*_all.deb

  while IFS= read -r f; do
    install -D -m0755 "${src}/${f}" "${t}/${f}"
  done < <(cd "${src}" && find etc usr -type f | LC_ALL=C sort)
  for f in usr/share/kernel/postinst.d/zz-a7s-extlinux usr/share/kernel/prerm.d/a7s-extlinux \
           etc/kernel/header_postinst.d/zz-a7s-extlinux etc/kernel/header_prerm.d/a7s-extlinux \
           usr/sbin/a7s-kernel-update; do
    [ -x "${t}/${f}" ] || die "hook: ${src} lacks ${f}"
  done
  for f in "${t}"/etc/kernel/*/* "${t}"/usr/share/kernel/*/* "${t}"/usr/sbin/*; do sh -n "${f}" || die "hook: ${f##*/} has a syntax error"; done

  install -d -m0755 "${t}/DEBIAN"
  ( cd "${t}" && find etc -type f | LC_ALL=C sort | sed 's|^|/|' ) > "${t}/DEBIAN/conffiles"
  chmod 0644 "${t}/DEBIAN/conffiles"
  cat > "${t}/DEBIAN/control" <<CONTROL
Package: ${HOOK_PACKAGE}
Version: ${ver}
Architecture: all
Maintainer: ${HOOK_MAINTAINER}
Section: kernel
Priority: optional
Depends: coreutils (>= 8.24), grep, awk, curl, apt
Description: extlinux entries and kernel updates for the A7S
 The command a7s-kernel-update installs the newest kernel release of
 a7s-linux-lts. Hooks for /usr/share/kernel make a newly installed a7s kernel the
 one that /boot/extlinux/extlinux.conf boots, keep the kernel that booted well
 as the safe-mode entry of extlinux-fallback.conf, and refuse to remove a
 kernel that either file boots. Nothing changes for kernels of other origin, in
 a chroot, when this boot has not been confirmed as successful, or when the new kernel
 would have no WLAN driver.
CONTROL
  find "${t}" -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +
  dpkg-deb --root-owner-group -Zxz -b "${t}" "${dest}/$(hook_deb_name)" >/dev/null \
    || die "hook: dpkg-deb failed"
  rm -rf "${t}"
  log "hook: $(hook_deb_name) -> ${dest}"
}
