# Sigil

A next-ability helper for Retribution Paladins in World of Warcraft: Forever.

Sigil shows which seal to press and when, your Unsealed Wrath stacks, your swing timer and a rough mana level, all in one halo. It never presses anything for you.

## Status

Version 0.1.0. Tested against a simulated game client only. Not yet verified in the live game.

## Install

```sh
tools/install.sh
```

This copies `Sigil/` into `_forever_/Interface/AddOns`. Restart the game the first time. After later updates, `/reload` is enough.

## In game

- A setup window opens on first login. It lists Sigil's buttons, shows which key each is on, and can place the missing ones into empty bar slots.
- `/sigil` opens options. `/sigil setup` reopens setup.
- `/sigil demo` plays every halo state outside combat.
- `/sigil check` saves a report of which game readings work. `/reload` writes it to disk.

## How it works

The game hides buffs, mana and cooldown times from addons during combat. Sigil counts the seal and stacks from your own casts and swings, estimates mana from which spells you can afford, and compares its count with the real buffs after every fight.

- `Sigil/Core/` is pure Lua with no game calls: the decision engine, the tracker and the mana estimate.
- `Sigil/Game.lua` is the only file that reads from the game.
- `Sigil/UI/` draws the halo, setup and options.

## Develop

```sh
luajit tests/run.lua    # engine tests
luajit tests/mock.lua   # whole addon against a fake client; add -v for the report
python3 tools/gen_textures.py   # rebuild artwork (needs rsvg-convert)
```

Design: `docs/design.html`.
