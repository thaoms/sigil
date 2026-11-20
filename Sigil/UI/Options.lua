-- Options window. Plain checkboxes and click-to-cycle buttons, no dropdowns.
local _, ns = ...

local Options = {}
ns.Options = Options

local CHOICES = {
  consecration = { { "aoe", "3 or more enemies" }, { "always", "Always" }, { "never", "Never" } },
  recover = { { "seal", "Seal of Wisdom" }, { "blessing", "Blessing of Wisdom reminder" }, { "both", "Both" } },
  attackKeys = { { 1, "One key (Attack macro)" }, { 2, "Two keys (Judgement, Holy Strike)" } },
}

local ROWS = {
  { "check", "locked", "Lock position", "Unlock to drag the halo." },
  { "check", "showWhy", "Show the reason line", "A short line under the halo saying why." },
  { "check", "onlyCombat", "Only when fighting", "Hide the halo when you have no target." },
  { "check", "weave", "Swap seals for Unsealed Wrath", "Turn off to stay on one seal." },
  { "cycle", "attackKeys", "Attack keys", "Use two if the macro misfires." },
  { "cycle", "consecration", "Consecration", "When Sigil marks it." },
  { "cycle", "recover", "When mana runs low", "How Sigil helps you recover." },
  { "check", "upkeep", "Aura and blessing reminders", "Shown only when one is missing." },
  { "check", "hojCue", "Hammer of Justice mark", "Shown just before Judgement is ready." },
  { "check", "hojInMacro", "Stun from the Attack key", "Adds Hammer of Justice to the macro: used whenever ready." },
  { "check", "sound", "Swap sound", "A soft click when it's time to swap seals." },
  { "check", "hideErrors", "Hide red error text", "Hides ALL red error messages, e.g. \"not ready yet\"." },
}

local function labelFor(key, value)
  for _, c in ipairs(CHOICES[key]) do
    if c[1] == value then return c[2] end
  end
  return tostring(value)
end

function Options.apply(key)
  local db = ns.db
  if key == "locked" or key == "scale" then ns.Halo.applyLayout() end
  if key == "hideErrors" and UIErrorsFrame then
    if db.hideErrors then pcall(UIErrorsFrame.UnregisterEvent, UIErrorsFrame, "UI_ERROR_MESSAGE")
    else pcall(UIErrorsFrame.RegisterEvent, UIErrorsFrame, "UI_ERROR_MESSAGE") end
  end
  if key == "attackKeys" or key == "hojInMacro" then
    if db.attackKeys ~= 2 then ns.Game.macroState = ns.Game.ensureMacro() end
    ns.Game.scanKeys()
  end
  if ns.refreshSetup then ns.refreshSetup() end
end

function Options.create()
  local f = ns.panel("SigilOptions", 400, 64 + #ROWS * 34 + 44)
  Options.frame = f
  f.title:SetText("Sigil options")
  f.controls = {}

  for i, row in ipairs(ROWS) do
    local kind, key, title, help = row[1], row[2], row[3], row[4]
    local y = -44 - (i - 1) * 34
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", 16, y)
    name:SetText(title)
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    sub:SetText(help)
    sub:SetJustifyH("LEFT")
    sub:SetWidth(kind == "check" and 320 or 170)
    if sub.SetWordWrap then sub:SetWordWrap(false) end
    if kind == "check" then
      local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
      cb:SetSize(24, 24)
      cb:SetPoint("TOPRIGHT", -16, y + 2)
      cb:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        Options.apply(key)
      end)
      f.controls[key] = cb
    else
      local b = ns.button(f, "", 190, function(self)
        local list = CHOICES[key]
        local at = 1
        for n, c in ipairs(list) do if c[1] == ns.db[key] then at = n end end
        ns.db[key] = list[at % #list + 1][1]
        self:SetText(labelFor(key, ns.db[key]))
        Options.apply(key)
      end)
      b:SetPoint("TOPRIGHT", -16, y)
      f.controls[key] = b
    end
  end

  local bottom = -44 - #ROWS * 34 - 4
  local size = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  size:SetPoint("TOPLEFT", 16, bottom)
  f.sizeText = size
  local function resize(by)
    ns.db.scale = math.max(0.6, math.min(1.6, (ns.db.scale or 1) + by))
    Options.apply("scale")
    Options.refresh()
  end
  local plus = ns.button(f, "+", 28, function() resize(0.1) end)
  plus:SetPoint("TOPRIGHT", -16, bottom + 4)
  local minus = ns.button(f, "-", 28, function() resize(-0.1) end)
  minus:SetPoint("RIGHT", plus, "LEFT", -4, 0)

  local setup = ns.button(f, "Setup", 80, function() ns.Setup.show() end)
  setup:SetPoint("BOTTOMLEFT", 16, 12)
  local close = ns.button(f, "Close", 80, function() f:Hide() end)
  close:SetPoint("BOTTOMRIGHT", -16, 12)
end

function Options.refresh()
  local f = Options.frame
  if not f then return end
  for _, row in ipairs(ROWS) do
    local kind, key = row[1], row[2]
    local control = f.controls[key]
    if kind == "check" then control:SetChecked(ns.db[key] and true or false)
    else control:SetText(labelFor(key, ns.db[key])) end
  end
  f.sizeText:SetText(("Size: %d%%"):format((ns.db.scale or 1) * 100 + 0.5))
end

function Options.toggle()
  if not Options.frame then Options.create() end
  if Options.frame:IsShown() then Options.frame:Hide() return end
  if ns.Setup.frame then ns.Setup.frame:Hide() end        -- one window at a time
  Options.refresh()
  Options.frame:Show()
end

-- A small entry in the game's own AddOns settings list that opens the window.
function Options.register()
  pcall(function()
    local canvas = CreateFrame("Frame")
    local text = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 16, -16)
    text:SetText("Sigil has its own options window.")
    local open = ns.button(canvas, "Open Sigil options", 180, function() Options.toggle() end)
    open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -10)
    local category = Settings.RegisterCanvasLayoutCategory(canvas, "Sigil")
    Settings.RegisterAddOnCategory(category)
  end)
end
