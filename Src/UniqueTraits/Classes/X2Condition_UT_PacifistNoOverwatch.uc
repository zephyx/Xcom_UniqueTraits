//---------------------------------------------------------------------------------------
//  FILE:   X2Condition_UT_PacifistNoOverwatch.uc
//  PURPOSE: Shooter condition that Pacifist's OnPostTemplatesCreated adds to every ability that reserves overwatch points: a holder of the trait can
//           never use them.
//---------------------------------------------------------------------------------------
class X2Condition_UT_PacifistNoOverwatch extends X2Condition;

event name CallMeetsCondition(XComGameState_BaseObject kTarget)
{
	local XComGameState_Unit Unit;

	Unit = XComGameState_Unit(kTarget);
	if (Unit != none && class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(Unit, 'UT_Pacifist'))
		return 'AA_AbilityUnavailable';

	return 'AA_Success';
}
