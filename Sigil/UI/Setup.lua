-- First-run setup: a checklist of Sigil's buttons, where they are, and a
-- way to put the missing ones on the bar without overwriting anything.
local _, ns = ...
local Data = ns.Data

local Setup = {}
ns.Setup = Setup

local W, ROW = 430, 30

local function panel(name, width, height)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(width, height)
  f:SetPoint("CENTER", 0, 60)
  f:SetFrameStrata("DIALOG")
  if f.SetToplevel then f:SetToplevel(true) end
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.03, 0.05, 0.08, 0.96)
  local line = f:CreateTexture(nil, "BORDER")
  line:SetPoint("TOPLEFT")
  line:SetPoint("TOPRIGHT")
  line:SetHeight(2)
  line:SetColorTexture(0.91, 0.73, 0.34, 0.9)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", 16, -14)
  f:Hide()
  if name and UISpecialFrames then table.insert(UISpecialFrames, name) end
  return f
end
ns.panel = panel

local function button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end
ns.button = button

-- The buttons Sigil will call, given the chosen seal pair and opener.
local function items()
  local list = ns.db.attackKeys == 2 and { "judgement", "holy_strike" } or { "attack" }
  local seen = {}
  local function add(id)
    if id and not seen[id] then seen[id] = true; list[#list + 1] = id end
  end
  local primary, secondary = ns.Engine.pair(ns.Game.knownFlags(), ns.db)
  add(primary); add(secondary)
  if ns.db.opener and ns.db.opener ~= "off" then add("crusader") end
  add("consecration"); add("hoj"); add("how"); add("wisdom")
  return list
end

local function learned(id)
  if id == "attack" then return ns.Game.known.judgement or ns.Game.known.holy_strike end
  return ns.Game.known[id]
end

local HELP = {
  attack = "Spam this. It casts whichever attack is ready.",
  judgement = "Press on cooldown.",
  holy_strike = "Press on cooldown.",
  command = "Halo calls it.",
  righteousness = "Halo calls it.",
  light = "Halo calls it.",
  justice = "Halo calls it.",
  crusader = "Opener, once per target.",
  consecration = "For packs of enemies.",
  hoj = "Stun just before Judgement.",
  how = "When the target is low.",
  wisdom = "When mana is nearly empty.",
}

function Setup.create()
  local f = panel("SigilSetup", W, 490)
  Setup.frame = f
  f.title:SetText("Sigil setup")

  f.intro = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.intro:SetPoint("TOPLEFT", 16, -38)
  f.intro:SetWidth(W - 32)
  f.intro:SetJustifyH("LEFT")

  f.rows = {}
  for i = 1, 9 do
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(W - 32, ROW)
    r:SetPoint("TOPLEFT", 16, -78 - (i - 1) * (ROW + 4))
    r.glyph = r:CreateTexture(nil, "ARTWORK")
    r.glyph:SetSize(26, 26)
    r.glyph:SetPoint("LEFT")
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", r.glyph, "TOPRIGHT", 8, 0)
    r.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.status:SetPoint("BOTTOMLEFT", r.glyph, "BOTTOMRIGHT", 8, -1)
    r.pick = button(r, "Pick up", 70, function()
      if ns.Game.inCombat then ns.say("You can't move buttons in combat.") return end
      if ns.Game.pickup(r.id) then
        ns.say("Now click an empty action bar slot to drop it.")
      else
        ns.say("Couldn't pick that up. Drag it from your spellbook instead.")
      end
    end)
    r.pick:SetPoint("RIGHT")
    f.rows[i] = r
  end

  f.plan = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.plan:SetPoint("BOTTOMLEFT", 16, 74)
  f.plan:SetWidth(W - 32)
  f.plan:SetJustifyH("LEFT")

  f.place = button(f, "Place missing buttons", 170, function() Setup.placeClicked() end)
  f.place:SetPoint("BOTTOMLEFT", 16, 44)
  f.move = button(f, "Move the halo", 120, function()
    ns.db.locked = not ns.db.locked
    ns.Halo.applyLayout()
    Setup.refresh()
  end)
  f.move:SetPoint("LEFT", f.place, "RIGHT", 8, 0)
  f.demo = button(f, "Play demo", 100, function() ns.toggleDemo() end)
  f.demo:SetPoint("LEFT", f.move, "RIGHT", 8, 0)

  f.options = button(f, "Options", 90, function() ns.Options.toggle() end)
  f.options:SetPoint("BOTTOMLEFT", 16, 14)
  f.close = button(f, "Done", 90, function()
    ns.db.setupDone = true
    if not ns.db.locked then
      ns.db.locked = true
      ns.Halo.applyLayout()
      ns.say("Halo locked. Type /sigil unlock to move it again.")
    end
    f:Hide()
  end)
  f.close:SetPoint("BOTTOMRIGHT", -16, 14)
  f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.foot:SetPoint("LEFT", f.options, "RIGHT", 10, 0)
  f.foot:SetPoint("RIGHT", f.close, "LEFT", -10, 0)
  f.foot:SetJustifyH("LEFT")
  f:SetScript("OnHide", function() ns.db.setupDone = true end)
end

local function missing()
  local list = {}
  for _, id in ipairs(items()) do
    if learned(id) and ns.Game.keys[id] == nil then list[#list + 1] = id end
  end
  return list
end

function Setup.placeClicked()
  local f = Setup.frame
  if ns.Game.inCombat then ns.say("You can't move buttons in combat.") return end
  if f.pending then
    local done = ns.Game.place(f.pending)
    local wanted = #f.pending
    f.pending = nil
    if done == wanted then
      ns.say(("Placed %d button%s."):format(done, done == 1 and "" or "s"))
    else
      ns.say(("Placed %d of %d. Use Pick up for the rest and drop them on your bar."):format(done, wanted))
    end
    Setup.refresh()
    return
  end
  local plan = ns.Game.placementPlan(missing())
  if #plan == 0 then
    f.plan:SetText("No empty slots found. Use Pick up and drop each button where you want it.")
    return
  end
  local lines = { "Sigil will fill these empty slots. Nothing is replaced:" }
  for _, p in ipairs(plan) do
    lines[#lines + 1] = ("  %s  ->  %s"):format(p.id == "attack" and "Attack" or ns.Game.name(p.id), ns.Game.slotLabel(p.slot))
  end
  f.plan:SetText(table.concat(lines, "\n"))
  f.pending = plan
  f.place:SetText("Confirm")
end

function Setup.refresh()
  local f = Setup.frame
  if not f or not f:IsShown() then return end
  local Game, db = ns.Game, ns.db
  local list = items()
  local intro
  if db.attackKeys == 2 then
    intro = "Two attack keys: press Judgement and Holy Strike on cooldown. The halo tells you when to press a seal."
  elseif Game.macroState == "later" or Game.macroState == nil then
    intro = "Setting up the Attack macro..."
  elseif Game.macroState == "failed" then
    intro = "Sigil couldn't create the Attack macro. Type /sigil macro to see its text and make it yourself, or switch to two attack keys in Options."
  else
    intro = "Sigil made an Attack macro for you. Put these buttons on your bar, spam Attack, and press a seal key when the halo tells you to."
  end
  f.intro:SetText(intro)

  local count = 0
  for i, r in ipairs(f.rows) do
    local id = list[i]
    r.id = id
    if id then
      r:Show()
      local c = Data.color[id] or Data.color.gold
      r.glyph:SetTexture(Data.MEDIA .. (Data.glyph[id] or "glyph_attack"))
      r.glyph:SetVertexColor(c[1], c[2], c[3])
      r.name:SetText((id == "attack" and "Attack" or Game.name(id)) .. "  |cff8d95a4" .. (HELP[id] or "") .. "|r")
      local key = Game.keys[id]
      if not learned(id) then
        r.status:SetText("|cff8d95a4Not learned yet|r")
        r.pick:Hide()
      elseif key then
        r.status:SetText("|cff7fd48aOn key " .. key .. "|r")
        r.pick:Hide()
      elseif key == false then
        r.status:SetText("|cffffb347On your bar, but no key is bound to that slot|r")
        r.pick:Hide()
      else
        r.status:SetText("|cffffb347Not on your bar|r")
        r.pick:Show()
        count = count + 1
      end
    else
      r:Hide()
    end
  end

  if not f.pending then
    f.place:SetText("Place missing buttons")
    f.plan:SetText(count == 0 and "|cff7fd48aEverything is on your bar. You're ready.|r" or "")
  end
  if count == 0 and not f.pending then f.place:Disable() else f.place:Enable() end
  f.move:SetText(db.locked and "Move the halo" or "Lock the halo")
  f.demo:SetText(ns.demo and "Stop demo" or "Play demo")
  local how = Game.unsealedWrathHow
  f.foot:SetText(Game.unsealedWrath
    and ("Unsealed Wrath: " .. (how == "assumed" and "assumed" or "found"))
    or "Unsealed Wrath not found: no seal swapping")
end
ns.refreshSetup = Setup.refresh

function Setup.show()
  if not Setup.frame then Setup.create() end
  if ns.Options.frame then ns.Options.frame:Hide() end   -- one window at a time
  Setup.frame.pending = nil
  ns.Game.scanKeys()
  Setup.frame:Show()
  Setup.refresh()
end
