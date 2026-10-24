# SPDX-License-Identifier: GPL-2.0-only OR MIT
# SPDX-FileCopyrightText: the a7s-linux-lts contributors
# shellcheck shell=bash
#
# Helpers for scripts/build.sh. Sourced, never run.
#
#   log, warn, die   messages; die ends the build
#   fetch_cached     download into the cache, checked against a sha256
#   fetch_verified   put a file with a given sha256 at a path
#   git_fetch_pinned check out a git commit at a path
#
# The cache is CACHE_DIR (set by scripts/build.sh). Optional: A7S_DOWNLOAD_MIRROR,
# A7S_FETCH_MAX_TIME.

log()  { printf '=== %s\n' "$*"; }
warn() { printf '::warning:: %s\n' "$*" >&2; }
die()  { printf '::error:: %s\n' "$*" >&2; exit 1; }

# --- downloads ----------------------------------------------------------------

_sha256_ok() {  # <sha256> <file>
  [ -f "$2" ] && printf '%s  %s\n' "$1" "$2" | sha256sum -c --status - 2>/dev/null
}

# fetch_cached <sha256> <url> [<url>...]
# Make sure the cache holds the file with this sha256 and print its path. Tries
# A7S_DOWNLOAD_MIRROR/<sha256> first when set, then every URL in order, each
# with retries. A download lands under a temporary name and enters the cache
# only after it matched the sha256; a cached copy is verified again on every
# call and dropped when it no longer matches.
fetch_cached() {
  local sha="$1"; shift
  case "${sha}" in
    [0-9a-f]*) [ "${#sha}" = 64 ] && [ -z "${sha//[0-9a-f]/}" ] || die "fetch: '${sha}' is not a sha256" ;;
    *) die "fetch: '${sha}' is not a sha256" ;;
  esac
  [ "$#" -gt 0 ] || die "fetch: no URL for ${sha}"
  local dir="${CACHE_DIR}/sha256" f part src
  f="${dir}/${sha}"
  mkdir -p "${dir}"
  if [ -e "${f}" ]; then
    if _sha256_ok "${sha}" "${f}"; then printf '%s\n' "${f}"; return 0; fi
    warn "cached ${f} no longer matches its sha256 -- dropped"
    rm -f "${f}"
  fi
  part="${f}.part.$$"
  for src in ${A7S_DOWNLOAD_MIRROR:+"${A7S_DOWNLOAD_MIRROR%/}/${sha}"} "$@"; do
    rm -f "${part}"
    if ! curl -fsSL --retry 4 --retry-all-errors --retry-delay 5 \
         --connect-timeout 30 --max-time "${A7S_FETCH_MAX_TIME:-3600}" \
         -o "${part}" "${src}" >&2; then
      warn "download failed: ${src}"
      continue
    fi
    if _sha256_ok "${sha}" "${part}"; then
      mv -f "${part}" "${f}"
      log "fetched ${src} (sha256 ${sha:0:16}... verified)" >&2
      printf '%s\n' "${f}"
      return 0
    fi
    warn "sha256 mismatch, discarded: ${src} (got $(sha256sum "${part}" | cut -c1-16)..., want ${sha:0:16}...)"
  done
  rm -f "${part}"
  die "no source delivered sha256 ${sha} (tried: ${A7S_DOWNLOAD_MIRROR:+mirror }$*)"
}

# fetch_verified <sha256> <dest> <url> [<url>...]
# Put the file with this sha256 at <dest>. The copy is verified again before it
# is renamed into place, so <dest> never exists with other content.
fetch_verified() {
  local sha="$1" dest="$2" f; shift 2
  [ -n "${dest}" ] || die "fetch_verified: no destination"
  f="$(fetch_cached "${sha}" "$@")" || exit 1
  mkdir -p "$(dirname "${dest}")"
  cp --reflink=auto "${f}" "${dest}.part.$$"
  _sha256_ok "${sha}" "${dest}.part.$$" || { rm -f "${dest}.part.$$"; die "fetch_verified: copy of ${f} does not match ${sha}"; }
  mv -f "${dest}.part.$$" "${dest}"
}

# git_fetch_pinned <url> <commit> <dest>
# Check out exactly <commit> (a full commit id) of <url> at <dest>, without
# history. Objects are kept in a bare repository under CACHE_DIR/git/ so a second
# build does not fetch again; <dest> is recreated from it and is self-contained.
# Git verifies every object against its id while fetching (transfer.fsckObjects),
# and HEAD is checked against <commit> at the end.
git_fetch_pinned() {
  local url="$1" commit="$2" dest="$3" cache try
  case "${#commit}" in
    40|64) [ -z "${commit//[0-9a-f]/}" ] || die "git_fetch_pinned: '${commit}' is not a full commit id" ;;
    *) die "git_fetch_pinned: '${commit}' is not a full commit id (need all 40 hex digits)" ;;
  esac
  [ -n "${dest}" ] || die "git_fetch_pinned: no destination"
  cache="${CACHE_DIR}/git/$(printf '%s' "${url}" | sha256sum | cut -c1-16).git"
  [ -d "${cache}" ] || git init -q --bare "${cache}"
  if ! git -C "${cache}" cat-file -e "${commit}^{commit}" 2>/dev/null; then
    for try in 1 2 3 4; do
      if git -C "${cache}" -c transfer.fsckObjects=true fetch -q --no-tags --depth 1 "${url}" "${commit}"; then
        break
      fi
      [ "${try}" = 4 ] && die "git_fetch_pinned: ${url} did not deliver ${commit}"
      warn "git fetch of ${commit} from ${url} failed (attempt ${try}), retrying"
      sleep $((try * 5))
    done
    git -C "${cache}" cat-file -e "${commit}^{commit}" \
      || die "git_fetch_pinned: ${url} answered, but ${commit} is not a commit"
  fi
  git -C "${cache}" update-ref "refs/a7s/${commit}" "${commit}"
  rm -rf "${dest}"
  mkdir -p "$(dirname "${dest}")"
  git init -q "${dest}"
  git -C "${dest}" fetch -q --no-tags --depth 1 "file://${cache}" "refs/a7s/${commit}"
  git -C "${dest}" checkout -q --detach FETCH_HEAD
  [ "$(git -C "${dest}" rev-parse HEAD)" = "${commit}" ] \
    || die "git_fetch_pinned: ${dest} is at $(git -C "${dest}" rev-parse HEAD), not ${commit}"
  log "${url} @ ${commit:0:12} -> ${dest}"
}
