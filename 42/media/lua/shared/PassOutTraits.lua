---------------------------------------------------------------------------
-- Pass Out - Build 42 Trait Definitions & MP Safety Net
--
-- On multiplayer client join, Core.ResetLua reloads scripts and can leave
-- custom trait definitions missing if script loading encounters timing quirks.
-- This module verifies both traits and repairs definitions if needed via the
-- Java API on OnGameBoot and character creation list rebuilding.
---------------------------------------------------------------------------

local TRAIT_DEFS = {
    {
        id        = "passout:pronetopassing",
        uiName    = "UI_trait_ProneToPassing",
        uiDesc    = "UI_trait_ProneToPassingDesc",
        cost      = -4,
        exclusive = { "passout:resistanttopassing" },
    },
    {
        id        = "passout:resistanttopassing",
        uiName    = "UI_trait_ResistantToPassing",
        uiDesc    = "UI_trait_ResistantToPassingDesc",
        cost      = 4,
        exclusive = { "passout:pronetopassing" },
    },
}

local function resolve(id)
    local ok, trait = pcall(function()
        return CharacterTrait.get(ResourceLocation.of(id))
    end)
    if ok then return trait end
    return nil
end

local function ensureType(id)
    local trait = resolve(id)
    if trait ~= nil then return trait end
    local ok, err = pcall(function() CharacterTrait.register(id) end)
    if not ok then
        print("[PassOut] could not register type " .. id .. ": " .. tostring(err))
        return nil
    end
    return resolve(id)
end

local function ensureDefinition(def, trait)
    if not CharacterTraitDefinition then return nil, false end
    local existing = CharacterTraitDefinition.getCharacterTraitDefinition(trait)
    if existing ~= nil then return existing, false end

    local ok, built = pcall(function()
        return CharacterTraitDefinition.addCharacterTraitDefinition(
            trait, def.uiName, def.cost, def.uiDesc, false, false)
    end)
    if not ok or built == nil then
        print("[PassOut] could not define " .. def.id .. ": " .. tostring(built))
        return nil, false
    end

    for _, otherId in ipairs(def.exclusive) do
        local other = resolve(otherId)
        if other ~= nil then
            built:addMutuallyExclusive(other)
        end
    end

    return built, true
end

local function ensureTraits(quiet)
    if not (CharacterTrait and ResourceLocation) then return end
    for _, def in ipairs(TRAIT_DEFS) do
        local trait = ensureType(def.id)
        if trait ~= nil then
            local built, repaired = ensureDefinition(def, trait)
            if not quiet or repaired or built == nil then
                print(string.format("[PassOut] %s registered=true defined=%s%s",
                    def.id, tostring(built ~= nil), repaired and " (rebuilt by fallback)" or ""))
            end
        end
    end
end

Events.OnGameBoot.Add(function() ensureTraits(false) end)

local LIST_BUILDERS = { "populateTraitList", "populateBadTraitList" }
local function wrapTraitLists()
    local screen = CharacterCreationProfession
    if screen == nil or screen.passOutWrapped then return end
    for _, name in ipairs(LIST_BUILDERS) do
        local original = screen[name]
        if type(original) == "function" then
            screen[name] = function(self, ...)
                pcall(ensureTraits, true)
                return original(self, ...)
            end
        end
    end
    screen.passOutWrapped = true
end

Events.OnGameBoot.Add(wrapTraitLists)
Events.OnMainMenuEnter.Add(function() ensureTraits(true) end)
