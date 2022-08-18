require('NPCs/MainCreationMethods');
local function PassOutTraits()
  -- Write number signifying how much points is spent/gained from a trait in the "cost" value
  -- Negative number gives you points, and positive number spends it
  -- False means the trait is *not* hidden and can be seen when creating a character, use true for occupation traits
    TraitFactory.addTrait("ProneToPassing", getText("UI_trait_PassOutProne"), cost, getText("UI_trait_PassOutProneDesc"), false);
    TraitFactory.addTrait("ResistantToPassing", getText("UI_trait_PassOutResistant"), cost, getText("UI_trait_PassOutResistantDesc"), false);
    TraitFactory.setMutualExclusive("ProneToPassing", "ResistantToPassing");
end

Events.OnGameBoot.Add(PassOutTraits);
