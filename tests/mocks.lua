-- Fake Build 42 game for the Pass Out client code.
--
-- mocks.world() builds fresh game globals in a harness sandbox, runs the mod's
-- real 42/media/registries.lua and 42/media/lua/client/Pass_Out.lua in it and
-- returns a world to drive time and players and to inspect what the mod did.
-- Values the engine computes (moodle levels, ZombRand) follow the decompiled
-- game code cited next to them.

local M = {}

-- Kahlua strings have contains(); vanilla and the mod call it on bed types.
string.contains = string.contains or function(s, part) return s:find(part, 1, true) ~= nil end

-- Moodle level = how many thresholds the stat is strictly above
-- (Moodle.java:129-180 with MoodleStat.java:12-14).
local MOODLES = {
    TIRED = { stat = "FATIGUE", 0.6, 0.7, 0.8, 0.9 },
    PANIC = { stat = "PANIC", 6, 30, 65, 80 },
}

-- SandboxVars.PassOut as the game builds it from the defaults in sandbox-options.txt.
local function sandboxDefaults()
    local file = assert(io.open(harness.root .. "/42/media/sandbox-options.txt", "rb"))
    local src = file:read("*a")
    file:close()
    local vars = {}
    for name, body in src:gmatch("option PassOut%.(%w+)%s*(%b{})") do
        local default = body:match("default%s*=%s*([^,%s]+)")
        if body:match("type%s*=%s*boolean") then
            vars[name] = default == "true"
        else
            vars[name] = tonumber(default)
        end
    end
    return vars
end

local function javaList(items)
    return { size = function() return #items end, get = function(_, i) return items[i + 1] end }
end

---------------------------------------------------------------------------
-- Players and vehicles
---------------------------------------------------------------------------

local Player = {}
Player.__index = Player

function Player:getModData() return self.modData end
function Player:isDead() return self.dead end
function Player:isLocalPlayer() return self.isLocal end
function Player:getPlayerNum() return self.num end
function Player:getOnlineID() return self.onlineId end
function Player:isAsleep() return self.asleep end
function Player:setAsleep(on) self.asleep = on end
function Player:hasTrait(trait) return self.traits[trait] == true end
function Player:Say(text) self.said[#self.said + 1] = text end
function Player:getVehicle() return self.vehicle end
function Player:isSitOnGround() return self.sitting end
function Player:isSittingOnFurniture() return false end
function Player:isOnBed() return false end
function Player:getCurrentActionContextStateName() return self.sitting and "sitonground" or self.action end
function Player:setAutoWalk(on) self.autoWalk = on end
function Player:StopAllActionQueue() self.actionQueueStops = self.actionQueueStops + 1 end
function Player:isBlockMovement() return self.blockMovement end
function Player:setBlockMovement(on) self.blockMovement = on end
function Player:setBed(bed) self.bed = bed end
function Player:setBedType(bedType) self.bedType = bedType end
function Player:setForceWakeUpTime(hour) self.wakeHour = hour end
function Player:setAsleepTime(t) self.asleepTime = t end
function Player:playSound(name) self.sounds[#self.sounds + 1] = name end

function Player:getStats()
    local stats = self.stats
    return {
        get = function(_, stat) return stats[stat] or 0 end,
        set = function(_, stat, value) stats[stat] = value end,
    }
end

function Player:getMoodles()
    local stats = self.stats
    return {
        getMoodleLevel = function(_, moodle)
            local level, thresholds = 0, MOODLES[moodle]
            for i, threshold in ipairs(thresholds) do
                if (stats[thresholds.stat] or 0) > threshold then level = i end
            end
            return level
        end,
    }
end

-- The sit-on-ground transition only starts from idle; forceGetUp ends it.
function Player:reportEvent(name)
    self.events[#self.events + 1] = name
    if name == "EventSitOnGround" and self.action == "idle" then self.sitting = true end
end

function Player:setVariable(name, value)
    self.vars[name] = value
    if name == "forceGetUp" and value then self.sitting = false end
end

local function newPlayer(opts)
    return setmetatable({
        num = opts.num or 0, onlineId = opts.onlineId or opts.num or 0, isLocal = opts.isLocal ~= false,
        stats = { FATIGUE = opts.fatigue or 0, PANIC = opts.panic or 0 },
        modData = {}, traits = {}, vars = {}, said = {}, events = {}, sounds = {},
        dead = false, asleep = opts.asleep or false, sitting = false, action = "idle",
        blockMovement = false, actionQueueStops = 0,
    }, Player)
end

-- driver defaults to the player the vehicle is given to by world:drive().
local function newVehicle(opts)
    return {
        battery = opts.battery or 1, horn = opts.horn ~= false, honking = false,
        isDriver = function(self, p) return self.driver == p end,
        getBatteryCharge = function(self) return self.battery end,
        hasHorn = function(self) return self.horn end,
        onHornStart = function(self) self.honking = true end,
        onHornStop = function(self) self.honking = false end,
    }
end

---------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------

local World = {}
World.__index = World

function M.world()
    local w = setmetatable({
        time = 0,              -- getGametimeTimestamp(): in-game seconds
        ms = 0,                -- getTimestampMs(): real milliseconds
        timeOfDay = 12,        -- GameTime:getTimeOfDay(): hours
        client = false,        -- isClient()
        server = { SleepAllowed = true, SleepNeeded = true },
        bedQuality = "floor",  -- ISWorldObjectContextMenu.getBedQuality(player, nil)
        rand = function() return 0 end, -- ZombRand's pick from its n results: 0 = lowest, n - 1 = highest
        players = {},          -- local players, index = player number + 1
        remote = {},           -- other players in getOnlinePlayers()
        search = {},           -- search-mode state per player number
        log = {},              -- calls into game APIs as { name, args... }
        vars = sandboxDefaults(),
    }, World)

    local function record(name, ...) w.log[#w.log + 1] = { name, ... } end

    local traits = {}
    local function trait(id) return { id = id } end

    local function searchState(pnum)
        w.search[pnum] = w.search[pnum] or { enabled = false, override = false, blur = 0, desat = 0, radius = 50, darkness = 0 }
        return w.search[pnum]
    end
    local function target(pnum, key)
        return function() return { setTargets = function(_, value) searchState(pnum)[key] = value end } end
    end
    local searchMode = {
        getSearchModeForPlayer = function(_, pnum)
            return { getBlur = target(pnum, "blur"), getDesat = target(pnum, "desat"),
                     getRadius = target(pnum, "radius"), getDarkness = target(pnum, "darkness") }
        end,
        setEnabled = function(_, pnum, on) searchState(pnum).enabled = on end,
        setOverrideSearchManager = function(_, pnum, on) searchState(pnum).override = on end,
    }

    local events, fire, handlers = harness.events()
    w.fire, w.handlers = fire, handlers

    w.env = harness.sandbox({
        Events = events,
        SandboxVars = { PassOut = w.vars },
        isClient = function() return w.client end,
        getServerOptions = function() return { getBoolean = function(_, name) return w.server[name] end } end,
        getNumActivePlayers = function() return #w.players end,
        getSpecificPlayer = function(i) return w.players[i + 1] end,
        getPlayer = function() return w.players[1] end,
        getOnlinePlayers = function()
            local all = {}
            for _, p in ipairs(w.players) do all[#all + 1] = p end
            for _, p in ipairs(w.remote) do all[#all + 1] = p end
            return javaList(all)
        end,
        getGametimeTimestamp = function() return w.time end,
        getTimestampMs = function() return w.ms end,
        GameTime = { getInstance = function() return { getTimeOfDay = function() return w.timeOfDay end } end },
        -- (int) casts truncate toward zero, then Next(min, max) is in [min, max)
        -- (LuaManager.java:6091, RandAbstract.java:33-50).
        ZombRand = function(min, max)
            local function int(x) return x < 0 and math.ceil(x) or math.floor(x) end
            min, max = int(min), int(max)
            if min == max then return min end
            if min > max then min, max = max, min end
            return min + w.rand(max - min)
        end,
        getText = function(key) return key end,
        MoodleType = { TIRED = "TIRED", PANIC = "PANIC" },
        CharacterStat = { FATIGUE = "FATIGUE", PANIC = "PANIC" },
        CharacterTrait = {
            INSOMNIAC = trait("base:insomniac"),
            NEEDS_LESS_SLEEP = trait("base:needslesssleep"),
            NEEDS_MORE_SLEEP = trait("base:needsmoresleep"),
            get = function(location) return traits[location.id] end,
            register = function(id) traits[id] = trait(id) end,
        },
        ResourceLocation = { of = function(id) return { id = id } end },
        HaloTextHelper = { addBadText = function(p, text) record("addBadText", p, text) end },
        getSearchMode = function() return searchMode end,
        triggerEvent = function(name, ...) record("triggerEvent", name, ...) end,
        ISTimedActionQueue = { clear = function(p) record("clearActionQueue", p) end },
        ISWorldObjectContextMenu = { getBedQuality = function() return w.bedQuality end },
        getSleepingEvent = function()
            return { setPlayerFallAsleep = function(_, p, hours) record("setPlayerFallAsleep", p, hours) end }
        end,
        UIManager = {
            setFadeBeforeUI = function(pnum, on) record("setFadeBeforeUI", pnum, on) end,
            FadeOut = function(pnum, seconds) record("FadeOut", pnum, seconds) end,
            getSpeedControls = function()
                return { SetCurrentGameSpeed = function(_, speed) record("SetCurrentGameSpeed", speed) end }
            end,
        },
        IsoPlayer = {
            allPlayersAsleep = function()
                for _, p in ipairs(w.players) do if not p.asleep then return false end end
                return true
            end,
        },
        save = function(...) record("save", ...) end,
        sendClientCommand = function(p, module, command, args) record("sendClientCommand", p, module, command, args) end,
        ISUIElement = {
            derive = function(self, name)
                local class = setmetatable({ Type = name }, { __index = self })
                class.__index = class
                return class
            end,
        },
        CharacterCreationProfession = {
            isTraitEnabled = function() return true end,
            prerender = function(screen) screen.vanillaPrerenders = (screen.vanillaPrerenders or 0) + 1 end,
        },
    })

    harness.load(w.env, "42/media/registries.lua")
    harness.load(w.env, "42/media/lua/client/Pass_Out.lua")
    return w
end

-- A local player; the first one added is player 0.
function World:addPlayer(opts)
    opts = opts or {}
    opts.num = #self.players
    local p = newPlayer(opts)
    self.players[#self.players + 1] = p
    return p
end

-- Another client's player, as seen through getOnlinePlayers().
function World:addRemotePlayer(opts)
    opts = opts or {}
    opts.isLocal, opts.num, opts.onlineId = false, -1, 100 + #self.remote
    local p = newPlayer(opts)
    self.remote[#self.remote + 1] = p
    return p
end

-- Seats p in a new vehicle, as its driver unless asPassenger.
function World:drive(p, opts, asPassenger)
    local vehicle = newVehicle(opts or {})
    vehicle.driver = not asPassenger and p or nil
    p.vehicle = vehicle
    return vehicle
end

-- The registered trait object for an id such as "passout:pronetopassing", or
-- a vanilla one by CharacterTrait field name such as "INSOMNIAC".
function World:trait(id)
    local CharacterTrait = self.env.CharacterTrait
    return CharacterTrait[id] or CharacterTrait.get(self.env.ResourceLocation.of(id))
end

function World:giveTrait(p, id) p.traits[self:trait(id)] = true end

function World:searchMode(pnum) return self.search[pnum or 0] or {} end

-- n in-game minutes (default 1), each firing EveryOneMinute.
function World:minute(n)
    for _ = 1, n or 1 do
        self.time = self.time + 60
        self.fire("EveryOneMinute")
    end
end

-- Ticks minutes until cond() holds and returns how many it took, or nil after limit.
function World:minutesUntil(cond, limit)
    for n = 1, limit or 5000 do
        self:minute()
        if cond() then return n end
    end
end

-- One rendered frame after ms real milliseconds (default 16): OnPlayerUpdate per local player.
function World:frame(ms)
    self.ms = self.ms + (ms or 16)
    for _, p in ipairs(self.players) do self.fire("OnPlayerUpdate", p) end
end

function World:tick(n)
    for _ = 1, n or 1 do self.fire("OnTick") end
end

-- The argument lists of every logged call to name, in order.
function World:called(name)
    local calls = {}
    for _, entry in ipairs(self.log) do
        if entry[1] == name then calls[#calls + 1] = { unpack(entry, 2, table.maxn(entry)) } end
    end
    return calls
end

return M
