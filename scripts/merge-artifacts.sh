#!/usr/bin/env bash
# Copy the .deb files from downloaded build artifacts into a repository's
# pool, each to pool/main/<first letter>/<package>/.
#
#   merge-artifacts.sh ARTIFACT_DIR... DEST
#
# The package name is read from each file's control data, and must match
# its file name.

set -euo pipefail

[ "$#" -ge 2 ] || { echo "Usage: merge-artifacts.sh ARTIFACT_DIR... DEST" >&2; exit 1; }
DEST=${!#}
set -- "${@:1:$#-1}"

copied=0
for src in "$@"; do
	[ -d "$src" ] || continue
	while IFS= read -r -d '' deb; do
		f=${deb##*/}
		name=$(dpkg-deb -f "$deb" Package)
		if [ -z "$name" ] || [ "${f%%_*}" != "$name" ]; then
			echo "Error: $deb: package name '$name' does not match the file name" >&2
			exit 1
		fi
		dir="$DEST/pool/main/${name:0:1}/$name"
		mkdir -p "$dir"
		cp "$deb" "$dir/"
		echo "  pool/main/${name:0:1}/$name/$f"
		copied=$((copied + 1))
	done < <(find "$src" -name '*.deb' -type f -print0)
done

if [ "$copied" -eq 0 ]; then
	echo "Error: no packages found in the build artifacts" >&2
	exit 1
fi
echo "Merged $copied packages"
