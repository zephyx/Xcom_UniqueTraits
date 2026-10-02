//---------------------------------------------------------------------------------------
//  FILE:   X2Condition_UT_ExcludeAlreadyOverwatching.uc
//  PURPOSE: Shooter condition for Always ready's UT_AlwaysReadyOverwatch. Without this, the
//           ability's X2Effect_ReserveOverwatchPoints (X2Effect_ReserveActionPoints.OnEffectAdded)
//           would unconditionally append a 2nd "overwatch" type entry to ReserveActionPoints
//           even if the unit already holds one (e.g. from manually activating vanilla
//           Overwatch earlier the same turn). Also requires ammo in the primary weapon (replaces
//           an X2AbilityCost_Ammo, which can't work without a source weapon).
//---------------------------------------------------------------------------------------
class X2Condition_UT_ExcludeAlreadyOverwatching extends X2Condition;

event name CallMeetsCondition(XComGameState_BaseObject kTarget)
{
	local XComGameState_Unit TargetUnit;
	local XComGameState_Item PrimaryWeapon;

	TargetUnit = XComGameState_Unit(kTarget);
	if (TargetUnit == none)
		return 'AA_NotAUnit';

	// Same "don't arm with an empty weapon" gate vanilla Overwatch gets from its ammo cost.
	PrimaryWeapon = TargetUnit.GetPrimaryWeapon();
	if (PrimaryWeapon == none || PrimaryWeapon.Ammo <= 0)
		return 'AA_AbilityUnavailable';

	if (TargetUnit.ReserveActionPoints.Find(class'X2CharacterTemplateManager'.default.OverwatchReserveActionPoint) != INDEX_NONE)
		return 'AA_AbilityUnavailable';

	return 'AA_Success';
}
