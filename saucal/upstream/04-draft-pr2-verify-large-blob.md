<!-- POST AS: a DRAFT pull request
     TITLE:  repository: Verify a large blob without a second copy of it
     BRANCH: upstream/pr2-verify-large-blob  ->  restic/restic:master  (1 commit, self-contained) -->
<!-- Everything below the next line is the body, verbatim. Replace the #<...> placeholders. -->
<!-- ----------------------------------------------------------------- -->

## What does this PR change? What problem does it solve?

One of three changes measured on #2446. **One commit, self-contained:** it does
not depend on #<pr1> or #<pr3> and can be merged on its own, in any order.

This is the "encrypted variant" term @shtratos identified on #2446 in 2019 and
#3773 named but did not address. It is independent of #21943 too — it helps any
large blob, not only a wide directory's tree.

`verifyCiphertext` decrypted and decompressed the blob it had just sealed and
rehashed it, holding the whole plaintext a second time to do so. For a large tree
blob — the tree of a directory with a million entries runs to several hundred
megabytes — that doubled the cost of saving it at exactly the moment the first copy
was still live.

Above 16 MiB uncompressed, this hashes the plaintext as it decompresses instead.
What gets verified does not change; only the copy is gone. Below the threshold
nothing changes, since setting up a streaming decoder is not free and
decompressing the whole blob is the cheaper way round.

Since this is the last check before a blob is uploaded, a version of it that always
passed would be worse than none. `TestVerifyCompressedCatchesCorruption` checks
that the streaming path rejects a wrong id, a bit flipped at three different
offsets, a truncated stream, and input that was never compressed.

Measured on a backup of one directory of a million entries, peak RSS falls from
773 MB to 603 MB. Disabling verification entirely reaches 592 MB, so almost all of
the difference was the copy.

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

#2446.
