#!/usr/bin/env bash
# Remove packages this repository no longer builds from a pool.
#
#   remove-orphan-debs.sh POOL
#
# Kept: every package with a packages/<name>/source.conf, and pi-star
# (built by Build Pi-Star DEB from Pi-Star_MCP). Removed: any other
# package, and an amd64 build of a package built for ARM only
# (wiringpi: GPIO).
#
# Run from the repository root. With no packages found there it stops
# rather than remove everything.

set -euo pipefail

POOL=${1:?pool}
EXTERNAL_PACKAGES="pi-star"
ARM_ONLY_PACKAGES="wiringpi"

declare -A KNOWN=()
for conf in packages/*/source.conf; do
	[ -f "$conf" ] || continue
	KNOWN[$(basename "$(dirname "$conf")")]=1
done
if [ "${#KNOWN[@]}" -eq 0 ]; then
	echo "Error: no packages/*/source.conf found (not run from the repository root?)" >&2
	exit 1
fi
for p in $EXTERNAL_PACKAGES; do KNOWN[$p]=1; done

removed=0
while IFS= read -r -d '' path; do
	f=${path##*/}
	name=${f%%_*}
	arch=${f##*_}
	arch=${arch%.deb}
	why=""
	if [ -z "${KNOWN[$name]:-}" ]; then
		why="no longer built here"
	elif [ "$arch" = "amd64" ] && [[ " $ARM_ONLY_PACKAGES " == *" $name "* ]]; then
		why="built for ARM only"
	fi
	if [ -n "$why" ]; then
		echo "  remove $f ($why)"
		rm -f -- "$path"
		removed=$((removed + 1))
	fi
done < <(find "$POOL" -type f -name '*.deb' -print0)
echo "Removed $removed packages this repository no longer builds"
