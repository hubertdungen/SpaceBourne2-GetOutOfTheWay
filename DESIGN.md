# Get Out of the Way — design

Part of the SpaceBourne 2 realism set. Works alone; HTR and the other set mods are optional.

## 1. Goal

In stations, markets and corridors, NPCs stand in your way. You either stop or shove them aside
with your capsule. With this mod, calm NPCs notice you walking straight at them. They turn, take a
short step out of your path (0.5–1 m), and step back to their spot once you have passed.

## 2. Who steps aside (research, game version of 2026-10)

The game has several kinds of on-foot NPCs. Only the ones with an AI controller and a real
character movement can walk a step:

| Kind (class or parent) | What it is | Steps aside? |
|---|---|---|
| `Q1_Shooter_AI_C` with `AIType` 1 Ally, 2 Civil, 4 Guard | civilians (`Q1_Civil_Follower`), guards (`Q1_GuardShooter`), companions | yes, when calm |
| `Q1_Shooter_AI_C` with `AIType` 0 Enemy / 3 Natural, bosses | enemies, creatures | never |
| `Master_Soldier_C` with `AI_Type` 1 | your ground squad | yes, when it has no target |
| `Master_NPC_C` | traders, quest givers, crew you talk to | yes, unless talking |
| `New_Q1_AI_C` with `IsCivilCompanian` | civil companions | yes, when calm |
| `Q1_NPC_Actor_C`, `Master_Anim_Decor_C` | animated decor (bar sitters, vendors, sweepers) | no: plain actors playing one animation, not characters |
| `Q1_NPC_Character_C` | scared civilians that run from fights | no: they already flee |
| `Cheap_AICharactePusher_C` (`Human_Citizen`) | city crowds moved by their own per-tick script | no (no AI controller) |

"Calm" means none of these:

- shooters: dead, not ready, blackboard `InCombat?`, `CanSeeTheTarget`, aiming (ALS `RotationMode` 2),
  boss, bank character;
- squad: a current target (`C_Target`); talkers: `InteractingTalking?`; civil companions: a sensed target;
- everyone: not walking on the ground (`CharacterMovement.MovementMode` not walking), ALS state not
  grounded, an ALS action (mantle, roll, getting up), crouched (cover), a montage playing (a
  scripted action), attached to something (a seat), already walking (its own AI is moving it).

Global quiet times: the player is not on foot (ship, hoverbike, other pawn), or Silent Ops reports
an alert of Yellow or higher near you (`ModRef` shared variable `SB2R_AlertLevel` >= 2).

## 3. How they move

The NPC's own `AIController:MoveToLocation` walks it to the side point. So it uses its normal walk
animation, turns towards where it goes (the "short turn"), and stays on the navigation mesh.
Teleporting, `LaunchCharacter` and `AddMovementInput` were rejected: a teleport and a launch slide
the NPC without leg animation, and movement input has to be fed every frame (a per-frame hook on
every NPC is too expensive).

The side point is checked first with `NavigationSystemV1:FindPathToLocationSynchronously`: the
path must be complete and short (no walking around a wall). The other side is tried if the first is
blocked, by the level or by another NPC.

Only NPCs whose AI has no move order are moved (`GetMoveStatus` idle, and slower than 1.5 m/s). An
NPC walking its own route is left alone: its behaviour tree would re-plan at once and cancel the
step (a twitch). Its speed alone is not the test: you may be pushing it.

## 4. When

Five times a second, in plain Lua, for the NPCs within 8 m:

- your path: the direction you ask to move in (`CharacterMovement:GetCurrentAcceleration`, i.e. your
  keys or stick), else your velocity. Pressed against an NPC your speed is zero but you still push
  towards it, and it must react (first play test, 2026-10-31: "if I am right in front of it and can't
  walk, it stays there");
- an NPC is in the way when it is ahead of you, closer than the trigger distance, and within the
  path width (0.75 m) of your line, on the same floor (height within 1.5 m);
- trigger distance: `TriggerDistance` (2.2 m) when walking, longer when running (your speed x 1.2 s,
  up to 4.5 m);
- an NPC with its back to you notices later (60 % of the distance); if you are also crouched, it
  does not notice at all;
- it reacts after 0.2–0.4 s (a human reaction), then steps to the side it is already on (to the right
  if it is dead centre), slightly away from you;
- step size: enough to clear your path, at least 0.5 m and at most `StepDistance` (0.8 m).

Then it waits until you have passed (you are past it and over 1.6 m from its spot, or you stopped
for a while), and walks back in two short legs, the last one along its old facing, so it ends where
it stood, facing the same way. If its own AI moved it meanwhile, it does not return.

Feel and limits: at most 4 NPCs move at once, at most 2 start per check, and one NPC waits
`Cooldown` (3 s) before it steps again.

## 5. Cost

- NPCs are learnt when the game creates them: `NotifyOnNewObject("/Script/Engine.Character")`; the
  callback only queues the object. No `FindAllOf` anywhere (50–70 ms each), no per-frame hook.
- Kept objects are checked with `IsValid` before every use, and their class name again before an
  order (an address can be reused after a level change).
- Each check (5 Hz): the player's pawn, position, velocity and movement input, and a slice of the
  tracked NPCs (each one is re-read once a second). Only while you move: one position read per NPC
  within 8 m. Switched off (`ToggleKey`): nothing but learning new NPCs.
- Only for an NPC in your way: about 15 property reads, up to two navigation queries, one move.

## 6. Compatibility with the set

- **Silent Ops**: no steps while its alert is Yellow or higher; NPCs it has made suspicious are
  aiming or in combat, so they are skipped anyway.
- **HTR**: HTR changes NPCs in combat only; this mod only moves calm ones. No shared hooks.
- **Tactical Engineering, Faction Power, Ammo Discipline, Ground Waypoints, Gear Without Levels,
  Split Controls, SB2 HOTAS**: nothing in common (turrets are not characters).
- No key by default. `ToggleKey` refuses the game's keys and the other set mods' keys (Shift+F3 is
  HTR's slow perks since key plan revision 2c).

## 7. Test plan

In game, on foot, with a test save (never the player's saves):

1. Spawned calm NPCs in front of the player (civilian, guard, companion): walk at them, run at
   them, approach from behind crouched; each one steps aside, waits, steps back.
2. An NPC against a wall steps to the free side; two NPCs side by side do not step into each other.
3. A hostile NPC and an NPC in combat never move.
4. In a ship: nothing happens.
5. Frame times with the mod on and off.

### Results (2026-10-31)

Test save: a copy of the CheckPoint save (Rivenox 116 landing pad, your squad of 4 around you),
with HTR, Silent Ops, Split Controls and Gear Without Levels installed. The player was moved by a
script (movement input from the player's own tick) or by the user. NPCs were spawned by script.

- **Squad** (`Q1_GroundSquad_C`): running through the squad, the two soldiers in the way stepped
  aside (66 and 36 cm), then followed you as usual.
- **User play test:** "better, but if I am right in front of it and can't walk, it stays there".
  Cause: the mod used your speed, which is zero when you are pressed against an NPC. Fixed: it uses
  your movement input. Re-test: pressed against a soldier and pushing at 0 cm/s, it stepped 84 cm
  aside at once.
- **Civilian** (`Q1_Civil_Follower_C`, stood up, behaviour tree stopped): you running at 3.75 m/s;
  it noticed you 2.6 m away, stepped 84 cm right, and 2 s later was back 8 cm from its spot, facing
  within 11° of its old facing. A first version cancelled the way back: ALS plays its stop
  transition as a montage, which the "scripted action" check took for one. Fixed: a step under way
  ends only for a fight, death or talk.
- **Busy NPCs:** a crouched civilian and NPCs in a fight (blackboard `InCombat?`, melee) never moved.
- **Silent Ops:** with `SB2R_AlertLevel` set to 2 (Yellow), you walked through the civilian and it
  did not move; at 0 it reacted again.
- **Not on foot:** while the ship was the pawn (loading the save), nothing ran.
- **Frames** (standing near the squad, 30 s each): mod on 95 fps, median 10.0 ms, p99 23 ms; mod
  off 95 fps, median 10.0 ms, p99 23 ms. A check costs about 0.3 ms, five times a second.
- Not tested: a real station or market (the test save starts on a landing pad) and the traders and
  quest givers (`Master_NPC_C`, moved the same way).
