-- Behaviour of the Build 42 client code, 42/media/lua/client/Pass_Out.lua.
-- tests/SPEC.md describes the same rules with diagrams; keep both in sync.
-- Run with ..\project-zomboid-mod-toolkit\run_tests.ps1 (or .\test.ps1).

local mocks = require("mocks")

local EXHAUSTED = 0.95 -- fatigue above 0.9 is TIRED moodle level 4
local LOWEST = function() return 0 end
local HIGHEST = function(n) return n - 1 end
local EFFECT_OFF = { enabled = false, override = false, blur = 0, desat = 0, radius = 50, darkness = 0 }

local w, p

local function fresh()
    w = mocks.world()
    p = w:addPlayer({ fatigue = EXHAUSTED })
end

before_each(fresh)

local function blackingOut() return p.modData.poPhase == "passing" end
local function asleep() return p.asleep end

-- Pass Out Hours 0 without randomness: the countdown starts on the first
-- minute and the blackout on the second.
local function startBlackout()
    w.vars.passOutHours, w.vars.passOutRandomness = 0, 0
    w:minute(2)
    assert(blackingOut(), "the blackout did not start")
end

-- Minutes from the start of the blackout to the collapse.
local function blackoutMinutes() return w:minutesUntil(asleep, 200) end

local function collapse()
    startBlackout()
    assert(blackoutMinutes(), "the player never collapsed")
end

describe("loading", function()
    it("adds one handler each to EveryOneMinute, OnPlayerUpdate, OnTick and OnPlayerDeath", function()
        for _, name in ipairs({ "EveryOneMinute", "OnPlayerUpdate", "OnTick", "OnPlayerDeath" }) do
            expect.eq(#w.handlers[name], 1, name)
        end
    end)

    it("registers both trait types through registries.lua", function()
        expect.truthy(w:trait("passout:pronetopassing"))
        expect.truthy(w:trait("passout:resistanttopassing"))
    end)
end)

describe("gating", function()
    it("does nothing while Enable Pass Out is off", function()
        w.vars.enableMod = false
        w:minute(1000)
        expect.eq(p.modData, {})
    end)

    it("treats a missing Enable Pass Out as on", function()
        w.vars.enableMod = nil
        startBlackout()
    end)

    it("runs in single-player whatever the server sleep options say", function()
        w.server = { SleepAllowed = false, SleepNeeded = false }
        startBlackout()
    end)

    it("runs on a multiplayer client only when the server allows and needs sleep", function()
        for _, case in ipairs({ { true, true, true }, { true, false, false }, { false, true, false }, { false, false, false } }) do
            fresh()
            w.client = true
            w.server = { SleepAllowed = case[1], SleepNeeded = case[2] }
            w.vars.passOutHours, w.vars.passOutRandomness = 0, 0
            w:minute(2)
            expect.eq(blackingOut(), case[3], string.format("SleepAllowed=%s SleepNeeded=%s", case[1], case[2]))
        end
    end)
end)

describe("countdown", function()
    before_each(function() w.vars.passOutRandomness = 0 end)

    it("does not run below the Required Tiredness Level", function()
        p.stats.FATIGUE = 0.85 -- TIRED level 3
        w:minute(1000)
        expect.eq(p.modData, {})
    end)

    it("starts on the first minute at the Required Tiredness Level", function()
        w.vars.tiredLevel = 2
        p.stats.FATIGUE = 0.75 -- TIRED level 2
        w:minute()
        expect.eq(p.modData.poTiredTime, 60)
    end)

    it("starts the blackout on the first minute more than Pass Out Hours after it started", function()
        -- minute 1 starts the countdown; 360 minutes later is not "more than" 6 h yet
        expect.eq(w:minutesUntil(blackingOut), 1 + 360 + 1)
    end)

    it("starts the blackout one minute after reaching the level with Pass Out Hours 0", function()
        w.vars.passOutHours = 0
        expect.eq(w:minutesUntil(blackingOut), 2)
    end)

    it("is 0.8 times as long for Prone to Passing Out", function()
        w:giveTrait(p, "passout:pronetopassing")
        expect.eq(w:minutesUntil(blackingOut), 1 + 288 + 1)
    end)

    it("is 1.2 times as long for Resistant to Passing Out", function()
        w:giveTrait(p, "passout:resistanttopassing")
        expect.eq(w:minutesUntil(blackingOut), 1 + 432 + 1)
    end)

    it("starts over when tiredness drops below the level", function()
        w:minute(100)
        p.stats.FATIGUE = 0.85
        w:minute()
        expect.eq(p.modData, {})
        p.stats.FATIGUE = EXHAUSTED
        expect.eq(w:minutesUntil(blackingOut), 362)
    end)

    it("starts over while the player sleeps", function()
        w:minute(100)
        p.asleep = true
        w:minute()
        expect.eq(p.modData, {})
    end)

    it("says IGUI_PassOut and starts a blackout of Passing Out Minutes", function()
        startBlackout()
        expect.eq(p.said, { "IGUI_PassOut" })
        expect.eq(p.modData, { poPhase = "passing", poPassOutFactor = 0, poStepFactor = 1 / 5 })
    end)
end)

describe("randomness", function()
    local function countdownWith(randomness, pick, trait)
        fresh()
        w.vars.passOutRandomness, w.rand = randomness, pick
        if trait then w:giveTrait(p, trait) end
        return w:minutesUntil(blackingOut)
    end

    it("moves the blackout by up to Pass Out Randomness hours either way, in 0.1 h steps", function()
        expect.eq(countdownWith(1, LOWEST), 1 + 300 + 1, "6 h - 1 h")
        expect.eq(countdownWith(1, HIGHEST), 1 + 420 + 1, "6 h + 1 h")
        expect.eq(countdownWith(0.2, LOWEST), 1 + 348 + 1, "6 h - 0.2 h")
        expect.eq(countdownWith(0.2, HIGHEST), 1 + 372 + 1, "6 h + 0.2 h")
    end)

    it("rolls once per countdown", function()
        w.rand = LOWEST
        w:minute()
        w.rand = HIGHEST
        w:minute(10)
        expect.eq(p.modData.poRandomnessValue, -0.2)
    end)

    it("is applied before the trait factor", function()
        expect.eq(countdownWith(1, LOWEST, "passout:pronetopassing"), 1 + 240 + 1, "(6 h - 1 h) * 0.8")
    end)
end)

describe("warning", function()
    before_each(function() w.vars.passOutRandomness = 0 end)

    it("shows IGUI_PassOut_Warning once, 10 minutes before the blackout", function()
        local warnedAt = w:minutesUntil(function() return #w:called("addBadText") > 0 end)
        expect.eq(warnedAt, 352)
        expect.eq(warnedAt + w:minutesUntil(blackingOut), 362)
        expect.eq(w:called("addBadText"), { { p, "IGUI_PassOut_Warning" } })
    end)

    it("is not shown with Pass Out Warning off", function()
        w.vars.warnPassOut = false
        w:minutesUntil(blackingOut)
        expect.eq(w:called("addBadText"), {})
    end)
end)

describe("blackout", function()
    it("drives the foraging search-mode effect with the blackout factor", function()
        startBlackout()
        w:minute()
        local f = 1 / 5
        expect.eq(w:searchMode(0), { enabled = true, override = true, blur = f, desat = f, radius = 5 / f, darkness = f / 1.2 })
        expect.eq(w:called("triggerEvent")[1], { "OnOverrideSearchManager", true, 0 })
    end)

    it("lasts Passing Out Minutes, rounded up", function()
        for minutes = 1, 20 do
            fresh()
            w.vars.passingOutTime = minutes
            startBlackout()
            expect.eq(blackoutMinutes(), minutes, "Passing Out Minutes " .. minutes)
        end
    end)

    it("lasts half as long, at least 1 minute, for Prone to Passing Out", function()
        for minutes = 1, 20 do
            fresh()
            w:giveTrait(p, "passout:pronetopassing")
            w.vars.passingOutTime = minutes
            startBlackout()
            expect.eq(blackoutMinutes(), math.ceil(math.max(1, minutes * 0.5)), "Passing Out Minutes " .. minutes)
        end
    end)

    it("lasts 1.5 times as long for Resistant to Passing Out", function()
        for minutes = 1, 20 do
            fresh()
            w:giveTrait(p, "passout:resistanttopassing")
            w.vars.passingOutTime = minutes
            startBlackout()
            expect.eq(blackoutMinutes(), math.ceil(minutes * 1.5), "Passing Out Minutes " .. minutes)
        end
    end)

    it("is called off without a collapse when the player falls asleep another way", function()
        startBlackout()
        w:minute()
        p.asleep = true
        w:minute()
        expect.eq(p.modData, {})
        expect.eq(w:searchMode(0), EFFECT_OFF)
        expect.eq(w:called("setPlayerFallAsleep"), {})
    end)

    it("turns the effect off on collapse", function()
        collapse()
        expect.eq(w:searchMode(0), EFFECT_OFF)
        local calls = w:called("triggerEvent")
        expect.eq(calls[#calls], { "OnOverrideSearchManager", false, 0 })
    end)
end)

describe("panic", function()
    before_each(function() p.stats.PANIC = 25 end) -- PANIC moodle level 1 is above 6

    it("keeps the player awake while the PANIC moodle shows, draining 10 panic a minute", function()
        startBlackout()
        expect.eq(blackoutMinutes(), 5 + 2, "25 -> 15 -> 5")
        expect.eq(p.said, { "IGUI_PassOut", "IGUI_PanicSave", "IGUI_PanicSave" })
        expect.eq(p.stats.PANIC, 5)
    end)

    it("drains 20 a minute for Prone and 5 for Resistant to Passing Out", function()
        w:giveTrait(p, "passout:pronetopassing")
        startBlackout()
        expect.eq(blackoutMinutes(), 3 + 1, "25 -> 5")

        fresh()
        p.stats.PANIC = 25
        w:giveTrait(p, "passout:resistanttopassing")
        startBlackout()
        expect.eq(blackoutMinutes(), 8 + 4, "25 -> 20 -> 15 -> 10 -> 5")
    end)

    it("does not drain below 0", function()
        p.stats.PANIC = 8
        w:giveTrait(p, "passout:pronetopassing")
        collapse()
        expect.eq(p.stats.PANIC, 0)
    end)

    it("is ignored with Panic Keeps You Awake off", function()
        w.vars.panicKeepsAwake = false
        startBlackout()
        expect.eq(blackoutMinutes(), 5)
        expect.eq(p.stats.PANIC, 25)
    end)

    it("treats a missing Panic Keeps You Awake as on", function()
        w.vars.panicKeepsAwake = nil
        startBlackout()
        expect.eq(blackoutMinutes(), 7)
    end)
end)

describe("collapse", function()
    it("puts the player to sleep on the floor where they stand", function()
        collapse()
        expect.truthy(p.asleep)
        expect.eq(p.bedType, "floor")
        expect.eq(p.asleepTime, 0)
        expect.eq(p.vars.ExerciseStarted, false)
        expect.eq(p.vars.ExerciseEnded, true)
        expect.eq(w:called("clearActionQueue"), { { p } })
    end)

    it("sleeps ZombRand(fatigue * 10, fatigue * 13) + 1 hours, times 0.7 on the floor", function()
        collapse()
        expect.eq(w:called("setPlayerFallAsleep"), { { p, 7 } }, "(9 + 1) * 0.7")
        expect.near(p.wakeHour, 12 + 7)

        fresh()
        w.rand = HIGHEST
        collapse()
        expect.eq(w:called("setPlayerFallAsleep"), { { p, 8 } }, "(11 + 1) * 0.7 = 8.4")
        expect.near(p.wakeHour, 12 + 8.4)
    end)

    it("maps Pass-Out Sleep Quality 2-4 to badBed (+1 h), averageBed and goodBed (-1 h)", function()
        for quality, case in pairs({ [2] = { "badBed", 11 }, [3] = { "averageBed", 10 }, [4] = { "goodBed", 9 } }) do
            fresh()
            w.vars.passOutSleepQuality = quality
            collapse()
            expect.eq(p.bedType, case[1])
            expect.eq(w:called("setPlayerFallAsleep"), { { p, case[2] } }, case[1])
        end
    end)

    it("rates the player's own spot with Pass-Out Sleep Quality 1", function()
        for bedType, hours in pairs({ floorPillow = 7, badBed = 11 }) do
            fresh()
            w.bedQuality = bedType
            collapse()
            expect.eq(p.bedType, bedType)
            expect.eq(w:called("setPlayerFallAsleep"), { { p, hours } }, bedType)
        end
    end)

    it("applies Insomniac 0.5, Needs Less Sleep 0.75 and Needs More Sleep 1.18", function()
        for trait, hours in pairs({ INSOMNIAC = 3.5, NEEDS_LESS_SLEEP = 5.25, NEEDS_MORE_SLEEP = 7 * 1.18 }) do
            fresh()
            w:giveTrait(p, trait)
            collapse()
            expect.eq(w:called("setPlayerFallAsleep"), { { p, math.floor(hours + 0.5) } }, trait)
            expect.near(p.wakeHour, 12 + hours, 1e-9, trait)
        end
    end)

    it("sleeps at least 3 and at most 16 hours", function()
        startBlackout()
        p.stats.FATIGUE = 0.2
        blackoutMinutes()
        expect.eq(w:called("setPlayerFallAsleep"), { { p, 3 } }, "(2 + 1) * 0.7 = 2.1")

        fresh()
        p.stats.FATIGUE = 1
        w.rand = HIGHEST
        w.vars.passOutSleepQuality = 2
        w:giveTrait(p, "NEEDS_MORE_SLEEP")
        collapse()
        expect.eq(w:called("setPlayerFallAsleep"), { { p, 16 } }, "(12 + 1 + 1) * 1.18 = 16.52")
    end)

    it("wraps the wake-up hour past midnight", function()
        w.timeOfDay = 22
        collapse()
        expect.near(p.wakeHour, 22 + 7 - 24)
    end)

    it("fades out and, once every player is asleep, speeds up time and saves", function()
        collapse()
        expect.eq(w:called("setFadeBeforeUI"), { { 0, true } })
        expect.eq(w:called("FadeOut"), { { 0, 1 } })
        expect.eq(w:called("SetCurrentGameSpeed"), { { 3 } })
        expect.eq(w:called("save"), { { true } })
    end)

    it("does not hold a solo single-player character down", function()
        collapse()
        expect.falsy(p.modData.poForcedWakeAtMs)
        expect.falsy(p.blockMovement)
    end)
end)

describe("collapse pose", function()
    it("sits the player on the ground and stands them up on waking", function()
        collapse()
        expect.eq(p.events, { "EventSitOnGround" })
        expect.truthy(p.sitting)
        p.asleep = false
        w:frame()
        expect.eq(p.vars.forceGetUp, true)
        expect.falsy(p.sitting)
        expect.eq(p.actionQueueStops, 1)
        expect.falsy(p.modData.poCollapsePose)
    end)

    it("drops the player again if something stands them up while asleep", function()
        collapse()
        p.sitting = false
        w:frame()
        expect.eq(p.events, { "EventSitOnGround", "EventSitOnGround" })
    end)

    it("waits until the player is idle", function()
        p.action = "walk"
        collapse()
        expect.eq(p.events, {})
        p.action = "idle"
        w:frame()
        expect.eq(p.events, { "EventSitOnGround" })
    end)

    it("is skipped with Collapse Animation off", function()
        w.vars.collapsePose = false
        collapse()
        w:frame()
        expect.eq(p.events, {})
    end)

    it("is skipped in a vehicle", function()
        w:drive(p, nil, true)
        collapse()
        w:frame()
        expect.eq(p.events, {})
    end)
end)

describe("hold where input can wake a sleeper", function()
    it("blocks movement for Forced Pass-Out Duration real seconds in split-screen", function()
        w:addPlayer()
        collapse()
        expect.eq(p.modData.poForcedWakeAtMs, 30 * 1000)
        expect.near(p.modData.poWakeHour, 12 + 7)
        expect.truthy(p.blockMovement)
    end)

    it("holds for at least 3 seconds with Forced Pass-Out Duration 0", function()
        w:addPlayer()
        w.vars.forcedSleepSeconds = 0
        collapse()
        expect.eq(p.modData.poForcedWakeAtMs, 3 * 1000)
    end)

    it("puts a player woken during the hold back to sleep", function()
        w:addPlayer()
        collapse()
        p.asleep, p.wakeHour = false, -1
        w:frame()
        expect.truthy(p.asleep)
        expect.near(p.wakeHour, 12 + 7)
        expect.eq(#w:called("FadeOut"), 2)
    end)

    it("lets go once the hold is over", function()
        w:addPlayer()
        collapse()
        w:frame(29 * 1000)
        expect.truthy(p.blockMovement)
        w:frame(1000)
        expect.falsy(p.blockMovement)
        expect.falsy(p.modData.poForcedWakeAtMs)
        p.asleep = false
        w:frame()
        expect.falsy(p.asleep)
    end)

    it("leaves the sleep itself to the server on a multiplayer client", function()
        w.client = true
        collapse()
        expect.eq(w:called("setPlayerFallAsleep"), {})
        expect.eq(w:called("FadeOut"), { { 0, 1 } })
        expect.eq(p.modData.poForcedWakeAtMs, 30 * 1000)
    end)

    it("tells the server when a multiplayer client collapses in a vehicle", function()
        w.client = true
        w:drive(p, nil, true)
        collapse()
        expect.eq(w:called("sendClientCommand"), { { p, "player", "onVehicleSleep", { id = 0, isAsleep = true } } })
    end)
end)

describe("driving", function()
    it("slumps onto the horn at the wheel and lets go on waking", function()
        local car = w:drive(p)
        collapse()
        expect.eq(p.sounds, { "VehicleGoToSleep" })
        expect.truthy(car.honking)
        p.asleep = false
        w:frame()
        expect.falsy(car.honking)
        expect.falsy(p.modData.poHonking)
    end)

    it("does not honk with a flat battery", function()
        local car = w:drive(p, { battery = 0 })
        collapse()
        expect.falsy(car.honking)
    end)

    it("honks through the server on a multiplayer client", function()
        w.client = true
        w:drive(p)
        collapse()
        expect.eq(w:called("sendClientCommand")[1], { p, "vehicle", "onHorn", { state = "start" } })
    end)

    it("stays off the horn with Honk When Passing Out at the Wheel off", function()
        w.vars.hornWhilePassedOut = false
        local car = w:drive(p)
        collapse()
        expect.eq(p.sounds, { "VehicleGoToSleep" })
        expect.falsy(car.honking)
        expect.falsy(p.modData.poHonking)
    end)

    it("treats a missing Honk When Passing Out at the Wheel as on", function()
        w.vars.hornWhilePassedOut = nil
        local car = w:drive(p)
        collapse()
        expect.truthy(car.honking)
    end)

    describe("with Pass Out While Driving off", function()
        before_each(function()
            w.vars.passOutWhileDriving = false
            w.vars.passOutHours, w.vars.passOutRandomness = 0, 0
        end)

        it("holds the blackout off while the player drives and starts it once they stop", function()
            w:drive(p)
            w:minute(100)
            expect.falsy(blackingOut())
            p.vehicle = nil
            w:minute()
            expect.truthy(blackingOut())
        end)

        it("still lets a passenger pass out", function()
            w:drive(p, nil, true)
            w:minute(2)
            expect.truthy(blackingOut())
        end)

        it("calls off a blackout when the player starts driving", function()
            startBlackout()
            w:minute()
            w:drive(p)
            w:minute()
            expect.falsy(blackingOut())
            expect.eq(w:searchMode(0), EFFECT_OFF)
        end)
    end)
end)

describe("split-screen", function()
    it("tracks each local player separately", function()
        local other = w:addPlayer({ fatigue = 0.5 })
        startBlackout()
        w:minute(5)
        expect.truthy(p.asleep)
        expect.falsy(other.asleep)
        expect.eq(other.modData, {})
        expect.eq(w.search[1], nil)
    end)
end)

describe("death", function()
    it("turns the blackout effect off when the player dies mid-blackout", function()
        startBlackout()
        w:minute()
        p.dead = true
        w.fire("OnPlayerDeath", p)
        expect.eq(p.modData, {})
        expect.eq(w:searchMode(0), EFFECT_OFF)
    end)

    it("skips dead players", function()
        p.dead = true
        w:minute(1000)
        expect.eq(p.modData, {})
    end)
end)

describe("remote sleepers", function()
    local other
    before_each(function() other = w:addRemotePlayer({ asleep = true }) end)

    it("mirrors the collapse pose onto other players every 10 ticks on a multiplayer client", function()
        w.client = true
        w:tick(9)
        expect.eq(other.events, {})
        w:tick()
        expect.eq(other.events, { "EventSitOnGround" })
        other.asleep = false
        w:tick(10)
        expect.eq(other.vars.forceGetUp, true)
        expect.eq(other.actionQueueStops, 0)
    end)

    it("leaves local players to OnPlayerUpdate", function()
        w.client = true
        p.asleep = true
        w:tick(10)
        expect.eq(p.events, {})
    end)

    it("does nothing in single-player or with Collapse Animation off", function()
        w:tick(20)
        w.client, w.vars.collapsePose = true, false
        w:tick(20)
        expect.eq(other.events, {})
    end)
end)

describe("character creation", function()
    local screen, prone, resistant, insomniac

    local function definition(id)
        local trait = w:trait(id)
        return { getType = function() return trait end }
    end

    before_each(function()
        screen = w.env.CharacterCreationProfession
        prone, resistant = definition("passout:pronetopassing"), definition("passout:resistanttopassing")
        insomniac = definition("INSOMNIAC")
    end)

    it("offers both traits where passing out can happen", function()
        expect.truthy(screen:isTraitEnabled(prone))
        expect.truthy(screen:isTraitEnabled(resistant))
    end)

    it("hides both traits while Enable Pass Out is off", function()
        w.vars.enableMod = false
        expect.falsy(screen:isTraitEnabled(prone))
        expect.falsy(screen:isTraitEnabled(resistant))
        expect.truthy(screen:isTraitEnabled(insomniac))
    end)

    it("hides both traits on a server that does not need sleep", function()
        w.client, w.server.SleepNeeded = true, false
        expect.falsy(screen:isTraitEnabled(prone))
        expect.falsy(screen:isTraitEnabled(resistant))
    end)

    it("drops a chosen Pass Out trait once the traits become unavailable", function()
        local list = setmetatable({ listboxTraitSelected = { items = { { item = prone }, { item = insomniac } } }, repopulated = 0 },
            { __index = screen })
        function list:removeTrait(i) table.remove(self.listboxTraitSelected.items, i) end
        function list:repopulateTraitLists() self.repopulated = self.repopulated + 1 end

        list:prerender()
        expect.eq(#list.listboxTraitSelected.items, 2)
        w.vars.enableMod = false
        list:prerender()
        list:prerender()
        expect.eq(list.listboxTraitSelected.items, { { item = insomniac } })
        expect.eq(list.repopulated, 2, "once per change")
        expect.eq(list.vanillaPrerenders, 3)
    end)
end)
