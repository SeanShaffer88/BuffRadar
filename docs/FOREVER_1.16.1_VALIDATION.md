# BuffRadar 1.16.1 — release verification

- **Artifact:** `BuffRadar-1.16.1-Forever.zip` · 1,281,395 bytes
- **Candidate SHA-256:** `7f874c4eb5fb856a38f68f561bbca05223e865c80004637b2b0c2e580fe1088d`
- **Source:** `v1.16.1`
- **POSIX package:** built and verified locally and in PR CI with the 1.16.1 tag.
- **Windows parity:** passed in [PR #59 CI run 44607301038](https://github.com/SeanShaffer88/BuffRadar/actions/runs/44607301038); Windows and POSIX package digests match.
- **In-game field test:** **Unverified**. No post-fix game session has been run.

The release workflow verifies the hosted ZIP and `SHA256SUMS.txt` against the
packaged bytes. Follow the 1.16.1 steps in
[`FOREVER_RELEASE_CHECKLIST.md`](FOREVER_RELEASE_CHECKLIST.md) before marking
the cast-tracking behavior field-tested.
