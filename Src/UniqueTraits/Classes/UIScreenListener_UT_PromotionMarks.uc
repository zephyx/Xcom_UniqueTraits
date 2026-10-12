//---------------------------------------------------------------------------------------
//  FILE:   UIScreenListener_UT_PromotionMarks.uc
//  PURPOSE: Two jobs on every soldier promotion screen of the "hero" family - the base game's UIArmory_PromotionHero and everything derived from it
//           (Community Promotion Screen's CPS_UIArmory_PromotionHero, New Promotion Screen by Default's). Only the base class is referenced: no class
//           of the other mods is.
//           - OnInit: puts a UT_PromotionMarks panel on the screen (the diamonds behind the evolutions of Someone different).
//           - OnRemoved: the screen is where abilities are bought and no event reports a purchase, so Someone different's stats (which follow the number
//             of evolutions bought) are synced when it closes. Independent of PROMOTION_MARKS_ENABLED.
//---------------------------------------------------------------------------------------
class UIScreenListener_UT_PromotionMarks extends UIScreenListener;

event OnInit(UIScreen Screen)
{
	if (!class'UT_PromotionMarks'.default.PROMOTION_MARKS_ENABLED || UIArmory_PromotionHero(Screen) == none)
		return;

	Screen.Spawn(class'UT_PromotionMarks', Screen).InitMarks();
}

event OnRemoved(UIScreen Screen)
{
	local UIArmory_PromotionHero PromotionScreen;

	PromotionScreen = UIArmory_PromotionHero(Screen);
	if (PromotionScreen != none)
		class'UT_Trait_SomeoneDifferent'.static.SyncUnit(PromotionScreen.GetUnitRef());
}

defaultproperties
{
	ScreenClass = none;
}
