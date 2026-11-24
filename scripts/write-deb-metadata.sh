#!/usr/bin/env bash
# Write and sign the APT metadata for a repository tree.
#
#   write-deb-metadata.sh DIR
#
# For each release (bookworm: ~deb12, trixie: ~deb13) and architecture,
# dists/<release>/main/binary-<arch>/Packages (.gz, .bz2) lists every
# package file in the pool for that release and architecture, every
# version kept (apt installs the newest, and can be given an older
# one); dists/<release>/Release lists those files with their checksums
# and is signed as Release.gpg and InRelease. Everything under dists/ is written afresh, so nothing stale
# is left behind.
#
# Each signature must verify against PUBLIC_KEY, the key clients are
# told to download (default: keys/hamradio.gpg, from the directory this
# is run in), or nothing is written: a wrong signing key fails here, not
# on every client.
#
# Needs dpkg-scanpackages, apt-ftparchive, gpg and gpgv, with the signing
# key imported. Environment: GPG_KEY_ID (signing key; default: gpg's
# default key), GPG_PASSPHRASE (optional), PUBLIC_KEY.

set -euo pipefail

DIR=${1:?repository}
RELEASES="bookworm:12 trixie:13"
ARCHES="amd64 arm64 armhf"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PUBLIC_KEY=${PUBLIC_KEY:-keys/hamradio.gpg}
gpg --batch --dearmor <"$PUBLIC_KEY" >"$WORK/clients.gpg"

cd "$DIR"
rm -rf dists
for rel in $RELEASES; do
	DIST=${rel%%:*}
	NN=${rel##*:}
	for ARCH in $ARCHES; do
		out="dists/$DIST/main/binary-$ARCH"
		mkdir -p "$out"
		# A pool of this release's packages for this architecture only
		tmp="$WORK/$DIST-$ARCH"
		mkdir -p "$tmp"
		find pool -type f -name "*~deb${NN}u*_${ARCH}.deb" | while IFS= read -r pkg; do
			mkdir -p "$tmp/$(dirname "$pkg")"
			ln -s "$(realpath "$pkg")" "$tmp/$pkg"
		done
		if [ -d "$tmp/pool" ]; then
			# Some control files (wiringpi) hold stray blank lines that would
			# split a stanza: drop every blank line, then separate stanzas
			(cd "$tmp" && dpkg-scanpackages --multiversion -a "$ARCH" pool 2>"$WORK/scan.err") |
				sed '/^[[:space:]]*$/d' | perl -pe 'print "\n" if /^Package:/ && $. > 1' >"$out/Packages"
		else
			: >"$out/Packages"
		fi
		files=$(find "$tmp" -name '*.deb' | wc -l)
		listed=$(grep -c '^Package:' "$out/Packages" || true)
		if [ "$files" -ne "$listed" ]; then
			echo "Error: $out lists $listed packages of $files" >&2
			cat "$WORK/scan.err" >&2 2>/dev/null || true
			exit 1
		fi
		gzip -9nc "$out/Packages" >"$out/Packages.gz"
		bzip2 -9c "$out/Packages" >"$out/Packages.bz2"
		echo "$out: $listed packages"
	done

	{
		echo "Origin: Ham Radio Packages"
		echo "Label: Ham Radio Packages"
		echo "Suite: $DIST"
		echo "Codename: $DIST"
		echo "Version: 1.0"
		echo "Architectures: $ARCHES"
		echo "Components: main"
		echo "Description: Amateur Radio Digital Voice packages for Debian $DIST"
		echo "Date: $(date -Ru)"
		apt-ftparchive release "dists/$DIST"
	} >"$WORK/Release"
	mv "$WORK/Release" "dists/$DIST/Release"

	sign=(gpg --batch --yes)
	[ -n "${GPG_KEY_ID:-}" ] && sign+=(--default-key "$GPG_KEY_ID")
	if [ -n "${GPG_PASSPHRASE:-}" ]; then
		sign+=(--pinentry-mode loopback --passphrase "$GPG_PASSPHRASE")
	fi
	"${sign[@]}" --armor --detach-sign -o "dists/$DIST/Release.gpg" "dists/$DIST/Release"
	"${sign[@]}" --clearsign -o "dists/$DIST/InRelease" "dists/$DIST/Release"
	for f in InRelease "Release.gpg Release"; do
		# shellcheck disable=SC2086 # two files for the detached signature
		(cd "dists/$DIST" && gpgv --keyring "$WORK/clients.gpg" $f 2>/dev/null) || {
			echo "Error: dists/$DIST/${f%% *} does not verify against $PUBLIC_KEY" >&2
			exit 1
		}
	done
	echo "dists/$DIST: Release signed"
done
