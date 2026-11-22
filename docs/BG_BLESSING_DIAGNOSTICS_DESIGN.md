# Battleground and Blessing Diagnostics Design

Approved before implementation. Examples are illustrative local output, not
player data or a claim about the reported clients.

```text
/br why NearbyPaladin
Context: battleground | BG pause: Off | Current blocker: none
Player: combat=No | PvP flag=Yes
NearbyPaladin: combat=No | PvP flag=Yes | PvP filter=allowed
Detected blessings (cached): Kings, Might, Wisdom | Spellbook entries: 3
Preferred blessing: Kings | Source: Built-in class priority
Effective blessing: Wisdom | Complement another Paladin
Complement: On, nearby | Kings owner=another Paladin | Wisdom available
[existing missing-buff/range/row explanation]

When paused:
BG pause is enabled. Buff needs below are separate from this pause.

When evidence is unavailable:
Player combat/PvP state is unavailable; eligibility cannot be confirmed.
Blessing ownership is unavailable; an alternative cannot be confirmed.

/br support
context.instance=pvp
settings.pauseInBG=false
pause.blocker=none
player.combat=false
player.pvp=true
blessings.cacheReady=true
blessings.detected.KINGS=true
blessings.detected.MIGHT=true
blessings.detected.WISDOM=true
blessings.ranks.MIGHT=1
```

Core owns live context, cached blessing-knowledge snapshots, selection trace
metadata, and an isolated diagnostic-read scope for aura tables and scan markers.
Pause and selection explanations use the existing decisions and preserve existing
return values. Reading diagnostics must not rebuild scans, change queue/coverage,
write settings, create coordination sessions, or send messages.

Support retains its bounded primitive allowlist and 16 KiB limit. Only fixed
enums, validated booleans and bounded numbers are added: pause preferences,
instance type, blocker, player combat/PvP/dead state, cache readiness and six
fixed blessing families with detection/rank counts. No player/caster names,
zone text, labels, saved free text, macros, or raw errors are serialized.

Why prints global context before matching a recipient, distinguishes preferred
from effective blessing, and explains precedence and complement suppression.
Missing data stays unknown. Cache detection is not a definitive unlearned-spell
claim when discovery is unavailable. Local target-name explanations retain their
existing local-chat scope. Exceptions restore all isolated state and use a
generic error message.
