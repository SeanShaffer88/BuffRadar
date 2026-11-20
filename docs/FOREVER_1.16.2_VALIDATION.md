# BuffRadar 1.16.2 — release verification

- **Artifact:** `BuffRadar-1.16.2-Forever.zip` · 1,282,441 bytes
- **Published SHA-256:** `66829bdf7630ea55700963d100f26980041bb613ef3f0106271b76c989648cdf`
- **Source:** `v1.16.2`. All 32 files in the published ZIP match the tagged blobs.
- **Local build note:** a package built from a Windows checkout with
  `core.autocrlf=true` contains CRLF text and hashes differently
  (`71d094ad…`). Build release candidates from LF text (CI, or a checkout
  with `core.autocrlf=false`) to reproduce the published bytes.
- **Windows gate:** `tools/check.ps1` passed (real luacheck 0 warnings / 0 errors; trial run in all 7 setups).
- **In-game field test:** **Unverified**. No game session has been run with the fix.

The release workflow verifies the hosted ZIP and `SHA256SUMS.txt` against the
packaged bytes. Follow the 1.16.2 steps in
[`FOREVER_RELEASE_CHECKLIST.md`](FOREVER_RELEASE_CHECKLIST.md): log out fully,
log back in and use the macro without remaking it, before marking the macro
behavior field-tested.
