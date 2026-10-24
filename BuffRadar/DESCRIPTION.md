# BuffRadar — Retail edition

**A click-to-buff list for World of Warcraft — Retail (patch 12.1.5).**

Store-listing copy prepared 2026-10-24 from the shipped 1.3.2
README.

---

Keeping a raid buffed shouldn't mean scanning forty unit frames.
BuffRadar shows one small window: every nearby player who is missing
one of *your* buffs, with their portrait, class-colored name and icons
of exactly what they still need. Click a name to buff them — or press
one key (or one macro) to buff the next person on the list. You always
come first, and because retail raid buffs apply to the whole party or
raid, one click usually clears several rows at once.

## Why you'll like it

- **One list, no hunting.** Players stay listed until your buff is on
  them, then drop off. The window is anchored by its top-left corner,
  so it grows downward without jumping around your screen.
- **It knows your class.** Covers Blizzard's player-cast raid buffs:
  Arcane Intellect, Battle Shout, Power Word: Fortitude, Mark of the
  Wild, Skyfury, Blessing of the Bronze, plus self and situational
  buffs like Earth Shield — offered to one tank at a time, since it
  can sit on only one player. Expiring buffs are re-offered; Battle
  Shout and Blessing of the Bronze, which only reach you and your
  group, are never offered to strangers and are skipped while on
  cooldown.
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
- **Yours to tune.** A tabbed settings window with hover help on
  every setting, per-buff toggles and rebuff thresholds, a resizable
  window, role ordering, a realm-aware right-click ignore list, cast
  statistics for the session and all-time — and a German translation
  of the main window on German clients (settings are English for
  now).

## How to use it

1. Move the `BuffRadar` folder into your retail `Interface\AddOns`
   folder and restart the game.
2. **Turn on friendly nameplates** (Shift+V, or `/br plates`) — that's
   how BuffRadar sees players outside your group.
3. Click a name to buff them, bind *Cast next buff*, or type
   `/br macro` and drop the macro on an action bar.
   `/br config` opens settings; `/br` shows or hides the window.

Good to know: the game freezes click-to-cast changes during combat,
so the list pauses until combat ends; addons can't check line of
sight in advance; and Midnight removed the "load out-of-date addons"
option, so this edition loads only on patch 12.1.5 (Interface
120105) — a new patch needs a new build.

A separate Forever edition (Interface 16001) exists for that client;
since 1.3.2 the two editions are built from the same source and share
the same settings layout.

BuffRadar is by Malikor, GPLv3. Casting approach and buff coverage
were informed by BuffYou by datdata (MIT).

**Status note:** 1.3.2 is built but not yet verified in a retail
client.
