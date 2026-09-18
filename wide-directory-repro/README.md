# What a very wide directory costs restic

This is the harness behind the memory work on `upstream/bound-wide-directory-memory`.
It produced every figure quoted there, and it exists because the site that prompted
the work — one WordPress uploads directory of 1.14M files on a host that kills a
process at roughly 680 MB — cannot be experimented on.

## The shape of the problem

The cost is per-directory **width**, not file count. The same 400,000 files:

| layout | peak RSS |
| ------ | -------- |
| one directory | 537 MB |
| 400 directories of 1000 | 77 MB |

## What the harness measures

`gen.go` builds a synthetic tree. The knobs matter more than they look:

    -total          how many files
    -per-dir        files per directory (0 = all in one, which is the case of interest)
    -size           bytes per file (0 keeps the disk cost near zero)
    -random-names   incompressible names, so the tree compresses like one whose
                    nodes carry content ids rather than like a repeated string

That last flag exists because of a mistake worth not repeating: a tree of
identical-looking names compresses at 2.2 GB/s and made compression look nearly
free. Real names, and a content id per node, run at about 200 MB/s — a fivefold
difference that inverted one conclusion. **Measure compression on realistic data.**

Names as long as WordPress's scaled-thumbnail names are the default, because every
name is held in memory while its directory is walked.

## Scripts

Each takes a restic binary in `/bin` and a tree in `/data`, and runs in a
throwaway container. Build binaries with `GOOS=linux GOARCH=arm64 go build` (or
amd64) and mount them in.

| script | answers |
| ------ | ------- |
| `run.sh` | peak RSS for one configuration, read from `/proc/<pid>/status` `VmHWM`, which is the kernel's own high-water mark and so cannot miss a spike between samples |
| `sweep2.sh` | several widths in one run |
| `cap3.sh` | survives a hard cgroup cap, or is killed — a verdict rather than a number |
| `same3.sh` | the tree written is unchanged: same repo, second backup with `--force`, root tree ids compared, then `check --read-data` and a restore diffed against the source |
| `compat.sh` | a pristine upstream binary can still read what this build writes, and both write the same tree |
| `reps.sh` | wall time of a first backup and of repeated re-backups |

## Two traps in measuring this

**Compare tree ids in the same repository.** Across two repositories they always
differ, because each gets its own random chunker polynomial, so blob ids — which
`ls -l` does not show — differ. That cost a false alarm about the fix changing
what was written.

**Page cache is not the process.** Measure the process with `VmHWM`, not the
container with `memory.peak`: generating a million files fills the page cache and
counts against the cgroup, which would swamp the figure being measured.

## Results this produced

One flat directory, zero-byte files, GOMAXPROCS=2 GOGC=20, peak RSS:

| entries | v0.19.1 | with the work |
| ------- | ------- | ------------- |
| 400,000 | 537 MB | 359 MB |
| 1,000,000 | 1248 MB | 208 MB |
| 1,200,000 | killed | 241 MB |

Under a hard 600 MiB cap, 600,000 entries in one directory fails on v0.19.1 and
succeeds with the work; 1,200,000 succeeds under 400 MiB.

The prediction held on the real host: elka, 940,544 files / 51.6 GiB, backed up at
a peak of 272 MB heap / 325 MB total, against 540-683 MB for the runs that were
killed. Docker had predicted 250-350 MB.
