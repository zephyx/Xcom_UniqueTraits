//---------------------------------------------------------------------------------------
//  FILE:   UIScreenListener_UT_HackingScreen.uc
//  PURPOSE: Security hacker: in the hacking screen of a security tower opened by a holder, the description of the BIGGEST reward gets one more line
//           about the XCOM ability points it also gives (UT_Trait_SecurityHacker.SECURITYHACKER_AP_TEXT, the amount from GetAPReward). The screen
//           builds its reward panels in its own OnInit (PopulateResultsInfo) and a screen listener's OnInit runs after that,
//           so the panel is simply filled again with the same values and the longer description.
//           Only the description: the name and the percentages are the template's / the game's. The hover preview under the ability (Perfect
//           Information) is not touched.
//---------------------------------------------------------------------------------------
class UIScreenListener_UT_HackingScreen extends UIScreenListener;

event OnInit(UIScreen Screen)
{
	local UIHackingScreen HackScreen;
	local X2HackRewardTemplate Template;
	local string FailText, Description;
	local int Index, Points;

	HackScreen = UIHackingScreen(Screen);
	if (HackScreen == none || HackScreen.UnitState == none || HackScreen.ObjectState == none || HackScreen.HackRewards.Length < 2)
		return;

	Index = GetBiggestIndex(HackScreen);
	if (Index == INDEX_NONE)
		return;

	Template = HackScreen.HackRewards[Index];
	if (!class'UT_Trait_SecurityHacker'.static.IsAPReward(Template, HackScreen.UnitState, HackScreen.ObjectState))
		return;

	Points = class'UT_Trait_SecurityHacker'.static.GetAPReward(Template, HackScreen.UnitState);
	if (Points <= 0)
		return;

	// The same values as UIHackingScreen.PopulateResultsInfo (a panel after the first one shows the "if the previous fails" text).
	FailText = HackScreen.HackRewards[0].bBadThing ? HackScreen.FeedbackFailText : HackScreen.GuaranteedFailText;
	Description = Template.GetDescription(HackScreen.HackTargetObject) $ "\n" $ Repl(class'UT_Trait_SecurityHacker'.default.SECURITYHACKER_AP_TEXT, "<Points/>", string(Points));

	HackScreen.AS_SetResultInfo(
		Index,
		false,
		Template.GetFriendlyName(),
		Template.RewardImagePath,
		Description,
		HackScreen.strRewardUnlockedLabel,
		HackScreen.strUnlockChanceLabel,
		string(Round(HackScreen.GetHackChance(Index))) $ "\%",
		Template.bBadThing,
		FailText);

	// The screen's own OnInit ended with RefreshPreviewState, which writes the rounded percentages ("54%") and the selected / highlighted state of the
	// panels with other calls, AS_SetResultInfo wrote the percentage again (a raw float, "54.00") and may have reset that state: do it once more.
	HackScreen.RefreshPreviewState();
}

// The index of the biggest reward (highest MinHackSuccess, not a bad thing) in the list of templates of the screen: the same rule as
// UT_Trait_SecurityHacker.GetBiggestRewardIndex, on the names of those templates (they are in the order of the panels).
static function int GetBiggestIndex(UIHackingScreen HackScreen)
{
	local array<name> Names;
	local int i;

	for (i = 0; i < HackScreen.HackRewards.Length; ++i)
		Names.AddItem(HackScreen.HackRewards[i].DataName);

	return class'UT_Trait_SecurityHacker'.static.GetBiggestRewardIndex(Names);
}

defaultproperties
{
	ScreenClass = class'UIHackingScreen'
}
