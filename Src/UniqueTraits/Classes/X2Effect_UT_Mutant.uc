//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_Mutant.uc
//  PURPOSE: Mutant's damage percentage (Someone different, phase 3): the DIRECT damage of the holder's attacks is raised or lowered by the percentage
//           the mutation calls for (UnitValue UT_SD_DamagePct, written by UT_Trait_SomeoneDifferent.SyncStats together with the stat changes),
//           never below 1. Damage over time ticks (UT_EffectHelpers.IsTickDamage) are left alone. A percentage, so it lives in the POST-default hook
//           (CHL #923): it applies to the total once every flat bonus is in, whatever the order of the effects.
//---------------------------------------------------------------------------------------
class X2Effect_UT_Mutant extends X2Effect_Persistent;

function float GetPostDefaultAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, float CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, XComGameState NewGameState)
{
	local float Percent, Modifier;

	if (CurrentDamage <= 0.0 || AbilityState == none || WeaponDamageEffect == none || class'UT_EffectHelpers'.static.IsTickDamage(AppliedData))
		return 0.0;

	Percent = class'UT_TraitBase'.static.GetUnitFloat(Attacker, 'UT_SD_DamagePct');
	if (Percent == 0.0)
		return 0.0;

	Modifier = CurrentDamage * Percent / 100.0;
	if (Modifier < 0.0)
		Modifier = -FMax(0.0, FMin(-Modifier, CurrentDamage - 1.0));

	return Modifier;
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
