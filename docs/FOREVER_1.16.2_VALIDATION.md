# BuffRadar 1.16.2 — release verification

- **Artifact:** `BuffRadar-1.16.2-Forever.zip` · 1,283,575 bytes
- **Candidate SHA-256:** `71d094ad2997f47fe6d3ac9b5d87e36871b18879bc15073d15a8859d3811e0c6`
- **Source:** `v1.16.2`
- **POSIX package:** built and verified locally from the release source.
- **Windows gate:** `tools/check.ps1` passed (real luacheck 0 warnings / 0 errors; trial run in all 7 setups).
- **In-game field test:** **Unverified**. No game session has been run with the fix.

The release workflow verifies the hosted ZIP and `SHA256SUMS.txt` against the
packaged bytes. Follow the 1.16.2 steps in
[`FOREVER_RELEASE_CHECKLIST.md`](FOREVER_RELEASE_CHECKLIST.md): log out fully,
log back in and use the macro without remaking it, before marking the macro
behavior field-tested.
