# Changelog

## Unreleased

- In a group, a miss on your target no longer takes a stack back. In party play those misses were other players', so Sigil was counting one stack too few and calling the swap a swing late

## 0.2.0-beta3

- The stack arcs are now drawn by the game from your real Unsealed Wrath stacks, in the seal's colour, so they stay right in combat, solo or in a group. No Cooldown Manager setup needed for this
- The Consecration mark only counts enemies near you (Judgement range), and stays on at low mana for pulls of 3 or more
- Your seal and stacks are cleared when you die
- Simpler stack counting with one miss rule everywhere, corrected mid-fight by the Cooldown Manager (if Unsealed Wrath is tracked there) and by Seal of Command extra hits

Known limits:

- The swap call still runs on Sigil's own count, which can be a swing off in a group; the arcs always show the real number
- English game client only for now
- Tested solo; groups, dungeons and raids are not tested yet

## 0.2.0-beta2

First public beta. For Retribution Paladins on WoW Forever 1.60.1.

- One halo showing the seal to press and its key, Unsealed Wrath stacks, the swing timer and a mana bar
- Seal weave for Unsealed Wrath, with a choice of seal pair and two patterns (3 and 3, or 3 and 1)
- Attack macro created and kept up to date for you: Judgement, Hammer of Wrath, Holy Strike, Exorcism on one key
- Optional Seal of the Crusader opener, on every target or only on elites and bosses
- Hammer of Justice manual, automatic when solo, or always automatic
- Low mana handling: drops Consecration and the swap, calls Seal of Wisdom, reminds you to drink
- Reminders for a missing or wrong aura and a missing blessing
- Setup window that finds your keys and can place missing buttons into empty slots
- Minimap button, options window, `/sigil` commands

Known limits:

- English game client only for now
- Tested solo; groups, dungeons and raids are not tested yet
- The game hides buffs, mana and damage from addons in combat, so stacks are counted from your swings and can drift in a group
