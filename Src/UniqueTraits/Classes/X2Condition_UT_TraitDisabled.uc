//---------------------------------------------------------------------------------------
//  FILE:   X2Condition_UT_TraitDisabled.uc
//  PURPOSE: Shooter condition that X2DownloadableContentInfo_UniqueTraits.OnPostTemplatesCreated adds to the abilities of a DISABLED trait (together with the removal of their
//           effects): the ability can never be used, so a soldier who still carries the trait is not affected by it.
//---------------------------------------------------------------------------------------
class X2Condition_UT_TraitDisabled extends X2Condition;

event name CallMeetsCondition(XComGameState_BaseObject kTarget)
{
	return 'AA_AbilityUnavailable';
}
