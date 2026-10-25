---------------------------------------------------------------------------
-- Pass Out - Build 42
--
-- Forces the character to fall asleep on the spot after staying at maximum
-- tiredness for a configurable number of in-game hours. A gradual "blacking
-- out" post-process (blur / desaturate / darken / vignette) plays while you go
-- under, reusing the foraging search-mode effect.
--
-- The collapse is FORCED: it reuses the vanilla sleep path but skips the
-- refusal checks that vanilla's onSleepWalkToComplete applies (nearby zombies,
-- panic, pain, the ExerciseEnded anim var) - those would silently abort the
-- sleep and are why "nothing happened" before. The single-player and
-- multiplayer branches of the vanilla path are preserved so it stays MP-safe.
--
-- Client-side. Works in single-player, on multiplayer clients (only when the
-- server both allows and needs sleep) and in split-screen, where every local
-- player is tracked independently via their own ModData state machine.
---------------------------------------------------------------------------

local PHASE_PASSING = "passing"

-- How far ahead of the actual pass-out the warning is shown, in in-game
-- seconds. 600s = 10 in-game minutes (matches the original mod's warning).
local WARN_LEAD_SECONDS = 600

-- Shortest hold (real seconds) on a collapse wherever input can wake a sleeper,
-- even with Forced Pass-Out Duration at 0, so a movement key that was still
-- held as the character dropped does not undo the collapse on the next frame.
local MIN_HOLD_SECONDS = 3

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Master on/off switch. Defaults to enabled if the option is missing (e.g. an
-- older sandbox config that predates the toggle).
local function modEnabled()
    local sv = SandboxVars.PassOut
    if sv == nil or sv.enableMod == nil then return true end
    return sv.enableMod
end

-- Passing out only makes sense where sleeping is possible.
--   Single-player / host : always.
--   Multiplayer client    : only when the server allows AND needs sleep,
--                           which mirrors vanilla's own sleep gating.
local function sleepAllowed()
    if not isClient() then return true end
    return getServerOptions():getBoolean("SleepAllowed")
        and getServerOptions():getBoolean("SleepNeeded")
end

-- Run fn(playerObj) for every living local player (1 in SP/MP, up to 4 in
-- split-screen).
local function forEachLocalPlayer(fn)
    local n = getNumActivePlayers()
    if n and n > 0 then
        for i = 0, n - 1 do
            local p = getSpecificPlayer(i)
            if p and not p:isDead() then fn(p) end
        end
    else
        local p = getPlayer()
        if p and not p:isDead() then fn(p) end
    end
end

-- Mirrors IsoPlayer.processWakingUp: pressing a movement or aim key wakes a
-- sleeper only on a multiplayer client or in split-screen.
local function wakesOnInput()
    return isClient() or getNumActivePlayers() > 1
end

-- Trait check supporting both B42 object registry (with cached lookup) and fallback
local cachedProneTrait = nil
local cachedResistantTrait = nil

local function getRegisteredTrait(id)
    if CharacterTrait and CharacterTrait.get and ResourceLocation and ResourceLocation.of then
        local ok, trait = pcall(function() return CharacterTrait.get(ResourceLocation.of(id)) end)
        if ok and trait then return trait end
    end
    return nil
end

local function hasTrait(playerObj, name)
    if not playerObj then return false end
    if name == "ProneToPassing" then
        if not cachedProneTrait then
            cachedProneTrait = getRegisteredTrait("passout:pronetopassing")
        end
        if cachedProneTrait then
            local ok, has = pcall(function() return playerObj:hasTrait(cachedProneTrait) end)
            if ok and has ~= nil then return has end
        end
    elseif name == "ResistantToPassing" then
        if not cachedResistantTrait then
            cachedResistantTrait = getRegisteredTrait("passout:resistanttopassing")
        end
        if cachedResistantTrait then
            local ok, has = pcall(function() return playerObj:hasTrait(cachedResistantTrait) end)
            if ok and has ~= nil then return has end
        end
    end

    if CharacterTrait and CharacterTrait.get and ResourceLocation and ResourceLocation.of then
        local lower = string.lower(name)
        for _, id in ipairs({ "passout:" .. lower, "passout:" .. name, name }) do
            local trait = getRegisteredTrait(id)
            if trait then
                local ok2, has = pcall(function() return playerObj:hasTrait(trait) end)
                if ok2 and has then return true end
            end
        end
    end
    if playerObj.HasTrait then
        local ok, has = pcall(function() return playerObj:HasTrait(name) end)
        if ok and has then return true end
    end
    return false
end

-- setBlockMovement makes IsoPlayer.pressedMovement report false, which is what
-- stops a held movement key from waking the player. Only ever released if we
-- set it, so it can't clobber anything else that blocks movement.
local function holdMovement(playerObj, md, on)
    if on then
        if not playerObj:isBlockMovement() then playerObj:setBlockMovement(true) end
        md.poBlockedMovement = true
    elseif md.poBlockedMovement then
        playerObj:setBlockMovement(false)
        md.poBlockedMovement = nil
    end
end

---------------------------------------------------------------------------
-- Project Viewpoint
--
-- Viewpoint's first/third-person view skips vanilla's weather-FX pass, and that
-- pass is what draws the search-mode blur / desaturate / darken used for the
-- blackout - so under Viewpoint the screen would never dim. While its view is
-- on, a plain darkening vignette is drawn in the UI layer instead (which
-- Viewpoint still renders). Blur and desaturation have no Lua equivalent.
---------------------------------------------------------------------------

local VIGNETTE_BANDS = 12

local function viewpointActive()
    local vp = Viewpoint
    if not (vp and vp.View and vp.View.next) then return false end
    -- next() offers "first" exactly when its 3D view is off.
    return vp.View.next() ~= "first"
end

local BlackoutUI = ISUIElement:derive("PassOutBlackoutUI")
local blackoutUIs = {}

function BlackoutUI:new(pnum)
    local o = ISUIElement.new(self, getPlayerScreenLeft(pnum), getPlayerScreenTop(pnum),
        getPlayerScreenWidth(pnum), getPlayerScreenHeight(pnum))
    o.pnum = pnum
    o.target = 0
    o.shown = 0
    o.lastMs = getTimestampMs()
    return o
end

function BlackoutUI:render()
    local now = getTimestampMs()
    local dt = math.min((now - self.lastMs) / 1000, 0.25)
    self.lastMs = now

    if not viewpointActive() then
        self.shown = 0
        return
    end

    -- Follow split-screen layout and resolution changes.
    local pnum = self.pnum
    self:setX(getPlayerScreenLeft(pnum))
    self:setY(getPlayerScreenTop(pnum))
    self:setWidth(getPlayerScreenWidth(pnum))
    self:setHeight(getPlayerScreenHeight(pnum))

    -- The factor only steps once per in-game minute; ease toward it so the
    -- screen sinks rather than jumps.
    self.shown = self.shown + (self.target - self.shown) * math.min(1, dt * 1.5)
    local f = math.min(self.shown, 1)
    if f <= 0.001 then return end

    local w, h = self.width, self.height
    self:drawRect(0, 0, w, h, 0.55 * f, 0, 0, 0)

    -- Nested frames, darkest at the edge, closing in as f rises.
    local reach = math.min(w, h) * 0.5 * f
    local band = reach / VIGNETTE_BANDS
    for i = 1, VIGNETTE_BANDS do
        local a = 0.45 * f * (1 - (i - 1) / VIGNETTE_BANDS)
        local inset = (i - 1) * band
        local innerW, innerH = w - inset * 2, h - inset * 2
        if innerW <= 0 or innerH <= 0 then break end
        self:drawRect(inset, inset, innerW, band, a, 0, 0, 0)
        self:drawRect(inset, h - inset - band, innerW, band, a, 0, 0, 0)
        self:drawRect(inset, inset + band, band, innerH - band * 2, a, 0, 0, 0)
        self:drawRect(w - inset - band, inset + band, band, innerH - band * 2, a, 0, 0, 0)
    end
end

-- Only built once Viewpoint is actually loaded; costs nothing without it.
local function setViewpointBlackout(pnum, f)
    if Viewpoint == nil then return end
    local ui = blackoutUIs[pnum]
    if not ui then
        ui = BlackoutUI:new(pnum)
        ui:initialise()
        ui:instantiate()
        ui.javaObject:setConsumeMouseEvents(false)
        ui.javaObject:setIgnoreLossControl(true)
        ui:addToUIManager()
        ui:backMost()
        blackoutUIs[pnum] = ui
    end
    ui.target = f
end

local function clearViewpointBlackout(pnum)
    local ui = blackoutUIs[pnum]
    if ui then
        ui:removeFromUIManager()
        blackoutUIs[pnum] = nil
    end
end

local function setBlackoutOverride(pnum, on)
    local sm = getSearchMode()
    if sm and sm.setOverrideSearchManager then
        sm:setOverrideSearchManager(pnum, on)
    end
    if triggerEvent then
        triggerEvent("OnOverrideSearchManager", on, pnum)
    end
end

-- Turn off the black-out post-process for a player and forget the watch/ramp
-- state. (Does not touch the forced-sleep window - that is cleared on wake.)
local function clearState(playerObj, md)
    md.poTiredTime = nil
    md.poRandomnessValue = nil
    md.poWarned = nil
    if md.poPhase ~= nil then
        md.poPhase = nil
        md.poPassOutFactor = nil
        md.poStepFactor = nil
        local pnum = playerObj:getPlayerNum()
        local sm = getSearchMode()
        if sm then
            local mode = sm:getSearchModeForPlayer(pnum)
            if mode then
                -- Reset search-mode targets back to engine defaults so subsequent foraging is not corrupted
                if mode.getDarkness then mode:getDarkness():setTargets(0.0, 0.0) end
                if mode.getBlur then mode:getBlur():setTargets(0.0, 0.0) end
                if mode.getDesat then mode:getDesat():setTargets(0.0, 0.0) end
                if mode.getRadius then mode:getRadius():setTargets(50.0, 50.0) end
            end
            sm:setEnabled(pnum, false)
        end
        setBlackoutOverride(pnum, false)
        clearViewpointBlackout(pnum)
    end
end

---------------------------------------------------------------------------
-- Collapse pose
--
-- setAsleep() only flips a stat: B42's animation state machine has no "asleep"
-- node outside a bed, so a passed-out character keeps the standing idle and
-- simply stands there with their eyes open.
--
-- What we drop them into instead is the sit-on-ground state
-- (EventSitOnGround -> sitonground -> sitonground-sitting). It is a stable
-- looping state that vanilla itself falls back to when you ask to rest and no
-- seat is reachable, it leaves the character's position untouched, and it has a
-- proper get-up animation on the way out. Because isAsleep() is one of the
-- booleans every PlayerPacket carries, each modded client can reproduce the
-- pose on its own copy of a sleeping player, so the collapse reads as a
-- collapse in multiplayer too.
--
-- The bed sleep pose (Bob_Asleep, selected by the OnBedAnim variable) is
-- deliberately not used: its root bone is authored at mattress height - 0.41
-- against 0.08 for the floor-lying poses, on a 0.51 standing hip - so on bare
-- ground the character would visibly float half a bed above the floor.
---------------------------------------------------------------------------

-- How many ticks between multiplayer sweeps. ~6 checks a second at 60fps.
local REMOTE_CHECK_TICKS = 10

local function collapsePoseEnabled()
    local sv = SandboxVars.PassOut
    if sv == nil or sv.collapsePose == nil then return true end
    return sv.collapsePose
end

-- The transition into sitonground only exists out of the idle action state, so
-- only fire the event when the character is idle and still upright.
local function canDropToGround(chr)
    if chr:getVehicle() then return false end
    if chr:isSitOnGround() or chr:isSittingOnFurniture() or chr:isOnBed() then return false end
    return chr:getCurrentActionContextStateName() == "idle"
end

local function dropToGround(chr, isLocal)
    if isLocal then chr:setAutoWalk(false) end
    chr:reportEvent("EventSitOnGround")
end

-- Mirrors vanilla's own sit-on-ground key handler. The action queue is only
-- worth clearing on a character this client actually drives.
local function standUpFromGround(chr, isLocal)
    if isLocal then chr:StopAllActionQueue() end
    chr:setVariable("forceGetUp", true)
end

-- Keep a passed-out local player slumped, and put them back on their feet once
-- they wake. Re-fires if something knocks them out of the pose (a hit reaction
-- from a zombie, say) while they are still under, so it is self-healing.
local function updateCollapsePose(playerObj, md)
    if not md.poCollapsePose then return end
    if playerObj:isAsleep() then
        if canDropToGround(playerObj) then dropToGround(playerObj, true) end
    else
        md.poCollapsePose = nil
        if playerObj:isSitOnGround() then standUpFromGround(playerObj, true) end
    end
end

-- Multiplayer: mirror the pose onto this client's copies of remote sleepers.
-- Purely visual - no packets are sent and nothing here moves anyone, so it
-- cannot desync. Other clients need the mod to see it.
local remoteSlumped = {}
local remoteTick = 0

local function updateRemoteSleepers()
    if not isClient() then return end
    if not modEnabled() or not collapsePoseEnabled() then return end

    remoteTick = remoteTick + 1
    if remoteTick < REMOTE_CHECK_TICKS then return end
    remoteTick = 0

    local players = getOnlinePlayers()
    if not players then return end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and not p:isDead() and not p:isLocalPlayer() then
            local id = p:getOnlineID()
            if p:isAsleep() then
                if canDropToGround(p) then
                    dropToGround(p, false)
                    remoteSlumped[id] = true
                end
            elseif remoteSlumped[id] then
                remoteSlumped[id] = nil
                if p:isSitOnGround() then standUpFromGround(p, false) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Forced sleep
--
-- A trimmed copy of ISWorldObjectContextMenu.onSleepWalkToComplete that omits
-- the refusal guards but keeps the real sleep mechanics and the SP/MP split,
-- so the character always goes under - on the floor, wherever they stand.
---------------------------------------------------------------------------

-- Sleep-quality sandbox enum (1-4) mapped to the engine's bed-quality strings.
-- The engine recovers fatigue based on this, so it directly tunes how restful a
-- collapse is - from barely resting on bare ground to a full night's sleep.
local PASSOUT_BED_TYPES = { "floor", "badBed", "averageBed", "goodBed" }

-- True when the player is at the wheel and the sandbox forbids dropping there,
-- so the collapse should be held off until they stop driving.
local function drivingBlocksCollapse(playerObj, sv)
    if sv.passOutWhileDriving == false then
        local veh = playerObj:getVehicle()
        if veh and veh:isDriver(playerObj) then return true end
    end
    return false
end

-- Lean on the horn (or release it). Mirrors ISVehicleMenu.onHornStart/Stop so it
-- works the same in single-player and multiplayer.
local function setHorn(playerObj, on)
    local veh = playerObj:getVehicle()
    if not veh then return end
    if on and veh:getBatteryCharge() <= 0.0 then return end
    if isClient() then
        sendClientCommand(playerObj, "vehicle", "onHorn", { state = on and "start" or "stop" })
    elseif on then
        veh:onHornStart()
    else
        veh:onHornStop()
    end
end

local function stopHonkingIfDone(playerObj, md)
    if not md.poHonking then return end
    local veh = playerObj:getVehicle()
    if playerObj:isDead() or not playerObj:isAsleep() or not veh or not veh:isDriver(playerObj)
       or veh:getBatteryCharge() <= 0.0 then
        setHorn(playerObj, false)
        md.poHonking = nil
    end
end

local function forceSleep(playerObj, md, sv)
    local pnum = playerObj:getPlayerNum()

    -- Cleanly end any exercise state first, mirroring vanilla onConfirmSleep, so
    -- the engine doesn't carry unfinished exercise fatigue across the sleep.
    playerObj:setVariable("ExerciseStarted", false)
    playerObj:setVariable("ExerciseEnded", true)

    ISTimedActionQueue.clear(playerObj)

    -- Slump to the ground where they stand. Skipped in a vehicle, where the
    -- driver already slumps over the wheel (see below). If the character is
    -- still finishing an action this frame the per-frame pass picks it up.
    if collapsePoseEnabled() and not playerObj:getVehicle() then
        md.poCollapsePose = true
        if canDropToGround(playerObj) then dropToGround(playerObj, true) end
    end

    local bedType = nil
    if sv.passOutSleepQuality and sv.passOutSleepQuality > 1 then
        bedType = PASSOUT_BED_TYPES[sv.passOutSleepQuality]
    elseif ISWorldObjectContextMenu and ISWorldObjectContextMenu.getBedQuality then
        bedType = ISWorldObjectContextMenu.getBedQuality(playerObj, nil)
    end
    if not bedType then bedType = "floor" end

    local fatigue = playerObj:getStats():get(CharacterStat.FATIGUE)
    local sleepFor = ZombRand(fatigue * 10, fatigue * 13) + 1
    if     bedType == "goodBed" or (bedType.contains and bedType:contains("goodBedPillow")) then sleepFor = sleepFor - 1
    elseif bedType == "badBed"  or (bedType.contains and bedType:contains("badBedPillow"))  then sleepFor = sleepFor + 1
    elseif bedType == "floor"   or (bedType.contains and bedType:contains("floorPillow"))   then sleepFor = sleepFor * 0.7 end
    if playerObj:hasTrait(CharacterTrait.INSOMNIAC)       then sleepFor = sleepFor * 0.5  end
    if playerObj:hasTrait(CharacterTrait.NEEDS_LESS_SLEEP) then sleepFor = sleepFor * 0.75 end
    if playerObj:hasTrait(CharacterTrait.NEEDS_MORE_SLEEP) then sleepFor = sleepFor * 1.18 end
    if sleepFor > 16 then sleepFor = 16 end
    if sleepFor < 3  then sleepFor = 3  end

    local sleepHours = sleepFor + GameTime.getInstance():getTimeOfDay()
    if sleepHours >= 24 then sleepHours = sleepHours - 24 end

    playerObj:setBed(nil)
    playerObj:setBedType(bedType)
    playerObj:setForceWakeUpTime(tonumber(sleepHours))
    playerObj:setAsleepTime(0.0)
    playerObj:setAsleep(true)

    -- Hold them under for a configurable number of REAL seconds wherever input
    -- can wake a sleeper (multiplayer, split-screen). Without this a movement
    -- key still held from walking wakes them on the very next frame, so the
    -- collapse never visibly happens and the countdown just starts over. In
    -- solo single-player the game time-accelerates through sleep and input
    -- cannot wake you anyway. See onPlayerUpdate.
    if wakesOnInput() then
        local holdSecs = math.max(sv.forcedSleepSeconds or 0, MIN_HOLD_SECONDS)
        md.poForcedWakeAtMs = getTimestampMs() + holdSecs * 1000
        md.poWakeHour = sleepHours
        holdMovement(playerObj, md, true)
    end

    -- Slumping at the wheel: lean on the horn (drawing every zombie around) and
    -- let the car coast/careen - you're not braking. Stops on wake (see below).
    local veh = playerObj:getVehicle()
    if veh and veh:isDriver(playerObj) then
        playerObj:playSound("VehicleGoToSleep")
        if veh:hasHorn() then
            setHorn(playerObj, true)
            md.poHonking = true
        end
    end

    if isClient() and getServerOptions():getBoolean("SleepAllowed") then
        UIManager.setFadeBeforeUI(pnum, true)
        UIManager.FadeOut(pnum, 1)
        if veh then
            sendClientCommand(playerObj, "player", "onVehicleSleep",
                { id = playerObj:getOnlineID(), isAsleep = true })
        end
        return
    end

    getSleepingEvent():setPlayerFallAsleep(playerObj, math.floor(sleepFor + 0.5))
    UIManager.setFadeBeforeUI(pnum, true)
    UIManager.FadeOut(pnum, 1)
    if IsoPlayer.allPlayersAsleep() then
        UIManager.getSpeedControls():SetCurrentGameSpeed(3)
        save(true)
    end
end

---------------------------------------------------------------------------
-- Per-frame: hold a forced-out player down until the lockout expires
---------------------------------------------------------------------------

local function onPlayerUpdate(playerObj)
    if not playerObj or not playerObj:isLocalPlayer() then return end
    local md = playerObj:getModData()

    local untilMs = md.poForcedWakeAtMs
    if untilMs then
        if getTimestampMs() < untilMs and not playerObj:isDead() then
            -- Re-asserted every frame: the block flag isn't saved with the
            -- character, so a reload mid-hold would otherwise drop it.
            holdMovement(playerObj, md, true)
            -- Something still woke them (the aim key, a hit) - put them back
            -- under, with the wake-up time vanilla's wakeUp() just cleared.
            if not playerObj:isAsleep() then
                local pnum = playerObj:getPlayerNum()
                playerObj:setForceWakeUpTime(md.poWakeHour or -1)
                playerObj:setAsleep(true)
                UIManager.setFadeBeforeUI(pnum, true)
                UIManager.FadeOut(pnum, 1)
            end
        else
            -- Hold over; natural wake allowed.
            md.poForcedWakeAtMs = nil
            md.poWakeHour = nil
            holdMovement(playerObj, md, false)
        end
    elseif md.poBlockedMovement then
        holdMovement(playerObj, md, false)
    end

    -- Cut the slumped-on-horn blare once the driver wakes / dies / leaves.
    stopHonkingIfDone(playerObj, md)

    -- Hold the collapse pose while under, stand back up on waking.
    updateCollapsePose(playerObj, md)
end

---------------------------------------------------------------------------
-- Phase 2: gradually blacking out (advanced once per in-game minute)
---------------------------------------------------------------------------

local function advancePassingOut(playerObj, md, sv)
    -- Bail out if the player has already fallen asleep some other way.
    if playerObj:isAsleep() then
        clearState(playerObj, md)
        return
    end

    -- Got behind the wheel mid-blackout and driving collapses are off: cancel
    -- the blackout so they aren't driving blind. The countdown re-arms once
    -- they stop driving.
    if drivingBlocksCollapse(playerObj, sv) then
        clearState(playerObj, md)
        return
    end

    md.poPassOutFactor = (md.poPassOutFactor or 0) + (md.poStepFactor or 0.2)
    local f = md.poPassOutFactor
    local pnum = playerObj:getPlayerNum()

    -- Drive the foraging search-mode post-process as the vignette.
    setBlackoutOverride(pnum, true)
    local mode = getSearchMode():getSearchModeForPlayer(pnum)
    getSearchMode():setEnabled(pnum, true)
    mode:getBlur():setTargets(f, f)
    mode:getDesat():setTargets(f, f)
    mode:getRadius():setTargets(5 / f, 5 / f)
    mode:getDarkness():setTargets(f / 1.2, f / 1.2)
    setViewpointBlackout(pnum, f)

    if f >= 1.0 then
        -- Optionally, panic keeps you on your feet a little longer. Each save
        -- shaves 10 points off panic so it eventually gives way.
        local panicKeepsAwake = sv.panicKeepsAwake
        if panicKeepsAwake == nil then panicKeepsAwake = true end
        if panicKeepsAwake and playerObj:getMoodles():getMoodleLevel(MoodleType.PANIC) >= 1 then
            playerObj:Say(getText("IGUI_PanicSave"))
            local stats = playerObj:getStats()
            local drain = 10
            if hasTrait(playerObj, "ProneToPassing") then
                drain = 20
            elseif hasTrait(playerObj, "ResistantToPassing") then
                drain = 5
            end
            stats:set(CharacterStat.PANIC, math.max(0, stats:get(CharacterStat.PANIC) - drain))
            -- Stay blacked-out-but-awake; panic drains each minute until you drop.
            return
        end

        -- Collapse - forced, so nearby zombies / pain / the ExerciseEnded var
        -- can't silently cancel it.
        clearState(playerObj, md)
        forceSleep(playerObj, md, sv)
    end
end

---------------------------------------------------------------------------
-- Phase 1: watching for sustained maximum tiredness
---------------------------------------------------------------------------

local function watch(playerObj, md, sv)
    local tiredLevel = sv.tiredLevel or 4

    if playerObj:getMoodles():getMoodleLevel(MoodleType.TIRED) >= tiredLevel
       and not playerObj:isAsleep() then

        -- First minute at the threshold: stamp the clock and roll randomness.
        if md.poTiredTime == nil or md.poRandomnessValue == nil then
            md.poTiredTime = getGametimeTimestamp()
            local r = sv.passOutRandomness or 0.2
            md.poRandomnessValue = ZombRand(-r * 10, r * 10 + 1) / 10
            md.poWarned = nil
        end

        local secondsSinceTired = getGametimeTimestamp() - md.poTiredTime
        local passOutHours = sv.passOutHours or 6
        local passOutSeconds = passOutHours * 3600 + md.poRandomnessValue * 3600

        if hasTrait(playerObj, "ProneToPassing") then
            passOutSeconds = passOutSeconds * 0.8
        elseif hasTrait(playerObj, "ResistantToPassing") then
            passOutSeconds = passOutSeconds * 1.2
        end

        if secondsSinceTired > passOutSeconds and not drivingBlocksCollapse(playerObj, sv) then
            -- Begin blacking out.
            playerObj:Say(getText("IGUI_PassOut"))
            md.poTiredTime = nil
            md.poRandomnessValue = nil
            md.poWarned = nil
            md.poPhase = PHASE_PASSING
            md.poPassOutFactor = 0.0

            local passingOutTime = sv.passingOutTime or 5
            if hasTrait(playerObj, "ProneToPassing") then
                passingOutTime = math.max(1, passingOutTime * 0.5)
            elseif hasTrait(playerObj, "ResistantToPassing") then
                passingOutTime = passingOutTime * 1.5
            end
            md.poStepFactor = 1.0 / passingOutTime
        elseif sv.warnPassOut and not md.poWarned
               and (secondsSinceTired + WARN_LEAD_SECONDS > passOutSeconds) then
            -- One private heads-up shortly before the collapse.
            md.poWarned = true
            HaloTextHelper.addBadText(playerObj, getText("IGUI_PassOut_Warning"))
        end
    else
        -- No longer maxed out / asleep: reset the countdown.
        if md.poTiredTime ~= nil or md.poRandomnessValue ~= nil or md.poWarned ~= nil then
            md.poTiredTime = nil
            md.poRandomnessValue = nil
            md.poWarned = nil
        end
    end
end

---------------------------------------------------------------------------
-- Main tick
---------------------------------------------------------------------------

local function passOutTick()
    if not modEnabled() then return end
    if not sleepAllowed() then return end

    local sv = SandboxVars.PassOut
    forEachLocalPlayer(function(playerObj)
        local md = playerObj:getModData()
        if md.poPhase == PHASE_PASSING then
            advancePassingOut(playerObj, md, sv)
        else
            watch(playerObj, md, sv)
        end
    end)
end

Events.EveryOneMinute.Add(passOutTick)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnTick.Add(updateRemoteSleepers)
