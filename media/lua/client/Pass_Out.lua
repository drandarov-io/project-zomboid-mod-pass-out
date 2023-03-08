function passingOutRoutine()
    local playerObj = getPlayer()
    local modData = playerObj:getModData()

    modData.poPassOutFactor = modData.poPassOutFactor + modData.poStepFactor
    local passOutFactor = modData.poPassOutFactor

    --print("poFactor: " .. passOutFactor)

    local mode = getSearchMode():getSearchModeForPlayer(playerObj:getPlayerNum())
    getSearchMode():setEnabled(playerObj:getPlayerNum(),true)
    mode:getBlur():setTargets(passOutFactor, passOutFactor)
    mode:getDesat():setTargets(passOutFactor, passOutFactor)
    mode:getRadius():setTargets(5 / passOutFactor,  5 / passOutFactor)
    mode:getDarkness():setTargets(passOutFactor / 1.2, passOutFactor / 1.2)

    if modData.poPassOutFactor >= 1.0 then
        -- Reset passing out when player is panicked, but reduce panic by 10 percentage points
        if playerObj:getMoodles():getMoodleLevel(MoodleType.Panic) >= 1 then
            playerObj:Say(getText("IGUI_PanicSave"))

            local panic = playerObj:getStats():getPanic()
            local amountToDecrease = 10
            if playerObj:HasTrait("ProneToPassing") then
               amountToDecrease = 20
            end
            if playerObj:HasTrait("ResistantToPassing") then
               amountToDecrease = 5 
            end
            playerObj:getStats():setPanic(panic - amountToDecrease)
            return
        end

        Events.EveryOneMinute.Remove(passingOutRoutine)
        Events.EveryTenMinutes.Add(passOutRoutine)

        -- Sleep
        ISWorldObjectContextMenu.onSleepWalkToComplete(playerObj:getPlayerNum(), nil)
        getSearchMode():setEnabled(playerObj:getPlayerNum(),false)
    end
end

function passOutRoutine()
    local playerObj = getPlayer()
    local modData = playerObj:getModData()

    -- Check whether player is awake with max tiredness level
    if playerObj:getMoodles():getMoodleLevel(MoodleType.Tired) >= 4 and not (playerObj:isAsleep()) then

        local sandboxPassOut = SandboxVars.PassOut

        -- Check whether subroutine has been initialized yet
        if modData.poTiredTime == nil or modData.poRandomnessValue == nil then
            modData.poTiredTime = getGametimeTimestamp()
            modData.poRandomnessValue = ZombRand(-sandboxPassOut.passOutRandomness * 10, sandboxPassOut.passOutRandomness * 10 + 1) / 10
        end

        -- Calculate the time since the Tired Moodle is at level 4
        local secondsSinceTired = getGametimeTimestamp() - modData.poTiredTime
        -- getGametimeTimestamp() returns the current time in seconds (600 = 10 min, 3600 = 1 hour)
        local passOutSeconds = sandboxPassOut.passOutHours * 3600 + modData.poRandomnessValue * 3600
        if playerObj:HasTrait("ProneToPassing") then
           passOutSeconds = passOutSeconds * 0.8
        end
        if playerObj:HasTrait("ResistantToPassing") then
           passOutSeconds = passOutSeconds * 1.2 
        end

        --print("timestamp: " .. getGametimeTimestamp())
        --print("poTiredTime " .. modData.poTiredTime)
        --print("secondsSinceTired: " .. secondsSinceTired)
        --print("modData.poRandomnessValue: " .. modData.poRandomnessValue)
        --print("passOutSeconds: " .. passOutSeconds)

        -- Check whether player will start passing out
        if secondsSinceTired > passOutSeconds then
            playerObj:Say(getText("IGUI_PassOut"))
            local PassingOutTime = sandboxPassOut.passingOutTime
            if playerObj:HasTrait("ProneToPassing") then
               PassingOutTime = PassingOutTime * 0.5 
            end
            if playerObj:HasTrait("ResistantToPassing") then
               PassingOutTime = PassingOutTime * 4 
            end
            modData.poTiredTime = nil
            modData.poPassOutFactor = 0.0
            modData.poStepFactor = 1.0 / PassingOutTime

            -- Switch routine
            Events.EveryTenMinutes.Remove(passOutRoutine)
            Events.EveryOneMinute.Add(passingOutRoutine)

        -- Else warn if enabled and player would pass out during the next check
        else
            if sandboxPassOut.warnPassOut and (secondsSinceTired + 600 > passOutSeconds) then
                playerObj:Say(getText("IGUI_PassOut_Warning"))
            end
        end
    else
        modData.poTiredTime = nil
    end
end

-- Check whether sleep is enabled
if not isClient() or getServerOptions():getBoolean("SleepNeeded") then
    Events.EveryTenMinutes.Add(passOutRoutine)
end
