-- Spell IDs (every rank, lowest first), artwork paths and colours.
local _, ns = ...

local Data = {}
ns.Data = Data

Data.MEDIA = "Interface\\AddOns\\Sigil\\Media\\"
Data.MACRO_NAME = "SigilAttack"

Data.spells = {
  judgement     = { 20271 },
  holy_strike   = { 679, 678, 1866, 680, 2495, 5569, 10332, 10333 },
  exorcism      = { 879, 5614, 5615, 10312, 10313, 10314, 415068, 415069, 415070, 415071, 415072, 415073 },
  how           = { 24275, 24274, 24239 },
  consecration  = { 26573, 20116, 20922, 20923, 20924 },
  hoj           = { 853, 5588, 5589, 10308 },
  command       = { 20375, 20915, 20918, 20919, 20920 },
  righteousness = { 20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293 },
  wisdom        = { 20166, 20356, 20357 },
  light         = { 20165, 20347, 20348, 20349 },
  crusader      = { 21082, 20162, 20305, 20306, 20307, 20308 },
  justice       = { 20164 },
  fury          = { 1311649, 1311656, 20163, 20419, 20421, 20422, 20423 },
  ret_aura      = { 7294, 10298, 10299, 10300, 10301 },
  might         = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 },
  bow           = { 19742, 19850, 19852, 19853, 19854, 25290 },
}

Data.sealByName = {
  ["Seal of Command"] = "command", ["Seal of Righteousness"] = "righteousness", ["Seal of Wisdom"] = "wisdom",
  ["Seal of Light"] = "light", ["Seal of the Crusader"] = "crusader", ["Seal of Justice"] = "justice", ["Seal of Fury"] = "fury",
}
-- Extra hits that seals cause. They show up as casts but are not seal casts.
Data.SEAL_PROCS = { [20424] = true }
Data.SEALS = { command = true, righteousness = true, wisdom = true, light = true, crusader = true, justice = true, fury = true }
Data.UNSEALED_WRATH = 1310735
-- Buff left behind by each seal under Unsealed Wrath.
Data.echo = { command = 1311703, righteousness = 1311704, fury = 1311701, justice = 1311705, light = 1328198, wisdom = 1328206 }
Data.GCD_SPELL = 29515

-- Cooldowns assumed until the game tells us otherwise.
Data.cooldowns = { judgement = 8, holy_strike = 10, exorcism = 15, how = 6, consecration = 8, hoj = 60 }
Data.OFF_GCD = { judgement = true }

Data.byId = {}
for key, ids in pairs(Data.spells) do
  for _, id in ipairs(ids) do Data.byId[id] = key end
end

Data.label = {
  attack = "Attack", command = "Seal of Command", righteousness = "Seal of Righteousness",
  wisdom = "Seal of Wisdom", consecration = "Consecration", hoj = "Hammer of Justice",
  judgement = "Judgement", holy_strike = "Holy Strike", idle = "",
}
Data.glyph = {
  attack = "glyph_attack", command = "glyph_command", righteousness = "glyph_righteousness",
  wisdom = "glyph_wisdom", consecration = "glyph_consecration", hoj = "glyph_hoj",
  judgement = "glyph_attack", holy_strike = "glyph_attack", idle = "glyph_attack",
  light = "glyph_seal", justice = "glyph_seal", fury = "glyph_seal", crusader = "glyph_seal",
}
Data.color = {
  attack = { 0.91, 0.73, 0.34 }, idle = { 0.55, 0.58, 0.64 },
  command = { 1.00, 0.42, 0.35 }, righteousness = { 1.00, 0.70, 0.28 },
  wisdom = { 0.53, 0.71, 1.00 }, consecration = { 1.00, 0.84, 0.43 },
  hoj = { 0.53, 0.71, 1.00 }, gold = { 0.91, 0.73, 0.34 },
  ink = { 0.93, 0.90, 0.84 }, dim = { 0.55, 0.58, 0.64 }, warn = { 1.00, 0.70, 0.28 },
  light = { 0.93, 0.90, 0.84 }, justice = { 0.93, 0.90, 0.84 }, fury = { 0.93, 0.90, 0.84 }, crusader = { 0.93, 0.90, 0.84 },
}
Data.manaColor = { { 1.00, 0.42, 0.35 }, { 1.00, 0.70, 0.28 }, { 0.53, 0.71, 1.00 } }

Data.defaults = {
  scale = 1, locked = false, showWhy = true, onlyCombat = false,
  consecration = "aoe", recover = "seal", upkeep = true, hojCue = true,
  sound = true, attackKeys = 1, hojInMacro = false, hideErrors = false, weave = true,
}

-- Action slot -> binding name.
function Data.bindingForSlot(slot)
  local i = (slot - 1) % 12 + 1
  if slot <= 24 or (slot >= 73 and slot <= 120) then return "ACTIONBUTTON" .. i end
  if slot <= 36 then return "MULTIACTIONBAR3BUTTON" .. i end
  if slot <= 48 then return "MULTIACTIONBAR4BUTTON" .. i end
  if slot <= 60 then return "MULTIACTIONBAR2BUTTON" .. i end
  if slot <= 72 then return "MULTIACTIONBAR1BUTTON" .. i end
  if slot >= 145 and slot <= 156 then return "MULTIACTIONBAR5BUTTON" .. i end
  if slot >= 157 and slot <= 168 then return "MULTIACTIONBAR6BUTTON" .. i end
  if slot >= 169 and slot <= 180 then return "MULTIACTIONBAR7BUTTON" .. i end
end
