# BuffRadar

**A click-to-buff list for World of Warcraft: Forever.**

Store-listing copy prepared 2026-10-24 from the shipped 1.3.2
Forever README.

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
  window is anchored by its top-left corner, so it grows downward
  without ever jumping around your screen.
- **It knows your class.** Arcane Intellect only goes to mana users,
  Thorns to melee, Fear Ward to warriors. Paladins lead with Blessing
  of Kings when they know it, with Might and Wisdom as fallbacks.
  Group versions count as buffed, expiring buffs are re-offered, and
  spells on cooldown are skipped.
- **Group casts, offered.** When enough of your party or raid needs
  the same buff, BuffRadar offers the group version instead — one
  cast for everyone.
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
  Buffs / Behavior / Ignore & Stats) with hover help on every
  setting, per-buff toggles and rebuff thresholds, a resizable
  window, role ordering, a realm-aware right-click ignore list, cast
  statistics for the session and all-time — and a German translation
  of the main window on German clients (settings are English for
  now).

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

**Status note:** 1.8.0 is built but not yet verified in game (1.7.0,
1.6.0, 1.5.0, 1.4.0 and 1.3.2 are likewise unverified); 1.2.2
was the last version confirmed live (by SEAN, 2026-10-20).
