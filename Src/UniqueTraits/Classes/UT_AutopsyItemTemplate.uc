//---------------------------------------------------------------------------------------
//  FILE:   UT_AutopsyItemTemplate.uc
//  PURPOSE: The fictive item "Autopsy: <alien type>" that the Coroner trait leaves in a blue loot zone (UT_Trait_Coroner). ONE template for every alien type: the type is the Nickname
//           (the name of the corpse item the dead alien left, e.g. CorpseSectoid) of the item STATE, and GetItemFriendlyName builds the displayed name from it
//           (UT_Trait_Coroner.GetTypeLabel strips "Corpse" from the corpse's name), so the tactical loot window shows "Autopsy: Sectoid".
//           CanBeLootedByUnit is what makes the loot Coroner-only: the game asks it before offering or giving a loot item (Helpers.HasAvailableLootInternal / GetLootInternal), so
//           anybody else neither sees the item nor can take it. Same hook as X2FocusLootItemTemplate (Templar focus).
//           In the mission the looted item stays in the Coroner's backpack. After the mission the BASE GAME moves it (and the ones left in the zones of a swept mission) to the HQ's
//           LootRecovered, so the loot recap screen lists one "Autopsy: <type>" line per item. UT_Trait_Coroner.OnPostMission credits the campaign tally from those lines.
//           HideInInventory + OnAcquiredFn (UT_Trait_Coroner.OnAutopsyAcquired) delete the item when the recap is closed and the loot is moved to the inventory: it never stays in the HQ.
//---------------------------------------------------------------------------------------
class UT_AutopsyItemTemplate extends X2ItemTemplate;

function bool CanBeLootedByUnit(XComGameState_Item LootItem, XComGameState_Unit Looter, Lootable LootableObject)
{
	return Looter != none && class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Looter, 'UT_Coroner');
}

// "Autopsy: Sectoid" for an item state that carries its type. The bare template name otherwise (ItemID 0: list of templates).
function string GetItemFriendlyName(optional int ItemID = 0, optional bool bShowSquadUpgrade)
{
	local XComGameState_Item ItemState;

	ItemState = XComGameState_Item(`XCOMHISTORY.GetGameStateForObjectID(ItemID));
	if (ItemState != none && ItemState.Nickname != "")
		return class'UT_Trait_Coroner'.static.GetAutopsyName(name(ItemState.Nickname));

	return class'UT_Trait_Coroner'.default.CORONER_ITEM_NAME_BASE;
}

function string GetItemFriendlyNameNoStats()
{
	return class'UT_Trait_Coroner'.default.CORONER_ITEM_NAME_BASE;
}

function string GetItemBriefSummary(optional int ItemID = 0)
{
	return class'UT_Trait_Coroner'.default.CORONER_ITEM_SUMMARY;
}

defaultproperties
{
	iItemSize = 0
	MaxQuantity = 1
	ItemCat = "resource"
	HideInInventory = true
	HideInLootRecovered = false
	LeavesExplosiveRemains = true
}
