-- BuffRadar - Data: buff tables, class sets, blessings, presets and themes.
-- Loaded FIRST through the .toc; everything lives on the shared namespace
-- table X so BuffRadar.lua (loaded next) can alias what it needs without
-- spending its own main-chunk locals (Lua 5.1 caps them at 200).
-- Copyright (C) 2026 Malikor. GPLv3 or later.

local _, NS = ...
NS = NS or {}
local X = NS.X or {}
NS.X = X

-- Edition, picked at load from the client's interface version: the
-- Forever client reports 16001, retail 120105 and up. One source serves
-- both; each edition's zip differs only in its .toc and docs. CLASSIC_FEATURES (true
-- on Forever) turns on spell ranks, group versions of buffs (Prayer of
-- Fortitude, ...) and paladin blessings; on retail their settings, commands
-- and cast modes ("id", "rank") are hidden and that code stays inert.
local CLASSIC_FEATURES
do
  local ok, _, _, _, iface = pcall(GetBuildInfo)
  iface = ok and tonumber(iface) or 0
  CLASSIC_FEATURES = iface > 0 and iface < 100000
end
X.classic = CLASSIC_FEATURES

---------------------------------------------------------------------------
-- Buff data. Edit freely.
--   id/name : rank-1 spell id (used to get the localized name) + English fallback
--   also    : other spells that count as "already has it" (group / greater versions)
--   classes : which classes actually benefit
--   on      : enabled by default (toggle in game with /br toggle KEY)
---------------------------------------------------------------------------
-- Fields:
--   key      settings key (/br toggle KEY, or the checkboxes in /br config)
--   id/name  spell to cast (rank-1 id gives the localized name; English fallback)
--   choices  instead of id/name: alternatives in priority order; the first one you know
--            is cast, and ANY of them already on the target counts as "has it"
--   also     other auras that count as "has it" (group / greater versions)
--   classes  who benefits (ignored for self-only buffs)
--   role     only players with this assigned group role ("TANK", ...); players
--            with no assigned role (strangers, unassigned) fall back to classes
--   self    true = can only be cast on yourself (shown on your own row)
--   groupOnly true = only reaches you and your party/raid (e.g. Battle Shout):
--            players outside your group are never listed for it
--   single   true = yours can sit on only one other player at a time (Earth
--            Shield): while it's on someone, nobody else is listed for it
--   who      short label for the settings window
--   on       enabled by default
-- Class sets and buff tables live on X (aliases are declared in BuffRadar.lua).
local ALL, MANA, MELEE, TANKS, BUFF_DEFS, AURA_DEFS
if not CLASSIC_FEATURES then
  -- Retail edition: all thirteen classes. (The Forever edition lists nine.)
  ALL = { WARRIOR=true, PALADIN=true, HUNTER=true, ROGUE=true, PRIEST=true,
                 SHAMAN=true, MAGE=true, WARLOCK=true, DRUID=true,
                 DEATHKNIGHT=true, MONK=true, DEMONHUNTER=true, EVOKER=true }
  -- Retail mana users: hunters use focus, so they drop off this list; evokers and
  -- monks (Mistweaver) join it.
  MANA = { PALADIN=true, PRIEST=true, SHAMAN=true, MAGE=true,
                 WARLOCK=true, DRUID=true, MONK=true, EVOKER=true }

  MELEE = { WARRIOR=true, ROGUE=true, PALADIN=true, SHAMAN=true, DRUID=true,
                  DEATHKNIGHT=true, MONK=true, DEMONHUNTER=true }
  TANKS = { WARRIOR=true, PALADIN=true, DRUID=true, DEATHKNIGHT=true,
                  MONK=true, DEMONHUNTER=true }

  -- Retail edition buff set. Retail has no spell ranks and no separate group
  -- versions: casting a raid buff on one group member applies it to the whole
  -- party/raid in range, so the per-person list simply clears as the aura lands.
  -- Blizzard's own list of player-cast long-term raid buffs (hotfix notes,
  -- 2026-04-03): Mark of the Wild, Arcane Intellect, Battle Shout, Power Word:
  -- Fortitude, Skyfury, Source of Magic, Symbiotic Relationship, Blessing of
  -- the Bronze. Source of Magic and Symbiotic Relationship are deliberately NOT
  -- here: each can sit on only ONE player per caster, so everyone else would
  -- show as "missing" forever. Battle Shout and Blessing of the Bronze are
  -- groupOnly: they can't be given to players outside your group, so listing
  -- strangers for them would also leave those strangers "missing" forever.
  -- Spells from the Forever edition that retail removed (mage armors, Divine
  -- Spirit, Fear Ward, Inner Fire, blessings, ...) are gone too — BuffRadar
  -- only ever offers spells found in your spellbook, so they could never fire.
  BUFF_DEFS = {
    -- Mage
    { key="ARCANE_INTELLECT", id=1459,  name="Arcane Intellect",
      also={}, classes=MANA, pets=true, who="mana users", on=true },
    -- Warrior (new in the retail edition: warriors have no buffs in Forever)
    { key="BATTLE_SHOUT",     id=6673,  name="Battle Shout",
      also={}, classes=ALL, groupOnly=true, who="you & your group", on=true },
    -- Priest
    { key="FORTITUDE",        id=1243,  name="Power Word: Fortitude",
      also={}, classes=ALL, pets=true, who="everyone", on=true },
    -- Druid
    { key="MARK_OF_THE_WILD", id=1126,  name="Mark of the Wild",
      also={}, classes=ALL, pets=true, who="everyone", on=true },
    { key="THORNS",           id=467,   name="Thorns",
      also={}, classes=MELEE, who="melee classes (PvP talent)", on=false },
    -- Shaman. Skyfury is NOT groupOnly: it's cast on a target ally, and only
    -- spreads to the whole party/raid when that ally is in your group, so
    -- players outside the group can receive it too.
    { key="SKYFURY",          id=462854, name="Skyfury",
      also={}, classes=ALL, who="everyone", on=true },
    { key="SHAMAN_SHIELD", self=true, who="you", on=true,
      choices={ {52127, "Water Shield"}, {324, "Lightning Shield"} } },
    -- Earth Shield sits on one other player at a time (plus yourself with
    -- Elemental Orbit, which BuffRadar doesn't count): single.
    { key="EARTH_SHIELD",     id=974,   name="Earth Shield",
      also={}, classes=TANKS, role="TANK", single=true, who="tanks", on=false },
    -- Evoker (new in the retail edition)
    { key="BLESSING_OF_THE_BRONZE", id=381732, name="Blessing of the Bronze",
      also={}, classes=ALL, groupOnly=true, who="you & your group", on=true },
    -- Warlock
    { key="UNENDING_BREATH",  id=5697,  name="Unending Breath",
      also={}, classes=ALL, who="everyone (situational)", on=false },
  }
else
  -- Forever edition (1.2.4 tables, unchanged): nine classes, spell ranks,
  -- group versions of buffs, paladin blessings (see BLESSINGS below).
  ALL = { WARRIOR=true, PALADIN=true, HUNTER=true, ROGUE=true, PRIEST=true,
                 SHAMAN=true, MAGE=true, WARLOCK=true, DRUID=true }
  MANA = { PALADIN=true, HUNTER=true, PRIEST=true, SHAMAN=true, MAGE=true,
                 WARLOCK=true, DRUID=true }

  MELEE = { WARRIOR=true, ROGUE=true, PALADIN=true, SHAMAN=true, DRUID=true }
  TANKS = { WARRIOR=true }

  BUFF_DEFS = {
    -- Mage
    { key="ARCANE_INTELLECT", id=1459,  name="Arcane Intellect",
      also={ {23028, "Arcane Brilliance"} }, groupCast={ 23028, "Arcane Brilliance" },
      classes=MANA, pets=true, who="mana users", on=true },
    { key="MAGE_ARMOR", self=true, who="you", on=true,
      choices={ {30482, "Molten Armor"}, {6117, "Mage Armor"}, {7302, "Ice Armor"}, {168, "Frost Armor"} } },
    { key="DAMPEN_MAGIC",     id=604,   name="Dampen Magic",
      also={}, classes=ALL, who="everyone (situational)", on=false },
    { key="AMPLIFY_MAGIC",    id=1008,  name="Amplify Magic",
      also={}, classes=ALL, who="everyone (situational)", on=false },
    -- Priest
    { key="FORTITUDE",        id=1243,  name="Power Word: Fortitude",
      also={ {21562, "Prayer of Fortitude"} }, groupCast={ 21562, "Prayer of Fortitude" },
      classes=ALL, pets=true, who="everyone", on=true },
    { key="DIVINE_SPIRIT",    id=14752, name="Divine Spirit",
      also={ {27681, "Prayer of Spirit"} }, groupCast={ 27681, "Prayer of Spirit" },
      classes=MANA, who="mana users", on=true },
    { key="FEAR_WARD",        id=6346,  name="Fear Ward",
      also={}, classes=TANKS, who="warriors", on=true },
    { key="INNER_FIRE",       id=588,   name="Inner Fire",
      self=true, also={}, who="you", on=true },
    { key="SHADOW_PROT",      id=976,   name="Shadow Protection",
      also={ {27683, "Prayer of Shadow Protection"} }, groupCast={ 27683, "Prayer of Shadow Protection" },
      classes=ALL, who="everyone (situational)", on=false },
    -- Druid
    { key="MARK_OF_THE_WILD", id=1126,  name="Mark of the Wild",
      also={ {21849, "Gift of the Wild"} }, groupCast={ 21849, "Gift of the Wild" },
      classes=ALL, pets=true, who="everyone", on=true },
    { key="THORNS",           id=467,   name="Thorns",
      also={}, classes=MELEE, who="melee classes", on=true },
    -- Shaman
    { key="SHAMAN_SHIELD", self=true, who="you", on=true,
      choices={ {24398, "Water Shield"}, {324, "Lightning Shield"} } },
    { key="EARTH_SHIELD",     id=974,   name="Earth Shield",
      also={}, classes=TANKS, who="warriors", on=false },
    { key="WATER_BREATHING",  id=131,   name="Water Breathing",
      also={}, classes=ALL, who="everyone (situational)", on=false },
    -- Warlock
    { key="WARLOCK_ARMOR", self=true, who="you", on=true,
      choices={ {28176, "Fel Armor"}, {706, "Demon Armor"}, {687, "Demon Skin"} } },
    { key="UNENDING_BREATH",  id=5697,  name="Unending Breath",
      also={}, classes=ALL, who="everyone (situational)", on=false },
    { key="DETECT_INVIS", classes=ALL, who="everyone (situational)", on=false,
      choices={ {11743, "Detect Greater Invisibility"}, {2970, "Detect Invisibility"},
                {132, "Detect Lesser Invisibility"} } },
  }

  -- Aura / aspect watch (1.8.0): self-only stances that work like the
  -- self buffs above, but live apart because they're a watch you turn on
  -- separately (/br aura). Any one of the choices counts as "it's up".
  AURA_DEFS = {
    { key = "HUNTER_ASPECT", who = "you (aspect)",
      choices = { {13165, "Aspect of the Hawk"}, {13163, "Aspect of the Monkey"},
                  {5118, "Aspect of the Cheetah"}, {13159, "Aspect of the Pack"},
                  {20043, "Aspect of the Wild"}, {13161, "Aspect of the Beast"} } },
    { key = "PALADIN_AURA", who = "you (aura)",
      choices = { {465, "Devotion Aura"}, {7294, "Retribution Aura"},
                  {19746, "Concentration Aura"}, {20218, "Sanctity Aura"},
                  {19876, "Shadow Resistance Aura"}, {19888, "Frost Resistance Aura"},
                  {19891, "Fire Resistance Aura"} } },
  }
end

X.ALL, X.MANA, X.MELEE, X.TANKS, X.BUFF_DEFS, X.AURA_DEFS =
  ALL, MANA, MELEE, TANKS, BUFF_DEFS, AURA_DEFS

-- Paladin: only one of YOUR blessings can sit on a player, so each class gets the
-- first blessing in its list that you know. Kings leads every list: it buffs all
-- stats, so a paladin who knows it wants it on everyone. Might/Wisdom are only
-- fallbacks for paladins who don't know Kings yet. (Before 1.2.3 Kings sat
-- second, behind Might/Wisdom — and since Kings is learned after them, anyone
-- who knew Kings already knew the first entry too, so Kings was never cast.)
X.BLESSINGS = {
  MIGHT     = { id=19740, name="Blessing of Might",     greater={25782, "Greater Blessing of Might"} },
  WISDOM    = { id=19742, name="Blessing of Wisdom",    greater={25894, "Greater Blessing of Wisdom"} },
  KINGS     = { id=20217, name="Blessing of Kings",     greater={25898, "Greater Blessing of Kings"} },
  SALVATION = { id=1038,  name="Blessing of Salvation", greater={25895, "Greater Blessing of Salvation"} },
  LIGHT     = { id=19977, name="Blessing of Light",     greater={25890, "Greater Blessing of Light"} },
  SANCTUARY = { id=20911, name="Blessing of Sanctuary", greater={25899, "Greater Blessing of Sanctuary"} },
}
X.BLESSING_PRIORITY = {
  WARRIOR = { "KINGS", "MIGHT" },
  ROGUE   = { "KINGS", "MIGHT" },
  HUNTER  = { "KINGS", "WISDOM" },   -- Might is melee attack power only
  PALADIN = { "KINGS", "WISDOM", "MIGHT" },
  SHAMAN  = { "KINGS", "WISDOM", "MIGHT" },
  DRUID   = { "KINGS", "WISDOM", "MIGHT" },
  PRIEST  = { "KINGS", "WISDOM" },
  MAGE    = { "KINGS", "WISDOM" },
  WARLOCK = { "KINGS", "WISDOM" },
  -- Retail-only classes. Paladin blessings don't exist on retail, so these
  -- rows never fire there; they keep the table complete over all classes.
  DEATHKNIGHT = { "KINGS", "MIGHT" },
  MONK        = { "KINGS", "WISDOM", "MIGHT" },
  DEMONHUNTER = { "KINGS", "MIGHT" },
  EVOKER      = { "KINGS", "WISDOM" },
}
X.BLESSING_CLASS_ORDER = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
X.BLESSING_CLASSES = {}
for _, class in ipairs(X.BLESSING_CLASS_ORDER) do X.BLESSING_CLASSES[class] = true end
X.BLESSING_KEYS = { "KINGS", "MIGHT", "WISDOM", "SALVATION", "LIGHT", "SANCTUARY" }

-- Shipped presets (1.6.0): one-click window/behavior setups.
X.PRESETS = {
  raid = { sortMode = "role", groupCast = true,
           groupOnly = false, pauseInCities = true },
  dungeon = { sortMode = "need", groupCast = true,
              groupOnly = true, pauseInCities = true },
  solo = { sortMode = "name", groupCast = false,
           groupOnly = false, pauseInCities = false },
}

-- Color themes (1.8.0): a theme is a background color + border color pair.
X.THEMES = {
  midnight  = { label = "Midnight",  bg = { 0.04, 0.05, 0.09 }, border = { 0.35, 0.55, 0.8 } },
  crimson   = { label = "Crimson",   bg = { 0.08, 0.02, 0.02 }, border = { 0.75, 0.2, 0.2 } },
  forest    = { label = "Forest",    bg = { 0.02, 0.07, 0.03 }, border = { 0.3, 0.7, 0.35 } },
  parchment = { label = "Parchment", bg = { 0.13, 0.11, 0.07 }, border = { 0.8, 0.7, 0.45 } },
}
X.THEME_ORDER = { "midnight", "crimson", "forest", "parchment" }
