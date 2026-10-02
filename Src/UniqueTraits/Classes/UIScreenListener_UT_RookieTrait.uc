//---------------------------------------------------------------------------------------
//  FILE:   UIScreenListener_UT_RookieTrait.uc
//  PURPOSE: A rookie now gets their trait as soon as they can choose a class, but the
//           vanilla Armory hides the whole ability summary of a rank-0 unit
//           (UIUtilities_Strategy.PopulateAbilitySummary returns early when GetRank() == 0 and
//           bSkipRankCheck is false), so the trait would stay invisible exactly when the player
//           needs it: before the class choice (ChooseMyClass / Promote button). Once the Armory
//           main menu has built itself (and every time it regains focus, e.g. back from the
//           class choice screen), this repopulates the summary with the rank check skipped.
//---------------------------------------------------------------------------------------
class UIScreenListener_UT_RookieTrait extends UIScreenListener;

event OnInit(UIScreen Screen)
{
	ShowRookieTrait(Screen);
}

event OnReceiveFocus(UIScreen Screen)
{
	ShowRookieTrait(Screen);
}

static function ShowRookieTrait(UIScreen Screen)
{
	local UIArmory_MainMenu Armory;
	local XComGameState_Unit Unit;
	local int TraitIndex;

	Armory = UIArmory_MainMenu(Screen);
	if (Armory == none)
		return;

	Unit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(Armory.UnitReference.ObjectID));
	if (Unit == none)
		return;

	if (Unit.GetRank() != 0)
		return;

	if (!class'X2DownloadableContentInfo_UniqueTraits'.static.GetAssignedTraitIndex(Unit, TraitIndex))
		return;

	class'UIUtilities_Strategy'.static.PopulateAbilitySummary(Armory, Unit, true);
}

defaultproperties
{
	ScreenClass = class'UIArmory_MainMenu'
}
