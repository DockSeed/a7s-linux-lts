#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only OR MIT
# SPDX-FileCopyrightText: the a7s-linux-lts contributors
#
# Linux 6.18 LTS for the Radxa Cubie A7S (Allwinner A733): the pinned mainline
# stable tarball plus the patch series in kernel/6.18/, built for arm64 into
# Image, the board's device tree and the modules, with the AIC8800 WLAN/BT
# driver built against that tree.
# Runs inside a container (../build.sh) or in the builder of a7s-build.
#
# Usage: scripts/build.sh <step>
#   pins            print the pinned inputs
#   fetch           download the kernel tarball (sha256 checked) and unpack it;
#                   fetch the AIC8800 driver at its commit and patch it
#   apply-patches   apply the series to the unpacked tree, at fuzz 0
#   compile-check   configure, then compile only the A733 driver directories
#   build           configure, then build Image, the dtb and the modules, then
#                   the AIC8800 modules -> OUT_DIR, with KERNEL-ID
#   all             fetch + apply-patches + build
#   key             print the identity of this checkout's kernel (cache key)
#   deb             after build: the kernel as Debian packages (linux-image,
#                   linux-headers) in OUT_DIR/deb; needs A7S_KERNEL_REVISION
#   package         after build and deb: the release files in OUT_DIR/release
#                   (loose files, modules, the two packages, SHA256SUMS)
#
# Needs an aarch64 cross compiler (none on an aarch64 host), make, patch, bc,
# bison, flex, libssl, libelf, kmod, xz, git and curl (container/packages.txt
# lists them). Nothing in the build is tied to the host architecture.
#
# Environment
#   WORK_DIR, OUT_DIR, CACHE_DIR   scratch, artefacts, verified downloads
#                                  (default: work/, out/, cache/ in this repository)
#   A7S_JOBS                       parallel jobs (default: nproc)
#   A7S_KERNEL_SOURCE_DATE_EPOCH   build time of the kernel; default: the commit
#                                  time of this checkout's HEAD. An ambient
#                                  SOURCE_DATE_EPOCH is ignored on purpose: the
#                                  kernel must not change with the caller.
#   A7S_KERNEL_REVISION            r<n> or t<n>: the release being built (from its
#                                  tag); part of the kernel release and of the key
#   A7S_KERNEL_DTB, A7S_KERNEL_SERIES, A7S_KERNEL_PATCHES, A7S_KERNEL_CONFIG,
#   A7S_SKIP_PATCHES, A7S_LOCALVERSION   developer switches, see scripts/lib/kernel.sh
#   A7S_DOWNLOAD_MIRROR, A7S_FETCH_MAX_TIME   see scripts/lib/common.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=lib/common.sh
. "${ROOT_DIR}/scripts/lib/common.sh"
# shellcheck source=lib/series.sh
. "${ROOT_DIR}/scripts/lib/series.sh"
# shellcheck source=lib/kernel.sh
. "${ROOT_DIR}/scripts/lib/kernel.sh"
# shellcheck source=lib/aic8800.sh
. "${ROOT_DIR}/scripts/lib/aic8800.sh"
# shellcheck source=lib/deb.sh
. "${ROOT_DIR}/scripts/lib/deb.sh"
# shellcheck source=lib/release.sh
. "${ROOT_DIR}/scripts/lib/release.sh"

# Fixed paths, locale and build time, so that equal inputs give equal bytes.
env_setup() {
  export WORK_DIR="${WORK_DIR:-${ROOT_DIR}/work}"
  export OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
  export CACHE_DIR="${CACHE_DIR:-${ROOT_DIR}/cache}"
  mkdir -p "${WORK_DIR}" "${OUT_DIR}" "${CACHE_DIR}" "${WORK_DIR}/tmp"
  # Large temporary files stay in WORK_DIR, not in the container's own storage.
  export TMPDIR="${WORK_DIR}/tmp"

  A7S_JOBS="${A7S_JOBS:-$(nproc)}"
  case "${A7S_JOBS}" in ''|*[!0-9]*) die "A7S_JOBS must be a number, not '${A7S_JOBS}'" ;; esac
  export A7S_JOBS

  SOURCE_DATE_EPOCH="$(kernel_source_date_epoch)" || exit 1
  export SOURCE_DATE_EPOCH

  export LC_ALL=C.UTF-8 TZ=UTC
  umask 022
}

stage_pins() { stage_pins_kernel; stage_pins_aic8800; }
stage_fetch() { stage_fetch_kernel && stage_fetch_aic8800; }

# The kernel with the out-of-tree driver, and what they are.
stage_build() { stage_build_kernel && stage_build_aic8800 && write_kernel_id; }
stage_all() { stage_fetch && stage_apply_patches && stage_build; }

usage() {
  sed -n '/^# Usage/,/^# Needs/p' "$0" | sed 's/^# \{0,1\}//' | sed '$d' >&"${1:-2}"
  exit "${2:-2}"
}

main() {
  local step="${1:-}"
  [ "$#" -eq 0 ] || shift
  case "${step}" in
    pins)          stage_pins ;;
    key)           kernel_key ;;
    fetch)         env_setup; stage_fetch ;;
    apply-patches) env_setup; stage_apply_patches ;;
    compile-check) env_setup; stage_compile_check ;;
    build)         env_setup; stage_build ;;
    all)           env_setup; stage_all ;;
    deb)           env_setup; stage_deb ;;
    package)       env_setup; stage_package ;;
    -h|--help|help) usage 1 0 ;;
    *)             usage ;;
  esac
}

main "$@"
