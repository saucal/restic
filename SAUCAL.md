# The saucal build of restic

This branch is what the maintenance action installs on WordPress hosts. It is
restic `v0.18.0` plus one change: restic no longer hangs forever on filesystems
that accept the preallocation syscall and never answer it, which is what
Pressable does. Without it a restore there stops on the first file that needs
data, leaves it empty, and cannot even be killed.

Upstream's copy of the same fix lives on `upstream/preallocation-guard`, against
`master`. Keep the two in step: `internal/fs/preallocate.go` here and
`internal/fileio/preallocate.go` there should differ only in the package name.
The reproduction that justifies the fix is on `repro/preallocation-hang`.

## How the hosts get it

The action downloads two files from `SAUCAL_RESTIC_RELEASE_BASE` and verifies the
checksum before running anything:

    $BASE/restic_0.18.0_linux_amd64.bz2
    $BASE/SHA256SUMS

The version in those names is **restic's**, not the tag's. The action derives it
from `RESTIC_VERSION` (default `0.18.0`) and only the base URL is ours to choose,
so the files have to be named exactly as upstream names theirs. The tag is still
visible where it matters:

    $ restic version
    restic 0.18.0 (v0.18.0-saucal.1-0-ge1385fd0f) compiled with go1.26.0 on linux/amd64

## Making a change

1. Commit it on this branch. Keep the fix itself as one commit, so it stays easy
   to compare with the upstream branch.
2. Let CI run — pull request #1 in this fork covers this branch.
3. Try the release pipeline without publishing: push the commit to a branch under
   `saucal-release-test/`. The release workflow builds, tests and smoke-tests it,
   then stops, because only a tag publishes anything.

       git push -f origin HEAD:saucal-release-test/try
4. Cut the release: tag and push.

       git tag -a v0.18.0-saucal.2 -m "what changed"
       git push origin v0.18.0-saucal.2

   The workflow builds the assets, checks them, and publishes the release. The
   workflow file must already be committed when the tag is made — a tag push runs
   the workflow as it exists in the tagged commit.
5. Point the fleet at the new release by setting the repo or organisation
   variable:

       SAUCAL_RESTIC_RELEASE_BASE=https://github.com/saucal/restic/releases/download/v0.18.0-saucal.2

   Prefer setting it on one repo and running a staging recreation before going
   organisation-wide.

## Building locally

    ./saucal/build-release.sh          # writes dist/

It refuses to build from a dirty working tree, and that is not fussiness: Go
stamps the build with the tree's state, so the same commit built with stray files
around produces a different binary (`vcs.modified=true`) from one built clean.
Check with `go version -m dist/restic_0.18.0_linux_amd64`. Builds from a clean
tree are byte-identical on repeat.

## Rebasing onto a newer restic

1. Rebase this branch onto the new tag; the fix touches
   `internal/fs/preallocate*.go` and three lines of `cmd/restic/main.go`.
2. Check whether upstream moved the files again — they went from
   `internal/restorer` to `internal/fs` to `internal/fileio` across releases.
3. `VERSION` changes with the upstream tag, so the asset names change with it.
   The action must then be told the new `RESTIC_VERSION`, or it will ask for a
   file the release does not have.
4. Re-run the reproduction on `repro/preallocation-hang` against the new build
   before trusting it.

## What the fix must keep doing

`cmd/restic/main.go` calls `fs.RunProbe()` before anything else parses arguments.
If that call is lost in a rebase, nothing fails loudly — preallocation just turns
itself off everywhere, quietly costing performance on healthy filesystems. The
release workflow smoke-tests it:

    restic --__preallocate-probe /tmp   ->   restic-preallocate-probe-answered
