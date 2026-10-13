//---------------------------------------------------------------------------------------
//  FILE:   UniqueTraits_MCMSettings.uc
//  PURPOSE: What the player changed in the Mod Config Menu page (UniqueTraits_MCMScreen), and ONLY that. Config(UniqueTraitsMCM) is
//           a file the mod does not ship (XComUniqueTraitsMCM.ini, created in the player's config folder when he saves), so the mod's own
//           XComUniqueTraits.ini stays the source of every default: a value the player did not touch follows the ini, a value he changed stays. A value saved
//           equal to the ini is not stored (StoreValue). Nothing here refers to Mod Config Menu: without it the list is simply empty, and the rest of the mod
//           reads it through UniqueTraits_TraitConfig (GetTraitProbability and the other accessors).
//---------------------------------------------------------------------------------------
class UniqueTraits_MCMSettings extends Object config(UniqueTraitsMCM);

struct MCMOverride
{
	var name OverrideKey;
	var int OverrideValue;
};

// A trait probability stored as a NEGATIVE value (-1) means "the player chose Default: use the default weight, not the mod's own number for that trait".
var config array<MCMOverride> Overrides;

// True and the player's value when he changed the setting OverrideKey.
static final function bool GetOverride(name OverrideKey, out int OverrideValue)
{
	local int Index;

	Index = default.Overrides.Find('OverrideKey', OverrideKey);
	if (Index == INDEX_NONE)
		return false;

	OverrideValue = default.Overrides[Index].OverrideValue;

	return true;
}

static final function SetOverride(name OverrideKey, int OverrideValue)
{
	local MCMOverride Entry;
	local int Index;

	Index = default.Overrides.Find('OverrideKey', OverrideKey);
	if (Index != INDEX_NONE)
	{
		default.Overrides[Index].OverrideValue = OverrideValue;
		return;
	}

	Entry.OverrideKey = OverrideKey;
	Entry.OverrideValue = OverrideValue;
	default.Overrides.AddItem(Entry);
}

static final function ClearOverride(name OverrideKey)
{
	local int Index;

	Index = default.Overrides.Find('OverrideKey', OverrideKey);
	if (Index != INDEX_NONE)
		default.Overrides.Remove(Index, 1);
}

// The player saved Value for OverrideKey: kept only if it differs from what the mod's ini gives (IniValue), else the setting follows the ini again.
// Commit() writes the file once everything is stored.
static final function StoreValue(name OverrideKey, int Value, int IniValue)
{
	if (Value == IniValue)
		ClearOverride(OverrideKey);
	else
		SetOverride(OverrideKey, Value);
}

// The mod's ini values of the options of the Advanced page (UniqueTraits_MCMOptions): read once, BEFORE the player's values are written into the class defaults,
// and kept in UniqueTraits_IniCache (never saved) so that "back to the ini" works while the game runs.
static final function bool HasIniCached(name OverrideKey)
{
	return class'UniqueTraits_IniCache'.static.Has(OverrideKey);
}

static final function CacheIni(name OverrideKey, int Value)
{
	class'UniqueTraits_IniCache'.static.Cache(OverrideKey, Value);
}

static final function int GetIniCached(name OverrideKey)
{
	return class'UniqueTraits_IniCache'.static.Get(OverrideKey);
}

static final function Commit()
{
	StaticSaveConfig();
}
