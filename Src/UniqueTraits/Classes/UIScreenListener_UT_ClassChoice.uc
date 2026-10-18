//---------------------------------------------------------------------------------------
//  FILE:   UIScreenListener_UT_ClassChoice.uc
//  PURPOSE: A rookie's trait is drawn as soon as they can choose a class, precisely so the player can
//           pick the class that fits it (with chooseMyClass like mod). This adds the trait to the choose my class
//           screen (if active) as an ability icon, below the soldier stats panel on the right, whose roll-over shows
//           the name and description. Works on vanilla's UIChooseClass (GTS "train
//           rookie") and every subclass of it, notably the Choose My Class mod's screen (opened from a
//           button it injects in the Armory), without referencing that mod's classes.
//---------------------------------------------------------------------------------------
class UIScreenListener_UT_ClassChoice extends UIScreenListener config(UniqueTraits);

var config int TRAIT_ICON_X;
var config int TRAIT_ICON_Y;
var config int TRAIT_ICON_SIZE;
var config int TRAIT_LABEL_FONT_SIZE;
var config int TRAIT_LABEL_Y_OFFSET;
var config string TRAIT_ICON_BG_COLOR;
var config string TRAIT_ICON_FG_COLOR;

var localized string m_strTraitHeader;
var localized string m_strGrantedHeader;

event OnInit(UIScreen Screen)
{
	local UIChooseClass ChooseScreen;
	local UIArmory Armory;
	local StateObjectReference UnitRef;
	local XComGameState_Unit Unit;
	local X2AbilityTemplateManager AbilityMgr;
	local X2AbilityTemplate AbilityTemplate;
	local UIIcon TraitIcon;
	local UIText LabelText;
	local string IconImage, TraitTitle, Body, GrantedBody;
	local int TraitIndex, i;

	ChooseScreen = UIChooseClass(Screen);
	if (ChooseScreen == none)
		return;

	UnitRef = ChooseScreen.m_UnitRef;
	if (UnitRef.ObjectID == 0)
	{
		Armory = UIArmory(Screen.Movie.Stack.GetFirstInstanceOf(class'UIArmory'));
		if (Armory != none)
			UnitRef = Armory.UnitReference;
	}

	Unit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(UnitRef.ObjectID));
	if (Unit == none || !class'X2DownloadableContentInfo_UniqueTraits'.static.GetAssignedTraitIndex(Unit, TraitIndex))
		return;

	// Only the trait's OWN abilities (this mod's 'UT_' ones) are shown: a trait may also grant a base-game
	// ability (Acrobat -> SkirmisherGrapple, BornToBeChief -> Quick Study, ...) whose icon/description must not
	// replace or pile onto the trait's own, which already mentions it. The icon and the name come from
	// the first own ability; the roll-over lists every own displayable ability.
	AbilityMgr = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	for (i = 0; i < class'UniqueTraits_TraitConfig'.default.Traits[TraitIndex].GrantedAbilities.Length; ++i)
	{
		AbilityTemplate = AbilityMgr.FindAbilityTemplate(class'UniqueTraits_TraitConfig'.default.Traits[TraitIndex].GrantedAbilities[i]);
		if (AbilityTemplate == none || AbilityTemplate.bDontDisplayInAbilitySummary)
			continue;

		// A base-game ability the trait grants: kept for a separate block AFTER the trait's own text.
		if (Left(string(class'UniqueTraits_TraitConfig'.default.Traits[TraitIndex].GrantedAbilities[i]), 3) != "UT_")
		{
			if (GrantedBody != "")
				GrantedBody $= "\n";
			GrantedBody $= "\n" $ class'UIUtilities_Text'.static.GetColoredText(AbilityTemplate.LocFriendlyName, eUIState_Good)
				$ "\n" $ AbilityTemplate.GetMyLongDescription(, Unit);
			continue;
		}

		if (IconImage == "")
		{
			IconImage = AbilityTemplate.IconImage;
			// Sentence case ("Jack of all trades", "False hope"): first letter upper, the rest lower.
			TraitTitle = Caps(Left(AbilityTemplate.LocFriendlyName, 1)) $ Locs(Mid(AbilityTemplate.LocFriendlyName, 1));
		}
		else
		{
			Body $= "\n\n" $ class'UIUtilities_Text'.static.GetColoredText(AbilityTemplate.LocFriendlyName, eUIState_Highlight) $ "\n";
		}
		Body $= AbilityTemplate.GetMyLongDescription(, Unit);
	}

	if (IconImage == "")
		return;

	// The granted base-game abilities come last, visibly separated by a muted divider line, so the trait
	// itself always reads first.
	if (GrantedBody != "")
	{
		Body $= "\n\n" $ class'UIUtilities_Text'.static.GetColoredText("-----  " $ m_strGrantedHeader $ "  -----", eUIState_Disabled)
			$ GrantedBody;
	}

	TraitIcon = Screen.Spawn(class'UIIcon', Screen);
	if (`ISCONTROLLERACTIVE)
		TraitIcon.bIsNavigable = false;
	TraitIcon.bDisableSelectionBrackets = true;
	TraitIcon.bAnimateOnInit = false;
	TraitIcon.InitIcon('UT_TraitIcon', IconImage, true, true, default.TRAIT_ICON_SIZE);
	// Background / icon colours (hex RRGGBB, no '#') from the ini; the vanilla ability-icon look (cyan
	// background, near-black icon) is used when an entry is missing (e.g. a stale deployed ini).
	TraitIcon.EnableMouseAutomaticColor(
		default.TRAIT_ICON_BG_COLOR != "" ? default.TRAIT_ICON_BG_COLOR : "91CACA",
		default.TRAIT_ICON_FG_COLOR != "" ? default.TRAIT_ICON_FG_COLOR : "161616");
	TraitIcon.SetPosition(default.TRAIT_ICON_X, default.TRAIT_ICON_Y);
	TraitIcon.SetTooltipText(Body, m_strTraitHeader $ ": " $ TraitTitle,,,,,, 0.2);

	// Caption to the right of the icon, in the icon's background colour, to catch the eye.
	LabelText = Screen.Spawn(class'UIText', Screen);
	LabelText.bIsNavigable = false;
	LabelText.InitText('UT_TraitLabel');
	LabelText.SetHTMLText("<font face='$TitleFont' size='" $ default.TRAIT_LABEL_FONT_SIZE $ "' color='#"
		$ (default.TRAIT_ICON_BG_COLOR != "" ? default.TRAIT_ICON_BG_COLOR : "91CACA") $ "'>" $ TraitTitle $ "</font>");
	LabelText.SetPosition(default.TRAIT_ICON_X + default.TRAIT_ICON_SIZE + 8, default.TRAIT_ICON_Y + default.TRAIT_LABEL_Y_OFFSET);
	LabelText.SetSize(220, default.TRAIT_ICON_SIZE);
}

defaultproperties
{
	ScreenClass = none
}
