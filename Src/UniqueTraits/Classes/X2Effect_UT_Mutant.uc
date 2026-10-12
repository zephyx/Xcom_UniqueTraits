//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_Mutant.uc
//  PURPOSE: Mutant's damage percentage (Someone different, phase 3): the DIRECT damage of the holder's attacks is raised or lowered by the percentage
//           the mutation calls for (UnitValue UT_SD_DamagePct, written by UT_Trait_SomeoneDifferent.SyncStats together with the stat changes), rounded,
//           never below 1. Damage over time ticks (bIgnoreBaseDamage) are left alone.
//---------------------------------------------------------------------------------------
class X2Effect_UT_Mutant extends X2Effect_Persistent;

function int GetAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, const int CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, optional XComGameState NewGameState)
{
	local float Percent;
	local int Modifier;

	if (CurrentDamage <= 0 || AbilityState == none || WeaponDamageEffect == none || WeaponDamageEffect.bIgnoreBaseDamage)
		return 0;

	Percent = class'UT_TraitBase'.static.GetUnitFloat(Attacker, 'UT_SD_DamagePct');
	if (Percent == 0.0)
		return 0;

	Modifier = Round(CurrentDamage * Percent / 100.0);
	if (Modifier < 0)
		Modifier = -Min(-Modifier, CurrentDamage - 1);

	return Modifier;
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
