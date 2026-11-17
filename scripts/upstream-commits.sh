#!/bin/sh
# upstream-commits.sh <source.conf>
#
# Lists every upstream git repository a package builds from, so that an
# update to any of them (not just GITURL) triggers a rebuild. Each GITURL*
# variable in source.conf is one repository; the commit last built from it
# is recorded in the matching GIT_COMMIT* variable:
#
#   GITURL=...           -> GIT_COMMIT
#   GITURL_MMDVM_CM=...  -> GIT_COMMIT_MMDVM_CM
#   GITURL_DISPLAY=...   -> GIT_COMMIT_DISPLAY
#
# A package that tracks releases (GIT_REF, e.g. wiringpi) has its GITURL
# checked by release tag instead, so it is left out here; its other
# repositories, if any, are listed.
#
# Prints one line per repository:
#
#   <commit variable> <recorded commit> <latest commit> <url> <url variable>
#
# "-" stands for no recorded commit, or a repository that could not be
# reached. The latest commit is that of the repository's default branch
# (git ls-remote HEAD), which is what build.sh's git clone builds.
set -eu

conf=$1
releases=$(grep -E '^GIT_REF=' "$conf" | head -1 | cut -d'"' -f2 || true)

grep -E '^GITURL[A-Z0-9_]*="' "$conf" | while IFS= read -r line; do
	var=${line%%=*}
	if [ "$var" = "GITURL" ] && [ -n "$releases" ]; then
		continue
	fi
	url=$(printf '%s' "$line" | cut -d'"' -f2)
	cvar="GIT_COMMIT${var#GITURL}"
	recorded=$(grep -E "^${cvar}=" "$conf" | head -1 | cut -d'"' -f2)
	latest=$(git ls-remote "$url" HEAD 2>/dev/null | head -1 | cut -c1-7)
	echo "$cvar ${recorded:--} ${latest:--} $url $var"
done
