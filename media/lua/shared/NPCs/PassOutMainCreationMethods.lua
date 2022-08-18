require('NPCs/MainCreationMethods');
local function PassOutTraits()
  -- Write number signifying how much points is spent/gained from a trait in the "cost" value
  -- Negative number gives you points, and positive number spends it
  -- False means the trait is *not* hidden and can be seen when creating a character, use true for occupation traits
  local sleepOK = (isClient() or isServer()) and getServerOptions():getBoolean("SleepAllowed") and getServerOptions():getBoolean("SleepNeeded")
    TraitFactory.addTrait("ProneToPassing", getText("UI_trait_ProneToPassing"), cost, getText("UI_trait_ProneToPassingDesc"), false, not SleepOK);
    TraitFactory.addTrait("ResistantToPassing", getText("UI_trait_ResistantToPassing"), cost, getText("UI_trait_ResistantToPassingDesc"), false, not SleepOK);
    TraitFactory.setMutualExclusive("ProneToPassing", "ResistantToPassing");
end

Events.OnGameBoot.Add(PassOutTraits);
