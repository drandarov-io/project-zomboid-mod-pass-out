---------------------------------------------------------------------------
-- Pass Out - Build 41 (backport, kept in lockstep with the Build 42 version)
--
-- Forces the character to fall asleep on the spot after staying at maximum
-- tiredness for a configurable number of in-game hours, with a gradual
-- "blacking out" post-process as you go under.
--
-- Client-side. Works in single-player, on multiplayer clients (only when the
-- server needs sleep) and in split-screen, where every local player is tracked
-- independently via their own ModData state machine.
---------------------------------------------------------------------------

local PHASE_PASSING = "passing"
local WARN_LEAD_SECONDS = 600 -- 10 in-game minutes

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function modEnabled()
    local sv = SandboxVars.PassOut
    if sv == nil or sv.enableMod == nil then return true end
    return sv.enableMod
end

-- Single-player / host: always. Multiplayer client: only when sleep is needed.
local function sleepAllowed()
    if not isClient() then return true end
    return getServerOptions():getBoolean("SleepNeeded")
end

local function hasTrait(playerObj, name)
    if not playerObj then return false end
    if playerObj.HasTrait then
        local ok, has = pcall(function() return playerObj:HasTrait(name) end)
        if ok and has then return true end
    end
    return false
end

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

local function clearState(playerObj, md)
    md.poTiredTime = nil
    md.poRandomnessValue = nil
    md.poWarned = nil
    if md.poPhase ~= nil then
        md.poPhase = nil
        md.poPassOutFactor = nil
        md.poStepFactor = nil
        getSearchMode():setEnabled(playerObj:getPlayerNum(), false)
    end
end

-- Sleep-quality sandbox enum (1-4) mapped to the engine's bed-quality strings.
local PASSOUT_BED_TYPES = { "floor", "badBed", "averageBed", "goodBed" }

-- True when the player is at the wheel and the sandbox forbids dropping there.
local function drivingBlocksCollapse(playerObj, sv)
    if sv.passOutWhileDriving == false then
        local veh = playerObj:getVehicle()
        if veh and veh:isDriver(playerObj) then return true end
    end
    return false
end

-- Lean on the horn (or release it). Mirrors ISVehicleMenu.onHornStart/Stop.
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
    if playerObj:isDead() or not playerObj:isAsleep() or not veh or not veh:isDriver(playerObj) then
        setHorn(playerObj, false)
        md.poHonking = nil
    end
end

-- Collapse, then optionally lock out an instant wake-by-moving for a number of
-- real seconds (multiplayer only). B41's onSleepWalkToComplete works as the
-- original mod relied on it, so we reuse it for the sleep itself, then override
-- the bed quality so sandbox-controlled recovery applies.
local function forceSleep(playerObj, md, sv)
    playerObj:setVariable("ExerciseStarted", false)
    playerObj:setVariable("ExerciseEnded", true)

    ISWorldObjectContextMenu.onSleepWalkToComplete(playerObj:getPlayerNum(), nil)

    -- Override the "floor" quality the call set with the sandbox choice so the
    -- engine recovers fatigue accordingly.
    local bedType = PASSOUT_BED_TYPES[sv.passOutSleepQuality or 1] or "floor"
    playerObj:setBedType(bedType)

    -- Slumping at the wheel: lean on the horn and let the car roll on.
    local veh = playerObj:getVehicle()
    if veh and veh:isDriver(playerObj) and veh:hasHorn() then
        setHorn(playerObj, true)
        md.poHonking = true
    end

    local forcedSecs = sv.forcedSleepSeconds or 0
    if isClient() and forcedSecs > 0 then
        md.poForcedWakeAtMs = getTimestampMs() + forcedSecs * 1000
    end
end

local function onPlayerUpdate(playerObj)
    if not playerObj or not playerObj:isLocalPlayer() then return end
    local md = playerObj:getModData()

    local untilMs = md.poForcedWakeAtMs
    if untilMs then
        if getTimestampMs() < untilMs then
            if not playerObj:isAsleep() then
                local pnum = playerObj:getPlayerNum()
                playerObj:setAsleep(true)
                UIManager.setFadeBeforeUI(pnum, true)
                UIManager.FadeOut(pnum, 1)
            end
        else
            md.poForcedWakeAtMs = nil
        end
    end

    stopHonkingIfDone(playerObj, md)
end

---------------------------------------------------------------------------
-- Phase 2: gradually blacking out
---------------------------------------------------------------------------

local function advancePassingOut(playerObj, md, sv)
    if playerObj:isAsleep() then
        clearState(playerObj, md)
        return
    end

    -- Driving collapses off + at the wheel: cancel the blackout, re-arm on stop.
    if drivingBlocksCollapse(playerObj, sv) then
        clearState(playerObj, md)
        return
    end

    md.poPassOutFactor = (md.poPassOutFactor or 0) + (md.poStepFactor or 0.2)
    local f = md.poPassOutFactor
    local pnum = playerObj:getPlayerNum()

    local mode = getSearchMode():getSearchModeForPlayer(pnum)
    getSearchMode():setEnabled(pnum, true)
    mode:getBlur():setTargets(f, f)
    mode:getDesat():setTargets(f, f)
    mode:getRadius():setTargets(5 / f, 5 / f)
    mode:getDarkness():setTargets(f / 1.2, f / 1.2)

    if f >= 1.0 then
        local panicKeepsAwake = sv.panicKeepsAwake
        if panicKeepsAwake == nil then panicKeepsAwake = true end
        if panicKeepsAwake then
            local moodles = playerObj:getMoodles()
            if moodles and moodles:getMoodleLevel(MoodleType.Panic) >= 1 then
                playerObj:Say(getText("IGUI_PanicSave"))
                local stats = playerObj:getStats()
                local drain = 10
                if hasTrait(playerObj, "ProneToPassing") then
                    drain = 20
                elseif hasTrait(playerObj, "ResistantToPassing") then
                    drain = 5
                end
                stats:setPanic(math.max(0, stats:getPanic() - drain))
                return
            end
        end

        clearState(playerObj, md)
        forceSleep(playerObj, md, sv)
    end
end

---------------------------------------------------------------------------
-- Phase 1: watching for sustained maximum tiredness
---------------------------------------------------------------------------

local function watch(playerObj, md, sv)
    local tiredLevel = sv.tiredLevel or 4
    local moodles = playerObj:getMoodles()
    if not moodles then return end

    if moodles:getMoodleLevel(MoodleType.Tired) >= tiredLevel
       and not playerObj:isAsleep() then

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
            md.poWarned = true
            HaloTextHelper.addBadText(playerObj, getText("IGUI_PassOut_Warning"))
        end
    else
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
    if sv == nil then return end
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
