# Changelog

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
