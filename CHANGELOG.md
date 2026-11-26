# Changelog

## 0.2.0

- A miss on your target up to 2 seconds after you cast Consecration no longer takes a stack back. Consecration's own hits can miss, and live one landed in a swing's window and undid a swing that had landed

## 0.2.0-beta4

- In a group, a miss on your target no longer takes a stack back. In party play those misses were other players', so Sigil was counting one stack too few and calling the swap a swing late
- Hammer of Justice is now always manual, with its mark like Consecration. In the Attack macro it kept Holy Strike from going off while the stun was on cooldown, and lower down it never went off itself. The "Hammer of Justice" automatic option is gone
- Hammer of Wrath is out of the Attack macro too, for the same reason: it only works on a low target and would stop Holy Strike the rest of the fight. It gets its own key and a mark when the game says it can be cast. Sigil trusts that only once it has seen the game refuse it on a healthy target, and ignores the game's answer during the global cooldown, when every spell reads as unusable

Known limits:

- In a group, your own rare miss can leave the count one stack high, so the swap comes a swing early; the arcs always show the real number
- The Hammer of Wrath mark is not tested live yet
- English game client only for now

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
