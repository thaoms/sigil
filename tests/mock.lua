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
function UnitGUID() return "Creature-0-1" end
function UnitClassification() return world.classification or "normal" end
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
    local names = { [20271] = "Judgement", [1866] = "Holy Strike", [879] = "Exorcism", [26573] = "Consecration", [853] = "Hammer of Justice", [24275] = "Hammer of Wrath",
      [20915] = "Seal of Command", [21084] = "Seal of Righteousness", [20166] = "Seal of Wisdom", [7294] = "Retribution Aura", [19740] = "Blessing of Might" }
    return names[id] or ("Spell " .. id)
  end,
  IsSpellInRange = function(id, unit) if unit and unit:find("nameplate") then return (world.near or {})[unit] end return true end,
  IsSpellUsable = function(id)
    local c = world.cost[id] or 0
    if world.unusable and world.unusable[id] then return false, false end
    return world.mana >= c, world.mana < c
  end,
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
expect("there is no stun setting", ns.db.stun, nil)
expect("macro created", world.macros.SigilAttack, "#showtooltip Holy Strike\n/startattack\n/cast Judgement\n/cast Holy Strike")
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
tick(0.3)
fire("UNIT_COMBAT", "target", "PARRY", "", 0, 1); tick(0.1)
expect("a later parry undoes the swing", ns.Game.tracker.stored, "righteousness")
expect("miss counted", ns.Game.stats.misses, 1)
fire("UNIT_COMBAT", "target", "MISS", "", 0, 1); tick(0.1)
expect("one swing is only undone once", ns.Game.stats.misses, 1)
cast(26573, 8); tick(0.3)
fire("PLAYER_SWING", 3.3, 0); tick(0.7)
local storedC, stacksC = ns.Game.tracker.stored, ns.Game.tracker.stacks
fire("UNIT_COMBAT", "target", "MISS", "", 0, 1); tick(0.1)
expect("a miss just after Consecration is not counted", ns.Game.stats.misses, 1)
expect("the swing after Consecration is kept", ns.Game.tracker.stacks, stacksC)
expect("and its seal", ns.Game.tracker.stored, storedC)
tick(2)
world.inGroup = true
fire("PLAYER_SWING", 3.3, 0); tick(0.5)
local missesBefore = ns.Game.stats.misses
local storedBefore, stacksBefore = ns.Game.tracker.stored, ns.Game.tracker.stacks
fire("UNIT_COMBAT", "target", "PARRY", "", 0, 1); tick(0.1)
expect("in a group a miss is not counted", ns.Game.stats.misses, missesBefore)
expect("in a group the swing is kept", ns.Game.tracker.stored, storedBefore)
expect("in a group the stacks are kept", ns.Game.tracker.stacks, stacksBefore)
world.inGroup = false
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

-- crusader opener on an elite
world.known[21082] = true; world.cost[21082] = 90; ns.Game.scanSpells()
ns.db.opener = "elite"; world.classification = "elite"
ns.Game.tracker.seal = nil; world.target = true; tick(0.2)
expect("elite target: opener is called", ns.Halo.frame.name.text, "Spell 21082")
cast(21082); tick(0.2); cast(20271, 8); tick(0.2)
expect("after the marking Judgement: main seal", ns.Halo.frame.name.text, "Seal of Command")
cast(20915); tick(0.2)
ns.db.opener = "off"; world.classification = nil

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
local stackFs = widget("FontString"); stackFs.text = SECRET
echoItem.Applications = setmetatable({ Applications = stackFs }, { __index = function() return nil end })
tick(0.6)
expect("the button's stack number is left alone", ns.Halo.frame.real, nil)
expect("the arcs keep showing", ns.Halo.frame.stacks[1].alpha, 1)
echoItem.auraInstanceID = nil; tick(0.6)
expect("no stacks reads as down", ns.Game.readCooldownManager().echo, false)
echoItem.auraInstanceID = SECRET; tick(0.6)
-- the Cooldown Manager says stacks exist while Sigil counts none
ns.Game.tracker.stacks, ns.Game.tracker.stored = 0, nil
fire("PLAYER_SWING", 3.3, 0); ns.Game.tracker.stacks, ns.Game.tracker.stored = 0, nil
tick(1.5)
expect("stacks shown, none counted: set to one", ns.Game.tracker.stacks, 1)
-- a Seal of Command extra hit while Righteousness is up and Sigil saw no release
cast(21084); tick(0.2)
ns.Game.tracker.stored, ns.Game.tracker.stacks = "righteousness", 2
fire("PLAYER_SWING", 3.3, 0); ns.Game.tracker.stored, ns.Game.tracker.stacks, ns.Game.tracker.lastRelease = "righteousness", 3, nil
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 20424); tick(0.1)
expect("command proc evidence resets the count", ns.Game.tracker.stacks, 1)
local fixes = ns.Game.cdm.fixes
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 20424); tick(0.1)
expect("only one correction per swing", ns.Game.cdm.fixes, fixes)
echoItem.Applications = nil; tick(0.6)
cast(20915); tick(0.2)
world.combat = false; fire("PLAYER_REGEN_ENABLED"); tick(0.2)

-- enemies near you: only nameplates within range count
fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); fire("NAME_PLATE_UNIT_ADDED", "nameplate2"); fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
local oldExists = UnitExists
UnitExists = function(u) return u:find("nameplate") and true or oldExists(u) end
world.combat = true
world.near = { nameplate1 = true, nameplate2 = false, nameplate3 = false }
expect("only enemies in range are counted", ns.Game.enemies(), 1)
world.near = { nameplate1 = true, nameplate2 = true, nameplate3 = true }
expect("a pack next to you counts fully", ns.Game.enemies(), 3)
world.near = {}
expect("no range answer: count every enemy in combat", ns.Game.enemies(), 3)
UnitExists = oldExists; world.near = nil
world.combat = false

-- dying clears the seal and stacks
ns.Game.tracker:castSeal("command", clock); ns.Game.tracker.stacks, ns.Game.tracker.stored = 2, "command"
fire("PLAYER_DEAD"); tick(0.1)
expect("death clears the seal", ns.Game.tracker.seal, nil)
expect("death clears the stacks", ns.Game.tracker.stacks, 0)

-- game-drawn stacks: the game's aura display fills the arcs itself
expect("without the aura display nothing is built", ns.Native.ready, false)
local containers = {}
local plainCreateFrame = CreateFrame
CreateFrame = function(kind, name, parent, template)
  local f = plainCreateFrame(kind, name)
  if kind == "AuraContainer" then
    containers[#containers + 1] = f
    f.template = template
    function f:SetUnit(u) self.unit = u end
    function f:AddAuraSlot(slot, filter, opts) self.slot = { name = slot, filter = filter, opts = opts } end
  end
  return f
end
CustomAuraContainerAuraProcessingPolicy, C_AuraContainerUtil = { None = 0 }, {}
local function gameButton(refuseLowerBound)
  local b = widget("Button")
  function b:SetApplicationBar(bar, o)
    if refuseLowerBound and o.minApplications then error("unknown option minApplications") end
    self.bar, self.range = bar, o
  end
  return b
end
world.combat = true
ns.Native.build()
expect("not built in combat", ns.Native.ready, false)
expect("waits for combat to end", #containers, 0)
world.combat = false; fire("PLAYER_REGEN_ENABLED")
expect("built when combat ends", ns.Native.ready, true)
local echoes = 0
for _ in pairs(ns.Data.echo) do echoes = echoes + 1 end
expect("three arcs for every seal's Echo", #containers, echoes * 3)
local perEcho, ranges, wrongSlot = {}, {}, 0
for _, c in ipairs(containers) do
  local ids = c.slot.opts.candidateFilters.includeSpellIDs
  local n, id = 0, nil
  for k in pairs(ids) do n, id = n + 1, k end
  if n ~= 1 or c.unit ~= "player" or c.slot.filter ~= "HELPFUL" or c.template ~= "CustomAuraContainerTemplate" then wrongSlot = wrongSlot + 1 end
  perEcho[id] = (perEcho[id] or 0) + 1
  local b = gameButton()
  c.slot.opts.initializeFrame(b)
  ranges[#ranges + 1] = b.range.minApplications .. "-" .. b.range.maxApplications
end
expect("each arc follows one of your Echo buffs", wrongSlot, 0)
local evenly = true
for _, id in pairs(ns.Data.echo) do if perEcho[id] ~= 3 then evenly = false end end
expect("every Echo buff gets exactly three arcs", evenly, true)
local seen = {}
for _, r in ipairs(ranges) do seen[r] = (seen[r] or 0) + 1 end
expect("arc 1 covers 0 to 1 stacks", seen["0-1"], echoes)
expect("arc 2 covers 1 to 2 stacks", seen["1-2"], echoes)
expect("arc 3 covers 2 to 3 stacks", seen["2-3"], echoes)
tick(0.6)
expect("the game-drawn arcs show", ns.Native.wrap.alpha, 1)
expect("Sigil's arcs stay as the empty track", ns.Halo.frame.stacks[3].alpha, 1)
SlashCmdList.SIGIL("demo"); tick(1)
expect("the demo hides the real arcs", ns.Native.wrap.alpha, 0)
SlashCmdList.SIGIL("demo"); tick(0.6)
expect("they come back after the demo", ns.Native.wrap.alpha, 1)
ns.db.realStacks = false; tick(0.6)
expect("the option turns them off", ns.Native.wrap.alpha, 0)
ns.db.realStacks = true; tick(0.6)
-- a client that refuses the lower bound would fill arcs part way: give up instead
containers[1].slot.opts.initializeFrame(gameButton(true))
tick(0.6)
expect("a refused range turns them off", ns.Native.wrap.alpha, 0)
expect("and says why", ns.Native.status:find("refused") ~= nil, true)
expect("Sigil's own arcs take over", ns.Halo.frame.stacks[1].alpha, 1)
for i = #SigilCharDB.log, 1, -1 do   -- that error was on purpose
  if SigilCharDB.log[i]:find("refused the arc range") then table.remove(SigilCharDB.log, i) end
end
CreateFrame = plainCreateFrame

-- commands
SlashCmdList.SIGIL("check")
local reported = false
for _, l in ipairs(SigilDB.report.lines) do if l:find("game%-drawn stacks: ") then reported = true end end
expect("the check report says how the stacks are shown", reported, true)
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

-- Hammer of Wrath: never in the macro, marked only when the game allows it
ns.db.attackKeys = 1
world.known[24275] = true; world.cost[24275] = 50; world.unusable = {}
ns.Game.scanSpells(); ns.Options.apply("attackKeys")
expect("hammer of wrath is known", ns.Game.known.how, 24275)
expect("hammer of wrath stays out of the macro", world.macros.SigilAttack:find("Hammer of Wrath", 1, true), nil)
expect("holy strike is still in the macro", world.macros.SigilAttack:find("/cast Holy Strike", 1, true) ~= nil, true)
expect("not trusted before the game has said no once", ns.Game.view().usable.how, nil)
world.unusable = { [24275] = true }
expect("no mark on a healthy target", ns.Game.view().usable.how, false)
expect("the 20% gate is remembered", ns.db.howGate, true)
world.unusable = {}
expect("usable on a low target", ns.Game.view().usable.how, true)
world.unusable = { [24275] = true }; world.cooling[29515] = clock + 1.5
expect("a reading during the global cooldown is ignored", ns.Game.view().usable.how, true)
world.cooling[29515] = nil
expect("read again after it", ns.Game.view().usable.how, false)
world.unusable = {}

-- Exorcism: out of the macro, marked only on undead and demons
expect("exorcism stays out of the macro", world.macros.SigilAttack:find("Exorcism", 1, true), nil)
expect("exorcism not trusted before the game has said no once", ns.Game.view().usable.exorcism, nil)
world.unusable = { [879] = true }
expect("no exorcism on a beast", ns.Game.view().usable.exorcism, false)
expect("the exorcism gate is remembered", ns.db.exorcismGate, true)
world.unusable = {}
expect("exorcism usable on undead", ns.Game.view().usable.exorcism, true)

for _, line in ipairs(SigilCharDB.log) do
  if line:find("error") then failed = failed + 1; out("LOGGED " .. line) end
end
if arg and arg[1] == "-v" then for _, l in ipairs(SigilDB.report.lines) do out(l) end end
out(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
