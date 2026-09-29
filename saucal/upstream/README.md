# The text that actually gets posted

One file per artifact, in posting order. Each contains **only** the body, below a
commented header giving what to post it as, the title, and the branch. The header
is an HTML comment, so it renders as nothing if you paste it by accident.

| file | post as | target |
| ---- | ------- | ------ |
| `01-comment-on-issue-2446.md` | comment | existing issue [#2446](https://github.com/restic/restic/issues/2446) |
| `02-draft-pr3-spill-wide-tree.md` | **draft** PR | `upstream/pr3-spill-wide-tree` → `restic/restic:master` |
| `03-draft-pr1-bound-pending-nodes.md` | **draft** PR | `upstream/pr1-bound-pending-nodes` → `restic/restic:master` |
| `04-draft-pr2-verify-large-blob.md` | **draft** PR | `upstream/pr2-verify-large-blob` → `restic/restic:master` |
| `06-new-issue-preallocation-hang.md` | new issue | `restic/restic` |
| `07-draft-pr4-preallocation-guard.md` | **draft** PR | `upstream/pr4-preallocation-guard` → `restic/restic:master` |

Step 05 is not a file: it is going back to PR 3's body once PR 1 and PR 2 have
numbers, and filling them in.

## Placeholders to replace

`#<pr1>`, `#<pr2>`, `#<pr3>`, `#<issue b>` — the numbers GitHub assigns. This is
the only reason PR 3 is posted before PR 1 and PR 2: they cite its number, so it
needs one first.

## Which PR contains which

- `01`, `03`, `04`, `06`, `07` — self-contained, nothing to coordinate.
- `02` (PR 3) — **three commits**: PR 1's, PR 2's, and its own. A fork pull
  request must be based on a branch in `restic/restic`, so it cannot be stacked.
  Each body now says its own status in its first paragraph, so a maintainer
  reading only the PR knows.

## Everything else

`../UPSTREAM-PRS.md` is the working document — the same bodies plus the reasoning,
the upstream research, the branch state and the changelog mechanics. **Nothing in
that file gets posted.** These six files are the deliverable; it is the notes.
