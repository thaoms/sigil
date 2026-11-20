-- A small button on the minimap: left-click for options, right-click for
-- setup, drag to move it around the minimap's edge.
local _, ns = ...
local Data = ns.Data

local Button = {}
ns.MinimapButton = Button

local function place(b)
  local angle = math.rad(ns.db.minimapAngle or 215)
  local radius = ((Minimap:GetWidth() or 140) / 2) + 6
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function Button.create()
  if Button.frame or not Minimap then return end
  local b = CreateFrame("Button", "SigilMinimapButton", Minimap)
  Button.frame = b
  b:SetSize(30, 30)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(Data.MEDIA .. "orb")
  bg:SetAllPoints()
  local edge = b:CreateTexture(nil, "BORDER")
  edge:SetTexture(Data.MEDIA .. "orb_edge")
  edge:SetAllPoints()
  edge:SetVertexColor(0.91, 0.73, 0.34, 1)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(Data.MEDIA .. "glyph_command")
  icon:SetPoint("CENTER")
  icon:SetSize(20, 20)
  icon:SetVertexColor(0.91, 0.73, 0.34, 1)
  local glow = b:CreateTexture(nil, "HIGHLIGHT")
  glow:SetTexture(Data.MEDIA .. "orb_edge")
  glow:SetAllPoints()
  glow:SetVertexColor(1, 1, 1, 0.9)
  glow:SetBlendMode("ADD")

  b:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then ns.Setup.show() else ns.Options.toggle() end
  end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Sigil")
    GameTooltip:AddLine("Left-click: options", 1, 1, 1)
    GameTooltip:AddLine("Right-click: setup", 1, 1, 1)
    GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale() or 1
      if not (mx and my and cx and cy) then return end
      ns.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
      place(self)
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  place(b)
  Button.apply()
end

function Button.apply()
  local b = Button.frame
  if not b then return end
  if ns.db.minimap == false then b:Hide() else b:Show() end
end

-- Also listed in the game's own addon menu next to the minimap.
function Sigil_OnAddonCompartmentClick()
  if ns.ready then ns.Options.toggle() end
end
