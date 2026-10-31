//---------------------------------------------------------------------------------------
//  FILE:   UIScreenListener_UT_BlackMarket.uc
//  PURPOSE: Coroner: when the black market's sell screen opens, the listed prices of the corpses are reconciled with the campaign's autopsy bonus
//           (UT_AutopsyBonuses.ReconcilePrices). The screen's own PopulateData has just added the prices of the items that were not listed yet (at the
//           template's value, a corpse that arrived after the last pass), so this is the moment to give them their bonus; the list is then drawn again.
//           Does nothing without any autopsy in the tally.
//---------------------------------------------------------------------------------------
class UIScreenListener_UT_BlackMarket extends UIScreenListener;

event OnInit(UIScreen Screen)
{
	local UIBlackMarket_Sell SellScreen;

	SellScreen = UIBlackMarket_Sell(Screen);
	if (SellScreen == none)
		return;

	if (class'UT_AutopsyBonuses'.static.ReconcileNow())
		SellScreen.PopulateData();
}

// ScreenClass is none on purpose: a listener typed on UIBlackMarket_Sell is never called in the game (the screen opened may be a subclass added by another mod).
// Every screen is looked at. the cast in OnInit keeps the sell screens and their subclasses.
defaultproperties
{
	ScreenClass = none
}
