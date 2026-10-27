//---------------------------------------------------------------------------------------
//  FILE:   UIScreenListener_UT_PromotionMarks.uc
//  PURPOSE: Two jobs on every soldier promotion screen of the "hero" family - the base game's UIArmory_PromotionHero and everything derived from it
//           (Community Promotion Screen's CPS_UIArmory_PromotionHero, New Promotion Screen by Default's). Only the base class is referenced: no class
//           of the other mods is.
//           - OnInit: puts a UT_PromotionMarks panel on the screen (the diamonds behind the evolutions of Someone different), and raises the information popup of the
//             mutation the first time a mutated holder's screen opens (UT_Trait_SomeoneDifferent.ShowMutationPopup).
//           - OnRemoved: the screen is where abilities are bought and no event reports a purchase, so Someone different's stats (which follow the number
//             of evolutions bought) and Predestined's (points, stats) are synced when it closes. Independent of PROMOTION_MARKS_ENABLED.
//---------------------------------------------------------------------------------------
class UIScreenListener_UT_PromotionMarks extends UIScreenListener;

event OnInit(UIScreen Screen)
{
	if (UIArmory_PromotionHero(Screen) == none)
		return;

	// Someone different: the explanation of the mutation, the first time the screen of a mutated holder opens (independent of PROMOTION_MARKS_ENABLED).
	class'UT_Trait_SomeoneDifferent'.static.ShowMutationPopup(Screen, UIArmory_PromotionHero(Screen).GetUnitRef());

	if (!class'UT_PromotionMarks'.default.PROMOTION_MARKS_ENABLED)
		return;

	Screen.Spawn(class'UT_PromotionMarks', Screen).InitMarks();
}

event OnRemoved(UIScreen Screen)
{
	local UIArmory_PromotionHero PromotionScreen;

	PromotionScreen = UIArmory_PromotionHero(Screen);
	if (PromotionScreen != none)
	{
		class'UT_Trait_SomeoneDifferent'.static.SyncUnit(PromotionScreen.GetUnitRef());
		class'UT_Trait_Predestined'.static.SyncUnit(PromotionScreen.GetUnitRef());
	}
}

defaultproperties
{
	ScreenClass = none;
}
