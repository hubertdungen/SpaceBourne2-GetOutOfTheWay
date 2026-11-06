![Get Out of the Way](docs/banner.png)

# Get Out of the Way — NPCs step aside naturally in SpaceBourne 2

In SpaceBourne 2's stations, markets and corridors, people stand in your way: you stop, or you
shove them aside with your body. With Get Out of the Way, calm NPCs notice you walking at them,
turn, take a short step out of your path, and step back to their spot once you have passed.

**Links:** [GitHub](https://github.com/hubertdungen/SpaceBourne2-GetOutOfTheWay) ·
[Nexus Mods](https://www.nexusmods.com/spacebourne2/mods/14) · UE4SS Lua mod · works alone or with
the rest of the realism set.
**Install the whole realism set in one go:** the
[SpaceBourne 2 Realism installer](https://github.com/hubertdungen/SpaceBourne2-Realism)
([Nexus](https://www.nexusmods.com/spacebourne2/mods/11)).

## Features

### Who steps aside

- **Calm people:** civilians, guards at rest, allied crew and companions, your ground squad, and the
  traders, quest givers and crew you talk to.
- **Never:** enemies, creatures, bosses, anyone in a fight or alerted, anyone talking to you,
  sitting, playing a scripted animation or already walking somewhere.

### How they move

- **Natural steps.** The NPC walks its step with its own walk animation and turns the way it goes.
  It steps to the side it is already on, a little away from you, 0.5 to 0.8 m: just enough to clear
  your path.
- **Never into a wall.** It never steps into a wall or into another NPC: if one side is blocked it
  takes the other, and if both are blocked it stays.
- **Back to its spot.** Once you have passed, it walks back and ends where it stood, facing the same
  way.

### When they react

- **Human timing.** It reacts within 0.2–0.4 s when you are about 2 m away (further when you run),
  and also when you are already pressed against it and keep pushing. Someone with their back to you
  notices later, and doesn't notice at all if you sneak up crouched.
- **Calm, not twitchy.** At most 4 NPCs move at once, and the same NPC waits 3 s before it steps
  again.
- **Out of the way of the fights.** Nothing happens while you are in a ship or on the hoverbike, or
  while Silent Ops reports an alert of Yellow or higher near you.

### On by default

- No key needed: it works as soon as it is installed.

## Requirements

- SpaceBourne 2 (Steam).
- [UE4SS 3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1) (the realism installer
  installs it for you).

## Install

**A. SpaceBourne 2 Realism installer (recommended)**
Get it on [Nexus](https://www.nexusmods.com/spacebourne2/mods/11) or
[GitHub](https://github.com/hubertdungen/SpaceBourne2-Realism/releases/latest). Tick Get Out of the
Way and any other mods of the set: it installs UE4SS if you don't have it, switches the mods on and
keeps them updated.

**B. Manual** (Nexus file, or the zip on the [releases page](https://github.com/hubertdungen/SpaceBourne2-GetOutOfTheWay/releases))
1. Extract the zip into your game folder (`...\SpaceBourne 2`, the one with `SpaceBourne2.exe`).
   It creates `SB2\Binaries\Win64\Mods\GetOutOfTheWay` and switches itself on.
2. No UE4SS yet? Get [RE-UE4SS 3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1)
   and copy `dwmapi.dll`, `UE4SS.dll` and `UE4SS-settings.ini` into
   `SpaceBourne 2\SB2\Binaries\Win64\`.

**Uninstall:** untick Get Out of the Way in the installer or delete the `GetOutOfTheWay` folder. Get
Out of the Way never writes to your saves.

## Settings

Edit `Mods\GetOutOfTheWay\scripts\config.lua`, then restart the game. Every line is optional.

- `Enabled`: `false` switches the mod off completely.
- `TriggerDistance` (2.2 m): how far ahead an NPC on your path reacts (more when you run).
- `StepDistance` (0.8 m): the longest side step (0.5–1.0).
- `PathWidth` (0.75 m): how close to your line counts as "in your way".
- `ReturnToSpot`: step back to the old spot once you have passed (`true`).
- `Cooldown` (3 s): before the same NPC steps aside again.
- Who: `Civilians`, `Guards`, `Allies`, `Squad`, `Talkers` (`true` / `false`).
- `ToggleKey`: none by default. Set one to switch the mod on and off in game. The set's mods already
  use every laptop key, so pick one your own setup leaves free; the game's own keys and the other set
  mods' keys are refused.

## How it works

The game creates its NPCs; the mod notes the calm kinds as they appear (no searching through the
world). A few times a second it looks only at the NPCs within 8 m of you: if one is ahead of you and
close to your line, its own AI is told to walk to a free spot beside it, checked on the game's
navigation mesh first. Details: [DESIGN.md](DESIGN.md).

## Known limits

- **Animated decor stays put.** Many station extras (people sitting at the bar, vendors behind a
  counter, sweepers) are animations placed in the level, not characters: they cannot walk.
- **NPCs already walking keep their route.** Their own AI would cancel a step at once; they go around
  you the game's way.
- **City crowds on planets** use their own simple mover and are not affected.
- **If you stop on its spot,** the NPC waits a while and then stays where it is.

Version history: [CHANGELOG.md](CHANGELOG.md).

## The SpaceBourne 2 realism set

Separate mods that work alone or in any combination. The
[SpaceBourne 2 Realism installer](https://github.com/hubertdungen/SpaceBourne2-Realism)
([Nexus](https://www.nexusmods.com/spacebourne2/mods/11)) installs the ones you tick and keeps them updated.

- **[Hardcore Tactical Realism](https://github.com/hubertdungen/SpaceBourne2-HardcoreTacticalRealism)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/4)): realistic ballistics, wounds and tactical AI. The core of the set.
- **[Silent Ops](https://github.com/hubertdungen/SpaceBourne2-SilentOps)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/6)): stealth, silent takedowns and suppressors.
- **[Ammo Discipline](https://github.com/hubertdungen/SpaceBourne2-AmmoDiscipline)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/12)): carried ammo limits and scavenging, so every magazine counts.
- **[Gear Without Levels](https://github.com/hubertdungen/SpaceBourne2-GearWithoutLevels)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/7)): use gear above your level, with small handling penalties.
- **[Tactical First Person](https://github.com/hubertdungen/SpaceBourne2-TacticalFirstPerson)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/15)): first person on foot, weapons held up, aiming down the sights.
- **[Tactical Engineering](https://github.com/hubertdungen/SpaceBourne2-TacticalEngineering)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/10)): realistic deployable turrets.
- **[Get Out of the Way](https://github.com/hubertdungen/SpaceBourne2-GetOutOfTheWay)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/14)): NPCs step aside naturally when you walk through them.
- **[Ground Waypoints](https://github.com/hubertdungen/SpaceBourne2-GroundWaypoints)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/13)): planet waypoints on foot and on the hoverbike.
- **[Faction Power](https://github.com/hubertdungen/SpaceBourne2-FactionPower)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/9)): dungeons, strategic sales and missions earn your faction power.
- **[Bigger Armies](https://github.com/hubertdungen/SpaceBourne2-BiggerArmies)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/17)): twice the general slots for your faction's ground and space forces.
- **[Clear HUD](https://github.com/hubertdungen/SpaceBourne2-ClearHUD)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/16)): a reticle you can see and HUD colours of your choice.
- **[Split Controls](https://github.com/hubertdungen/SpaceBourne2-SplitControls)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/5)): separate vertical invert for ship and on foot, per device.
- **[SB2 HOTAS](https://github.com/hubertdungen/SpaceBourne2-HOTAS)**
  ([Nexus](https://www.nexusmods.com/spacebourne2/mods/8)): HOTAS, rudder pedals, triple screens and head tracking.

## License

MIT. See [LICENSE](LICENSE).
