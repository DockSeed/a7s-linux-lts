#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only OR MIT
# SPDX-FileCopyrightText: the a7s-linux-lts contributors
#
# a7s-linux-lts: build Linux 6.18 for the Radxa Cubie A7S in a builder
# container. This is the only script that runs on the host. It needs bash,
# coreutils and podman or docker; no root, no other host package.
# The steps themselves are scripts/build.sh, which runs inside the container.
#
#   ./build.sh [<step>]           pins | fetch | apply-patches | compile-check |
#                                 build | deb | package | all (default) | key
#   ./build.sh shell [<cmd>...]   a shell (or one command) in the builder
#   ./build.sh --help
#
# Result: ./out/{Image,<dtb>,config,System.map,modules/,KERNEL-ID}.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_REPO="localhost/a7s-linux-lts-builder"

die() { printf 'build.sh: error: %s\n' "$*" >&2; exit 1; }
log() { printf '=== %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
Usage:
  ./build.sh [<step>]              run a step in the builder container
                                   (default: all = fetch + apply-patches + build)
  ./build.sh shell [<cmd> [<arg>...]]
                                   interactive shell (or one command) in the builder
  ./build.sh --help                this text

Steps (scripts/build.sh): pins, fetch, apply-patches, compile-check, build, deb, package,
all, key.

Environment (read by this script only):
  KERNEL_ENGINE   podman or docker (default: podman if installed, else docker)
  KERNEL_WORK     where the sources are unpacked and built (default: ./work)
  KERNEL_OUT      where the result goes (default: ./out)
  KERNEL_CACHE    verified downloads, shared between checkouts (default: ./cache)
Passed into the container when set: A7S_KERNEL_SOURCE_DATE_EPOCH, A7S_KERNEL_REVISION, A7S_JOBS,
A7S_DOWNLOAD_MIRROR, A7S_FETCH_MAX_TIME and the developer switches
A7S_KERNEL_DTB, A7S_KERNEL_SERIES, A7S_KERNEL_PATCHES, A7S_KERNEL_CONFIG,
A7S_SKIP_PATCHES, A7S_LOCALVERSION.

The first run builds the builder image from container/ (Debian trixie, pinned by
digest, packages from snapshot.debian.org at the version in
container/packages.lock). Result: out/Image, the dtb, out/modules/ and
out/KERNEL-ID.
USAGE
}

pick_engine() {
  ENGINE="${KERNEL_ENGINE:-}"
  if [ -z "${ENGINE}" ]; then
    if command -v podman >/dev/null 2>&1; then ENGINE=podman
    elif command -v docker >/dev/null 2>&1; then ENGINE=docker
    else die "neither podman nor docker is installed"; fi
  fi
  case "${ENGINE}" in podman|docker) ;; *) die "KERNEL_ENGINE must be podman or docker, not '${ENGINE}'" ;; esac
  command -v "${ENGINE}" >/dev/null 2>&1 || die "KERNEL_ENGINE=${ENGINE}, but ${ENGINE} is not installed"
  # Rootless engines map the container's root to the invoking user, so what the
  # build writes is the user's anyway. A rootful engine would write as root:
  # then the container runs as the invoking user instead.
  ROOTLESS=false
  case "${ENGINE}" in
    podman) [ "$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = true ] && ROOTLESS=true ;;
    docker) docker info --format '{{.SecurityOptions}}' 2>/dev/null | grep -q rootless && ROOTLESS=true ;;
  esac
  return 0
}

# The builder image tag is a hash over everything in container/: any change to
# the Containerfile, the package list or the lock gives a new tag and a rebuild.
builder_tag() {
  local h
  h="$(cd "${REPO}/container" \
       && find . -type f ! -name '*~' -print0 | LC_ALL=C sort -z | xargs -0 sha256sum \
       | sha256sum | cut -c1-16)"
  printf '%s:%s' "${IMAGE_REPO}" "${h}"
}

ensure_builder() {
  TAG="$(builder_tag)"
  if "${ENGINE}" image inspect "${TAG}" >/dev/null 2>&1; then
    return 0
  fi
  log "building the builder image ${TAG} (once per change to container/)"
  local opts=()
  # podman: no SELinux separation for the build containers (docker's BuildKit
  # has no such option and needs none).
  [ "${ENGINE}" != podman ] || opts+=(--security-opt label=disable)
  "${ENGINE}" build "${opts[@]}" -t "${TAG}" -f "${REPO}/container/Containerfile" "${REPO}/container" \
    || die "building the builder image failed"
}

abs_dir() {  # <path relative to the repository or absolute>
  local p="$1"
  case "${p}" in /*) ;; *) p="${REPO}/${p}" ;; esac
  mkdir -p "${p}" || die "cannot create ${p}"
  (cd "${p}" && pwd)
}

main() {
  local a
  for a in "$@"; do
    case "${a}" in -h|--help|help) usage; exit 0 ;; esac
  done
  [ "$#" -gt 0 ] || set -- all

  case "$(uname -m)" in
    x86_64|aarch64) ;;
    *) die "host architecture $(uname -m) is not supported (x86_64 or aarch64)" ;;
  esac

  pick_engine
  local work out cache
  work="$(abs_dir "${KERNEL_WORK:-work}")"
  out="$(abs_dir "${KERNEL_OUT:-out}")"
  cache="$(abs_dir "${KERNEL_CACHE:-cache}")"
  ensure_builder

  local run=(run --rm --init
    # SELinux: no relabeling of the user's directories (:z would rewrite their
    # labels for good); the container runs without SELinux separation instead.
    --security-opt label=disable
    -v "${REPO}:/src:ro"
    -v "${work}:/work"
    -v "${out}:/out"
    -v "${cache}:/cache"
    -e WORK_DIR=/work -e OUT_DIR=/out -e CACHE_DIR=/cache -e HOME=/work/home
    -w /src)
  if [ "${ROOTLESS}" = false ] && [ "$(id -u)" != 0 ]; then
    run+=(--user "$(id -u):$(id -g)")
  fi
  if [ -t 0 ] && [ -t 1 ]; then run+=(-it); elif [ "$1" = shell ]; then run+=(-i); fi
  local name
  for name in A7S_KERNEL_SOURCE_DATE_EPOCH A7S_JOBS A7S_DOWNLOAD_MIRROR A7S_FETCH_MAX_TIME \
              A7S_KERNEL_REVISION A7S_KERNEL_DTB A7S_KERNEL_SERIES A7S_KERNEL_PATCHES A7S_KERNEL_CONFIG \
              A7S_SKIP_PATCHES A7S_LOCALVERSION; do
    [ -z "${!name+x}" ] || run+=(-e "${name}=${!name}")
  done
  mkdir -p "${work}/home"

  log "${ENGINE} ($([ "${ROOTLESS}" = true ] && echo rootless || echo rootful)), builder ${TAG}, step: $*"
  if [ "$1" = shell ]; then
    shift
    [ "$#" -gt 0 ] || set -- bash
    exec "${ENGINE}" "${run[@]}" "${TAG}" "$@"
  fi
  exec "${ENGINE}" "${run[@]}" "${TAG}" bash /src/scripts/build.sh "$@"
}

main "$@"
