//---------------------------------------------------------------------------------------
//  FILE:   UIScreenListener_UT_LootWindow.uc
//  PURPOSE: Thief's secretly kept items are removed from the looter's inventory the moment they
//           are taken, and the tactical loot window (UIInventoryTactical) only lists items the
//           looter actually holds (UpdateData skips the rest), so a stolen item simply vanishes
//           from it. This adds, once the window has built its own list, one red "Stolen!" row per
//           item of the looted object that Thief stole.
//---------------------------------------------------------------------------------------
class UIScreenListener_UT_LootWindow extends UIScreenListener;

event OnInit(UIScreen Screen)
{
	local UIInventoryTactical LootWindow;
	local UIInventoryTactical_LootingItem Row;
	local array<StateObjectReference> LootItems;
	local UnitValue StolenValue;
	local int i;

	LootWindow = UIInventoryTactical(Screen);
	if (LootWindow == none || LootWindow.LootTarget == none || LootWindow.m_Looter == none || LootWindow.m_kLootList == none)
		return;

	LootItems = LootWindow.LootTarget.GetAvailableLoot();
	for (i = 0; i < LootItems.Length; ++i)
	{
		if (LootWindow.m_Looter.InventoryItems.Find('ObjectID', LootItems[i].ObjectID) != INDEX_NONE)
			continue;

		if (!LootWindow.m_Looter.GetUnitValue(name("UT_Thief_Stolen_" $ LootItems[i].ObjectID), StolenValue))
			continue;

		Row = LootWindow.Spawn(class'UIInventoryTactical_LootingItem', LootWindow.m_kLootList.ItemContainer).InitLootItem(true);
		Row.SetText(class'UIUtilities_Text'.static.GetColoredText(class'X2EventListener_UniqueTraits'.default.THIEF_STEAL_FLYOVER, eUIState_Bad));
		Row.GameStateObjectID = LootItems[i].ObjectID;
	}
}

defaultproperties
{
	ScreenClass = class'UIInventoryTactical'
}
