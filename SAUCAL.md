# The saucal build of restic

`release/saucal` is what the maintenance action installs on WordPress hosts: an
upstream release with our patches on top. Today that is `v0.19.1` plus one
change — restic no longer hangs forever on filesystems that accept the
preallocation syscall and never answer it, which is what Pressable does. Without
it a restore there stops on the first file that needs data, leaves it empty, and
cannot even be killed.

## How the branches fit together

    master            tracks upstream, never committed to directly
      ├── <feature>   one branch per change we intend to send upstream
      └── ...
    release/saucal    an upstream release tag + those changes, merged for
                      integration testing; what we actually ship
    repro/…           reproductions and evidence; nothing there ships

Work meant for upstream starts on a branch off `master`, so its diff is against
what upstream has.

It reaches the fleet through an integration branch cut from the release tag
`release/saucal` sits on — never by merging the master-based branch itself, which
would bring all of post-release master with it:

    git checkout -b saucal/<change> v0.19.1
    git cherry-pick <the commit from the master-based branch>
    git checkout release/saucal
    git merge --no-ff saucal/<change>

The merge commit is where changes meet each other: two of them touching the same
place conflict there, in the open, instead of silently in a cherry-pick. Both
hooks at the top of `cmd/restic/main.go` were reconciled exactly that way.

Nothing is ever merged into `master`: keeping it identical to upstream is what
makes both the upstream diffs and the version merges clean.

`saucal/IDEAS.md` lists what else is worth building here, and why.

Note that a change may need two shapes, because upstream moves files between
releases. The preallocation fix sits in `internal/fs/` on `release/saucal` (where
0.19.1 keeps it) and in `internal/fileio/` on the master-based branch (where
upstream moved it after 0.19.1); the two differ only in the package name.

## How the hosts get it

The action downloads two files from `SAUCAL_RESTIC_RELEASE_BASE` and verifies the
checksum before running anything:

    $BASE/restic_0.19.1_linux_amd64.bz2
    $BASE/SHA256SUMS

The version in those names is **restic's**, taken from the `VERSION` file, not
from our tag. The action derives the same name from its `RESTIC_VERSION` setting
and only the base URL is ours to choose, so the two have to agree: moving this
branch to a new upstream release means updating `RESTIC_VERSION` in the action in
the same change, or it will ask for a file the release does not have. The tag is
still visible where it matters:

    $ restic version
    restic 0.19.1 (v0.19.1-saucal.1-0-g77352dde4) compiled with go1.25.8 on linux/amd64

## Making a change

1. Commit it on this branch. Keep the fix itself as one commit, so it stays easy
   to compare with the upstream branch.
2. Let CI run — pull request #1 in this fork covers this branch.
3. Try the release pipeline without publishing: push the commit to a branch under
   `saucal-release-test/`. The release workflow builds, tests and smoke-tests it,
   then stops, because only a tag publishes anything.

       git push -f origin HEAD:saucal-release-test/try
4. Cut the release: tag and push.

       git tag -a v0.19.1-saucal.3 -m "what changed"
       git push origin v0.19.1-saucal.3

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

## Moving to a newer restic

Merge the upstream tag into this branch, rather than rebasing: the history of
what we shipped stays intact, and each version merge is one reviewable commit.

    git fetch upstream --tags
    git merge v0.20.0

1. Expect conflicts only where our patches sit. Check whether upstream moved the
   files again — preallocation went from `internal/restorer` to `internal/fs` to
   `internal/fileio` across releases, and a merge will not follow that on its own.
2. `VERSION` comes from the merge, so the asset names change with it. Update
   `RESTIC_VERSION` in the action in the same change.
3. Check the Go version in `go.mod` against the release workflow: 0.19.1 needs
   Go 1.25, and a release built with an older toolchain will not compile at all.
4. Read upstream's changelog for behaviour our scripts depend on. Going 0.18.0 to
   0.19.1, `backup` began exiting 3 when a source path is missing, where it used
   to exit 0 — a job that passed on an incomplete backup now fails.
5. Re-run the reproduction on `repro/preallocation-hang` against the new build
   before trusting it.

## What the fix must keep doing

`cmd/restic/main.go` calls `fs.RunProbe()` before anything else parses arguments.
If that call is lost in a rebase, nothing fails loudly — preallocation just turns
itself off everywhere, quietly costing performance on healthy filesystems. The
release workflow smoke-tests it:

    restic --__preallocate-probe /tmp   ->   restic-preallocate-probe-answered
