# Changelog

## 0.1.3 — 2026-11-06

- **Fix: a "Fatal Error!" crash that could come at any moment.** The mod's check, five times a
  second, ran on a UE4SS background thread. When two mods of the set did that at the same moment,
  UE4SS's own bookkeeping broke and the game crashed. It now runs on the game's own thread, driven
  by the game's tick (the same fix in every mod of the realism set).
- Not tested in game yet.

## 0.1.2 — 2026-11-06

- **Fix: a possible crash while a level loads.** The mod learnt each new NPC through a UE4SS
  feature that runs on the game's loading thread, and that could crash the game ("Fatal Error!")
  during a level load. NPCs now report themselves when they appear in the world, on the game's own
  thread.
- Tested in game with the whole realism set: no crash; your squad was tracked as before.

## 0.1.1 — 2026-11-01

- `ToggleKey` refuses Shift+F3 (HTR's slow perks since the set's key plan revision 2c); the docs no
  longer suggest it as a free key. No change in game otherwise.

## 0.1.0 — 2026-10-31

First release.

- Calm NPCs (civilians, guards at rest, allied crew and companions, your squad, traders, quest givers
  and crew) notice you walking at them (or pushing against them), turn and step out of your path,
  then step back to their spot facing the same way.
- The step is walked by the NPC's own AI on the navigation mesh, to the free side; never into a wall
  or another NPC.
- Never: enemies, creatures, bosses, NPCs in a fight, alerted, talking, sitting, in a scripted
  animation or walking their own route; nothing in a ship or on the hoverbike, or while Silent Ops
  reports Yellow or higher.
- Rate-limited (4 NPCs at once, 3 s per NPC) and cheap: no world searches, only NPCs within 8 m are
  checked, five times a second.
- On by default; settings in `config.lua`; optional `ToggleKey` (none by default).
