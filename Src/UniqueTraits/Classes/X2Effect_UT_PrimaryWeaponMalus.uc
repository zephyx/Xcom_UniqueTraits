//---------------------------------------------------------------------------------------
//  FILE:   X2Effect_UT_PrimaryWeaponMalus.uc
//  PURPOSE: Maniac explosive's malus: abilities fired with the holder's PRIMARY weapon deal DamageReductionPct% less BASE damage, never
//           below 1 (a 0 would also hide the damage preview, as it did for Baseball player). Like X2Effect_UT_WeakExplosives it only
//           touches the weapon's own damage: tick effects (poison, burning...) are left alone (UT_EffectHelpers.IsTickDamage).
//           A percentage of the weapon's BASE damage only, so it lives in the PRE-default hook (CHL #923): it runs
//           right after the base damage is computed (weapon damage and spread, +1 rolls, critical or graze, rupture) and BEFORE every flat bonus
//           (HeavyHitter, Psi adept...), which are therefore not reduced. Percentages of the total go to the post-default hook instead.
//---------------------------------------------------------------------------------------
class X2Effect_UT_PrimaryWeaponMalus extends X2Effect_Persistent;

var int DamageReductionPct;

function float GetPreDefaultAttackingDamageModifier_CH(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, float CurrentDamage, X2Effect_ApplyWeaponDamage WeaponDamageEffect, XComGameState NewGameState)
{
	if (CurrentDamage <= 1.0 || AbilityState == none || WeaponDamageEffect == none || class'UT_EffectHelpers'.static.IsTickDamage(AppliedData))
		return 0.0;

	if (!class'UT_EffectHelpers'.static.IsPrimaryWeaponAbility(AbilityState))
		return 0.0;

	return -FMax(0.0, FMin(CurrentDamage * DamageReductionPct / 100.0, CurrentDamage - 1.0));
}

defaultproperties
{
	DuplicateResponse = eDupe_Ignore
}
