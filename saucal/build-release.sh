#!/usr/bin/env bash
# Build the assets the maintenance action downloads from SAUCAL_RESTIC_RELEASE_BASE.
#
# The action fetches "restic_<version>_linux_amd64.bz2" and a "SHA256SUMS" covering
# it, and verifies the checksum before running anything — so the names here have to
# match upstream's exactly. <version> comes from the VERSION file, NOT from our tag:
# the action derives it from RESTIC_VERSION (default 0.18.0) and only the base URL is
# ours to choose. The tag still shows up in `restic version`, via git describe.
#
# Usage: saucal/build-release.sh [output dir]    (default: dist)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
out="${1:-dist}"

# Go stamps the build with the working tree's state, so the same commit built with
# stray files around produces a different binary (vcs.modified=true) than one built
# clean. A release has to be reproducible from its tag, so refuse a dirty tree.
# The output directory is git-ignored and does not count. Override with FORCE=1.
if [ -n "$(git status --porcelain)" ] && [ "${FORCE:-}" != "1" ]; then
    echo "the working tree is not clean, so this build would not be reproducible:" >&2
    git status --short >&2
    echo "commit or stash first, or set FORCE=1 to build anyway" >&2
    exit 1
fi
version="$(cat VERSION)"
binary="restic_${version}_linux_amd64"

rm -rf "$out"
mkdir -p "$out"

# build.go, rather than helpers/build-release-binaries: only build.go injects the
# version, so `restic version` names the build an operator is looking at.
echo "building ${binary} from $(git describe --long --tags --dirty --always)"
go run build.go --goos linux --goarch amd64 -o "${out}/${binary}"

bzip2 -k -9 "${out}/${binary}"

# sha256sum on Linux, shasum on macOS; the action runs `grep … | sha256sum -c -`.
(
    cd "$out"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${binary}.bz2" "${binary}" > SHA256SUMS
    else
        shasum -a 256 "${binary}.bz2" "${binary}" > SHA256SUMS
    fi
)

echo
echo "assets in ${out}:"
ls -l "$out"
echo
cat "${out}/SHA256SUMS"
