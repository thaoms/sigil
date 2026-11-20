-- The halo: one shape showing what to press, your stacks, your swing timer
-- and your mana level.
local _, ns = ...
local Data = ns.Data

local Halo = {}
ns.Halo = Halo

local SIZE = 176                 -- pixels at scale 1; artwork is drawn on a 220-unit grid
local U = SIZE / 220

local function tex(parent, name, layer, sub)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
  t:SetTexture(Data.MEDIA .. name)
  t:SetAllPoints(parent)
  return t
end

local function tint(t, c, a)
  t:SetVertexColor(c[1], c[2], c[3], a or 1)
end

local function makeOrb(parent, size)
  local o = CreateFrame("Frame", nil, parent)
  o:SetSize(size, size)
  o.bg = tex(o, "orb", "BACKGROUND")
  o.edge = tex(o, "orb_edge", "BORDER")
  o.glyph = o:CreateTexture(nil, "ARTWORK")
  o.glyph:SetPoint("CENTER")
  o.glyph:SetSize(size * 0.62, size * 0.62)
  o.key = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.key:SetPoint("TOP", o, "BOTTOM", 0, -1)
  o:Hide()
  return o
end

local function setOrb(o, id, key, alpha)
  if not id then o:Hide() return end
  local c = Data.color[id] or Data.color.ink
  o.glyph:SetTexture(Data.MEDIA .. (Data.glyph[id] or "glyph_attack"))
  tint(o.glyph, c)
  tint(o.edge, c, 0.45)
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

  f.glow = tex(f, "glow", "BACKGROUND", -2)
  f.track = tex(f, "ring_track", "BACKGROUND", 1)
  tint(f.track, Data.color.ink, 0.13)

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
  f.stacks, f.mana = {}, {}
  for i = 1, 3 do
    f.stacks[i] = tex(art, "stack" .. i, "ARTWORK", 1)
    f.mana[i] = tex(art, "mana" .. i, "ARTWORK", 1)
  end
  f.disc = tex(art, "disc", "ARTWORK", 2)
  f.edge = tex(art, "disc_edge", "ARTWORK", 3)
  f.pulse = tex(art, "pulse", "OVERLAY", 1)
  f.pulse:SetAlpha(0)
  f.burst = tex(art, "burst", "OVERLAY", 2)
  f.burst:SetAlpha(0)

  f.glyph = art:CreateTexture(nil, "OVERLAY", nil, 3)
  f.glyph:SetPoint("CENTER")
  f.glyph:SetSize(76 * U, 76 * U)

  local okAnim, group = pcall(f.pulse.CreateAnimationGroup, f.pulse)
  if okAnim and group then
    pcall(function()
      group:SetLooping("BOUNCE")
      local a = group:CreateAnimation("Alpha")
      a:SetFromAlpha(0.9)
      a:SetToAlpha(0.1)
      a:SetDuration(0.45)
    end)
    f.pulseAnim = group
  end

  f.name = art:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.name:SetPoint("TOP", f, "BOTTOM", 0, -4)
  f.why = art:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.why:SetPoint("TOP", f.name, "BOTTOM", 0, -3)
  f.why:SetWidth(SIZE * 1.6)
  f.marks = art:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.marks:SetPoint("TOP", f.why, "BOTTOM", 0, -4)
  f.marks:SetWidth(SIZE * 1.8)
  f.marks:SetTextColor(Data.color.warn[1], Data.color.warn[2], Data.color.warn[3])

  f.orbs = {}
  for i = 1, 3 do
    local size = (i == 1 and 54 or 46) * U
    local o = makeOrb(art, size)
    f.orbs[i] = o
  end
  f.orbs[1]:SetPoint("LEFT", f, "RIGHT", 6, 26 * U)
  f.orbs[2]:SetPoint("TOP", f.orbs[1], "BOTTOM", 0, -16)
  f.orbs[3]:SetPoint("TOP", f.orbs[2], "BOTTOM", 0, -16)

  f.hint = art:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

local function setPulse(f, on, c)
  if on == f.pulsing then return end
  f.pulsing = on
  if on then
    tint(f.pulse, c)
    if f.pulseAnim then pcall(f.pulseAnim.Play, f.pulseAnim) else f.pulse:SetAlpha(0.8) end
  else
    if f.pulseAnim then pcall(f.pulseAnim.Stop, f.pulseAnim) end
    f.pulse:SetAlpha(0)
  end
end

-- Draws one decision from the engine.
function Halo.render(d, demo)
  local f, db, Game = Halo.frame, ns.db, ns.Game
  if not f then return end
  local main = d.main
  local idle = main.id == "idle"

  if db.onlyCombat and idle and db.locked and not demo then
    f:SetAlpha(0)
    return
  end
  f:SetAlpha(idle and 0.45 or 1)

  local c = Data.color[main.id] or Data.color.gold
  f.glyph:SetTexture(Data.MEDIA .. (Data.glyph[main.id] or "glyph_attack"))
  tint(f.glyph, c, idle and 0.5 or 1)
  tint(f.edge, c, 0.5)
  tint(f.glow, c, main.urgent and 1 or 0.55)
  setPulse(f, main.urgent and not idle, c)

  local stackColor = Data.color[d.stored or ""] or Data.color.gold
  for i = 1, 3 do
    if i <= (d.stacks or 0) then tint(f.stacks[i], stackColor, 1) else tint(f.stacks[i], Data.color.ink, 0.13) end
    local level = d.mana or 3
    if i <= level then tint(f.mana[i], Data.manaColor[level], 1) else tint(f.mana[i], Data.color.ink, 0.13) end
  end

  if idle then
    f.name:SetText("")
    f.why:SetText("")
  else
    local key = demo and (demo.keys[main.id]) or Game.keyFor(main.id)
    local label = (main.id == "attack") and "Attack" or Game.name(main.id)
    if key then label = ("%s  |cffffffff[%s]|r"):format(label, key) end
    f.name:SetText(label)
    f.name:SetTextColor(c[1], c[2], c[3])
    f.why:SetText(db.showWhy and main.why or "")
  end

  local slot = 1
  if d.next then
    setOrb(f.orbs[slot], d.next, demo and demo.keys[d.next] or Game.keyFor(d.next), 0.7)
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
  if d.marks.aura then marks[#marks + 1] = "Retribution Aura is off" end
  if d.marks.blessing then marks[#marks + 1] = "No blessing" end
  if d.marks.blessingOfWisdom then marks[#marks + 1] = "Low mana: Blessing of Wisdom" end
  if d.marks.drink then marks[#marks + 1] = "Drink before the next pull" end
  if not Game.keyFor("attack") and not demo and not idle then marks[#marks + 1] = "Attack is not on your bar: /sigil setup" end
  f.marks:SetText(table.concat(marks, "  ·  "))

  if db.sound and main.urgent and main.id ~= f.lastUrgent and not demo then
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856, "Master")
  end
  f.lastUrgent = main.urgent and main.id or nil
end

function Halo.animate(now)
  local f = Halo.frame
  if not f then return end
  if f.burstUntil then
    local left = f.burstUntil - now
    if left <= 0 then f.burst:SetAlpha(0); f.burstUntil = nil else f.burst:SetAlpha(left / 0.6) end
  end
end
