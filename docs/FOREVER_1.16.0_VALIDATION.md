# BuffRadar 1.16.0 — release verification

- **Artifact:** `BuffRadar-1.16.0-Forever.zip` · 1,280,608 bytes
- **SHA-256:** `0d2e610f4129b91be229a8bff6fe33d1274919174e0217a139f75eeeb5aa82db`
- **Target:** WoW: Forever, Interface 16001 · SavedVariables schema 23
- **Source:** [`v1.16.0`](https://github.com/SeanShaffer88/BuffRadar/tree/v1.16.0)

1.16.0 publishes the runtime changes from the unpublished 1.15.38 audit
candidate. It is a new ZIP; do not use the candidate's checksum or carry over
its field-test status. The [audit ledger](AUDIT_1.15.38.md) explains the runtime
changes and their limits.

| Check | Evidence |
|---|---|
| Local Lua 5.1 gate | Passed: compile, advisory limits, German keys and format checks, pattern check, 2,802 smoke steps across seven setups, 22 two-client coordination scenarios, and seven packaging tests. |
| Local Luacheck 1.2.0 | Passed with Lua 5.1.5: zero warnings or errors across 22 addon and locale files. |
| Local release build | Two byte-identical ZIPs and checksum files. Exact `--tag v1.16.0` check, matching changelog section, source-aware verification of all 32 files, 22 TOC entries, four bindings, and `/br selftest` version/edition. |
| Windows/POSIX package parity | See the [release preparation CI runs](https://github.com/SeanShaffer88/BuffRadar/actions/workflows/ci.yml?query=branch%3Aarena%2F6447ba6f-buffradar) for the `windows-package` digest comparison. The full local Windows `tools/check.ps1` gate was not run. |
| Tagged package and hosted readback | See the [tagged Release run](https://github.com/SeanShaffer88/BuffRadar/actions/workflows/release.yml?query=branch%3Av1.16.0) and [published assets](https://github.com/SeanShaffer88/BuffRadar/releases/tag/v1.16.0). The release workflow verifies the matching tag and then compares the downloaded ZIP and `SHA256SUMS.txt` to the build. |
| Live WoW: Forever field test | **Unverified**. The fake client and package checks do not exercise real protected actions, rendering, restricted aura data, latency or server chat delivery. |

## Verify the download

Download the ZIP and `SHA256SUMS.txt` from the same GitHub release. In their
folder run `sha256sum -c SHA256SUMS.txt`, or compare `Get-FileHash -Algorithm
SHA256 BuffRadar-1.16.0-Forever.zip` to the digest above in PowerShell. Install
only the matching ZIP into `Interface/AddOns`, then confirm `/br selftest`
reports **1.16.0 · Forever edition · interface 16001** and schema 23.

## Field handoff

Run the [audit field scenarios](FOREVER_1.15.38_VALIDATION.md#forever-field-pass--pending)
against the exact **1.16.0** ZIP above, substituting its version and hash for the
1.15.38 candidate in the install check. Also run the applicable
[Forever release checklist](FOREVER_RELEASE_CHECKLIST.md) steps. Record tester,
client build/interface and locale, resolution and UI scale, roster size, ZIP
hash, and outcomes. The priority checks are:

- Save upgrade and non-destructive future/overflow recovery with backed-up data.
- BR1, BR2 and plan review, cancellation, replacement and scope drift.
- Row, keybind, macro, modifier and group/pet casts through combat, death and roster changes.
- Short viewports, Settings and Ready Check positions, Nearby closure and German layout.
- Confirmed versus unknown aura/coating data, pull cancellation, chat routing, and `/br perf` in a raid.

Mark individual checks verified only after running them on this artifact.
