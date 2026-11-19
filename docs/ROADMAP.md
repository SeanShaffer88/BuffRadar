# BuffRadar roadmap

This is the public roadmap for BuffRadar on WoW: Forever. Priorities may change
with player feedback and client capabilities. To suggest a feature, use the
[feature request form](https://github.com/SeanShaffer88/BuffRadar/issues/new?template=feature_request.md)
or copy its link in **Settings → Readiness → Feedback** (`/br feedback`).

| Status | Work |
| --- | --- |
| **1.15.38 candidate — offline checks complete** | Safer saves, reviews, cast eligibility and roster cleanup; deterministic Forever candidate. See the [audit ledger](AUDIT_1.15.38.md) and [verification matrix](FOREVER_1.15.38_VALIDATION.md). |
| **1.15.37 — released; live verification pending** | Confirmed buff expiry forecasts, contextual priority, personal readiness, player/focus debuff watches, a read-only status API, Quick Setup, minimap status, quiet visuals, adaptive scans, and Lite mode. |
| **Next: field test in Forever** | Ship only after the applicable checks; Windows package bytes matched in CI. Walk the [release checklist](FOREVER_RELEASE_CHECKLIST.md) on the exact candidate. Check real casts, short viewports, a raid-sized roster, countdowns, chat delivery, combat aura visibility, and scan/memory diagnostics. |
| **Under consideration** | Shareable encounter presets after spell IDs and aura availability are confirmed, more options for placing the debuff strip, and community examples using the [status API](STATUS_API.md). |
| **Waiting on client data** | Confirming that a placed Soulwell is reachable and usable, and automatically predicting upcoming encounter mechanics. BuffRadar does not guess at data the client does not expose. |
