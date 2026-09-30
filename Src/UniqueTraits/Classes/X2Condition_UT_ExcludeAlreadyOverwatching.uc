//---------------------------------------------------------------------------------------
//  FILE:   X2Condition_UT_ExcludeAlreadyOverwatching.uc
//  PURPOSE: Shooter condition for Always ready's UT_AlwaysReadyOverwatch. Without this, the
//           ability's X2Effect_ReserveOverwatchPoints (X2Effect_ReserveActionPoints.OnEffectAdded)
//           would unconditionally append a 2nd "overwatch" type entry to ReserveActionPoints
//           even if the unit already holds one (e.g. from manually activating vanilla
//           Overwatch earlier the same turn)
//---------------------------------------------------------------------------------------
class X2Condition_UT_ExcludeAlreadyOverwatching extends X2Condition;

event name CallMeetsCondition(XComGameState_BaseObject kTarget)
{
	local XComGameState_Unit TargetUnit;

	TargetUnit = XComGameState_Unit(kTarget);
	if (TargetUnit == none)
		return 'AA_NotAUnit';

	if (TargetUnit.ReserveActionPoints.Find(class'X2CharacterTemplateManager'.default.OverwatchReserveActionPoint) != INDEX_NONE)
		return 'AA_AbilityUnavailable';

	return 'AA_Success';
}
