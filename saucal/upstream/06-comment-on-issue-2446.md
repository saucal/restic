<!-- COMMENT on https://github.com/restic/restic/issues/2446. Post last: it links the PRs above. -->

Some data and patches for this, from backing up WordPress sites.

WordPress puts every upload and its generated thumbnails (core sizes plus any registered by the theme and plugins) in a flat `wp-content/uploads/YYYY/MM/` directory. Busy sites reach tens or hundreds of thousands of files per directory without anyone choosing that layout, and the files are addressed by URL, so they can't be moved. The case that brought me here is a 1.14M-file directory (51 GiB) on a host that kills processes at about 680 MB.

Memory depends on per-directory width, not total file count. On 0.19.1, the same 400,000 files take 537 MB in one directory and 77 MB as 400 directories of 1000. One directory of 1M entries takes 1248 MB.

| PR | change | 1M entries |
|---|---|---|
| | 0.19.1 | 1248 MB |
| #<pr1> | fold finished entries into the tree during the walk | 773 MB |
| #<pr2> | verify large blobs while decompressing, without a second copy | 603 MB |
| #<pr3> | write wide trees through a temp file | 208 MB |

#<pr1> and #<pr2> are self-contained and ready for review. #<pr3> is a draft containing all three; it overlaps #21943 and I'd expect chunked trees to replace it, so whether it's worth carrying meanwhile is your call.

I'd rather help with the chunked-tree work than maintain a fork. If parts of it can be split off (porting call sites, tests, measuring very wide directories), I have time to take them on following your design. I'm an engineer but not a Go developer, and I work with an AI assistant.
