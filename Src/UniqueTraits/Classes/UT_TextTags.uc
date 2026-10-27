//---------------------------------------------------------------------------------------
//  FILE:   UT_TextTags.uc
//  PURPOSE: The placeholders {VARIABLE} of the ability texts
//           (XComGame.int/.fra) are replaced by PatchTemplates (X2DownloadableContentInfo_UniqueTraits.OnPostTemplatesCreated, then each time the Advanced page of the Mod Config Menu is saved), with the value of a config
//           variable of a UT_Trait_<Name> class: the ini's, or the player's from the Mod Config Menu (UniqueTraits_MCMOptions.ApplyOverrides writes both into the class
//           default, before the templates are created). The placeholders that need a computation (Mind over matter, Security hacker) are answered by their trait
//           (GetTextValue). An option flagged R (baked into the templates) keeps its startup value in the texts until the next launch.
//---------------------------------------------------------------------------------------
class UT_TextTags extends Object config(UniqueTraitsTextCache);

// Session memory, declared `config` ON PURPOSE (a non-config array of a class default is const in script, see UniqueTraits_IniCache); nothing ever saves this class.
// - RawKeys / RawTexts: the text of an ability ("<Name>|L" long, "<Name>|H" help) or of a buff ("<Name>|T0|F"...) as it was loaded, with its {placeholders}; only the texts
//   that have one are kept, so that PatchTemplates can run again after the Mod Config Menu was saved.
// - FrozenKeys / FrozenValues: the value a placeholder had at startup, kept for the options baked into the templates when the game starts (flag R of the Advanced page,
//   FrozenOptionKeys = their keys): their text keeps the value the abilities really have until the next launch.
var config array<string> RawKeys, RawTexts;
var config array<string> FrozenKeys, FrozenValues, FrozenOptionKeys;

// A float without useless zeros ("1.5", "3"), with the decimal separator of the language (UniqueTraits.int/.fra, [UT_TextTags] DecimalSeparator).
static final function string FormatFloat(float Value)
{
	local int Scaled, Whole, Frac;
	local string Sign, FracText, Separator;

	Scaled = Round(Abs(Value) * 100.0);
	Whole = Scaled / 100;
	Frac = Scaled % 100;
	if (Value < 0.0 && Scaled != 0)
		Sign = "-";
	if (Frac == 0)
		return Sign $ string(Whole);

	FracText = (Frac < 10 ? "0" : "") $ string(Frac);
	if (Right(FracText, 1) == "0")
		FracText = Left(FracText, 1);

	Separator = Localize("UT_TextTags", "DecimalSeparator", "UniqueTraits");
	if (Separator == "" || Left(Separator, 2) == "<?")
		Separator = ".";

	return Sign $ string(Whole) $ Separator $ FracText;
}

// "+5/+5/+10" : the elements, each preceded by Prefix.
static final function string JoinInts(array<int> Values, string Prefix)
{
	local string Result;
	local int i;

	for (i = 0; i < Values.Length; ++i)
	{
		if (i > 0)
			Result $= "/";
		Result $= Prefix $ string(Values[i]);
	}

	return Result;
}

// "1/2/3" up to Count.
static final function string CountUp(int Count)
{
	local string Result;
	local int i;

	for (i = 1; i <= Count; ++i)
	{
		if (i > 1)
			Result $= "/";
		Result $= string(i);
	}

	return Result;
}

static final function int IntAt(array<int> Values, int Index)
{
	if (Index >= 0 && Index < Values.Length)
		return Values[Index];

	return 0;
}

// "+3" for a positive number, "-3" or "0" otherwise.
static final function string SignedInt(int Value)
{
	if (Value > 0)
		return "+" $ string(Value);

	return string(Value);
}

// Every {KEY} of Text becomes its value; an unknown key is left as it is (and logged).
static function string ReplaceTokens(string Text)
{
	local string Result, Key, Value;
	local int Start, CloseAt;

	while (true)
	{
		Start = InStr(Text, "{");
		if (Start == INDEX_NONE)
			break;

		CloseAt = InStr(Mid(Text, Start), "}");
		if (CloseAt == INDEX_NONE)
			break;

		Key = Mid(Text, Start + 1, CloseAt - 1);
		Result $= Left(Text, Start);
		if (ResolveValue(Key, Value))
		{
			Result $= Value;
		}
		else
		{
			`log("UniqueTraits [WARN] : unknown placeholder" @ Key @ "in a text",, 'UniqueTraits');
			Result $= "{" $ Key $ "}";
		}
		Text = Mid(Text, Start + CloseAt + 1);
	}

	return Result $ Text;
}

// The value of a placeholder: the current one, except for an option baked into the templates at startup (flag R), which keeps the value it had when the game started.
static function bool ResolveValue(string Key, out string OutString)
{
	local int Index;
	local string UpperKey;

	if (!IsFrozen(Key))
		return GetValue(Key, OutString);

	UpperKey = Caps(Key);
	Index = default.FrozenKeys.Find(UpperKey);
	if (Index != INDEX_NONE)
	{
		OutString = default.FrozenValues[Index];
		return true;
	}

	if (!GetValue(Key, OutString))
		return false;

	default.FrozenKeys.AddItem(UpperKey);
	default.FrozenValues.AddItem(OutString);

	return true;
}

// True when the placeholder is, or is made of, an option of the Advanced page flagged R (UniqueTraits_MCMOptions.GetRows): its key is the placeholder's, or the placeholder's
// followed by _<index> for an array.
static final function bool IsFrozen(string Key)
{
	local array<string> Rows, Parts;
	local string OptionKey, UpperKey, Prefix;
	local int i;

	if (default.FrozenOptionKeys.Length == 0)
	{
		Rows = class'UniqueTraits_MCMOptions'.static.GetRows();
		for (i = 0; i < Rows.Length; ++i)
		{
			ParseStringIntoArray(Rows[i], Parts, "|", false);
			if (Parts.Length > 6 && InStr(Parts[6], "R") != INDEX_NONE)
				default.FrozenOptionKeys.AddItem(Caps(Parts[0]));
		}
	}

	UpperKey = Caps(Key);
	Prefix = UpperKey $ "_";
	foreach default.FrozenOptionKeys(OptionKey)
	{
		if (OptionKey ~= UpperKey || Left(OptionKey, Len(Prefix)) ~= Prefix)
			return true;
	}

	return false;
}

// Current is the text now in the template; the first time (startup) it still holds its placeholders and is remembered under Key, later calls start again from the
// remembered text. A text without placeholder is left alone.
static final function string PatchText(string Key, string Current)
{
	local int Index;

	Index = default.RawKeys.Find(Key);
	if (Index != INDEX_NONE)
		return ReplaceTokens(default.RawTexts[Index]);

	if (InStr(Current, "{") == INDEX_NONE)
		return Current;

	default.RawKeys.AddItem(Key);
	default.RawTexts.AddItem(Current);

	return ReplaceTokens(Current);
}

// The placeholders of the texts of every ability of this mod, and of the buff descriptions its effects were given when the templates were created (they were copied from the
// raw text then). Called at startup, from OnPostTemplatesCreated, and again when the Advanced page of the Mod Config Menu is saved (the options flagged R keep their
// startup value).
static function PatchTemplates()
{
	local X2AbilityTemplateManager AbilityManager;
	local X2AbilityTemplate Template;
	local array<name> TemplateNames;
	local name TemplateName;
	local int Count;

	AbilityManager = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager();
	AbilityManager.GetTemplateNames(TemplateNames);
	foreach TemplateNames(TemplateName)
	{
		if (!(Left(string(TemplateName), 3) ~= "UT_"))
			continue;

		Template = AbilityManager.FindAbilityTemplate(TemplateName);
		if (Template == none)
			continue;

		Template.LocLongDescription = PatchText(string(TemplateName) $ "|L", Template.LocLongDescription);
		Template.LocHelpText = PatchText(string(TemplateName) $ "|H", Template.LocHelpText);
		PatchEffects(Template.AbilityTargetEffects, string(TemplateName) $ "|T");
		PatchEffects(Template.AbilityShooterEffects, string(TemplateName) $ "|S");
		PatchEffects(Template.AbilityMultiTargetEffects, string(TemplateName) $ "|M");
		++Count;
	}

	`log("UniqueTraits : placeholders of the texts replaced in" @ Count @ "abilities",, 'UniqueTraits');
}

static final function PatchEffects(array<X2Effect> Effects, string Prefix)
{
	local X2Effect_Persistent Persistent;
	local int i;

	for (i = 0; i < Effects.Length; ++i)
	{
		Persistent = X2Effect_Persistent(Effects[i]);
		if (Persistent == none)
			continue;

		Persistent.FriendlyDescription = PatchText(Prefix $ string(i) $ "|F", Persistent.FriendlyDescription);
		Persistent.SourceFriendlyDescription = PatchText(Prefix $ string(i) $ "|S", Persistent.SourceFriendlyDescription);
	}
}

// The value of the placeholder Key (any case), false when it is unknown.
static function bool GetValue(string Key, out string OutString)
{
	if (class'UT_Trait_MindOverMatter'.static.GetTextValue(Key, OutString))
		return true;
	if (class'UT_Trait_SecurityHacker'.static.GetTextValue(Key, OutString))
		return true;

	switch (name(Key))
	{
		case 'ATHLETE_MOBILITY': OutString = string(class'UT_Trait_Athlete'.default.ATHLETE_MOBILITY); return true;
		case 'ATHLETE_DODGE': OutString = string(class'UT_Trait_Athlete'.default.ATHLETE_DODGE); return true;
		case 'ATHLETE_AIM': OutString = string(class'UT_Trait_Athlete'.default.ATHLETE_AIM); return true;
		case 'ATHLETE_CRIT': OutString = string(class'UT_Trait_Athlete'.default.ATHLETE_CRIT); return true;
		case 'NERD_HACKING_BASE': OutString = string(class'UT_Trait_Nerd'.default.NERD_HACKING_BASE); return true;
		case 'NERD_HACKING_PER_RANK': OutString = string(class'UT_Trait_Nerd'.default.NERD_HACKING_PER_RANK); return true;
		case 'NERD_WILL_BASE': OutString = string(class'UT_Trait_Nerd'.default.NERD_WILL_BASE); return true;
		case 'NERD_WILL_PER_RANK': OutString = string(class'UT_Trait_Nerd'.default.NERD_WILL_PER_RANK); return true;
		case 'NERD_MELEE_DAMAGE_TAKEN': OutString = string(class'UT_Trait_Nerd'.default.NERD_MELEE_DAMAGE_TAKEN); return true;
		case 'GUARD_AIM': OutString = string(class'UT_Trait_Guard'.default.GUARD_AIM); return true;
		case 'GUARD_OVERWATCH_AIM': OutString = string(class'UT_Trait_Guard'.default.GUARD_OVERWATCH_AIM); return true;
		case 'PACIFIST_DEFENSE_BONUS': OutString = string(class'UT_Trait_Pacifist'.default.PACIFIST_DEFENSE_BONUS); return true;
		case 'PACIFIST_DODGE_BONUS': OutString = string(class'UT_Trait_Pacifist'.default.PACIFIST_DODGE_BONUS); return true;
		case 'PACIFIST_RADIUS_TILES': OutString = string(class'UT_Trait_Pacifist'.default.PACIFIST_RADIUS_TILES); return true;
		case 'PACIFIST_COOLDOWN': OutString = string(class'UT_Trait_Pacifist'.default.PACIFIST_COOLDOWN); return true;
		case 'BASEBALL_EXPLOSIVE_DAMAGE_REDUCTION': OutString = string(class'UT_Trait_BaseballPlayer'.default.BASEBALL_EXPLOSIVE_DAMAGE_REDUCTION); return true;
		case 'BASEBALL_BOMBARD_RANGE': OutString = string(class'UT_Trait_BaseballPlayer'.default.BASEBALL_BOMBARD_RANGE); return true;
		case 'ALLINARMS_THROW_RANGE': OutString = string(class'UT_Trait_AllInArms'.default.ALLINARMS_THROW_RANGE); return true;
		case 'ALLINARMS_MOBILITY': OutString = string(class'UT_Trait_AllInArms'.default.ALLINARMS_MOBILITY); return true;
		case 'DISCREET_DETECTION_MULT': OutString = string(Round((1.0 - class'UT_Trait_Discreet'.default.DISCREET_DETECTION_MULT) * 100.0)); return true;
		case 'DISCREET_PRIMARY_WEAPON_DAMAGE_REDUCTION': OutString = string(class'UT_Trait_Discreet'.default.DISCREET_PRIMARY_WEAPON_DAMAGE_REDUCTION); return true;
		case 'ACROBAT_AIM_PENALTY': OutString = string(class'UT_Trait_Acrobat'.default.ACROBAT_AIM_PENALTY); return true;
		case 'ACROBAT_CRIT_PENALTY': OutString = string(class'UT_Trait_Acrobat'.default.ACROBAT_CRIT_PENALTY); return true;
		case 'QUICKHEALING_DAMAGE_TAKEN_MULT': OutString = string(Round((class'UT_Trait_QuickHealing'.default.QUICKHEALING_DAMAGE_TAKEN_MULT - 1.0) * 100.0)); return true;
		case 'THIEF_STEAL_CHANCE_PCT': OutString = string(class'UT_Trait_Thief'.default.THIEF_STEAL_CHANCE_PCT); return true;
		case 'JACKOFALLTRADES_AP_BONUS': OutString = string(class'UT_Trait_JackOfAllTrades'.default.JACKOFALLTRADES_AP_BONUS); return true;
		case 'TACTICIAN_AIM': OutString = string(class'UT_Trait_Tactician'.default.TACTICIAN_AIM); return true;
		case 'SCOUT_SCANNER_RANGE_MULT': OutString = string(Round((class'UT_Trait_Scout'.default.SCOUT_SCANNER_RANGE_MULT - 1.0) * 100.0)); return true;
		case 'SCOUT_SIGHT_RADIUS_PENALTY': OutString = string(class'UT_Trait_Scout'.default.SCOUT_SIGHT_RADIUS_PENALTY); return true;
		case 'SUPPORT_MOBILITY_BONUS': OutString = string(class'UT_Trait_Support'.default.SUPPORT_MOBILITY_BONUS); return true;
		case 'MANIAC_EXTRA_GRENADE_POCKETS': OutString = string(class'UT_Trait_ManiacExplosive'.default.MANIAC_EXTRA_GRENADE_POCKETS); return true;
		case 'MANIAC_PRIMARY_WEAPON_DAMAGE_REDUCTION_PCT': OutString = string(class'UT_Trait_ManiacExplosive'.default.MANIAC_PRIMARY_WEAPON_DAMAGE_REDUCTION_PCT); return true;
		case 'MANIAC_IMPROVISE_COOLDOWN': OutString = string(class'UT_Trait_ManiacExplosive'.default.MANIAC_IMPROVISE_COOLDOWN); return true;
		case 'MANIAC_IMPROVISE_CHARGES': OutString = string(class'UT_Trait_ManiacExplosive'.default.MANIAC_IMPROVISE_CHARGES); return true;
		case 'BRIBE_SUPPLY_BONUS': OutString = string(class'UT_Trait_Bribe'.default.BRIBE_SUPPLY_BONUS); return true;
		case 'STAYFOCUS_WILL_LOSS': OutString = string(class'UT_Trait_StayFocus'.default.STAYFOCUS_WILL_LOSS); return true;
		case 'STAYFOCUS_AIM_BONUS': OutString = string(class'UT_Trait_StayFocus'.default.STAYFOCUS_AIM_BONUS); return true;
		case 'STAYFOCUS_CRIT_BONUS': OutString = string(class'UT_Trait_StayFocus'.default.STAYFOCUS_CRIT_BONUS); return true;
		case 'STAYFOCUS_RADIUS_TILES': OutString = string(class'UT_Trait_StayFocus'.default.STAYFOCUS_RADIUS_TILES); return true;
		case 'STAYFOCUS_COOLDOWN': OutString = string(class'UT_Trait_StayFocus'.default.STAYFOCUS_COOLDOWN); return true;
		case 'SELFREINFORCEMENT_DURATION_PCT': OutString = string(class'UT_Trait_SelfReinforcement'.default.SELFREINFORCEMENT_DURATION_PCT); return true;
		case 'SELFREINFORCEMENT_STAT_MULT': OutString = FormatFloat(class'UT_Trait_SelfReinforcement'.default.SELFREINFORCEMENT_STAT_MULT); return true;
		case 'RELIABLE_CRIT_TO_AIM_DIVISOR': OutString = string(class'UT_Trait_Reliable'.default.RELIABLE_CRIT_TO_AIM_DIVISOR); return true;
		case 'RELIABLE_DODGE_REDUCTION_PCT': OutString = string(class'UT_Trait_Reliable'.default.RELIABLE_DODGE_REDUCTION_PCT); return true;
		case 'APOTHECARY_HP_MALUS': OutString = string(class'UT_Trait_Apothecary'.default.APOTHECARY_HP_MALUS); return true;
		case 'APOTHECARY_MIN_HP': OutString = string(class'UT_Trait_Apothecary'.default.APOTHECARY_MIN_HP); return true;
		case 'APOTHECARY_RECOVERY_PCT': OutString = string(class'UT_Trait_Apothecary'.default.APOTHECARY_RECOVERY_PCT); return true;
		case 'SMOKER_GRENADE_COUNT': OutString = string(class'UT_Trait_Smoker'.default.SMOKER_GRENADE_COUNT); return true;
		case 'SMOKER_WILL_REGEN': OutString = string(class'UT_Trait_Smoker'.default.SMOKER_WILL_REGEN); return true;
		case 'BORNTOBECHIEF_AIM_DODGE_WILL_BASE': OutString = string(class'UT_Trait_BornToBeChief'.default.BORNTOBECHIEF_AIM_DODGE_WILL_BASE); return true;
		case 'BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK': OutString = string(class'UT_Trait_BornToBeChief'.default.BORNTOBECHIEF_AIM_DODGE_WILL_PER_RANK); return true;
		case 'SWORDSMAN_MELEE_BONUS_BY_TIER': OutString = JoinInts(class'UT_Trait_Swordsman'.default.SWORDSMAN_MELEE_BONUS_BY_TIER, "+"); return true;
		case 'SWORDSMAN_FIREARM_DAMAGE_REDUCTION': OutString = string(class'UT_Trait_Swordsman'.default.SWORDSMAN_FIREARM_DAMAGE_REDUCTION); return true;
		case 'HUNTER_CONCEALED_SIGHT_BONUS': OutString = string(class'UT_Trait_Hunter'.default.HUNTER_CONCEALED_SIGHT_BONUS); return true;
		case 'HUNTER_DETECTION_MODIFIER': OutString = string(Round(-class'UT_Trait_Hunter'.default.HUNTER_DETECTION_MODIFIER * 10.0)); return true;
		case 'FALSEHOPE_XP_REDUCTION_PCT': OutString = string(class'UT_Trait_FalseHope'.default.FALSEHOPE_XP_REDUCTION_PCT); return true;
		case 'FALSEHOPE_AIM_BASE': OutString = string(class'UT_Trait_FalseHope'.default.FALSEHOPE_AIM_BASE); return true;
		case 'FALSEHOPE_HP_BASE': OutString = FormatFloat(class'UT_Trait_FalseHope'.default.FALSEHOPE_HP_BASE); return true;
		case 'FALSEHOPE_AIM_PER_RANK': OutString = FormatFloat(class'UT_Trait_FalseHope'.default.FALSEHOPE_AIM_PER_RANK); return true;
		case 'FALSEHOPE_HP_PER_RANK': OutString = FormatFloat(class'UT_Trait_FalseHope'.default.FALSEHOPE_HP_PER_RANK); return true;
		case 'FALSEHOPE_HP_FLOOR': OutString = FormatFloat(class'UT_Trait_FalseHope'.default.FALSEHOPE_HP_FLOOR); return true;
		case 'LONGRANGE_FAR_RANGE_SHIFT': OutString = string(class'UT_Trait_LongRange'.default.LONGRANGE_FAR_RANGE_SHIFT); return true;
		case 'LONGRANGE_CLOSE_RANGE_AIM_PENALTY': OutString = JoinInts(class'UT_Trait_LongRange'.default.LONGRANGE_CLOSE_RANGE_AIM_PENALTY, "-"); return true;
		case 'LONGRANGE_CLOSE_RANGE_AIM_PENALTY_COUNT': OutString = string(class'UT_Trait_LongRange'.default.LONGRANGE_CLOSE_RANGE_AIM_PENALTY.Length); return true;
		case 'LONGRANGE_CLOSE_RANGE_AIM_PENALTY_TILES': OutString = CountUp(class'UT_Trait_LongRange'.default.LONGRANGE_CLOSE_RANGE_AIM_PENALTY.Length); return true;
		case 'QUALITY_CRIT_BY_TIER': OutString = JoinInts(class'UT_Trait_QualityOverQuantity'.default.QUALITY_CRIT_BY_TIER, "+"); return true;
		case 'QUALITY_CLIP_REDUCTION': OutString = string(class'UT_Trait_QualityOverQuantity'.default.QUALITY_CLIP_REDUCTION); return true;
		case 'QUALITY_CLIP_MIN_FOR_REDUCTION': OutString = string(class'UT_Trait_QualityOverQuantity'.default.QUALITY_CLIP_MIN_FOR_REDUCTION); return true;
		case 'BOUNTYHUNTER_SUPPLY_PER_KILL': OutString = string(class'UT_Trait_BountyHunter'.default.BOUNTYHUNTER_SUPPLY_PER_KILL); return true;
		case 'BOUNTYHUNTER_NO_XP_CHANCE_PCT': OutString = string(class'UT_Trait_BountyHunter'.default.BOUNTYHUNTER_NO_XP_CHANCE_PCT); return true;
		case 'CYBORG_UPGRADE_CHANCE_PCT': OutString = string(class'UT_Trait_Cyborg'.default.CYBORG_UPGRADE_CHANCE_PCT); return true;
		case 'RECRUITER_DODGE_MALUS': OutString = string(class'UT_Trait_Recruiter'.default.RECRUITER_DODGE_MALUS); return true;
		case 'RECRUITER_RECRUIT_CHANCE_FACTOR': OutString = string(Round(class'UT_Trait_Recruiter'.default.RECRUITER_RECRUIT_CHANCE_FACTOR * 100.0)); return true;
		case 'RECRUITER_ROOKIE_CHANCE_FACTOR': OutString = string(Round(class'UT_Trait_Recruiter'.default.RECRUITER_ROOKIE_CHANCE_FACTOR * 100.0)); return true;
		case 'YOUNGDOCTOR_HEAL_REDUCTION_PCT': OutString = string(class'UT_Trait_YoungDoctor'.default.YOUNGDOCTOR_HEAL_REDUCTION_PCT); return true;
		case 'YOUNGDOCTOR_XP_PER_TREATMENT': OutString = FormatFloat(class'UT_Trait_YoungDoctor'.default.YOUNGDOCTOR_XP_PER_TREATMENT); return true;
		case 'YOUNGDOCTOR_STABILIZE_XP_MULT': OutString = FormatFloat(class'UT_Trait_YoungDoctor'.default.YOUNGDOCTOR_STABILIZE_XP_MULT); return true;
		case 'PSIADEPT_PSI_PER_PIERCE': OutString = string(class'UT_Trait_PsiAdept'.default.PSIADEPT_PSI_PER_PIERCE); return true;
		case 'PSIADEPT_PSI_PER_DAMAGE': OutString = string(class'UT_Trait_PsiAdept'.default.PSIADEPT_PSI_PER_DAMAGE); return true;
		case 'PSIADEPT_ROBOTIC_DAMAGE_REDUCTION_PCT': OutString = string(class'UT_Trait_PsiAdept'.default.PSIADEPT_ROBOTIC_DAMAGE_REDUCTION_PCT); return true;
		case 'GIVEMEMORE_DEFENSE_MALUS': OutString = string(class'UT_Trait_GiveMeMore'.default.GIVEMEMORE_DEFENSE_MALUS); return true;
		case 'GIVEMEMORE_DODGE_BONUS': OutString = string(class'UT_Trait_GiveMeMore'.default.GIVEMEMORE_DODGE_BONUS); return true;
		case 'GIVEMEMORE_WOUND_HP_REDUCTION': OutString = string(class'UT_Trait_GiveMeMore'.default.GIVEMEMORE_WOUND_HP_REDUCTION); return true;
		case 'CHEMIST_AIM_MALUS': OutString = string(class'UT_Trait_Chemist'.default.CHEMIST_AIM_MALUS); return true;
		case 'CHEMIST_DAMAGE_MALUS': OutString = string(class'UT_Trait_Chemist'.default.CHEMIST_DAMAGE_MALUS); return true;
		case 'CHEMIST_DISEASE_TURNS': OutString = string(class'UT_Trait_Chemist'.default.CHEMIST_DISEASE_TURNS); return true;
		case 'CHEMIST_DOT_DAMAGE_BONUS': OutString = string(class'UT_Trait_Chemist'.default.CHEMIST_DOT_DAMAGE_BONUS); return true;
		case 'PSYCHICBOND_SHARED_DAMAGE_PCT': OutString = string(class'UT_Trait_PsychicBond'.default.PSYCHICBOND_SHARED_DAMAGE_PCT); return true;
		case 'LASERDESIGNATOR_COOLDOWN': OutString = string(class'UT_Trait_LaserDesignator'.default.LASERDESIGNATOR_COOLDOWN); return true;
		case 'LASERDESIGNATOR_DODGE_BONUS': OutString = string(class'UT_Trait_LaserDesignator'.default.LASERDESIGNATOR_DODGE_BONUS); return true;
		case 'LASERDESIGNATOR_HOLOTARGET_COOLDOWN_REDUCTION': OutString = string(class'UT_Trait_LaserDesignator'.default.LASERDESIGNATOR_HOLOTARGET_COOLDOWN_REDUCTION); return true;
		case 'SECURITYHACKER_DEFENSE_PCT_LOW': OutString = string(class'UT_Trait_SecurityHacker'.default.SECURITYHACKER_DEFENSE_PCT_LOW); return true;
		case 'SECURITYHACKER_DEFENSE_PCT_MID': OutString = string(class'UT_Trait_SecurityHacker'.default.SECURITYHACKER_DEFENSE_PCT_MID); return true;
		case 'SECURITYHACKER_DEFENSE_PCT_HIGH': OutString = string(class'UT_Trait_SecurityHacker'.default.SECURITYHACKER_DEFENSE_PCT_HIGH); return true;
		case 'SECURITYHACKER_FORCE_LEVEL_MID': OutString = string(class'UT_Trait_SecurityHacker'.default.SECURITYHACKER_FORCE_LEVEL_MID); return true;
		case 'SECURITYHACKER_FORCE_LEVEL_HIGH': OutString = string(class'UT_Trait_SecurityHacker'.default.SECURITYHACKER_FORCE_LEVEL_HIGH); return true;
		case 'SECURITYHACKER_FAILURE_DAMAGE_PCT': OutString = string(class'UT_Trait_SecurityHacker'.default.SECURITYHACKER_FAILURE_DAMAGE_PCT); return true;
		case 'SECURITYHACKER_AP_REWARD_LATE': OutString = string(class'UT_Trait_SecurityHacker'.default.SECURITYHACKER_AP_REWARD_LATE); return true;
		case 'SECURITYHACKER_LATE_TURN': OutString = string(class'UT_Trait_SecurityHacker'.default.SECURITYHACKER_LATE_TURN); return true;
		case 'NEMESIS_AIM_PER_KILL': OutString = string(class'UT_Trait_Nemesis'.default.NEMESIS_AIM_PER_KILL); return true;
		case 'NEMESIS_MAX_AIM': OutString = string(class'UT_Trait_Nemesis'.default.NEMESIS_MAX_AIM); return true;
		case 'NEMESIS_DEFENSE_PER_KILL': OutString = string(class'UT_Trait_Nemesis'.default.NEMESIS_DEFENSE_PER_KILL); return true;
		case 'NEMESIS_MAX_DEFENSE': OutString = string(class'UT_Trait_Nemesis'.default.NEMESIS_MAX_DEFENSE); return true;
		case 'MEATTENDERIZER_AIM_BONUS': OutString = string(class'UT_Trait_MeatTenderizer'.default.MEATTENDERIZER_AIM_BONUS); return true;
		case 'MEATTENDERIZER_CRIT_BONUS': OutString = string(class'UT_Trait_MeatTenderizer'.default.MEATTENDERIZER_CRIT_BONUS); return true;
		case 'MEATTENDERIZER_MOBILITY_MALUS': OutString = string(class'UT_Trait_MeatTenderizer'.default.MEATTENDERIZER_MOBILITY_MALUS); return true;
		case 'MEATTENDERIZER_SLIGHT_AIM_BONUS': OutString = string(class'UT_Trait_MeatTenderizer'.default.MEATTENDERIZER_SLIGHT_AIM_BONUS); return true;
		case 'MEATTENDERIZER_SLIGHT_CRIT_BONUS': OutString = string(class'UT_Trait_MeatTenderizer'.default.MEATTENDERIZER_SLIGHT_CRIT_BONUS); return true;
		case 'MEATTENDERIZER_SLIGHT_MOBILITY_MALUS': OutString = string(class'UT_Trait_MeatTenderizer'.default.MEATTENDERIZER_SLIGHT_MOBILITY_MALUS); return true;
		case 'SHREDDER_ACID_TICK_BONUS': OutString = string(class'UT_Trait_Shredder'.default.SHREDDER_ACID_TICK_BONUS); return true;
		case 'SHREDDER_UNARMORED_DAMAGE_MALUS_PCT': OutString = string(class'UT_Trait_Shredder'.default.SHREDDER_UNARMORED_DAMAGE_MALUS_PCT); return true;
		case 'SOMEONEDIFFERENT_PCT_LOW_0': OutString = SignedInt(IntAt(class'UT_Trait_SomeoneDifferent'.default.SOMEONEDIFFERENT_PCT_LOW, 0)); return true;
		case 'SOMEONEDIFFERENT_PCT_HIGH_0': OutString = SignedInt(IntAt(class'UT_Trait_SomeoneDifferent'.default.SOMEONEDIFFERENT_PCT_HIGH, 0)); return true;
		case 'MIN_MAX_WILL': OutString = string(class'UniqueTraits_TraitConfig'.default.MIN_MAX_WILL); return true;
	}

	return false;
}
