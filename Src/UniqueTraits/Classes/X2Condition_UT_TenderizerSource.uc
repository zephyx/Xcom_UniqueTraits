//---------------------------------------------------------------------------------------
//  FILE:   X2Condition_UT_TenderizerSource.uc
//  PURPOSE: Meat Tenderizer's switch between the original stun / disorient and its Tenderized twin. "Tenderizing" means: the effect's source holds
//           the trait AND the target is an enemy of that source. bRequireTenderizing = true keeps the twin effect for exactly that case, false
//           (put on the original effect) keeps the original effect for every other case.
//---------------------------------------------------------------------------------------
class X2Condition_UT_TenderizerSource extends X2Condition;

var bool bRequireTenderizing;

event name CallMeetsConditionWithSource(XComGameState_BaseObject kTarget, XComGameState_BaseObject kSource)
{
	local XComGameState_Unit SourceUnit, TargetUnit;
	local bool bTenderizing;

	SourceUnit = XComGameState_Unit(kSource);
	TargetUnit = XComGameState_Unit(kTarget);

	bTenderizing = SourceUnit != none && TargetUnit != none && SourceUnit.IsEnemyUnit(TargetUnit)
		&& class'X2DownloadableContentInfo_UniqueTraits'.static.UnitHasTrait(SourceUnit, 'UT_MeatTenderizer');

	if (bTenderizing == bRequireTenderizing)
		return 'AA_Success';

	return 'AA_AbilityUnavailable';
}
