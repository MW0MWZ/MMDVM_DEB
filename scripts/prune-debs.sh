#!/usr/bin/env bash
# Keep the newest KEEP versions of each package, for each Debian release
# and architecture, in a repository pool, and delete the rest.
#
#   prune-debs.sh [--dry-run] KEEP POOL
#
# A file is <name>_<version>_<arch>.deb, the version being
# <date>-<revision>~deb<NN>u<N> (2026.11.24-3~deb12u1): files are grouped
# by name, Debian release (deb12, deb13) and architecture, and ordered by
# version number (date, then revision: -10 after -9), never by file time
# or by name: the files are fresh copies in every run, so their times say
# nothing about which build is newer.
#
# Nothing is deleted on doubt: a file whose name or version is not in
# that form is left alone with a warning, and so is every file of its
# group.
#
# CLEANUP_TOTAL_DELETED and CLEANUP_SPACE_FREED are written to the file
# named by PRUNE_ENV when one is set.

set -euo pipefail
export LC_ALL=C

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
	DRY_RUN=1
	shift
fi

KEEP="${1:-}"
POOL="${2:-}"
if ! [[ "$KEEP" =~ ^[0-9]+$ ]] || [ "$KEEP" -lt 1 ]; then
	echo "Error: KEEP must be a whole number of at least 1 (got '$KEEP')" >&2
	exit 1
fi
if [ ! -d "$POOL" ]; then
	echo "Error: no pool at '$POOL'" >&2
	exit 1
fi

warn() {
	if [ -n "${GITHUB_ACTIONS:-}" ]; then
		echo "::warning::$*"
	else
		echo "WARNING: $*"
	fi
}

declare -A ROWS=()   # group -> "upstream<TAB>revision<TAB>u<TAB>path" lines
declare -A UNSAFE=() # group -> 1

while IFS= read -r -d '' path; do
	f=${path##*/}
	if [[ "$f" =~ ^([^_]+)_([^_]+)_([^_]+)\.deb$ ]]; then
		name=${BASH_REMATCH[1]}
		ver=${BASH_REMATCH[2]}
		arch=${BASH_REMATCH[3]}
		if [[ "$ver" =~ ^([0-9]+(\.[0-9]+)*)-([0-9]+)~deb([0-9]+)u([0-9]+)$ ]]; then
			group="$name deb${BASH_REMATCH[4]} $arch"
			ROWS[$group]+="${BASH_REMATCH[1]}"$'\t'"${BASH_REMATCH[3]}"$'\t'"${BASH_REMATCH[5]}"$'\t'"$path"$'\n'
		else
			if [[ "$ver" =~ ~deb([0-9]+) ]]; then
				group="$name deb${BASH_REMATCH[1]} $arch"
				UNSAFE[$group]=1
				ROWS[$group]+=$'\t\t\t'"$path"$'\n'
			fi
			warn "$f: version '$ver' not understood, left alone"
		fi
	else
		warn "$f: name not understood, left alone"
	fi
done < <(find "$POOL" -type f -name '*.deb' -print0)

TOTAL_DELETED=0
TOTAL_BYTES=0
for group in $(printf '%s\n' "${!ROWS[@]}" | sort | tr ' ' '|'); do
	group=${group//|/ }
	mapfile -t sorted < <(printf '%s' "${ROWS[$group]}" | sort -t $'\t' -k1,1Vr -k2,2nr -k3,3nr)
	count=${#sorted[@]}
	if [ -n "${UNSAFE[$group]:-}" ]; then
		warn "$group: a version is not understood, its $count files left alone"
		continue
	fi
	[ "$count" -gt "$KEEP" ] || continue
	kept=()
	for ((i = 0; i < KEEP; i++)); do
		p=$(cut -f4 <<<"${sorted[$i]}")
		kept+=("${p##*/}")
	done
	echo "$group: $count versions, keeping ${kept[*]}"
	for ((i = KEEP; i < count; i++)); do
		p=$(cut -f4 <<<"${sorted[$i]}")
		bytes=$(stat -c %s "$p")
		echo "  delete ${p##*/}"
		if [ "$DRY_RUN" -eq 0 ]; then
			rm -f -- "$p"
		fi
		TOTAL_DELETED=$((TOTAL_DELETED + 1))
		TOTAL_BYTES=$((TOTAL_BYTES + bytes))
	done
done

FREED="$((TOTAL_BYTES / 1024 / 1024))MB"
echo "Deleted $TOTAL_DELETED old package files, freed $FREED$([ "$DRY_RUN" -eq 1 ] && echo ' (dry run: nothing removed)')"

if [ -n "${PRUNE_ENV:-}" ] && [ "$DRY_RUN" -eq 0 ]; then
	echo "CLEANUP_TOTAL_DELETED=$TOTAL_DELETED" >>"$PRUNE_ENV"
	echo "CLEANUP_SPACE_FREED=$FREED" >>"$PRUNE_ENV"
fi
