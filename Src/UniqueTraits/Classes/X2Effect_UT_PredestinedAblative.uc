//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_PredestinedAblative.uc
//  PURPOSE: Predestined's red symbol also gives ABLATIVE hit points (eStat_ShieldHP), for the mission: the amount is computed when the effect is applied (OnEffectAdded) from the red
//           perks the holder owns (UT_Trait_Predestined.GetAblativeAmount).
//---------------------------------------------------------------------------------------
class X2Effect_UT_PredestinedAblative extends X2Effect_PersistentStatChange;

simulated protected function OnEffectAdded(const out EffectAppliedData ApplyEffectParameters, XComGameState_BaseObject kNewTargetState, XComGameState NewGameState, XComGameState_Effect NewEffectState)
{
	local XComGameState_Unit Unit;
	local StatChange Change;
	local int Amount;

	Unit = XComGameState_Unit(kNewTargetState);
	NewEffectState.StatChanges.Length = 0;

	Amount = class'UT_Trait_Predestined'.static.GetAblativeAmount(Unit);
	if (Amount <= 0)
		return;

	Change.StatType = eStat_ShieldHP;
	Change.StatAmount = Amount;
	Change.ModOp = MODOP_Addition;
	NewEffectState.StatChanges.AddItem(Change);

	// Skip X2Effect_PersistentStatChange's own OnEffectAdded (it would overwrite StatChanges with the fixed list) and go straight to the one that applies them.
	super(X2Effect_ModifyStats).OnEffectAdded(ApplyEffectParameters, kNewTargetState, NewGameState, NewEffectState);
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
