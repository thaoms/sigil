-- Works out a rough mana level from which spells the player can afford.
-- The game hides the exact number, but it does say "not enough mana" per
-- spell, so spells of different cost bracket the real value.
local _, ns = ...

local Mana = {}
ns.Mana = Mana

Mana.COMFORTABLE, Mana.LOW, Mana.EMPTY = 3, 2, 1

-- probes: list of { cost = number, affordable = boolean }
-- costs:  { weave = cost of both seals, attack = cost of one attack }
-- previous: last level, for hysteresis so the level doesn't flicker.
function Mana.level(probes, costs, previous)
  local floor, ceiling, top = 0, nil, 0
  for _, p in ipairs(probes) do
    if p.cost and p.cost > 0 then
      if p.cost > top then top = p.cost end
      if p.affordable then
        if p.cost > floor then floor = p.cost end
      elseif not ceiling or p.cost < ceiling then
        ceiling = p.cost
      end
    end
  end
  if not ceiling then return Mana.COMFORTABLE, floor, nil end

  local weave = costs.weave or 0
  local emptyBelow = weave + (costs.attack or 0)
  local lowBelow = math.min(top, 2 * weave + (costs.attack or 0))
  if emptyBelow >= lowBelow then emptyBelow = lowBelow * 0.5 end

  local level
  if ceiling <= emptyBelow then
    level = Mana.EMPTY
  elseif previous == Mana.EMPTY and floor < lowBelow then
    level = Mana.EMPTY          -- stay in recovery until clearly out of it
  else
    level = Mana.LOW
  end
  return level, floor, ceiling
end
