//---------------------------------------------------------------------------------------
//  FILE:   UniqueTraits_MCMScreen.uc
//  PURPOSE: The "Draw" page of the Mod Config Menu:
//           the general options (trait given at recruitment, default weight) and ONE spinner per trait for its probability, i.e. its weight in the draw
//           (relative to the others, 0 = never drawn). Only created by UIScreenListener_UT_MCM when MCM's options screen exists.
//           - A trait's spinner starts with "Default (N)" then the fixed values (GetStandardValues, plus the player's own
//             value if it is not one of them). N is the DEFAULT WEIGHT and follows the default-weight slider LIVE (DefaultSliderChanged), so the player sees at
//             once which traits use the default. For EVERY trait "Default" means that default weight.
//           - A trait that follows the default weight (no Probability= of its own in the mod's ini): it starts on "Default (N)"; choosing "Default" erases the
//             player's setting; choosing a number stores it, even if it equals the current default.
//           - A trait with a Probability= of its own in the mod's ini (Someone different, 2): it starts on its number (2) and the setting stays empty while
//             it is there (so a change of the ini reaches the player); choosing "Default" stores the marker -1 (= the default weight instead of the ini's
//             number, see UniqueTraits_TraitConfig.GetTraitProbability); choosing another number stores it; choosing the ini's number again erases the setting.
//           - The first option of every trait's spinner (before "Default (N)") is "Disabled": the trait is switched OFF for real (UniqueTraits_TraitConfig.IsTraitDisabled:
//             never drawn, no event registered, no template patched, abilities inert), applied at the next launch; stored as the key D_<TraitID> (1 = off, 0 = on although the
//             ini's bDisabled says off), only when it differs from the ini; the weight stored for the trait is left alone.
//           - Every label ends with "(?)": MCM has no icon, the description is the hover tooltip of the whole row.
//           - Save: for the two general settings only what the player CHANGED is stored (UniqueTraits_MCMSettings.StoreValue: a value equal to the mod's ini goes
//             back to "follows the ini"); the trait spinners are stored as explained above.
//           - Reset: every widget goes back to the mod's ini value ("Default" for every trait); saving then erases the player's choices. Cancel changes nothing.
//---------------------------------------------------------------------------------------
class UniqueTraits_MCMScreen extends Object config(UniqueTraits);

var config bool MCM_TOOLTIP_FIX_ENABLED;   // see UT_MCMTooltipFix: puts back the tooltips of every MCM setting (ini default true)

const MAX_WEIGHT = 50;
const HELP_MARK = " (?)";

var localized string TabDraw, TitleDraw, GroupGeneral, GroupProbabilities;
var localized string AssignLabel, AssignTip, DefaultLabel, DefaultTip, TraitTip, ProbabilityHelp, OptionDefault, TipModDefault, TipOn, TipOff;

var localized string TabAdvanced, TitleAdvanced, GroupAdvancedInfo, AdvancedInfoLabel, AdvancedInfoTip, NoteRestart, NotePermanent, NoteStats;
var localized string OptionDisabled;

// The Advanced page: one slider per option of UniqueTraits_MCMOptions (parallel arrays).
var array<MCM_API_Slider> OptSliders;
var array<name> OptKeys;
var array<int> OptScales;                   // 1 for a whole number, 100 for a number with decimals (stored x100)
var array<int> OptInitial;                  // the value (scaled) the slider had when the page was built / last saved
var array<int> OptIni;                      // the mod's ini value (scaled)
var array<MCM_API_Checkbox> OptChecks;     // the boolean options (flag B): a checkbox each, parallel to the three arrays below
var array<name> OptCheckKeys;
var array<int> OptCheckInitial;             // 1 / 0: the value the checkbox had when the page was built / last saved
var array<int> OptCheckIni;                 // the mod's ini value, 1 / 0

var MCM_API_Checkbox AssignCheckbox;
var MCM_API_Slider DefaultSlider;
var array<MCM_API_Spinner> TraitSpinners;   // one per trait listed, parallel to the arrays below
var array<int> TraitIndices;                // index of each listed trait in UniqueTraits_TraitConfig.Traits
var array<bool> TraitFollowsGlobal;         // true: the trait gives no Probability in the ini (no own weight): it starts on "Default (N)"
var array<int> TraitExtra;                  // the player's value when it is not in GetStandardValues (kept in the list), else -1
var array<int> TraitOwn;                    // the trait's own weight from the mod's ini (it starts on that number), else -1
var array<string> TraitDefaultLabel;        // the text of the "Default (N)" option as it is now (the default weight)
var array<bool> DisabledInitial;            // true: the trait was on the option "Disabled" when the page was built / last saved
var bool AssignInitial;
var int DefaultInitial;

event OnInit(UIScreen Screen)
{
	local MCM_API MCMScreen;

	MCMScreen = MCM_API(Screen);
	if (MCMScreen != none)
	{
		MCMScreen.RegisterClientMod(1, 0, ClientModCallback);
		`log("UniqueTraits : MCM -- page registered on" @ Screen.Class $ ", tooltip fix" @ (default.MCM_TOOLTIP_FIX_ENABLED ? "on" : "off"),, 'UniqueTraits');

		// MCM drops the tooltips of a page the first time it is displayed: this panel puts ours back (see UT_MCMTooltipFix).
		if (default.MCM_TOOLTIP_FIX_ENABLED)
			Screen.Spawn(class'UT_MCMTooltipFix', Screen).InitFix();
	}
}

simulated function ClientModCallback(MCM_API_Instance ConfigAPI, int GameMode)
{
	local MCM_API_SettingsPage Page;
	local MCM_API_SettingsGroup Group;
	local MCM_API_Spinner Spinner;
	local X2AbilityTemplateManager AbilityMgr;
	local X2AbilityTemplate AbilityTemplate;
	local string TraitLabel, Tip, DefaultOption, Selection;
	local int i, PlayerValue, Extra, Own;
	local bool bFollows;

	TraitSpinners.Length = 0;
	TraitIndices.Length = 0;
	TraitFollowsGlobal.Length = 0;
	TraitExtra.Length = 0;
	TraitOwn.Length = 0;
	TraitDefaultLabel.Length = 0;
	DisabledInitial.Length = 0;

	Page = ConfigAPI.NewSettingsPage(TabDraw);
	Page.SetPageTitle(TitleDraw);
	Page.SetSaveHandler(SaveButtonClicked);
	Page.EnableResetButton(ResetButtonClicked);

	Group = Page.AddGroup('UT_General', GroupGeneral);

	AssignInitial = class'UniqueTraits_TraitConfig'.static.ShouldAssignAtRecruitment();
	AssignCheckbox = Group.AddCheckbox('UT_AssignAtRecruitment', AssignLabel $ HELP_MARK,
		AssignTip $ "\n" $ ModDefaultText(class'UniqueTraits_TraitConfig'.default.ASSIGN_TRAIT_AT_RECRUITMENT ? TipOn : TipOff), AssignInitial);

	// The slider tells the trait spinners the new default weight as it moves (its change handler).
	DefaultInitial = class'UniqueTraits_TraitConfig'.static.GetDefaultTraitProbability();
	DefaultSlider = Group.AddSlider('UT_DefaultProbability', DefaultLabel $ HELP_MARK,
		DefaultTip $ "\n" $ ModDefaultText(string(class'UniqueTraits_TraitConfig'.static.GetIniDefaultTraitProbability())),
		0, Max(MAX_WEIGHT, DefaultInitial), 1, DefaultInitial, , DefaultSliderChanged);
	DefaultSlider.SetValueDisplayFilter(FormatWeight);

	// The explanation of the probabilities is the tooltip of this one row (TraitTip)
	Group.AddLabel('UT_ProbabilityHelp', ProbabilityHelp $ HELP_MARK, TraitTip);
	Group.AddLabel('MCM_NoBorder_Empty', "", "");

	Group = Page.AddGroup('UT_Probabilities', GroupProbabilities);
	AbilityMgr = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();

	for (i = 0; i < class'UniqueTraits_TraitConfig'.default.Traits.Length; ++i)
	{
		// A trait whose required mods are not loaded can never be drawn: no row for it.
		if (!class'UniqueTraits_TraitConfig'.static.AreRequiredModsActive(i))
			continue;

		// The trait's name and help text are those of its ability.
		TraitLabel = string(class'UniqueTraits_TraitConfig'.default.Traits[i].TraitID);
		Tip = "";
		if (class'UniqueTraits_TraitConfig'.default.Traits[i].GrantedAbilities.Length > 0)
		{
			AbilityTemplate = AbilityMgr.FindAbilityTemplate(class'UniqueTraits_TraitConfig'.default.Traits[i].GrantedAbilities[0]);
			if (AbilityTemplate != none)
			{
				TraitLabel = AbilityTemplate.LocFriendlyName;
				Tip = AbilityTemplate.LocHelpText;
			}
		}


		// Every trait offers "Default (N)" = the default weight. A trait with a weight of its own in the mod's ini (Own) starts on that number instead.
		bFollows = !class'UniqueTraits_TraitConfig'.static.HasOwnProbability(i);
		Own = bFollows ? -1 : class'UniqueTraits_TraitConfig'.static.GetIniTraitProbability(i);
		DefaultOption = DefaultOptionLabel(DefaultInitial);

		// The selection: the player's value if any (the list gets it even when it is not one of the usual values; a negative one is "Default"), else "Default (N)",
		// else the trait's own number.
		Extra = -1;
		Selection = bFollows ? DefaultOption : string(Own);
		if (class'UniqueTraits_MCMSettings'.static.GetOverride(class'UniqueTraits_TraitConfig'.static.GetTraitProbabilityKey(i), PlayerValue))
		{
			if (PlayerValue < 0)
			{
				Selection = DefaultOption;
			}
			else
			{
				Extra = PlayerValue;
				Selection = string(PlayerValue);
			}
		}

		// A disabled trait (the player's choice, else the ini's bDisabled) starts on "Disabled".
		DisabledInitial.AddItem(class'UniqueTraits_TraitConfig'.static.IsTraitDisabled(i));
		if (DisabledInitial[DisabledInitial.Length - 1])
			Selection = OptionDisabled;

		Spinner = Group.AddSpinner(name("UT_P_" $ class'UniqueTraits_TraitConfig'.default.Traits[i].TraitID), TraitLabel $ HELP_MARK, Tip, BuildOptions(Extra, Own, DefaultOption), Selection);

		TraitIndices.AddItem(i);
		TraitFollowsGlobal.AddItem(bFollows);
		TraitExtra.AddItem(Extra);
		TraitOwn.AddItem(Own);
		TraitDefaultLabel.AddItem(DefaultOption);
		TraitSpinners.AddItem(Spinner);
	}

	Page.ShowSettings();

	BuildAdvancedPage(ConfigAPI);
}

// The "Advanced options" page: for each trait, the numbers it can be tuned with (UniqueTraits_MCMOptions). A "*" in a label means the value is
// built into the abilities when the game starts (applies at the next launch), "**" that it only changes what is done when the trait is given.
// No mark for the flag "S" (permanent stat changes of Nerd, False Hope, Born to be chief): the tooltip says that the soldiers who already have the trait are
// adjusted at their next promotion, mission start or month end.
simulated function BuildAdvancedPage(MCM_API_Instance ConfigAPI)
{
	local MCM_API_SettingsPage Page;
	local MCM_API_SettingsGroup Group;
	local MCM_API_Slider Slider;
	local MCM_API_Checkbox OptCheck;
	local X2AbilityTemplateManager AbilityMgr;
	local X2AbilityTemplate AbilityTemplate;
	local array<string> Rows, Parts;
	local name TraitID, Key;
	local string TraitName, Label, Tip, Flags;
	local int t, r, OptMin, OptMax, OptStep, Scale, Current;
	local bool bBoolean;

	OptSliders.Length = 0;
	OptKeys.Length = 0;
	OptScales.Length = 0;
	OptInitial.Length = 0;
	OptIni.Length = 0;
	OptChecks.Length = 0;
	OptCheckKeys.Length = 0;
	OptCheckInitial.Length = 0;
	OptCheckIni.Length = 0;

	// Makes sure the ini values are cached (they normally are, from OnPreCreateTemplates).
	class'UniqueTraits_MCMOptions'.static.ApplyOverrides();

	Page = ConfigAPI.NewSettingsPage(TabAdvanced);
	Page.SetPageTitle(TitleAdvanced);
	Page.SetSaveHandler(AdvancedSaveClicked);
	Page.EnableResetButton(AdvancedResetClicked);

	Group = Page.AddGroup('UT_AdvancedInfo', GroupAdvancedInfo);
	Group.AddLabel('UT_AdvancedInfoHelp', AdvancedInfoLabel $ HELP_MARK, AdvancedInfoTip);

	AbilityMgr = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	Rows = class'UniqueTraits_MCMOptions'.static.GetRows();

	for (t = 0; t < class'UniqueTraits_TraitConfig'.default.Traits.Length; ++t)
	{
		// A trait whose required mods are not loaded is not in the game: no options for it.
		if (!class'UniqueTraits_TraitConfig'.static.AreRequiredModsActive(t))
			continue;

		TraitID = class'UniqueTraits_TraitConfig'.default.Traits[t].TraitID;
		Group = none;

		for (r = 0; r < Rows.Length; ++r)
		{
			ParseStringIntoArray(Rows[r], Parts, "|", false);
			if (name(Parts[1]) != TraitID)
				continue;

			// The group of a trait is created with its first option; its name is the trait's (that of its ability).
			if (Group == none)
			{
				TraitName = string(TraitID);
				if (class'UniqueTraits_TraitConfig'.default.Traits[t].GrantedAbilities.Length > 0)
				{
					AbilityTemplate = AbilityMgr.FindAbilityTemplate(class'UniqueTraits_TraitConfig'.default.Traits[t].GrantedAbilities[0]);
					if (AbilityTemplate != none)
						TraitName = AbilityTemplate.LocFriendlyName;
				}

				Group = Page.AddGroup(name("UT_A_" $ TraitID), TraitName);
			}

			Key = name(Parts[0]);
			OptMin = int(Parts[2]);
			OptMax = int(Parts[3]);
			OptStep = int(Parts[4]);
			Scale = int(Parts[5]);
			Flags = Parts[6];

			Current = class'UniqueTraits_MCMOptions'.static.GetCurrent(Key);
			Label = Localize("UT_MCM_Options", string(Key) $ "_Label", "UniqueTraits");
			Tip = Localize("UT_MCM_Options", string(Key) $ "_Tip", "UniqueTraits");
			bBoolean = InStr(Flags, "B") != INDEX_NONE;
			if (InStr(Flags, "R") != INDEX_NONE)
			{
				Label $= " *";
				Tip $= "\n" $ NoteRestart;
			}
			else if (InStr(Flags, "P") != INDEX_NONE)
			{
				Label $= " **";
				Tip $= "\n" $ NotePermanent;
			}
			else if (InStr(Flags, "S") != INDEX_NONE)
				Tip $= "\n" $ NoteStats;

			// A boolean option (flag B): a checkbox, stored as 0 / 1.
			if (bBoolean)
			{
				OptCheck = Group.AddCheckbox(name("UT_O_" $ Key), Label $ HELP_MARK, Tip, Current != 0);
				OptChecks.AddItem(OptCheck);
				OptCheckKeys.AddItem(Key);
				OptCheckInitial.AddItem(Current);
				OptCheckIni.AddItem(class'UniqueTraits_MCMSettings'.static.GetIniCached(Key));
				continue;
			}

			Slider = Group.AddSlider(name("UT_O_" $ Key), Label $ HELP_MARK, Tip, float(Min(OptMin, Current)) / float(Scale), float(Max(OptMax, Current)) / float(Scale), float(OptStep) / float(Scale), float(Current) / float(Scale), , AdvancedSliderChanged);
			if (Scale == 100)
				Slider.SetValueDisplayFilter(FormatDecimal);
			else
				Slider.SetValueDisplayFilter(FormatWeight);

			OptSliders.AddItem(Slider);
			OptKeys.AddItem(Key);
			OptScales.AddItem(Scale);
			OptInitial.AddItem(Current);
			OptIni.AddItem(class'UniqueTraits_MCMSettings'.static.GetIniCached(Key));
		}
	}

	Page.ShowSettings();
}

// A slider that shows a number with two decimals (1.25).
simulated function string FormatDecimal(float Value)
{
	local int Hundredths;
	local string Sign, Fraction;

	Hundredths = Round(Value * 100.0);
	if (Hundredths < 0)
	{
		Sign = "-";
		Hundredths = -Hundredths;
	}

	Fraction = string(Hundredths % 100);
	if (Len(Fraction) < 2)
		Fraction = "0" $ Fraction;

	return Sign $ (Hundredths / 100) $ "." $ Fraction;
}

// Quality over quantity: the minimum clip for the reduction must exceed the reduction (minimum - reduction >= 1), or a holder's clip could reach 0. The slider of the minimum
// is pushed up to reduction + 1 when the player lowers it below that or raises the reduction (UT_Trait_QualityOverQuantity.GetMinClipForReduction applies the same rule at run
// time, whatever is stored).
simulated function EnforceClipRule()
{
	local int ReductionIndex, MinIndex, Needed;

	ReductionIndex = OptKeys.Find('QUALITY_CLIP_REDUCTION');
	MinIndex = OptKeys.Find('QUALITY_CLIP_MIN_FOR_REDUCTION');
	if (ReductionIndex == INDEX_NONE || MinIndex == INDEX_NONE)
		return;

	Needed = Round(OptSliders[ReductionIndex].GetValue()) + 1;
	if (Round(OptSliders[MinIndex].GetValue()) < Needed)
		OptSliders[MinIndex].SetValue(float(Needed), true);
}

// Change handler of every slider of the Advanced page (only fired by the player): keeps the clip rule above.
simulated function AdvancedSliderChanged(MCM_API_Setting Setting, float Value)
{
	EnforceClipRule();
}

// Saves what changed on the Advanced page (a value equal to the mod's ini is not stored), then applies it at once: the values read when used change now, the ones
// baked into the abilities (marked *) at the next launch.
simulated function AdvancedSaveClicked(MCM_API_SettingsPage Page)
{
	local int i, Value;

	EnforceClipRule();

	for (i = 0; i < OptSliders.Length; ++i)
	{
		Value = Round(OptSliders[i].GetValue() * float(OptScales[i]));
		if (Value == OptInitial[i])
			continue;

		class'UniqueTraits_MCMSettings'.static.StoreValue(OptKeys[i], Value, OptIni[i]);
		OptInitial[i] = Value;
	}

	for (i = 0; i < OptChecks.Length; ++i)
	{
		Value = 0;
		if (OptChecks[i].GetValue())
			Value = 1;
		if (Value == OptCheckInitial[i])
			continue;

		class'UniqueTraits_MCMSettings'.static.StoreValue(OptCheckKeys[i], Value, OptCheckIni[i]);
		OptCheckInitial[i] = Value;
	}

	class'UniqueTraits_MCMSettings'.static.Commit();
	class'UniqueTraits_MCMOptions'.static.ApplyOverrides();
}

// Every slider back to the mod's ini value (saving then erases the player's choices).
simulated function AdvancedResetClicked(MCM_API_SettingsPage Page)
{
	local int i;

	for (i = 0; i < OptSliders.Length; ++i)
		OptSliders[i].SetValue(float(OptIni[i]) / float(OptScales[i]), true);

	for (i = 0; i < OptChecks.Length; ++i)
		OptChecks[i].SetValue(OptCheckIni[i] != 0, true);
}

// "Default (N)" (the first option of a trait's spinner).
simulated function string DefaultOptionLabel(int Weight)
{
	return OptionDefault @ "(" $ Weight $ ")";
}

// The fixed values a trait can be given: 0 to 10, then coarser steps (weights are relative, the usual range is small).
simulated function array<int> GetStandardValues()
{
	local array<int> Values;
	local int i;

	for (i = 0; i <= 10; ++i)
		Values.AddItem(i);

	Values.AddItem(12);
	Values.AddItem(15);
	Values.AddItem(20);
	Values.AddItem(25);
	Values.AddItem(30);
	Values.AddItem(40);
	Values.AddItem(MAX_WEIGHT);

	return Values;
}

// Puts Value in the sorted list of fixed values when it is not one of them (a negative Value means "none").
simulated function InsertValue(out array<int> Values, int Value)
{
	local int i, Position;

	if (Value < 0 || Values.Find(Value) != INDEX_NONE)
		return;

	Position = Values.Length;
	for (i = 0; i < Values.Length; ++i)
	{
		if (Values[i] > Value)
		{
			Position = i;
			break;
		}
	}

	Values.InsertItem(Position, Value);
}

// The options of a trait's spinner: "Disabled" (the trait is OFF for real, applies at the next launch), DefaultOption (none when empty: a trait with its own weight), then the usual values and, in order, the player's own value
// (ExtraValue) and the trait's own weight (OwnValue) when they are not among them.
simulated function array<string> BuildOptions(int ExtraValue, int OwnValue, string DefaultOption)
{
	local array<string> Options;
	local array<int> Values;
	local int i;

	Values = GetStandardValues();
	InsertValue(Values, ExtraValue);
	InsertValue(Values, OwnValue);

	Options.AddItem(OptionDisabled);
	if (DefaultOption != "")
		Options.AddItem(DefaultOption);

	for (i = 0; i < Values.Length; ++i)
		Options.AddItem(string(Values[i]));

	return Options;
}

// The default-weight slider moved (change handler, only fired by the player): the "Default (N)" option of EVERY trait shows the new N, whether that trait is on
// "Default" (it stays selected) or on a fixed value (it stays selected, but the option it can go back to is right).
simulated function DefaultSliderChanged(MCM_API_Setting Setting, float Value)
{
	local int i;
	local string NewLabel, Selection;

	NewLabel = DefaultOptionLabel(Round(Value));
	for (i = 0; i < TraitSpinners.Length; ++i)
	{
		Selection = TraitSpinners[i].GetValue();
		if (Selection == TraitDefaultLabel[i])
			Selection = NewLabel;

		TraitSpinners[i].SetOptions(BuildOptions(TraitExtra[i], TraitOwn[i], NewLabel), Selection, true);
		TraitDefaultLabel[i] = NewLabel;
	}
}

// "Mod default: X" appended to the tooltips of the two general settings (the value the mod's ini gives, ignoring what the player chose).
simulated function string ModDefaultText(string DefaultValue)
{
	return TipModDefault @ DefaultValue;
}

// A slider shows whole numbers.
simulated function string FormatWeight(float Value)
{
	return string(Round(Value));
}

// Stores what the player set on this page (see the header), then writes the file once.
simulated function SaveButtonClicked(MCM_API_SettingsPage Page)
{
	local int i, Value;
	local bool bChecked;
	local string Selection;
	local name Key, DisabledKey;

	bChecked = AssignCheckbox.GetValue();
	if (bChecked != AssignInitial)
	{
		class'UniqueTraits_MCMSettings'.static.StoreValue('AssignAtRecruitment', bChecked ? 1 : 0, class'UniqueTraits_TraitConfig'.default.ASSIGN_TRAIT_AT_RECRUITMENT ? 1 : 0);
		AssignInitial = bChecked;
	}

	Value = Round(DefaultSlider.GetValue());
	if (Value != DefaultInitial)
	{
		class'UniqueTraits_MCMSettings'.static.StoreValue('DefaultProbability', Value, class'UniqueTraits_TraitConfig'.static.GetIniDefaultTraitProbability());
		DefaultInitial = Value;
	}

	// "Default" erases the player's setting; a number stores it (even if it equals the current default weight).
	for (i = 0; i < TraitSpinners.Length; ++i)
	{
		Key = class'UniqueTraits_TraitConfig'.static.GetTraitProbabilityKey(TraitIndices[i]);
		DisabledKey = class'UniqueTraits_TraitConfig'.static.GetTraitDisabledKey(TraitIndices[i]);
		Selection = TraitSpinners[i].GetValue();

		// "Disabled": the trait is OFF (applies at the next launch); stored only if the mod's ini does not already say so. The weight the player had stays stored for the
		// day he enables the trait again. Any other option: enabled (stored only if the ini says disabled).
		class'UniqueTraits_MCMSettings'.static.StoreValue(DisabledKey, Selection == OptionDisabled ? 1 : 0, class'UniqueTraits_TraitConfig'.static.IsTraitDisabledByIni(TraitIndices[i]) ? 1 : 0);
		DisabledInitial[i] = Selection == OptionDisabled;
		if (Selection == OptionDisabled)
			continue;

		if (Selection == TraitDefaultLabel[i] && !TraitFollowsGlobal[i])
		{
			// "Default" on a trait that has a weight of its own in the mod's ini: the player wants the default weight instead of the ini's number: marker -1.
			class'UniqueTraits_MCMSettings'.static.SetOverride(Key, -1);
			TraitExtra[i] = -1;
		}
		else if (Selection == TraitDefaultLabel[i] || (!TraitFollowsGlobal[i] && int(Selection) == TraitOwn[i]))
		{
			// "Default" on a trait that follows the default weight, or the number the mod's ini gives a trait with its own weight: nothing to store.
			class'UniqueTraits_MCMSettings'.static.ClearOverride(Key);
			TraitExtra[i] = -1;
		}
		else
		{
			class'UniqueTraits_MCMSettings'.static.SetOverride(Key, int(Selection));
			TraitExtra[i] = int(Selection);
		}
	}

	class'UniqueTraits_MCMSettings'.static.Commit();
}

// Every widget back to the mod's ini value: "Default" for every trait, with the N of the mod's ini. Nothing is written until the player saves (saving then
// erases the player's choices).
simulated function ResetButtonClicked(MCM_API_SettingsPage Page)
{
	local int i;
	local string DefaultOption, Selection;

	AssignCheckbox.SetValue(class'UniqueTraits_TraitConfig'.default.ASSIGN_TRAIT_AT_RECRUITMENT, true);
	DefaultSlider.SetValue(class'UniqueTraits_TraitConfig'.static.GetIniDefaultTraitProbability(), true);

	for (i = 0; i < TraitSpinners.Length; ++i)
	{
		// "Default (N)" with the N of the mod's ini for a trait that follows the default weight; the ini's own number for the others (their "Default (N)" option
		// stays in the list).
		DefaultOption = DefaultOptionLabel(class'UniqueTraits_TraitConfig'.static.GetIniDefaultTraitProbability());
		Selection = TraitFollowsGlobal[i] ? DefaultOption : string(TraitOwn[i]);
		if (class'UniqueTraits_TraitConfig'.static.IsTraitDisabledByIni(TraitIndices[i]))
			Selection = OptionDisabled;
		TraitSpinners[i].SetOptions(BuildOptions(-1, TraitOwn[i], DefaultOption), Selection, true);
		TraitExtra[i] = -1;
		TraitDefaultLabel[i] = DefaultOption;
	}
}
