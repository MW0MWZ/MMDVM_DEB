#!/bin/bash
# Sourced by the packages' build.sh scripts.
#
# shlibdeps_depends <package dir>: the Depends for the ELF executables and
# libraries in a package being built, from dpkg-shlibdeps: the shared
# libraries they link, under the package names the Debian release being
# built for gives them (a library renamed for the 64-bit time_t
# transition, libfoo1t64, is only so named where it was renamed).
shlibdeps_depends() {
    local pkgdir tmp files deps
    pkgdir=$(cd "$1" && pwd) || return 1
    tmp=$(mktemp -d)
    mkdir -p "$tmp/debian"
    printf 'Source: shlibdeps\n\nPackage: shlibdeps\nArchitecture: any\n' > "$tmp/debian/control"
    files=$(find "$pkgdir" -type f ! -path "*/DEBIAN/*" -exec sh -c 'file -b "$1" | grep -q "^ELF"' _ {} \; -print)
    if [ -z "$files" ]; then
        rm -rf "$tmp"
        echo "shlibdeps: no executables in $pkgdir" >&2
        return 1
    fi
    # Libraries from no Debian package (wiringPi built from source) have no
    # dependency information: the build adds those itself
    deps=$(cd "$tmp" && dpkg-shlibdeps --ignore-missing-info -O $files 2>/dev/null | sed -n 's/^shlibs:Depends=//p')
    rm -rf "$tmp"
    if [ -z "$deps" ]; then
        echo "shlibdeps: dpkg-shlibdeps found no dependencies for $pkgdir" >&2
        return 1
    fi
    echo "$deps"
}
