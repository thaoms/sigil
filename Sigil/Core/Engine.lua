-- Decides what the halo shows. Pure Lua: a view of the fight goes in, one
-- call comes out. With the Attack macro, all attacks share a key, so the
-- only calls that need a decision are the seals.
local _, ns = ...

local Engine = {}
ns.Engine = Engine

local COMFORTABLE, EMPTY = 3, 1
local REFRESH_BEFORE = 2      -- re-cast a seal this many seconds before it runs out
local STUN_WINDOW = 3         -- cue Hammer of Justice when Judgement is this close

local function call(id, why, urgent)
  return { id = id, why = why, urgent = urgent or false }
end

-- view fields (all optional unless noted):
--   combat, target        booleans
--   seal, sealRemains     active seal key and seconds left
--   stored, stacks        Unsealed Wrath copies
--   manaLevel             3 comfortable, 2 low, 1 nearly empty
--   known[key]            spells the character has
--   afford[key]           false when the game says "not enough mana"
--   ready[key]            cooldown is up
--   judgementRemains      seconds until Judgement is ready
--   enemies               enemies in melee, nil when unknown
--   auraMissing, blessingMissing
function Engine.decide(view, settings)
  local known = view.known or {}
  local afford = view.afford or {}
  local ready = view.ready or {}
  local level = view.manaLevel or COMFORTABLE
  local seal, stored, stacks = view.seal, view.stored, view.stacks or 0

  local primary = known.command and "command" or (known.righteousness and "righteousness" or nil)
  local secondary = (primary == "command" and known.righteousness) and "righteousness" or nil
  local weave = secondary and view.unsealedWrath ~= false and settings.weave ~= false
  local useWisdom = known.wisdom and settings.recover ~= "blessing"

  local out = { mana = level, stacks = stacks, stored = stored, seal = seal, side = {}, marks = {} }
  local active = view.combat or view.target

  local function seals()
    if not primary then return nil end
    local expiring = seal and (view.sealRemains or 99) < REFRESH_BEFORE

    if level == EMPTY and useWisdom then
      if seal ~= "wisdom" or expiring then
        return call("wisdom", "Nearly out of mana. Seal of Wisdom gives mana back as you hit.", true)
      end
      return nil
    end
    if not seal then
      return call(primary, "No seal active.", true)
    end
    if seal == "wisdom" then
      if level == COMFORTABLE or not useWisdom then
        return call(primary, "Mana is back. Return to your seal.", false)
      end
      if expiring then return call("wisdom", "Seal of Wisdom is about to run out.", false) end
      return nil
    end
    if seal ~= primary and seal ~= secondary then
      return nil              -- a seal the player chose on purpose: leave it alone
    end
    if not weave then
      if expiring then return call(seal, "Your seal is about to run out.", false) end
      return nil
    end
    if seal == primary then
      if level == COMFORTABLE and stored == primary and stacks >= 3 then
        return call(secondary, "3 stacks stored. Swap before your next swing.", true)
      end
      if expiring then return call(primary, "Your seal is about to run out.", false) end
      return nil
    end
    -- the secondary seal is active
    if stored == primary and stacks > 0 then
      return nil              -- waiting for the swing that releases the stacks
    end
    if level ~= COMFORTABLE then
      return call(primary, "Mana is getting low. Stay on your main seal.", false)
    end
    return call(primary, "Stacks released. Swap back and rebuild.", true)
  end

  local main = active and seals() or nil
  if main and afford[main.id] == false then
    main = nil
    out.broke = true
  end

  if main then
    out.main = main
  elseif not active then
    out.main = call("idle", "")
  else
    local why = "Keep attacking."
    if out.broke then
      why = "Not enough mana for a seal. Keep attacking."
    elseif weave and seal == secondary and stored == primary and stacks > 0 then
      why = "Your next swing releases the stacks."
    elseif weave and seal == primary and level == COMFORTABLE then
      why = ("Building stacks: %d of 3."):format(stored == primary and stacks or 0)
    elseif level == EMPTY and seal == "wisdom" then
      why = "Recovering mana."
    end
    out.main = call("attack", why)
  end

  -- what comes after the current call, for the small preview orb
  if weave and level == COMFORTABLE and active then
    if out.main.id == "attack" and seal == primary and stored == primary and stacks == 2 then
      out.next = secondary
    elseif out.main.id == secondary or (out.main.id == "attack" and seal == secondary) then
      out.next = primary
    end
  end

  if view.combat then
    local cons = settings.consecration or "aoe"
    if known.consecration and ready.consecration and level == COMFORTABLE and afford.consecration ~= false
      and (cons == "always" or (cons == "aoe" and (view.enemies or 0) >= 3)) then
      out.side[#out.side + 1] = "consecration"
    end
    if settings.hojCue ~= false and known.hoj and ready.hoj and seal == "command"
      and (view.judgementRemains or 99) <= STUN_WINDOW and afford.hoj ~= false then
      out.side[#out.side + 1] = "hoj"
    end
  end

  if settings.upkeep ~= false then
    if view.auraMissing then out.marks.aura = true end
    if view.blessingMissing then out.marks.blessing = true end
  end
  if not view.combat and level < COMFORTABLE then
    out.marks.drink = true
    if level == EMPTY and settings.recover ~= "seal" then out.marks.blessingOfWisdom = true end
  elseif level == EMPTY and settings.recover ~= "seal" and settings.recover ~= nil then
    out.marks.blessingOfWisdom = true
  end

  return out
end
