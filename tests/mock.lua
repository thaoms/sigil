-- Loads the whole addon against a fake game client and plays a fight.
-- Run with: luajit tests/mock.lua   (from the repo root)
local out = print
local SECRET = newproxy(true)          -- any arithmetic or ordering on it errors, like a real secret
local clock = 100
local errors = {}

local Widget = {}
Widget.__index = function(self, key)
  local known = rawget(Widget, key)
  if known then return known end
  if type(key) == "string" and key:match("^%u") then return function() return nil end end   -- any widget method
  return nil
end
local function widget(kind)
  return setmetatable({ kind = kind, scripts = {}, events = {}, shown = true, children = {} }, Widget)
end
local frames = {}
function Widget:SetScript(name, fn) self.scripts[name] = fn end
function Widget:RegisterEvent(e) if e == "COMBAT_LOG_EVENT_UNFILTERED" or e == "LEARNED_SPELL_IN_TAB" then error("bad event") end self.events[e] = true end
function Widget:RegisterUnitEvent(e) self.events[e] = true end
function Widget:UnregisterEvent(e) self.events[e] = nil end
function Widget:CreateTexture() return widget("Texture") end
function Widget:CreateFontString() return widget("FontString") end
function Widget:CreateAnimationGroup() return widget("AnimationGroup") end
function Widget:CreateAnimation() return widget("Animation") end
function Widget:SetText(t) self.text = t end
function Widget:GetText() return self.text end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
function Widget:IsShown() return self.shown end
function Widget:SetAlpha(a) self.alpha = a end
function Widget:SetTexture(t) self.texture = t end
function Widget:GetFrameLevel() return 1 end
function Widget:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Widget:SetChecked(v) self.checked = v end
function Widget:GetChecked() return self.checked end
function Widget:Enable() self.enabled = true end
function Widget:Disable() self.enabled = false end
function Widget:SetCooldown(a, b) self.cooldown = { a, b } end

function CreateFrame(kind, name)
  local f = widget(kind)
  frames[#frames + 1] = f
  if name then _G[name] = f end
  return f
end
UIParent, UIErrorsFrame, UISpecialFrames = widget("Frame"), widget("Frame"), {}
Minimap, GameTooltip = widget("Frame"), widget("Frame")
function Minimap:GetCenter() return 100, 100 end
function Minimap:GetEffectiveScale() return 1 end
function GetCursorPosition() return 100, 200 end
function GetTime() return clock end
function issecretvalue(v) return v == SECRET end
function print() end   -- the addon's chat output
function date() return "2026-11-20 12:00:00" end
SlashCmdList = {}
SOUNDKIT = {}
function PlaySound() end
C_Timer = { After = function(_, fn) fn() end }
C_Secrets = { ShouldAurasBeSecret = function() return world.combat end }
Enum = { SpellBookSpellBank = { Player = 0 } }
Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }

world = {
  combat = false, target = true, mana = 2000, form = 1, inGroup = false,
  known = { [20271] = true, [679] = true, [678] = true, [1866] = true, [879] = true, [26573] = true, [853] = true,
            [20375] = true, [20915] = true, [20154] = true, [21084] = true, [20166] = true, [7294] = true, [19740] = true, [19742] = true },
  cost = { [20271] = 60, [1866] = 80, [879] = 85, [26573] = 320, [853] = 55, [20915] = 140, [21084] = 110, [20166] = 60, [19740] = 90, [19742] = 70,
           [679] = 40, [678] = 60, [20375] = 100, [20154] = 70 },
  cooling = {}, auras = {}, actions = {}, macros = {}, bindings = {},
}
for i = 1, 12 do world.bindings["ACTIONBUTTON" .. i] = tostring(i % 10) end

function UnitClass() return "Paladin", "PALADIN" end
function UnitLevel() return 40 end
function UnitName() return "Plains Boar" end
function UnitExists(u) return (u == "target" and world.target) or false end
function UnitCanAttack() return true end
function UnitIsDead() return false end
function UnitAffectingCombat() return world.combat end
function UnitPower() return SECRET end
function UnitPowerMax() return 2162 end
function UnitCreatureType() return "Beast", 1 end
function IsInGroup() return world.inGroup end
function InCombatLockdown() return world.combat end
function GetShapeshiftForm() return world.form end
function GetNumShapeshiftForms() return 3 end
function GetShapeshiftFormInfo(i) return 1, true, true, ({ 465, 7294, 19746 })[i] end
function GetBuildInfo() return "1.60.1", "70959", "Nov 2026", 16001 end
function GetActionInfo(slot) local a = world.actions[slot] if a then return a[1], a[2] end end
function GetActionText(slot) local a = world.actions[slot] return a and a[3] end
function GetBindingKey(b) return world.bindings[b] end
function ClearCursor() world.cursor = nil end
function PickupMacro(n) world.cursor = { "macro", 20271, n } end
function PlaceAction(slot) world.actions[slot] = world.cursor; world.cursor = nil end
function GetMacroIndexByName(n) return world.macros[n] and 121 or 0 end
function GetMacroBody() return world.macros.SigilAttack end
function CreateMacro(n, _, body) if world.combat then error("combat") end world.macros[n] = body return 121 end
function EditMacro(_, _, _, body) world.macros.SigilAttack = body return 121 end

C_SpellBook = {
  IsSpellKnown = function(id) return world.known[id] or false end,
  GetNumSpellBookSkillLines = function() return 0 end,
}
C_Spell = {
  GetSpellTexture = function(id) return 130000 + id end,
  GetSpellName = function(id)
    local names = { [20271] = "Judgement", [1866] = "Holy Strike", [879] = "Exorcism", [26573] = "Consecration", [853] = "Hammer of Justice",
      [20915] = "Seal of Command", [21084] = "Seal of Righteousness", [20166] = "Seal of Wisdom", [7294] = "Retribution Aura", [19740] = "Blessing of Might" }
    return names[id] or ("Spell " .. id)
  end,
  IsSpellUsable = function(id) local c = world.cost[id] or 0 return world.mana >= c, world.mana < c end,
  GetSpellCooldown = function(id)
    local active = (world.cooling[id] or 0) > clock
    return { isActive = active, isEnabled = true, duration = world.combat and SECRET or 0, startTime = world.combat and SECRET or 0 }
  end,
  GetSpellPowerCost = function(id) local c = world.cost[id] return c and { { type = 0, cost = c } } or {} end,
  PickupSpell = function(id) world.cursor = { "spell", id } end,
}
C_UnitAuras = {
  GetPlayerAuraBySpellID = function(id) if world.combat then return nil end return world.auras[id] end,
  GetAuraDataByIndex = function() if world.combat then error("Auras cannot be accessed when secret") end return nil end,
}

local ns = {}
for line in io.lines("Sigil/Sigil.toc") do
  if line:match("%.lua$") then
    local chunk, err = loadfile("Sigil/" .. line:gsub("\\", "/"))
    assert(chunk, err)
    chunk("Sigil", ns)
  end
end

local function fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local function tick(seconds)
  local steps = math.floor(seconds / 0.06 + 0.5)
  for _ = 1, steps do
    clock = clock + 0.06
    for _, f in ipairs(frames) do
      if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.06) end
    end
  end
end
local function cast(id, cd)
  world.mana = world.mana - (world.cost[id] or 0)
  if cd then world.cooling[id] = clock + cd end
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", id)
end

local passed, failed = 0, 0
local function expect(what, got, want)
  if got == want then passed = passed + 1 else failed = failed + 1; out("FAIL " .. what .. ": expected " .. tostring(want) .. ", got " .. tostring(got)) end
end
local function shown()
  local f = ns.Halo.frame
  local key = f.key.text
  return (f.name.text or "") .. ((key and key ~= "") and ("  [" .. key .. "]") or "")
end

fire("ADDON_LOADED", "Sigil")
fire("PLAYER_LOGIN")
expect("started", ns.ready, true)
expect("debug log is off by default", ns.db.debug, false)
ns.Game.log("swing test"); expect("nothing is recorded with debug off", #SigilCharDB.log, 0)
ns.Game.log("tick error: test"); expect("errors are always recorded", #SigilCharDB.log, 1)
SigilCharDB.log = {}; ns.db.debug = true
ns.db.pattern = "burst"      -- the fight below plays the 3-and-1 pattern
expect("start error", SigilDB.startError, nil)
ns.db.hojInMacro = true; ns.Options.apply("hojInMacro")
expect("stun can be added to the macro", world.macros.SigilAttack, "#showtooltip\n/startattack\n/cast Hammer of Justice\n/cast Judgement\n/cast Holy Strike\n/cast Exorcism")
ns.db.hojInMacro = false; ns.Options.apply("hojInMacro")
expect("macro created", world.macros.SigilAttack, "#showtooltip\n/startattack\n/cast Judgement\n/cast Holy Strike\n/cast Exorcism")
expect("holy strike resolves to highest known rank", ns.Game.known.holy_strike, 1866)
expect("unsealed wrath assumed", ns.Game.unsealedWrathHow, "assumed")
expect("setup window opened", SigilSetup ~= nil and SigilSetup.shown, true)

-- setup: nothing on the bar yet, slot 2 already holds something else
world.actions[2] = { "spell", 635 }
ns.Game.scanKeys()
ns.Setup.show()
ns.Setup.placeClicked()                       -- shows the plan
expect("plan asks for confirm", ns.Setup.frame.place.text, "Confirm")
ns.Setup.placeClicked()                       -- confirms
expect("attack placed on 1", world.actions[1] and world.actions[1][3], "SigilAttack")
expect("slot 2 untouched", world.actions[2][2], 635)
expect("command went to the next free slot", world.actions[3] and world.actions[3][2], 20915)
expect("attack key found", ns.Game.keyFor("attack"), "1")
expect("command key found", ns.Game.keyFor("command"), "3")

-- a fight
world.combat = true
fire("PLAYER_REGEN_DISABLED")
tick(0.2)
expect("no seal: calls command", shown(), "Seal of Command  [3]")
cast(20915); tick(0.2)
expect("quiet attack state", shown(), "Attack  [1]")
expect("reason line", ns.Halo.frame.why.text, "Building stacks: 0 of 3.")
for i = 1, 3 do
  fire("PLAYER_SWING", 3.3, 0)
  cast(20271, 8); tick(1.0); cast(1866, 10); tick(2.3)
end
expect("three stacks: calls righteousness", shown(), "Seal of Righteousness  [4]")
expect("swing ring was driven", ns.Halo.frame.swing.cooldown ~= nil, true)
cast(21084); tick(0.2)
expect("waiting for release", ns.Halo.frame.why.text, "Your next swing releases the stacks.")
fire("PLAYER_SWING", 3.3, 0); tick(0.2)
expect("after release: back to command", shown(), "Seal of Command  [3]")
cast(20915); tick(0.2)

-- a miss is undone when solo
fire("PLAYER_SWING", 3.3, 0); tick(0.5)
expect("swing released righteousness and stored command", ns.Game.tracker.stored, "command")
cast(1866, 10)
fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1); tick(0.1)
expect("a dodge right after an ability is the ability's", ns.Game.tracker.stored, "command")
tick(0.5)
fire("UNIT_COMBAT", "target", "PARRY", "", 0, 1); tick(0.1)
expect("a later parry undoes the swing", ns.Game.tracker.stored, "righteousness")
expect("miss counted", ns.Game.stats.misses, 1)
fire("UNIT_COMBAT", "target", "MISS", "", 0, 1); tick(0.1)
expect("one swing is only undone once", ns.Game.stats.misses, 1)
cast(20915); fire("PLAYER_SWING", 3.3, 0); tick(0.3)
world.known[99999] = true
C_Spell.GetSpellName = (function(old) return function(id) if id == 99999 then return "Seal of Righteousness" end return old(id) end end)(C_Spell.GetSpellName)
cast(99999); tick(0.1)
expect("a seal's extra hit is not mistaken for casting the seal", ns.Game.tracker.seal, "command")

-- secret payloads must not break anything
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", SECRET)
fire("PLAYER_SWING", SECRET, SECRET)
fire("UNIT_COMBAT", SECRET, SECRET, SECRET, SECRET, SECRET)
tick(0.2)

-- mana runs down
world.mana = 300; tick(0.3)
expect("low mana level", ns.Game.lastLevel, 2)
world.mana = 100; tick(0.3)
expect("nearly empty calls wisdom", shown():match("^Seal of Wisdom") ~= nil, true)
cast(20166); world.mana = 100; tick(0.3)
expect("recovering", ns.Halo.frame.why.text, "Recovering mana.")
world.mana = 2000; tick(0.3)
expect("mana back: command again", shown():match("^Seal of Command") ~= nil, true)

-- after the fight the real buffs are compared and adopted
world.combat = false
world.auras[20915] = { expirationTime = clock + 20 }
world.auras[1311703] = { applications = 2, expirationTime = clock + 9 }
fire("PLAYER_REGEN_ENABLED"); tick(0.2)
expect("adopted real stacks", ns.Game.tracker.stacks, 2)
expect("comparison counted", ns.Game.stats.compared, 1)
expect("kill time tallied for the mob and pattern", ns.db.kills["Plains Boar (40)"].burst.fights, 1)
ns.db.kills["Only Even (40)"] = { even = { fights = 1, seconds = 12, seals = 1 } }
ns.db.kills["Both (40)"] = { even = { fights = 2, seconds = 30, seals = 2 }, burst = { fights = 1, seconds = 14, seals = 2 } }
local both, single = ns.Game.compareLines()
expect("mob fought with both patterns", both[1], "Both (40): 3 and 1 14.0s over 1 fight, 3 and 3 15.0s over 2 fights")
expect("mob fought with one pattern", single[1], "Only Even (40): 3 and 3 12.0s over 1 fight")
SlashCmdList.SIGIL("compare")

-- aura reminders
world.form = 0; tick(0.2)
expect("no aura is reported", (ns.Halo.frame.marks.text or ""):find("No aura active", 1, true) ~= nil, true)
ns.db.aura = "ret_aura"; world.form = 1; tick(0.2)
expect("wrong aura is reported", (ns.Halo.frame.marks.text or ""):find("Switch to Retribution Aura", 1, true) ~= nil, true)
world.form = 2; tick(0.2)
expect("right aura: no reminder", (ns.Halo.frame.marks.text or ""):find("aura", 1, true), nil)

-- minimap button
local mb = SigilMinimapButton
expect("minimap button exists", mb ~= nil and mb.shown, true)
if ns.Options.frame then ns.Options.frame:Hide() end; mb.scripts.OnClick(mb, "LeftButton")
expect("left-click opens options", ns.Options.frame.shown, true)
mb.scripts.OnClick(mb, "RightButton")
expect("right-click opens setup", ns.Setup.frame.shown, true)
mb.scripts.OnEnter(mb); mb.scripts.OnLeave(mb)
mb.scripts.OnDragStart(mb); mb.scripts.OnUpdate(mb); mb.scripts.OnDragStop(mb)
expect("dragging moves it around the edge", math.floor(ns.db.minimapAngle + 0.5), 90)
Sigil_OnAddonCompartmentClick()

-- cooldown manager watching
BuffIconCooldownViewer = widget("Frame")
local echoItem = setmetatable({ cooldownID = 200341 }, { __index = function() return nil end })
function BuffIconCooldownViewer:GetChildren() return echoItem end
world.combat = true; fire("PLAYER_REGEN_DISABLED"); tick(1.0)
expect("cooldown manager button found", ns.Game.cdm.found[200341], "BuffIconCooldownViewer")
echoItem.auraInstanceID = SECRET; tick(0.6)
expect("a secret instance id reads as up", ns.Game.readCooldownManager().echo, true)
cast(20915); fire("PLAYER_SWING", 3.3, 0); tick(1.2)
expect("stacks kept while the button shows them", ns.Game.tracker.stacks > 0, true)
local fixesBefore = ns.Game.cdm.fixes or 0
echoItem.auraInstanceID = nil; tick(1.0)
expect("stacks dropped once the button says they are gone", ns.Game.tracker.stacks, 0)
expect("the correction is counted", ns.Game.cdm.fixes, fixesBefore + 1)
world.combat = false; fire("PLAYER_REGEN_ENABLED"); tick(0.2)

-- commands
SlashCmdList.SIGIL("check")
expect("report saved", type(SigilDB.report.lines), "table")
SlashCmdList.SIGIL("demo"); tick(12); SlashCmdList.SIGIL("demo")
ns.Setup.show(); SlashCmdList.SIGIL("")
expect("opening options closes setup", ns.Setup.frame.shown, false)
ns.Setup.show()
expect("opening setup closes options", ns.Options.frame.shown, false)
SlashCmdList.SIGIL(""); SlashCmdList.SIGIL("lock"); SlashCmdList.SIGIL("unlock"); SlashCmdList.SIGIL("macro"); SlashCmdList.SIGIL("reset"); SlashCmdList.SIGIL("nonsense")
for _, row in ipairs({ "locked", "hideErrors", "attackKeys", "consecration", "recover" }) do
  local c = ns.Options.frame.controls[row]
  if c.scripts.OnClick then c.scripts.OnClick(c) end
end
tick(0.3)

for _, line in ipairs(SigilCharDB.log) do
  if line:find("error") then failed = failed + 1; out("LOGGED " .. line) end
end
if arg and arg[1] == "-v" then for _, l in ipairs(SigilDB.report.lines) do out(l) end end
out(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
