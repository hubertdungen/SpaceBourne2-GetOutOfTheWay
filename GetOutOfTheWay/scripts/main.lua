--[[
  Get Out of the Way for SpaceBourne 2 (UE4SS Lua mod)
  Part of the SpaceBourne 2 realism set.

  Calm NPCs (civilians, crew, traders, allies, guards at rest) notice you walking straight at them,
  turn, step out of your path, and step back to their spot once you have passed. See DESIGN.md.

  How they move: the NPC's own AI controller walks it (AIController:MoveToLocation), so it uses
  the game's walk animation, turns the game's way and stays on the navigation mesh.

  Cost rules:
    * NPCs are learnt when they begin play (hooks on their families' ReceiveBeginPlay, on the
      game thread). No FindAllOf anywhere, no per-frame hook.
    * 5 times a second: the player, and the NPCs already within 8 m (one position read each), plus a
      slice of the other tracked NPCs (each re-read once a second).
    * only for an NPC in your way: a few property reads, up to two navigation queries, one move.
]]

local VERSION = "0.1.3"

-- Game names (the only things to fix after a game patch) -------------------------------------
local G = {
    Character = "/Script/Engine.Character",
    Player = "Q1_Character_C",
    -- NPC families that may step aside (the class or one of its parents). Everything else is ignored.
    Families = {
        Q1_Shooter_AI_C = "shooter",   -- on-foot NPCs: civilians, guards, companions (by AIType)
        Master_Soldier_C = "soldier",  -- your ground squad (AI_Type 1)
        Master_NPC_C = "talker",       -- traders, quest givers, crew you talk to
        New_Q1_AI_C = "crew",          -- civil companions (IsCivilCompanian)
    },
    -- Never: scared civilians that run from fights, city crowds moved by their own script, bosses.
    Never = {
        Q1_NPC_Character_C = true, Cheap_AICharactePusher_C = true, Q1_Boss_C = true,
        Q1_MasterMiniBoss_C = true, SneakyMiniBoss_C = true, EBP_Sister_C = true, EBP_SisterTween_C = true,
    },
    AIController = "AIController",
    AIType = { Ally = 1, Civil = 2, Guard = 4 },      -- Q1_Shooter_AI.AIType (0 Enemy, 3 Natural)
    InCombat = "InCombat?",                            -- shooter blackboard key
    NavSystem = "/Script/NavigationSystem.Default__NavigationSystemV1",
    Statics = "/Script/Engine.Default__GameplayStatics",
    AlertLevel = "SB2R_AlertLevel",                    -- Silent Ops: highest alert near you, 0 Blue .. 4 Red
    Walking = { [1] = true, [2] = true },              -- EMovementMode: Walking, NavWalking
}

-- Folder and log ---------------------------------------------------------------------------
local DIR
do
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    local cut
    for i in src:lower():gmatch("()[\\/]scripts[\\/]") do cut = i end
    DIR = cut and src:sub(1, cut) or ".\\Mods\\GetOutOfTheWay\\"
end
local LOG = DIR .. "getoutoftheway.log"
local verbose = false

local function write(prefix, ...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    local f = io.open(LOG, "a")
    if f then f:write(os.date("%H:%M:%S "), prefix, table.concat(t, " "), "\n"); f:close() end
    return table.concat(t, " ")
end
local function log(...) if verbose then write("", ...) end end
local function warn(...) print("[GetOutOfTheWay] " .. write("WARN ", ...) .. "\n") end

-- Settings ---------------------------------------------------------------------------------
local defaults = {
    Enabled = true, StartOn = true, ToggleKey = "",
    TriggerDistance = 2.2, StepDistance = 0.8, PathWidth = 0.75, ReturnToSpot = true, Cooldown = 3,
    Civilians = true, Guards = true, Allies = true, Squad = true, Talkers = true,
    Debug = false,
}
local okCfg, cfg = pcall(require, "config")
if not okCfg or type(cfg) ~= "table" then
    warn("config.lua could not be read (" .. tostring(cfg) .. "); using defaults")
    cfg = {}
end
for k, v in pairs(defaults) do if cfg[k] == nil or type(cfg[k]) ~= type(v) then cfg[k] = v end end
local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
verbose = cfg.Debug == true

if not cfg.Enabled then
    warn("Get Out of the Way " .. VERSION .. " loaded, disabled in config.lua (Enabled = false)")
    return
end

-- Tuning (cm, s) -----------------------------------------------------------------------------
local T = {
    tick = 0.2,                                              -- check period
    near = 800, nearZ = 300,                                 -- "near" NPCs are re-read every check
    trigger = clamp(cfg.TriggerDistance, 1.0, 4.0) * 100,    -- walking
    triggerTime = 1.2, triggerMax = 450,                     -- running: speed x 1.2 s, up to 4.5 m
    behind = 0.6,                                            -- an NPC with its back to you notices later
    width = clamp(cfg.PathWidth, 0.4, 1.5) * 100,            -- your path, each side of your line
    floor = 150,                                             -- same floor
    minSpeed = 60,                                           -- you must be moving
    stepMin = 50, stepMax = clamp(cfg.StepDistance, 0.5, 1.0) * 100,
    stepAway = 25,                                           -- the step also moves slightly away from you
    walking = 150,                                           -- an NPC faster than this is walking somewhere
    maxActive = 4, maxStart = 2,
    cooldown = clamp(cfg.Cooldown, 0, 30),
    stepTimeout = 2.0, asideMin = 0.8, asideMax = 10, passed = 160, legBack = 30, legTimeout = 3.0,
    roomFromNPC = 60,                                        -- the side point must be this far from other NPCs
}

-- Helpers ----------------------------------------------------------------------------------
local function valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end
-- UE4SS 3.0.1 answers a property the object does not have with a placeholder object instead of
-- nil, so a value whose type differs from a plain default counts as missing.
local PLAIN = { number = true, boolean = true, string = true }
local function get(o, prop, default)
    local ok, v = pcall(function() return o[prop] end)
    if ok and v ~= nil then
        if default ~= nil and PLAIN[type(default)] and type(v) ~= type(default) then return default end
        return v
    end
    return default
end
local function className(o)
    local ok, n = pcall(function() return o:GetClass():GetFName():ToString() end)
    return ok and n or ""
end
local function classChain(o, depth)
    local names = {}
    local ok, c = pcall(function() return o:GetClass() end)
    for _ = 1, depth or 12 do
        if not (ok and valid(c)) then break end
        local okN, n = pcall(function() return c:GetFName():ToString() end)
        if okN then names[n] = true end
        ok, c = pcall(function() return c:GetSuperStruct() end)
    end
    return names
end
local function addr(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    return ok and a or nil
end
local function location(a)
    local ok, l = pcall(function() return a:K2_GetActorLocation() end)
    if ok and l then return l.X, l.Y, l.Z end
    return nil
end
local function velocity(a)
    local ok, v = pcall(function() return a:GetVelocity() end)
    if ok and v then return v.X, v.Y end
    return 0, 0
end
local function forward(a)
    local ok, f = pcall(function() return a:GetActorForwardVector() end)
    if ok and f then
        local n = math.sqrt(f.X * f.X + f.Y * f.Y)
        if n > 0.01 then return f.X / n, f.Y / n end
    end
    return nil
end

local GS
local function statics()
    if not valid(GS) then GS = StaticFindObject(G.Statics) end
    return GS
end
local NAV, navBroken
local function nav()
    if navBroken then return nil end
    if not valid(NAV) then NAV = StaticFindObject(G.NavSystem) end
    return valid(NAV) and NAV or nil
end
local IN_COMBAT
local function inCombatName()
    if IN_COMBAT == nil then
        local ok, n = pcall(FName, G.InCombat)
        IN_COMBAT = ok and n or false
    end
    return IN_COMBAT or nil
end

-- State ------------------------------------------------------------------------------------
local S = {
    on = cfg.StartOn ~= false,
    pending = {},           -- characters the game just created (queued by the notify callback)
    list = {}, byAddr = {}, -- tracked NPCs
    cursor = 0,
    player = nil,           -- the newest on-foot player character the game created (context object)
    pawnAddr = nil, onFoot = false,
    quiet = false, alertAt = 0,
    active = 0,
    stats = { ticks = 0, time = 0, max = 0, steps = 0, returns = 0, skipped = 0, since = os.clock() },
    skipLog = {},
}

-- Which families the settings allow, and whether this NPC is on a side that may step aside.
local function sideAllowed(e, npc)
    local f = e.fam
    if f == "shooter" then
        local t = get(npc, "AIType", -1)
        local companion = get(npc, "IsCompanian", false) == true
        if companion then return cfg.Allies end
        if t == G.AIType.Civil then return cfg.Civilians end
        if t == G.AIType.Guard then return cfg.Guards end
        if t == G.AIType.Ally then return cfg.Allies end
        return false
    elseif f == "soldier" then
        return cfg.Squad and get(npc, "AI_Type", -1) == 1
    elseif f == "talker" then
        return cfg.Talkers
    elseif f == "crew" then
        return cfg.Civilians and get(npc, "IsCivilCompanian", false) == true
    end
    return false
end

-- Why this NPC must not be moved right now (nil = calm and free).
-- light: only the reasons that end a step already under way (fight, death, talk). The others
-- (crouched, a montage, not grounded...) are normal while it walks: ALS plays its stop and turn
-- transitions as montages.
local function busyReason(e, npc, light)
    if not sideAllowed(e, npc) then return "side" end
    local f = e.fam
    if f == "shooter" then
        -- (not "Ready?": civilians spawned by script stay not ready, and a not-ready NPC cannot fight)
        if get(npc, "NPCDead", false) or get(npc, "GoreDead?", false) then return "dead" end
        if get(npc, "IsBoss", false) or get(npc, "IsBankCharacter", false) then return "special" end
        if get(npc, "CanSeeTheTarget", false) then return "combat" end
        if get(npc, "SwordAttackOn", false) or get(npc, "ThrowingGranede", false) then return "combat" end
    elseif f == "soldier" then
        if valid(get(npc, "C_Target")) then return "combat" end
    elseif f == "talker" then
        if get(npc, "InteractingTalking?", false) then return "talking" end
    elseif f == "crew" then
        if valid(get(npc, "BestSensedActor")) or get(npc, "DirectAttack?", false) then return "combat" end
        if get(npc, "Ragdoling", false) or get(npc, "DeadMontagePlaying", false) then return "dead" end
    end
    -- ALS states (missing on non-ALS characters: then the defaults pass)
    if get(npc, "RotationMode", 0) == 2 then return "aiming" end
    if light then
        if e.fam == "shooter" then
            local bb = get(get(npc, "Controller"), "Blackboard")
            local key = inCombatName()
            if key and valid(bb) then
                local ok, v = pcall(function() return bb:GetValueAsBool(key) end)
                if ok and v == true then return "combat" end
            end
        end
        return nil
    end
    if get(npc, "MovementState", 1) ~= 1 then return "not grounded" end
    if get(npc, "MovementAction", 0) ~= 0 then return "action" end
    if get(npc, "Stance", 0) ~= 0 then return "crouched" end
    local cm = get(npc, "CharacterMovement")
    if not valid(cm) then return "no movement" end
    if not G.Walking[get(cm, "MovementMode", 0)] then return "not walking" end
    local ctrl = get(npc, "Controller")
    if not valid(ctrl) then return "no controller" end
    local ca = addr(ctrl)
    if ca ~= e.ctrlAddr then -- an AI controller (not the player's), checked once per controller
        e.ctrlAddr, e.ctrlAI = ca, classChain(ctrl)[G.AIController] == true
    end
    if not e.ctrlAI then return "not AI" end
    if f == "shooter" then
        local bb = get(ctrl, "Blackboard")
        local key = inCombatName()
        if key and valid(bb) then
            local ok, v = pcall(function() return bb:GetValueAsBool(key) end)
            if ok and v == true then return "combat" end
        end
    end
    local okP, parent = pcall(function() return npc:GetAttachParentActor() end)
    if okP and valid(parent) then return "attached" end
    local okA, playing = pcall(function() return npc.Mesh:GetAnimInstance():IsAnyMontagePlaying() end)
    if okA and playing == true then return "montage" end
    return nil, ctrl
end

-- Reasons that pass in a moment: look again soon.
local BRIEF = { ["own move"] = true, walking = true, montage = true, ["no longer in the way"] = true }
local function skip(e, why, now)
    S.stats.skipped = S.stats.skipped + 1
    e.cool = now + (BRIEF[why] and 0.4 or 1.5)
    if verbose then
        local k = e.cls .. ":" .. why
        if (S.skipLog[k] or 0) < now then
            S.skipLog[k] = now + 10
            log("skip " .. e.cls .. " (" .. why .. ")")
        end
    end
end

-- Registry -----------------------------------------------------------------------------------
local function untrack(i)
    local e = S.list[i]
    if e.state then S.active = S.active - 1 end
    S.byAddr[e.addr] = nil
    table.remove(S.list, i)
end

local function adopt(obj, now)
    if not valid(obj) then return end
    local a = addr(obj)
    if not a then return end
    local okN, full = pcall(function() return obj:GetFullName() end)
    if not okN or type(full) ~= "string" or full:find("Default__", 1, true) or not full:find(":PersistentLevel.", 1, true) then return end
    local chain = classChain(obj)
    if chain[G.Player] then
        S.player = obj
        return
    end
    local fam
    for cls, f in pairs(G.Families) do if chain[cls] then fam = f; break end end
    for cls in pairs(G.Never) do if chain[cls] then fam = nil; break end end
    if verbose then -- debug: which characters this place has (once per class)
        local cn = className(obj)
        S.seen = S.seen or {}
        if not S.seen[cn] then S.seen[cn] = true; log("seen " .. cn .. " -> " .. (fam or "ignored")) end
    end
    if not fam then return end
    local old = S.byAddr[a]
    if old then -- the address was reused: forget the old one
        for i = #S.list, 1, -1 do if S.list[i] == old then untrack(i); break end end
    end
    local e = { obj = obj, addr = a, cls = className(obj), fam = fam, readAt = 0, cool = now + 1 }
    S.list[#S.list + 1] = e
    S.byAddr[a] = e
    log("tracking " .. e.cls .. " (" .. fam .. ")")
end

-- Movement -----------------------------------------------------------------------------------
local function vec(x, y, z) return { X = x, Y = y, Z = z } end

-- Path length on the navigation mesh, false if there is no complete path, nil if unknown.
local function pathLength(npc, x0, y0, z0, x1, y1, z1)
    local ns = nav()
    if not ns then return nil end
    local ok, path = pcall(function() return ns:FindPathToLocationSynchronously(npc, vec(x0, y0, z0), vec(x1, y1, z1), npc, nil) end)
    if not ok then
        navBroken = true
        warn("navigation query unavailable (" .. tostring(path) .. "); using the move order's own check")
        return nil
    end
    if not valid(path) then return false end
    local okL, len = pcall(function() return path:GetPathLength() end)
    if not okL or type(len) ~= "number" or len <= 0 then return false end
    local okP, partial = pcall(function() return path:IsPartial() end)
    if okP and partial == true then return false end
    return len
end

-- Order the NPC's AI controller to walk to (x, y, z). true if the order was accepted.
local function moveTo(ctrl, x, y, z)
    local ok, r = pcall(function() return ctrl:MoveToLocation(vec(x, y, z), 15.0, false, true, true, false, nil, false) end)
    if not ok then
        if not S.moveWarned then S.moveWarned = true; warn("MoveToLocation failed: " .. tostring(r)) end
        return false
    end
    return r == 1 or r == 2 -- AlreadyAtGoal / RequestSuccessful
end

local function moveStatus(ctrl)
    local ok, st = pcall(function() return ctrl:GetMoveStatus() end)
    return ok and st or -1 -- 0 Idle, 1 Waiting, 2 Paused, 3 Moving
end

-- Is the controller's current move still ours (towards target t)? Our legs are short and straight,
-- so the next path point is the target; anything else is a new order from the NPC's own AI.
local function stillOurs(ctrl, t)
    local ok, d = pcall(function() return ctrl:GetImmediateMoveDestination() end)
    if not ok or not d then return true end
    return (d.X - t.x) ^ 2 + (d.Y - t.y) ^ 2 < 50 * 50
end

local function finish(e, now, cool, why)
    if e.state then
        S.active = S.active - 1
        if why then log("done " .. e.cls .. " (" .. why .. ")") end
    end
    e.state, e.ctrl, e.target = nil, nil, nil
    e.cool = now + (cool or T.cooldown)
end

-- Is (x, y) free of other tracked NPCs?
local function roomAt(self, x, y)
    for _, o in ipairs(S.list) do
        if o ~= self and o.x and o.near then
            local dx, dy = o.x - x, o.y - y
            if dx * dx + dy * dy < T.roomFromNPC * T.roomFromNPC then return false end
        end
    end
    return true
end

-- The NPC e is in your way: turn and step aside.
local function stepAside(e, now, P)
    local npc = e.obj
    if className(npc) ~= e.cls then e.dead = true; return end
    local why, ctrl = busyReason(e, npc)
    if why then return skip(e, why, now) end
    -- walking its own route: its AI has a move order. (Its speed alone says nothing: you may be
    -- pushing it.)
    if moveStatus(ctrl) ~= 0 then return skip(e, "own move", now) end
    local vx, vy = velocity(npc)
    if vx * vx + vy * vy > T.walking * T.walking then return skip(e, "walking", now) end
    local nx, ny, nz = location(npc)
    if not nx then return end
    -- fresh geometry
    local ux, uy = P.ux, P.uy
    local dx, dy = nx - P.x, ny - P.y
    local along = dx * ux + dy * uy
    local cross = ux * dy - uy * dx -- > 0: the NPC is on your right (UE: X forward, Y right)
    if along <= 0 or math.abs(cross) > T.width then return skip(e, "no longer in the way", now) end
    local side = cross >= -10 and 1 or -1 -- dead centre: keep right
    local step = clamp(T.width + 20 - math.abs(cross), T.stepMin, T.stepMax)
    local px, py = -uy, ux -- your right
    local tries = { side, -side }
    for _, sd in ipairs(tries) do
        -- from the NPC's line: clear your path on that side, slightly away from you
        local lateral = (sd == side) and step or clamp(T.width + 20 + math.abs(cross), T.stepMin, T.stepMax + 20)
        local tx = nx + px * sd * lateral + ux * T.stepAway
        local ty = ny + py * sd * lateral + uy * T.stepAway
        if roomAt(e, tx, ty) then
            local straight = math.sqrt((tx - nx) ^ 2 + (ty - ny) ^ 2)
            local len = pathLength(npc, nx, ny, nz, tx, ty, nz)
            if len ~= false and (len == nil or len < straight * 1.6 + 30) then
                if moveTo(ctrl, tx, ty, nz) then
                    local fx, fy = forward(npc)
                    e.home = { x = nx, y = ny, z = nz, fx = fx or -ux, fy = fy or -uy }
                    e.aside = { x = tx, y = ty }
                    e.state, e.ctrl, e.since, e.target = "step", ctrl, now, e.aside
                    S.active = S.active + 1
                    S.stats.steps = S.stats.steps + 1
                    log(string.format("step %s side=%s %.0f cm (you %.0f cm away at %.0f cm/s, %.0f cm off your line, path %s)",
                        e.cls, sd > 0 and "R" or "L", straight, along, P.sp, cross, len and string.format("%.0f", len) or "?"))
                    return
                end
            end
        end
    end
    skip(e, "no room", now)
    e.cool = now + 2
end

-- Steps in progress: wait, return to the spot, finish.
local function updateActive(e, now, P)
    local npc, ctrl = e.obj, e.ctrl
    if not valid(ctrl) then return finish(e, now, nil, "controller gone") end
    local why = busyReason(e, npc, true)
    if why then return finish(e, now, 5, why) end -- e.g. a fight: leave it
    local st = moveStatus(ctrl)
    if st == 3 and e.target and not stillOurs(ctrl, e.target) then
        return finish(e, now, nil, "its own AI gave a new order") -- leave it to it
    end
    if e.state == "step" then
        if st == 0 or now - e.since > T.stepTimeout then e.state, e.since, e.target = "aside", now, nil end
    elseif e.state == "aside" then
        local home = e.home
        local pdx, pdy = home.x - P.x, home.y - P.y
        local pd = math.sqrt(pdx * pdx + pdy * pdy)
        local coming = P.moving and (pdx * P.ux + pdy * P.uy) > 0
        local waited = now - e.since
        if waited < T.asideMin then return end
        if waited > T.asideMax * 3 then return finish(e, now, nil, "you stay on its spot") end
        local passed = pd > T.passed and not coming
        if not passed and not (waited > T.asideMax and pd > 120) then return end
        if not (cfg.ReturnToSpot and e.fam ~= "soldier") then return finish(e, now, nil, "stays") end
        -- only if its own AI left it where we put it
        local nx, ny = location(npc)
        if not nx or st ~= 0 or (nx - e.aside.x) ^ 2 + (ny - e.aside.y) ^ 2 > 60 * 60 then
            return finish(e, now, nil, "moved on by itself")
        end
        local bx, by = home.x - home.fx * T.legBack, home.y - home.fy * T.legBack
        if moveTo(ctrl, bx, by, home.z) then
            e.state, e.since, e.target = "back1", now, { x = bx, y = by }
        else
            finish(e, now, nil, "no way back")
        end
    elseif e.state == "back1" then
        if st == 0 or now - e.since > T.legTimeout then
            -- last leg along the old facing: it ends where it stood, facing the same way
            if moveTo(ctrl, e.home.x, e.home.y, e.home.z) then
                e.state, e.since, e.target = "back2", now, { x = e.home.x, y = e.home.y }
            else
                finish(e, now, nil, "no way back")
            end
        end
    elseif e.state == "back2" then
        if st == 0 or now - e.since > T.legTimeout then
            S.stats.returns = S.stats.returns + 1
            finish(e, now, nil, "back on its spot")
        end
    end
end

-- The check (5 times a second) -----------------------------------------------------------------
local function readAlert(now)
    if now < S.alertAt then return end
    S.alertAt = now + 1
    local ok, v = pcall(function() return ModRef:GetSharedVariable(G.AlertLevel) end)
    local q = ok and type(v) == "number" and v >= 2
    if q ~= S.quiet then log("Silent Ops alert " .. tostring(v) .. (q and ": quiet" or ": calm again")) end
    S.quiet = q
end

local function tick(now)
    if verbose then -- debug only: toggle.txt in the mod folder switches the mod (tests without a keyboard)
        local f = io.open(DIR .. "toggle.txt", "r")
        if f then f:close(); os.remove(DIR .. "toggle.txt"); S.on = not S.on; log("toggled by file: " .. tostring(S.on)) end
    end
    -- characters created since the last check
    if #S.pending > 0 then
        local q = S.pending
        S.pending = {}
        local seen = {} -- a child's BeginPlay and its parent's both report it
        for _, o in ipairs(q) do
            local a = addr(o)
            if a and not seen[a] then seen[a] = true; adopt(o, now) end
        end
    end
    if not S.on then -- switched off: only keep learning new NPCs
        if S.active > 0 then for _, e in ipairs(S.list) do if e.state then finish(e, now) end end end
        return
    end
    -- the player's pawn, asked of the world of a live object: the player character, else a tracked NPC
    local pawn
    local ctxs = { S.player }
    for _, e in ipairs(S.list) do if valid(e.obj) then ctxs[#ctxs + 1] = e.obj; break end end
    for i = 1, 2 do
        local ctx = ctxs[i]
        if valid(ctx) then
            local okP, p = pcall(function() return statics():GetPlayerPawn(ctx, 0) end)
            if okP and valid(p) then pawn = p; break end
        end
    end
    if not pawn then return end
    local pa = addr(pawn)
    if pa ~= S.pawnAddr then
        S.pawnAddr = pa
        S.onFoot = classChain(pawn)[G.Player] == true
        log("pawn " .. className(pawn) .. (S.onFoot and " (on foot)" or " (not on foot)"))
    end
    readAlert(now)
    local px, py, pz = location(pawn)
    if not px then return end
    local vx, vy = velocity(pawn)
    local sp = math.sqrt(vx * vx + vy * vy)
    -- Where you want to go: the movement you ask for (your keys / stick), not only where you move.
    -- Pressed against an NPC your speed drops to zero, but you still push towards it.
    if pa ~= S.cmPawn then S.cmPawn, S.cm = pa, get(pawn, "CharacterMovement") end
    local ax, ay = 0, 0
    if valid(S.cm) then
        local okA, a = pcall(function() return S.cm:GetCurrentAcceleration() end)
        if okA and a then ax, ay = a.X, a.Y end
    end
    local am = math.sqrt(ax * ax + ay * ay)
    local pushing = am > 1
    local P = { x = px, y = py, z = pz, sp = sp, moving = sp >= T.minSpeed or pushing }
    if pushing then P.ux, P.uy = ax / am, ay / am
    elseif sp > 1 then P.ux, P.uy = vx / sp, vy / sp
    else P.ux, P.uy = 1, 0 end
    local allowed = S.on and S.onFoot and not S.quiet

    -- tracked NPCs: the near ones every check, the others in slices (each once a second)
    local n = #S.list
    local slice = math.max(1, math.ceil(n * T.tick / 1.0))
    for _ = 1, math.min(slice, n) do
        S.cursor = S.cursor % #S.list + 1
        local e = S.list[S.cursor]
        if e and not e.near then
            if not valid(e.obj) or e.dead then
                untrack(S.cursor); S.cursor = S.cursor - 1
                if #S.list == 0 then break end
            else
                local x, y, z = location(e.obj)
                if x then
                    e.x, e.y, e.z = x, y, z
                    e.near = (x - px) ^ 2 + (y - py) ^ 2 < T.near * T.near and math.abs(z - pz) < T.nearZ
                end
            end
        end
    end
    local cands = {}
    for i = #S.list, 1, -1 do
        local e = S.list[i]
        -- near NPCs are re-read every check only while you move (or one is stepping aside)
        if e.state or e.notice or (e.near and P.moving and allowed) then
            if not valid(e.obj) or e.dead then
                untrack(i)
            else
                local x, y, z = location(e.obj)
                if x then
                    e.x, e.y, e.z = x, y, z
                    e.near = (x - px) ^ 2 + (y - py) ^ 2 < T.near * T.near and math.abs(z - pz) < T.nearZ
                end
                if e.state then
                    if allowed then
                        local ok, err = pcall(updateActive, e, now, P)
                        if not ok then warn("update: " .. tostring(err)); finish(e, now, 5) end
                    else
                        finish(e, now)
                    end
                elseif e.notice then
                    if now >= e.notice then e.notice = nil; cands[#cands + 1] = e end
                elseif allowed and P.moving and e.near and now >= e.cool and math.abs(e.z - pz) < T.floor then
                    -- in your way?
                    local dx, dy = e.x - px, e.y - py
                    local along = dx * P.ux + dy * P.uy
                    local cross = P.ux * dy - P.uy * dx
                    if along > 0 and math.abs(cross) < T.width then
                        local reach = math.max(T.trigger, math.min(sp * T.triggerTime, T.triggerMax))
                        local fx, fy = e.fx, e.fy
                        if not fx or now >= (e.fAt or 0) then
                            fx, fy = forward(e.obj); e.fx, e.fy, e.fAt = fx, fy, now + 1
                        end
                        local backTurned = fx and (fx * -dx + fy * -dy) < -0.3 * math.sqrt(dx * dx + dy * dy)
                        if backTurned then
                            if get(pawn, "Stance", 0) == 1 then reach = 0 else reach = reach * T.behind end
                        end
                        if along <= reach then
                            if verbose then
                                log(string.format("notice %s: %.0f cm ahead, %.0f cm off your line, you at %.0f cm/s (reach %.0f%s)",
                                    e.cls, along, cross, sp, reach, backTurned and ", behind it" or ""))
                            end
                            -- noticed: reacts on this check or the next one (0.2-0.4 s)
                            if math.random() < 0.5 then cands[#cands + 1] = e else e.notice = now + T.tick * 0.9 end
                        end
                    end
                end
            end
        end
    end
    if not (allowed and P.moving) then return end
    local started = 0
    for _, e in ipairs(cands) do
        if S.active >= T.maxActive or started >= T.maxStart then break end
        if valid(e.obj) and not e.state then
            local ok, err = pcall(stepAside, e, now, P)
            if not ok then warn("step: " .. tostring(err)); e.cool = now + 5 end
            if e.state then started = started + 1 end
        end
    end
end

-- Loop ---------------------------------------------------------------------------------------
local errors = 0
local function guardedTick()
    if errors >= 25 then return end
    local now = os.clock()
    local ok, err = pcall(tick, now)
    if not ok then
        errors = errors + 1
        if errors <= 3 then warn("error: " .. tostring(err)) end
        if errors >= 25 then warn("switched off after repeated errors") end
    end
    local dt = os.clock() - now
    local st = S.stats
    st.ticks, st.time = st.ticks + 1, st.time + dt
    if dt > st.max then st.max = dt end
    if verbose and now - st.since >= 10 then
        local near = 0
        for _, e in ipairs(S.list) do if e.near then near = near + 1 end end
        log(string.format("perf: %d checks avg %.3f ms max %.2f ms; tracked %d, near %d, active %d; steps %d, returns %d, skipped %d; on=%s foot=%s quiet=%s",
            st.ticks, st.ticks > 0 and st.time / st.ticks * 1000 or 0, st.max * 1000, #S.list, near, S.active,
            st.steps, st.returns, st.skipped, tostring(S.on), tostring(S.onFoot), tostring(S.quiet)))
        S.stats = { ticks = 0, time = 0, max = 0, steps = 0, returns = 0, skipped = 0, since = now }
    end
end

-- NPCs report themselves when they begin play: hooks on their families' ReceiveBeginPlay, on the
-- game thread (0.1.2). 0.1.1 used NotifyOnNewObject on Character, whose callback UE4SS runs on
-- whatever thread creates the object (the loading thread during a level load), which could crash
-- inside UE4SS (2026-11-06). A class is hooked once it is loaded; a lookup miss costs ~37 ms, so
-- misses back off up to a minute.
local BEGIN = {
    "/Game/Locomotion/Blueprints/CharacterLogic/ALS_Base.ALS_Base_C:ReceiveBeginPlay",
    "/Game/1Data/11_AI/Q1_Shooter_AI.Q1_Shooter_AI_C:ReceiveBeginPlay",
    "/Game/1Data/11_AI/BattleAI/Master_Soldier.Master_Soldier_C:ReceiveBeginPlay",
    "/Game/Locomotion/Blueprints/CharacterLogic/Master_NPC.Master_NPC_C:ReceiveBeginPlay",
}
local hooked, hookAt, hookWait = {}, 0, 1
local function onBegin(self)
    local o = self:get()
    if o ~= nil then S.pending[#S.pending + 1] = o end
end
local function hookFamilies(now)
    if now < hookAt then return end
    local missing = 0
    for _, fn in ipairs(BEGIN) do
        if not hooked[fn] then
            local cls = StaticFindObject((fn:gsub(":ReceiveBeginPlay$", "")))
            if valid(cls) and pcall(RegisterHook, fn, onBegin) then
                hooked[fn] = true
                log("watching " .. fn:match("%.([%w_]+):"))
            else
                missing = missing + 1
            end
        end
    end
    if missing == 0 then hookAt = math.huge else hookAt = now + hookWait; hookWait = math.min(hookWait * 2, 60) end
end

-- The check runs on the game thread, pumped by the HUD draw, with the ALS character tick as a
-- fallback (gametick.lua, 0.1.3). Until
-- 0.1.2 it was LoopAsync + ExecuteInGameThread: called from UE4SS's async thread,
-- ExecuteInGameThread writes a map all mods share without a lock, and two mods doing it at once
-- crashed the game (UE4SS.dll+0x87c104). After each load or possession (ClientRestart) the pump
-- hook is set again and the families are looked for at once, before the NPCs begin play.
local GT = require("gametick")
GT.log = function(msg) warn(msg) end
GT.drive(GT.HUD_TICK, "hud")
GT.drive(GT.FOOT_TICK, "foot")
GT.boot(function(now) pcall(hookFamilies, now) end)
GT.every(T.tick, function(now)
    pcall(hookFamilies, now)
    guardedTick()
end)

-- Optional toggle key (none by default) --------------------------------------------------------
-- Realism set key plan: the game's keys are refused with or without Shift, and so are the keys the
-- other set mods use (Shift+F3 is HTR's slow perks). UE4SS matches modifiers exactly.
local GAME_KEYS = { F1 = 1, F2 = 1, F5 = 1, F6 = 1, F8 = 1, F10 = 1, F12 = 1 }
local PLAIN_TAKEN = {
    F3 = "Silent Ops", F4 = "Silent Ops", F7 = "HTR", F9 = "HTR", F11 = "HTR", DEL = "Tactical Engineering",
    ZERO = "Ground Waypoints", I = "the game's cargo key", P = "a second Escape key in the game",
}
local SHIFT_TAKEN = {
    F3 = "HTR (slow perks)",
    F4 = "Silent Ops", F7 = "HTR", F9 = "Faction Power", F11 = "Tactical First Person",
    DEL = "Gear Without Levels", ZERO = "Ammo Discipline",
}
local KEY_ALIAS = { INSERT = "INS", DELETE = "DEL", PAGEDOWN = "PAGE_DOWN", PAGEUP = "PAGE_UP", ESC = "ESCAPE",
    ["0"] = "ZERO", ["1"] = "ONE", ["2"] = "TWO", ["3"] = "THREE", ["4"] = "FOUR", ["5"] = "FIVE", ["6"] = "SIX",
    ["7"] = "SEVEN", ["8"] = "EIGHT", ["9"] = "NINE" }
local function bindToggle(spec)
    if type(spec) ~= "string" or spec:gsub("%s", "") == "" then return nil end
    local shift, key, bad = false, nil, nil
    for part in spec:upper():gsub("%s", ""):gmatch("[^+]+") do
        if part == "SHIFT" then shift = true
        elseif part == "CTRL" or part == "CONTROL" or part == "ALT" then bad = "Ctrl and Alt are game actions on foot"
        else key = KEY_ALIAS[part] or part end
    end
    if not bad and not (key and Key and Key[key]) then bad = "unknown key" end
    if not bad and GAME_KEYS[key] then bad = "the game uses " .. key end
    if not bad and not shift and PLAIN_TAKEN[key] then bad = "plain " .. key .. ": " .. PLAIN_TAKEN[key] end
    if not bad and shift and SHIFT_TAKEN[key] then bad = "Shift+" .. key .. ": " .. SHIFT_TAKEN[key] end
    if bad then warn("ToggleKey '" .. spec .. "' refused (" .. bad .. "); no key bound"); return nil end
    local function toggle()
        ExecuteInGameThread(function()
            S.on = not S.on
            warn("Get Out of the Way " .. (S.on and "ON" or "OFF"))
        end)
    end
    if shift then RegisterKeyBind(Key[key], { ModifierKey.SHIFT }, toggle) else RegisterKeyBind(Key[key], toggle) end
    return (shift and "Shift+" or "") .. key
end
local bound = bindToggle(cfg.ToggleKey)

warn(string.format("=== Get Out of the Way %s loaded: %s, toggle key %s ===", VERSION, S.on and "ON" or "OFF", bound or "none"))
