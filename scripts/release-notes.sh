#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only OR MIT
# SPDX-FileCopyrightText: the a7s-linux-lts contributors
#
# Print the CHANGELOG.md section of a release tag: the text between the heading
# "## [<version>]" and the next "## " heading. Fails when the tag is not of the
# form v<kernel version>-T<n> or -R<n> (v6.18.59-R1), when its section is missing,
# or when the section is empty. Runs on the host, needs bash and awk.
#
# Usage: scripts/release-notes.sh <tag> [<changelog>]
set -euo pipefail

tag="${1:-}"
log="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/CHANGELOG.md}"

case "${tag}" in
  v[0-9]*.[0-9]*.[0-9]*-[TR][0-9]*) ;;
  *) echo "release-notes: '${tag}' is not a release tag (v<kernel version>-T<n> or -R<n>, e.g. v6.18.59-R1)" >&2; exit 2 ;;
esac
tail_="${tag#v}"
case "${tail_//[0-9.TR-]/}" in
  '') ;;
  *) echo "release-notes: '${tag}' is not a release tag (v<kernel version>-T<n> or -R<n>, e.g. v6.18.59-R1)" >&2; exit 2 ;;
esac
[ -f "${log}" ] || { echo "release-notes: ${log} does not exist" >&2; exit 1; }

notes="$(awk -v head="## [${tail_}]" '
  /^## / {
    if (on) exit
    if (index($0, head) == 1) {
      rest = substr($0, length(head) + 1)
      if (rest == "" || rest ~ /^ - /) { on = 1; found = 1; next }
    }
  }
  on { print }
  END { if (!found) exit 3 }
' "${log}")" || { echo "release-notes: ${log} has no section '## [${tail_}]'" >&2; exit 1; }

# Trim blank lines at both ends.
notes="$(printf '%s\n' "${notes}" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' | sed '/./,$!d')"
[ -n "${notes}" ] || { echo "release-notes: the section '## [${tail_}]' of ${log} is empty" >&2; exit 1; }
printf '%s\n' "${notes}"
