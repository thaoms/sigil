-- The halo: one shape showing what to press, your stacks, your swing timer
-- and your mana.
local _, ns = ...
local Data = ns.Data

local Halo = {}
ns.Halo = Halo

local SIZE = 176                 -- pixels at scale 1; artwork is drawn on a 220-unit grid
local U = SIZE / 220
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function tex(parent, name, layer, sub)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
  t:SetTexture(Data.MEDIA .. name)
  t:SetAllPoints(parent)
  return t
end

local function tint(t, c, a)
  t:SetVertexColor(c[1], c[2], c[3], a or 1)
end

-- Cuts a square spell icon into a circle. Returns false if the client can't.
local function makeRound(owner, icon)
  local ok = pcall(function()
    local mask = owner:CreateMaskTexture()
    mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
  end)
  if not ok then pcall(icon.SetTexCoord, icon, 0.07, 0.93, 0.07, 0.93) end
  return ok
end

-- Shows the game's own icon for a call; falls back to Sigil's drawn glyph.
local function setIcon(icon, glyph, id, color)
  local file = ns.Game.icon(id)
  if file then
    icon:SetTexture(file)
    icon:SetVertexColor(1, 1, 1, 1)
    icon:Show()
    glyph:Hide()
  else
    icon:Hide()
    glyph:SetTexture(Data.MEDIA .. (Data.glyph[id] or "glyph_attack"))
    tint(glyph, color)
    glyph:Show()
  end
end

local function makeOrb(parent, size)
  local o = CreateFrame("Frame", nil, parent)
  o:SetSize(size, size)
  o.bg = tex(o, "orb", "BACKGROUND")
  o.icon = o:CreateTexture(nil, "ARTWORK")
  o.icon:SetPoint("CENTER")
  o.icon:SetSize(size * 0.86, size * 0.86)
  makeRound(o, o.icon)
  o.glyph = o:CreateTexture(nil, "ARTWORK")
  o.glyph:SetPoint("CENTER")
  o.glyph:SetSize(size * 0.62, size * 0.62)
  o.edge = tex(o, "orb_edge", "OVERLAY")
  o.key = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.key:SetPoint("TOP", o, "BOTTOM", 0, -1)
  pcall(o.key.SetFont, o.key, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
  o:Hide()
  return o
end

local function setOrb(o, id, key, alpha)
  if not id then o:Hide() return end
  local c = Data.color[id] or Data.color.ink
  setIcon(o.icon, o.glyph, id, c)
  tint(o.edge, c, 0.9)
  o.key:SetText(key or "")
  o:SetAlpha(alpha or 1)
  o:Show()
end

function Halo.create()
  local f = CreateFrame("Frame", "SigilHalo", UIParent)
  Halo.frame = f
  f:SetSize(SIZE, SIZE)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    if not ns.db.locked and not ns.Game.inCombat then self:StartMoving() end
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint(1)
    ns.db.pos = { point, rel, x, y }
  end)

  f.back = tex(f, "back", "BACKGROUND", -3)
  f.glow = tex(f, "glow", "BACKGROUND", -2)
  f.track = tex(f, "ring_track", "BACKGROUND", 1)
  tint(f.track, Data.color.ink, 0.3)

  -- swing timer: a ring that fills toward the notch
  local ok, swing = pcall(CreateFrame, "Cooldown", nil, f, "CooldownFrameTemplate")
  if ok and swing then
    f.swing = swing
    swing:SetAllPoints(f)
    pcall(swing.SetSwipeTexture, swing, Data.MEDIA .. "ring_fill")
    pcall(swing.SetSwipeColor, swing, Data.color.gold[1], Data.color.gold[2], Data.color.gold[3], 1)
    pcall(swing.SetUseCircularEdge, swing, true)
    pcall(swing.SetDrawEdge, swing, false)
    pcall(swing.SetDrawBling, swing, false)
    pcall(swing.SetHideCountdownNumbers, swing, true)
    pcall(swing.SetReverse, swing, true)
    pcall(swing.EnableMouse, swing, false)
  end

  local art = CreateFrame("Frame", nil, f)
  art:SetAllPoints(f)
  art:SetFrameLevel(f:GetFrameLevel() + 3)
  f.art = art

  f.notch = tex(art, "notch", "ARTWORK", 2)
  tint(f.notch, Data.color.gold)
  f.stacks = {}
  for i = 1, 3 do f.stacks[i] = tex(art, "stack" .. i, "ARTWORK", 1) end
  f.disc = tex(art, "disc", "ARTWORK", 2)

  -- the spell's own icon, cut round, small and centred on the dark disc.
  -- Game icons are 64 pixels: drawn larger than that they turn blurry.
  f.icon = art:CreateTexture(nil, "ARTWORK", nil, 3)
  f.icon:SetPoint("CENTER", 0, 12 * U)
  f.icon:SetSize(64 * U, 64 * U)
  makeRound(art, f.icon)
  f.glyph = art:CreateTexture(nil, "ARTWORK", nil, 3)
  f.glyph:SetPoint("CENTER", 0, 10 * U)
  f.glyph:SetSize(70 * U, 70 * U)
  f.edge = tex(art, "disc_edge", "OVERLAY", 1)
  f.burst = tex(art, "burst", "OVERLAY", 2)
  f.burst:SetAlpha(0)

  -- the swap cue: a thick ring that keeps bursting outward from the halo
  local pulse = CreateFrame("Frame", nil, f)
  pulse:SetPoint("CENTER")
  pulse:SetSize(SIZE, SIZE)
  pulse:SetFrameLevel(f:GetFrameLevel() + 2)
  f.pulseFrame = pulse
  f.pulse = tex(pulse, "pulse", "OVERLAY", 1)
  f.pulse:SetAlpha(0)
  pcall(f.pulse.SetBlendMode, f.pulse, "ADD")

  local labels = CreateFrame("Frame", nil, f)
  labels:SetAllPoints(f)
  labels:SetFrameLevel(f:GetFrameLevel() + 5)
  f.labels = labels

  -- real mana: the game draws the true value into this bar; Sigil never reads it
  local okBar, bar = pcall(CreateFrame, "StatusBar", nil, labels)
  if okBar and bar then
    f.manaBar = bar
    bar:SetSize(SIZE * 0.66, 6)
    bar:SetPoint("TOP", f, "BOTTOM", 0, 3)
    pcall(bar.SetStatusBarTexture, bar, "Interface\\Buttons\\WHITE8X8")
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)
    bg:SetColorTexture(0.02, 0.03, 0.05, 0.85)
  end

  -- dark plate behind the text so it reads on any ground
  f.plate = labels:CreateTexture(nil, "BACKGROUND")
  f.plate:SetColorTexture(0.02, 0.03, 0.05, 0.62)
  f.plate:SetPoint("TOP", f, "BOTTOM", 0, -8)
  f.plate:SetSize(SIZE * 1.75, 44)

  -- the key to press, large, at the bottom of the disc
  f.key = labels:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  f.key:SetPoint("CENTER", f, "CENTER", 0, -40 * U)
  f.key:SetTextColor(1, 1, 1)

  f.name = labels:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.name:SetPoint("TOP", f, "BOTTOM", 0, -14)
  f.why = labels:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.why:SetPoint("TOP", f.name, "BOTTOM", 0, -3)
  f.marks = labels:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.marks:SetPoint("TOP", f.why, "BOTTOM", 0, -4)
  f.marks:SetTextColor(1.00, 0.82, 0.30)
  local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  pcall(f.key.SetFont, f.key, font, 24, "THICKOUTLINE")
  pcall(f.name.SetFont, f.name, font, 16, "OUTLINE")
  pcall(f.why.SetFont, f.why, font, 12, "OUTLINE")
  pcall(f.marks.SetFont, f.marks, font, 12, "OUTLINE")

  f.orbs = {}
  for i = 1, 3 do
    f.orbs[i] = makeOrb(labels, (i == 1 and 54 or 46) * U)
  end
  f.orbs[1]:SetPoint("LEFT", f, "RIGHT", 6, 26 * U)
  f.orbs[2]:SetPoint("TOP", f.orbs[1], "BOTTOM", 0, -16)
  f.orbs[3]:SetPoint("TOP", f.orbs[2], "BOTTOM", 0, -16)

  f.hint = labels:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.hint:SetPoint("BOTTOM", f, "TOP", 0, 6)
  f.hint:SetText("Drag me. Lock with /sigil lock")
  f.hint:Hide()

  Halo.applyLayout()
  return f
end

function Halo.applyLayout()
  local f, db = Halo.frame, ns.db
  if not f then return end
  f:SetScale(db.scale or 1)
  f:ClearAllPoints()
  local p = db.pos
  if p then
    f:SetPoint(p[1] or "CENTER", UIParent, p[2] or "CENTER", p[3] or 0, p[4] or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
  end
  f:EnableMouse(not db.locked)
  if db.locked then f.hint:Hide() else f.hint:Show() end
end

function Halo.swing(now, speed)
  local f = Halo.frame
  if f and f.swing and speed and speed > 0 then
    pcall(f.swing.SetCooldown, f.swing, now, speed)
  end
end

function Halo.release(released)
  local f = Halo.frame
  if not f then return end
  tint(f.burst, Data.color[released.seal] or Data.color.gold)
  f.burstUntil = GetTime() + 0.6
end

-- Feeds the hidden mana value straight into the bar. The game accepts the
-- hidden number here; if it ever refuses, the bar is switched off.
function Halo.updateMana(level)
  local f = Halo.frame
  local bar = f and f.manaBar
  if not bar or f.manaBarBroken then return end
  local ok = pcall(function()
    bar:SetMinMaxValues(0, UnitPowerMax("player", 0))
    bar:SetValue(UnitPower("player", 0))
  end)
  if not ok then
    f.manaBarBroken = true
    bar:Hide()
    ns.Game.log("mana bar refused the value; hidden")
    return
  end
  local c = Data.manaColor[level or 3]
  pcall(bar.SetStatusBarColor, bar, c[1], c[2], c[3], 1)
end

Halo.SOUNDS = {
  ready = { "READY_CHECK", 8960 },
  warning = { "RAID_WARNING", 8959 },
  click = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856 },
}

function Halo.playCue(kind)
  local s = Halo.SOUNDS[kind]
  if not s then return end
  local id = (SOUNDKIT and SOUNDKIT[s[1]]) or s[2]
  local ok, played = pcall(PlaySound, id, "Master")
  if not ok or played == false then ns.Game.log("sound %s (%s) did not play", tostring(kind), tostring(id)) end
end

-- Draws one decision from the engine.
function Halo.render(d, demo)
  local f, db, Game = Halo.frame, ns.db, ns.Game
  if not f then return end
  local main = d.main
  local idle = main.id == "idle"

  if db.onlyCombat and idle and db.locked and not demo then
    f:SetAlpha(0)
    f.pulsing = false
    return
  end
  f:SetAlpha(1)
  local dim = idle and 0.75 or 1
  f.art:SetAlpha(dim)
  f.back:SetAlpha(dim)
  if f.swing then f.swing:SetAlpha(dim) end

  local c = Data.color[main.id] or Data.color.gold
  setIcon(f.icon, f.glyph, main.id, c)
  pcall(f.icon.SetDesaturated, f.icon, idle)
  f.icon:SetAlpha(idle and 0.6 or 1)
  tint(f.edge, c, main.urgent and 1 or 0.8)
  tint(f.glow, c, main.urgent and 1 or 0.55)
  f.pulsing = main.urgent and not idle
  if f.pulsing then tint(f.pulse, c) else f.pulse:SetAlpha(0) end

  local stackColor = Data.color[d.stored or ""] or Data.color.gold
  for i = 1, 3 do
    if i <= (d.stacks or 0) then tint(f.stacks[i], stackColor, 1) else tint(f.stacks[i], Data.color.ink, 0.28) end
  end
  Halo.updateMana(d.mana)

  local lines = 0
  if idle then
    f.name:SetText("")
    f.why:SetText("")
    f.key:SetText("")
  else
    local key = demo and (demo.keys[main.id]) or Game.keyFor(main.id)
    f.key:SetText(key or "")
    f.name:SetText((main.id == "attack") and "Attack" or Game.name(main.id))
    f.name:SetTextColor(0.5 + c[1] * 0.5, 0.5 + c[2] * 0.5, 0.5 + c[3] * 0.5)
    local why = db.showWhy and main.why or ""
    f.why:SetText(why)
    lines = 1 + (why ~= "" and 1 or 0)
  end

  local slot = 1
  if d.next then
    setOrb(f.orbs[slot], d.next, demo and demo.keys[d.next] or Game.keyFor(d.next), 0.75)
    slot = slot + 1
  end
  for _, id in ipairs(d.side) do
    if slot <= 3 then
      setOrb(f.orbs[slot], id, demo and demo.keys[id] or Game.keyFor(id), 1)
      slot = slot + 1
    end
  end
  for i = slot, 3 do f.orbs[i]:Hide() end

  local marks = {}
  local wanted = db.aura ~= "any" and Game.known[db.aura] and Game.name(db.aura) or nil
  if d.marks.aura then marks[#marks + 1] = wanted and ("No aura: cast " .. wanted) or "No aura active" end
  if d.marks.auraWrong and wanted then marks[#marks + 1] = "Switch to " .. wanted end
  if d.marks.blessing then marks[#marks + 1] = "No blessing" end
  if d.marks.blessingOfWisdom then marks[#marks + 1] = "Low mana: Blessing of Wisdom" end
  if d.marks.drink then marks[#marks + 1] = "Drink before the next pull" end
  if not Game.keyFor("attack") and not demo and not idle then marks[#marks + 1] = "Attack is not on your bar: /sigil setup" end
  f.marks:SetText(table.concat(marks, "  ·  "))
  f.marks:ClearAllPoints()
  if lines == 0 then
    f.marks:SetPoint("TOP", f, "BOTTOM", 0, -14)
  elseif lines == 1 then
    f.marks:SetPoint("TOP", f.name, "BOTTOM", 0, -4)
  else
    f.marks:SetPoint("TOP", f.why, "BOTTOM", 0, -4)
  end
  if #marks > 0 then lines = lines + 1 end
  if lines == 0 then
    f.plate:Hide()
  else
    local widest = 0
    for _, fs in ipairs({ f.name, f.why, f.marks }) do
      local w = fs.GetStringWidth and fs:GetStringWidth() or 0
      if type(w) == "number" and w > widest then widest = w end
    end
    f.plate:SetWidth(widest > 0 and (widest + 28) or SIZE * 1.75)
    f.plate:SetHeight(12 + (idle and 0 or 22) + (lines - (idle and 0 or 1)) * 17)
    f.plate:Show()
  end

  if main.urgent and main.id ~= f.lastUrgent and not demo and db.cue ~= "off" then
    Halo.playCue(db.cue or "ready")
  end
  f.lastUrgent = main.urgent and main.id or nil
end

-- Per-frame motion: the swap pulse and the release flash.
function Halo.animate(now)
  local f = Halo.frame
  if not f then return end
  if f.burstUntil then
    local left = f.burstUntil - now
    if left <= 0 then f.burst:SetAlpha(0); f.burstUntil = nil else f.burst:SetAlpha(left / 0.6) end
  end
  if f.pulsing then
    local phase = (now % 0.9) / 0.9
    local size = SIZE * (0.9 + 0.35 * phase)
    f.pulseFrame:SetSize(size, size)
    f.pulse:SetAlpha(0.7 * (1 - phase * phase))
    -- the key number blinks too, so the cue is visible even at a glance
    f.key:SetAlpha(phase < 0.5 and 1 or 0.45)
  elseif f.key then
    f.key:SetAlpha(1)
  end
end
