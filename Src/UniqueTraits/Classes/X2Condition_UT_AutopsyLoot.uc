//---------------------------------------------------------------------------------------
//  FILE:   X2Condition_UT_AutopsyLoot.uc
//  PURPOSE: Added (UT_Trait_Coroner.OnPostTemplatesCreated) to the multi-target conditions of every ability that loots by area (the base game's Loot): an autopsy zone is a valid
//           target only for the Coroner. The base game's own multi-target condition (X2Condition_Lootable.CallMeetsCondition) only asks whether the zone HAS loot, not whether THIS
//           looter can take it, so any soldier who looted an ordinary corpse near a blue zone got the zone in his loot action and an empty loot window for it.
//---------------------------------------------------------------------------------------
class X2Condition_UT_AutopsyLoot extends X2Condition;

event name CallMeetsConditionWithSource(XComGameState_BaseObject kTarget, XComGameState_BaseObject kSource)
{
	local XComGameState_LootDrop Drop;
	local XComGameState_Unit Looter;

	Drop = XComGameState_LootDrop(kTarget);
	if (Drop == none || !class'UT_Trait_Coroner'.static.IsAutopsyDrop(Drop))
		return 'AA_Success';

	Looter = XComGameState_Unit(kSource);
	if (Looter != none && class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Looter, 'UT_Coroner'))
		return 'AA_Success';

	return 'AA_TargetHasNoLoot';
}
