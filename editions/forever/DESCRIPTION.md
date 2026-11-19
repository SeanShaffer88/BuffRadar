# BuffRadar

**A click-to-buff list for World of Warcraft: Forever.**

Forever package · Interface 16001

---

Keeping a group buffed shouldn't mean scanning forty unit frames.
BuffRadar shows one small window: every nearby player who is missing
one of *your* buffs, with their portrait, class-colored name and icons
of exactly what they still need. Click a name to buff them — or press
one key (or one macro) to buff the next person on the list. You always
come first.

## Why you'll like it

- **One list, no hunting.** Players stay listed until every buff you
  can cast that suits their class is on them, then drop off. The
  list scrolls when more targets are available than fit on your screen.
- **It knows your class.** Arcane Intellect only goes to mana users,
  Thorns to melee, Fear Ward to warriors. Paladins lead with Blessing
  of Kings when they know it, with Might and Wisdom as fallbacks.
  Group versions count as buffed, expiring buffs are re-offered, and
  spells on cooldown are skipped.
- **Group casts, offered.** When enough of your party or raid needs
  the same buff and the group spell is eligible, BuffRadar offers the
  group version. Otherwise it offers the eligible single-target spell.
- **Honest about what it can see.** Addons get no list of nearby
  players, so BuffRadar finds people through your group, your target,
  your mouseover and friendly nameplates. If nameplates are off, it
  tells you so (and warns at login) instead of claiming everyone is
  buffed — `/br debug` shows exactly what it can see.
- **Stays out of the way.** Pauses in major cities, optional
  battleground pause, party/raid-only mode, autohide, a minimap
  button, and a water-droplet alert (mutable, or swapped for a system
  sound or silence) when someone new needs a buff. Buffing your group
  doesn't even change your target.
- **Yours to tune.** A tabbed settings window (Window / Alerts /
  Buffs / Behavior / Ignore & Stats / Readiness) with hover help on every
  setting, per-buff toggles and rebuff thresholds, a resizable
  window, role ordering, a realm-aware right-click ignore list, cast
  statistics for the session and all-time — and a German translation
  of the main window on German clients (settings are English for
  now).

## What's new in 1.16.0

Review a paste before applying settings or plans. Plans stay local unless
an authorised player chooses to share them, and importing a named profile
no longer risks replacing a save without showing the collision. The list
fits shorter viewports; Settings and Ready Check positions can be remembered
separately with `/br positions on`.

## Readiness

Choose your role and activity in Quick Setup, see what needs attention on the
minimap, and review consumables, Healthstones in bags, and gear durability in
Personal readiness. Optional forecasts warn about readable buff expirations.
Watched debuffs show stacks separately from the cast queue. Lite mode pauses
optional checks while keeping the main queue.

## How to use it

1. Move the `BuffRadar` folder into your Forever
   `Interface\AddOns` folder and restart the game.
2. **Turn on friendly nameplates** (Shift+V, or `/br plates`) — that's
   how BuffRadar sees players outside your group.
3. Click a name to buff them, bind *Cast next buff*, or type
   `/br macro` and drop the macro on an action bar.
   `/br config` opens settings; `/br` shows or hides the window.

Good to know: the game freezes click-to-cast changes during combat,
so the list pauses until combat ends; and addons can't check line of
sight in advance.

BuffRadar is by Malikor, GPLv3. Casting approach and buff coverage
were informed by BuffYou by datdata (MIT). Since 1.3.2 the Forever
and Retail editions are built from the same source; **from 1.8.0
BuffRadar is Forever-only** — Retail support ended at 1.7.0.

**Verification:** Field-tested through 1.15.33. The 1.16.0 release passes
automated checks; live casting, layout and chat behavior are **Unverified**
on this build.
