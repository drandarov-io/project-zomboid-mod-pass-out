require('NPCs/MainCreationMethods')

local function passOutTraits()
    local sleepDisabled = false
    if isClient() or isServer() then
        local opt = getServerOptions()
        if opt and not opt:getBoolean("SleepNeeded") then
            sleepDisabled = true
        end
    end

    local prone = TraitFactory.addTrait(
        "ProneToPassing",
        getText("UI_trait_ProneToPassing"),
        -4,
        getText("UI_trait_ProneToPassingDesc"),
        false,
        sleepDisabled
    )
    if prone and prone.getTexture then
        local tex = prone:getTexture()
        if tex and tex.setTexture then
            tex:setTexture("media/ui/Traits/trait_ProneToPassing.png")
        end
    end

    local resistant = TraitFactory.addTrait(
        "ResistantToPassing",
        getText("UI_trait_ResistantToPassing"),
        4,
        getText("UI_trait_ResistantToPassingDesc"),
        false,
        sleepDisabled
    )
    if resistant and resistant.getTexture then
        local tex = resistant:getTexture()
        if tex and tex.setTexture then
            tex:setTexture("media/ui/Traits/trait_ResistantToPassing.png")
        end
    end

    TraitFactory.setMutualExclusive("ProneToPassing", "ResistantToPassing")
end

Events.OnGameBoot.Add(passOutTraits)
