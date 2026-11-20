-- Tracks what the game hides in combat: the active seal, Unsealed Wrath
-- stacks, cooldowns and the swing timer, counted from the player's own casts
-- and swings. Pure Lua: no game calls, so it runs under a test harness.
local _, ns = ...

local Tracker = {}
Tracker.__index = Tracker
ns.Tracker = Tracker

Tracker.SEAL_DURATION = 30
Tracker.STACK_DURATION = 15
Tracker.MAX_STACKS = 3
Tracker.GCD = 1.5

-- Seals that leave a copy behind for Unsealed Wrath.
local STORES = { command = true, righteousness = true, wisdom = true, light = true, justice = true, fury = true }

function Tracker.new()
  local t = setmetatable({}, Tracker)
  t.cooldowns = {}
  t.readyAt = {}
  t.stacks = 0
  t.gcdEnd = 0
  t.unsealedWrath = true
  return t
end

function Tracker:setCooldown(key, seconds)
  self.cooldowns[key] = seconds
end

function Tracker:expire(now)
  if self.seal and self.sealExpires and now >= self.sealExpires then
    self.seal, self.sealExpires = nil, nil
  end
  if self.stacks > 0 and self.stacksExpire and now >= self.stacksExpire then
    self.stacks, self.stored, self.stacksExpire = 0, nil, nil
  end
end

function Tracker:castSeal(seal, now)
  self:expire(now)
  self.seal = seal
  self.sealExpires = now + Tracker.SEAL_DURATION
  self.gcdEnd = now + Tracker.GCD
end

function Tracker:castSpell(key, now, offGcd)
  local cd = self.cooldowns[key]
  if cd then self.readyAt[key] = now + cd end
  if not offGcd then self.gcdEnd = now + Tracker.GCD end
end

function Tracker:remains(key, now)
  local at = self.readyAt[key]
  if not at or at <= now then return 0 end
  return at - now
end

-- The game reported the spell as ready (or not): trust it over our timer.
function Tracker:correctCooldown(key, isReady, now)
  if isReady then
    self.readyAt[key] = nil
  elseif self:remains(key, now) == 0 and self.cooldowns[key] then
    self.readyAt[key] = now + 1
  end
end

local function applyHit(self, now)
  local seal = self.seal
  if not seal or not self.unsealedWrath then return end
  local released
  if self.stacks > 0 and self.stored ~= seal then
    released = { seal = self.stored, count = self.stacks }
    self.stacks, self.stored = 0, nil
  end
  if STORES[seal] then
    if self.stored == seal then
      self.stacks = math.min(Tracker.MAX_STACKS, self.stacks + 1)
    else
      self.stored, self.stacks = seal, 1
    end
    self.stacksExpire = now + Tracker.STACK_DURATION
  end
  return released
end

-- A main-hand swing happened. It is counted as a hit straight away; if the
-- game later reports it missed, swingMissed() undoes it.
function Tracker:swing(now, speed)
  self:expire(now)
  self.lastSwing = now
  if speed and speed > 0 then self.swingSpeed = speed end
  self.undo = { stacks = self.stacks, stored = self.stored, stacksExpire = self.stacksExpire, at = now }
  self.lastRelease = applyHit(self, now)
  if self.lastRelease then self.lastRelease.at = now end
  return self.lastRelease
end

function Tracker:swingMissed(now)
  local u = self.undo
  if not u or now - u.at > 2 then return false end
  self.stacks, self.stored, self.stacksExpire = u.stacks, u.stored, u.stacksExpire
  self.undo, self.lastRelease = nil, nil
  return true
end

function Tracker:swingRemains(now)
  if not self.lastSwing or not self.swingSpeed then return nil end
  local left = self.lastSwing + self.swingSpeed - now
  if left < -1 then return nil end
  return math.max(0, left)
end

-- Out of combat the game's own buff list is readable: adopt it.
function Tracker:sync(real, now)
  if real.seal ~= nil then
    self.seal = real.seal or nil
    self.sealExpires = real.seal and (real.sealExpires or now + Tracker.SEAL_DURATION) or nil
  end
  if real.stacks ~= nil then
    self.stacks = real.stacks
    self.stored = real.stacks > 0 and real.stored or nil
    self.stacksExpire = real.stacks > 0 and (real.stacksExpire or now + Tracker.STACK_DURATION) or nil
  end
end

function Tracker:snapshot(now)
  self:expire(now)
  return {
    seal = self.seal,
    sealRemains = self.seal and math.max(0, self.sealExpires - now) or 0,
    stored = self.stored,
    stacks = self.stacks,
    swingRemains = self:swingRemains(now),
    swingSpeed = self.swingSpeed,
    gcdRemains = math.max(0, self.gcdEnd - now),
  }
end
