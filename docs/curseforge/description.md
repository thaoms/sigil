Sigil tells a Retribution Paladin which seal to press and when. It never presses anything for you.

This is a beta. I built it for my own paladin and it works well for me solo, but dungeons and raids are untested.

## What you get

- One halo under your character with the seal to press, the key it is on, your Unsealed Wrath stacks, your swing timer and a mana bar
- It stays quiet most of the time. It only pulses and plays a sound when you need to swap seals
- An Attack macro that Sigil makes for you. Judgement, Holy Strike, Exorcism and Hammer of Wrath on one key, so you spam that and only think about seals
- Seal weaving for Unsealed Wrath. Command and Righteousness by default, but you can pick the pair. 3 and 3 or 3 and 1
- Optional Seal of the Crusader opener, for every target or only elites and bosses
- A mark that tells you when to press Hammer of Justice, just before Judgement
- When mana gets low it stops asking for the expensive stuff and calls Seal of Wisdom
- Reminders when your aura or blessing is missing

## Setup

A setup window opens on your first login. It shows which buttons Sigil uses and what key each one is on, and it can put the missing ones in empty bar slots. It never replaces a button you already have.

`/sigil` opens the options, or use the minimap button.

## Good to know

- WoW Forever hides buffs, mana and damage from addons in combat. The stack arcs on the halo are drawn by the game itself, so they always show your real stacks
- Sigil can't read that number, so it decides when to swap from its own count of your swings. It checks itself against the real buff after every fight. Solo this has been right every time for me. In a group it can be a swing off now and then, because it can't tell your misses from other players'; the arcs show the truth
- If you enable the Cooldown Manager and track Unsealed Wrath and Seals there, Sigil uses that to correct its count during a fight
- English client only for now
- Retribution only

## Commands

- `/sigil` options
- `/sigil setup` the setup window
- `/sigil demo` shows every state of the halo out of combat
- `/sigil compare` average kill time per mob for each seal pattern

Found a bug? Turn on Debug log in the options, fight a bit, `/reload`, and send me what happened.
