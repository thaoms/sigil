-- Everything that touches the game client. The game hides many values from
-- addons in combat ("secret values"): touching one raises an error, so every
-- read here goes through pcall and is checked before use. A failed read means
-- "unknown", never "false".
local _, ns = ...
local Data, Tracker, Mana = ns.Data, ns.Tracker, ns.Mana

local Game = { known = {}, cost = {}, keys = {}, probes = {}, refused = {}, stats = {} }
ns.Game = Game

local issecret = issecretvalue or function() return false end

-- Never compare a value before this check: comparing a secret is an error.
local function plain(v)
  if issecret(v) then return nil end
  return v
end

-- Reads one field of a table the game returned; nil if it can't be read.
local function field(t, k)
  if type(t) ~= "table" then return nil end
  local ok, v = pcall(function() return t[k] end)
  if ok then return plain(v) end
  return nil
end

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
  return nil
end

local C_Spell, C_SpellBook, C_UnitAuras = C_Spell or {}, C_SpellBook or {}, C_UnitAuras or {}

-- Fight details are only recorded with "Debug log" on in the options.
-- Errors and count mismatches are always recorded.
function Game.log(fmt, ...)
  local db = SigilCharDB
  if not db then return end
  if not db.debug and not (fmt:find("error", 1, true) or fmt:find("drift", 1, true)) then return end
  db.log = db.log or {}
  local ok, line = pcall(string.format, fmt, ...)
  db.log[#db.log + 1] = ("%.1f %s"):format(GetTime and GetTime() or 0, ok and line or fmt)
  if #db.log > 400 then table.remove(db.log, 1) end
end

---------------------------------------------------------------------------
-- Spells the character knows, their costs and which key they are on
---------------------------------------------------------------------------

local function isKnown(id)
  local known = plain(try(C_SpellBook.IsSpellKnown, id))
  if known == nil then known = plain(try(IsSpellKnown, id)) end
  return known == true
end

local function manaCost(id)
  local costs = try(C_Spell.GetSpellPowerCost, id)
  if type(costs) ~= "table" then return nil end
  local found
  pcall(function()
    for _, c in ipairs(costs) do
      local kind, cost = field(c, "type"), field(c, "cost")
      if kind == 0 and cost and cost > 0 then found = cost break end
    end
  end)
  return found
end

function Game.scanSpells()
  for key, ids in pairs(Data.spells) do
    local best
    for _, id in ipairs(ids) do
      if isKnown(id) then best = id end
    end
    Game.known[key] = best
    if best then
      local c = manaCost(best)
      if c then Game.cost[key] = c end
    end
  end
  Game.detectUnsealedWrath()
  Game.buildProbes()
end

-- The game's own icon for one of Sigil's calls.
function Game.icon(id)
  if id == "idle" or id == "attack" then id = Game.known.holy_strike and "holy_strike" or "judgement" end
  local spell = Game.known[id]
  if not spell then return nil end
  return plain(try(C_Spell.GetSpellTexture, spell))
end

function Game.name(key)
  local id = Game.known[key]
  return id and plain(try(C_Spell.GetSpellName, id)) or Data.label[key]
end

-- Unsealed Wrath is a talent; talents don't always answer the "known" check.
function Game.detectUnsealedWrath()
  if isKnown(Data.UNSEALED_WRATH) then Game.unsealedWrath, Game.unsealedWrathHow = true, "spellbook" return end
  local found
  pcall(function()
    local config = C_ClassTalents.GetActiveConfigID()
    local info = C_Traits.GetConfigInfo(config)
    for _, tree in ipairs(info.treeIDs) do
      for _, nodeID in ipairs(C_Traits.GetTreeNodes(tree)) do
        local node = C_Traits.GetNodeInfo(config, nodeID)
        if node and node.entryIDs then
          for _, entryID in ipairs(node.entryIDs) do
            local entry = C_Traits.GetEntryInfo(config, entryID)
            local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
            if def and def.spellID == Data.UNSEALED_WRATH then
              found = (node.ranksPurchased or 0) > 0
            end
          end
        end
      end
    end
  end)
  if found ~= nil then
    Game.unsealedWrath, Game.unsealedWrathHow = found, "talents"
  else
    Game.unsealedWrath, Game.unsealedWrathHow = true, "assumed"
  end
end

-- Spells of different mana cost: which of them the game says we can afford
-- brackets the real (hidden) mana value.
function Game.buildProbes()
  local seen, list = {}, {}
  local function add(id)
    if not id or not isKnown(id) then return end
    local c = manaCost(id)
    if c and not seen[c] then seen[c] = true; list[#list + 1] = { id = id, cost = c } end
  end
  for _, ids in pairs(Data.spells) do
    for _, id in ipairs(ids) do add(id) end
  end
  pcall(function()
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
      local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
      for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
        local item = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
        if item and not item.isPassive then add(plain(item.spellID)) end
      end
    end
  end)
  table.sort(list, function(a, b) return a.cost < b.cost end)
  if #list > 0 then Game.probes = list end
end

function Game.manaLevel()
  local now = GetTime()
  if Game.lastLevel and Game.manaAt and now - Game.manaAt < 0.3 then return Game.lastLevel end
  Game.manaAt = now
  local probes = {}
  for i, p in ipairs(Game.probes) do
    local _, short = try(C_Spell.IsSpellUsable, p.id)
    short = plain(short)
    if short ~= nil then probes[#probes + 1] = { cost = p.cost, affordable = not short } end
  end
  local weave = (Game.cost.command or 0) + (Game.cost.righteousness or Game.cost.command or 0)
  local level, floor, ceiling = Mana.level(probes, { weave = weave, attack = Game.cost.holy_strike or 0 }, Game.lastLevel)
  Game.lastLevel, Game.manaFloor, Game.manaCeiling = level, floor, ceiling
  return level
end

function Game.afford(key)
  local id = Game.known[key]
  if not id then return nil end
  local _, short = try(C_Spell.IsSpellUsable, id)
  short = plain(short)
  if short == nil then return nil end
  return not short
end

-- true when the game says the spell can be cast now (ignoring mana), nil when hidden
-- The game calls every spell unusable during the global cooldown and while
-- casting, so only a reading outside those counts; it stands until the next.
Game.usableSeen = {}
function Game.usable(key)
  local id = Game.known[key]
  if not id then return nil end
  local gcd = field(try(C_Spell.GetSpellCooldown, Data.GCD_SPELL), "isActive")
  local casting = UnitCastingInfo and plain(try(UnitCastingInfo, "player")) ~= nil
  if gcd ~= true and not casting then
    local usable, short = try(C_Spell.IsSpellUsable, id)
    usable, short = plain(usable), plain(short)
    if usable == nil then Game.usableSeen[key] = nil
    else Game.usableSeen[key] = usable == true or short == true end
  end
  return Game.usableSeen[key]
end

-- Hammer of Wrath only works on a low target, and the game's "usable" says
-- so. Sigil trusts that only after seeing it say "no" once on a live
-- target: otherwise a client that always says "yes" would light the mark
-- all fight. Remembered per character. (As the Paladin Toolkit does.)
-- Exorcism works the same way: only on undead and demons.
local GATES = {
  how = { field = "howGate", note = "hammer of wrath: the game says not usable on a healthy target, so usable means low enough" },
  exorcism = { field = "exorcismGate", note = "exorcism: the game says not usable on this target, so usable means undead or demon" },
}
function Game.gatedUsable(key, liveTarget)
  local gate = GATES[key]
  local usable = Game.usable(key)
  if usable == false and liveTarget and not ns.db[gate.field] then
    ns.db[gate.field] = true
    Game.log(gate.note)
  end
  if not ns.db[gate.field] then return nil end
  return usable
end
function Game.howUsable(liveTarget) return Game.gatedUsable("how", liveTarget) end

-- true when off cooldown (the global cooldown doesn't count), nil when unknown
function Game.ready(key)
  local id = Game.known[key]
  if not id then return nil end
  local info = try(C_Spell.GetSpellCooldown, id)
  if type(info) ~= "table" then return nil end
  local active = field(info, "isActive")
  if active == nil then return nil end
  if not active then return true end
  return field(info, "isOnGCD") == true
end

local function keyText(key)
  if not key then return nil end
  key = key:gsub("SHIFT%-", "S-"):gsub("CTRL%-", "C-"):gsub("ALT%-", "A-")
  key = key:gsub("NUMPAD", "N"):gsub("MOUSEWHEELUP", "MwU"):gsub("MOUSEWHEELDOWN", "MwD"):gsub("BUTTON", "M")
  return key
end

-- Which key each of Sigil's buttons sits on, by scanning the action bars.
function Game.scanKeys()
  local found, slots = {}, {}
  for slot = 1, 180 do
    local binding = Data.bindingForSlot(slot)
    if binding then
      local kind, id = try(GetActionInfo, slot)
      kind, id = plain(kind), plain(id)
      local key
      if kind == "macro" then
        local text = plain(try(GetActionText, slot))
        local index = plain(try(GetMacroIndexByName, Data.MACRO_NAME)) or 0
        local spell = type(id) == "number" and Data.byId[id]
        if text == Data.MACRO_NAME or (text == nil and index > 0 and id == index) then
          key = "attack"
        elseif text == nil and index > 0 and (spell == "judgement" or spell == "holy_strike" or spell == "how" or spell == "exorcism") then
          key = "attack"   -- on this client a macro slot reports the spell it will cast
        end
      elseif kind == "spell" and type(id) == "number" then
        key = Data.byId[id]
      end
      if key and not found[key] then
        found[key] = keyText(plain(try(GetBindingKey, binding))) or false
        slots[key] = slot
      end
    end
  end
  Game.keys, Game.slots = found, slots
end

function Game.keyFor(id)
  if id == "attack" then
    if (ns.db and ns.db.attackKeys) == 2 then
      local a, b = Game.keys.judgement, Game.keys.holy_strike
      if a and b then return a .. " " .. b end
      return a or b or nil
    end
    return Game.keys.attack or nil
  end
  return Game.keys[id] or nil
end

---------------------------------------------------------------------------
-- The Attack macro
---------------------------------------------------------------------------

function Game.macroBody()
  -- A fixed icon: without a name the button shows whichever spell is first
  -- in the list.
  local face = Game.known.holy_strike or Game.known.judgement
  local faceName = face and plain(try(C_Spell.GetSpellName, face))
  local lines = { faceName and ("#showtooltip " .. faceName) or "#showtooltip", "/startattack" }
  -- A macro press stops at the first spell that uses the global cooldown and
  -- can't be cast. Live, Hammer of Justice on cooldown kept Holy Strike from
  -- firing. So only spells that are reliably castable go here: Judgement
  -- (off the global cooldown), Holy Strike, and Exorcism last. Hammer of
  -- Justice, Hammer of Wrath (low targets only) and Exorcism (undead and
  -- demons only) are manual keys with marks. Exorcism below Holy Strike
  -- never went off live: Holy Strike either fires or, on cooldown, stops the
  -- press.
  local order = { "judgement", "holy_strike" }
  for _, key in ipairs(order) do
    if Game.known[key] then
      local name = plain(try(C_Spell.GetSpellName, Game.known[key]))
      if name then lines[#lines + 1] = "/cast " .. name end
    end
  end
  return table.concat(lines, "\n")
end

-- Creates or updates the macro. Returns "ok", "combat", "failed" or "none".
function Game.ensureMacro()
  if Game.inCombat or (InCombatLockdown and InCombatLockdown()) then return "combat" end
  local body = Game.macroBody()
  if not body:find("/cast") then return "none" end
  local index = plain(try(GetMacroIndexByName, Data.MACRO_NAME)) or 0
  if index > 0 then
    if plain(try(GetMacroBody, index)) == body then return "ok" end
    local ok = pcall(EditMacro, index, nil, nil, body)
    return ok and "ok" or "failed"
  end
  if not Game.macrosLoaded then return "later" end
  local ok, made = pcall(CreateMacro, Data.MACRO_NAME, "INV_Misc_QuestionMark", body, true)
  if not ok or not made then
    ok, made = pcall(CreateMacro, Data.MACRO_NAME, "INV_Misc_QuestionMark", body, false)
  end
  Game.log("macro create ok=%s result=%s", tostring(ok), tostring(made))
  return (ok and made) and "ok" or "failed"
end

function Game.pickup(id)
  if Game.inCombat then return false end
  pcall(ClearCursor)
  if id == "attack" then
    return (pcall(PickupMacro, Data.MACRO_NAME))
  end
  local spell = Game.known[id]
  if not spell then return false end
  if C_Spell.PickupSpell then return (pcall(C_Spell.PickupSpell, spell)) end
  if PickupSpell then return (pcall(PickupSpell, spell)) end
  return false
end

-- Only "definitely empty" counts: placing onto a full slot would knock the
-- old button off the bar.
local function slotEmpty(slot)
  local ok, kind = pcall(GetActionInfo, slot)
  if not ok or issecret(kind) then return false end
  return kind == nil
end

-- Where the missing buttons would go. Only ever empty slots.
function Game.placementPlan(items)
  local plan, taken = {}, {}
  local function free(slot) return not taken[slot] and slotEmpty(slot) end
  for index, id in ipairs(items) do
    local slot
    if free(index) then
      slot = index
    else
      for s = 1, 12 do if free(s) then slot = s break end end
      if not slot then for s = 61, 72 do if free(s) then slot = s break end end end
    end
    if slot then taken[slot] = true; plan[#plan + 1] = { id = id, slot = slot } end
  end
  return plan
end

function Game.place(plan)
  if Game.inCombat or (InCombatLockdown and InCombatLockdown()) then return 0 end
  local done = 0
  for _, p in ipairs(plan) do
    if slotEmpty(p.slot) and Game.pickup(p.id) then
      local ok = pcall(PlaceAction, p.slot)
      pcall(ClearCursor)
      if ok and not slotEmpty(p.slot) then done = done + 1 end
      Game.log("place %s slot %d ok=%s", p.id, p.slot, tostring(ok))
    end
  end
  Game.scanKeys()
  return done
end

function Game.slotLabel(slot)
  local binding = Data.bindingForSlot(slot)
  local key = binding and keyText(plain(try(GetBindingKey, binding)))
  local i = (slot - 1) % 12 + 1
  local bar = slot <= 12 and "main bar" or (slot >= 61 and slot <= 72) and "bottom left bar" or "bar"
  if key then return ("%s, button %d (key %s)"):format(bar, i, key) end
  return ("%s, button %d"):format(bar, i)
end

---------------------------------------------------------------------------
-- Buffs: readable out of combat only
---------------------------------------------------------------------------

local function aurasReadable()
  if Game.inCombat then return false end
  local secret = try(C_Secrets and C_Secrets.ShouldAurasBeSecret)
  return plain(secret) ~= true
end

local function playerBuff(id)
  local aura = try(C_UnitAuras.GetPlayerAuraBySpellID, id)
  if type(aura) ~= "table" then return nil end
  return aura
end

-- Reads the real seal, stacks and blessing. Returns nil when not readable.
function Game.readBuffs()
  if not aurasReadable() then return nil end
  local real = { seal = false, stacks = 0 }
  for key in pairs(Data.SEALS) do
    for _, id in ipairs(Data.spells[key]) do
      local aura = playerBuff(id)
      if aura then
        real.seal = key
        real.sealExpires = field(aura, "expirationTime")
      end
    end
  end
  for key, id in pairs(Data.echo) do
    local aura = playerBuff(id)
    if aura then
      real.stored = key
      real.stacks = math.max(1, field(aura, "applications") or 1)
      real.stacksExpire = field(aura, "expirationTime")
    end
  end
  real.blessing = false
  pcall(function()
    for i = 1, 40 do
      local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      if not aura then break end
      local name = field(aura, "name")
      if name and (name:find("^Blessing of") or name:find("^Greater Blessing")) then
        real.blessing = true
        real.blessingExpires = field(aura, "expirationTime")
      end
    end
  end)
  if not real.blessing then
    for _, key in ipairs({ "might", "bow" }) do
      for _, id in ipairs(Data.spells[key]) do
        local aura = playerBuff(id)
        if aura then real.blessing, real.blessingExpires = true, field(aura, "expirationTime") end
      end
    end
  end
  return real
end

function Game.syncBuffs()
  local real = Game.readBuffs()
  if not real then return end
  local compare = Game.compareDue
  Game.compareDue = nil
  local now = GetTime()
  local t = Game.tracker
  if compare then
    t:expire(now)
    local stats = Game.stats
    stats.compared = (stats.compared or 0) + 1
    Game.log("after fight: counted %s x%d, real %s x%d, seal counted %s real %s", tostring(t.stored), t.stacks,
      tostring(real.stored), real.stacks, tostring(t.seal), tostring(real.seal))
    if t.stacks ~= real.stacks or (real.stacks > 0 and t.stored ~= real.stored) then
      stats.drifted = (stats.drifted or 0) + 1
      Game.log("drift: counted %s x%d, real %s x%d", tostring(t.stored), t.stacks, tostring(real.stored), real.stacks)
      if stats.drifted == 3 and ns.say then
        ns.say("My stack count has been off after 3 fights. Type /sigil check then /reload so it can be looked at.")
      end
    end
    if (t.seal or false) ~= real.seal then
      Game.log("seal drift: counted %s, real %s", tostring(t.seal), tostring(real.seal))
    end
  end
  t:sync(real, now)
  Game.blessing = real.blessing
  Game.blessingExpires = real.blessing and real.blessingExpires or nil
end

-- Paladin auras are "stances" to the game, readable even in combat.
-- Returns "missing", "wrong" (not the aura picked in options) or nil.
function Game.auraState()
  local count = plain(try(GetNumShapeshiftForms))
  local form = plain(try(GetShapeshiftForm))
  if form == nil then return nil end
  if form ~= 0 then Game.formSeen = true end
  if not Game.formSeen and not (count and count > 0) then return nil end   -- can't tell: don't nag
  if form == 0 then return "missing" end
  local want = ns.db and ns.db.aura
  if not want or want == "any" or not Game.known[want] then return nil end
  local _, _, _, spellID = try(GetShapeshiftFormInfo, form)
  spellID = plain(spellID)
  if not spellID then return nil end
  local active = Data.byId[spellID]
  if not active then
    -- an aura rank not in the ID list: compare by name
    local name = plain(try(C_Spell.GetSpellName, spellID))
    if name == Game.name(want) then return nil end
    return name and "wrong" or nil
  end
  return active ~= want and "wrong" or nil
end

function Game.blessingMissing(now)
  if not (Game.known.might or Game.known.bow) then return nil end
  if Game.blessing == nil then return nil end
  if Game.blessing and Game.blessingExpires and Game.blessingExpires > 0 and now > Game.blessingExpires then
    return true
  end
  return not Game.blessing
end

---------------------------------------------------------------------------
-- Enemies nearby, from nameplates
---------------------------------------------------------------------------

local plates = {}

-- Enemies close to you: alive, attackable, in combat, and within Judgement's
-- range (about 10 yards), so mobs fighting someone else further away don't
-- count. If the game gives no range answer for any of them, falls back to
-- counting every enemy nameplate in combat.
function Game.enemies()
  local near, all, any, ranged = 0, 0, false, false
  local probe = Game.known.judgement or Game.known.hoj
  for unit in pairs(plates) do
    any = true
    if plain(try(UnitExists, unit)) and plain(try(UnitCanAttack, "player", unit))
      and plain(try(UnitAffectingCombat, unit)) and not plain(try(UnitIsDead, unit)) then
      all = all + 1
      local inRange = probe and plain(try(C_Spell.IsSpellInRange, probe, unit))
      if inRange ~= nil then ranged = true end
      if inRange == true then near = near + 1 end
    end
  end
  if not any then return nil end
  if ranged then return near end
  return all
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- The Crusader mark on the target can't be read in combat. Sigil remembers
-- which target it judged with Seal of the Crusader. The mark lasts 40 seconds
-- and your own hits keep refreshing it.
local CRUSADER_LASTS = 40
local function targetId()
  return plain(try(UnitGUID, "target")) or "target"
end
function Game.crusaderDone(now)
  local mark = Game.crusaderMark
  if not mark then return false end
  if now > mark.untilTime or mark.id ~= targetId() then return false end
  return true
end

local MISSES = { MISS = true, DODGE = true, PARRY = true }
local CONSECRATION_MISSES = 2   -- seconds after a Consecration cast when a miss is taken as its own

-- A Seal of Command extra hit while another seal is up can only come from
-- stored Command copies released by the swing that just landed. If Sigil
-- didn't think that swing released Command copies, its count was off:
-- right after a release, one copy of the current seal is stored.
function Game.commandProc(now)
  local t = Game.tracker
  if not t.seal or t.seal == "command" then return end
  if not Game.swingAt or now - Game.swingAt > 1.5 then return end
  if Game.procCheckedFor == Game.swingAt then return end
  Game.procCheckedFor = Game.swingAt
  local released = t.lastRelease
  if released and released.seal == "command" and released.at == Game.swingAt then return end
  local before = ("%s x%d"):format(tostring(t.stored), t.stacks)
  t.stored, t.stacks, t.stacksExpire, t.undo = t.seal, 1, Game.swingAt + Tracker.STACK_DURATION, nil
  Game.cdm.fixes = (Game.cdm.fixes or 0) + 1
  Game.log("command proc drift: Command copies were released; counted %s, now %s x1", before, t.seal)
end

local function onCast(spellID)
  local id = plain(spellID)
  if not id then return end
  local now = GetTime()
  local t = Game.tracker
  local key = Data.byId[id]
  if not key then
    -- Not a seal rank we know. A seal's extra hit reports itself under the
    -- seal's name (Seal of Command's is 20424), so the name alone must never
    -- count as casting the seal. Record it and move on.
    if Data.SEAL_PROCS[id] then Game.commandProc(now) return end
    local name = plain(try(C_Spell.GetSpellName, id))
    if name and name:find("^Seal of") then
      Game.log("unlisted seal id %s name %s (ignored)", tostring(id), name)
    end
    return
  end
  if Data.SEALS[key] or key == "other" then
    t:castSeal(key, now)
    if Game.fight then Game.fight.seals = Game.fight.seals + 1 end
    Game.log("seal %s (id %s)", key, tostring(id))
  elseif Data.cooldowns[key] then
    t:castSpell(key, now, Data.OFF_GCD[key])
    Game.castAt = Game.castAt or {}
    Game.castAt[key] = now
    Game.lastAbility = now
    if key == "judgement" and t.seal == "crusader" then
      Game.crusaderMark = { id = targetId(), untilTime = now + CRUSADER_LASTS }
      Game.log("crusader mark applied")
    elseif key == "holy_strike" and Game.crusaderMark and Game.crusaderMark.id == targetId() then
      Game.crusaderMark.untilTime = now + CRUSADER_LASTS
    end
    Game.log("cast %s", key)
    if key == "judgement" or key == "holy_strike" then
      Game.stats[key] = (Game.stats[key] or 0) + 1
    end
  elseif key == "might" or key == "bow" then
    Game.blessing, Game.blessingExpires = true, nil
  end
end

local function onSwing(duration, swingType)
  duration, swingType = plain(duration), plain(swingType)
  if swingType ~= nil and swingType ~= 0 then return end
  local now = GetTime()
  local released = Game.tracker:swing(now, duration)
  Game.swingAt = now
  Game.stats.swings = (Game.stats.swings or 0) + 1
  Game.log("swing %.2fs -> %s x%d%s", duration or 0, tostring(Game.tracker.stored), Game.tracker.stacks,
    released and (" released " .. tostring(released.seal) .. " x" .. tostring(released.count)) or "")
  if Game.crusaderMark and Game.crusaderMark.id == targetId() and now < Game.crusaderMark.untilTime then
    Game.crusaderMark.untilTime = now + CRUSADER_LASTS
  end
  if released and ns.onRelease then ns.onRelease(released) end
  if ns.onSwing then ns.onSwing(now, Game.tracker.swingSpeed) end
end

-- The game reports "something was missed, dodged or parried on the target"
-- without saying by whom. A missed swing stores no stack (the real buff
-- confirmed it), so solo a miss at the moment your swing's result is due
-- undoes the stack that swing added.
local function onUnitCombat(unit, action)
  if plain(unit) ~= "target" then return end
  if not MISSES[plain(action) or ""] then return end
  local now = GetTime()
  local sinceSwing = Game.swingAt and (now - Game.swingAt) or -1
  local sinceAbility = Game.lastAbility and (now - Game.lastAbility) or -1
  local verdict = "ignored"
  -- Live, your swing's result arrived 0.3 to 1.0 seconds after the swing and
  -- an ability's at the moment of the cast. In a group the target's misses
  -- are mostly other players': in party play every swing undone this way had
  -- in fact landed. So in a group misses change nothing; the Cooldown Manager
  -- and the game-drawn arcs still show the real stacks.
  -- Consecration's hits can miss too, and live one landed a second after
  -- the cast, right in a swing's window, and took back a stack that was real.
  local sinceConsecration = Game.castAt and Game.castAt.consecration and (now - Game.castAt.consecration)
  if plain(try(IsInGroup)) == true then
    verdict = "in a group, not counted"
  elseif sinceConsecration and sinceConsecration <= CONSECRATION_MISSES then
    verdict = ("%.2fs after Consecration, likely its hit, not counted"):format(sinceConsecration)
  elseif sinceAbility >= 0 and sinceAbility < 0.25 then
    verdict = "ability"
  elseif sinceSwing < 0.25 then
    verdict = "too soon after the swing to be its result"
  elseif sinceSwing <= 1.1 and Game.tracker:swingMissed(now) then
    verdict = "swing undone, now x" .. Game.tracker.stacks
    Game.stats.misses = (Game.stats.misses or 0) + 1
  end
  Game.log("target %s: %.2fs after swing, %.2fs after ability -> %s", tostring(plain(action)), sinceSwing, sinceAbility, verdict)
end

local handlers = {}

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
  if plain(unit) == "player" then onCast(spellID) end
end
handlers.PLAYER_SWING = onSwing
handlers.UNIT_COMBAT = onUnitCombat

function handlers.PLAYER_REGEN_DISABLED()
  Game.inCombat = true
  local name, level = plain(try(UnitName, "target")), plain(try(UnitLevel, "target"))
  Game.fight = { start = GetTime(), seals = 0, pattern = ns.db and ns.db.pattern or "burst",
    mob = (name and plain(try(UnitCanAttack, "player", "target"))) and (name .. " (" .. tostring(level or "?") .. ")") or nil }
  Game.compareDue = nil
  Game.stats.fights = (Game.stats.fights or 0) + 1
end

-- The game hides hit amounts from addons, so damage can't be added up.
-- What can be measured is how long a kill takes: per seal pattern and per
-- kind of mob, solo, one enemy at a time.
local function closeFight()
  local fight = Game.fight
  Game.fight = nil
  if not fight or not ns.db then return end
  local seconds = GetTime() - fight.start
  local why
  if not fight.mob then why = "no target at the start"
  elseif seconds < 5 then why = "under 5 seconds"
  elseif (fight.enemies or 0) > 1 then why = "more than one enemy"
  elseif plain(try(IsInGroup)) then why = "in a group" end
  if why then Game.log("fight not counted (%s): %.1fs", why, seconds) return end
  Game.log("fight: %s, %.1fs, %d seals, pattern %s", fight.mob, seconds, fight.seals, fight.pattern)
  ns.db.kills = ns.db.kills or {}
  local mob = ns.db.kills[fight.mob] or {}
  ns.db.kills[fight.mob] = mob
  local t = mob[fight.pattern] or { fights = 0, seconds = 0, seals = 0 }
  mob[fight.pattern] = t
  t.fights, t.seconds, t.seals = t.fights + 1, t.seconds + seconds, t.seals + fight.seals
end

-- Lines for /sigil compare: mobs fought with both patterns come first.
function Game.compareLines()
  local both, single = {}, {}
  for mob, by in pairs(ns.db and ns.db.kills or {}) do
    local a, b = by.burst, by.even
    local function part(label, x)
      return x and ("%s %.1fs over %d fight%s"):format(label, x.seconds / x.fights, x.fights, x.fights == 1 and "" or "s") or nil
    end
    local parts = {}
    if a then parts[#parts + 1] = part("3 and 1", a) end
    if b then parts[#parts + 1] = part("3 and 3", b) end
    local line = mob .. ": " .. table.concat(parts, ", ")
    if a and b then both[#both + 1] = line else single[#single + 1] = line end
  end
  table.sort(both); table.sort(single)
  return both, single
end

function handlers.PLAYER_REGEN_ENABLED()
  Game.inCombat = false
  closeFight()
  Game.compareDue = true
  C_Timer.After(0.6, function()
    if Game.inCombat then return end
    Game.syncBuffs()
    Game.scanSpells()
    if ns.db and ns.db.attackKeys ~= 2 then Game.ensureMacro() end
    Game.scanKeys()
    if ns.refreshSetup then ns.refreshSetup() end
  end)
end

-- Where the target can't be identified (dungeons), a new target means a new mark.
function handlers.PLAYER_TARGET_CHANGED()
  if Game.crusaderMark and Game.crusaderMark.id == "target" then Game.crusaderMark = nil end
end

-- Dying removes your seal and every stored copy.
function handlers.PLAYER_DEAD()
  local t = Game.tracker
  t.seal, t.sealExpires = nil, nil
  t.stacks, t.stored, t.stacksExpire, t.undo = 0, nil, nil, nil
  Game.crusaderMark = nil
  Game.log("died: seal and stacks cleared")
end

function handlers.NAME_PLATE_UNIT_ADDED(unit)
  unit = plain(unit)
  if unit then plates[unit] = true end
end
function handlers.NAME_PLATE_UNIT_REMOVED(unit)
  unit = plain(unit)
  if unit then plates[unit] = nil end
end

local function rescan()
  if Game.rescanQueued then return end
  Game.rescanQueued = true
  C_Timer.After(0.5, function()
    Game.rescanQueued = false
    if not Game.inCombat then
      Game.scanSpells()
      if ns.db and ns.db.attackKeys ~= 2 then Game.ensureMacro() end
    end
    Game.scanKeys()
    if ns.refreshSetup then ns.refreshSetup() end
  end)
end
for _, e in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP", "UPDATE_BINDINGS", "UPDATE_MACROS",
  "ACTIONBAR_SLOT_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED" }) do
  handlers[e] = rescan
end

function handlers.UNIT_AURA(unit)
  if plain(unit) == "player" and not Game.inCombat then Game.syncBuffs() end
end

function Game.start()
  -- Cooldown Manager scores are kept with the settings so a reload can't lose them
  if ns.db then
    local saved = ns.db.cdm
    if type(saved) == "table" then
      for k, v in pairs(Game.cdm) do if saved[k] == nil then saved[k] = v end end
      saved.at, saved.lastEcho, saved.echoDownRun, saved.sealDownRun, saved.echoUpRun = nil, nil, nil, nil, nil
      saved.clog = nil   -- leftover from the combat log test
      Game.cdm = saved
    else
      ns.db.cdm = Game.cdm
    end
  end
  Game.tracker = Tracker.new()
  for key, seconds in pairs(Data.cooldowns) do Game.tracker:setCooldown(key, seconds) end
  Game.inCombat = plain(try(UnitAffectingCombat, "player")) == true

  local frame = CreateFrame("Frame")
  Game.frame = frame
  for event in pairs(handlers) do
    local ok
    if event == "UNIT_COMBAT" then
      ok = pcall(frame.RegisterUnitEvent, frame, event, "target")
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_AURA" then
      ok = pcall(frame.RegisterUnitEvent, frame, event, "player")
    else
      ok = pcall(frame.RegisterEvent, frame, event)
    end
    if not ok then Game.refused[#Game.refused + 1] = event end
  end
  frame:SetScript("OnEvent", function(_, event, ...)
    local h = handlers[event]
    if not h then return end
    local ok, err = pcall(h, ...)
    if not ok then Game.log("error in %s: %s", event, tostring(err)) end
  end)

  for i = 1, 40 do
    local unit = "nameplate" .. i
    if plain(try(UnitExists, unit)) then plates[unit] = true end
  end

  Game.scanSpells()
  Game.scanKeys()
  Game.syncBuffs()
  Game.tracker.unsealedWrath = Game.unsealedWrath ~= false
end

-- Learns real cooldown lengths: the moment the game says a spell is ready
-- again, the time since we cast it is its cooldown.
local function calibrate(now)
  if not Game.castAt then return end
  for key, at in pairs(Game.castAt) do
    local ready = Game.ready(key)
    if ready then
      local took = now - at
      if took > 2.5 and took < 120 and math.abs(took - (Game.tracker.cooldowns[key] or 0)) > 0.75 then
        local rounded = math.floor(took * 2 + 0.5) / 2
        Game.log("cooldown %s measured %.1f", key, took)
        if took < (Game.tracker.cooldowns[key] or 999) + 3 then Game.tracker:setCooldown(key, rounded) end
      end
      Game.castAt[key] = nil
      Game.tracker:correctCooldown(key, true, now)
    elseif ready == false then
      Game.tracker:correctCooldown(key, false, now)
    end
  end
end

---------------------------------------------------------------------------
-- The game's Cooldown Manager. Its buttons carry one readable bit per
-- tracked buff: up or down. In live fights it agreed with Sigil's own count
-- in 399 of 399 checks, so it is trusted for one correction: when it says a
-- buff is gone for half a second or more while Sigil still counts it, Sigil
-- drops it. The other direction (it says up, Sigil counts none) can't say
-- how many stacks or which seal, so that is only recorded.
---------------------------------------------------------------------------

local CDM_VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local CDM_IDS = { [200341] = "echo", [200342] = "echo", [200339] = "seal", [200340] = "seal" }
Game.cdm = { polls = 0, found = {}, echoAgree = 0, echoDown = 0, echoUp = 0, sealAgree = 0, sealDown = 0, sealUp = 0 }

-- Returns { echo = true/false/nil, seal = true/false/nil }; nil means not shown.
function Game.readCooldownManager()
  local state = {}
  for _, name in ipairs(CDM_VIEWERS) do
    local viewer = _G[name]
    if viewer and viewer.GetChildren then
      pcall(function()
        local kids = { viewer:GetChildren() }
        for _, item in ipairs(kids) do
          local id = plain(rawget(item, "cooldownID"))
          local what = id and CDM_IDS[id]
          if what then
            local instance = rawget(item, "auraInstanceID")
            local up = issecret(instance) or instance ~= nil
            Game.cdm.found[id] = name
            if up then state[what] = true elseif state[what] == nil then state[what] = false end
          end
        end
      end)
    end
  end
  return state
end

local function watchCooldownManager(now)
  local c = Game.cdm
  if c.at and now - c.at < 0.25 then return end
  c.at = now
  local state = Game.readCooldownManager()
  c.polls = c.polls + 1
  if not Game.inCombat then return end
  local t = Game.tracker
  -- give the game a moment to light the button after a change
  local settled = not Game.swingAt or now - Game.swingAt > 0.8
  if state.echo ~= nil and settled then
    local mine = t.stacks > 0
    if mine == state.echo then c.echoAgree = c.echoAgree + 1
    elseif mine then c.echoDown = c.echoDown + 1
    else c.echoUp = c.echoUp + 1 end
    if mine ~= state.echo and c.lastEcho ~= state.echo then
      Game.log("cooldown manager: stacks shown %s, counted x%d", state.echo and "up" or "down", t.stacks)
    end
    c.lastEcho = state.echo
    -- stacks exist but Sigil counts none: at least one copy is stored
    if state.echo and not mine and t.seal and t.seal ~= "crusader" then
      c.echoUpRun = (c.echoUpRun or 0) + 1
      if c.echoUpRun >= 2 then
        t.stored, t.stacks, t.stacksExpire = t.seal, 1, now + Tracker.STACK_DURATION
        c.fixes = (c.fixes or 0) + 1
        c.echoUpRun = 0
        Game.log("cooldown manager drift: stacks exist, counted none; now %s x1", tostring(t.seal))
      end
    else
      c.echoUpRun = 0
    end
    if mine and not state.echo then
      c.echoDownRun = (c.echoDownRun or 0) + 1
      if c.echoDownRun >= 2 then
        Game.log("cooldown manager drift: stacks are gone, dropping counted x%d", t.stacks)
        t.stacks, t.stored, t.stacksExpire, t.undo = 0, nil, nil, nil
        c.fixes = (c.fixes or 0) + 1
        c.echoDownRun = 0
      end
    else
      c.echoDownRun = 0
    end
  end
  if state.seal ~= nil then
    local mine = t.seal ~= nil
    if mine == state.seal then c.sealAgree = c.sealAgree + 1
    elseif mine then c.sealDown = c.sealDown + 1
    else c.sealUp = c.sealUp + 1 end
    local fresh = t.sealExpires and (t.sealExpires - Tracker.SEAL_DURATION) > now - 0.8   -- just cast: button not lit yet
    if mine and not state.seal and not fresh then
      c.sealDownRun = (c.sealDownRun or 0) + 1
      if c.sealDownRun >= 2 then
        Game.log("cooldown manager drift: seal is gone, dropping counted %s", tostring(t.seal))
        t.seal, t.sealExpires = nil, nil
        c.fixes = (c.fixes or 0) + 1
        c.sealDownRun = 0
      end
    else
      c.sealDownRun = 0
    end
  end
end

local FLAG_KEYS = { "command", "righteousness", "wisdom", "light", "justice", "crusader", "consecration", "hoj", "how", "exorcism" }
function Game.knownFlags()
  local flags = {}
  for _, key in ipairs(FLAG_KEYS) do flags[key] = Game.known[key] ~= nil end
  return flags
end

-- One picture of the fight for the engine.
function Game.view()
  local now = GetTime()
  local t = Game.tracker
  calibrate(now)
  watchCooldownManager(now)
  local v = t:snapshot(now)
  -- the game's own "global cooldown running" flag beats Sigil's timer
  local gcd = field(try(C_Spell.GetSpellCooldown, Data.GCD_SPELL), "isActive")
  if gcd == false then v.gcdRemains = 0
  elseif gcd == true and v.gcdRemains == 0 then v.gcdRemains = 0.3 end
  v.now = now
  v.combat = Game.inCombat
  v.target = plain(try(UnitExists, "target")) == true and plain(try(UnitCanAttack, "player", "target")) == true
    and plain(try(UnitIsDead, "target")) ~= true
  v.manaLevel = Game.manaLevel()
  v.unsealedWrath = Game.unsealedWrath
  v.known, v.afford = Game.knownFlags(), {}
  for key in pairs(v.known) do v.afford[key] = Game.afford(key) end
  v.crusaderDone = Game.crusaderDone(now)
  local class = plain(try(UnitClassification, "target"))
  v.elite = class == "elite" or class == "rareelite" or class == "worldboss"
  v.ready = { consecration = Game.ready("consecration") == true, hoj = Game.ready("hoj") == true, how = Game.ready("how"),
    exorcism = Game.ready("exorcism") }
  v.usable = {}
  Game.lastUsable = Game.lastUsable or {}
  for _, key in ipairs({ "how", "exorcism" }) do
    if v.known[key] then
      v.usable[key] = Game.gatedUsable(key, v.target)
      if v.combat and v.usable[key] ~= Game.lastUsable[key] then
        Game.lastUsable[key] = v.usable[key]
        Game.log("%s usable %s", key == "how" and "hammer of wrath" or key, tostring(v.usable[key]))
      end
    end
  end
  local judgementReady = Game.ready("judgement")
  v.judgementRemains = judgementReady and 0 or t:remains("judgement", now)
  if judgementReady == false and v.judgementRemains == 0 then v.judgementRemains = 99 end
  v.inGroup = plain(try(IsInGroup)) == true
  v.enemies = Game.enemies()
  if Game.fight and v.enemies and v.enemies > (Game.fight.enemies or 0) then Game.fight.enemies = v.enemies end
  local aura = Game.auraState()
  v.auraMissing = aura == "missing"
  v.auraWrong = aura == "wrong"
  v.blessingMissing = Game.blessingMissing(now)
  return v
end

---------------------------------------------------------------------------
-- /sigil check: one report of which readings work on this client
---------------------------------------------------------------------------

local function describe(v)
  if issecret(v) then return "SECRET" end
  if v == nil then return "nil" end
  return tostring(v)
end

function Game.report()
  local out = {}
  local function add(fmt, ...) out[#out + 1] = fmt:format(...) end
  local function section(fn)
    local ok, err = pcall(fn)
    if not ok then out[#out + 1] = "report error: " .. tostring(err) end
  end
  section(function()
  local version, build, _, interface = try(GetBuildInfo)
  add("client %s build %s interface %s", describe(version), describe(build), describe(interface))
  add("class %s level %s combat %s", describe(select(2, try(UnitClass, "player"))), describe(try(UnitLevel, "player")), tostring(Game.inCombat))
  add("issecretvalue %s  C_Secrets %s  C_Timer %s", tostring(issecretvalue ~= nil), tostring(C_Secrets ~= nil), tostring(C_Timer ~= nil))
  end)
  for _, key in ipairs({ "judgement", "holy_strike", "exorcism", "how", "consecration", "hoj", "command", "righteousness", "wisdom", "ret_aura", "might", "bow" }) do
    section(function()
    local id = Game.known[key]
    if id then
      local usable, short = try(C_Spell.IsSpellUsable, id)
      local info = try(C_Spell.GetSpellCooldown, id)
      add("%s id %d cost %s usable %s short %s active %s gcd %s dur %s key %s", key, id, tostring(Game.cost[key]),
        describe(usable), describe(short), describe(try(rawget, info, "isActive")), describe(try(rawget, info, "isOnGCD")),
        describe(try(rawget, info, "duration")), tostring(Game.keys[key]))
    else
      add("%s not known", key)
    end
    end)
  end
  section(function()
  add("unsealed wrath %s (%s)", tostring(Game.unsealedWrath), tostring(Game.unsealedWrathHow))
  local costs = {}
  for _, p in ipairs(Game.probes) do costs[#costs + 1] = p.cost end
  add("mana probes %s", table.concat(costs, " "))
  add("mana level %s floor %s ceiling %s", tostring(Game.lastLevel), tostring(Game.manaFloor), tostring(Game.manaCeiling))
  end)
  section(function()
  add("UnitPower %s UnitPowerMax %s", describe(try(UnitPower, "player", 0)), describe(try(UnitPowerMax, "player", 0)))
  end)
  section(function()
  local real = Game.readBuffs()
  if real then
    add("buffs readable: seal %s stacks %s x%s blessing %s", tostring(real.seal), tostring(real.stored), tostring(real.stacks), tostring(real.blessing))
  else
    add("buffs not readable right now")
  end
  local t = Game.tracker
  add("counted: seal %s stacks %s x%d swing speed %s", tostring(t.seal), tostring(t.stored), t.stacks, tostring(t.swingSpeed))
  end)
  section(function()
  add("aura form %s enemies %s creature %s", describe(try(GetShapeshiftForm)), tostring(Game.enemies()), describe(select(2, try(UnitCreatureType, "target"))))
  local index = plain(try(GetMacroIndexByName, Data.MACRO_NAME)) or 0
  add("macro index %d key %s", index, tostring(Game.keys.attack))
  if index > 0 then add("macro body: %s", (plain(try(GetMacroBody, index)) or "?"):gsub("\n", " | ")) end
  add("events refused: %s", #Game.refused > 0 and table.concat(Game.refused, " ") or "none")
  local s = Game.stats
  add("stats: fights %s swings %s misses %s judgements %s holy strikes %s compared %s drifted %s", tostring(s.fights), tostring(s.swings),
    tostring(s.misses), tostring(s.judgement), tostring(s.holy_strike), tostring(s.compared), tostring(s.drifted))
  for name, cd in pairs(Game.tracker.cooldowns) do add("cooldown %s %.1f", name, cd) end
  local c = Game.cdm
  local shown = {}
  for id, where in pairs(c.found) do shown[#shown + 1] = id .. " in " .. where end
  add("cooldown manager: %s", #shown > 0 and table.concat(shown, ", ") or "no Sigil-relevant buttons found")
  add("cooldown manager stacks: agree %d, shows down while counted %d, shows up while none counted %d", c.echoAgree, c.echoDown, c.echoUp)
  add("cooldown manager seal: agree %d, shows down while counted %d, shows up while none counted %d", c.sealAgree, c.sealDown, c.sealUp)
  add("cooldown manager corrections made: %d", c.fixes or 0)
  if ns.Native then add("game-drawn stacks: %s", ns.Native.status) end
  local both, single = Game.compareLines()
  for _, line in ipairs(both) do add("kill time %s", line) end
  for _, line in ipairs(single) do add("kill time %s", line) end
  end)
  return out
end
