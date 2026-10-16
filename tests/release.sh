#!/usr/bin/env bash
# Check JReleaser archives against the installation before publishing them.
set -e
export LC_ALL=C

if (($# != 1)); then
    printf '%s\n' 'Usage: bash tests/release.sh VERSION' >&2
    exit 2
fi
version=$1
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    printf '%s\n' 'Expected a MAJOR.MINOR.PATCH release version' >&2
    exit 1
fi
cd -- "${BASH_SOURCE[0]%/*}/.."
root=$PWD
prefix="sycol-$version/"
directory="$root/out/jreleaser/assemble/sycol/archive"
temp=$(mktemp -d "${TMPDIR:-/tmp}/sycol-release.XXXXXXXX")
trap 'rm -rf -- "$temp"' EXIT

printf '%s\n' "$version" > "$temp/version"
if ! cmp -s .sycol/VERSION "$temp/version"; then
    printf '%s\n' 'VERSION must match the release input and use ASCII with LF' >&2
    exit 1
fi
{
    find .sycol examples -type f
    printf '%s\n' sycol sycol.bat LICENSE README.md RELEASE.md SPEC.md
} | sort > "$temp/expected"
sed "s|^|$prefix|" "$temp/expected" > "$temp/entries"
awk -F/ '{path=""; for (i=1; i<NF; i++) {path=path $i "/"; print path}}' \
    "$temp/entries" | sort -u > "$temp/directories"

for extension in zip tgz; do
    archive="$directory/sycol-$version.$extension"
    destination="$temp/$extension"
    mkdir "$destination"
    if [[ "$extension" == zip ]]; then
        unzip -Z1 "$archive" > "$temp/listing"
    else
        tar -tzf "$archive" > "$temp/listing"
    fi
    # Compare before extraction: also rejects duplicates and paths outside the package.
    sed '/\/$/d' "$temp/listing" | sort > "$temp/actual"
    diff -u "$temp/entries" "$temp/actual"
    # Explicit directory entries must be parents of expected files.
    while IFS= read -r entry; do
        case "$entry" in
            */) grep -Fxq "$entry" "$temp/directories" ;;
        esac
    done < "$temp/listing"
    if [[ "$extension" == zip ]]; then
        unzip -q "$archive" -d "$destination"
    else
        tar -xzf "$archive" -C "$destination"
    fi
    # Regular-file discovery rejects symlinks in place of packaged files.
    (cd "$destination/$prefix" && find . -type f | sed 's|^./||' | sort) > "$temp/actual"
    diff -u "$temp/expected" "$temp/actual"
    while IFS= read -r name; do
        cmp "$root/$name" "$destination/$prefix$name"
    done < "$temp/expected"
    for name in sycol .sycol/bin/sycol; do
        if [[ ! -x "$destination/$prefix$name" ]]; then
            printf 'Not executable: %s\n' "$name" >&2
            exit 1
        fi
    done
    printf 'ok - sycol-%s.%s: contents, version, and executable permissions\n' "$version" "$extension"
done
