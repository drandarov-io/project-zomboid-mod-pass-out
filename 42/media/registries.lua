---------------------------------------------------------------------------
-- Pass Out - Build 42 Registries
--
-- Registers custom trait types with the engine before scripts are loaded.
---------------------------------------------------------------------------

local function ensureTrait(id)
    if not (CharacterTrait and ResourceLocation) then return end
    local loc = ResourceLocation.of(id)
    if CharacterTrait.get(loc) ~= nil then return end
    local ok, err = pcall(function() CharacterTrait.register(id) end)
    if not ok then
        print("[PassOut] failed to register trait " .. id .. ": " .. tostring(err))
    end
end

ensureTrait("passout:pronetopassing")
ensureTrait("passout:resistanttopassing")
