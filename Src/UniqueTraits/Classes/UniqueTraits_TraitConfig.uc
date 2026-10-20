//---------------------------------------------------------------------------------------
//  FILE:   UniqueTraits_TraitConfig.uc
//  PURPOSE: Declares the pool of unique traits (Config/XComUniqueTraits.ini) and small
//           shared helpers (mod-dependency detection, trait lookup) used by the rest of
//           the mod.
//---------------------------------------------------------------------------------------
class UniqueTraits_TraitConfig extends Object config(UniqueTraits);

struct UniqueTraitDefinition
{
	var name TraitID;                  // stable id, used in logs/localization lookups
	var array<name> GrantedAbilities;  // ability template names added via AWCAbilities (GrantTraitToUnit)
	var array<name> RequiredMods;      // DLCNames that must ALL be active for this trait to be eligible;
	                                    // used for any mod this trait needs to work as designed (LWOTC,
	                                    // Community Promotion Screen, etc.) -- not just LWOTC specifically.
	                                    // Leave empty for traits with no dependency.
	var int Probability;               // optional: the weight of this trait in the draw (relative to the others). Omitted = DEFAULT_TRAIT_PROBABILITY.
	                                    // Probability=0 disables the trait without deleting it. An omitted field reads -1 (structdefaultproperties below, which
	                                    // an ini line inherits), so "omitted" and "0" differ.

	structdefaultproperties
	{
		Probability=-1
	}
};

var config array<UniqueTraitDefinition> Traits;

// The weight of a trait that gives no Probability of its own. A trait is drawn with a chance proportional to its weight among the traits still
// available (not carried by a living soldier, mods present, IsEligible): weight 10 against 2 = 5 times more likely.
var config int DEFAULT_TRAIT_PROBABILITY;

// false (default): a rookie gets its trait when it can choose a class (mission / covert action, AssignTraitsToEligibleRookies). true: as soon as it
// is a rookie of the roster (recruit, starting soldier...), see X2DownloadableContentInfo_UniqueTraits.IsRookieEligibleForTrait.
var config bool ASSIGN_TRAIT_AT_RECRUITMENT;

// Not an option, a note kept in memory (never read from nor written to a file): the ObjectIDs of the holders whose stats are being rebuilt by the console mod [WOTC] Additional Soldier Console Commands
// ResetSelectedSoldiersClass, noted by the event 'UnitRandomizedStats' (X2EventListener_UniqueTraits.OnUnitRandomizedStats_StatsWiped) and used by
// UT_TraitBase.WasRespecSinceLastShift to tell its "Reset Soldier" state from the one of RebuildSelectedSoldiersClass (which keeps the stats). The event's unit is NOT the
// pending copy that gets submitted (it showed the stale rank and stats), so nothing can be written into it: a config array, whose default may be changed at run time, is
// the only place a static function can write.
var config array<int> RESET_UNIT_IDS;

static final function NoteUnitRandomized(int UnitID)
{
	if (default.RESET_UNIT_IDS.Find(UnitID) == INDEX_NONE)
		default.RESET_UNIT_IDS.AddItem(UnitID);
}

static final function bool IsUnitRandomized(int UnitID)
{
	return default.RESET_UNIT_IDS.Find(UnitID) != INDEX_NONE;
}

static final function ForgetUnitRandomized(int UnitID)
{
	default.RESET_UNIT_IDS.RemoveItem(UnitID);
}

// ---- The settings the player may have changed in the Mod Config Menu (UniqueTraits_MCMSettings, only the changed ones). Without Mod Config Menu there is none
// and these accessors give the mod's ini values.

// The key of a trait's probability in UniqueTraits_MCMSettings.
static final function name GetTraitProbabilityKey(int Index)
{
	return name("P_" $ default.Traits[Index].TraitID);
}

// DEFAULT_TRAIT_PROBABILITY in the ini, ignoring the player's choice.
static final function int GetIniDefaultTraitProbability()
{
	return Max(0, default.DEFAULT_TRAIT_PROBABILITY);
}

// The weight of a trait that gives no Probability of its own: the player's, else the ini's.
static final function int GetDefaultTraitProbability()
{
	local int Value;

	if (class'UniqueTraits_MCMSettings'.static.GetOverride('DefaultProbability', Value))
		return Max(0, Value);

	return GetIniDefaultTraitProbability();
}

// ASSIGN_TRAIT_AT_RECRUITMENT: the player's choice, else the ini's.
static final function bool ShouldAssignAtRecruitment()
{
	local int Value;

	if (class'UniqueTraits_MCMSettings'.static.GetOverride('AssignAtRecruitment', Value))
		return Value != 0;

	return default.ASSIGN_TRAIT_AT_RECRUITMENT;
}

// True when the trait's ini line gives a Probability of its own (so its weight does not follow the default weight).
static final function bool HasOwnProbability(int Index)
{
	return Index >= 0 && Index < default.Traits.Length && default.Traits[Index].Probability >= 0;
}

// The weight of the trait at Index as the mod's ini gives it (its own Probability, else the ini's default weight), ignoring the player's choices.
static final function int GetIniTraitProbability(int Index)
{
	local int Value;

	if (Index < 0 || Index >= default.Traits.Length)
		return 0;

	Value = default.Traits[Index].Probability;
	if (Value < 0)
		return GetIniDefaultTraitProbability();

	return Value;
}

// The weight of the trait at Index in the draw: the player's value for this trait, else its own Probability in the ini (0 = disabled), else the default
// weight (the player's, else the ini's) when the ini line gives none (negative).
static final function int GetTraitProbability(int Index)
{
	local int Value;

	if (Index < 0 || Index >= default.Traits.Length)
		return 0;

	if (class'UniqueTraits_MCMSettings'.static.GetOverride(GetTraitProbabilityKey(Index), Value))
	{
		// The player's value; a NEGATIVE one (-1) is his choice "Default": the default weight, whatever the mod's ini gives that trait (Someone different has 2).
		if (Value < 0)
			return GetDefaultTraitProbability();

		return Max(0, Value);
	}

	Value = default.Traits[Index].Probability;
	if (Value < 0)
		return GetDefaultTraitProbability();

	return Value;
}

// All the mods the trait needs are loaded (a trait without RequiredMods always is).
static final function bool AreRequiredModsActive(int Index)
{
	local name RequiredMod;

	if (Index < 0 || Index >= default.Traits.Length)
		return false;

	foreach default.Traits[Index].RequiredMods(RequiredMod)
	{
		if (!IsModActive(RequiredMod))
			return false;
	}

	return true;
}

static final function bool IsTraitEligible(int Index)
{
	local class<UT_TraitBase> TraitClass;

	if (Index < 0 || Index >= default.Traits.Length)
		return false;

	if (GetTraitProbability(Index) <= 0)
		return false;   // disabled (Probability=0)

	if (!AreRequiredModsActive(Index))
		return false;

	// The trait's own extra condition (e.g. Support needs at least one item its vest slot accepts).
	TraitClass = GetTraitClass(default.Traits[Index].TraitID);
	if (TraitClass != none && !TraitClass.static.IsEligible())
		return false;

	return true;
}

static final function int FindTraitIndexByID(name TraitID)
{
	local int i;

	for (i = 0; i < default.Traits.Length; ++i)
	{
		if (default.Traits[i].TraitID == TraitID)
			return i;
	}

	return INDEX_NONE;
}

// The per-trait class holding a trait's grant/clear/rank-up hooks: "UT_Nerd" -> UT_Trait_Nerd. None for a
// trait that has no class of its own (yet), callers must tolerate that.
static final function class<UT_TraitBase> GetTraitClass(name TraitID)
{
	return class<UT_TraitBase>(DynamicLoadObject("UniqueTraits.UT_Trait_" $ Mid(string(TraitID), 3), class'Class', true));
}

// Checked against the list of currently loaded/active DLC packages rather than merely
// "installed". DLCName is the mod's .XComMod base filename,
// NOT its DLCIdentifier (e.g. LWOTC = 'LongWarOfTheChosen', Community Promotion Screen =
// 'X2WOTCCommunityPromotionScreen' -- verified against their actual .XComMod files).
static final function bool IsModActive(name DLCName)
{
	local int i;

	for (i = `ONLINEEVENTMGR.GetNumDLC() - 1; i >= 0; --i)
	{
		if (`ONLINEEVENTMGR.GetDLCNames(i) == DLCName)
			return true;
	}

	return false;
}
