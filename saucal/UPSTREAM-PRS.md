# Upstream submission — notes

**Posted 2026-09-29.** The text as posted is in `saucal/upstream/`.

| | what | branch |
|---|---|---|
| restic/restic#22080 | bound pending nodes, ready | `upstream/pr1-bound-pending-nodes` |
| restic/restic#22081 | verify large blob, ready | `upstream/pr2-verify-large-blob` |
| restic/restic#22082 | whole memory solution (carries the two above), draft | `upstream/pr3-spill-wide-tree` |
| restic/restic#2446 comment 5899856389 | measurements, links, offer to help with chunked trees | — |
| restic/restic#22083 | issue: fallocate never returns | — |
| restic/restic#22084 | preallocation guard, ready, closes #22083 | `upstream/pr4-preallocation-guard` |

If #22080 or #22081 change after review, rebuild #22082 from them (PR1 commit + cherry-pick PR2 + the spill commit). A maintainer must approve the first test run.

## Context

- The memory problem is upstream #2446 (open since 2019). The maintainer's plan is chunked tree blobs: #3773 (2022) shrank the structs, #5613 (merged 2026-01-31) replaced `data.Tree` with an iterator, and #21943 (his open draft) adds `object.Reader`/`Writer` for blob sequences. Our PR3 is a special case of that, so it goes up as a draft and we offer to help with chunked trees instead.
- The preallocation hang has no upstream issue. Neighbours: #5543, #5553 (closed), #5045 (retry on signal), #2675/#2893.
- The minio CI fix is obsolete (upstream switched to seaweedfs in #22067). `upstream/resource-diagnostics` is not going up (own instrumentation; accidental binaries in `dist/`).

## Branches

| branch | commits | self-contained |
|---|---|---|
| `upstream/pr1-bound-pending-nodes` | 1 | yes |
| `upstream/pr2-verify-large-blob` | 1 | yes |
| `upstream/pr3-spill-wide-tree` | 3 (PR1 + PR2 + spill) | no |
| `upstream/pr4-preallocation-guard` | 1 | yes |

All rebased on `restic/restic` master `5127c4abf` (2026-09-27): build, gofmt, `golangci-lint --new-from-rev` (0 issues), tests and `calens` pass. Full `go test ./...` fails only the six tests that also fail on unmodified master locally (mount, stdin-from-command, xattr). PR3's code is identical to what passed CI and runs in production. Rebase and re-check before posting.

Nothing in the upstream branches or bodies mentions saucal, clients, AI attribution trailers or session links; the disclosure is the note in each body.

Before step 01, push the four branches and `repro/wide-directory-memory` (PR1 links its harness; the client-name scrub is local only).
