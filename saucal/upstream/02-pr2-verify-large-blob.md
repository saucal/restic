<!-- PULL REQUEST, ready for review. Branch upstream/pr2-verify-large-blob -> restic/restic:master
     Title: repository: Verify a large blob without a second copy of it -->

## What does this PR change? What problem does it solve?

Part of #2446. One commit, self-contained.

Before upload, `verifyCiphertext` decrypts, decompresses and rehashes each blob, holding a second full copy of the plaintext. For a large tree blob (hundreds of MB for a directory of 1M entries) this doubles memory at the peak.

For blobs over 16 MiB uncompressed, this hashes while decompressing instead. What is verified is unchanged. Smaller blobs keep the existing path, which is cheaper for them.

`TestVerifyCompressedCatchesCorruption` checks that the streaming path rejects a wrong id, bit flips at three offsets, a truncated stream, and uncompressed input.

Directory of 1M entries, with #<pr1> applied: 773 MB to 603 MB peak RSS (592 MB with verification disabled entirely). Measured as described in #<pr1>.

> **How this was written:** I'm an engineer, not a Go developer. I use restic to back up WordPress sites, which can hold very large numbers of thumbnails in one directory. An AI assistant wrote this code; it solves my case, but I don't claim it's the right solution, and there are use cases I can't anticipate without Go experience. The numbers are my own measurements; the change passes the existing test suite plus the tests added here, and has run on real backups. Happy to rework it in whatever direction you prefer.

## Was the change previously discussed in an issue or on the forum?

#2446

Checklist
---------

- [x] I have added tests for all code changes, see [writing tests](https://restic.readthedocs.io/en/stable/090_participating.html#writing-tests)
- [ ] I have added documentation for relevant changes (in the manual). *Not applicable: no options or commands change.*
- [x] There's a new file in `changelog/unreleased/` that describes the changes for our users (see [template](https://github.com/restic/restic/blob/master/changelog/TEMPLATE)).
- [x] I'm done! This pull request is ready for review.
