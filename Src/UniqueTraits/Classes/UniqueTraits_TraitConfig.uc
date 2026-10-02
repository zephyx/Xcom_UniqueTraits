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
	var bool bEnabled;                 // set to false in ini to disable this trait without deleting it
};

var config array<UniqueTraitDefinition> Traits;
var localized string JackOfAllTradesLockedReason;

static final function bool IsTraitEligible(int Index)
{
	local name RequiredMod;

	if (Index < 0 || Index >= default.Traits.Length)
		return false;

	if (!default.Traits[Index].bEnabled)
		return false;

	foreach default.Traits[Index].RequiredMods(RequiredMod)
	{
		if (!IsModActive(RequiredMod))
			return false;
	}

	// Support's vest slot is only meaningful if some active content actually provides a genuine
	// vest-type item for it to hold : base XCOM 2 WOTC provides none, same as it never grants
	// GTS options tied to absent content. See X2ItemSlot_UniqueTraits.AnyVestItemTemplateExists.
	if (default.Traits[Index].TraitID == 'UT_Support' && !class'X2ItemSlot_UniqueTraits'.static.AnyVestItemTemplateExists())
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
