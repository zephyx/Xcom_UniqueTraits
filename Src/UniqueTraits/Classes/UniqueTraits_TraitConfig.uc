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

// The weight of the trait at Index in the draw: its own Probability (0 = disabled), DEFAULT_TRAIT_PROBABILITY when the ini line gives none (negative).
static final function int GetTraitProbability(int Index)
{
	local int Value;

	if (Index < 0 || Index >= default.Traits.Length)
		return 0;

	Value = default.Traits[Index].Probability;
	if (Value < 0)
		return Max(0, default.DEFAULT_TRAIT_PROBABILITY);

	return Value;
}

static final function bool IsTraitEligible(int Index)
{
	local name RequiredMod;
	local class<UT_TraitBase> TraitClass;

	if (Index < 0 || Index >= default.Traits.Length)
		return false;

	if (GetTraitProbability(Index) <= 0)
		return false;   // disabled (Probability=0)

	foreach default.Traits[Index].RequiredMods(RequiredMod)
	{
		if (!IsModActive(RequiredMod))
			return false;
	}

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
