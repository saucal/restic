# Text to post upstream

Post in file order. Each file is the body only; its HTML-comment header gives what to post it as, the title and the branch.

| # | post as | contains |
|---|---|---|
| 01 | PR, ready | PR1 — self-contained |
| 02 | PR, ready | PR2 — self-contained |
| 03 | **draft** PR | PR3 — **carries PR1 + PR2** plus the spill |
| 04 | new issue | preallocation hang |
| 05 | PR, ready | PR4 — self-contained, closes 04 |
| 06 | comment on #2446 | links 01–03; posted last |

Replace placeholders as numbers are assigned: `#<pr1>`, `#<pr2>`, `#<pr3>`, `#<issue>`. Each only refers to something posted earlier.

Before pushing each branch, rename its changelog placeholder and fix the URL on its last line: PR1 keeps `issue-2446`; PR2 `pull-99996` → `pull-<n>`; PR3 `pull-99995` → `pull-<n>`; PR4 `pull-99999` → `issue-<n>`.
