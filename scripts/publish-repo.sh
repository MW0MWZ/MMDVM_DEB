#!/usr/bin/env bash
# Publish to the gh-pages branch, leaving the APT repository clean and
# ready for use, without undoing anyone else's release.
#
#   publish-repo.sh DIR MESSAGE COMMAND [ARGS...]
#
# DIR is a git checkout of gh-pages. Each attempt:
#   1. resets DIR to gh-pages as it is now on the remote
#   2. runs COMMAND ARGS... DIR, which adds this run's packages
#   3. tidies the whole repository, whatever this run changed:
#      - removes packages this repository no longer builds
#        (remove-orphan-debs.sh)
#      - keeps the newest VERSIONS_TO_KEEP versions of every package, for
#        each Debian release and architecture (prune-debs.sh)
#      - writes and signs all of dists/ afresh (write-deb-metadata.sh)
#      - restores the public key, CNAME, index.html and .nojekyll
#   4. commits and pushes, never forced
# Every workflow that changes gh-pages publishes this way. When the push
# is refused because another workflow pushed first, the next attempt
# starts again from that newer branch, so both releases end up
# published: a deploy never replaces the branch with an older copy.
#
# COMMAND may append lines for the commit message to "$PUBLISH_NOTES".
#
# Environment:
#   GPG_PRIVATE_KEY   signing key (required)
#   GPG_KEY_ID        key to sign with
#   GPG_PASSPHRASE    optional
#   PUBLIC_KEY        the key clients download, default keys/hamradio.gpg:
#                     published as hamradio.gpg, and every signature must
#                     verify against it
#   VERSIONS_TO_KEEP  default 5
#   SKIP_CLEANUP      "true" keeps every version (a manual run's choice)
#   CLEANUP_ORPHANED  "false" keeps packages no longer built (default true)
#   ATTEMPTS          default 5

set -euo pipefail

DIR=${1:?gh-pages checkout}
MESSAGE=${2:?commit message}
shift 2
[ "$#" -gt 0 ] || { echo "Error: no update command" >&2; exit 1; }
: "${GPG_PRIVATE_KEY:?}"
ATTEMPTS=${ATTEMPTS:-5}
KEEP=${VERSIONS_TO_KEEP:-5}
export PUBLIC_KEY=${PUBLIC_KEY:-$PWD/keys/hamradio.gpg}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export PUBLISH_NOTES="$WORK/notes"
export GNUPGHOME="$WORK/gnupg"
mkdir -m 700 "$GNUPGHOME"
printf '%s\n' "$GPG_PRIVATE_KEY" | gpg --batch --import 2>/dev/null
if [ -z "$(gpg --batch --list-secret-keys 2>/dev/null)" ]; then
	echo "Error: GPG_PRIVATE_KEY holds no secret key" >&2
	exit 1
fi

git -C "$DIR" config user.name "github-actions[bot]"
git -C "$DIR" config user.email "github-actions[bot]@users.noreply.github.com"

for ((attempt = 1; attempt <= ATTEMPTS; attempt++)); do
	echo "=== Publish attempt $attempt of $ATTEMPTS"

	git -C "$DIR" fetch --depth=1 origin gh-pages
	git -C "$DIR" reset --hard FETCH_HEAD
	git -C "$DIR" clean -ffdx
	: >"$PUBLISH_NOTES"
	mkdir -p "$DIR/pool"

	"$@" "$DIR"

	if [ "${CLEANUP_ORPHANED:-true}" = "true" ]; then
		scripts/remove-orphan-debs.sh "$DIR/pool"
	fi
	if [ "${SKIP_CLEANUP:-false}" = "true" ]; then
		echo "Cleanup skipped: every version kept"
	else
		: >"$WORK/prune"
		PRUNE_ENV="$WORK/prune" scripts/prune-debs.sh "$KEEP" "$DIR/pool"
		DELETED=$(sed -n 's/^CLEANUP_TOTAL_DELETED=//p' "$WORK/prune")
		FREED=$(sed -n 's/^CLEANUP_SPACE_FREED=//p' "$WORK/prune")
		if [ "$DELETED" != "0" ]; then
			echo "Cleaned up $DELETED old packages, freed $FREED" >>"$PUBLISH_NOTES"
		fi
	fi
	find "$DIR/pool" -mindepth 1 -type d -empty -delete

	scripts/write-deb-metadata.sh "$DIR"

	cp "$PUBLIC_KEY" "$DIR/hamradio.gpg"
	cp index.html "$DIR/index.html"
	echo "deb.pistar.uk" >"$DIR/CNAME"
	touch "$DIR/.nojekyll"

	total=$(find "$DIR/pool" -name '*.deb' | wc -l)
	git -C "$DIR" add -A
	if git -C "$DIR" diff --cached --quiet; then
		echo "Nothing to publish: gh-pages is already up to date"
		exit 0
	fi
	git -C "$DIR" commit -q -F - <<-EOM
		$MESSAGE - $total packages
		$(cat "$PUBLISH_NOTES")
	EOM
	if git -C "$DIR" push origin HEAD:refs/heads/gh-pages; then
		echo "Published $(git -C "$DIR" rev-parse --short HEAD)"
		[ -n "${GITHUB_OUTPUT:-}" ] && echo "total_packages=$total" >>"$GITHUB_OUTPUT"
		exit 0
	fi
	echo "gh-pages moved on while this run was publishing; starting again from it"
	sleep $((attempt * 15))
done

echo "Error: could not publish after $ATTEMPTS attempts" >&2
exit 1
