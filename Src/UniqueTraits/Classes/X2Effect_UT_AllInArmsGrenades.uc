//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_AllInArmsGrenades.uc
//  PURPOSE: All in arms' free flashbangs: the temporary item effect (X2Effect_UT_TemporaryItem), with a number that depends on the holder's rank at the start of the
//           mission: ALLINARMS_FLASHBANG_COUNT, or ALLINARMS_FLASHBANG_COUNT_STAFF from the rank ALLINARMS_STAFF_RANK. Read from the trait's class defaults when the
//           mission starts (not copied into the effect), so the Mod Config Menu values apply at once.
//---------------------------------------------------------------------------------------
class X2Effect_UT_AllInArmsGrenades extends X2Effect_UT_TemporaryItem;

function int GetGrantCount(XComGameState_Unit UnitState)
{
	if (UnitState.GetRank() >= class'UT_Trait_AllInArms'.default.ALLINARMS_STAFF_RANK)
		return Max(class'UT_Trait_AllInArms'.default.ALLINARMS_FLASHBANG_COUNT_STAFF, 0);

	return Max(class'UT_Trait_AllInArms'.default.ALLINARMS_FLASHBANG_COUNT, 0);
}
