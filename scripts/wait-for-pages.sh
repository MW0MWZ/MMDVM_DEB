#!/bin/bash
# Wait until the live site serves the repository indexes just pushed to
# gh-pages, purging Cloudflare once GitHub Pages has the new content.
#
# Purging before the Pages build finishes lets Cloudflare re-cache the old
# index for up to 4 hours (max-age=14400), so clients and image builds
# install the previous release. This:
#   1. records the hash of each index file at the gh-pages commit
#   2. waits for the GitHub Pages build of that commit
#   3. purges those index URLs from Cloudflare (when credentials are set)
#   4. polls the live URLs until every hash matches, re-purging while stale
#
# Environment:
#   GH_TOKEN               GitHub token (contents:read, pages:read)
#   GITHUB_REPOSITORY      owner/repo
#   SITE                   e.g. https://apk.pistar.uk
#   INDEX_PATHS            space-separated paths of the index files
#   CLOUDFLARE_ZONE        optional, with CLOUDFLARE_TOKEN
#   CLOUDFLARE_TOKEN       optional
#   TIMEOUT                seconds, default 1800
#
# Exits 0 when the site matches gh-pages, 1 otherwise.

set -euo pipefail

: "${GITHUB_REPOSITORY:?}" "${SITE:?}" "${INDEX_PATHS:?}"
TIMEOUT="${TIMEOUT:-1800}"
DEADLINE=$(( $(date +%s) + TIMEOUT ))
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

log() { echo "[wait-for-pages] $*"; }
time_left() { [ "$(date +%s)" -lt "$DEADLINE" ]; }

purge() {
	if [ -z "${CLOUDFLARE_ZONE:-}" ] || [ -z "${CLOUDFLARE_TOKEN:-}" ]; then
		log "Cloudflare credentials not set, not purging"
		return 0
	fi
	local files="" p
	for p in $INDEX_PATHS; do
		files="${files:+$files,}\"${SITE}/${p}\""
	done
	local reply
	reply=$(curl -s -X POST \
		"https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE}/purge_cache" \
		-H "Authorization: Bearer ${CLOUDFLARE_TOKEN}" \
		-H "Content-Type: application/json" \
		--data "{\"files\": [${files}]}")
	if echo "$reply" | grep -q '"success": *true'; then
		log "Cloudflare purged $(echo "$INDEX_PATHS" | wc -w) index files"
	else
		log "WARNING: Cloudflare purge failed: ${reply}"
	fi
}

# 1. Expected hashes at the current gh-pages commit
SHA=$(gh api "repos/${GITHUB_REPOSITORY}/git/ref/heads/gh-pages" -q .object.sha)
log "gh-pages is at ${SHA:0:7}"
for p in $INDEX_PATHS; do
	gh api "repos/${GITHUB_REPOSITORY}/contents/${p}?ref=${SHA}" \
		-H "Accept: application/vnd.github.raw" > "$WORK/f"
	sha256sum < "$WORK/f" | cut -d' ' -f1 > "$WORK/$(echo "$p" | tr / _)"
done

# 2. GitHub Pages build of that commit
while :; do
	read -r status commit < <(gh api "repos/${GITHUB_REPOSITORY}/pages/builds/latest" \
		-q '.status + " " + .commit' 2>/dev/null || echo "unknown none")
	if [ "$commit" = "$SHA" ] && [ "$status" = "built" ]; then
		log "GitHub Pages build of ${SHA:0:7} is complete"
		break
	fi
	if [ "$commit" = "$SHA" ] && [ "$status" = "errored" ]; then
		log "ERROR: GitHub Pages build of ${SHA:0:7} failed"
		exit 1
	fi
	if ! time_left; then
		log "ERROR: timed out waiting for the Pages build (latest: ${status} ${commit:0:7})"
		exit 1
	fi
	log "Pages build: ${status} ${commit:0:7}, waiting for ${SHA:0:7}..."
	sleep 20
done

# 3 & 4. Purge, then check what clients receive
purge
last_purge=$(date +%s)
while :; do
	stale=""
	for p in $INDEX_PATHS; do
		live=$(curl -fsS "${SITE}/${p}" 2>/dev/null | sha256sum | cut -d' ' -f1)
		[ "$live" = "$(cat "$WORK/$(echo "$p" | tr / _)")" ] || stale="$stale $p"
	done
	if [ -z "$stale" ]; then
		log "${SITE} matches gh-pages ${SHA:0:7}"
		exit 0
	fi
	if ! time_left; then
		log "ERROR: still stale after ${TIMEOUT}s:${stale}"
		exit 1
	fi
	log "still stale:${stale}"
	if [ $(( $(date +%s) - last_purge )) -ge 60 ]; then
		purge
		last_purge=$(date +%s)
	fi
	sleep 20
done
