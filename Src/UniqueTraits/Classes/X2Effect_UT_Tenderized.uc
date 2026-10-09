//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_Tenderized.uc
//  PURPOSE: Meat Tenderizer's debuffs ("Tenderized" replaces a stun, "Slightly Tenderized" a disorient): a stat change on the target.
//           The action point given back to the source is NOT here: the ability's cost is applied AFTER its effects (and may consume every
//           point), so it is granted by UT_Trait_MeatTenderizer.OnAbilityActivated_MeatTenderizer once the ability is over.
//           The two cannot stack: the full one removes the light one (here), and the light one is refused on a unit that already has the full
//           one (X2Condition_UnitEffects added by UT_Trait_MeatTenderizer).
//---------------------------------------------------------------------------------------
class X2Effect_UT_Tenderized extends X2Effect_PersistentStatChange;

var bool bSlight;                       // true = Slightly Tenderized
var name SlightEffectName;              // the light twin, removed when the full one is applied

simulated protected function OnEffectAdded(const out EffectAppliedData ApplyEffectParameters, XComGameState_BaseObject kNewTargetState, XComGameState NewGameState, XComGameState_Effect NewEffectState)
{
	local XComGameState_Unit TargetUnit;
	local XComGameState_Effect SlightEffect;

	super.OnEffectAdded(ApplyEffectParameters, kNewTargetState, NewGameState, NewEffectState);

	// Tenderized wins over Slightly Tenderized.
	TargetUnit = XComGameState_Unit(kNewTargetState);
	if (!bSlight && TargetUnit != none)
	{
		SlightEffect = TargetUnit.GetUnitAffectedByEffectState(SlightEffectName);
		if (SlightEffect != none)
			SlightEffect.RemoveEffect(NewGameState, NewGameState, true);
	}
}

defaultproperties
{
	DuplicateResponse = eDupe_Refresh
}
