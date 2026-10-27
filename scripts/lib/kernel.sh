# SPDX-License-Identifier: GPL-2.0-only OR MIT
# SPDX-FileCopyrightText: the a7s-linux-lts contributors
# shellcheck shell=bash
#
# The kernel steps: pins, fetch, apply-patches, compile-check, build, and the
# identity (key, KERNEL-ID). Sourced by scripts/build.sh after scripts/lib/common.sh
# and scripts/lib/series.sh; scripts/lib/aic8800.sh adds the out-of-tree driver.
#
# The kernel is the mainline stable tarball plus the patch series in
# kernel/6.18/ (series, patches/, config), cross compiled for arm64.
# Output: OUT_DIR/{Image,<dtb>,config,System.map,modules/,KERNEL-ID}.

# --- pins -----------------------------------------------------------------------
# Linux stable v6.18.59 (longterm). The sha256 is the one cdn.kernel.org lists
# in its signed sha256sums.asc (checked with the kernel.org autosigner key
# B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1; the tarball's own signature
# linux-6.18.59.tar.sign by Greg Kroah-Hartman, 647F28654894E3BD457199BE38DBBDC86092693E,
# is good over the uncompressed tar). fetch refuses any other bytes.
# A version bump is: the version and sha256 here, and every patch that no
# longer applies at fuzz 0.
KERNEL_VERSION="6.18.59"
KERNEL_TARBALL="linux-${KERNEL_VERSION}.tar.xz"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_VERSION%%.*}.x/${KERNEL_TARBALL}"
KERNEL_SHA256="53a55ac9863a5547e292b8e381d4e4c2240dd1127d5428a7c44dbc550be23963"
KERNEL_ARCH="arm64"
# The boot dtb built and shipped (relative to arch/arm64/boot/dts/).
KERNEL_DTB="${A7S_KERNEL_DTB:-allwinner/sun60i-a733-cubie-a7s.dtb}"
# What the build is read from. The defaults are the repository's own files; the
# variables let a developer point the stage at another series or config without
# editing the tree (the pinned tarball still decides the base).
#   A7S_KERNEL_SERIES   series file         (default: kernel/6.18/series)
#   A7S_KERNEL_PATCHES  patch directory     (default: kernel/6.18/patches)
#   A7S_KERNEL_CONFIG   defconfig file      (default: kernel/6.18/config)
# A build that uses any of these, A7S_SKIP_PATCHES or A7S_LOCALVERSION is a
# variant: KERNEL-ID says so (kernel_variant), and the image recipe refuses it.
kernel_paths() {
  KERNEL_SERIES_FILE="${A7S_KERNEL_SERIES:-${ROOT_DIR}/kernel/6.18/series}"
  KERNEL_PATCH_DIR="${A7S_KERNEL_PATCHES:-${ROOT_DIR}/kernel/6.18/patches}"
  KERNEL_CONFIG_FILE="${A7S_KERNEL_CONFIG:-${ROOT_DIR}/kernel/6.18/config}"
  # A series next to its patches is also fine.
  [ -f "${KERNEL_SERIES_FILE}" ] || KERNEL_SERIES_FILE="${KERNEL_PATCH_DIR}/series"
}

# Print the kernel tree this stage works on.
kernel_tree() { printf '%s' "${WORK_DIR}/linux-${KERNEL_VERSION}"; }

stage_pins_kernel() {
  kernel_paths
  local entries="<unreadable>"
  if series_load "${KERNEL_PATCH_DIR}" "${KERNEL_SERIES_FILE}" 2>/dev/null; then entries="${#SERIES[@]}"; fi
  log "kernel   : v${KERNEL_VERSION}, ${KERNEL_URL}"
  log "           sha256 ${KERNEL_SHA256}"
  log "           ${entries} series entries (${KERNEL_SERIES_FILE#"${ROOT_DIR}/"})"
}

stage_fetch_kernel() {
  mkdir -p "${WORK_DIR}"
  fetch_verified "${KERNEL_SHA256}" "${CACHE_DIR}/downloads/${KERNEL_TARBALL}" "${KERNEL_URL}"
  log "kernel tarball verified (sha256 ${KERNEL_SHA256})"
  rm -rf "$(kernel_tree)"
  tar -xf "${CACHE_DIR}/downloads/${KERNEL_TARBALL}" -C "${WORK_DIR}"
  log "kernel unpacked -> $(kernel_tree)"
}

# One patch, dry run first, at fuzz 0. An "offset" or "fuzz" line in patch's
# output is a failure too: a hunk that moved can land on a repeated context in
# the wrong place (this tree's device tree has many identical OPP blocks), so the
# patch has to be regenerated rather than nudged.
_apply_one() {  # <patch dir> <entry>
  local out
  out="$(patch -p1 --fuzz=0 --no-backup-if-mismatch < "$1/$2" 2>&1)" \
    || die "patch failed to apply at fuzz 0 (context drifted, regenerate it): $2
${out}"
  if grep -Eq 'offset|fuzz' <<<"${out}"; then
    die "patch applied with an offset or fuzz (regenerate it): $2
${out}"
  fi
}

stage_apply_patches() {
  local tree; tree="$(kernel_tree)"
  [ -d "${tree}" ] || die "kernel tree missing -- run build.sh fetch first"
  kernel_paths
  # The order is the series file and nothing else (scripts/lib/series.sh has
  # the format and what it refuses). A missing or empty series is an error,
  # never a "pristine baseline": a stage that applies nothing and returns 0 is
  # how a kernel without its patches goes green.
  series_load "${KERNEL_PATCH_DIR}" "${KERNEL_SERIES_FILE}" \
    || die "${KERNEL_SERIES_FILE} is missing, empty or malformed -- nothing applied"
  cd "${tree}"
  # A7S_SKIP_PATCHES: comma-separated series entries to leave out, to build a
  # variant ("is this workaround still needed?" is answered by a kernel without
  # it). A token is a series path or a basename, with or without `.patch`; every
  # token must name exactly one entry or the stage dies. Announced loudly.
  local skip="${A7S_SKIP_PATCHES:-}"
  declare -gA SERIES_SKIP=()
  if [ -n "${skip}" ]; then
    series_resolve_skip "${skip}" || die "A7S_SKIP_PATCHES='${skip}' does not resolve -- nothing applied"
    log "VARIANT BUILD -- leaving out: ${!SERIES_SKIP[*]}"
  fi
  # Apply with `patch`, not `git apply`: when the tree sits inside another git
  # repository (WORK_DIR in a checkout), `git apply` can report "Skipped" with a
  # success exit code and apply nothing, which builds a kernel without the
  # patches and still goes green. `patch` is index-unaware and fails loudly.
  # --fuzz=0: `patch` defaults to fuzz 2 and places a hunk with up to two lines
  # of context ignored, so a hunk can land in the wrong DT node (a pin group, for
  # example) and the build stays green. At fuzz 0 a drifted context fails the build and the
  # patch has to be regenerated.
  local p applied=0 total="${#SERIES[@]}"
  for p in "${SERIES[@]}"; do
    if [ -n "${SERIES_SKIP[${p}]:-}" ]; then
      log "SKIP  ${p}  (A7S_SKIP_PATCHES)"
      continue
    fi
    _apply_one "${KERNEL_PATCH_DIR}" "${p}"
    applied=$((applied + 1))
  done
  local skipped="${#SERIES_SKIP[@]}"
  log "applied ${applied} of ${total} series entries, skipped ${skipped}"
}

# make for the kernel tree: cross compile unless the host is arm64.
_kmake() {
  local cc=""
  [ "$(uname -m)" = "aarch64" ] || cc="aarch64-linux-gnu-"
  # -ffile-prefix-map maps the build directory to "." in objects and debug
  # info, so the objects do not depend on where the tree is.
  # A7S_LOCALVERSION goes to make, never into .config: a Kconfig string lands
  # in autoconf.h, which every object includes.
  # The build stamp comes from SOURCE_DATE_EPOCH, not from the clock and the
  # container hostname, so two builds of the same inputs match.
  local stamp="${KBUILD_BUILD_TIMESTAMP:-$(date -u -d "@${SOURCE_DATE_EPOCH}" '+%a, %d %b %Y %H:%M:%S +0000')}"
  make ARCH="${KERNEL_ARCH}" CROSS_COMPILE="${cc}" \
    KCFLAGS="-ffile-prefix-map=$(pwd)=. ${KCFLAGS:-}" \
    ${A7S_LOCALVERSION:+LOCALVERSION="${A7S_LOCALVERSION}"} \
    KBUILD_BUILD_TIMESTAMP="${stamp}" \
    KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-root}" \
    KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-a7s-build}" "$@"
}

# Read pins/kernel-config.assert entries of one kind (y, m, file, line).
_kassert() {
  sed -n "s/^$1 //p" "${ROOT_DIR}/pins/kernel-config.assert"
}

_kernel_configure() {
  local tree="$1" c
  kernel_paths
  [ -f "${KERNEL_CONFIG_FILE}" ] || die "kernel config ${KERNEL_CONFIG_FILE} missing"
  cd "${tree}"
  # The base is our own defconfig, not arm64's, so two builds can be diffed.
  # pins/kernel-config.assert holds what the file must still say after
  # olddefconfig; they run below.
  install -m644 "${KERNEL_CONFIG_FILE}" arch/arm64/configs/a7s_defconfig
  _kmake a7s_defconfig
  # Applied on top, and cheap: if the file already carries a symbol these are
  # no-ops, and if an edit dropped one they put it back instead of failing a
  # build hours later on the board.
  while read -r c; do ./scripts/config --enable "${c}"; done < <(_kassert y)
  while read -r c; do ./scripts/config --module "${c}"; done < <(_kassert m)
  if [ -n "${A7S_LOCALVERSION:-}" ]; then
    printf '%s' "${A7S_LOCALVERSION}" | grep -Eqx -- '-[a-z0-9][a-z0-9.]*' \
      || die "A7S_LOCALVERSION '${A7S_LOCALVERSION}' must look like -t1 (lower case, digits, dots)"
    log "local version ${A7S_LOCALVERSION}: kernel release will be ${KERNEL_VERSION}${A7S_LOCALVERSION}"
  fi
  _kmake olddefconfig
  # olddefconfig silently drops a symbol whose dependencies are unmet, so assert.
  while read -r c; do
    grep -qx "CONFIG_${c}=y" .config || die "CONFIG_${c} not enabled after olddefconfig"
  done < <(_kassert y)
  # Exact lines: integers, strings and "is not set", which the =y check cannot see.
  local l
  while IFS= read -r l; do
    grep -qxF -- "${l}" .config || die ".config lacks the line '${l}' (pins/kernel-config.assert)"
  done < <(_kassert line)
  # A module must land as =m. =y means something selects it built in: a real
  # finding, so fail loudly instead of guessing.
  while read -r c; do
    grep -qx "CONFIG_${c}=m" .config || die "CONFIG_${c} not =m after olddefconfig (bool-only, or selected =y -- decide, do not guess)"
  done < <(_kassert m)
}

# Fast compile gate: build only the A733 driver directories against a real
# configured tree. Seconds, not the full build. It does not link modules: an
# unresolved EXPORT_SYMBOL shows up at modpost in build.
stage_compile_check() {
  local tree; tree="$(kernel_tree)"
  [ -d "${tree}" ] || die "kernel tree missing -- run build.sh fetch and apply-patches first"
  _kernel_configure "${tree}"
  local c
  for c in SUN60I_A733_CCU PINCTRL_SUN60I_A733 SUN60I_A733_SERDES_CCU PWM_SUN60I_A733 \
           SENSORS_PWM_FAN DRM_SUN60I_DP DRM_SUN60I_TCON_TV DRM_SUN60I_DE DRM_SUN60I_KMS SUN60I_IOMMU; do
    grep -q "CONFIG_${c}=y" "${tree}/.config" || die "${c} not enabled in .config -- patch/Kconfig wiring broken"
  done
  _kmake -j"${A7S_JOBS}" drivers/clk/sunxi-ng/ drivers/pinctrl/sunxi/ \
    drivers/mmc/host/ drivers/phy/allwinner/ drivers/usb/dwc3/ \
    drivers/pwm/ drivers/hwmon/ drivers/pmdomain/sunxi/ drivers/gpu/drm/sun60i/ \
    drivers/gpu/drm/imagination/ drivers/iommu/ drivers/pci/controller/dwc/ \
    drivers/soc/sunxi/ drivers/firmware/psci/ drivers/cpuidle/ drivers/devfreq/ \
    drivers/dma/sun6i-dma.o sound/soc/sunxi/
  _kmake -j"${A7S_JOBS}" "${KERNEL_DTB}"
  log "compile-check OK"
}

stage_build_kernel() {
  local tree; tree="$(kernel_tree)"
  [ -d "${tree}" ] || die "kernel tree missing -- run build.sh fetch and apply-patches first"
  rm -f "${OUT_DIR}/KERNEL-ID"
  _kernel_configure "${tree}"
  cd "${tree}"
  # The raw Image and the one boot dtb: `dtbs` would compile hundreds of
  # unrelated boards.
  _kmake -j"${A7S_JOBS}" Image "${KERNEL_DTB}"
  local want_release="${KERNEL_VERSION}${A7S_LOCALVERSION:-}"
  [ "$(cat "${tree}/include/config/kernel.release")" = "${want_release}" ] \
    || die "kernel.release is '$(cat "${tree}/include/config/kernel.release")', expected '${want_release}'"
  mkdir -p "${OUT_DIR}"
  cp "${tree}/arch/arm64/boot/Image" "${OUT_DIR}/"
  cp "${tree}/arch/arm64/boot/dts/${KERNEL_DTB}" "${OUT_DIR}/"
  cp "${tree}/.config" "${OUT_DIR}/config"
  cp "${tree}/System.map" "${OUT_DIR}/"
  log "kernel Image + dtb + config + System.map -> ${OUT_DIR}"

  # Modules. Without them everything =m is absent from the image, not "loaded
  # later". INSTALL_MOD_STRIP=1: debug info in a shipped module is dead weight.
  local n_mod
  n_mod="$(grep -c '^CONFIG_.*=m$' "${tree}/.config" || true)"
  if [ "${n_mod}" -gt 0 ]; then
    _kmake -j"${A7S_JOBS}" modules
    rm -rf "${OUT_DIR}/modules"
    _kmake INSTALL_MOD_PATH="${OUT_DIR}/modules" INSTALL_MOD_STRIP=1 modules_install
    local kver moddir
    kver="$(cat "${tree}/include/config/kernel.release")"
    moddir="${OUT_DIR}/modules/lib/modules/${kver}"
    [ -d "${moddir}" ] || die "modules_install produced no ${moddir}"
    # Assert the modules we care about are really on disk rather than trusting
    # an exit code. A Kconfig symbol does not carry its object name, so the file
    # names are listed (pins/kernel-config.assert) and this loop keeps the two
    # lists consistent.
    local f missing=""
    while read -r f; do
      find "${moddir}" -name "${f}" -print -quit | grep -q . || missing="${missing} ${f}"
    done < <(_kassert file)
    [ -z "${missing}" ] || die "declared modules missing from ${moddir}:${missing}"
    log "all declared module files present ($(_kassert file | wc -l))"
    log "modules -> ${moddir} ($(find "${moddir}" -name '*.ko' | wc -l) .ko, $(du -sh "${OUT_DIR}/modules" | cut -f1))"
  else
    log "modules: nothing is =m in this config -- skipping"
  fi
}

# What the kernel in OUT_DIR is, so it can be told from another one. Content
# addressed, with the build time the kernel was made with: the same inputs give
# the same file.
write_kernel_id() {
  local tree; tree="$(kernel_tree)"
  local id="${OUT_DIR}/KERNEL-ID" variant
  variant="$(kernel_variant)"
  {
    echo "key=$(kernel_key)"
    echo "version=${KERNEL_VERSION}"
    echo "release=$(cat "${tree}/include/config/kernel.release")"
    echo "tarball_sha256=${KERNEL_SHA256}"
    echo "source_date_epoch=${SOURCE_DATE_EPOCH}"
    echo "dtb=${KERNEL_DTB##*/}"
    echo "aic8800=${AIC8800_COMMIT}"
    echo "aic8800_tag=${AIC8800_TAG}"
    [ -z "${variant}" ] || echo "variant=${variant}"
    ( cd "${OUT_DIR}" && sha256sum Image "${KERNEL_DTB##*/}" config System.map | sed 's/^\([0-9a-f]*\)  \(.*\)$/sha256_\2=\1/' )
  } > "${id}"
  log "kernel identity:"
  sed 's/^/        /' "${id}"
}

# Developer switches in use, comma separated; empty for the recipe as committed.
kernel_variant() {
  local v="" n
  for n in A7S_KERNEL_SERIES A7S_KERNEL_PATCHES A7S_KERNEL_CONFIG A7S_SKIP_PATCHES A7S_LOCALVERSION; do
    [ -z "${!n:-}" ] || v+="${v:+,}${n}"
  done
  printf '%s' "${v}"
}

# The build time of the kernel: A7S_KERNEL_SOURCE_DATE_EPOCH, else the commit
# time of this checkout's HEAD. An ambient SOURCE_DATE_EPOCH is not used.
kernel_source_date_epoch() {
  local sde="${A7S_KERNEL_SOURCE_DATE_EPOCH:-}"
  if [ -z "${sde}" ]; then
    sde="$(git -C "${ROOT_DIR}" log -1 --format=%ct 2>/dev/null)" || sde=""
  fi
  [ -n "${sde}" ] || die "no build time: ${ROOT_DIR} has no commit -- set A7S_KERNEL_SOURCE_DATE_EPOCH"
  case "${sde}" in *[!0-9]*) die "the build time must be a number, not '${sde}'" ;; esac
  printf '%s\n' "${sde}"
}

# One hash over everything that decides what this recipe builds: every file of
# scripts/, kernel/, pins/ and out-of-tree/, the package list, and the build time
# in use.
# Paths are relative to the repository root, so the hash does not depend on
# where the repository is checked out, and a rename changes it.
kernel_inputs_id() {
  local sde; sde="$(kernel_source_date_epoch)" || exit 1
  { ( cd "${ROOT_DIR}" \
        && find scripts kernel pins out-of-tree container/packages.txt -type f -print0 \
           | LC_ALL=C sort -z | xargs -0 sha256sum ) \
    && printf 'source_date_epoch=%s\n' "${sde}"; } \
    | sha256sum | cut -d' ' -f1
}

# The key of the kernel this checkout builds: version, tarball and inputs, known
# from the checkout (and the build time) alone, with no fetch and no build.
# KERNEL-ID carries it.
kernel_key() {
  local id; id="$(kernel_inputs_id)" || exit 1
  printf '%s-%s-%s\n' "${KERNEL_VERSION}" "${KERNEL_SHA256:0:12}" "${id:0:12}"
}
