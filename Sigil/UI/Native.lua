-- Game-drawn stacks. In combat the game hides Unsealed Wrath's stack count
-- from addons, but its aura display (AuraContainer) can still draw it: Sigil
-- says which buff to show and where, and the game fills in the count itself.
-- Sigil never reads the value.
--
-- Each of the halo's three arcs becomes a status bar the game fills from an
-- Echo buff's stack count: arc 1 covers 0 to 1 stacks, arc 2 covers 1 to 2,
-- arc 3 covers 2 to 3. Counts are whole numbers, so every arc is either empty
-- or full. Every seal's Echo buff gets its own three arcs in that seal's
-- colour; the game only draws the buffs you have.
--
-- Once built, the game owns these frames: Sigil may not restyle or hide them,
-- only fade the wrapper frames it owns (allowed in combat). Building is only
-- allowed out of combat, so a build asked for in combat waits for it to end.
-- The technique comes from the Unsealed Wrath Tracker addon.
local _, ns = ...
local Data = ns.Data

local Native = { ready = false, broken = false, status = "not built" }
ns.Native = Native

local MAX = 3

function Native.available()
  return CreateFrame ~= nil and CustomAuraContainerAuraProcessingPolicy ~= nil and C_AuraContainerUtil ~= nil
end

local function inCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

-- The game hands Sigil the button for one Echo buff; this turns it into one arc.
-- Runs whenever the game first draws that buff, which can be mid-fight.
local function initializeArc(button, halo, seal, i)
  button:EnableMouse(false)
  button:ClearAllPoints()
  button:SetAllPoints(halo)
  local bar = CreateFrame("StatusBar", nil, button)
  bar:SetAllPoints(halo)
  bar:SetStatusBarTexture(Data.MEDIA .. "stack" .. i)
  local c = Data.color[seal] or Data.color.gold
  bar:SetStatusBarColor(c[1], c[2], c[3], 1)
  local ok = pcall(button.SetApplicationBar, button, bar, { minApplications = i - 1, maxApplications = i })
  if not ok then
    -- Without a lower bound the arc would fill part way and show a wrong
    -- count. Give up on game-drawn stacks; the halo goes back to the others.
    bar:Hide()
    Native.broken = true
    Native.status = "the game refused the arc range; using the other stack displays"
    if ns.Game and ns.Game.log then ns.Game.log("error: game-drawn stacks refused the arc range") end
  end
end

local function newArc(wrap, halo, seal, id, i)
  local c = CreateFrame("AuraContainer", nil, wrap, "CustomAuraContainerTemplate")
  c:SetEnabled(false)
  c:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
  c:SetAllPoints(halo)
  c:SetUnit("player")
  c:AddAuraSlot("Echo", "HELPFUL", {
    candidateFilters = { includeSpellIDs = { [id] = true } },
    initializeFrame = function(button) initializeArc(button, halo, seal, i) end,
  })
  c:SetAuraSlotEnabled("Echo", true)
  c:SetEnabled(true)
  return c
end

-- Builds the arcs over the halo once. Returns true when they are up.
function Native.build()
  local f = ns.Halo and ns.Halo.frame
  if Native.ready or not f then return Native.ready end
  if not Native.available() then
    Native.status = "not offered by this client"
    return false
  end
  if inCombat() then
    Native.pending = true
    Native.status = "waiting for combat to end"
    return false
  end
  Native.pending = false
  local ok, err = pcall(function()
    -- one wrapper frame Sigil owns, between the arcs and the labels
    local wrap = CreateFrame("Frame", nil, f.art)
    wrap:SetAllPoints(f)
    wrap:SetFrameLevel(f.art:GetFrameLevel() + 1)
    wrap:SetAlpha(0)
    Native.wrap = wrap
    Native.containers = {}
    for seal, id in pairs(Data.echo) do
      for i = 1, MAX do
        Native.containers[#Native.containers + 1] = newArc(wrap, f, seal, id, i)
      end
    end
  end)
  Native.ready = ok
  Native.status = ok and ("active, " .. #Native.containers .. " arcs") or ("failed: " .. tostring(err))
  if not ok and ns.Game and ns.Game.log then ns.Game.log("error: game-drawn stacks failed: %s", tostring(err)) end
  return ok
end

-- Shows or hides the game-drawn arcs. Returns true when they are showing,
-- so the halo can draw its own arcs as the empty track underneath.
function Native.show(on)
  local active = on and Native.ready and not Native.broken and ns.db.realStacks ~= false
  if Native.wrap then pcall(Native.wrap.SetAlpha, Native.wrap, active and 1 or 0) end
  return active and true or false
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function()
  if Native.pending then Native.build() end
end)
