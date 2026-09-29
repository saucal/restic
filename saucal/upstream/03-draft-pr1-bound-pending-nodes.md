<!-- POST AS: a DRAFT pull request
     TITLE:  archiver: Bound the memory a wide directory costs
     BRANCH: upstream/pr1-bound-pending-nodes  ->  restic/restic:master  (1 commit, self-contained) -->
<!-- Everything below the next line is the body, verbatim. Replace the #<...> placeholders. -->
<!-- ----------------------------------------------------------------- -->

## What does this PR change? What problem does it solve?

One of three changes measured on #2446. **One commit, self-contained:** it does
not depend on #<pr2> or #<pr3> and can be merged on its own, in any order. It
needs no format change and adds no interface, and it picks up where #3773
stopped.

`saveDir` submitted every entry of a directory and folded the results into the
directory's tree only once the whole directory had been walked, so a finished entry
was held — its node, the two paths naming it, and its channel, about a kilobyte in
all — until then. #3773 shrank those structs; what it did not change is how long
the array lives. A directory of a million entries therefore still needed roughly a
gigabyte on top of the tree itself, which is enough for a host with a memory cap
to kill the backup outright.

The entries of a directory are folded into its tree in the order they appear, so a
finished entry need not be kept. This folds them in as the walk goes, holding only
enough of a window — 10000 entries — to let the entries ahead of a slow one finish
out of order. The file saver's queue is unbuffered, so the walk was already paced
by the file readers, and consuming results earlier costs no concurrency.
Directories no wider than the window behave exactly as before.

Two smaller costs went with it: each entry's name is released once the paths have
been built from it, and the buffer holding the tree is sized from the directory's
entry count rather than being grown and copied repeatedly, which held two copies of
a large tree at once. On that second point, `bytes.Buffer.Grow` is the wrong tool
here: `growSlice` appends onto a fresh allocation and so holds both sizes at once,
which took a million entries from 982 MB to 1565 MB.

Measured on one flat directory of a million zero-byte files, `GOMAXPROCS=2
GOGC=20`: peak RSS 1248 MB before, 773 MB after. Backing up 600,000 entries in one
directory under a hard 600 MiB cap fails before this change and succeeds after it.

The tree written is byte for byte unchanged: same repository, second backup with
`--force`, root tree ids compared, then `check --read-data` and a restore diffed
against the source. Note for anyone reproducing this — tree ids differ across two
repositories regardless, since each gets its own chunker polynomial, so the
comparison has to be within one repository.

`TestArchiverSaveDirWide` covers what the window makes different: a directory
wider than the window, including entries that finish out of order.

The harness behind the numbers:
https://github.com/saucal/restic/tree/repro/wide-directory-memory/wide-directory-repro

Happy to fold this changelog entry together with the other two into one
`issue-2446` entry if you would rather have a single line for all of it.

> **How this was written.** I am not a Go developer, though I am an engineer. I
> came at this from operationally using restic to back up WordPress sites, which
> sometimes hold very large numbers of small thumbnail files in a single
> directory. I had an AI assistant take a stab at the problem, and what it
> produced solved my use case — but I am not claiming it is the right solution to
> the problem, and I know there is a whole universe of use cases I cannot think of
> or cover, especially without Go-specific knowledge. What I can vouch for is the
> measuring: the numbers above are ones I took myself, before and after, and the
> change passes the existing test suite along with the tests added here and has
> been running on real backups. I can follow directions, so if the shape is wrong,
> tell me what it should be and I will do the work.

## Was the change previously discussed in an issue or on the forum?

#2446. See also #<pr3>, the third change, which I expect to close.
