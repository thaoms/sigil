-- Everything that touches the game client. The game hides many values from
-- addons in combat ("secret values"): touching one raises an error, so every
-- read here goes through pcall and is checked before use. A failed read means
-- "unknown", never "false".
local _, ns = ...
local Data, Tracker, Mana = ns.Data, ns.Tracker, ns.Mana

local Game = { known = {}, cost = {}, keys = {}, probes = {}, refused = {}, stats = {} }
ns.Game = Game

local issecret = issecretvalue or function() return false end

local function plain(v)
  if v == nil or issecret(v) then return nil end
  return v
end
Game.plain = plain

-- Reads one field of a table the game returned; nil if it can't be read.
local function field(t, k)
  if type(t) ~= "table" then return nil end
  local ok, v = pcall(function() return t[k] end)
  if ok then return plain(v) end
  return nil
end
Game.field = field

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
  return nil
end
Game.try = try

local C_Spell, C_SpellBook, C_UnitAuras = C_Spell or {}, C_SpellBook or {}, C_UnitAuras or {}

function Game.log(fmt, ...)
  local db = SigilCharDB
  if not db then return end
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
  local lines = { "#showtooltip", "/startattack" }
  for _, key in ipairs({ "judgement", "how", "holy_strike", "exorcism" }) do
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

local function slotEmpty(slot)
  local ok, kind = pcall(GetActionInfo, slot)
  return ok and kind == nil
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

function Game.syncBuffs(compare)
  local real = Game.readBuffs()
  if not real then return end
  local now = GetTime()
  local t = Game.tracker
  if compare then
    t:expire(now)
    local stats = Game.stats
    stats.compared = (stats.compared or 0) + 1
    if t.stacks ~= real.stacks or (real.stacks > 0 and t.stored ~= real.stored) then
      stats.drifted = (stats.drifted or 0) + 1
      Game.log("drift: counted %s x%d, real %s x%d", tostring(t.stored), t.stacks, tostring(real.stored), real.stacks)
    end
    if (t.seal or false) ~= real.seal then
      Game.log("seal drift: counted %s, real %s", tostring(t.seal), tostring(real.seal))
    end
  end
  t:sync(real, now)
  Game.blessing = real.blessing
  Game.blessingExpires = real.blessing and real.blessingExpires or nil
end

function Game.auraMissing()
  if not Game.known.ret_aura then return nil end
  local form = plain(try(GetShapeshiftForm))
  if form == nil then return nil end
  if form ~= 0 then Game.formSeen = true end
  if not Game.formSeen then return nil end     -- never seen an aura register: don't nag
  return form == 0
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

function Game.enemies()
  local n, any = 0, false
  for unit in pairs(plates) do
    any = true
    if plain(try(UnitExists, unit)) and plain(try(UnitCanAttack, "player", unit))
      and plain(try(UnitAffectingCombat, unit)) and not plain(try(UnitIsDead, unit)) then
      n = n + 1
    end
  end
  if not any then return nil end
  return n
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local MISSES = { MISS = true, DODGE = true, PARRY = true }

local function onCast(spellID)
  local id = plain(spellID)
  if not id then return end
  local now = GetTime()
  local t = Game.tracker
  local key = Data.byId[id]
  if not key then
    local name = plain(try(C_Spell.GetSpellName, id))
    if name and name:find("^Seal of") then key = "other" else return end
  end
  if Data.SEALS[key] or key == "other" then
    t:castSeal(key, now)
    Game.log("seal %s", key)
    if ns.onSeal then ns.onSeal(key) end
  elseif Data.cooldowns[key] then
    t:castSpell(key, now, Data.OFF_GCD[key])
    Game.castAt = Game.castAt or {}
    Game.castAt[key] = now
    Game.lastAbility = now
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
  if released and ns.onRelease then ns.onRelease(released) end
  if ns.onSwing then ns.onSwing(now, Game.tracker.swingSpeed) end
end

-- A miss on our target shortly after our swing, with no ability of ours in
-- between, was the swing. In a group other players' misses look the same,
-- so there we count every swing as a hit and let the after-fight check fix it.
local function onUnitCombat(unit, action, _, amount)
  if plain(unit) ~= "target" or not MISSES[plain(action) or ""] then return end
  if plain(try(IsInGroup)) then return end
  local now = GetTime()
  local since = Game.swingAt and (now - Game.swingAt)
  if not since or since > 1.0 then return end
  if Game.lastAbility and now - Game.lastAbility < 0.7 and Game.lastAbility >= Game.swingAt - 0.2 then return end
  if Game.tracker:swingMissed(now) then
    Game.stats.misses = (Game.stats.misses or 0) + 1
    Game.log("swing missed (%s), stacks back to %d", tostring(plain(action)), Game.tracker.stacks)
  end
end

local handlers = {}

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
  if plain(unit) == "player" then onCast(spellID) end
end
handlers.PLAYER_SWING = onSwing
handlers.UNIT_COMBAT = onUnitCombat

function handlers.PLAYER_REGEN_DISABLED()
  Game.inCombat = true
  Game.stats.fights = (Game.stats.fights or 0) + 1
end

function handlers.PLAYER_REGEN_ENABLED()
  Game.inCombat = false
  C_Timer.After(0.6, function()
    if Game.inCombat then return end
    Game.syncBuffs(true)
    Game.scanSpells()
    if ns.db and ns.db.attackKeys ~= 2 then Game.ensureMacro() end
    Game.scanKeys()
    if ns.refreshSetup then ns.refreshSetup() end
  end)
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
  if plain(unit) == "player" and not Game.inCombat then Game.syncBuffs(false) end
end

function Game.start()
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
  Game.syncBuffs(false)
  Game.unsealedWrathNote()
end

function Game.unsealedWrathNote()
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
      if took > 2.5 and took < 120 and math.abs(took - (Game.tracker.cooldowns[key] or 0)) > 0.4 then
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

-- One picture of the fight for the engine.
function Game.view()
  local now = GetTime()
  local t = Game.tracker
  calibrate(now)
  local v = t:snapshot(now)
  v.now = now
  v.combat = Game.inCombat
  v.target = plain(try(UnitExists, "target")) == true and plain(try(UnitCanAttack, "player", "target")) == true
    and plain(try(UnitIsDead, "target")) ~= true
  v.manaLevel = Game.manaLevel()
  v.unsealedWrath = Game.unsealedWrath
  v.known = {
    command = Game.known.command ~= nil, righteousness = Game.known.righteousness ~= nil,
    wisdom = Game.known.wisdom ~= nil, consecration = Game.known.consecration ~= nil, hoj = Game.known.hoj ~= nil,
  }
  v.afford = {
    command = Game.afford("command"), righteousness = Game.afford("righteousness"),
    wisdom = Game.afford("wisdom"), consecration = Game.afford("consecration"), hoj = Game.afford("hoj"),
  }
  v.ready = { consecration = Game.ready("consecration") == true, hoj = Game.ready("hoj") == true }
  local judgementReady = Game.ready("judgement")
  v.judgementRemains = judgementReady and 0 or t:remains("judgement", now)
  if judgementReady == false and v.judgementRemains == 0 then v.judgementRemains = 99 end
  v.enemies = Game.enemies()
  v.auraMissing = Game.auraMissing()
  v.blessingMissing = Game.blessingMissing(now)
  return v
end

---------------------------------------------------------------------------
-- /sigil check: one report of which readings work on this client
---------------------------------------------------------------------------

local function describe(v)
  if v == nil then return "nil" end
  if issecret(v) then return "SECRET" end
  return tostring(v)
end

function Game.report()
  local out = {}
  local function add(fmt, ...) out[#out + 1] = fmt:format(...) end
  local version, build, _, interface = try(GetBuildInfo)
  add("client %s build %s interface %s", describe(version), describe(build), describe(interface))
  add("class %s level %s combat %s", describe(select(2, try(UnitClass, "player"))), describe(try(UnitLevel, "player")), tostring(Game.inCombat))
  add("issecretvalue %s  C_Secrets %s  C_Timer %s", tostring(issecretvalue ~= nil), tostring(C_Secrets ~= nil), tostring(C_Timer ~= nil))
  for _, key in ipairs({ "judgement", "holy_strike", "exorcism", "how", "consecration", "hoj", "command", "righteousness", "wisdom", "ret_aura", "might", "bow" }) do
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
  end
  add("unsealed wrath %s (%s)", tostring(Game.unsealedWrath), tostring(Game.unsealedWrathHow))
  local costs = {}
  for _, p in ipairs(Game.probes) do costs[#costs + 1] = p.cost end
  add("mana probes %s", table.concat(costs, " "))
  add("mana level %s floor %s ceiling %s", tostring(Game.lastLevel), tostring(Game.manaFloor), tostring(Game.manaCeiling))
  add("UnitPower %s UnitPowerMax %s", describe(try(UnitPower, "player", 0)), describe(try(UnitPowerMax, "player", 0)))
  local real = Game.readBuffs()
  if real then
    add("buffs readable: seal %s stacks %s x%s blessing %s", tostring(real.seal), tostring(real.stored), tostring(real.stacks), tostring(real.blessing))
  else
    add("buffs not readable right now")
  end
  local t = Game.tracker
  add("counted: seal %s stacks %s x%d swing speed %s", tostring(t.seal), tostring(t.stored), t.stacks, tostring(t.swingSpeed))
  add("aura form %s enemies %s creature %s", describe(try(GetShapeshiftForm)), tostring(Game.enemies()), describe(select(2, try(UnitCreatureType, "target"))))
  local index = plain(try(GetMacroIndexByName, Data.MACRO_NAME)) or 0
  add("macro index %d key %s", index, tostring(Game.keys.attack))
  if index > 0 then add("macro body: %s", (plain(try(GetMacroBody, index)) or "?"):gsub("\n", " | ")) end
  add("events refused: %s", #Game.refused > 0 and table.concat(Game.refused, " ") or "none")
  local s = Game.stats
  add("stats: fights %s swings %s misses %s judgements %s holy strikes %s compared %s drifted %s", tostring(s.fights), tostring(s.swings),
    tostring(s.misses), tostring(s.judgement), tostring(s.holy_strike), tostring(s.compared), tostring(s.drifted))
  for name, cd in pairs(t.cooldowns) do add("cooldown %s %.1f", name, cd) end
  return out
end
