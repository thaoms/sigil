-- Start-up, the update loop and the /sigil commands.
local ADDON, ns = ...
local Data, Engine = ns.Data, ns.Engine

function ns.say(text)
  print("|cffe7ba57Sigil:|r " .. text)
end

local DEMO_KEYS = { attack = "1", command = "2", righteousness = "3", consecration = "4", hoj = "5", wisdom = "6" }
local DEMO = {
  { 2.0, { main = { id = "command", why = "No seal active.", urgent = true }, stacks = 0, mana = 3 } },
  { 1.6, { main = { id = "attack", why = "Building stacks: 1 of 3." }, stacks = 1, stored = "command", mana = 3 } },
  { 1.6, { main = { id = "attack", why = "Building stacks: 2 of 3." }, stacks = 2, stored = "command", mana = 3, next = "righteousness" } },
  { 2.4, { main = { id = "righteousness", why = "3 stacks stored. Swap before your next swing.", urgent = true }, stacks = 3, stored = "command", mana = 3, next = "command" } },
  { 1.6, { main = { id = "attack", why = "Your next swing releases the stacks." }, stacks = 3, stored = "command", mana = 3, next = "command" }, "release" },
  { 2.0, { main = { id = "command", why = "Stacks released. Swap back and rebuild.", urgent = true }, stacks = 1, stored = "righteousness", mana = 3 } },
  { 2.0, { main = { id = "attack", why = "Building stacks: 1 of 3." }, stacks = 1, stored = "command", mana = 3, side = { "consecration", "hoj" } } },
  { 2.0, { main = { id = "attack", why = "Mana is getting low. Staying on your main seal." }, stacks = 3, stored = "command", mana = 2 } },
  { 2.4, { main = { id = "wisdom", why = "Nearly out of mana. Seal of Wisdom gives mana back as you hit.", urgent = true }, stacks = 2, stored = "command", mana = 1 } },
  { 2.0, { main = { id = "attack", why = "Recovering mana." }, stacks = 1, stored = "wisdom", mana = 1, marks = { blessing = true } } },
}

function ns.toggleDemo()
  if ns.demo then
    ns.demo = nil
    ns.say("Demo stopped.")
  else
    ns.demo = { step = 0, untilTime = 0, keys = DEMO_KEYS }
    ns.say("Demo playing. Type /sigil demo again to stop.")
  end
  if ns.refreshSetup then ns.refreshSetup() end
end

local function demoTick(now)
  local demo = ns.demo
  if now >= demo.untilTime then
    demo.step = demo.step % #DEMO + 1
    local step = DEMO[demo.step]
    demo.untilTime = now + step[1]
    ns.Halo.swing(now, step[1])
    if step[3] == "release" then
      demo.releaseAt = now + step[1] - 0.2
    end
  end
  if demo.releaseAt and now >= demo.releaseAt then
    demo.releaseAt = nil
    ns.Halo.release({ seal = "command", count = 3 })
  end
  local d = DEMO[demo.step][2]
  d.side, d.marks = d.side or {}, d.marks or {}
  ns.Halo.render(d, demo)
end

local elapsed = 0
local function onUpdate(_, dt)
  elapsed = elapsed + dt
  local now = GetTime()
  ns.Halo.animate(now)
  if elapsed < 0.05 then return end
  elapsed = 0
  if ns.demo then demoTick(now) return end
  local ok, result = pcall(function()
    return Engine.decide(ns.Game.view(), ns.db)
  end)
  if ok then
    ns.Halo.render(result)
  elseif result ~= ns.lastError then
    ns.lastError = result
    ns.Game.log("tick error: %s", tostring(result))
  end
end

local function check()
  local lines = ns.Game.report()
  SigilDB.report = { at = date and date("%Y-%m-%d %H:%M:%S") or "?", lines = lines }
  SigilDB.stackButton = ns.Game.describeStackButton()
  for _, line in ipairs(lines) do print("|cff8d95a4" .. line .. "|r") end
  ns.say("Report saved. Type /reload so it is written to disk.")
end

local function command(msg)
  local word, rest = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  local db = ns.db
  if not ns.ready then
    ns.say("Sigil only runs on a Paladin.")
  elseif word == "" or word == "options" or word == "config" then
    ns.Options.toggle()
  elseif word == "setup" then
    ns.Setup.show()
  elseif word == "lock" or word == "unlock" then
    db.locked = word == "lock"
    ns.Halo.applyLayout()
    ns.say(db.locked and "Halo locked." or "Halo unlocked. Drag it where you want it.")
  elseif word == "demo" then
    ns.toggleDemo()
  elseif word == "check" then
    check()
  elseif word == "compare" then
    local both, single = ns.Game.compareLines()
    if #both + #single == 0 then
      ns.say("No fights measured yet. It counts solo fights against one enemy, 5 seconds or longer.")
    else
      ns.say("Average time to kill, per seal pattern (shorter is better):")
      for _, line in ipairs(both) do print("  " .. line) end
      if #single > 0 then
        print("  Fought with one pattern only so far:")
        for _, line in ipairs(single) do print("    " .. line) end
      end
    end
  elseif word == "macro" then
    ns.say("Attack macro text:")
    for line in ns.Game.macroBody():gmatch("[^\n]+") do print("  " .. line) end
  elseif word == "reset" then
    db.pos, db.scale, db.locked = nil, 1, false
    ns.Halo.applyLayout()
    ns.say("Halo moved back to the middle of the screen.")
  elseif word == "scale" and tonumber(rest) then
    db.scale = math.max(0.6, math.min(1.6, tonumber(rest)))
    ns.Halo.applyLayout()
  else
    ns.say("Commands: /sigil (options), setup, lock, unlock, demo, compare, check, macro, reset, scale 0.6-1.6")
  end
end

SLASH_SIGIL1 = "/sigil"
SlashCmdList.SIGIL = function(msg)
  -- a command must never fail silently
  local ok, err = pcall(command, msg)
  if not ok then
    ns.say("That command hit an error: " .. tostring(err))
    if ns.Game and ns.Game.log then ns.Game.log("command error (%s): %s", tostring(msg), tostring(err)) end
  end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name ~= ADDON then return end
    SigilDB = SigilDB or {}
    SigilCharDB = SigilCharDB or {}
    for key, value in pairs(Data.defaults) do
      if SigilCharDB[key] == nil then SigilCharDB[key] = value end
    end
    -- keep earlier entries: a reload without fighting must not wipe the log
    SigilCharDB.log = SigilCharDB.log or {}
    if SigilCharDB.debug then
      SigilCharDB.log[#SigilCharDB.log + 1] = "--- session " .. (date and date("%H:%M:%S") or "?")
    end
    while #SigilCharDB.log > 400 do table.remove(SigilCharDB.log, 1) end
    -- settings renamed since 0.2.0
    if SigilCharDB.hojInMacro then SigilCharDB.stun = "always" end
    SigilCharDB.hojInMacro, SigilCharDB.sound = nil, nil
    ns.db = SigilCharDB
    return
  end

  local _, class = UnitClass("player")
  if class ~= "PALADIN" then return end
  ns.db = ns.db or SigilCharDB or {}
  local ok, err = pcall(function()
    ns.Game.start()
    ns.Halo.create()
    ns.onSwing = ns.Halo.swing
    ns.onRelease = ns.Halo.release
    ns.Options.register()
    pcall(ns.MinimapButton.create)
    if ns.db.hideErrors then ns.Options.apply("hideErrors") end
    -- the macro list may not be loaded this early: wait before creating one
    C_Timer.After(4, function()
      ns.Game.macrosLoaded = true
      if ns.db.attackKeys ~= 2 then ns.Game.macroState = ns.Game.ensureMacro() end
      ns.Game.scanKeys()
      if ns.refreshSetup then ns.refreshSetup() end
    end)
    boot:SetScript("OnUpdate", onUpdate)
    ns.ready = true
  end)
  if not ok then
    SigilDB.startError = tostring(err)
    ns.say("Couldn't start: " .. tostring(err))
    return
  end
  SigilDB.startError = nil
  if not ns.db.setupDone then
    C_Timer.After(5, function()
      ns.say("Welcome. Type /sigil setup any time to see this window again.")
      ns.Setup.show()
    end)
  end
end)
