//---------------------------------------------------------------------------------------
//  FILE:   UniqueTraits_IniCache.uc
//  PURPOSE: The mod's ini value of each option of the Advanced page of the Mod Config Menu (UniqueTraits_MCMOptions), read once BEFORE the player's values are written into the
//           trait classes' defaults, so that "back to the ini" works while the game runs. Reached through UniqueTraits_MCMSettings (HasIniCached / CacheIni / GetIniCached).
//           Parallel arrays declared `config` ON PURPOSE: a plain (non-config) array of a class default is const in script ("Attempting to call 'AddItem' on const dynamic
//           array" throw a compile error), while a config one can be filled. Nothing ever calls StaticSaveConfig on this class, so it is never written to a file.
//---------------------------------------------------------------------------------------
class UniqueTraits_IniCache extends Object config(UniqueTraitsIniCache);

var config array<name> CachedKeys;
var config array<int> CachedValues;

static final function bool Has(name Key)
{
	return default.CachedKeys.Find(Key) != INDEX_NONE;
}

static final function Cache(name Key, int Value)
{
	if (Has(Key))
		return;

	default.CachedKeys.AddItem(Key);
	default.CachedValues.AddItem(Value);
}

static final function int Get(name Key)
{
	local int Index;

	Index = default.CachedKeys.Find(Key);
	if (Index == INDEX_NONE)
		return 0;

	return default.CachedValues[Index];
}
