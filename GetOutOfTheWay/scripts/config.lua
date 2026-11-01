--[[
  Get Out of the Way for SpaceBourne 2
  ====================================
  USER SETTINGS. Edit with any text editor, then restart the game.
  Everything here is optional: delete a line and the default is used.
]]

return {
    -- false = the mod does nothing at all.
    Enabled = true,

    -- The mod starts ON. false = start off (then use ToggleKey to switch it on).
    StartOn = true,

    -- Key to switch the mod on / off. None by default ("").
    -- The realism set uses every laptop key already, so pick a key your own setup leaves free.
    -- Refused: the game's own keys F1, F2, F5, F6, F8, F10, F12 (with or without Shift), Ctrl and
    -- Alt (map and crouch on foot), plain I (cargo) and P (a second Escape), and the keys of the
    -- other set mods (F3, F4, F7, F9, F11, Delete, 0, and Shift with F3, F4, F7, F9, F11, Delete, 0).
    ToggleKey = "",

    -- Distances, in metres.
    TriggerDistance = 2.2,  -- an NPC this far ahead on your path steps aside (further when you run). 1.0 - 4.0
    StepDistance = 0.8,     -- the longest side step. 0.5 - 1.0
    PathWidth = 0.75,       -- how close to your line counts as "in your way", each side. 0.4 - 1.5

    -- Step back to where they stood (facing the same way) once you have passed.
    ReturnToSpot = true,

    -- Seconds before the same NPC steps aside again.
    Cooldown = 3,

    -- Who steps aside. Enemies, creatures and bosses never do.
    Civilians = true,       -- civilians and civil companions
    Guards = true,          -- guards (only while calm)
    Allies = true,          -- allied crew and companions
    Squad = true,           -- your ground squad (when it has no target)
    Talkers = true,         -- traders, quest givers and crew you talk to (not while talking)

    Debug = false,          -- true: writes details to getoutoftheway.log in the mod folder
}
